import QtQuick
import Quickshell
import Quickshell.Io
import "plugin" as P
import "plugin/StatusModel.js" as StatusModel
// The real Service.qml with the console open on ten fictional computers, against the fictional
// daemon run.sh starts on this test's own socket. control.json changes what each computer does:
//   00 pictures never answer from 15 s     01 pictures time out on their route from 15 s
//   02 pictures never answer from the start 03 status and pictures fail 15–27 s (it is the open computer)
//   04 healthy, on an older version         05 revoked at 40 s
//   06 denied from the start                07 status and pictures fail 15–150 s
//   08 fails two status reads from 15 s, then answers that it doesn't let you watch, then fails again
//   09 fails two status reads from 15 s, is removed and added again, still failing
// Each second it samples what the console would show; at the end it prints one OFFLINE_E2E line.
// Times are seconds since the lab started. Checks of what only the fix adds read as false before it.
ShellRoot {
  id: lab
  readonly property string late: "Busy · picture is late"
  readonly property var ids: ["fictional-00", "fictional-01", "fictional-02", "fictional-03", "fictional-04", "fictional-05", "fictional-06", "fictional-07", "fictional-08", "fictional-09"]
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
  function group(id) { return tokens.groupOf(state(id)) }
  function offline(id) { return !!s(id) && s(id).connection === "offline" }
  function problem(id) { return svc.problems.filter(function(p) { return p.computer_id === id })[0] || null }
  function hasProblem(id) { return !!svc.problemStarts[id] || !!problem(id) }
  function unanswered(id) { return svc.unanswered && svc.unanswered[id] ? Number(svc.unanswered[id].count) || 0 : 0 }
  function drift(id) { return typeof StatusModel.driftWords === "function" ? StatusModel.driftWords(s(id), svc.fleetBuild) : null }
  function polled(id) { return Number(svc.statusPolledAt[id] || 0) }
  function setControl(change) {
    controlState = Object.assign({}, controlState || JSON.parse(controlFile.text() || "{}"), change)
    controlFile.setText(JSON.stringify(controlState))
    console.log("OFFLINE_E2E_EVENT " + JSON.stringify({ t: at(), control: change }))
  }
  // Which computers answer nothing (control.json `offline`), one at a time.
  property var down: ({})
  function setDown(id, on) {
    var next = Object.assign({}, down)
    if (on) next[id] = true; else delete next[id]
    down = next
    setControl({ offline: Object.keys(next).sort() })
  }
  // Every change of what a computer shows, for the timeline in results.json.
  function record() {
    var next = Object.assign({}, shown)
    ids.forEach(function(id) {
      var x = s(id)
      if (!x) return
      var row = { connection: x.connection, state: state(id), group: group(id), picture: !!x.frame, note: String(x.frame_error || ""), unanswered: unanswered(id), problem: !!problem(id) }
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
      if (t >= 3 && svc.visibleComputerIds.length < lab.ids.length) {
        svc.setSurfaceOpen("console", true)
        svc.setVisibleComputerIds(lab.ids, false)
        svc.selectComputer("fictional-03")
      }
      if (t >= 4) lab.record()
      if (t === 12) {
        // Version drift, from the first status reads (control.json from run.sh).
        lab.check("version_kept_from_status", !!lab.s("fictional-00") && lab.s("fictional-00").version === "0.3.6-1" && lab.s("fictional-04").version === "0.3.4-1")
        lab.check("build_kept_from_status", !!lab.s("fictional-00") && lab.s("fictional-00").build === "1a2b3c4" && lab.s("fictional-01").build === "9f8e7d6")
        lab.check("fleet_build_is_the_most_common", !!svc.fleetBuild && svc.fleetBuild.version === "0.3.6-1" && svc.fleetBuild.build === "1a2b3c4")
        lab.check("different_version_flagged", lab.drift("fictional-04") === "Others run ibara 0.3.6-1")
        lab.check("different_build_flagged", lab.drift("fictional-01") === "Others run another build")
        lab.check("same_build_not_flagged", ["fictional-00", "fictional-02", "fictional-03", "fictional-05", "fictional-07"].every(function(id) { return lab.drift(id) === "" }))
        lab.check("no_version_not_flagged", lab.drift("fictional-06") === "" && !lab.s("fictional-06").version)
        lab.check("all_ready_before_trouble", ["fictional-00", "fictional-01", "fictional-03", "fictional-04", "fictional-05", "fictional-07"].every(function(id) { return lab.state(id) === "ready" && !!lab.s(id).frame }))
      }
      if (t === 15) {
        lab.mark("trouble_ms", now)
        lab.setControl({ picture_silent: ["fictional-02", "fictional-00"], hang: ["fictional-01"] })
        ;["fictional-03", "fictional-07", "fictional-08", "fictional-09"].forEach(function(id) { lab.setDown(id, true) })
      }
      if (t === 27) lab.setDown("fictional-03", false)
      if (t === 27) lab.mark("brief_outage_end_ms", now)
      if (t === 40) lab.setControl({ revoked: ["fictional-05"] })
      if (t === 150) { lab.mark("long_outage_end_ms", now); lab.setDown("fictional-07", false) }
      // An answer, even a refusal, starts its unanswered reads over (08), and a computer taken
      // out of the fleet takes its count with it (09): after it, one unanswered read is not
      // Offline, however many went unanswered before and however long ago the first was.
      if (t >= 15 && lab.unanswered("fictional-08") >= 1) lab.mark("08_first_unanswered_ms", now)
      if (!lab.marks["08_answers_ms"] && lab.unanswered("fictional-08") >= 2) {
        lab.mark("08_answers_ms", now)
        lab.setControl({ deny: ["fictional-06", "fictional-08"] })
        lab.setDown("fictional-08", false)
      }
      if (lab.marks["08_answers_ms"] && !lab.marks["08_denied_seen_ms"] && lab.s("fictional-08").observation === "denied") lab.mark("08_denied_seen_ms", now)
      if (lab.marks["08_denied_seen_ms"] && !lab.marks["08_down_again_ms"] && now - lab.marks["08_first_unanswered_ms"] >= 32000) {
        lab.mark("08_down_again_ms", now)
        lab.setDown("fictional-08", true)
      }
      if (lab.marks["08_down_again_ms"] && now - lab.marks["08_down_again_ms"] <= 25000) lab.flag("08_offline_after_one_more", lab.offline("fictional-08"))
      if (t >= 15 && lab.unanswered("fictional-09") >= 1) lab.mark("09_first_unanswered_ms", now)
      if (!lab.marks["09_removed_ms"] && lab.unanswered("fictional-09") >= 2 && !svc.mutating) {
        lab.mark("09_removed_ms", now)
        svc.removeComputer("fictional-09")
      }
      if (lab.marks["09_removed_ms"] && !lab.marks["09_gone_ms"] && !lab.s("fictional-09")) lab.mark("09_gone_ms", now)
      if (lab.marks["09_gone_ms"] && !lab.marks["09_back_ms"] && now - lab.marks["09_first_unanswered_ms"] >= 32000) {
        lab.mark("09_back_ms", now)
        lab.setControl({ restored: ["fictional-09"] })
        svc.loadComputers()
      }
      if (lab.marks["09_back_ms"] && !lab.marks["09_listed_again_ms"] && !!lab.s("fictional-09")) lab.mark("09_listed_again_ms", now)
      if (lab.marks["09_listed_again_ms"] && now - lab.marks["09_listed_again_ms"] <= 25000) lab.flag("09_offline_after_one_more", lab.offline("fictional-09"))
      if (t === 200) { lab.setDown("fictional-08", false); lab.setDown("fictional-09", false); lab.setControl({ deny: ["fictional-06"] }) }
      // Late pictures: never Offline, never Needs attention, never a problem (00 and 01 from 15 s, 02 from the start).
      ;["fictional-00", "fictional-01", "fictional-02"].forEach(function(id) {
        if (t < (id === "fictional-02" ? 4 : 15)) return
        lab.flag(id + "_offline", lab.offline(id))
        lab.flag(id + "_attention", lab.group(id) === "attention" || lab.state(id) === "attention")
        lab.flag(id + "_problem", lab.hasProblem(id))
      })
      if (t === 60) {
        lab.check("silent_picture_keeps_last_frame_with_note", !!lab.s("fictional-00").frame && lab.s("fictional-00").frame_error === lab.late)
        lab.check("timed_out_picture_keeps_last_frame_with_note", !!lab.s("fictional-01").frame && lab.s("fictional-01").frame_error === lab.late)
        lab.check("first_picture_late_keeps_state", !lab.s("fictional-02").frame && lab.s("fictional-02").frame_error === lab.late && lab.state("fictional-02") === "ready")
        lab.mark("polled_00_at_60", lab.polled("fictional-00")); lab.mark("polled_01_at_60", lab.polled("fictional-01"))
      }
      if (t === 110) {
        lab.check("late_picture_status_still_read", lab.polled("fictional-00") > lab.marks.polled_00_at_60 && lab.polled("fictional-01") > lab.marks.polled_01_at_60)
      }
      // A late computer is never asked for a picture again before its backoff ends, and its
      // backoff doubles. They take turns on one lane, so each gets a turn every 30–60 s.
      if (t >= 15) ["fictional-00", "fictional-01", "fictional-02"].forEach(function(id) {
        var b = svc.previewBackoff[id]
        if (!b) return
        lab.marks["max_backoff_" + id] = Math.max(lab.marks["max_backoff_" + id] || 0, b.delay)
        lab.flag(id + "_asked_during_backoff", svc.previewActive.some(function(r) { return !!r && r.computer_id === id && r.dispatched_ms < b.until }))
      })
      // At most one picture lane for the late computers, once each has been late.
      if (t >= 50 && t <= 130) {
        var slow = svc.previewActive.filter(function(r) { return !!r && ["fictional-00", "fictional-01", "fictional-02"].indexOf(r.computer_id) !== -1 }).length
        lab.marks.max_late_lanes = Math.max(lab.marks.max_late_lanes || 0, slow)
      }
      // The healthy computer keeps getting pictures.
      if (t >= 20) {
        var frame = lab.s("fictional-04") && lab.s("fictional-04").frame
        lab.marks.max_healthy_picture_age_s = Math.max(lab.marks.max_healthy_picture_age_s || 0, frame ? Math.round((now - frame.received_ms) / 100) / 10 : 999)
      }
      // Brief outage on the open computer: never Offline.
      if (t >= 15 && t <= 60) lab.flag("fictional-03_offline", lab.offline("fictional-03"))
      if (t === 60) lab.check("brief_outage_recovers", lab.s("fictional-03").connection === "ready" && lab.state("fictional-03") === "ready")
      // Long outage.
      if (t >= 15 && lab.offline("fictional-07")) {
        lab.mark("long_offline_ms", now)
        lab.mark("long_offline_unanswered", lab.unanswered("fictional-07"))
        lab.mark("polled_07_at_offline", lab.polled("fictional-07"))
      }
      var p7 = lab.problem("fictional-07")
      if (p7) { lab.mark("long_problem_ms", now); lab.mark("long_problem_heading", p7.heading) }
      if (t === 148) lab.check("offline_status_still_read", lab.marks.polled_07_at_offline !== undefined && lab.polled("fictional-07") > lab.marks.polled_07_at_offline)
      if (t > 150 && lab.s("fictional-07").connection === "ready") {
        lab.mark("long_back_ms", now)
        lab.mark("long_back_unanswered", lab.unanswered("fictional-07"))
      }
      if (lab.marks.long_back_ms && now - lab.marks.long_back_ms >= 2000) lab.mark("long_problem_after_back", !!lab.problem("fictional-07"))
      // Refusals fail closed.
      if (t >= 40) lab.flag("fictional-05_offline", lab.offline("fictional-05"))
      if (t === 60) lab.check("revoked_fails_closed", lab.s("fictional-05").connection === "unauthorized" && !lab.s("fictional-05").frame && lab.s("fictional-05").frame_error !== lab.late && lab.state("fictional-05") === "attention")
      if (t >= 4) lab.flag("fictional-06_offline", lab.offline("fictional-06"))
      if (t === 20) lab.check("denied_fails_closed", lab.s("fictional-06").connection === "unauthorized" && !lab.s("fictional-06").frame && lab.state("fictional-06") === "attention")
      if (t === 235) {
        ;["fictional-00", "fictional-01", "fictional-02"].forEach(function(id) {
          lab.check(id + "_late_never_offline", !lab.flags[id + "_offline"])
          lab.check(id + "_late_never_needs_attention", !lab.flags[id + "_attention"])
          lab.check(id + "_late_never_a_problem", !lab.flags[id + "_problem"])
        })
        lab.check("late_pictures_share_one_lane", lab.marks.max_late_lanes <= 1)
        lab.check("late_pictures_back_off", ["fictional-00", "fictional-01", "fictional-02"].every(function(id) { return !lab.flags[id + "_asked_during_backoff"] && lab.marks["max_backoff_" + id] >= 6000 }))
        lab.check("healthy_pictures_keep_coming", lab.marks.max_healthy_picture_age_s <= 15)
        lab.check("brief_outage_never_offline", !lab.flags["fictional-03_offline"])
        lab.check("long_outage_goes_offline", !!lab.marks.long_offline_ms)
        lab.check("long_outage_offline_after_30s", !!lab.marks.long_offline_ms && lab.marks.long_offline_ms - lab.marks.trouble_ms >= 30000)
        lab.check("long_outage_offline_after_3_unanswered", lab.marks.long_offline_unanswered >= 3)
        lab.check("long_outage_raises_isnt_answering", !!lab.marks.long_problem_ms && /isn't answering$/.test(String(lab.marks.long_problem_heading)))
        lab.check("long_outage_comes_back", !!lab.marks.long_back_ms && lab.marks.long_back_ms - lab.marks.long_outage_end_ms <= 75000)
        lab.check("back_clears_unanswered_and_problem", !!lab.marks.long_back_ms && lab.marks.long_back_unanswered === 0 && lab.marks.long_problem_after_back === false)
        lab.check("revoked_never_offline", !lab.flags["fictional-05_offline"])
        lab.check("denied_never_offline", !lab.flags["fictional-06_offline"])
        lab.check("answer_starts_unanswered_over", !!lab.marks["08_down_again_ms"] && !lab.flags["08_offline_after_one_more"])
        lab.check("removed_computer_starts_unanswered_over", !!lab.marks["09_listed_again_ms"] && !lab.flags["09_offline_after_one_more"])
        console.log("OFFLINE_E2E " + JSON.stringify({ checks: lab.results, marks: lab.marks, flags: lab.flags }))
        Qt.quit()
      }
    }
  }
}
