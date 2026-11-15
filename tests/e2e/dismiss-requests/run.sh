#!/usr/bin/env bash
# Usage: run.sh PLUGIN_DIR OUTPUT_DIR. Needs Quickshell, Python 3 and Omarchy's shell (Commons, Ui).
# The real Service.qml, QuickPanel.qml and IPC handler, offscreen in an isolated home and runtime
# folder, with fictional requests and no ibarad. In this copy the windows that need a compositor
# (request pop-ups, Hand Back pills, the quick panel's own layer-shell window) are plain items, so
# the run never touches a desktop. Writes OUTPUT_DIR/results.json, the lab's log and the
# dismissal file it left.
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
plugin=$(cd "$1" && pwd)
mkdir -p "$2"; out=$(cd "$2" && pwd)
work=$(mktemp -d "$out/work.XXXXXX")
runtime=$(mktemp -d /tmp/ibara-dismiss.XXXXXX)
trap 'rm -rf "$runtime" "$work"' EXIT
ln -s /usr/share/omarchy/shell/Commons "$work/Commons"
cp -r /usr/share/omarchy/shell/Ui "$work/Ui"
cat > "$work/Ui/KeyboardPanel.qml" <<'QML'
import QtQuick
// Stands in for Omarchy's KeyboardPanel, a layer-shell window: its content as a plain item.
Item {
  property Item anchorItem: null
  property QtObject bar: null
  property var owner: null
  property bool open: false
  property Item focusTarget: null
  property int padding: 0
  property int margin: 0
  property int contentWidth: 340
  property int contentHeight: 200
  function fittedContentWidth(width) { return width }
  function fittedContentHeight(height, most) { return Math.min(height, most) }
  width: contentWidth
  height: contentHeight
}
QML
cp -r "$plugin" "$work/plugin"; rm -rf "$work/plugin/.git"
for name in RequestPopups HandBackPills; do printf 'import QtQuick\nItem { property var service: null }\n' > "$work/plugin/$name.qml"; done
cp "$here/lab.qml" "$work/"
home=$work/home; mkdir -p "$home/.local/state/omarchy" "$home/.config"
(
  cd "$work"
  unset WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE
  export HOME=$home XDG_CONFIG_HOME=$home/.config XDG_STATE_HOME=$home/.local/state XDG_RUNTIME_DIR=$runtime
  export QT_QPA_PLATFORM=offscreen DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent/ibara-dismiss-bus
  export IBARA_LAB_PATH=$work/lab.qml
  timeout 120 quickshell --no-color --path "$work/lab.qml" > "$out/lab.log" 2>&1 || echo "quickshell exited $?" >> "$out/lab.log"
)
cp "$home/.local/state/omarchy/ibara-request-dismissals.json" "$out/dismissals.json" 2>/dev/null || : > "$out/dismissals.json"
OUT=$out PLUGIN=$plugin python3 -I - <<'PY'
import hashlib,json,os,pathlib,re,sys
out=pathlib.Path(os.environ["OUT"]); plugin=pathlib.Path(os.environ["PLUGIN"])
log=(out/"lab.log").read_text(errors="replace")
found=re.findall(r"DISMISS_E2E (\{[^\n]*\})",log)
lab=json.loads(found[0]) if len(found)==1 else {"checks":{"lab_produced_one_result":False}}
checks=dict(lab["checks"])
# Without the shell, a bare `Color` resolves to Qt's own color helper, not Omarchy's theme
# (as in the offline lab), so the quick panel's cards and buttons fail to read their theme
# colors. An error on a source line that reads a bare `Color.` is that; any other counts.
def theme_only(line):
    m=re.search(r"@plugin/([A-Za-z]+\.qml)\[(\d+):",line)
    if not m or "TypeError: Cannot read property" not in line: return False
    source=(plugin/m.group(1)).read_text().splitlines()
    n=int(m.group(2))
    return 0<n<=len(source) and re.search(r"(?<![\w.])Color\.",source[n-1]) is not None
loaded=log.split("Configuration Loaded",1)
errors=[l for l in (loaded[1] if len(loaded)==2 else log).splitlines() if re.search(r"TypeError|ReferenceError|is not a function|quickshell exited",l) and not theme_only(l)]
checks["no_qml_errors"]=not errors
saved=(out/"dismissals.json").read_bytes()
checks["no_request_text_on_disk"]=b"MARKER" not in saved
sha=lambda name: hashlib.sha256((plugin/name).read_bytes()).hexdigest()
report={"passed":all(v is True for v in checks.values()),"failed":sorted(k for k,v in checks.items() if v is not True),"checks":checks,
  "phase":lab.get("phase"),"ipc":lab.get("ipc"),"qml_errors":errors[:20],
  "service_sha256":sha("Service.qml"),"quick_panel_sha256":sha("QuickPanel.qml"),"status_model_sha256":sha("StatusModel.js")}
(out/"results.json").write_text(json.dumps(report,indent=2,sort_keys=True)+"\n")
print(json.dumps({"passed":report["passed"],"failed":report["failed"],"checks":len(checks)}))
sys.exit(0 if report["passed"] else 1)
PY
