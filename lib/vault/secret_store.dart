import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:benterm/vault/github_vault_store.dart';

/// Small key/value store for secrets that must not go in the vault blob:
/// the GitHub token, and the repo coordinates needed to fetch the vault
/// before it can be decrypted.
abstract class SecretStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

/// Keychain on iOS/macOS, Keystore on Android, DPAPI on Windows, libsecret
/// on Linux.
///
/// The Linux backend needs a running keyring service, which a headless box
/// will not have — [MemorySecretStore] is the fallback there.
class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Non-persistent store, for tests.
class MemorySecretStore implements SecretStore {
  final _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

/// Reads and writes the GitHub sync configuration.
class VaultSyncSettings {
  const VaultSyncSettings(this._store);

  static const _ownerKey = 'github.owner';
  static const _repoKey = 'github.repo';
  static const _pathKey = 'github.path';
  static const _branchKey = 'github.branch';
  static const _tokenKey = 'github.token';

  final SecretStore _store;

  /// Returns null until sync has been configured.
  Future<GithubVaultLocation?> load() async {
    final owner = await _store.read(_ownerKey);
    final repo = await _store.read(_repoKey);
    final token = await _store.read(_tokenKey);
    if (owner == null || repo == null || token == null) return null;

    return GithubVaultLocation(
      owner: owner,
      repo: repo,
      token: token,
      path: await _store.read(_pathKey) ?? 'vault.json',
      branch: await _store.read(_branchKey),
    );
  }

  Future<void> save(GithubVaultLocation location) async {
    await _store.write(_ownerKey, location.owner);
    await _store.write(_repoKey, location.repo);
    await _store.write(_pathKey, location.path);
    await _store.write(_tokenKey, location.token);
    final branch = location.branch;
    if (branch == null) {
      await _store.delete(_branchKey);
    } else {
      await _store.write(_branchKey, branch);
    }
  }

  Future<void> clear() async {
    for (final key in [_ownerKey, _repoKey, _pathKey, _branchKey, _tokenKey]) {
      await _store.delete(key);
    }
  }
}
