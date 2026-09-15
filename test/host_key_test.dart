import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/ssh/host_key.dart';
import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/vault/vault.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_service.dart';

void main() {
  const fingerprint = 'SHA256:LqcOdAmQTGaWVaCF1tAjFt8soTT3UIsASPmyrIiTNDg';
  const different = 'SHA256:Ch0tVDz/Bah7FUQSSqosIVfAKW1ESoRV/Ut2KNNfQ4k';

  group('verdict', () {
    test('an unknown host is trusted on first use', () {
      expect(
        verifyHostKey(pinned: null, observed: fingerprint),
        HostKeyVerdict.firstUse,
      );
    });

    test('a matching key is accepted', () {
      expect(
        verifyHostKey(pinned: fingerprint, observed: fingerprint),
        HostKeyVerdict.matches,
      );
    });

    test('a changed key is refused', () {
      expect(
        verifyHostKey(pinned: fingerprint, observed: different),
        HostKeyVerdict.mismatch,
      );
    });

    test('comparison is exact', () {
      // Fingerprints are base64, which is case-sensitive; a near-miss must
      // not be waved through.
      expect(
        verifyHostKey(pinned: fingerprint, observed: fingerprint.toLowerCase()),
        HostKeyVerdict.mismatch,
      );
      expect(
        verifyHostKey(pinned: fingerprint, observed: '$fingerprint '),
        HostKeyVerdict.mismatch,
      );
    });
  });

  group('mismatch report', () {
    test('names the endpoint and both fingerprints', () {
      const error = HostKeyMismatch(
        endpoint: 'example.com:22',
        pinned: fingerprint,
        observed: different,
      );

      final message = error.toString();
      expect(message, contains('example.com:22'));
      expect(message, contains(fingerprint));
      expect(message, contains(different));
    });
  });

  group('pins in the vault', () {
    test('a pin survives lock and unlock', () async {
      final service = VaultService(blobStore: MemoryVaultBlobStore());
      await service.unlock('a passphrase');

      const host = SshHost(
        id: 'h1',
        hostname: 'example.com',
        username: 'ben',
      );
      await service.pinHostKey(host.endpoint, fingerprint);

      service.lock();
      final reopened = await service.unlock('a passphrase');

      expect(reopened.knownHosts[host.endpoint], fingerprint);
      expect(
        verifyHostKey(
          pinned: reopened.knownHosts[host.endpoint],
          observed: fingerprint,
        ),
        HostKeyVerdict.matches,
      );
    });

    test('pins are keyed by port, not just hostname', () {
      // Two services behind one hostname are different endpoints and can
      // legitimately present different keys.
      const plain = SshHost(hostname: 'example.com', username: 'ben');
      const alternate = SshHost(
        hostname: 'example.com',
        username: 'ben',
        port: 2222,
      );

      var vault = const Vault();
      vault = vault.pinHostKey(plain.endpoint, fingerprint);
      vault = vault.pinHostKey(alternate.endpoint, different);

      expect(vault.knownHosts[plain.endpoint], fingerprint);
      expect(vault.knownHosts[alternate.endpoint], different);
    });

    test('re-pinning replaces the recorded key', () {
      var vault = const Vault().pinHostKey('example.com:22', fingerprint);
      vault = vault.pinHostKey('example.com:22', different);

      expect(vault.knownHosts, hasLength(1));
      expect(vault.knownHosts['example.com:22'], different);
    });
  });
}
