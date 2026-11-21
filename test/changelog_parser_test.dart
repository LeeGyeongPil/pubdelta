import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

String fixture(String name) =>
    File('test/fixtures/changelogs/$name').readAsStringSync();

void main() {
  group('heading formats', () {
    final parsed = parseChangelog(fixture('formats.md'));
    Map<String, Section> byVersion() => {
      for (final s in parsed.sections) '${s.version}': s,
    };

    test('recognizes all seven version styles', () {
      expect(byVersion().keys.toSet(), {
        '1.6.0', // ## 1.6.0
        '3.5.0', // ## 3.5.0 - 2026-11-06
        '6.1.3', // ## 6.1.3 - date (retracted)
        '4.7.3', // ## [4.7.3]
        '1.2.0', // # v1.2.0
        '6.1.5+1', // build number
        '1.5.0-beta.2', // pre-release
      });
    });

    test('keeps the heading text as the title', () {
      expect(byVersion()['3.5.0']!.title, '3.5.0 - 2026-11-06');
      expect(byVersion()['4.7.3']!.title, '[4.7.3]');
    });

    test('keeps the retracted tag only where it is written', () {
      expect(byVersion()['6.1.3']!.tags, contains('retracted'));
      expect(byVersion()['1.6.0']!.tags, isEmpty);
    });

    test('non-version headings are skipped with notices', () {
      final keys = parsed.notices.map((n) => n.key).toList();
      expect(keys, contains('parse.skippedHeading')); // # CHANGELOG
      expect(keys, contains('parse.unreleased')); // ## Unreleased
      expect(
        parsed.sections.any((s) => s.lines.join().contains('not released yet')),
        isFalse,
        reason: 'the Unreleased section must not become an entry',
      );
    });

    test('a deeper sub heading stays inside the entry', () {
      final beta = byVersion()['1.5.0-beta.2']!;
      expect(beta.lines.join('\n'), contains('### Fixed'));
    });

    test('headings inside code fences are ignored', () {
      expect(byVersion().containsKey('9.9.9'), isFalse);
      expect(
        byVersion()['1.5.0-beta.2']!.lines.join('\n'),
        contains('fake heading'),
      );
    });

    test('body lines are trimmed of blank edges', () {
      final s = byVersion()['1.6.0']!;
      expect(s.lines, ['- Plain heading.']);
    });
  });

  group('file without version headings', () {
    test('falls back to the first 40 lines', () {
      final parsed = parseChangelog(fixture('no_headings.md'));
      expect(parsed.isFallback, isTrue);
      expect(parsed.fallbackLines, hasLength(fallbackLineCount));
      expect(parsed.fallbackLines.first, startsWith('Release notes'));
      expect(
        parsed.notices.map((n) => n.key),
        contains('parse.noVersionHeadings'),
      );
    });

    test('confidence is low and an entry carries the lines', () {
      final log = sliceChangelog(
        pkg: _pkg('nohead', '1.0.0'),
        from: Version.parse('1.0.0'),
        to: Version.parse('1.1.0'),
        fetched: FetchedChangelog(
          text: fixture('no_headings.md'),
          origin: Origin.dir,
        ),
      );
      expect(log.confidence, 'low');
      expect(log.entries, hasLength(1));
      expect(log.entries.single.body.split('\n'), hasLength(fallbackLineCount));
      expect(log.entries.single.fallbackLines, fallbackLineCount);
    });

    test('a short file reports the lines it really shows', () {
      final parsed = parseChangelog('just text\nno headings\n');
      expect(parsed.fallbackLines, ['just text', 'no headings']);
      expect(
        parsed.notices.single,
        const Notice('parse.noVersionHeadings', ['2']),
      );
    });

    test('an empty file gives a warning and no 0-line entry', () {
      for (final text in ['', '\n  \n\n']) {
        final parsed = parseChangelog(text);
        expect(parsed.isFallback, isTrue);
        expect(parsed.fallbackLines, isEmpty);
        expect(parsed.notices.single, const Notice('parse.empty'));
        final log = sliceChangelog(
          pkg: _pkg('empty', '1.0.0'),
          from: Version.parse('1.0.0'),
          to: Version.parse('1.1.0'),
          fetched: FetchedChangelog(text: text, origin: Origin.dir),
        );
        expect(log.confidence, 'low');
        expect(log.entries, isEmpty);
        expect(log.notices.map((n) => n.key), contains('parse.empty'));
      }
    });
  });

  // Q-18: 머리글 없는 변경 기록의 대체 항목 제목이 --lang ko 에서도 영어로 나오던 회귀.
  group('fallback entry title follows the language', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('pubdelta_fb_'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<(int, String)> log(String lang, String format) async {
      final (code, c) = await cli([
        'log',
        'http',
        '--to',
        '1.6.0',
        '--lock',
        'example/pubspec.lock',
        '--changelog-dir',
        dir.path,
        '--format',
        format,
        '--lang',
        lang,
      ]);
      return (code, c.out.toString());
    }

    test('text and md: Korean in ko, English in en', () async {
      File('${dir.path}/http.md').writeAsStringSync('just text\nno headings\n');
      for (final (lang, format, heading, warning) in [
        ('ko', 'text', '  == (앞 2줄)', '버전 머리글이 없어 앞 2줄만'),
        ('ko', 'md', '### (앞 2줄)', '버전 머리글이 없어 앞 2줄만'),
        ('en', 'text', '  == (first 2 lines)', 'showing the first 2 lines'),
        ('en', 'md', '### (first 2 lines)', 'showing the first 2 lines'),
      ]) {
        final (code, out) = await log(lang, format);
        expect(code, 0, reason: '$lang $format');
        expect(out.split('\n'), contains(heading), reason: '$lang $format');
        expect(out, contains(warning), reason: '$lang $format');
        expect(out, contains('just text'));
        if (lang == 'ko') {
          expect(out, isNot(contains('first 2 lines')), reason: format);
        }
      }
    });

    test('json keeps the language-independent title', () async {
      File('${dir.path}/http.md').writeAsStringSync('just text\nno headings\n');
      for (final lang in ['en', 'ko']) {
        final (code, out) = await log(lang, 'json');
        expect(code, 0);
        final pkg = (jsonDecode(out) as Map)['packages'][0] as Map;
        expect(pkg['confidence'], 'low');
        expect((pkg['entries'] as List).single['title'], '(first 2 lines)');
      }
    });

    test(
      'empty changelog: a warning in the chosen language, no entry',
      () async {
        File('${dir.path}/http.md').writeAsStringSync('');
        for (final (lang, warning) in [
          ('ko', 'CHANGELOG 가 비어 있어'),
          ('en', 'the CHANGELOG is empty'),
        ]) {
          final (code, out) = await log(lang, 'text');
          expect(code, 0);
          expect(out, contains(warning));
          expect(out, isNot(contains('==')), reason: lang);
          expect(out, isNot(contains('0 lines')));
          expect(out, isNot(contains('0줄')));
        }
      },
    );
  });

  group('real changelog excerpts', () {
    test('dio: preamble, Unreleased and versions', () {
      final parsed = parseChangelog(
        File('example/changelogs/dio.md').readAsStringSync(),
      );
      expect(parsed.sections.first.version.toString(), '5.11.1');
      expect(
        parsed.notices.map((n) => n.key),
        containsAll(['parse.skippedHeading', 'parse.unreleased']),
      );
    });

    test('provider: build number and retracted entry', () {
      final parsed = parseChangelog(
        File('example/changelogs/provider.md').readAsStringSync(),
      );
      final versions = parsed.sections.map((s) => '${s.version}').toList();
      expect(versions.take(4), ['6.1.5+1', '6.1.5', '6.1.4', '6.1.3']);
      expect(parsed.sections[3].tags, contains('retracted'));
    });

    test('get: bracketed versions', () {
      final parsed = parseChangelog(
        File('example/changelogs/get.md').readAsStringSync(),
      );
      expect(parsed.sections.first.version.toString(), '4.7.3');
    });
  });
}

LockedPackage _pkg(String name, String version) => LockedPackage(
  name: name,
  version: Version.parse(version),
  dependency: 'direct main',
  source: 'hosted',
  hostedUrl: 'https://pub.dev',
);
