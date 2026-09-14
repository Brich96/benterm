import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

import 'package:benterm/vault/vault.dart';

/// Raised when a vault cannot be decrypted with the supplied passphrase.
///
/// Also raised for a tampered blob: AES-GCM cannot tell a wrong key from
/// modified ciphertext, and neither can we.
class WrongVaultPassphrase implements Exception {
  const WrongVaultPassphrase();

  @override
  String toString() => 'Wrong vault passphrase, or the vault was modified';
}

/// Raised when a blob is not a vault this build can read.
class UnreadableVault implements Exception {
  const UnreadableVault(this.reason);

  final String reason;

  @override
  String toString() => 'Unreadable vault: $reason';
}

/// Encrypts and decrypts the vault blob.
///
/// Argon2id for key derivation, AES-GCM-256 for the payload. Argon2id is
/// pure Dart here — `cryptography_flutter` ships no native Argon2 for any
/// platform, and measured on desktop the OWASP-minimum parameters below cost
/// ~450ms, so the libsodium dependency the plan held in reserve buys nothing
/// and would have to be cross-compiled five ways.
///
/// KDF parameters live in the envelope, so they can be raised later without
/// stranding existing vaults.
class VaultCrypto {
  const VaultCrypto();

  /// Envelope format version, independent of [Vault.schemaVersion].
  static const envelopeFormat = 1;

  /// OWASP minimum for Argon2id: 19 MiB, t=2, p=1.
  static const kdfMemoryKib = 19 * 1024;
  static const kdfIterations = 2;
  static const kdfParallelism = 1;

  static const _saltLength = 16;
  static const _keyLength = 32;

  static final _random = Random.secure();

  AesGcm get _cipher => AesGcm.with256bits();

  Future<String> encrypt(Vault vault, String passphrase) async {
    final salt = _randomBytes(_saltLength);
    final key = await _deriveKey(
      passphrase: passphrase,
      salt: salt,
      memory: kdfMemoryKib,
      iterations: kdfIterations,
      parallelism: kdfParallelism,
    );

    final stamped = vault.copyWith(updatedAt: DateTime.now().toUtc());
    final plaintext = utf8.encode(jsonEncode(stamped.toJson()));

    final cipher = _cipher;
    final box = await cipher.encrypt(
      plaintext,
      secretKey: key,
      nonce: cipher.newNonce(),
    );

    return jsonEncode({
      'format': envelopeFormat,
      'kdf': {
        'algorithm': 'argon2id',
        'memory': kdfMemoryKib,
        'iterations': kdfIterations,
        'parallelism': kdfParallelism,
        'salt': base64.encode(salt),
      },
      'cipher': {
        'algorithm': 'aes-gcm-256',
        'nonce': base64.encode(box.nonce),
      },
      'ciphertext': base64.encode(box.cipherText),
      'mac': base64.encode(box.mac.bytes),
    });
  }

  Future<Vault> decrypt(String envelopeJson, String passphrase) async {
    final Map<String, Object?> envelope;
    try {
      envelope = jsonDecode(envelopeJson) as Map<String, Object?>;
    } on FormatException catch (error) {
      throw UnreadableVault('not JSON (${error.message})');
    } on TypeError {
      throw const UnreadableVault('not a JSON object');
    }

    final format = envelope['format'];
    if (format != envelopeFormat) {
      throw UnreadableVault('unsupported envelope format: $format');
    }

    final kdf = envelope['kdf'];
    final cipherSpec = envelope['cipher'];
    if (kdf is! Map<String, Object?> || cipherSpec is! Map<String, Object?>) {
      throw const UnreadableVault('missing kdf or cipher parameters');
    }
    if (kdf['algorithm'] != 'argon2id') {
      throw UnreadableVault('unsupported kdf: ${kdf['algorithm']}');
    }
    if (cipherSpec['algorithm'] != 'aes-gcm-256') {
      throw UnreadableVault('unsupported cipher: ${cipherSpec['algorithm']}');
    }

    final key = await _deriveKey(
      passphrase: passphrase,
      salt: base64.decode(kdf['salt']! as String),
      memory: kdf['memory']! as int,
      iterations: kdf['iterations']! as int,
      parallelism: kdf['parallelism']! as int,
    );

    final box = SecretBox(
      base64.decode(envelope['ciphertext']! as String),
      nonce: base64.decode(cipherSpec['nonce']! as String),
      mac: Mac(base64.decode(envelope['mac']! as String)),
    );

    final List<int> plaintext;
    try {
      plaintext = await _cipher.decrypt(box, secretKey: key);
    } on SecretBoxAuthenticationError {
      throw const WrongVaultPassphrase();
    }

    return Vault.fromJson(
      jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>,
    );
  }

  Future<SecretKey> _deriveKey({
    required String passphrase,
    required List<int> salt,
    required int memory,
    required int iterations,
    required int parallelism,
  }) {
    final kdf = Argon2id(
      memory: memory,
      iterations: iterations,
      parallelism: parallelism,
      hashLength: _keyLength,
    );

    return kdf.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
  }

  List<int> _randomBytes(int length) {
    return List<int>.generate(length, (_) => _random.nextInt(256));
  }
}
