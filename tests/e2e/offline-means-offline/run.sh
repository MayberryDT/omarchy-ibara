#!/usr/bin/env bash
# Usage: run.sh PLUGIN_DIR OUTPUT_DIR. Needs Quickshell, Node, Python 3 and Omarchy's shell Commons.
# Runs offscreen in an isolated home and runtime: the real Service.qml against the fictional daemon
# on this test's own socket, never a real ibarad, compositor or notification server. Two labs, one
# after the other, each with a fresh daemon: fixture.qml (console open, about 4 minutes) and
# closed.qml (nothing open, about 2.5 minutes). Writes OUTPUT_DIR/results.json, with each lab's log
# and the daemon's own record of every session and status read.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd "$1" && pwd)
mkdir -p "$2"; out=$(cd "$2" && pwd)
work=$(mktemp -d "$out/work.XXXXXX")
# Short: the daemon's socket path must fit in a Unix socket address.
runtime=$(mktemp -d /tmp/ibara-offline.XXXXXX)
daemon=""
stop_daemon() { if [[ -n $daemon ]]; then kill "$daemon" 2>/dev/null || true; wait "$daemon" 2>/dev/null || true; daemon=""; fi; }
trap 'stop_daemon; rm -rf "$runtime" "$work"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cp -r "$plugin" "$work/plugin"; rm -rf "$work/plugin/.git"
# The service's two layer-shell windows (request pop-ups, Hand Back pills) need a compositor and
# are not what this checks. In this copy they are empty items, so the run never touches a desktop.
for name in RequestPopups HandBackPills; do printf 'import QtQuick\nItem { property var service: null }\n' > "$work/plugin/$name.qml"; done
cp "$here/fixture.qml" "$here/closed.qml" "$work/"
# Ten fictional screens, one color each, for the daemon to send as pictures.
python3 -I - "$work/plugin/fixtures/wall-previews" <<'PY'
import pathlib,sys
d=pathlib.Path(sys.argv[1]); d.mkdir(parents=True, exist_ok=True)
for i in range(10):
    (d/f"fictional-{i:02d}.ppm").write_bytes(b"P6\n320 180\n255\n"+bytes([40+i*20,90,200-i*15])*(320*180))
PY
# lab NAME CONTROL: a fresh home, daemon and runtime folder, then NAME.qml until it quits.
lab() {
  local name=$1 home=$work/home-$1 run=$runtime/$1
  mkdir -p "$home/.local/state/omarchy" "$home/.config" "$run/ibara"; chmod 700 "$run/ibara"
  printf '%s\n' "$2" > "$run/ibara/control.json"
  # The daemon's own runtime folder has no ibarad in it, so nothing it forwards reaches a real one.
  HOME=$home XDG_RUNTIME_DIR=$work/no-ibarad IBARA_DEV_WALL_COUNT=10 \
    node "$work/plugin/tests/dev-fixture-daemon.mjs" "$run/ibara/ibarad.sock" > "$out/$name-daemon.log" 2>&1 &
  daemon=$!
  for _ in $(seq 50); do [[ -S $run/ibara/ibarad.sock ]] && break; sleep 0.2; done
  [[ -S $run/ibara/ibarad.sock ]] || { echo "The fictional daemon did not start; see $out/$name-daemon.log" >&2; exit 1; }
  (
    cd "$work"
    unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
    export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$run
    export QT_QPA_PLATFORM=offscreen DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/ibara-offline-bus
    export IBARA_E2E_CONTROL=$run/ibara/control.json
    timeout 330 quickshell --no-color --path "$work/$name.qml" > "$out/$name.log" 2>&1 || echo "quickshell exited $?" >> "$out/$name.log"
  )
  stop_daemon
  cp "$run/ibara/status.jsonl" "$out/$name-status.jsonl" 2>/dev/null || : > "$out/$name-status.jsonl"
  cp "$run/ibara/requests.jsonl" "$out/$name-pictures.jsonl" 2>/dev/null || : > "$out/$name-pictures.jsonl"
}
lab fixture '{"deny":["fictional-06"],"picture_silent":["fictional-02"],"version":"0.3.6-1","versions":{"fictional-04":"0.3.4-1"},"build":"1a2b3c4","builds":{"fictional-01":"9f8e7d6"}}'
lab closed '{"offline":["fictional-08"]}'
OUT=$out PLUGIN=$plugin python3 -I - <<'PY'
import hashlib,json,os,pathlib,re,sys
out=pathlib.Path(os.environ["OUT"]); plugin=pathlib.Path(os.environ["PLUGIN"])
checks={}; marks={}; timeline={}; errors=[]
def reads(status,computer,start,end,answered,command=None):
    return [r for r in status if r["computer"]==computer and start<=r["at_ms"]<=end and r["answered"]==answered and (command is None or r["command"]==command)]
for name in ("fixture","closed"):
    log=(out/f"{name}.log").read_text(errors="replace")
    found=re.findall(r"OFFLINE_E2E (\{[^\n]*\})",log)
    lab=json.loads(found[0]) if len(found)==1 else {"checks":{f"{name}_produced_one_result":False},"marks":{}}
    checks.update(lab["checks"]); marks[name]=m=lab["marks"]
    timeline[name]=[json.loads(x) for x in re.findall(r"OFFLINE_E2E_EVENT (\{[^\n]*\})",log)]
    # Without the shell, a bare `Color` in Tokens.qml resolves to QtQuick's own Color, so its theme
    # colors fail once while the configuration loads. Any error once it has loaded counts.
    loaded=log.split("Configuration Loaded",1)
    errors+=[f"{name}: {l}" for l in (loaded[1] if len(loaded)==2 else log).splitlines() if re.search(r"TypeError|ReferenceError|is not a function|quickshell exited",l)]
    errors+=[f"{name}: {l}" for l in loaded[0].splitlines() if "Failed to load configuration" in l]
    # From the daemon's side, independent of the console: which reads it answered or failed.
    status=[json.loads(l) for l in (out/f"{name}-status.jsonl").read_text().splitlines() if l.strip()]
    if name=="fixture" and m.get("trouble_ms"):
        start=m["trouble_ms"]
        checks["brief_outage_had_failed_reads"]=len(reads(status,"fictional-03",start,m["brief_outage_end_ms"]+1000,False))>=2
        off=m.get("long_offline_ms"); failed=reads(status,"fictional-07",start,off or 0,False)
        checks["daemon_failed_3_reads_over_30s_before_offline"]=bool(off) and len(failed)>=3 and off-failed[0]["at_ms"]>=30000
        checks["late_computers_status_answered"]=all(len(reads(status,c,start+45000,start+95000,True))>=2 for c in ("fictional-00","fictional-01"))
    if name=="closed" and m.get("start_ms"):
        checks["closed_brief_outage_had_failed_read"]=len(reads(status,"fictional-09",m.get("brief_start_ms",0),m.get("brief_end_ms",0)+1000,False))>=1
        off=m.get("start_offline_ms"); failed=reads(status,"fictional-08",0,off or 0,False,"operator-session")
        checks["daemon_failed_3_session_reads_over_30s_before_offline"]=bool(off) and len(failed)>=3 and off-failed[0]["at_ms"]>=30000
checks["no_qml_errors"]=not errors
sha=lambda name: hashlib.sha256((plugin/name).read_bytes()).hexdigest()
report={"passed":all(v is True for v in checks.values()),"failed":sorted(k for k,v in checks.items() if v is not True),
  "checks":checks,"marks":marks,"service_sha256":sha("Service.qml"),"status_model_sha256":sha("StatusModel.js"),
  "qml_errors":errors[:20],"timeline":timeline}
(out/"results.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps({"passed":report["passed"],"failed":report["failed"],"checks":len(checks)}))
sys.exit(0 if report["passed"] else 1)
PY
