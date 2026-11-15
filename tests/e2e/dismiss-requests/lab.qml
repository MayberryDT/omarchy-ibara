import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as P
import "plugin/StatusModel.js" as StatusModel
// The real Service.qml and QuickPanel.qml with fictional requests, offscreen. The IPC calls go
// through `quickshell ipc` to this very instance. Prints one DISMISS_E2E line, then quits.
ShellRoot {
  id: lab
  property int tick: 0
  property var results: ({})
  property var seen: ({})
  property string phase: "start"
  function check(name, value) { var next = Object.assign({}, results); next[name] = value === true; results = next }
  function ago(minutes) { return new Date(Date.now() - minutes * 60000).toISOString() }
  // Raw fleet-attention items, read as the console reads them.
  function raw() {
    return StatusModel.attentionView({ items: [
      { computer_id: "computer_a", label: "Fictional A", ref: "att_approval_a", kind: "approval", summary: "MARKERAPPROVAL", at: ago(10) },
      { computer_id: "computer_b", label: "Fictional B", ref: "att_question_b", kind: "question", summary: "MARKERQUESTION", options: ["Yes", "No"], at: ago(9) },
      { computer_id: "computer_d", label: "Fictional D", ref: "att_future_d", kind: "future_kind", summary: "MARKERFUTURED", at: ago(6) },
      { computer_id: "computer_e", label: "Fictional E", ref: "att_future_e", kind: "future_kind", summary: "MARKERFUTUREE", at: ago(5) }
    ] })
  }
  function login(ref, minutes, tag) {
    return { ref: ref, kind: "login", computer_id: "computer_c", label: "Fictional C", at: Date.now() - minutes * 60000, unreachable: true,
      login: { agent: "fictional-agent", goal: "Fictional sign-up", sites: [{ site: "example.invalid", state: "asking" }],
        assistance: { version: 1, revision: 1, notification: "attention",
          signup: { state: "proposed", proposal: { site: "MARKERSITE" + tag + ".invalid", identity: "MARKERIDENTITY" + tag, credential_store: "MARKERSTORE" + tag, summary: "MARKERSUMMARY" + tag } } } } }
  }
  function requests(extra) { return raw().concat([login("att_login_c", 8, "C"), login("att_login_timed_out", 7, "T")], extra || []) }
  function find(item, label) {
    if (!item) return null
    if (item.label === label && typeof item.clicked === "function") return item
    var kids = item.children || []
    for (var i = 0; i < kids.length; i++) { var hit = find(kids[i], label); if (hit) return hit }
    return null
  }
  function dismissButton() { return find(quick, "Dismiss requests") }
  function shown(button) { if (!button) return false; for (var p = button; p; p = p.parent) if (!p.visible) return false; return true }
  // One IPC call to this instance; its parsed answer goes to `seen[name]`.
  function ipc(name, call) {
    var next = Object.assign({}, seen); next[name] = undefined; seen = next
    ipcRun.name = name
    ipcRun.command = ["quickshell", "ipc", "--path", Quickshell.env("IBARA_LAB_PATH"), "call", "io.zet.ibara", call]
    ipcRun.running = true
  }
  Process {
    id: ipcRun
    property string name: ""
    stdout: StdioCollector {
      onStreamFinished: {
        var value
        try { value = JSON.parse(text) } catch (e) { value = { unreadable: String(text).slice(0, 400) } }
        var next = Object.assign({}, lab.seen); next[ipcRun.name] = value; lab.seen = next
        console.log("DISMISS_E2E_IPC " + JSON.stringify({ name: ipcRun.name, answer: value }))
      }
    }
    stderr: StdioCollector { onStreamFinished: if (text.trim()) console.log("DISMISS_E2E_IPC_ERROR " + JSON.stringify({ name: ipcRun.name, error: text.slice(0, 400) })) }
  }
  FileView { id: dismissals; path: Quickshell.env("HOME") + "/.local/state/omarchy/ibara-request-dismissals.json"; blockLoading: true; watchChanges: false; printErrors: false }
  P.Service { id: svc; onServiceStoppedChanged: if (serviceStopped) serviceStopped = false }
  P.QuickPanel { id: quick; service: svc }
  Timer {
    interval: 1000; repeat: true; running: true
    onTriggered: {
      lab.tick++
      var t = lab.tick
      if (t === 2) {
        svc.dndRead = true; svc.persistedDnd = false; svc.serviceStopped = false
        svc.attention = lab.requests()
      }
      if (t === 3) svc.expireLoginPopup("att_login_timed_out")
      if (t === 4) {
        lab.check("all_requests_listed", quick.asks.length === 6)
        lab.check("timed_out_sign_in_still_listed", quick.asks.some(function(a) { return a.ref === "att_login_timed_out" }))
        lab.check("dismiss_shown_while_requests_wait", lab.shown(lab.dismissButton()))
        lab.ipc("status_before", "status")
        lab.phase = "status_before"
      }
      if (lab.phase === "status_before" && lab.seen.status_before !== undefined) {
        var before = lab.seen.status_before
        lab.check("status_counts_visible_requests", before.visible_requests === 6)
        lab.check("status_says_dismissals_ready", before.dismissals_ready === true)
        var button = lab.dismissButton()
        if (button) button.clicked()
        lab.phase = "clicked"; lab.seen.clicked_at = t
      }
      if (lab.phase === "clicked" && t >= lab.seen.clicked_at + 1) {
        lab.check("dismiss_empties_quick_panel", quick.asks.length === 0)
        lab.check("dismiss_hidden_when_nothing_waits", !lab.shown(lab.dismissButton()))
        lab.check("dismissed_stay_answerable_in_console", svc.approvals.length === 1 && svc.questions.length === 1 && svc.logins.length === 2)
        lab.ipc("status_after", "status")
        lab.phase = "status_after"
      }
      if (lab.phase === "status_after" && lab.seen.status_after !== undefined) {
        lab.check("status_counts_none_after_dismiss", lab.seen.status_after.visible_requests === 0)
        svc.attention = lab.requests(StatusModel.attentionView({ items: [{ computer_id: "computer_a", label: "Fictional A", ref: "att_approval_new", kind: "approval", summary: "MARKERNEW", at: lab.ago(1) }] }))
        lab.phase = "arrived"; lab.seen.arrived_at = t
      }
      if (lab.phase === "arrived" && t >= lab.seen.arrived_at + 1) {
        lab.check("new_request_after_dismiss_shows", quick.asks.length === 1 && quick.asks[0].ref === "att_approval_new" && lab.shown(lab.dismissButton()))
        lab.ipc("ipc_dismiss", "dismissRequests")
        lab.phase = "ipc_dismiss"
      }
      if (lab.phase === "ipc_dismiss" && lab.seen.ipc_dismiss !== undefined) {
        lab.check("ipc_dismiss_says_none_remain", lab.seen.ipc_dismiss.remaining === 0)
        lab.check("ipc_dismiss_empties_quick_panel", quick.asks.length === 0)
        lab.phase = "file"; lab.seen.file_at = t
      }
      // The service writes the dismissal file once per request, each write atomic; read it once
      // the last has had time to land.
      if (lab.phase === "file" && t >= lab.seen.file_at + 2) {
        dismissals.reload()
        var file = String(dismissals.text() || ""), saved = {}
        try { saved = JSON.parse(file) } catch (e) {}
        lab.check("dismissal_file_has_no_request_text", file.length > 0 && file.indexOf("MARKER") === -1)
        lab.check("newer_ibara_cards_dismissed_by_their_own_requests", !!saved["att_future_d"] && !!saved["att_future_e"] && !saved["undefined"])
        lab.check("every_request_dismissed_by_its_identity", ["att_approval_a", "att_question_b", "att_login_c", "att_login_timed_out", "att_approval_new"].every(function(r) { return !!saved[r] && !saved[r].popupOnly }))
        lab.phase = "done"
      }
      if (lab.phase === "done" || t === 40) {
        console.log("DISMISS_E2E " + JSON.stringify({ checks: lab.results, phase: lab.phase, ipc: lab.seen }))
        Qt.quit()
      }
    }
  }
}
