import QtQuick
import Quickshell
import "./plugin" as Plugin
ShellRoot {
 Plugin.Service { id: service }
 Timer { interval: 1200; running: true; onTriggered: {
   service.ibaraMissing = "package";
   console.info("BOOTSTRAP_COMMAND", service.ibaraInstallCommand);
   if (!service.installIbara()) console.error("INSTALL_ACTION_FAILED");
 } }
 Timer { interval: 6000; running: true; onTriggered: {
   service.ibaraMissing = "setup";
   if (!service.installIbara()) console.error("SETUP_ACTION_FAILED");
 } }
 Timer { interval: 8500; running: true; onTriggered: Qt.quit() }
}
