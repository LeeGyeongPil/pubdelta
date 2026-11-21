import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

/// Slices a real changelog excerpt from example/changelogs.
PackageLog slice(String name, String from, String to) {
  final text = File('example/changelogs/$name.md').readAsStringSync();
  return sliceChangelog(
    pkg: LockedPackage(
      name: name,
      version: Version.parse(from),
      dependency: 'direct main',
      source: 'hosted',
      hostedUrl: 'https://pub.dev',
    ),
    from: Version.parse(from),
    to: Version.parse(to),
    fetched: FetchedChangelog(text: text, origin: Origin.dir),
  );
}

Entry entry(PackageLog log, String version) =>
    log.entries.singleWhere((e) => '${e.version}' == version);

void main() {
  group('real changelog excerpts', () {
    test(
      'http 1.2.2 -> 1.6.0 is a minor bump with a strong signal in 1.6.0',
      () {
        final log = slice('http', '1.2.2', '1.6.0');
        expect(log.bump, Bump.minor);
        final e = entry(log, '1.6.0');
        expect(e.strongest, SignalLevel.strong);
        expect(e.signals.first.line, contains('**Breaking**'));
        expect(entry(log, '1.5.0').signals, isEmpty);
      },
    );

    test(
      'firebase_core 5.0.0: melos note and **BREAKING** lines are strong',
      () {
        final log = slice('firebase_core', '4.14.0', '5.2.0');
        final e = entry(log, '5.0.0');
        final strong =
            e.signals.where((s) => s.level == SignalLevel.strong).toList();
        expect(strong.length, 3);
        expect(
          strong.first.line,
          contains('This release has breaking changes'),
        );
        expect(e.major, isTrue);
      },
    );

    test('lints 5.0.0: "removed" is medium', () {
      final log = slice('lints', '4.0.0', '6.1.0');
      final e = entry(log, '5.0.0');
      expect(e.strongest, SignalLevel.medium);
      expect(e.signals.single.line, contains('removed'));
      expect(
        e.signals.single.line,
        contains('avoid_null_checks_in_equality_operators'),
      );
    });

    test('dio: the preamble and "breaking any" prose give no signal', () {
      final log = slice('dio', '5.9.2', '5.11.1');
      expect(log.entries, isNotEmpty);
      for (final e in log.entries) {
        expect(e.signals, isEmpty, reason: '${e.version} must have no signal');
      }
      // The preamble sentence really exists in the file.
      expect(
        File('example/changelogs/dio.md').readAsStringSync(),
        contains('Breaking changes might happen'),
      );
      expect(
        File('example/changelogs/dio.md').readAsStringSync(),
        contains('breaking any'),
      );
    });

    test('riverpod 3.5.0: "Fix the deprecated" is weak, nothing stronger', () {
      final log = slice('riverpod', '3.4.0', '3.5.0');
      final e = entry(log, '3.5.0');
      expect(e.strongest, SignalLevel.weak);
      expect(
        e.signals.any((s) => s.line.contains('Fix the deprecated')),
        isTrue,
      );
    });
  });

  group('detectSignals rules', () {
    test('bold Breaking, upper case BREAKING and a Breaking sub heading', () {
      expect(
        detectSignals(['* **Breaking** x']).single.level,
        SignalLevel.strong,
      );
      expect(detectSignals(['- BREAKING: x']).single.level, SignalLevel.strong);
      expect(
        detectSignals(['### Breaking Changes']).single.level,
        SignalLevel.strong,
      );
    });

    test('the bare lower case word "breaking" is not a signal', () {
      expect(detectSignals(['This stopped breaking any caller.']), isEmpty);
    });

    test('"breaking changes" is medium, but "no breaking changes" is not', () {
      expect(
        detectSignals(['This has breaking changes in the API.']).single.level,
        SignalLevel.medium,
      );
      expect(detectSignals(['There are no breaking changes.']), isEmpty);
    });

    test('nested removal list item is medium; Deprecated is weak', () {
      expect(
        detectSignals(['  - removed foo']).single.level,
        SignalLevel.medium,
      );
      expect(
        detectSignals(['- Deprecated bar']).single.level,
        SignalLevel.weak,
      );
    });

    test('one signal per line, the strongest wins', () {
      final s = detectSignals(['- **BREAKING** removed the deprecated API']);
      expect(s, hasLength(1));
      expect(s.single.level, SignalLevel.strong);
    });

    test('shortenLinks and cleanSignalLine', () {
      const raw =
          ' - **FIX**: x ([#1](https://github.com/o/r/issues/1)). ([d0fec9cc](https://github.com/o/r/commit/d0fec9cc817e))';
      expect(shortenLinks(raw), contains('(#1)'));
      expect(shortenLinks(raw), isNot(contains('https')));
      expect(cleanSignalLine(raw), startsWith('**FIX**'));
    });
  });
}
