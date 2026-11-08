import QtQuick
import Quickshell
import "plugin" as P
// Loads an older dismissal file, then exits so run.sh can read what reached the disk.
ShellRoot {
  P.Service { id: svc; onServiceStoppedChanged: if (serviceStopped) serviceStopped = false }
  Timer { interval: 3000; running: true; onTriggered: {
    console.log("DISMISSAL_MIGRATE " + JSON.stringify({ migrate_load_completes: svc.requestDismissalsReady === true }))
    Qt.quit()
  } }
}
