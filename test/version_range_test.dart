import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

Version v(String s) => Version.parse(s);

void main() {
  group('Dart version ordering (pub_semver)', () {
    test('pre-release sorts before the release, build after', () {
      final sorted =
          [
              '1.5.0',
              '6.1.5+1',
              '1.5.0-beta.2',
              '0.13.6',
              '6.1.5',
              '1.5.0-beta',
            ].map(v).toList()
            ..sort();
      expect(sorted.map((e) => '$e').toList(), [
        '0.13.6',
        '1.5.0-beta',
        '1.5.0-beta.2',
        '1.5.0',
        '6.1.5',
        '6.1.5+1',
      ]);
    });

    test('6.1.5 < 6.1.5+1 and 1.5.0-beta < 1.5.0-beta.2 < 1.5.0', () {
      expect(v('6.1.5') < v('6.1.5+1'), isTrue);
      expect(v('1.5.0-beta') < v('1.5.0-beta.2'), isTrue);
      expect(v('1.5.0-beta.2') < v('1.5.0'), isTrue);
    });
  });

  group('inRange is (from, to]', () {
    final from = v('1.2.2');
    final to = v('1.6.0');

    test('excludes from, includes to', () {
      expect(inRange(from, from, to), isFalse);
      expect(inRange(to, from, to), isTrue);
    });

    test('keeps versions in between and drops outside ones', () {
      expect(inRange(v('1.3.0'), from, to), isTrue);
      expect(inRange(v('1.2.1'), from, to), isFalse);
      expect(inRange(v('1.6.1'), from, to), isFalse);
    });

    test('build number and pre-release positions', () {
      expect(inRange(v('6.1.5+1'), v('6.1.5'), v('6.1.5+1')), isTrue);
      expect(inRange(v('6.1.5'), v('6.1.5'), v('6.1.5+1')), isFalse);
      expect(inRange(v('1.5.0-beta'), v('1.4.0'), v('1.5.0')), isTrue);
    });
  });

  group('classifyBump', () {
    test('major, minor, patch', () {
      expect(classifyBump(v('1.2.2'), v('2.0.0')), Bump.major);
      expect(classifyBump(v('1.2.2'), v('1.6.0')), Bump.minor);
      expect(classifyBump(v('6.1.2'), v('6.1.5')), Bump.patch);
    });

    test('0.x: a minor step is the breaking unit (major)', () {
      expect(classifyBump(v('0.13.6'), v('0.14.0')), Bump.major);
      expect(classifyBump(v('0.13.6'), v('0.13.9')), Bump.patch);
      expect(classifyBump(v('0.9.0'), v('1.0.0')), Bump.major);
    });

    test('pre-release, build and equal', () {
      expect(classifyBump(v('1.5.0-beta'), v('1.5.0')), Bump.prerelease);
      expect(classifyBump(v('6.1.5'), v('6.1.5+1')), Bump.build);
      expect(classifyBump(v('1.0.0'), v('1.0.0')), Bump.none);
    });
  });

  group('input errors', () {
    test('to lower than from is an input error (exit 3)', () {
      expect(
        () => validateRange(v('2.0.0'), v('1.0.0'), package: 'x'),
        throwsA(
          isA<PubdeltaException>()
              .having((e) => e.exitCode, 'exitCode', 3)
              .having((e) => e.toString(), 'message', contains('lower')),
        ),
      );
    });

    test('equal versions are accepted', () {
      validateRange(v('1.0.0'), v('1.0.0'));
    });

    test('unreadable version is an input error with the flag name', () {
      expect(
        () => parseVersion('abc', what: '--to'),
        throwsA(
          isA<PubdeltaException>()
              .having((e) => e.exitCode, 'exitCode', 3)
              .having((e) => e.toString(), 'message', contains('--to')),
        ),
      );
    });
  });
}
