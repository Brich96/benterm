import 'package:benterm/ssh/ssh_host.dart';
import 'package:benterm/vault/github_vault_store.dart';
import 'package:benterm/vault/vault.dart';
import 'package:benterm/vault/vault_blob_store.dart';
import 'package:benterm/vault/vault_crypto.dart';

/// Raised when an operation needs an unlocked vault and there isn't one.
class VaultLocked implements Exception {
  const VaultLocked();

  @override
  String toString() => 'The vault is locked';
}

/// What a [VaultService.sync] call actually did.
enum SyncOutcome {
  /// Local changes were written to GitHub.
  pushed,

  /// The remote copy was newer and has been adopted.
  pulled,

  /// The vault was created on GitHub for the first time.
  created,

  /// Nothing to do: no local changes and the remote is unchanged.
  upToDate,
}

/// Owns the unlocked vault and moves it between this device and GitHub.
///
/// Local edits are saved (encrypted) immediately and pushed separately, so
/// the app stays usable offline and a failed sync never loses an edit.
class VaultService {
  VaultService({
    required VaultBlobStore blobStore,
    GithubVaultStore? remote,
    VaultCrypto crypto = const VaultCrypto(),
  }) : _blobStore = blobStore,
       _remote = remote,
       _crypto = crypto;

  final VaultBlobStore _blobStore;

  /// Null until GitHub sync is configured; the vault works offline without it.
  final GithubVaultStore? _remote;

  final VaultCrypto _crypto;

  Vault? _vault;
  String? _passphrase;

  /// The sha the local copy came from; null until the vault exists remotely.
  String? _baseSha;

  /// Whether the local copy has edits not yet pushed.
  bool _dirty = false;

  bool get isUnlocked => _vault != null;

  bool get hasUnpushedChanges => _dirty;

  Vault get vault {
    final vault = _vault;
    if (vault == null) throw const VaultLocked();
    return vault;
  }

  /// Decrypts the local vault, creating an empty one on first run.
  ///
  /// Throws [WrongVaultPassphrase] if the passphrase does not match.
  Future<Vault> unlock(String passphrase) async {
    final blob = await _blobStore.readBlob();

    if (blob == null) {
      _passphrase = passphrase;
      _baseSha = await _blobStore.readSha();
      await _store(const Vault(), markDirty: true);
      return vault;
    }

    final decrypted = await _crypto.decrypt(blob, passphrase);
    _passphrase = passphrase;
    _vault = decrypted;
    _baseSha = await _blobStore.readSha();
    return decrypted;
  }

  void lock() {
    _vault = null;
    _passphrase = null;
  }

  /// Encrypts and saves [vault] locally, marking it for the next push.
  Future<void> save(Vault vault) => _store(vault, markDirty: true);

  Future<void> upsertHost(SshHost host) => save(vault.upsertHost(host));

  Future<void> removeHost(String id) => save(vault.removeHost(id));

  Future<void> pinHostKey(String endpoint, String fingerprint) =>
      save(vault.pinHostKey(endpoint, fingerprint));

  /// Pushes local changes, or adopts the remote copy if it moved on.
  ///
  /// Throws [VaultConflict] when both sides changed — the caller decides
  /// whether to discard local edits or overwrite the remote.
  Future<SyncOutcome> sync({GithubVaultLocation? location}) async {
    final remote = _remote;
    if (remote == null || location == null) {
      throw StateError('No GitHub location configured');
    }
    if (_passphrase == null) throw const VaultLocked();

    final current = await remote.fetch(location);

    if (current == null) {
      await _push(remote, location, sha: null);
      return SyncOutcome.created;
    }

    if (current.sha == _baseSha) {
      if (!_dirty) return SyncOutcome.upToDate;
      await _push(remote, location, sha: current.sha);
      return SyncOutcome.pushed;
    }

    // The remote moved. Adopting it is only safe with nothing local to lose.
    if (_dirty) throw const VaultConflict();

    final pulled = await _crypto.decrypt(current.contents, _passphrase!);
    _vault = pulled;
    _baseSha = current.sha;
    _dirty = false;
    await _blobStore.writeBlob(current.contents);
    await _blobStore.writeSha(current.sha);
    return SyncOutcome.pulled;
  }

  /// Discards local edits and takes whatever is on GitHub.
  Future<Vault> pullDiscardingLocalChanges(
    GithubVaultLocation location,
  ) async {
    final remote = _remote;
    if (remote == null) throw StateError('No GitHub location configured');
    if (_passphrase == null) throw const VaultLocked();

    final current = await remote.fetch(location);
    if (current == null) throw const GithubVaultError(404, 'No vault on GitHub');

    final pulled = await _crypto.decrypt(current.contents, _passphrase!);
    _vault = pulled;
    _baseSha = current.sha;
    _dirty = false;
    await _blobStore.writeBlob(current.contents);
    await _blobStore.writeSha(current.sha);
    return pulled;
  }

  /// Overwrites GitHub with the local copy, abandoning the remote version.
  Future<void> pushOverwritingRemote(GithubVaultLocation location) async {
    final remote = _remote;
    if (remote == null) throw StateError('No GitHub location configured');

    final current = await remote.fetch(location);
    await _push(remote, location, sha: current?.sha);
  }

  Future<void> _push(
    GithubVaultStore remote,
    GithubVaultLocation location, {
    required String? sha,
  }) async {
    final blob = await _blobStore.readBlob();
    if (blob == null) throw const VaultLocked();

    final newSha = await remote.write(location, contents: blob, sha: sha);
    _baseSha = newSha;
    _dirty = false;
    await _blobStore.writeSha(newSha);
  }

  Future<void> _store(Vault next, {required bool markDirty}) async {
    final passphrase = _passphrase;
    if (passphrase == null) throw const VaultLocked();

    final blob = await _crypto.encrypt(next, passphrase);
    await _blobStore.writeBlob(blob);
    _vault = await _crypto.decrypt(blob, passphrase);
    if (markDirty) _dirty = true;
  }
}
