# Offline means not answering — 14 November 2026

A fleet computer kept showing Offline, under Needs attention, with "<name> isn't answering", while it was up and only slow for a few seconds at a time. Two things caused it:

- A picture that took longer than 20 s, or whose route timed out, marked the whole computer Offline (`refusePreview`), as one failed status read did too.
- While the console was open, an Offline computer's status was never read again (`pollVisibleStatus` skipped it), so only a later picture could bring it back, and its pictures were backing off to 60 s.

Now only status reads decide Offline: three in a row unanswered, the first at least 30 s before (`Service.offlineAfterReads`, `offlineAfterMs`). A status read gives up after 10 s on the computer's route (core `CALL_TIMEOUT`) or 15 s in ibarad (`COMMAND_TIMEOUT`), and an unanswered one is retried 5 s, 10 s, 20 s, then 40 s and 60 s later. A computer slow for a few seconds fails one read, sometimes two; one whose ibara restarts fails reads at once for a few seconds, so the 30 s floor keeps it from showing Offline. A computer that really stops answering is Offline after 35–60 s, and the bar turns red a minute after that, as before. One answered status, or one picture, brings it back at once, and an Offline computer's status is still read on its retry while the console is open.

A late picture keeps the last one with "Busy · picture is late" under the state, and the computer keeps its state, group and color. Its pictures back off from 3 s to 60 s, and computers whose pictures are late share one of the four picture lanes, as Offline ones did. Denials, revocations and identity changes still clear the picture at once.

Each computer's card also says when it runs another ibara version or build than most of the fleet. The core reports `version` in `operator-status`; a build identifier is read from an optional `build` field beside it, which current cores do not send yet. Without it, versions alone are compared and no build shows.

## Repeat

On a computer with Quickshell, Node, Python 3 and Omarchy's shell (for `qs.Commons` and `qs.Ui`):

    bash tests/e2e/offline-means-offline/run.sh . OUTPUT_DIR

It runs offscreen in an isolated home and runtime folder, against the fictional daemon on its own socket, for about four minutes, and writes `OUTPUT_DIR/results.json` with each check, a timeline of what each computer showed, and the daemon's own record of every status read (`status.jsonl`). It never reaches a real ibarad, compositor or notification server; in its copy of the plugin the request pop-ups and Hand Back pills, the two windows that need a compositor, are empty items. The failure cases were written first: [FAILURE-CASES.md](../../tests/e2e/offline-means-offline/FAILURE-CASES.md). The drift rule alone is `node --test tests/fleet-build.test.mjs`.

| Receipt | Source | Result |
| --- | --- | --- |
| [results-before.json](results-before.json) | Checks only, commit `91f89e0` (public `main` 162b055 plus the checks) | 25 of 41 fail: every late-picture, outage and drift case; the 15 guards and preconditions and the error check pass |
| [results-fixed.json](results-fixed.json) | The fix, `Service.qml` SHA-256 in the file | All 41 pass |

Both ran on one Omarchy computer (Omarchy 4.5.0rc2, Quickshell 0.3.2, Qt 6.12). In the fixed run the long outage went Offline 50 s after it began, after four unanswered reads (the third came only 18 s after the first), raised "FICTIONAL 08 isn't answering" 61 s later, and came back on the first answered read, 25 s after the outage ended.

Limits: fictional computers, one machine, offscreen. The daemon's failures are instant or 10 s; a real route's timing varies. No live desktop, real fleet computer or real build field was used. Without a theme, a bare `Color` in `Tokens.qml` resolves to QtQuick's own in this harness, so colours fail once while the configuration loads; the run counts errors after that.
