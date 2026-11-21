import 'dart:convert';
import 'dart:io';

import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// Arguments of the start command (practice mock: sample files in example/).
const startArgs = [
  'log',
  '--all',
  '--lock',
  'example/pubspec.lock',
  '--outdated',
  'example/outdated.json',
  '--changelog-dir',
  'example/changelogs',
  '--budget',
  '2500',
];

void main() {
  group('start command (practice mock)', () {
    test('shows http 1.2.2 → 1.6.0 and a Breaking line, exit 0', () async {
      final (code, c) = await cli(startArgs);
      expect(code, 0);
      final out = c.out.toString();
      expect(out, contains('http 1.2.2 → 1.6.0'));
      final lines = out.split('\n');
      final header = lines.indexWhere(
        (l) => l.startsWith('http 1.2.2 → 1.6.0'),
      );
      expect(
        lines[header + 1],
        contains('Breaking'),
        reason: 'the first line under the header is the strong signal',
      );
      expect(out, contains('estimated tokens:'));
      expect(
        c.err.toString(),
        contains('sample data'),
        reason: 'the mock nature is stated',
      );
    });

    test('--fail-on breaking exits 1', () async {
      final (code, c) = await cli([...startArgs, '--fail-on', 'breaking']);
      expect(code, 1);
      expect(c.err.toString(), contains('http'));
      expect(c.err.toString(), contains('firebase_core'));
    });

    test('--fail-on major exits 1; none exits 0', () async {
      expect((await cli([...startArgs, '--fail-on', 'major'])).$1, 1);
      expect((await cli([...startArgs, '--fail-on', 'none'])).$1, 0);
    });

    test('--fail-on breaking passes when no strong signal exists', () async {
      final (code, _) = await cli([
        'log',
        'dio',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
        '--changelog-dir',
        'example/changelogs',
        '--fail-on',
        'breaking',
      ]);
      expect(code, 0);
    });

    test('works as a real process (dart bin/pubdelta.dart)', () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['bin/pubdelta.dart', ...startArgs],
        environment: {'LANG': 'C'},
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect('${result.stdout}', contains('http 1.2.2 → 1.6.0'));
      expect('${result.stdout}', contains('Breaking'));
    });
  });

  group('log <package>', () {
    test(
      'log http --to 1.6.0: signal first, then 1.6.0..1.3.0, no 1.2.2',
      () async {
        final (code, c) = await cli([
          'log',
          'http',
          '--to',
          '1.6.0',
          '--lock',
          'example/pubspec.lock',
          '--changelog-dir',
          'example/changelogs',
        ]);
        expect(code, 0);
        final out = c.out.toString();
        expect(out, startsWith('http 1.2.2 → 1.6.0 (minor)'));
        expect(
          out.split('\n')[1],
          startsWith('  ! STRONG 1.6.0: **Breaking**'),
        );
        final headings = RegExp(
          r'^  == (\S+)$',
          multiLine: true,
        ).allMatches(out).map((m) => m[1]);
        expect(headings.toList(), ['1.6.0', '1.5.0', '1.4.0', '1.3.0']);
      },
    );

    test('explicit --to makes no call to pub outdated', () async {
      var calls = 0;
      final (code, _) = await cli(
        [
          'log',
          'http',
          '--to',
          '1.6.0',
          '--lock',
          'example/pubspec.lock',
          '--changelog-dir',
          'example/changelogs',
        ],
        runner: (exe, args, {workingDirectory, environment}) async {
          calls++;
          return ProcessResult(1, 1, '', 'should not run');
        },
      );
      expect(code, 0);
      expect(calls, 0);
    });

    test(
      'provider --to 6.1.5+1: order 6.1.5+1, 6.1.5, 6.1.4, 6.1.3 (retracted)',
      () async {
        final (code, c) = await cli([
          'log',
          'provider',
          '--to',
          '6.1.5+1',
          '--lock',
          'example/pubspec.lock',
          '--changelog-dir',
          'example/changelogs',
        ]);
        expect(code, 0);
        final out = c.out.toString();
        final headings = RegExp(
          r'^  == (.+)$',
          multiLine: true,
        ).allMatches(out).map((m) => m[1]!);
        expect(headings.map((h) => h.split(' ').first).toList(), [
          '6.1.5+1',
          '6.1.5',
          '6.1.4',
          '6.1.3',
        ]);
        expect(headings.last, contains('retracted'));
        expect(out, isNot(contains('6.1.2 -')));
      },
    );

    test('from/to flags work together', () async {
      final (code, c) = await cli([
        'log',
        'http',
        '--from',
        '1.3.0',
        '--to',
        '1.5.0',
        '--lock',
        'example/pubspec.lock',
        '--changelog-dir',
        'example/changelogs',
      ]);
      expect(code, 0);
      final headings = RegExp(
        r'^  == (\S+)$',
        multiLine: true,
      ).allMatches(c.out.toString()).map((m) => m[1]);
      expect(headings.toList(), ['1.5.0', '1.4.0']);
    });

    test('a package that is already at its target says so', () async {
      final (code, c) = await cli([
        'log',
        'http',
        '--to',
        '1.2.2',
        '--lock',
        'example/pubspec.lock',
        '--changelog-dir',
        'example/changelogs',
      ]);
      expect(code, 0);
      expect(c.err.toString(), contains('already at the target'));
    });
  });

  group('formats', () {
    test('md has headings and the omitted note', () async {
      final (_, c) = await cli([
        ...startArgs.sublist(0, startArgs.length - 1),
        '700',
        '--format',
        'md',
      ]);
      final out = c.out.toString();
      expect(out, startsWith('# Upgrade notes'));
      expect(out, contains('## http 1.2.2 → 1.6.0 (minor)'));
      expect(out, contains('> omitted:'));
    });

    test('json is valid and complete', () async {
      final (_, c) = await cli([...startArgs, '--format', 'json']);
      final json = jsonDecode(c.out.toString()) as Map<String, Object?>;
      expect(json['schema'], 1);
      final packages = json['packages'] as List<Object?>;
      final http = packages.cast<Map<String, Object?>>().singleWhere(
        (p) => p['name'] == 'http',
      );
      expect(http['from'], '1.2.2');
      expect(http['to'], '1.6.0');
      expect(http['confidence'], 'high');
      final entries = http['entries'] as List<Object?>;
      final first = entries.first as Map<String, Object?>;
      expect(first['version'], '1.6.0');
      expect(
        (first['signals'] as List<Object?>).first,
        containsPair('level', 'strong'),
      );
      expect(json.containsKey('omitted'), isTrue);
      expect(json['estimatedTokens'], isA<int>());
    });

    test('without --budget nothing is omitted', () async {
      final (_, c) = await cli([
        'log',
        '--all',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
        '--changelog-dir',
        'example/changelogs',
      ]);
      expect(c.out.toString(), isNot(contains('omitted:')));
    });
  });

  group('errors', () {
    test('usage errors exit 2', () async {
      for (final args in [
        ['log'],
        ['log', '--all', 'http'],
        ['log', '--all', '--to', '1.0.0'],
        ['log', 'http', 'dio', '--to', '1.0.0'],
        ['log', 'http', '--budget', 'abc'],
        ['log', 'http', '--budget', '0'],
        ['log', 'http', '--nope'],
        ['log', 'http', '--mode', 'sideways'],
        ['plan', 'extra'],
        ['frobnicate'],
        <String>[],
      ]) {
        final (code, c) = await cli(args);
        expect(code, 2, reason: args.join(' '));
        expect('${c.err}${c.out}', isNotEmpty);
      }
    });

    test('unknown package exits 3 and names it', () async {
      final (code, c) = await cli([
        'log',
        'nope',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
      ]);
      expect(code, 3);
      expect(c.err.toString(), contains('"nope"'));
    });

    test('--to lower than --from exits 3', () async {
      final (code, c) = await cli([
        'log',
        'http',
        '--to',
        '1.0.0',
        '--lock',
        'example/pubspec.lock',
        '--changelog-dir',
        'example/changelogs',
      ]);
      expect(code, 3);
      expect(c.err.toString(), contains('lower than current'));
    });

    test('unreadable --to exits 3', () async {
      final (code, _) = await cli([
        'log',
        'http',
        '--to',
        'x',
        '--lock',
        'example/pubspec.lock',
      ]);
      expect(code, 3);
    });

    test('--help and --version exit 0', () async {
      expect((await cli(['--help'])).$1, 0);
      expect((await cli(['log', '--help'])).$1, 0);
      final (code, c) = await cli(['--version']);
      expect(code, 0);
      expect(c.out.toString(), 'pubdelta $pubdeltaVersion\n');
    });
  });
}
