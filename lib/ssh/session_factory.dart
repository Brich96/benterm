import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/ssh/ssh_session.dart';
import 'package:benterm/vault/vault_service.dart';

/// Builds a session for [host], wired to the vault's pinned host keys.
///
/// Every connection goes through here so host-key checking cannot be
/// forgotten at one of the call sites.
SshSession sessionFor(SshHost host, VaultService? service) {
  return SshSession(
    host,
    pinnedFingerprint: service?.vault.knownHosts[host.endpoint],
    onHostKeyPinned: service == null
        ? null
        : (fingerprint) => service.pinHostKey(host.endpoint, fingerprint),
  );
}
