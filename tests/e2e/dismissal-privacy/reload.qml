import QtQuick
import Quickshell
import "plugin" as P
ShellRoot {
  id: lab
  property int tick: 0
  function login(ref, tag) {
    return { ref: ref, kind: "login", computer_id: "computer_fixture", label: "Fictional test", at: Date.now(), unreachable: true,
      login: { agent: "Fictional agent", goal: "Fictional sign-up", sites: [{ site: "example.invalid", state: "asking" }],
        assistance: { version: 1, revision: 1, notification: "attention", signup: { state: "proposed", proposal: { site: "MARKERSITE" + tag + ".invalid", identity: "MARKERIDENTITY" + tag, credential_store: "MARKERSTORE" + tag, summary: "MARKERSUMMARY" + tag } } } } }
  }
  function byRef(ref) { return svc.logins.filter(function(l) { return l.ref === ref })[0] }
  P.Service { id: svc; onServiceStoppedChanged: if (serviceStopped) serviceStopped = false }
  Timer {
    interval: 1000; repeat: true; running: true
    onTriggered: {
      lab.tick++
      if (lab.tick === 2) {
        svc.dndRead = true; svc.persistedDnd = false; svc.serviceStopped = false
        svc.attention = [lab.login("att_legacy_signup", "B"), lab.login("att_expire", "C"), lab.login("att_dismiss", "D")]
      } else if (lab.tick === 4) {
        console.log("DISMISSAL_RELOAD " + JSON.stringify({
          reload_keeps_dismissal: svc.requestPopupHidden(lab.byRef("att_legacy_signup")) && svc.requestPopupHidden(lab.byRef("att_dismiss")) && !svc.requestNeedsAlert(lab.byRef("att_dismiss")),
          reload_keeps_popup_only_expiry: svc.requestPopupHidden(lab.byRef("att_expire")) && svc.requestNeedsAlert(lab.byRef("att_expire")),
          reload_opens_no_popup: svc.popupRequests.length === 0 }))
        Qt.quit()
      }
    }
  }
}
