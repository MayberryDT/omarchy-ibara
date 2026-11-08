# Request dismissal privacy: failure cases

Written before the fix. Each is exercised by `run.sh` against the real `Service.qml`,
real `FileView` persistence and an isolated home, using fictional marker strings.

1. A sign-up proposal's site, identity, credential store or summary reaches the dismissal file when its popup expires.
2. The same text reaches the file on an explicit dismissal.
3. A file written by an older version keeps its plain proposal after load.
4. Conversion produces a different signature from new code, so a dismissed proposal alerts again.
5. A second load hashes an already converted signature and loses the dismissal.
6. An ordinary `request` signature is converted and every other dismissal is lost.
7. A malformed entry stops loading, so `requestDismissalsReady` never becomes true and popups stop.
8. `Qt.md5` is unavailable in Quickshell and every signature call throws.
9. A changed proposal stays hidden behind an earlier dismissal.
10. A dismissal or popup-only expiry is lost across a shell reload.
11. A file with nothing to convert is rewritten on every load.
12. Text survives elsewhere under the home, such as a leftover atomic-write temporary file.
