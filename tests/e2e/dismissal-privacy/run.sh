#!/usr/bin/env bash
# Usage: run.sh PLUGIN_DIR OUTPUT_DIR. Run on an Omarchy desktop with a Wayland session.
# Real Service.qml and FileView, isolated home, fictional data. Writes OUTPUT_DIR/results.json.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd "$1" && pwd)
mkdir -p "$2"; out=$(cd "$2" && pwd)
: "${XDG_RUNTIME_DIR:?}" "${WAYLAND_DISPLAY:?}"
work=$(mktemp -d "$out/work.XXXXXX")
runtime=$(mktemp -d /tmp/ibara-dismiss.XXXXXX)
trap 'rm -rf "$runtime"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
ln -s /usr/share/omarchy/shell/Ui "$work/Ui"
cp -r "$plugin" "$work/plugin"; rm -rf "$work/plugin/.git"
cp "$here"/migrate.qml "$here"/fixture.qml "$here"/reload.qml "$work/"
ln -s "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" "$runtime/$WAYLAND_DISPLAY"
if [[ -d $XDG_RUNTIME_DIR/hypr ]]; then ln -s "$XDG_RUNTIME_DIR/hypr" "$runtime/hypr"; fi
home=$work/home; mkdir -p "$home/.local/state/omarchy" "$home/.config"
export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime
export QT_QPA_PLATFORM=wayland DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/ibara-fixture-bus
export WORK=$work OUT=$out
python3 -I - seed <<'PY'
import json,os,pathlib
def p(t): return {"state":"proposed","proposal":{"site":f"MARKERSITE{t}.invalid","identity":f"MARKERIDENTITY{t}","credential_store":f"MARKERSTORE{t}","summary":f"MARKERSUMMARY{t}"}}
legacy=json.dumps(p("A"),separators=(",",":"))
pathlib.Path(os.environ["WORK"],"legacy-signature.txt").write_text(legacy)
data={"att_legacy_signup":{"at":1,"signature":legacy,"popupOnly":False},"att_plain_request":{"at":2,"signature":"request","popupOnly":False},
 "att_already_converted":{"at":3,"signature":"signup:0123456789abcdef0123456789abcdef","popupOnly":False},"att_null":None,"att_number":{"at":4,"signature":7},"att_text":"not an entry"}
pathlib.Path(os.environ["HOME"],".local/state/omarchy/ibara-request-dismissals.json").write_text(json.dumps(data))
PY
cd "$work"
run() { timeout 60 quickshell --no-color --path "$work/$1.qml" > "$out/$1.log" 2>&1 || echo "quickshell $1 exited $?" >> "$out/$1.log"; }
run migrate; cp "$home/.local/state/omarchy/ibara-request-dismissals.json" "$work/after-migrate.json"
run fixture; cp "$home/.local/state/omarchy/ibara-request-dismissals.json" "$work/after-fixture.json"
run reload;  cp "$home/.local/state/omarchy/ibara-request-dismissals.json" "$work/after-reload.json"
python3 -I - check <<'PY'
import hashlib,json,os,pathlib,re,sys
work=pathlib.Path(os.environ["WORK"]); out=pathlib.Path(os.environ["OUT"]); home=pathlib.Path(os.environ["HOME"])
results={}
def tagged(log,tag):
    m=re.findall(tag+r" (\{[^\n]*\})",(out/log).read_text())
    return json.loads(m[0]) if len(m)==1 else {f"{tag.lower()}_produced_one_result":False}
results.update(tagged("migrate.log","DISMISSAL_MIGRATE")); results.update(tagged("fixture.log","DISMISSAL_FIXTURE")); results.update(tagged("reload.log","DISMISSAL_RELOAD"))
migrated=(work/"after-migrate.json").read_bytes()
legacy=(work/"legacy-signature.txt").read_text()
results["migration_removes_proposal_from_disk"]=b"MARKER" not in migrated
results["migration_hash_matches_independent_md5"]=json.loads(migrated).get("att_legacy_signup",{}).get("signature")=="signup:"+hashlib.md5(legacy.encode()).hexdigest()
results["disk_has_no_proposal_after_fixture"]=b"MARKER" not in (work/"after-fixture.json").read_bytes()
results["reload_does_not_rewrite_clean_file"]=(work/"after-fixture.json").read_bytes()==(work/"after-reload.json").read_bytes()
hits=[str(f.relative_to(home)) for f in home.rglob("*") if f.is_file() and not f.is_symlink() and b"MARKER" in f.read_bytes()]
results["no_proposal_text_anywhere_under_home"]=not hits
state=home/".local/state/omarchy"; results["no_leftover_temporary_files"]=sorted(p.name for p in state.iterdir() if "ibara-request-dismissals" in p.name)==["ibara-request-dismissals.json"]
errors=[l for n in ("migrate","fixture","reload") for l in (out/f"{n}.log").read_text().splitlines() if re.search(r"TypeError|ReferenceError|Qt\.md5|exited|is not a function",l)]
results["no_qml_errors"]=not errors
report={"passed":all(v is True for v in results.values()),"checks":results,"leak_paths":hits,"qml_errors":errors[:20]}
(out/"results.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps(report,sort_keys=True)); sys.exit(0 if report["passed"] else 1)
PY
