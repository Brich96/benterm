# Custom SSH Client — Build Plan (Flutter)

## Goal

A lightweight, native (not Electron-style bloated) SSH terminal client — a
Termius-style tool — that:

- Runs on **Windows, Linux, macOS, iOS, and Android** from one codebase
- Renders natively via Flutter's Skia/Impeller engine — **no bundled Chromium,
  no Node.js, no DOM/webview** — fast startup, small footprint
- Stores SSH hosts and private keys in an **encrypted vault that syncs across
  devices** via a private **GitHub repo**, using **GitHub's REST API directly
  over HTTPS** (no system `git` binary, no embedded git library)

## Why this stack (context for whoever picks this up)

This plan went through several iterations before landing here — worth knowing
why, so the reasoning isn't re-litigated mid-build:

- Terminal emulator *apps* (Alacritty, Kitty, WezTerm, Ghostty) are not
  extensible — none of them have a plugin system for adding something like
  sync. You embed a terminal *engine/library*, not an app.
- Kitty was ruled out early — no native Windows support (Linux/macOS only).
- WezTerm was ruled out — its last tagged *stable* release is from Feb 2024
  (nightlies still ship, release process is effectively stalled), and it has
  no mobile story at all.
- A Tauri + xterm.js (webview) approach was considered and rejected once
  "fast/lightweight, not Electron-bloated" was confirmed as the real
  priority — a webview isn't Chromium-bloated like Electron, but it's still
  not truly native rendering.
- A fully custom native Rust stack (`alacritty_terminal` + `wgpu` + `winit`,
  with hand-built FFI shells for iOS/Android) was the direction settled on
  next — genuinely the fastest/lightest possible option, but the mobile leg
  would have meant hand-building FFI + rendering glue + touch/keyboard
  handling from scratch, with no existing terminal+SSH library ecosystem to
  lean on for that work.
- **Once "must be Rust" was dropped as a constraint, Flutter became the
  better fit.** It still renders natively via Skia/Impeller (not a webview),
  but mobile is its core, mature use case rather than a bolt-on — and there
  are already production-grade libraries for exactly this app:
  - [`xterm.dart`](https://pub.dev/packages/xterm) — mature terminal widget,
    renders at 60fps, explicit mobile support, MIT licensed
  - [`dartssh2`](https://pub.dev/packages/dartssh2) — pure-Dart SSH/SFTP
    client, no native C bindings to cross-compile per platform
  - A real reference implementation already exists:
    [`rudra-sah00/ssh-client`](https://github.com/rudra-sah00/ssh-client) —
    an open-source Flutter SSH client with terminal, SFTP, multi-session, and
    secure keychain storage, built on this exact stack
- Git-as-sync-transport was chosen over a from-scratch encrypted-blob server
  (Cloudflare R2) or a self-hosted Vaultwarden instance — GitHub's Contents
  API gives free versioning and free conflict detection (via SHA
  preconditions) with nothing self-hosted to run. Embedding a full git
  library was considered and rejected in favor of plain HTTPS calls — the
  vault is one small encrypted blob, not a multi-file repo needing real git
  semantics, and a bare HTTP client is the most portable option across all
  five target platforms.

**Honest trade-off to flag:** Flutter apps bundle a runtime engine, so the
binary/memory footprint won't be quite as minimal as a from-scratch native
Rust binary would be. It's a different category from Electron — no bundled
Chromium, no Node, real GPU rendering — but it's not the absolute floor
either. This was an explicit, deliberate trade against a much larger mobile
build risk, not an oversight.

## Architecture

A single Flutter app, structured to keep concerns separated even though it's
one codebase:

```
/lib
  /terminal    — xterm.dart Terminal + TerminalView wiring
  /ssh         — dartssh2 session management (connect, auth, pty)
  /vault       — encrypted host/key storage + GitHub sync
  /ui          — host list, connection screens, settings, theming
```

### terminal

- `xterm.dart`'s `Terminal` object owns the VT100/ANSI parsing, character
  grid, cursor, colors, and scrollback — feed it raw bytes, it maintains
  state.
- `TerminalView` is the Flutter widget that renders it and captures
  keyboard/IME input, including on mobile.

### ssh

- `dartssh2` owns the SSH session: authentication (password, private key,
  interactive), pty allocation, and port forwarding if needed later.
- Pipe incoming SSH channel bytes into the `xterm.dart` `Terminal`; pipe
  `Terminal.onOutput` (user keystrokes) back out through the SSH channel.
- SFTP is available via the same package if file browsing gets added later —
  see the `rudra-sah00/ssh-client` reference project for a working example of
  this wired up end-to-end.

### vault

- Vault format: a single JSON blob containing host entries + private keys,
  encrypted client-side before it ever leaves the device.
- Encryption library: the `cryptography` package (cross-platform: mobile,
  desktop, JS/WASM) is the starting point for AEAD encryption
  (XChaCha20-Poly1305 or AES-GCM) and key derivation.
  **Needs verification before committing:** confirm `cryptography` /
  `cryptography_flutter` actually expose Argon2id natively on all five
  target platforms — if not, fall back to `sodium`/`sodium_libs`
  (libsodium bindings), which reliably supports Argon2id. Don't skip this
  check; getting the crypto backend wrong is expensive to unwind later.
- Local secret storage (the GitHub PAT, and the derived/cached vault key if
  you choose to cache it): `flutter_secure_storage`, which uses Keychain on
  iOS/macOS and Keystore on Android. **Linux caveat:** it requires `libsecret`
  and a running keyring service (usually present on a desktop environment,
  not guaranteed headless) — confirm this works in your actual Linux target
  environment early.
- Sync transport: a plain Dart `http` (or `dio`) client calling GitHub's
  Contents API directly:
  - `GET /repos/{owner}/{repo}/contents/{path}` to fetch the current blob and
    its `sha`
  - `PUT /repos/{owner}/{repo}/contents/{path}` with that `sha` as a
    precondition to write — a `409` response means something else wrote
    first; surface that to the user rather than silently overwriting
  - Auth: a GitHub personal access token, scoped to just this one private
    repo
- New-device onboarding: user enters their vault passphrase and points the
  app at the GitHub repo + PAT once; the app pulls and decrypts the vault
  locally from then on.

### ui

- Host list, add/edit host screens, connection tabs for multiple concurrent
  sessions, settings (including where the GitHub repo/PAT get configured).
- Flutter's Material/Cupertino widgets cover this without extra libraries.

## Suggested build order

1. **Local terminal, no SSH, no sync, desktop only.** Wire up `xterm.dart` in
   a bare Flutter desktop app so you can see and interact with a working
   terminal widget before adding networking.
2. **Add `dartssh2`.** Connect to a real host, pipe bytes both directions.
   Now it's a real SSH client on desktop.
3. **Add the `vault` module + GitHub sync.** Host list UI, add/edit hosts,
   encrypt, push/pull against the GitHub Contents API.
4. **Resolve the crypto-backend verification** from the vault section above,
   if not already settled by this point.
5. **Bring up mobile (iOS, then Android, or whichever matters more first).**
   Expect this to be far less work than the Rust-native plan would have
   required, since `xterm.dart` and `dartssh2` already support mobile — the
   main new work here is touch-friendly UI (on-screen keyboard toolbar for
   Ctrl/Alt/Esc/arrows — see `rudra-sah00/ssh-client` for a working example)
   rather than low-level platform glue.
6. **Polish** — multi-session tabs, SFTP browsing, theming, connection
   search/filter.

## Open decisions to make early

- Final crypto backend: `cryptography`/`cryptography_flutter` vs.
  `sodium`/`sodium_libs` — resolve via the verification step above
- Vault schema: one encrypted blob vs. one file per host (affects how
  granular GitHub's conflict detection and history are)
- Whether to cache the derived vault key in `flutter_secure_storage` for
  convenience, or require the passphrase every session (security/convenience
  trade-off, your call)
- GitHub PAT scope — use a fine-grained PAT limited to the single private
  vault repo, not a broad classic token
