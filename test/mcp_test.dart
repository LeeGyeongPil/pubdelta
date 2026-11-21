import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/helpers.dart';

/// Arguments shared by the MCP call and the CLI run it is compared with.
const exampleLock = 'example/pubspec.lock';

void main() {
  group('pubdelta mcp as a child process (stdio)', () {
    late Process proc;
    late StreamIterator<String> lines;

    setUp(() async {
      proc = await Process.start(
        Platform.resolvedExecutable,
        ['bin/pubdelta.dart', 'mcp'],
        environment: {'LANG': 'C', 'PUBDELTA_LANG': 'en'},
      );
      lines = StreamIterator(
        proc.stdout.transform(utf8.decoder).transform(const LineSplitter()),
      );
    });

    tearDown(() async {
      await proc.stdin.close();
      await proc.exitCode.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          proc.kill();
          return -1;
        },
      );
      await lines.cancel();
    });

    int nextId = 1;
    Future<Map<String, Object?>> request(
      String method, [
      Map<String, Object?>? params,
    ]) async {
      final id = nextId++;
      proc.stdin.writeln(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': id,
          'method': method,
          if (params != null) 'params': params,
        }),
      );
      expect(
        await lines.moveNext().timeout(const Duration(seconds: 60)),
        isTrue,
      );
      final reply = jsonDecode(lines.current) as Map<String, Object?>;
      expect(reply['id'], id);
      return reply;
    }

    test('initialize, tools/list and tools/call changelog', () async {
      final init = await request('initialize', {
        'protocolVersion': '2025-06-18',
        'capabilities': {},
        'clientInfo': {'name': 'test', 'version': '0'},
      });
      final initResult = init['result'] as Map<String, Object?>;
      expect(initResult['protocolVersion'], '2025-06-18');
      expect((initResult['serverInfo'] as Map)['name'], 'pubdelta');
      expect(
        initResult['capabilities'],
        containsPair('tools', isA<Map<String, Object?>>()),
      );

      // A notification gets no reply; the next request must still be answered.
      proc.stdin.writeln(
        jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}),
      );

      final list = await request('tools/list');
      final tools =
          ((list['result'] as Map)['tools'] as List)
              .cast<Map<String, Object?>>();
      expect(tools.map((t) => t['name']), containsAll(['plan', 'changelog']));
      for (final t in tools) {
        expect(t['description'], isA<String>());
        expect(t['inputSchema'], containsPair('type', 'object'));
      }

      final call = await request('tools/call', {
        'name': 'changelog',
        'arguments': {
          'projectDir': 'example',
          'lockFile': exampleLock,
          'outdatedFile': 'example/outdated.json',
          'changelogDir': 'example/changelogs',
          'offline': true,
          'budget': 1500,
        },
      });
      final result = call['result'] as Map<String, Object?>;
      expect(result['isError'], false);
      final text = ((result['content'] as List).first as Map)['text'] as String;

      // 1.6.0 strong signal and the omitted line are there ...
      expect(text, contains('STRONG 1.6.0: **Breaking**'));
      expect(text, contains('omitted:'));

      // ... and the body equals what the CLI prints for the same request.
      final (code, c) = await cli([
        'log',
        '--all',
        '--lock',
        exampleLock,
        '--outdated',
        'example/outdated.json',
        '--changelog-dir',
        'example/changelogs',
        '--offline',
        '--budget',
        '1500',
        '--format',
        'md',
      ]);
      expect(code, 0);
      expect(text, c.out.toString().trimRight());
    });

    test('plan tool lists the upgrade table', () async {
      final call = await request('tools/call', {
        'name': 'plan',
        'arguments': {
          'lockFile': exampleLock,
          'outdatedFile': 'example/outdated.json',
        },
      });
      final text =
          (((call['result'] as Map)['content'] as List).first as Map)['text']
              as String;
      expect(text, contains('| http | 1.2.2 | 1.6.0 | minor |'));
    });

    test('a bad package is a tool error, not a crash', () async {
      final call = await request('tools/call', {
        'name': 'changelog',
        'arguments': {
          'lockFile': exampleLock,
          'outdatedFile': 'example/outdated.json',
          'packages': ['nope'],
        },
      });
      final result = call['result'] as Map<String, Object?>;
      expect(result['isError'], true);
      final text = ((result['content'] as List).first as Map)['text'] as String;
      expect(text, contains('"nope"'));
      // The server is still alive.
      expect((await request('ping'))['result'], isEmpty);
    });

    group('bad input files do not end the server (Q-15)', () {
      late Directory tmp;
      setUp(() => tmp = Directory.systemTemp.createTempSync('pubdelta_mcp_'));
      tearDown(() => tmp.deleteSync(recursive: true));

      test('Latin-1 CHANGELOG: answer with a warning, then ping', () async {
        final logs = Directory('${tmp.path}/logs')..createSync();
        File('${logs.path}/http.md').writeAsBytesSync(latin1Changelog());
        final call = await request('tools/call', {
          'name': 'changelog',
          'arguments': {
            'lockFile': exampleLock,
            'outdatedFile': 'example/outdated.json',
            'changelogDir': logs.path,
            'packages': ['http'],
            'offline': true,
          },
        });
        final result = call['result'] as Map<String, Object?>;
        expect(result['isError'], false);
        final text = [
          for (final c in result['content'] as List) (c as Map)['text'],
        ].join('\n');
        expect(text, contains('caf� option removed'));
        expect(text, contains('is not valid UTF-8'));
        expect((await request('ping'))['result'], isEmpty);
      });

      test('Latin-1 lock file: tool error, then ping', () async {
        final lock = File('${tmp.path}/pubspec.lock')
          ..writeAsBytesSync(latin1.encode('packages:\n  café: {}\n'));
        final call = await request('tools/call', {
          'name': 'plan',
          'arguments': {
            'lockFile': lock.path,
            'outdatedFile': 'example/outdated.json',
          },
        });
        final result = call['result'] as Map<String, Object?>;
        expect(result['isError'], true);
        final text =
            ((result['content'] as List).first as Map)['text'] as String;
        expect(text, contains('not valid UTF-8'));
        expect((await request('ping'))['result'], isEmpty);
      });

      test('Latin-1 outdated file: tool error, then ping', () async {
        final bad = File('${tmp.path}/outdated.json')
          ..writeAsBytesSync([...'{"packages":['.codeUnits, 0xE9]);
        final call = await request('tools/call', {
          'name': 'plan',
          'arguments': {'lockFile': exampleLock, 'outdatedFile': bad.path},
        });
        expect((call['result'] as Map)['isError'], true);
        expect((await request('ping'))['result'], isEmpty);
      });

      test('bytes that are not UTF-8 on stdin, then ping', () async {
        proc.stdin.add([
          ...'{"jsonrpc":"2.0","id":99,"method":"ping'.codeUnits,
          0xFF,
          ...'"}\n'.codeUnits,
        ]);
        expect(
          await lines.moveNext().timeout(const Duration(seconds: 30)),
          isTrue,
        );
        final reply = jsonDecode(lines.current) as Map<String, Object?>;
        expect(reply['id'], 99);
        expect((reply['error'] as Map)['code'], -32601);
        expect((await request('ping'))['result'], isEmpty);
      });
    });
  });

  group('McpServer.handleLine', () {
    final server = McpServer(env: const {'LANG': 'C'});

    test('unknown method with an id is a JSON-RPC error', () async {
      final r = await server.handleLine(
        '{"jsonrpc":"2.0","id":7,"method":"nope"}',
      );
      expect((r!['error'] as Map)['code'], -32601);
      expect(r['id'], 7);
    });

    test('unknown notification is ignored', () async {
      expect(
        await server.handleLine('{"jsonrpc":"2.0","method":"nope"}'),
        isNull,
      );
    });

    test('invalid JSON is a parse error', () async {
      final r = await server.handleLine('{oops');
      expect((r!['error'] as Map)['code'], -32700);
    });

    // Q-18: 머리글 없는 변경 기록의 대체 항목 제목이 한국어 MCP 응답에서도 한국어인지.
    test('PUBDELTA_LANG=ko: fallback entry title is Korean', () async {
      final dir = Directory.systemTemp.createTempSync('pubdelta_mcp_fb_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/http.md').writeAsStringSync('just text\nno headings\n');
      final ko = McpServer(env: const {'PUBDELTA_LANG': 'ko'});
      final r = await ko.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 2,
          'method': 'tools/call',
          'params': {
            'name': 'changelog',
            'arguments': {
              'lockFile': exampleLock,
              'packages': ['http'],
              'to': '1.6.0',
              'changelogDir': dir.path,
            },
          },
        }),
      );
      final result = r!['result'] as Map;
      expect(result['isError'], false);
      final text = ((result['content'] as List).first as Map)['text'] as String;
      expect(text.split('\n'), contains('### (앞 2줄)'));
      expect(text, contains('버전 머리글이 없어 앞 2줄만'));
      expect(text, isNot(contains('first 2 lines')));
    });

    test('plan include adds to dev, like the CLI', () async {
      final r = await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': 'plan',
            'arguments': {
              'lockFile': exampleLock,
              'outdatedFile': 'example/outdated.json',
              'include': ['transitive'],
            },
          },
        }),
      );
      final text =
          (((r!['result'] as Map)['content'] as List).first as Map)['text']
              as String;
      expect(text, contains('| lints |'));
      expect(text, contains('| async |'));
    });

    test('unknown tool is reported as a tool error', () async {
      final r = await server.handleLine(
        jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {'name': 'zzz'},
        }),
      );
      expect((r!['result'] as Map)['isError'], true);
    });

    test(
      'an unsupported protocol version gets the newest supported one',
      () async {
        final r = await server.handleLine(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': {'protocolVersion': '1999-01-01'},
          }),
        );
        expect(
          (r!['result'] as Map)['protocolVersion'],
          supportedProtocolVersions.first,
        );
      },
    );
  });
}
