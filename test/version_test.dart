import 'package:flutter_test/flutter_test.dart';

import 'package:benterm/update/version.dart';

void main() {
  group('parsing', () {
    test('accepts a plain version', () {
      expect(Version.tryParse('1.2.3').toString(), '1.2.3');
    });

    test('accepts a release tag', () {
      expect(Version.tryParse('v0.2.0').toString(), '0.2.0');
    });

    test('fills in missing components', () {
      expect(Version.tryParse('2').toString(), '2.0.0');
      expect(Version.tryParse('2.1').toString(), '2.1.0');
    });

    test('ignores pre-release and build suffixes', () {
      expect(Version.tryParse('1.2.3-beta.1').toString(), '1.2.3');
      expect(Version.tryParse('1.2.3+45').toString(), '1.2.3');
    });

    test('rejects what is not a version', () {
      for (final text in ['', 'latest', 'v', '1.2.3.4', '1.x.0', '-1.0.0']) {
        expect(Version.tryParse(text), isNull, reason: text);
      }
    });
  });

  group('comparison', () {
    test('orders by each component in turn', () {
      expect(isNewer('1.0.0', '0.9.9'), isTrue);
      expect(isNewer('0.3.0', '0.2.9'), isTrue);
      expect(isNewer('0.2.2', '0.2.1'), isTrue);
    });

    test('compares numerically, not as text', () {
      // The trap: '0.10.0' sorts before '0.2.0' as a string.
      expect(isNewer('0.10.0', '0.2.0'), isTrue);
      expect(isNewer('0.2.0', '0.10.0'), isFalse);
      expect(isNewer('1.0.0', '0.100.0'), isTrue);
    });

    test('an identical version is not newer', () {
      expect(isNewer('0.2.0', '0.2.0'), isFalse);
      expect(isNewer('v0.2.0', '0.2.0'), isFalse);
    });

    test('an older version is not newer', () {
      expect(isNewer('0.1.0', '0.2.0'), isFalse);
    });

    test('unparseable input never triggers an update', () {
      expect(isNewer('nightly', '0.2.0'), isFalse);
      expect(isNewer('0.3.0', 'unknown'), isFalse);
    });
  });
}
