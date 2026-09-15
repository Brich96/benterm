*ai project. Written with Claude Code. I set the direction and reviewed it, but
the code is the model's.

# BenTerm

An SSH client for Windows and Android. Your hosts live in an encrypted file that
syncs between your devices through a private GitHub repo you own.

I wanted something like Termius that doesn't ship a whole browser inside it, and
I'd rather keep my host list somewhere I control than in someone else's account.

## Status

Early. It connects, holds sessions open, syncs, and updates itself. A fair bit
is still missing. The version numbers are low for a reason.

## What it does

- SSH with a password or a private key
- Several sessions at once, in tabs
- Host list with search, and a quick-connect form for one-off boxes
- Remembers a server's host key the first time and refuses to connect if it
  ever changes
- Keeps hosts and keys in a passphrase-encrypted vault that syncs through your
  own private GitHub repo
- Updates itself from GitHub releases

## What it doesn't do

- No SFTP or file transfer
- No port forwarding or agent forwarding
- No jump hosts
- macOS and Linux compile but aren't released. iOS is untested.

## Install

Builds are on the [releases page](https://github.com/Brich96/benterm/releases).

**Windows.** Unzip it somewhere you can write to, like a folder under your user
directory. Don't put it in Program Files: the updater replaces its own files in
place, and it can't do that without elevation. Nothing is code-signed, so
SmartScreen will complain the first time you run it.

**Android.** Install the APK. Every release is signed with the same key, which
is what makes in-app updates possible at all.

## The vault

Hosts, passwords and private keys go into one small JSON blob. That blob is
encrypted with AES-256-GCM, under a key derived from your passphrase with
Argon2id, and the encrypted result is what gets written to GitHub. The
passphrase isn't stored anywhere and never leaves the device, so if you forget
it the vault is gone.

Sync needs a private repo and a fine-grained access token scoped to just that
repo. The token and repo details go in the OS keychain (DPAPI on Windows,
Keystore on Android) rather than the vault, since you need them before there's
anything to decrypt.

Every write sends back the blob SHA it was read at. If another device has
changed the vault since, the write is refused instead of silently overwriting,
and you decide which side wins.

## Building

CI pins Flutter 3.47.4. Anything close to that should work.

    flutter pub get
    flutter run -d windows
    flutter test

## Releasing

Tag and push:

    git tag v0.3.3
    git push origin v0.3.3

Actions runs the tests, builds Windows and Android, checks the APK carries the
right signature, and publishes the release with checksums. The version that
ships comes from the tag, not from pubspec.yaml.
