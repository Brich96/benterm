import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:benterm/update/release_check.dart';
import 'package:benterm/update/update_downloader.dart';

String releaseJson({
  required String tag,
  List<String> assets = const ['benterm-windows-x64.zip', 'SHA256SUMS.txt'],
}) {
  return jsonEncode({
    'tag_name': tag,
    'body': 'Release notes for $tag',
    'assets': [
      for (final name in assets)
        {
          'name': name,
          'browser_download_url': 'https://example.invalid/$name',
          'size': 1234,
        },
    ],
  });
}

void main() {
  group('latest release', () {
    test('reads the tag, notes and assets', () async {
      final check = ReleaseCheck(
        client: MockClient((_) async => http.Response(releaseJson(tag: 'v0.3.0'), 200)),
      );

      final release = await check.latest();

      expect(release!.version, '0.3.0');
      expect(release.tag, 'v0.3.0');
      expect(release.notes, contains('Release notes'));
      expect(release.assetNamed('benterm-windows-x64.zip'), isNotNull);
      expect(release.checksums, isNotNull);
    });

    test('a repository with no releases yields null', () async {
      final check = ReleaseCheck(
        client: MockClient((_) async => http.Response('{"message":"Not Found"}', 404)),
      );

      expect(await check.latest(), isNull);
    });

    test('a rate limit is an error, not "no update"', () async {
      final check = ReleaseCheck(
        client: MockClient(
          (_) async => http.Response('{"message":"API rate limit exceeded"}', 403),
        ),
      );

      await expectLater(
        check.latest(),
        throwsA(
          isA<ReleaseCheckFailed>()
              .having((e) => e.statusCode, 'statusCode', 403)
              .having((e) => e.message, 'message', contains('rate limit')),
        ),
      );
    });

    test('a tag that is not a version is ignored', () async {
      final check = ReleaseCheck(
        client: MockClient((_) async => http.Response(releaseJson(tag: 'nightly'), 200)),
      );

      expect(await check.latest(), isNull);
    });

    test('is anonymous: no credentials are sent', () async {
      late http.Request seen;
      final check = ReleaseCheck(
        client: MockClient((request) async {
          seen = request;
          return http.Response(releaseJson(tag: 'v0.3.0'), 200);
        }),
      );

      await check.latest();

      expect(seen.headers.keys.map((k) => k.toLowerCase()),
          isNot(contains('authorization')));
    });
  });

  group('newerThan', () {
    Future<ReleaseInfo?> check(String tag, String current) {
      return ReleaseCheck(
        client: MockClient((_) async => http.Response(releaseJson(tag: tag), 200)),
      ).newerThan(current);
    }

    test('offers a newer release', () async {
      expect((await check('v0.3.0', '0.2.0'))!.version, '0.3.0');
    });

    test('stays quiet when already current', () async {
      expect(await check('v0.2.0', '0.2.0'), isNull);
    });

    test('stays quiet when running something newer', () async {
      expect(await check('v0.2.0', '0.3.0'), isNull);
    });
  });

  group('downloading', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('benterm-update'));
    tearDown(() => temp.deleteSync(recursive: true));

    const payload = 'pretend this is a zip';
    // sha256 of `payload`.
    const payloadDigest =
        '767b91e9bc138ebb2fdd7aa147ade085d0c257404d1abc83ce8861fc8f6a88eb';

    ReleaseAsset asset() => ReleaseAsset(
      name: 'benterm-windows-x64.zip',
      url: Uri.parse('https://example.invalid/benterm-windows-x64.zip'),
      size: payload.length,
    );

    test('saves the file and reports progress', () async {
      final downloader = UpdateDownloader(
        client: MockClient((_) async => http.Response(payload, 200)),
      );

      var lastReceived = 0;
      final file = await downloader.download(
        asset(),
        into: temp,
        onProgress: (received, _) => lastReceived = received,
      );

      expect(file.readAsStringSync(), payload);
      expect(lastReceived, payload.length);
    });

    test('accepts a file matching its checksum', () async {
      final downloader = UpdateDownloader(
        client: MockClient((_) async => http.Response(payload, 200)),
      );

      final file = await downloader.download(
        asset(),
        into: temp,
        expected: payloadDigest,
      );

      expect(file.existsSync(), isTrue);
    });

    test('rejects and deletes a file that fails its checksum', () async {
      final downloader = UpdateDownloader(
        client: MockClient((_) async => http.Response('tampered', 200)),
      );

      await expectLater(
        downloader.download(asset(), into: temp, expected: payloadDigest),
        throwsA(isA<ChecksumMismatch>()),
      );

      // Nothing is left behind for an installer to pick up by mistake.
      expect(temp.listSync(), isEmpty);
    });

    test('parses the published checksum file', () async {
      final downloader = UpdateDownloader(
        client: MockClient(
          (_) async => http.Response(
            '$payloadDigest  benterm-windows-x64.zip\n'
            'aaaa  benterm-android.apk\n',
            200,
          ),
        ),
      );

      final digests = await downloader.checksums(
        ReleaseInfo(
          tag: 'v0.3.0',
          version: '0.3.0',
          notes: '',
          assets: [
            ReleaseAsset(
              name: 'SHA256SUMS.txt',
              url: Uri.parse('https://example.invalid/SHA256SUMS.txt'),
              size: 100,
            ),
          ],
        ),
      );

      expect(digests['benterm-windows-x64.zip'], payloadDigest);
      expect(digests['benterm-android.apk'], 'aaaa');
    });

    test('a release without checksums yields no digests', () async {
      final downloader = UpdateDownloader(client: MockClient((_) async {
        fail('should not fetch anything');
      }));

      final digests = await downloader.checksums(
        const ReleaseInfo(tag: 'v0.1.0', version: '0.1.0', notes: '', assets: []),
      );

      expect(digests, isEmpty);
    });
  });
}
