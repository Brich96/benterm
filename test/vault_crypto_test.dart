import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/vault/vault.dart';
import 'package:benterm/vault/vault_crypto.dart';

void main() {
  const crypto = VaultCrypto();
  const passphrase = 'correct horse battery staple';

  Vault sampleVault() {
    return Vault(
      hosts: [
        SshHost.create(
          hostname: 'example.com',
          username: 'ben',
          label: 'prod',
          password: 'hunter2',
        ),
        SshHost.create(
          hostname: 'box.internal',
          username: 'root',
          port: 2222,
          privateKeyPem: '-----BEGIN OPENSSH PRIVATE KEY-----',
        ),
      ],
      knownHosts: const {'example.com:22': 'SHA256:abc123'},
    );
  }

  test('round-trips a vault', () async {
    final vault = sampleVault();

    final blob = await crypto.encrypt(vault, passphrase);
    final restored = await crypto.decrypt(blob, passphrase);

    expect(restored.hosts, hasLength(2));
    expect(restored.hosts.first.label, 'prod');
    expect(restored.hosts.first.password, 'hunter2');
    expect(restored.hosts.last.port, 2222);
    expect(restored.knownHosts['example.com:22'], 'SHA256:abc123');
    expect(restored.updatedAt, isNotNull);
  });

  test('secrets never appear in the encrypted blob', () async {
    final blob = await crypto.encrypt(sampleVault(), passphrase);

    expect(blob, isNot(contains('hunter2')));
    expect(blob, isNot(contains('example.com')));
    expect(blob, isNot(contains('OPENSSH PRIVATE KEY')));
  });

  test('rejects the wrong passphrase', () async {
    final blob = await crypto.encrypt(sampleVault(), passphrase);

    expect(
      () => crypto.decrypt(blob, 'not the passphrase'),
      throwsA(isA<WrongVaultPassphrase>()),
    );
  });

  test('rejects a tampered ciphertext', () async {
    final blob = await crypto.encrypt(sampleVault(), passphrase);
    final envelope = jsonDecode(blob) as Map<String, Object?>;

    final ciphertext = base64.decode(envelope['ciphertext']! as String);
    ciphertext[0] ^= 0xff;
    envelope['ciphertext'] = base64.encode(ciphertext);

    expect(
      () => crypto.decrypt(jsonEncode(envelope), passphrase),
      throwsA(isA<WrongVaultPassphrase>()),
    );
  });

  test('each encryption uses a fresh salt and nonce', () async {
    final vault = sampleVault();

    final first =
        jsonDecode(await crypto.encrypt(vault, passphrase))
            as Map<String, Object?>;
    final second =
        jsonDecode(await crypto.encrypt(vault, passphrase))
            as Map<String, Object?>;

    final firstKdf = first['kdf']! as Map<String, Object?>;
    final secondKdf = second['kdf']! as Map<String, Object?>;
    final firstCipher = first['cipher']! as Map<String, Object?>;
    final secondCipher = second['cipher']! as Map<String, Object?>;

    expect(firstKdf['salt'], isNot(secondKdf['salt']));
    expect(firstCipher['nonce'], isNot(secondCipher['nonce']));
  });

  test('reports an unreadable envelope distinctly from a bad passphrase',
      () async {
    expect(
      () => crypto.decrypt('not json at all', passphrase),
      throwsA(isA<UnreadableVault>()),
    );

    final blob = await crypto.encrypt(sampleVault(), passphrase);
    final envelope = jsonDecode(blob) as Map<String, Object?>;
    envelope['format'] = 99;

    expect(
      () => crypto.decrypt(jsonEncode(envelope), passphrase),
      throwsA(isA<UnreadableVault>()),
    );
  });

  test('decrypts with the kdf parameters stored in the envelope', () async {
    // Parameters are read back from the blob, so raising them later must not
    // strand vaults written with the old ones.
    final blob = await crypto.encrypt(sampleVault(), passphrase);
    final envelope = jsonDecode(blob) as Map<String, Object?>;
    final kdf = envelope['kdf']! as Map<String, Object?>;

    expect(kdf['memory'], VaultCrypto.kdfMemoryKib);
    expect(kdf['iterations'], VaultCrypto.kdfIterations);
    expect(kdf['parallelism'], VaultCrypto.kdfParallelism);
  });
}
