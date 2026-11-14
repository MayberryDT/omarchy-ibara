import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as P
// The real Service.qml with nothing open, as under the bar alone, against the fictional daemon.
//   07 answers nothing from 10 s to 80 s, long enough to go Offline, then comes back
//   08 answers nothing from the start until 95 s (its first session read fails)
//   09 answers nothing from 50 s to 80 s, around its once-a-minute status read
// Prints one OFFLINE_E2E line of checks, then quits.
ShellRoot {
  id: lab
  readonly property var ids: ["fictional-07", "fictional-08", "fictional-09"]
  readonly property double started: Date.now()
  property int tick: 0
  property var results: ({})
  property var marks: ({})
  property var flags: ({})
  property var shown: ({})
  property var controlState: null
  function check(name, value) { var next = Object.assign({}, results); next[name] = value === true; results = next }
  function mark(name, value) { if (marks[name] !== undefined) return; var next = Object.assign({}, marks); next[name] = value; marks = next }
  function flag(name, value) { if (!value) return; var next = Object.assign({}, flags); next[name] = true; flags = next }
  function at() { return Math.round((Date.now() - started) / 100) / 10 }
  function s(id) { return svc.sessions[id] || null }
  function state(id) { return tokens.stateOf(s(id)) }
  function offline(id) { return !!s(id) && s(id).connection === "offline" }
  function hasProblem(id) { return !!svc.problemStarts[id] || svc.problems.some(function(p) { return p.computer_id === id }) }
  function setControl(change) {
    controlState = Object.assign({}, controlState || JSON.parse(controlFile.text() || "{}"), change)
    controlFile.setText(JSON.stringify(controlState))
    console.log("OFFLINE_E2E_EVENT " + JSON.stringify({ t: at(), control: change }))
  }
  function record() {
    var next = Object.assign({}, shown)
    ids.forEach(function(id) {
      var x = s(id)
      if (!x) return
      var row = { connection: x.connection, state: state(id), picture: !!x.frame, note: String(x.frame_error || ""), unanswered: svc.unanswered && svc.unanswered[id] ? svc.unanswered[id].count : 0 }
      var key = JSON.stringify(row)
      if (next[id] === key) return
      next[id] = key
      console.log("OFFLINE_E2E_EVENT " + JSON.stringify(Object.assign({ t: at(), computer: id }, row)))
    })
    shown = next
  }
  P.Service { id: svc }
  P.Tokens { id: tokens }
  FileView { id: controlFile; path: Quickshell.env("IBARA_E2E_CONTROL"); blockLoading: true; watchChanges: false }
  Timer {
    interval: 1000; repeat: true; running: true
    onTriggered: {
      lab.tick++
      var t = lab.tick, now = Date.now()
      lab.record()
      if (t === 1) lab.mark("start_ms", now)
      if (t === 10) lab.setControl({ offline: ["fictional-08", "fictional-07"] })
      if (t === 50) { lab.mark("brief_start_ms", now); lab.setControl({ offline: ["fictional-08", "fictional-07", "fictional-09"] }) }
      if (t === 80) { lab.mark("brief_end_ms", now); lab.setControl({ offline: ["fictional-08"] }) }
      // 07: back from Offline, it reads as it is, not Needs Attention.
      if (lab.offline("fictional-07")) lab.mark("long_offline_ms", now)
      if (lab.marks.long_offline_ms && t > 80 && lab.s("fictional-07").connection === "ready") lab.mark("long_back_ms", now)
      if (lab.marks.long_back_ms && now - lab.marks.long_back_ms >= 1000) lab.flag("long_back_attention", lab.state("fictional-07") !== "ready" || lab.hasProblem("fictional-07"))
      if (t === 95) { lab.mark("start_outage_end_ms", now); lab.setControl({ offline: [] }) }
      // 08: Connecting, never Offline, until it has gone unanswered long enough; then Offline.
      if (lab.offline("fictional-08")) lab.mark("start_offline_ms", now)
      if (t === 10 || t === 25) lab.flag("start_connecting_" + t, lab.state("fictional-08") === "connecting")
      if (lab.marks.start_offline_ms && t > 95 && lab.s("fictional-08").connection === "ready") lab.mark("start_back_ms", now)
      // 09: a brief outage with nothing open is never Offline and never a problem.
      if (t >= 50) { lab.flag("brief_offline", lab.offline("fictional-09")); lab.flag("brief_problem", lab.hasProblem("fictional-09")) }
      if (t === 150) {
        lab.check("closed_long_outage_goes_offline_and_back", !!lab.marks.long_offline_ms && !!lab.marks.long_back_ms)
        lab.check("closed_back_from_offline_reads_ready", !!lab.marks.long_back_ms && !lab.flags.long_back_attention)
        lab.check("closed_brief_outage_never_offline", !lab.flags.brief_offline)
        lab.check("closed_brief_outage_never_a_problem", !lab.flags.brief_problem)
        lab.check("closed_brief_outage_recovers", lab.s("fictional-09").connection === "ready" && lab.state("fictional-09") === "ready")
        lab.check("start_unanswered_shows_connecting", !!lab.flags.start_connecting_10 && !!lab.flags.start_connecting_25)
        lab.check("start_unanswered_goes_offline", !!lab.marks.start_offline_ms)
        lab.check("start_unanswered_connects_once_answered", !!lab.marks.start_back_ms && lab.state("fictional-08") === "ready")
        console.log("OFFLINE_E2E " + JSON.stringify({ checks: lab.results, marks: lab.marks, flags: lab.flags }))
        Qt.quit()
      }
    }
  }
}
