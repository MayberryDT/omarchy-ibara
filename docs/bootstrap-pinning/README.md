# Authenticated bootstrap installer — 30 October 2026

The README command and Install ibara handler download the exact first-stage installer at:

`https://github.com/MayberryDT/ibara/releases/download/v0.3.4/install`

Reviewed SHA-256: `92591da2459f18da47b6567d47cb66c0b16b988d4752fa88ec67283021a03fbe`.

The public asset and retained signed-release copy have this digest. Download goes into a private mktemp file, HTTPS redirects only. The checksum check precedes sh; any download/checksum failure stops the subshell. Exit cleanup removes the file. The authenticated installer then verifies the signed release manifest and package hashes using its embedded release public key. Future bootstrap changes require a reviewed version-and-digest update here and in both commands. Signed package updates may still follow the Latest channel after the bootstrap is authenticated.

[Twenty process E2E receipts](bootstrap-results.json) cover both README and plugin commands: valid fixture, altered/truncated/empty/HTML payloads, download error after valid bytes were written, missing downloader, checker error, missing checker, and a real public download. Valid bytes reach the interpreter with mode0600; all negative cases stop before interpreter handoff. Every temporary file is cleaned, including with spaces in its directory.

[Real QML handler receipt](button-results.json) proves the install handler launches the identical command, authenticates the public installer and reaches the expected interpreter handoff. The setup-only handler still launches `ibara setup`. The service loaded on the real Wayland backend; the terminal launcher and final sh handoff were recording stand-ins. These checks do not install packages, exercise a physical button click, or claim a complete machine installation/security audit.

## Repeat

Use Python3, curl, sha256sum and a new scratch directory:

```bash
python3 /path/to/checkout/tests/e2e/bootstrap-install.py /path/to/checkout
```

This writes `bootstrap-results.json` and per-case handoff artifacts. The fixture records the final interpreter handoff rather than running the downloaded installer. Eight negative cases per entry point never create a handoff receipt.

On Omarchy with Quickshell, use a separate new scratch directory for the QML check:

```bash
cp /path/to/checkout/tests/e2e/{button.qml,button-e2e.py,terminal-launcher} .
ln -s /path/to/checkout plugin
python3 button-e2e.py
```

That writes `button-results.json`, the terminal-launch receipts and authenticated handoff. HOME/state and runtime are isolated. The initial fixture attempt exceeded Unix socket path length; the exercised script uses a short private temporary runtime directory.

Independent source review found no material defects. Final receipts were inspected by the implementing agent. Shell syntax, plugin manifest and QML syntax checks passed. Existing v0.3.4 assets are unchanged; this fix updates the Marketplace plugin and maintained core/bundle sources.
