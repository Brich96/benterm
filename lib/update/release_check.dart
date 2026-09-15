import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:benterm/update/version.dart';

/// A downloadable file attached to a release.
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.url,
    required this.size,
  });

  final String name;
  final Uri url;
  final int size;
}

/// The latest published release, as GitHub describes it.
class ReleaseInfo {
  const ReleaseInfo({
    required this.tag,
    required this.version,
    required this.notes,
    required this.assets,
  });

  final String tag;
  final String version;
  final String notes;
  final List<ReleaseAsset> assets;

  ReleaseAsset? assetNamed(String name) {
    for (final asset in assets) {
      if (asset.name == name) return asset;
    }
    return null;
  }

  /// The published checksums, if CI attached them.
  ReleaseAsset? get checksums => assetNamed('SHA256SUMS.txt');
}

/// Raised when GitHub cannot be asked about releases.
class ReleaseCheckFailed implements Exception {
  const ReleaseCheckFailed(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'Update check failed ($statusCode): $message';
}

/// Asks GitHub what the newest release is.
///
/// Anonymous: the repository is public, so no token is involved and none is
/// stored on the device.
class ReleaseCheck {
  ReleaseCheck({
    http.Client? client,
    this.owner = 'Brich96',
    this.repo = 'benterm',
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String owner;
  final String repo;

  /// Returns the latest release, or null if the repository has none yet.
  Future<ReleaseInfo?> latest() async {
    final response = await _client.get(
      Uri.https('api.github.com', '/repos/$owner/$repo/releases/latest'),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ReleaseCheckFailed(response.statusCode, _message(response));
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final tag = json['tag_name'] as String? ?? '';
    final parsed = Version.tryParse(tag);
    if (parsed == null) return null;

    return ReleaseInfo(
      tag: tag,
      version: parsed.toString(),
      notes: json['body'] as String? ?? '',
      assets: [
        for (final asset
            in (json['assets'] as List<Object?>? ?? const [])
                .cast<Map<String, Object?>>())
          ReleaseAsset(
            name: asset['name']! as String,
            url: Uri.parse(asset['browser_download_url']! as String),
            size: asset['size'] as int? ?? 0,
          ),
      ],
    );
  }

  /// The release to offer, or null when [currentVersion] is already current.
  Future<ReleaseInfo?> newerThan(String currentVersion) async {
    final release = await latest();
    if (release == null) return null;
    return isNewer(release.version, currentVersion) ? release : null;
  }

  void close() => _client.close();

  String _message(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return json['message'] as String? ?? response.reasonPhrase ?? 'unknown';
    } on FormatException {
      return response.reasonPhrase ?? 'unknown';
    }
  }
}
