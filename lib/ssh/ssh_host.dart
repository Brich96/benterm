import 'dart:math';

/// Connection details for a single SSH host.
///
/// Hosts stored in the vault carry a generated [id]; hosts built ad-hoc by
/// the quick-connect form leave it empty.
class SshHost {
  const SshHost({
    required this.hostname,
    required this.username,
    this.id = '',
    this.port = 22,
    this.label,
    this.password,
    this.privateKeyPem,
    this.privateKeyPassphrase,
  });

  /// Creates a host with a fresh random [id], for storing in the vault.
  factory SshHost.create({
    required String hostname,
    required String username,
    int port = 22,
    String? label,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
  }) {
    return SshHost(
      id: newId(),
      hostname: hostname,
      username: username,
      port: port,
      label: label,
      password: password,
      privateKeyPem: privateKeyPem,
      privateKeyPassphrase: privateKeyPassphrase,
    );
  }

  factory SshHost.fromJson(Map<String, Object?> json) {
    return SshHost(
      id: json['id'] as String? ?? '',
      hostname: json['hostname'] as String,
      username: json['username'] as String,
      port: json['port'] as int? ?? 22,
      label: json['label'] as String?,
      password: json['password'] as String?,
      privateKeyPem: json['privateKeyPem'] as String?,
      privateKeyPassphrase: json['privateKeyPassphrase'] as String?,
    );
  }

  static final _random = Random.secure();

  /// 128 bits of randomness, hex encoded.
  static String newId() {
    return List.generate(
      16,
      (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  final String id;
  final String hostname;
  final String username;
  final int port;
  final String? label;

  /// Password auth. Null when authenticating with a key.
  final String? password;

  /// OpenSSH/PEM private key text. Null when authenticating with a password.
  final String? privateKeyPem;

  /// Passphrase for an encrypted [privateKeyPem].
  final String? privateKeyPassphrase;

  String get displayName => label ?? '$username@$hostname';

  /// Key used to look up this host's pinned fingerprint.
  String get endpoint => '$hostname:$port';

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'hostname': hostname,
      'username': username,
      'port': port,
      if (label != null) 'label': label,
      if (password != null) 'password': password,
      if (privateKeyPem != null) 'privateKeyPem': privateKeyPem,
      if (privateKeyPassphrase != null)
        'privateKeyPassphrase': privateKeyPassphrase,
    };
  }

  SshHost copyWith({
    String? hostname,
    String? username,
    int? port,
    String? label,
    String? password,
    String? privateKeyPem,
    String? privateKeyPassphrase,
  }) {
    return SshHost(
      id: id,
      hostname: hostname ?? this.hostname,
      username: username ?? this.username,
      port: port ?? this.port,
      label: label ?? this.label,
      password: password ?? this.password,
      privateKeyPem: privateKeyPem ?? this.privateKeyPem,
      privateKeyPassphrase: privateKeyPassphrase ?? this.privateKeyPassphrase,
    );
  }
}
