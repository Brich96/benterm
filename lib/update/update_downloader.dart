import 'dart:convert';
import 'dart:io';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'package:benterm/update/release_check.dart';

/// Raised when a downloaded file does not match its published checksum.
///
/// The download is discarded rather than installed: a truncated or corrupt
/// binary that replaced a working install would be worse than no update.
class ChecksumMismatch implements Exception {
  const ChecksumMismatch({
    required this.name,
    required this.expected,
    required this.actual,
  });

  final String name;
  final String expected;
  final String actual;

  @override
  String toString() =>
      '$name does not match its published checksum '
      '(expected $expected, got $actual)';
}

/// Raised when a release is missing the file this platform needs.
class MissingReleaseAsset implements Exception {
  const MissingReleaseAsset(this.name);

  final String name;

  @override
  String toString() => 'This release has no $name to install';
}

/// Fetches release assets and checks them against the published checksums.
class UpdateDownloader {
  UpdateDownloader({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Parses `SHA256SUMS.txt` into a map of file name to digest.
  ///
  /// Returns an empty map when the release predates checksum publishing, so
  /// an older release can still be installed — just unverified.
  Future<Map<String, String>> checksums(ReleaseInfo release) async {
    final asset = release.checksums;
    if (asset == null) return const {};

    final response = await _client.get(asset.url);
    if (response.statusCode != 200) return const {};

    final digests = <String, String>{};
    for (final line in const LineSplitter().convert(response.body)) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) continue;
      // `sha256sum` writes "<digest>  <name>", the name possibly with a
      // leading '*' for binary mode.
      digests[parts.last.replaceFirst(RegExp(r'^\*'), '')] = parts.first;
    }
    return digests;
  }

  /// Downloads [asset] into [into], reporting progress as bytes arrive.
  ///
  /// Verifies the result against [expected] when a digest is known.
  Future<File> download(
    ReleaseAsset asset, {
    required Directory into,
    String? expected,
    void Function(int received, int total)? onProgress,
  }) async {
    await into.create(recursive: true);
    final target = File('${into.path}${Platform.pathSeparator}${asset.name}');

    final request = http.Request('GET', asset.url);
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw ReleaseCheckFailed(
        response.statusCode,
        'could not download ${asset.name}',
      );
    }

    final total = response.contentLength ?? asset.size;
    final sink = target.openWrite();
    var received = 0;
    try {
      await response.stream
          .map((chunk) {
            received += chunk.length;
            onProgress?.call(received, total);
            return chunk;
          })
          .pipe(sink);
    } finally {
      await sink.close();
    }

    if (expected != null) {
      final actual = await digestOf(target);
      if (actual != expected.toLowerCase()) {
        await target.delete();
        throw ChecksumMismatch(
          name: asset.name,
          expected: expected.toLowerCase(),
          actual: actual,
        );
      }
    }

    return target;
  }

  /// SHA-256 of a file, streamed so a large artifact is not held in memory.
  static Future<String> digestOf(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    final digest = output.events.single;
    output.close();
    return digest.toString();
  }

  void close() => _client.close();
}
