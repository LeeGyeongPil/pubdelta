import 'dart:convert';
import 'dart:io';

import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/fake_pub_server.dart';
import 'support/helpers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pubdelta_plan_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('plan from the example files', () {
    Future<List<PlanEntry>> plan({
      Mode mode = Mode.resolvable,
      Set<String>? include,
    }) async {
      final r = await buildPlan(
        PlanRequest(
          lockFile: 'example/pubspec.lock',
          outdatedFile: 'example/outdated.json',
          mode: mode,
          include: include ?? const {'dev'},
        ),
      );
      return r.entries;
    }

    test('http goes 1.2.2 -> 1.6.0 as a minor bump', () async {
      final http = (await plan()).singleWhere((e) => e.name == 'http');
      expect('${http.from}', '1.2.2');
      expect('${http.to}', '1.6.0');
      expect(http.bump, Bump.minor);
      expect(http.package.dependency, 'direct main');
    });

    test(
      'resolvable mode reaches firebase_core 5.2.0 (major); upgradable stays',
      () async {
        final fb = (await plan()).singleWhere((e) => e.name == 'firebase_core');
        expect('${fb.to}', '5.2.0');
        expect(fb.bump, Bump.major);
        final up = await plan(mode: Mode.upgradable);
        expect(
          up.any((e) => e.name == 'firebase_core'),
          isFalse,
          reason: 'upgradable == current, so no entry',
        );
      },
    );

    test('build number target: provider 6.1.2 -> 6.1.5+1', () async {
      final p = (await plan()).singleWhere((e) => e.name == 'provider');
      expect('${p.to}', '6.1.5+1');
      expect(p.bump, Bump.patch);
    });

    test('transitive packages are left out unless asked for', () async {
      expect((await plan()).any((e) => e.name == 'async'), isFalse);
      final all = await plan(include: {'dev', 'transitive'});
      expect(all.any((e) => e.name == 'async'), isTrue);
    });

    test('dev packages can be left out', () async {
      expect((await plan(include: {})).any((e) => e.name == 'lints'), isFalse);
      expect((await plan()).any((e) => e.name == 'lints'), isTrue);
    });
  });

  group('CLI --include adds to the default, it does not replace dev', () {
    const files = [
      '--lock',
      'example/pubspec.lock',
      '--outdated',
      'example/outdated.json',
    ];

    Future<List<String>> names(List<String> extra) async {
      final (code, c) = await cli([
        'plan',
        ...files,
        '--format',
        'json',
        ...extra,
      ]);
      expect(code, 0);
      final json = jsonDecode(c.out.toString()) as Map<String, Object?>;
      return [
        for (final p in json['packages'] as List<Object?>)
          (p as Map<String, Object?>)['name'] as String,
      ];
    }

    test('default: direct main and dev, no transitive', () async {
      final n = await names([]);
      expect(n, containsAll(['http', 'lints']));
      expect(n, isNot(contains('async')));
    });

    test('--include transitive keeps dev (lints) and adds async', () async {
      final n = await names(['--include', 'transitive']);
      expect(n, containsAll(['http', 'lints', 'async']));
    });

    test(
      '--include dev,transitive is the same as --include transitive',
      () async {
        expect(
          await names(['--include', 'dev,transitive']),
          await names(['--include', 'transitive']),
        );
      },
    );

    test('log of a dev package by name works with any --include', () async {
      final (code, c) = await cli([
        'log',
        'lints',
        ...files,
        '--changelog-dir',
        'example/changelogs',
        '--include',
        'transitive',
      ]);
      expect(code, 0);
      expect(c.out.toString(), contains('lints 4.0.0 → 6.1.0'));
      expect(c.out.toString(), isNot(contains('Nothing to show')));
    });

    test(
      'log of a transitive package by name works without --include',
      () async {
        // 빈 pub 캐시 + --offline: async 는 예제 변경 기록이 없어 종료 4 지만 목표 버전은 찾는다
        final (code, c) = await cli(
          [
            'log',
            'async',
            ...files,
            '--changelog-dir',
            'example/changelogs',
            '--offline',
          ],
          env: {'LANG': 'C', 'PUB_CACHE': tmp.path},
        );
        expect(code, 4);
        expect(c.out.toString(), contains('async 2.13.0 → 2.13.1'));
        expect(c.err.toString(), isNot(contains('already at the target')));
      },
    );

    test('flags come from the outdated JSON', () {
      const json = '''
{"packages":[{"package":"x","kind":"direct","isDiscontinued":true,
"isCurrentRetracted":true,"isCurrentAffectedByAdvisory":true,
"current":{"version":"1.0.0"},"upgradable":{"version":"1.1.0"},
"resolvable":{"version":"1.1.0"},"latest":{"version":"1.1.0"}}]}''';
      final locked = parseLockfile(
        'packages:\n  x:\n    dependency: "direct main"\n    description:\n      name: x\n      url: "https://pub.dev"\n    source: hosted\n    version: "1.0.0"\n',
      );
      final entries = buildPlanEntries(
        locked,
        parseOutdatedJson(json),
        mode: Mode.resolvable,
      );
      expect(entries.single.flags, ['retracted', 'discontinued', 'advisory']);
    });

    test('CLI plan --format json carries name, from, to and bump', () async {
      final (code, c) = await cli([
        'plan',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
        '--format',
        'json',
      ]);
      expect(code, 0);
      final out = c.out.toString();
      expect(out, contains('"name":"http"'));
      expect(out, contains('"from":"1.2.2"'));
      expect(out, contains('"to":"1.6.0"'));
      expect(out, contains('"bump":"minor"'));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      expect(decoded['schema'], 1);
    });
  });

  group('lock file and outdated JSON parsing', () {
    test('reads dependency kinds and sources', () {
      final locked = parseLockfile('''
packages:
  a:
    dependency: "direct main"
    description: {name: a, url: "https://pub.dev"}
    source: hosted
    version: "1.0.0"
  b:
    dependency: "direct dev"
    description: {path: "../b", relative: true}
    source: path
    version: "0.0.1"
  c:
    dependency: transitive
    description: flutter
    source: sdk
    version: "0.0.0"
''');
      expect(locked.map((p) => p.kind), ['main', 'dev', 'transitive']);
      expect(locked[1].source, 'path');
      expect(locked[1].path, '../b');
      expect(locked[1].pathIsRelative, isTrue);
      expect(locked[0].hostedUrl, 'https://pub.dev');
    });

    test('a missing lock file is an input error (exit 3) with a fix', () async {
      final (code, c) = await cli(['plan', '--lock', '${tmp.path}/none.lock']);
      expect(code, 3);
      expect(c.err.toString(), contains('dart pub get'));
    });

    test('a broken lock file is an input error (exit 3)', () async {
      File('${tmp.path}/pubspec.lock').writeAsStringSync('::: not yaml: [');
      final (code, _) = await cli([
        'plan',
        '--lock',
        '${tmp.path}/pubspec.lock',
      ]);
      expect(code, 3);
    });

    test('outdated JSON that is not JSON is exit 5 territory', () {
      expect(
        () => parseOutdatedJson('nope'),
        throwsA(isA<PubdeltaException>().having((e) => e.exitCode, 'exit', 5)),
      );
    });
  });

  group('dry-run fallback', () {
    const dryRun = '''
Resolving dependencies...
> http 1.6.0 (was 1.2.2)
> lints 6.1.0 (was 4.0.0)
< old 1.0.0 (was 2.0.0)
  args 2.5.0 (2.7.0 available)
No changes would be made.
''';

    test('parseDryRun reads upgrade lines only', () {
      final info = parseDryRun(dryRun);
      expect(info.keys.toSet(), {'http', 'lints'});
      expect('${info['http']!.resolvable}', '1.6.0');
      expect('${info['http']!.current}', '1.2.2');
    });

    ProcessRunner runner({
      required bool outdatedFails,
      bool upgradeFails = false,
    }) {
      return (exe, args, {workingDirectory, environment}) async {
        if (args.contains('outdated')) {
          return outdatedFails
              ? ProcessResult(
                1,
                1,
                '',
                'Got TLS error CERTIFICATE_VERIFY_FAILED',
              )
              : ProcessResult(1, 0, '{"packages":[]}', '');
        }
        return upgradeFails
            ? ProcessResult(2, 1, '', 'offline resolution failed')
            : ProcessResult(2, 0, dryRun, '');
      };
    }

    test('plan falls back with a warning when outdated fails', () async {
      final lock = writeLock(tmp, {
        'http': ('1.2.2', 'direct main'),
        'lints': ('4.0.0', 'direct dev'),
      });
      final r = await buildPlan(
        PlanRequest(lockFile: lock, runner: runner(outdatedFails: true)),
      );
      expect(r.entries.map((e) => '${e.name} ${e.to}').toList(), [
        'http 1.6.0',
        'lints 6.1.0',
      ]);
      expect(r.notices.single.key, 'outdated.fallback');
      expect(r.notices.single.args.first, contains('TLS'));
    });

    test('CLI prints the warning and still succeeds', () async {
      final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
      final (code, c) = await cli([
        'plan',
        '--lock',
        lock,
      ], runner: runner(outdatedFails: true));
      expect(code, 0);
      expect(c.err.toString(), contains('failed'));
      expect(c.out.toString(), contains('1.6.0'));
    });

    test('both failing is exit code 5', () async {
      final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
      final (code, c) = await cli([
        'plan',
        '--lock',
        lock,
      ], runner: runner(outdatedFails: true, upgradeFails: true));
      expect(code, 5);
      expect(c.err.toString(), contains('--outdated'));
    });
  });

  // SDK 의 실제 pub 를 띄우는 시험 — dart_test.yaml 이 기본으로 건너뛴다.
  // 직접 돌리기: dart test --run-skipped -t integration
  group('real `dart pub outdated --json` against a fake repository', () {
    test(
      'runs end to end with PUB_HOSTED_URL',
      () async {
        final server = await FakePubServer.start({
          'http': [
            const FakeVersion('1.2.2'),
            const FakeVersion('1.5.0-beta'),
            const FakeVersion('1.6.0'),
          ],
          'args': [const FakeVersion('2.5.0'), const FakeVersion('2.7.0')],
        });
        addTearDown(server.close);

        File('${tmp.path}/pubspec.yaml').writeAsStringSync('''
name: fake_app
environment:
  sdk: ^3.0.0
dependencies:
  http: any
  args: any
''');
        final lock = writeLock(tmp, {
          'http': ('1.2.2', 'direct main'),
          'args': ('2.5.0', 'direct main'),
        }, url: server.url);
        final cache = Directory('${tmp.path}/cache')..createSync();

        final r = await buildPlan(
          PlanRequest(
            lockFile: lock,
            environment: {
              ...Platform.environment,
              'PUB_HOSTED_URL': server.url,
              'PUB_CACHE': cache.path,
            },
          ),
        );
        expect(
          r.notices,
          isEmpty,
          reason: 'no fallback should have been needed',
        );
        final byName = {for (final e in r.entries) e.name: e};
        expect('${byName['http']!.to}', '1.6.0');
        expect('${byName['args']!.to}', '2.7.0');
        expect(server.requests, contains('/api/packages/http'));
      },
      tags: ['integration'],
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });
}
