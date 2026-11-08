# Request dismissal privacy check

`Service.qml` saves popup dismissals to `~/.local/state/omarchy/ibara-request-dismissals.json`. Earlier versions used the whole sign-up proposal as the saved signature. The signature is now an MD5 fingerprint of that proposal, and older files are converted on load.

To repeat the check on an Omarchy desktop with a Wayland session:

    bash tests/e2e/dismissal-privacy/run.sh . OUTPUT_DIR

It loads the real `Service.qml` and real `FileView` persistence in an isolated home, with fictional marker strings, and writes `OUTPUT_DIR/results.json`. A popup expires through its real 15-second timer. The failure cases were written first and are in [FAILURE-CASES.md](../../tests/e2e/dismissal-privacy/FAILURE-CASES.md).

| Receipt | Source | Result |
| --- | --- | --- |
| [results-before.json](results-before.json) | Previous commit `b8ee14b` | Fails; marker text reaches the dismissal file |
| [results-fixed.json](results-fixed.json) | This fix, `Service.qml` SHA-256 `06b070db60c144097102ecc7a7a542aeaa8adafc49a64fc58ce9efe9e38121c5` | All 23 checks pass |

Both ran on Omarchy 4.0.4-1 with Quickshell 0.3.1. The previous commit's later checks also fail because a malformed `null` entry made dismissals throw; this fix removes such entries on load.

Limits: fictional data and one machine. No real account or sign-up was used. This is a scoped integration check, not a security audit. The file's mode is unchanged; it no longer holds proposal text.
