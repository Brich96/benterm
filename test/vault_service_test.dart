import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/vault.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_crypto.dart';
import 'package:benterm/vault/vault_service.dart';

/// A stand-in for the vault file on GitHub, with the sha semantics the real
/// Contents API enforces.
class FakeGithub {
  String? contents;
  String? sha;
  var writes = 0;

  http.Client get client => MockClient((request) async {
    if (request.method == 'GET') {
      if (contents == null) {
        return http.Response('{"message":"Not Found"}', 404);
      }
      return http.Response(
        jsonEncode({
          'content': base64.encode(utf8.encode(contents!)),
          'encoding': 'base64',
          'sha': sha,
        }),
        200,
      );
    }

    final body = jsonDecode(request.body) as Map<String, Object?>;
    final providedSha = body['sha'] as String?;
    if (providedSha != sha) {
      return http.Response('{"message":"sha mismatch"}', 409);
    }

    writes++;
    contents = utf8.decode(base64.decode(body['content']! as String));
    sha = 'sha-$writes';
    return http.Response(
      jsonEncode({
        'content': {'sha': sha},
      }),
      200,
    );
  });
}

void main() {
  const location = GithubVaultLocation(
    owner: 'ben',
    repo: 'ssh-vault',
    token: 'token',
  );
  const passphrase = 'open sesame';
  const crypto = VaultCrypto();

  late MemoryVaultBlobStore blobStore;
  late FakeGithub github;
  late VaultService service;

  setUp(() {
    blobStore = MemoryVaultBlobStore();
    github = FakeGithub();
    service = VaultService(
      blobStore: blobStore,
      remote: GithubVaultStore(client: github.client),
    );
  });

  /// Simulates another device having pushed [hosts] since our last sync.
  Future<void> remoteWritesHost(String hostname) async {
    github.contents = await crypto.encrypt(
      Vault(hosts: [SshHost.create(hostname: hostname, username: 'ben')]),
      passphrase,
    );
    github.sha = 'sha-remote';
  }

  test('first unlock creates an empty vault', () async {
    final vault = await service.unlock(passphrase);

    expect(vault.hosts, isEmpty);
    expect(service.isUnlocked, isTrue);
    expect(await blobStore.readBlob(), isNotNull);
  });

  test('locking clears the decrypted copy', () async {
    await service.unlock(passphrase);
    service.lock();

    expect(service.isUnlocked, isFalse);
    expect(() => service.vault, throwsA(isA<VaultLocked>()));
  });

  test('re-unlocking requires the same passphrase', () async {
    await service.unlock(passphrase);
    await service.upsertHost(
      SshHost.create(hostname: 'example.com', username: 'ben'),
    );
    service.lock();

    await expectLater(
      service.unlock('wrong'),
      throwsA(isA<WrongVaultPassphrase>()),
    );

    final reopened = await service.unlock(passphrase);
    expect(reopened.hosts.single.hostname, 'example.com');
  });

  test('edits are kept encrypted at rest', () async {
    await service.unlock(passphrase);
    await service.upsertHost(
      SshHost.create(
        hostname: 'example.com',
        username: 'ben',
        password: 'hunter2',
      ),
    );

    expect(await blobStore.readBlob(), isNot(contains('hunter2')));
    expect(service.hasUnpushedChanges, isTrue);
  });

  test('first sync creates the vault on GitHub', () async {
    await service.unlock(passphrase);

    expect(await service.sync(location: location), SyncOutcome.created);
    expect(github.contents, isNotNull);
    expect(service.hasUnpushedChanges, isFalse);
  });

  test('a second sync with no changes does nothing', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);

    expect(await service.sync(location: location), SyncOutcome.upToDate);
    expect(github.writes, 1);
  });

  test('local edits are pushed', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);
    await service.upsertHost(
      SshHost.create(hostname: 'example.com', username: 'ben'),
    );

    expect(await service.sync(location: location), SyncOutcome.pushed);
    expect(github.writes, 2);
    expect(service.hasUnpushedChanges, isFalse);
  });

  test('a remote change is adopted when nothing local would be lost', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);
    await remoteWritesHost('from-phone.example');

    expect(await service.sync(location: location), SyncOutcome.pulled);
    expect(service.vault.hosts.single.hostname, 'from-phone.example');
  });

  test('changes on both sides conflict instead of clobbering', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);
    await remoteWritesHost('theirs');
    await service.upsertHost(SshHost.create(hostname: 'mine', username: 'ben'));

    await expectLater(
      service.sync(location: location),
      throwsA(isA<VaultConflict>()),
    );

    // Neither side was silently overwritten.
    expect(service.vault.hosts.single.hostname, 'mine');
    expect(github.writes, 1);
  });

  test('a conflict can be resolved by taking the remote copy', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);
    await remoteWritesHost('theirs');
    await service.upsertHost(SshHost.create(hostname: 'mine', username: 'ben'));

    final resolved = await service.pullDiscardingLocalChanges(location);

    expect(resolved.hosts.single.hostname, 'theirs');
    expect(service.hasUnpushedChanges, isFalse);
  });

  test('a conflict can be resolved by overwriting the remote copy', () async {
    await service.unlock(passphrase);
    await service.sync(location: location);
    await remoteWritesHost('theirs');
    await service.upsertHost(SshHost.create(hostname: 'mine', username: 'ben'));

    await service.pushOverwritingRemote(location);

    final pushed = await crypto.decrypt(github.contents!, passphrase);
    expect(pushed.hosts.single.hostname, 'mine');
    expect(service.hasUnpushedChanges, isFalse);
  });

  group('joining from another device', () {
    /// A device with empty local storage, pointed at the same repo.
    VaultService freshDevice() => VaultService(
      blobStore: MemoryVaultBlobStore(),
      remote: GithubVaultStore(client: github.client),
    );

    test('restores the existing vault with the same passphrase', () async {
      await service.unlock(passphrase);
      await service.upsertHost(
        SshHost.create(hostname: 'example.com', username: 'ben'),
      );
      await service.sync(location: location);

      final joined = freshDevice();
      final restored = await joined.restoreFromRemote(location, passphrase);

      expect(restored.hosts.single.hostname, 'example.com');
      expect(joined.isUnlocked, isTrue);
      // Nothing local to push: it is in step with the remote already.
      expect(joined.hasUnpushedChanges, isFalse);
      expect(await joined.sync(location: location), SyncOutcome.upToDate);
    });

    test('rejects a different passphrase', () async {
      await service.unlock(passphrase);
      await service.sync(location: location);

      await expectLater(
        freshDevice().restoreFromRemote(location, 'a different passphrase'),
        throwsA(isA<WrongVaultPassphrase>()),
      );
    });

    test('reports an empty repository distinctly', () async {
      await expectLater(
        freshDevice().restoreFromRemote(location, passphrase),
        throwsA(isA<NoRemoteVault>()),
      );
    });

    test('edits made after joining push without a conflict', () async {
      await service.unlock(passphrase);
      await service.sync(location: location);

      final joined = freshDevice();
      await joined.restoreFromRemote(location, passphrase);
      await joined.upsertHost(
        SshHost.create(hostname: 'from-the-phone', username: 'ben'),
      );

      expect(await joined.sync(location: location), SyncOutcome.pushed);
    });
  });

  test('a new device pulls the vault with just the passphrase', () async {
    await service.unlock(passphrase);
    await service.upsertHost(
      SshHost.create(hostname: 'example.com', username: 'ben'),
    );
    await service.sync(location: location);

    // Fresh device: empty local storage, same GitHub repo and passphrase.
    final newDevice = VaultService(
      blobStore: MemoryVaultBlobStore(),
      remote: GithubVaultStore(client: github.client),
    );
    await newDevice.unlock(passphrase);
    final pulled = await newDevice.pullDiscardingLocalChanges(location);

    expect(pulled.hosts.single.hostname, 'example.com');
  });

  test('removing a host is persisted', () async {
    await service.unlock(passphrase);
    final host = SshHost.create(hostname: 'example.com', username: 'ben');
    await service.upsertHost(host);
    await service.removeHost(host.id);

    service.lock();
    final reopened = await service.unlock(passphrase);
    expect(reopened.hosts, isEmpty);
  });

  test('editing a host replaces it instead of duplicating', () async {
    await service.unlock(passphrase);
    final host = SshHost.create(hostname: 'example.com', username: 'ben');
    await service.upsertHost(host);
    await service.upsertHost(host.copyWith(username: 'root'));

    expect(service.vault.hosts, hasLength(1));
    expect(service.vault.hosts.single.username, 'root');
  });

  test('pinned host keys survive a round trip', () async {
    await service.unlock(passphrase);
    await service.pinHostKey('example.com:22', 'SHA256:abc');

    service.lock();
    final reopened = await service.unlock(passphrase);
    expect(reopened.knownHosts['example.com:22'], 'SHA256:abc');
  });
}
