// Q-15: 사용자가 준 파일·하위 프로세스·예상하지 못한 예외가 스택 트레이스와
// exit 255 로 끝나지 않고, 고른 언어의 문구와 정해진 종료 코드로 끝나는지 본다.
import 'dart:convert';
import 'dart:io';

import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('pubdelta_rob_'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('readTextFile / decodeText (the one place that reads text files)', () {
    test('valid UTF-8 is returned as is', () async {
      final f = File('${tmp.path}/a.md')..writeAsStringSync('## 1.0.0 – é');
      final r = await readTextFile(f);
      expect(r.text, '## 1.0.0 – é');
      expect(r.hadInvalidUtf8, isFalse);
    });

    test('Latin-1 bytes become U+FFFD and are flagged, no exception', () {
      final r = decodeText(latin1.encode('café'));
      expect(r.text, 'caf�');
      expect(r.hadInvalidUtf8, isTrue);
    });

    test('a byte order mark is dropped', () {
      expect(decodeText([0xEF, 0xBB, 0xBF, 0x41]).text, 'A');
    });

    test('a directory is an UnreadableFile with the path', () async {
      await expectLater(
        readTextFile(File(tmp.path)),
        throwsA(isA<UnreadableFile>().having((e) => e.path, 'path', tmp.path)),
      );
    });
  });

  group('lock file', () {
    test('not UTF-8: exit 3 with a fix, in en and ko', () async {
      final lock = File('${tmp.path}/pubspec.lock')
        ..writeAsBytesSync(latin1.encode('packages:\n  café: {}\n'));
      for (final (lang, text) in [
        ('en', 'the file is not valid UTF-8 text'),
        ('ko', '파일이 올바른 UTF-8 텍스트가 아닙니다'),
      ]) {
        final (code, c) = await cli([
          'plan',
          '--lock',
          lock.path,
          '--outdated',
          'example/outdated.json',
          '--lang',
          lang,
        ]);
        expect(code, 3);
        expect(c.err.toString(), contains(text));
        expect(c.err.toString(), contains('dart pub get'));
      }
    });

    test('cannot be read: exit 3 input.cannotRead', () async {
      final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
      if (!makeUnreadable(lock)) {
        markTestSkipped('cannot make a file unreadable here (Windows/root)');
        return;
      }
      final (code, c) = await cli([
        'plan',
        '--lock',
        lock,
        '--outdated',
        'example/outdated.json',
        '--lang',
        'ko',
      ]);
      expect(code, 3);
      expect(c.err.toString(), contains('읽을 수 없습니다'));
      expect(c.err.toString(), contains(lock));
    });

    test('structural problems are explained in the chosen language', () async {
      File('${tmp.path}/pubspec.lock').writeAsStringSync('sdks: {}\n');
      final (code, c) = await cli([
        'plan',
        '--lock',
        '${tmp.path}/pubspec.lock',
        '--outdated',
        'example/outdated.json',
        '--lang',
        'ko',
      ]);
      expect(code, 3);
      expect(c.err.toString(), contains('"packages" 항목이 없습니다'));
      expect(c.err.toString(), isNot(contains('no "packages" map')));
    });
  });

  group('--outdated file', () {
    test('not UTF-8: exit 5 outdated.badFile, in en and ko', () async {
      final bad = File('${tmp.path}/outdated.json')
        ..writeAsBytesSync([...'{"packages":[{"package":"caf'.codeUnits, 0xE9]);
      for (final (lang, text) in [
        ('en', 'is not valid "dart pub outdated --json" output'),
        ('ko', '"dart pub outdated --json" 출력 형식이 아닙니다'),
      ]) {
        final (code, c) = await cli([
          'plan',
          '--lock',
          'example/pubspec.lock',
          '--outdated',
          bad.path,
          '--lang',
          lang,
        ]);
        expect(code, 5);
        expect(c.err.toString(), contains(text));
      }
    });

    test('cannot be read: exit 3 input.cannotRead', () async {
      final f = File('${tmp.path}/outdated.json')
        ..writeAsStringSync('{"packages":[]}');
      if (!makeUnreadable(f.path)) {
        markTestSkipped('cannot make a file unreadable here (Windows/root)');
        return;
      }
      final (code, c) = await cli([
        'plan',
        '--lock',
        'example/pubspec.lock',
        '--outdated',
        f.path,
      ]);
      expect(code, 3);
      expect(c.err.toString(), contains('cannot read'));
    });
  });

  group('unexpected errors (last catch)', () {
    // 하위 프로세스 실행기가 예상하지 못한 예외를 던지는 상황을 만든다
    Future<ProcessResult> boom(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    }) async => throw StateError('boom');

    test('CLI: one line in the chosen language and exit 6', () async {
      for (final (lang, text) in [
        ('en', 'unexpected error (StateError: Bad state: boom)'),
        ('ko', '예상하지 못한 오류 (StateError: Bad state: boom)'),
      ]) {
        final (code, c) = await cli([
          'plan',
          '--lock',
          'example/pubspec.lock',
          '--lang',
          lang,
        ], runner: boom);
        expect(code, exitUnexpected);
        expect(code, 6);
        expect(c.err.toString(), contains(text));
        expect(c.err.toString().trim().split('\n'), hasLength(1));
      }
    });

    test('MCP: only that call is an error; the server answers next', () async {
      final server = McpServer(
        env: const {'LANG': 'C', 'PUBDELTA_LANG': 'ko'},
        runner: boom,
      );
      final r = await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'plan',
            'arguments': {'lockFile': 'example/pubspec.lock'},
          },
        }),
      );
      final result = r!['result'] as Map<String, Object?>;
      expect(result['isError'], true);
      final text = ((result['content'] as List).first as Map)['text'] as String;
      expect(text, contains('예상하지 못한 오류'));
      final ping = await server.handleLine(
        '{"jsonrpc":"2.0","id":2,"method":"ping"}',
      );
      expect(ping!['result'], isEmpty);
    });
  });

  group('child process output', () {
    test('bytes that are not UTF-8 do not throw', () async {
      if (Platform.isWindows) {
        markTestSkipped('uses /bin/sh');
        return;
      }
      final r = await defaultRunner('/bin/sh', ['-c', r"printf 'caf\351'"]);
      expect(r.exitCode, 0);
      expect(r.stdout, 'caf�');
    });
  });

  group('as a real process (no stack trace, no exit 255)', () {
    test('Latin-1 lock file exits 3 with one error line', () async {
      final lock = File('${tmp.path}/pubspec.lock')
        ..writeAsBytesSync(latin1.encode('packages:\n  café: {}\n'));
      final r = await Process.run(Platform.resolvedExecutable, [
        'bin/pubdelta.dart',
        'plan',
        '--lock',
        lock.path,
        '--outdated',
        'example/outdated.json',
        '--lang',
        'ko',
      ]);
      expect(r.exitCode, 3, reason: '${r.stderr}');
      expect('${r.stderr}', contains('UTF-8'));
      expect('${r.stderr}', isNot(contains('Unhandled exception')));
    });
  });
}
