import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:benterm/vault/github_vault_store.dart';

void main() {
  const location = GithubVaultLocation(
    owner: 'ben',
    repo: 'ssh-vault',
    token: 'ghp_example',
    path: 'vault.json',
  );

  test('fetch decodes base64 content and returns the sha', () async {
    late http.Request seen;
    final store = GithubVaultStore(
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            // GitHub wraps base64 at 60 columns.
            'content': '${base64.encode(utf8.encode('{"hello":"world"}'))}\n',
            'encoding': 'base64',
            'sha': 'abc123',
          }),
          200,
        );
      }),
    );

    final remote = await store.fetch(location);

    expect(remote!.contents, '{"hello":"world"}');
    expect(remote.sha, 'abc123');
    expect(seen.url.path, '/repos/ben/ssh-vault/contents/vault.json');
    expect(seen.headers['Authorization'], 'Bearer ghp_example');
  });

  test('fetch returns null when the vault does not exist yet', () async {
    final store = GithubVaultStore(
      client: MockClient((_) async => http.Response('{"message":"Not Found"}', 404)),
    );

    expect(await store.fetch(location), isNull);
  });

  test('fetch surfaces a bad token as an error, not an empty vault', () async {
    final store = GithubVaultStore(
      client: MockClient(
        (_) async => http.Response('{"message":"Bad credentials"}', 401),
      ),
    );

    await expectLater(
      store.fetch(location),
      throwsA(
        isA<GithubVaultError>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Bad credentials'),
      ),
    );
  });

  test('write sends the sha as a precondition', () async {
    late Map<String, Object?> body;
    final store = GithubVaultStore(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'content': {'sha': 'def456'},
          }),
          200,
        );
      }),
    );

    final sha = await store.write(
      location,
      contents: 'encrypted-blob',
      sha: 'abc123',
    );

    expect(sha, 'def456');
    expect(body['sha'], 'abc123');
    expect(utf8.decode(base64.decode(body['content']! as String)),
        'encrypted-blob');
  });

  test('write omits the sha when creating the file', () async {
    late Map<String, Object?> body;
    final store = GithubVaultStore(
      client: MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'content': {'sha': 'new123'},
          }),
          201,
        );
      }),
    );

    await store.write(location, contents: 'blob', sha: null);

    expect(body.containsKey('sha'), isFalse);
  });

  test('a concurrent write is reported as a conflict', () async {
    for (final status in [409, 422]) {
      final store = GithubVaultStore(
        client: MockClient(
          (_) async => http.Response('{"message":"does not match"}', status),
        ),
      );

      await expectLater(
        store.write(location, contents: 'blob', sha: 'stale'),
        throwsA(isA<VaultConflict>()),
        reason: 'status $status should be a conflict',
      );
    }
  });

  test('a 422 while creating is an error, not a conflict', () async {
    // With no sha there is nothing to conflict with, so 422 means the
    // request itself was rejected and must not be reported as a race.
    final store = GithubVaultStore(
      client: MockClient(
        (_) async => http.Response('{"message":"Invalid request"}', 422),
      ),
    );

    await expectLater(
      store.write(location, contents: 'blob', sha: null),
      throwsA(isA<GithubVaultError>()),
    );
  });

  test('branch is passed through on both read and write', () async {
    const branched = GithubVaultLocation(
      owner: 'ben',
      repo: 'ssh-vault',
      token: 't',
      branch: 'main',
    );
    late Uri readUrl;
    late Map<String, Object?> body;

    final store = GithubVaultStore(
      client: MockClient((request) async {
        if (request.method == 'GET') {
          readUrl = request.url;
          return http.Response('{"message":"Not Found"}', 404);
        }
        body = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode({
            'content': {'sha': 's'},
          }),
          201,
        );
      }),
    );

    await store.fetch(branched);
    await store.write(branched, contents: 'blob', sha: null);

    expect(readUrl.queryParameters['ref'], 'main');
    expect(body['branch'], 'main');
  });
}
