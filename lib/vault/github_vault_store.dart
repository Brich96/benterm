import 'dart:convert';

import 'package:http/http.dart' as http;

/// Where the encrypted vault lives on GitHub.
class GithubVaultLocation {
  const GithubVaultLocation({
    required this.owner,
    required this.repo,
    required this.token,
    this.path = 'vault.json',
    this.branch,
  });

  final String owner;
  final String repo;

  /// Fine-grained personal access token, scoped to this repo only.
  final String token;

  final String path;
  final String? branch;

  Uri get contentsUri => Uri.https(
    'api.github.com',
    '/repos/$owner/$repo/contents/$path',
    branch == null ? null : {'ref': branch},
  );
}

/// A vault blob plus the GitHub blob `sha` it was read at.
///
/// The sha is the write precondition: passing back the one you read is what
/// makes a concurrent write fail loudly instead of silently clobbering.
class RemoteVault {
  const RemoteVault({required this.contents, required this.sha});

  final String contents;
  final String sha;
}

/// Raised when the remote vault moved on since it was read.
class VaultConflict implements Exception {
  const VaultConflict();

  @override
  String toString() =>
      'The vault changed on GitHub since it was last fetched; '
      'pull the current version before writing';
}

/// Raised for auth, permission, and other non-conflict API failures.
class GithubVaultError implements Exception {
  const GithubVaultError(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'GitHub API error $statusCode: $message';
}

/// Reads and writes the encrypted vault through GitHub's Contents API.
///
/// Plain HTTPS — no git binary, no embedded git library. The vault is one
/// small blob, so real git semantics would buy nothing.
class GithubVaultStore {
  GithubVaultStore({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Map<String, String> _headers(GithubVaultLocation location) => {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer ${location.token}',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  /// Fetches the current vault, or null if the file does not exist yet.
  Future<RemoteVault?> fetch(GithubVaultLocation location) async {
    final response = await _client.get(
      location.contentsUri,
      headers: _headers(location),
    );

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw GithubVaultError(response.statusCode, _errorMessage(response));
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final encoding = json['encoding'];
    if (encoding != 'base64') {
      // Files over 1MB come back without content and need the blobs API.
      throw GithubVaultError(
        response.statusCode,
        'unexpected content encoding: $encoding',
      );
    }

    // GitHub wraps base64 content at 60 columns.
    final content = (json['content']! as String).replaceAll('\n', '');

    return RemoteVault(
      contents: utf8.decode(base64.decode(content)),
      sha: json['sha']! as String,
    );
  }

  /// Writes [contents], requiring the remote to still be at [sha].
  ///
  /// Pass a null [sha] only when creating the file for the first time.
  /// Throws [VaultConflict] if someone else wrote first.
  Future<String> write(
    GithubVaultLocation location, {
    required String contents,
    required String? sha,
    String message = 'Update vault',
  }) async {
    final response = await _client.put(
      location.contentsUri,
      headers: {
        ..._headers(location),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'message': message,
        'content': base64.encode(utf8.encode(contents)),
        'sha': ?sha,
        'branch': ?location.branch,
      }),
    );

    // 409 is the documented conflict; 422 covers "sha wasn't supplied or
    // didn't match" for an existing file, which is the same situation.
    if (response.statusCode == 409 ||
        (response.statusCode == 422 && sha != null)) {
      throw const VaultConflict();
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw GithubVaultError(response.statusCode, _errorMessage(response));
    }

    final json = jsonDecode(response.body) as Map<String, Object?>;
    final content = json['content']! as Map<String, Object?>;
    return content['sha']! as String;
  }

  void close() => _client.close();

  String _errorMessage(http.Response response) {
    try {
      final json = jsonDecode(response.body) as Map<String, Object?>;
      return json['message'] as String? ?? response.reasonPhrase ?? 'unknown';
    } on FormatException {
      return response.reasonPhrase ?? 'unknown';
    }
  }
}
