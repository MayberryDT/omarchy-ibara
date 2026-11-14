# Offline means not answering: failure cases

Written before the fix. Each is exercised by `run.sh` against the real `Service.qml`, `Tokens.qml`
and `StatusModel.js`, with the fictional daemon (`tests/dev-fixture-daemon.mjs`) on an isolated
socket, isolated home and offscreen Qt. Guards marked (guard) already hold before the fix and must
keep holding after it.

## A late picture is not Offline

1. A picture that never answers (the console's own 20 s limit) marks its computer Offline.
2. A picture whose route times out ("Selected operator transport timed out.") while the computer's
   status still answers marks it Offline.
3. A late picture moves its computer into Needs attention: its fleet state, the wall's filter and
   the computer list's group.
4. A late picture starts a problem, so a minute later the bar turns red and the console shows
   "<name> isn't answering".
5. A computer whose first picture is late, so it has no picture at all, turns Needs Attention
   (an unknown note on a picture-less card) instead of keeping its state.
6. The late picture says nothing, or the alarming "didn't send a picture in time", instead of the
   calm "Busy · picture is late"; or its last picture is dropped.
7. Once a picture is late, the computer's status stops being read while the console is open, so
   only a later picture can bring it back.
8. (guard) Late pictures from several computers hold more than one of the four picture lanes.
9. (guard) A late picture is asked for again at once instead of backing off.
10. (guard) A healthy computer stops getting pictures while others are late.

## Offline takes several unanswered status reads

11. One failed status read marks a computer Offline.
12. A brief status outage (about 12 s: two or three failed reads) marks it Offline.
13. A long outage marks it Offline before three failed reads in a row, or sooner than 30 s after
    the first; or never.
14. (guard) A long outage never turns the bar red with "<name> isn't answering" a minute later.
15. While the console is open, an Offline computer's status is never read again.
16. An Offline computer does not come back when a status read is answered, or needs more than one.
17. (guard) A refused computer (denied, revoked) is shown as late or Offline instead of failing
    closed: its picture must clear and it must read as access not confirmed.

## Version drift is visible

18. (guard) A computer's version from its status is not kept.
19. A computer's build from its status (`build`, optional) is not kept.
20. A computer on a different ibara version than the rest of the fleet is not flagged.
21. A computer on the same version but a different build is not flagged.
22. A computer on the fleet's own version and build is flagged.
23. A computer with no version yet (no status answered) is flagged.

The pure drift rule (ties, missing versions, no build anywhere) is checked in isolation in
`tests/fleet-build.test.mjs`, with its own failure list.
