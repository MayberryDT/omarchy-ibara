# Dismiss requests: failure cases

Written before the quick panel's Dismiss requests, the `visible_requests` and `dismissals_ready`
status fields and the binding of cards that need a newer ibara were brought back (0.3.1–0.3.4 had
them; 0.3.5 was built from a line without them). Each is exercised by `run.sh` against the real
`Service.qml`, `QuickPanel.qml`, `StatusModel.js` and IPC handler, in an isolated home, offscreen,
with fictional requests and marker strings.

1. The quick panel has no Dismiss requests, or shows it while nothing waits, or hides it while
   something does.
2. After Dismiss requests an approval, a question, a sign-in request or a request that needs a
   newer ibara still shows in the quick panel.
3. A request that arrives after Dismiss requests is hidden too.
4. Dismiss requests writes request text to the dismissal file: a sign-up proposal's site,
   identity, credential store or summary, or any request's words.
5. A card for a request that needs a newer ibara is dismissed under no request identity (the key
   `undefined`) or another computer's, so it stays, or dismissing it hides another computer's.
6. The IPC status has no `visible_requests` or `dismissals_ready`; `visible_requests` counts
   dismissed requests or leaves out ones that need a newer ibara.
7. The IPC `dismissRequests` is missing, or does not dismiss, or does not say how many still wait.
8. (guard) A sign-in whose pop-up only timed out leaves the quick panel (the 5 November repair).
9. (guard) Answering is still possible: dismissed requests stay in the service's lists for the
   console.
