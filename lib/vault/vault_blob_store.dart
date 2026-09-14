import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Local persistence for the encrypted vault blob and the GitHub `sha` it
/// was last synced at.
///
/// Only ever holds ciphertext: the passphrase is never written here.
abstract class VaultBlobStore {
  Future<String?> readBlob();

  Future<void> writeBlob(String blob);

  /// The blob sha this device's copy came from, or null if never synced.
  Future<String?> readSha();

  Future<void> writeSha(String? sha);

  Future<void> clear();
}

/// Stores the blob in the platform's application support directory.
class FileVaultBlobStore implements VaultBlobStore {
  FileVaultBlobStore({this.fileName = 'vault.json'});

  final String fileName;

  Directory? _directory;

  Future<Directory> _dir() async {
    return _directory ??= await getApplicationSupportDirectory();
  }

  Future<File> _blobFile() async => File('${(await _dir()).path}/$fileName');

  Future<File> _metaFile() async =>
      File('${(await _dir()).path}/$fileName.meta');

  @override
  Future<String?> readBlob() async {
    final file = await _blobFile();
    return file.existsSync() ? file.readAsString() : null;
  }

  @override
  Future<void> writeBlob(String blob) async {
    final file = await _blobFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(blob, flush: true);
  }

  @override
  Future<String?> readSha() async {
    final file = await _metaFile();
    if (!file.existsSync()) return null;
    final json = jsonDecode(await file.readAsString()) as Map<String, Object?>;
    return json['sha'] as String?;
  }

  @override
  Future<void> writeSha(String? sha) async {
    final file = await _metaFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode({'sha': sha}), flush: true);
  }

  @override
  Future<void> clear() async {
    for (final file in [await _blobFile(), await _metaFile()]) {
      if (file.existsSync()) await file.delete();
    }
  }
}

/// In-memory store, for tests and for running without a writable directory.
class MemoryVaultBlobStore implements VaultBlobStore {
  String? _blob;
  String? _sha;

  @override
  Future<String?> readBlob() async => _blob;

  @override
  Future<void> writeBlob(String blob) async => _blob = blob;

  @override
  Future<String?> readSha() async => _sha;

  @override
  Future<void> writeSha(String? sha) async => _sha = sha;

  @override
  Future<void> clear() async {
    _blob = null;
    _sha = null;
  }
}
