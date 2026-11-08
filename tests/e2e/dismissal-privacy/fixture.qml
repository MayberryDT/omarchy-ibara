import QtQuick
import Quickshell
import "plugin" as P
ShellRoot {
  id: lab
  property int tick: 0
  property var results: ({})
  function check(name, value) { var next = Object.assign({}, results); next[name] = !!value; results = next }
  function proposal(tag) { return { state: "proposed", proposal: { site: "MARKERSITE" + tag + ".invalid", identity: "MARKERIDENTITY" + tag, credential_store: "MARKERSTORE" + tag, summary: "MARKERSUMMARY" + tag } } }
  function login(ref, signup) {
    return { ref: ref, kind: "login", computer_id: "computer_fixture", label: "Fictional test", at: Date.now(), unreachable: true,
      login: { agent: "Fictional agent", goal: "Fictional sign-up", sites: [{ site: "example.invalid", state: "asking" }],
        assistance: { version: 1, revision: 1, notification: "attention", signup: signup } } }
  }
  function hashed(ref) { var e = svc.hiddenRequestPopups[ref]; return !!e && /^signup:[0-9a-f]{32}$/.test(String(e.signature)) }
  P.Service { id: svc; onServiceStoppedChanged: if (serviceStopped) serviceStopped = false }
  Timer {
    interval: 1000; repeat: true; running: true
    onTriggered: {
      lab.tick++
      if (lab.tick === 2) {
        svc.dndRead = true; svc.persistedDnd = false; svc.serviceStopped = false
        svc.attention = [lab.login("att_legacy_signup", lab.proposal("A"))]
      } else if (lab.tick === 4) {
        lab.check("malformed_entries_do_not_stop_loading", svc.requestDismissalsReady === true)
        lab.check("legacy_signature_converted", lab.hashed("att_legacy_signup"))
        lab.check("legacy_dismissal_stays_dismissed", svc.requestPopupHidden(svc.logins[0]) && svc.popupRequests.length === 0)
        lab.check("request_signature_unchanged", svc.hiddenRequestPopups["att_plain_request"].signature === "request")
        lab.check("converted_signature_not_rehashed", svc.hiddenRequestPopups["att_already_converted"].signature === "signup:0123456789abcdef0123456789abcdef")
        svc.attention = [lab.login("att_legacy_signup", lab.proposal("B"))]
      } else if (lab.tick === 5) {
        lab.check("changed_proposal_realerts", svc.popupRequests.length === 1 && svc.requestNeedsAlert(svc.logins[0]))
        svc.hideRequestPopup("att_legacy_signup")
        lab.check("explicit_dismissal_hashes_signature", lab.hashed("att_legacy_signup"))
        svc.attention = [lab.login("att_expire", lab.proposal("C"))]
      } else if (lab.tick === 7) {
        lab.check("new_proposal_popup_opens", svc.popupRequests.length === 1)
      } else if (lab.tick === 25) {
        var entry = svc.hiddenRequestPopups["att_expire"]
        lab.check("real_popup_expiry_recorded_popup_only", !!entry && entry.popupOnly === true)
        lab.check("real_popup_expiry_hashes_signature", lab.hashed("att_expire"))
        lab.check("expired_request_still_alerts", svc.popupRequests.length === 0 && svc.requestNeedsAlert(svc.logins[0]))
        svc.attention = [lab.login("att_dismiss", lab.proposal("D"))]
      } else if (lab.tick === 26) {
        svc.hideRequestPopup("att_dismiss")
        lab.check("explicit_dismissal_quiets_alert", !svc.requestNeedsAlert(svc.logins[0]) && svc.popupRequests.length === 0)
      } else if (lab.tick === 28) {
        console.log("DISMISSAL_FIXTURE " + JSON.stringify(lab.results))
        Qt.quit()
      }
    }
  }
}
