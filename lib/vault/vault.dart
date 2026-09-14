import 'package:benterm/ssh/ssh_host.dart';

/// The decrypted contents of the vault: everything that syncs between
/// devices.
///
/// Stored as a single blob rather than a file per host — the whole thing is
/// a few KB, and GitHub's `sha` precondition then gives whole-vault conflict
/// detection with no merge logic to get wrong.
class Vault {
  const Vault({
    this.hosts = const [],
    this.knownHosts = const {},
    this.updatedAt,
  });

  factory Vault.fromJson(Map<String, Object?> json) {
    final hosts = (json['hosts'] as List<Object?>? ?? const [])
        .cast<Map<String, Object?>>()
        .map(SshHost.fromJson)
        .toList();

    final knownHosts = (json['knownHosts'] as Map<String, Object?>? ?? const {})
        .map((endpoint, fingerprint) => MapEntry(endpoint, fingerprint as String));

    final updatedAt = json['updatedAt'] as String?;

    return Vault(
      hosts: hosts,
      knownHosts: knownHosts,
      updatedAt: updatedAt == null ? null : DateTime.parse(updatedAt),
    );
  }

  /// Bumped when the plaintext schema changes in a way older builds cannot
  /// read. The envelope carries its own separate format version.
  static const schemaVersion = 1;

  final List<SshHost> hosts;

  /// Pinned host-key fingerprints, keyed by `hostname:port`.
  final Map<String, String> knownHosts;

  final DateTime? updatedAt;

  Map<String, Object?> toJson() {
    return {
      'version': schemaVersion,
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
      'hosts': [for (final host in hosts) host.toJson()],
      'knownHosts': knownHosts,
    };
  }

  /// Adds [host], or replaces the existing entry with the same id.
  Vault upsertHost(SshHost host) {
    final next = [...hosts];
    final index = next.indexWhere((candidate) => candidate.id == host.id);
    if (index == -1) {
      next.add(host);
    } else {
      next[index] = host;
    }
    return copyWith(hosts: next);
  }

  Vault removeHost(String id) {
    return copyWith(hosts: [
      for (final host in hosts)
        if (host.id != id) host,
    ]);
  }

  /// Pins [fingerprint] for [endpoint] (`hostname:port`).
  Vault pinHostKey(String endpoint, String fingerprint) {
    return copyWith(knownHosts: {...knownHosts, endpoint: fingerprint});
  }

  Vault copyWith({
    List<SshHost>? hosts,
    Map<String, String>? knownHosts,
    DateTime? updatedAt,
  }) {
    return Vault(
      hosts: hosts ?? this.hosts,
      knownHosts: knownHosts ?? this.knownHosts,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
