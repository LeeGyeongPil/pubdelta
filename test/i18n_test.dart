import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// Replaces every value by its type so that only the key structure is left.
Object? shape(Object? v) {
  if (v is Map) return {for (final e in v.entries) e.key: shape(e.value)};
  if (v is List) return v.isEmpty ? [] : [shape(v.first)];
  if (v is String) return 'string';
  return v.runtimeType.toString();
}

void main() {
  group('message tables', () {
    test('English and Korean have exactly the same keys', () {
      expect(
        messageTable(Lang.ko).keys.toSet(),
        messageTable(Lang.en).keys.toSet(),
      );
    });

    test(
      'no empty values, and the same {n} placeholders in both languages',
      () {
        final en = messageTable(Lang.en);
        final ko = messageTable(Lang.ko);
        final placeholder = RegExp(r'\{\d+\}');
        for (final key in en.keys) {
          expect(en[key], isNotEmpty, reason: key);
          expect(ko[key], isNotEmpty, reason: key);
          Set<String> marks(String s) =>
              placeholder.allMatches(s).map((m) => m[0]!).toSet();
          expect(
            marks(ko[key]!),
            marks(en[key]!),
            reason: 'placeholders of $key',
          );
        }
      },
    );

    test('Korean texts really are Korean where it matters', () {
      expect(tr(Lang.ko, 'col.package'), '패키지');
      expect(tr(Lang.en, 'col.package'), 'Package');
    });

    test('tr fills placeholders and falls back to the key', () {
      expect(
        tr(Lang.en, 'log.upToDate', ['http', '1.0.0']),
        contains('http: already at the target version 1.0.0'),
      );
      expect(tr(Lang.en, 'no.such.key'), 'no.such.key');
    });
  });

  group(
    'language choice: --lang > PUBDELTA_LANG > LC_ALL > LC_MESSAGES > LANG',
    () {
      test('flag beats everything', () {
        expect(
          resolveLang(
            flag: 'en',
            env: {'PUBDELTA_LANG': 'ko', 'LANG': 'ko_KR.UTF-8'},
          ),
          Lang.en,
        );
        expect(resolveLang(flag: 'ko', env: {'PUBDELTA_LANG': 'en'}), Lang.ko);
      });

      test('PUBDELTA_LANG beats the locale variables', () {
        expect(
          resolveLang(env: {'PUBDELTA_LANG': 'ko', 'LC_ALL': 'en_US.UTF-8'}),
          Lang.ko,
        );
        expect(
          resolveLang(env: {'PUBDELTA_LANG': 'en', 'LANG': 'ko_KR.UTF-8'}),
          Lang.en,
        );
      });

      test('LC_ALL > LC_MESSAGES > LANG', () {
        expect(
          resolveLang(
            env: {
              'LC_ALL': 'ko_KR.UTF-8',
              'LC_MESSAGES': 'en_US',
              'LANG': 'en_US',
            },
          ),
          Lang.ko,
        );
        expect(
          resolveLang(env: {'LC_MESSAGES': 'ko_KR.UTF-8', 'LANG': 'en_US'}),
          Lang.ko,
        );
        expect(
          resolveLang(env: {'LC_MESSAGES': 'en_US', 'LANG': 'ko_KR.UTF-8'}),
          Lang.en,
        );
        expect(resolveLang(env: {'LANG': 'ko_KR.UTF-8'}), Lang.ko);
      });

      test('empty values are skipped; anything else is English', () {
        expect(
          resolveLang(env: {'LC_ALL': '', 'LANG': 'ko_KR.UTF-8'}),
          Lang.ko,
        );
        expect(resolveLang(env: {'LANG': 'C'}), Lang.en);
        expect(resolveLang(env: {'LANG': 'fr_FR.UTF-8'}), Lang.en);
        expect(resolveLang(env: const {}), Lang.en);
      });
    },
  );

  group('the CLI really switches language', () {
    test('plan table headers', () async {
      final args = [
        'plan',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
      ];
      final (_, en) = await cli([...args, '--lang', 'en']);
      final (_, ko) = await cli([...args, '--lang', 'ko']);
      expect(en.out.toString(), contains('Package'));
      expect(en.out.toString(), contains('Current'));
      expect(ko.out.toString(), contains('패키지'));
      expect(ko.out.toString(), contains('현재'));
      expect(ko.out.toString(), isNot(contains('Package')));
    });

    test('warnings', () async {
      final args = [
        'plan',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
      ];
      final (_, en) = await cli(args, env: {'LANG': 'C'});
      final (_, ko) = await cli(args, env: {'LANG': 'ko_KR.UTF-8'});
      expect(en.err.toString(), contains('warning:'));
      expect(ko.err.toString(), contains('경고:'));
    });

    test('help text and error messages', () async {
      final (_, en) = await cli(['--help', '--lang', 'en']);
      final (_, ko) = await cli(['--help', '--lang', 'ko']);
      expect(en.out.toString(), contains('Usage: pubdelta'));
      expect(ko.out.toString(), contains('사용법: pubdelta'));

      final (codeEn, errEn) = await cli(['log', '--lang', 'en']);
      final (codeKo, errKo) = await cli(['log', '--lang', 'ko']);
      expect(codeEn, 2);
      expect(codeKo, 2);
      expect(errEn.err.toString(), contains('give at least one package name'));
      expect(errKo.err.toString(), contains('패키지 이름을 하나 이상'));
    });

    test('PUBDELTA_LANG and LANG are honored; --lang wins', () async {
      final args = ['log', '--lang', 'en'];
      final (_, flagWins) = await cli(args, env: {'PUBDELTA_LANG': 'ko'});
      expect(flagWins.err.toString(), contains('give at least one'));
      final (_, fromEnv) = await cli(['log'], env: {'PUBDELTA_LANG': 'ko'});
      expect(fromEnv.err.toString(), contains('패키지 이름을'));
      final (_, fromLang) = await cli(['log'], env: {'LANG': 'ko_KR.UTF-8'});
      expect(fromLang.err.toString(), contains('패키지 이름을'));
    });

    test('log output: header words and omitted line', () async {
      final base = [
        'log',
        '--all',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        'example/outdated.json',
        '--changelog-dir',
        'example/changelogs',
        '--budget',
        '700',
      ];
      final (_, en) = await cli([...base, '--lang', 'en']);
      final (_, ko) = await cli([...base, '--lang', 'ko']);
      expect(en.out.toString(), contains('omitted:'));
      expect(en.out.toString(), contains('STRONG'));
      expect(ko.out.toString(), contains('생략:'));
      expect(ko.out.toString(), contains('강함'));
    });
  });

  group('JSON does not depend on the language', () {
    test('plan and log JSON have the same keys in en and ko', () async {
      for (final args in [
        [
          'plan',
          '--lock',
          'example/pubspec.lock',
          '--outdated',
          'example/outdated.json',
          '--format',
          'json',
        ],
        [
          'log',
          '--all',
          '--lock',
          'example/pubspec.lock',
          '--outdated',
          'example/outdated.json',
          '--changelog-dir',
          'example/changelogs',
          '--format',
          'json',
        ],
      ]) {
        final (_, en) = await cli([...args, '--lang', 'en']);
        final (_, ko) = await cli([...args, '--lang', 'ko']);
        final enJson = jsonDecode(en.out.toString());
        final koJson = jsonDecode(ko.out.toString());
        expect(shape(koJson), shape(enJson));
        // Data values such as levels and bump names stay English.
        expect(ko.out.toString(), contains('"bump":"minor"'));
      }
    });
  });

  group('option parse errors use our own tables, never args English', () {
    // args 패키지가 내는 영어 문구 조각. 어느 언어에서도 이대로 나오면 안 된다.
    const argsEnglish = [
      'Could not find',
      'is not an allowed value',
      'Missing argument',
      'should not be given a value',
      'Cannot negate',
      'cannot handle value',
      'is mandatory',
    ];

    // (인수, 한국어에서 꼭 나올 문구, 영어에서 꼭 나올 문구)
    const cases = <(List<String>, String, String)>[
      // 알 수 없는 옵션: 긴 이름, 짧은 이름, 짧은 이름 묶음, 최상위
      (
        ['log', 'http', '--bogus'],
        '에 없는 옵션입니다: "--bogus"',
        'has no option "--bogus"',
      ),
      (
        ['log', '-z'],
        '"pubdelta log" 에 없는 옵션입니다: "-z"',
        '"pubdelta log" has no option "-z"',
      ),
      (['log', '-hz'], '에 없는 옵션입니다: "-z"', 'has no option "-z"'),
      (['--bogus'], '"pubdelta" 에 없는 옵션입니다', '"pubdelta" has no option'),
      (
        ['plan', '--no-bogus'],
        '에 없는 옵션입니다: "--no-bogus"',
        'has no option "--no-bogus"',
      ),
      // 허용되지 않은 값: 공백, =, 여러 값 옵션의 쉼표 목록
      (
        ['log', 'http', '--mode', 'foo'],
        '"foo" 은(는) --mode 에 쓸 수 없는 값',
        '"foo" is not a valid value for --mode',
      ),
      (
        ['plan', '--format=pdf'],
        '"pdf" 은(는) --format 에 쓸 수 없는 값',
        '"pdf" is not a valid value for --format',
      ),
      (
        ['plan', '--include', 'dev,foo'],
        '"foo" 은(는) --include 에 쓸 수 없는 값',
        '"foo" is not a valid value for --include',
      ),
      (
        ['log', 'http', '--fail-on', 'maybe'],
        '가능한 값: none, breaking, major',
        'choose from: none, breaking, major',
      ),
      // 값 누락: 맨 끝, 값 자리에 다른 옵션
      (
        ['log', 'http', '--mode'],
        '옵션 "--mode" 에 값이 필요합니다',
        'option "--mode" needs a value',
      ),
      (
        ['log', 'http', '--lock'],
        '옵션 "--lock" 에 값이 필요합니다',
        'option "--lock" needs a value',
      ),
      (
        ['log', 'http', '--lock', '--offline'],
        '옵션 "--lock" 에 값이 필요합니다',
        'option "--lock" needs a value',
      ),
      // 플래그에 값, 끌 수 없는 옵션
      (
        ['log', '--all=yes'],
        '플래그 "--all" 는 값을 받지 않습니다',
        'flag "--all" does not take a value',
      ),
      (['--version=1'], '플래그 "--version"', 'flag "--version"'),
      (['log', '-h=1'], '플래그 "-h"', 'flag "-h"'),
      (['log', '--no-all'], '--all 는 끌 수 없는 옵션', '--all cannot be turned off'),
      (
        ['plan', '--no-lock'],
        '--lock 는 끌 수 없는 옵션',
        '--lock cannot be turned off',
      ),
      // 알 수 없는 명령
      (['frob'], '알 수 없는 명령 "frob"', 'unknown command "frob"'),
    ];

    for (final (args, ko, en) in cases) {
      test(args.join(' '), () async {
        final (codeKo, k) = await cli([...args, '--lang', 'ko']);
        final (codeEn, e) = await cli([...args, '--lang', 'en']);
        expect(codeKo, 2);
        expect(codeEn, 2);
        final errKo = k.err.toString();
        final errEn = e.err.toString();
        expect(errKo, contains(ko));
        expect(errKo, contains('사용법은 "pubdelta --help"'));
        expect(errEn, contains(en));
        for (final phrase in argsEnglish) {
          expect(errKo, isNot(contains(phrase)), reason: 'ko: $phrase');
          expect(errEn, isNot(contains(phrase)), reason: 'en: $phrase');
        }
      });
    }

    test('the language comes from PUBDELTA_LANG too, before parsing', () async {
      final (code, c) = await cli(
        ['log', '--bogus'],
        env: {'PUBDELTA_LANG': 'ko'},
      );
      expect(code, 2);
      expect(c.err.toString(), contains('에 없는 옵션입니다'));
    });

    test(
      '"--lang" followed by another option does not pick a language',
      () async {
        // "--lang --lang ko": 첫 --lang 의 값 자리에 옵션이 왔으니 뒤의 ko 를 쓴다
        final (code, c) = await cli(['--lang', '--lang', 'ko']);
        expect(code, 2);
        expect(c.err.toString(), contains('옵션 "--lang" 에 값이 필요합니다'));
      },
    );

    test('an ArgParserException without an argument name is translated', () {
      final parser = ArgParser()..addFlag('x');
      final text = describeArgError(
        ArgParserException('Some English text'),
        parser,
        ['--weird'],
        Lang.ko,
      );
      expect(text, '알 수 없는 옵션이나 잘못된 값: --weird');
    });
  });

  group('no English sentence parts inside translated messages', () {
    test('every fetch failure kind has a message in both tables', () {
      for (final kind in fetchFailureKinds) {
        expect(messageTable(Lang.en).containsKey('fetch.$kind'), isTrue);
        expect(messageTable(Lang.ko).containsKey('fetch.$kind'), isTrue);
      }
    });

    test('messageRef is translated where it is shown', () {
      final notice = Notice('outdated.fallback', [
        messageRef('outdated.badJson'),
      ]);
      expect(notice.text(Lang.ko), contains('예상한 JSON 을 출력하지 않았습니다'));
      expect(notice.text(Lang.ko), isNot(contains('did not print')));
      expect(notice.text(Lang.en), contains('did not print the expected JSON'));
      expect(
        tr(Lang.ko, 'outdated.failed', [
          messageRef('input.noLock', ['a.lock']),
          messageRef('outdated.noOutput'),
        ]),
        allOf(contains('잠금 파일을 찾을 수 없습니다: a.lock'), contains('오류 출력 없음')),
      );
    });

    test('pub outdated failures are Korean end to end in ko', () async {
      // 첫 번째 실행은 JSON 이 아닌 출력, 두 번째(오프라인 대체)는 출력 없이 실패
      Future<ProcessResult> runner(
        String exe,
        List<String> args, {
        String? workingDirectory,
        Map<String, String>? environment,
      }) async {
        if (args.contains('outdated')) return ProcessResult(1, 0, 'nope', '');
        return ProcessResult(2, 1, '', '');
      }

      final (code, c) = await cli([
        'plan',
        '--lock',
        'example/pubspec.lock',
        '--lang',
        'ko',
      ], runner: runner);
      expect(code, 5);
      final err = c.err.toString();
      expect(err, contains('예상한 JSON 을 출력하지 않았습니다'));
      expect(err, contains('오류 출력 없음'));
      expect(err, isNot(contains('did not print')));
      expect(err, isNot(contains('no output')));
    });

    test('MCP tool errors follow PUBDELTA_LANG', () async {
      final server = McpServer(env: const {'PUBDELTA_LANG': 'ko'});
      Future<String> call(Map<String, Object?> params) async {
        final r = await server.handleLine(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': params,
          }),
        );
        final result = r!['result'] as Map;
        expect(result['isError'], true);
        return ((result['content'] as List).first as Map)['text'] as String;
      }

      expect(await call({'name': 'zzz'}), contains('알 수 없는 도구 "zzz"'));
      final bad = await call({
        'name': 'plan',
        'arguments': {'mode': 'sideways'},
      });
      expect(bad, contains('인자 "mode" 의 값이 잘못되었습니다: sideways'));
      expect(bad, isNot(contains('Invalid argument')));
    });
  });

  test('--help has no English "default" text in Korean, any command', () async {
    for (final cmd in ['plan', 'log']) {
      final (code, c) = await cli([cmd, '--help', '--lang', 'ko']);
      expect(code, 0);
      final out = c.out.toString();
      expect(out, isNot(contains('default')), reason: cmd);
      expect(out, isNot(contains('defaults to')), reason: cmd);
      expect(out, contains('기본:'), reason: cmd);
    }
  });

  test('defaults still apply without parser defaults', () async {
    final (code, c) = await cli([
      'plan',
      '--lock',
      'example/pubspec.lock',
      '--outdated',
      'example/outdated.json',
    ]);
    expect(code, 0);
    expect(c.out.toString(), contains('http'));
  });

  test('--lang help names the real precedence in both languages', () {
    for (final lang in [Lang.en, Lang.ko]) {
      final t = tr(lang, 'opt.lang');
      expect(t, contains('LC_ALL'));
      expect(t, contains('LC_MESSAGES'));
    }
  });

  test('a broken --outdated file names the file and the fix, exit 5', () async {
    final dir = Directory.systemTemp.createTempSync('pd_bad');
    addTearDown(() => dir.deleteSync(recursive: true));
    final bad = File('${dir.path}/o.json')..writeAsStringSync('{nope');
    final (code, c) = await cli([
      'plan',
      '--lock',
      'example/pubspec.lock',
      '--outdated',
      bad.path,
    ]);
    expect(code, 5);
    expect(c.err.toString(), contains(bad.path));
    expect(c.err.toString(), contains('dart pub outdated --json >'));
  });

  test('a hanging dart process is killed after processTimeout', () async {
    final saved = processTimeout;
    processTimeout = const Duration(milliseconds: 300);
    addTearDown(() => processTimeout = saved);
    final sw = Stopwatch()..start();
    final r = await defaultRunner('sleep', ['30']);
    expect(r.exitCode, 124);
    // stderr 는 메시지 참조라 보여 줄 때 고른 언어로 바뀐다
    expect(
      tr(Lang.en, 'outdated.fallback', ['${r.stderr}']),
      contains('timed out'),
    );
    expect(
      tr(Lang.ko, 'outdated.fallback', ['${r.stderr}']),
      contains('중단했습니다'),
    );
    expect(sw.elapsed, lessThan(const Duration(seconds: 10)));
  });

  test('version constant matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match![1], pubdeltaVersion);
  });
}
