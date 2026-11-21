import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

import 'support/fake_pub_server.dart';
import 'support/helpers.dart';

Version v(String s) => Version.parse(s);

String changelog(List<String> versions) =>
    versions.map((x) => '## $x\n\n- change in $x\n').join('\n');

void main() {
  late Directory tmp;
  late Directory cache;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pubdelta_src_');
    cache = Directory('${tmp.path}/cache')..createSync();
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ChangelogSources sources({
    String? dir,
    bool offline = false,
    String? override,
    Map<String, String> env = const {},
  }) => ChangelogSources(
    projectDir: tmp.path,
    environment: {'PUB_CACHE': cache.path, ...env},
    changelogDir: dir,
    offline: offline,
    hostedOverride: override,
  );

  void putCache(String host, String name, String version, String text) {
    final d = Directory('${cache.path}/hosted/$host/$name-$version')
      ..createSync(recursive: true);
    File('${d.path}/CHANGELOG.md').writeAsStringSync(text);
  }

  group('order: --changelog-dir, cache, hosted', () {
    test('--changelog-dir wins over cache and network', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.6.0', changelog: '## 1.6.0\n\nserver\n')],
      });
      addTearDown(server.close);
      final dir = Directory('${tmp.path}/logs')..createSync();
      File('${dir.path}/http.md').writeAsStringSync('## 1.6.0\n\nfrom dir\n');
      putCache(
        hostedDirName(server.url),
        'http',
        '1.6.0',
        '## 1.6.0\n\ncache\n',
      );

      final s = sources(dir: dir.path);
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: server.url),
        v('1.6.0'),
      );
      expect(r.origin, Origin.dir);
      expect(r.text, contains('from dir'));
      expect(server.requests, isEmpty);
    });

    test('the cache is used next: lowest cached version >= to', () async {
      for (final x in ['1.5.0', '1.6.0', '1.7.0']) {
        putCache(
          'pub.dev',
          'http',
          x,
          changelog([
            '1.7.0',
            '1.6.0',
            '1.5.0',
          ]).replaceAll('change in', 'cache $x change in'),
        );
      }
      // A different package whose name starts the same must not match.
      putCache('pub.dev', 'http_parser', '9.9.9', '## 9.9.9\n');

      final s = sources(offline: true);
      addTearDown(s.close);
      final r = await s.fetch(hosted('http', '1.2.2'), v('1.6.0'));
      expect(r.origin, Origin.cache);
      expect(
        r.text,
        contains('cache 1.6.0 change'),
        reason: '1.5.0 is below to, 1.7.0 is not the lowest',
      );
    });

    test('hosted: downloads the archive, with + encoded as %2B', () async {
      final server = await FakePubServer.start({
        'provider': [
          FakeVersion('6.1.2', changelog: changelog(['6.1.2'])),
          FakeVersion(
            '6.1.5+1',
            changelog: changelog(['6.1.5+1', '6.1.5', '6.1.4', '6.1.2']),
          ),
        ],
      });
      addTearDown(server.close);

      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('provider', '6.1.2', url: server.url),
        v('6.1.5+1'),
      );
      expect(r.origin, Origin.hosted);
      expect(r.text, contains('## 6.1.5+1'));
      expect(r.apiVersions, ['6.1.2', '6.1.5+1']);
      expect(
        server.requests,
        contains('/api/archives/provider-6.1.5%2B1.tar.gz'),
        reason: 'the archive_url from the API is used as is',
      );
    });

    test('PUBDELTA_HOSTED_URL override replaces the lock file URL', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.6.0', changelog: '## 1.6.0\n\nmirror\n')],
      });
      addTearDown(server.close);
      final s = sources(override: server.url);
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: 'http://127.0.0.1:1'),
        v('1.6.0'),
      );
      expect(r.text, contains('mirror'));
    });
  });

  group('--offline', () {
    test('makes no request and reports an offline failure', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.6.0', changelog: '## 1.6.0\n')],
      });
      addTearDown(server.close);
      final s = sources(offline: true);
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: server.url),
        v('1.6.0'),
      );
      expect(r.text, isNull);
      expect(r.failure?.kind, 'offline');
      expect(server.requests, isEmpty);
    });

    test('CLI: --offline with an empty cache exits 4 with a way out', () async {
      final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
      final (code, c) = await cli(
        ['log', 'http', '--to', '1.6.0', '--lock', lock, '--offline'],
        env: {'LANG': 'C', 'PUB_CACHE': cache.path},
      );
      expect(code, 4);
      expect(c.out.toString(), contains('--changelog-dir'));
      expect(c.err.toString(), contains('Exit code 4'));
      // Q-16: 안내가 목표 버전을 캐시에 받는 명령을 그대로 보여 준다 (dart pub get 은 현재 버전만 받는다)
      expect(
        c.out.toString(),
        contains('dart pub cache add http --version 1.6.0'),
      );
      expect(c.out.toString(), isNot(contains('dart pub get')));
    });

    test('the offline advice names the target version in ko too', () {
      final text = tr(Lang.ko, 'fetch.offline', ['http', '1.6.0']);
      expect(text, contains('목표 버전 1.6.0'));
      expect(text, contains('dart pub cache add http --version 1.6.0'));
    });
  });

  group('failures turn into exit code 4 with alternatives', () {
    test('connection refused', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.6.0')],
      });
      final dead = server.url;
      await server.close();

      final lock = writeLock(tmp, {
        'http': ('1.2.2', 'direct main'),
      }, url: dead);
      final (code, c) = await cli(
        ['log', 'http', '--to', '1.6.0', '--lock', lock],
        env: {'LANG': 'C', 'PUB_CACHE': cache.path},
      );
      expect(code, 4);
      final text = c.out.toString();
      expect(text, contains('cannot connect'));
      expect(text, contains('PUBDELTA_HOSTED_URL'));
      expect(text, contains('--changelog-dir'));
    });

    test('target version not on the repository', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.2.2'), const FakeVersion('1.5.0')],
      });
      addTearDown(server.close);
      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: server.url),
        v('1.6.0'),
      );
      expect(r.failure?.kind, 'versionNotFound');
    });

    test('archive without CHANGELOG', () async {
      final server = await FakePubServer.start({
        'http': [const FakeVersion('1.6.0')],
      });
      addTearDown(server.close);
      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: server.url),
        v('1.6.0'),
      );
      expect(r.failure?.kind, 'noChangelog');
    });

    test('unknown package is a 404', () async {
      final server = await FakePubServer.start({});
      addTearDown(server.close);
      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('ghost', '1.0.0', url: server.url),
        v('1.1.0'),
      );
      expect(r.failure?.kind, 'notFound');
    });
  });

  group('missingInChangelog', () {
    test(
      'versions the API lists but the changelog lacks are reported',
      () async {
        final server = await FakePubServer.start({
          'http': [
            const FakeVersion('1.2.2'),
            const FakeVersion('1.5.0-beta'),
            const FakeVersion('1.5.0-beta.2'),
            FakeVersion('1.5.0', changelog: changelog(['1.5.0', '1.2.2'])),
          ],
        });
        addTearDown(server.close);
        final s = sources();
        addTearDown(s.close);
        final pkg = hosted('http', '1.2.2', url: server.url);
        final fetched = await s.fetch(pkg, v('1.5.0'));
        final log = sliceChangelog(
          pkg: pkg,
          from: v('1.2.2'),
          to: v('1.5.0'),
          fetched: fetched,
        );
        expect(log.missingInChangelog, ['1.5.0-beta.2', '1.5.0-beta']);
        expect(log.entries.map((e) => '${e.version}'), ['1.5.0']);
        expect(log.confidence, 'high');
      },
    );
  });

  group('path, git and sdk dependencies', () {
    test(
      'path: reads the local CHANGELOG, range unknown, low confidence',
      () async {
        final local = Directory('${tmp.path}/local_pkg')..createSync();
        File(
          '${local.path}/CHANGELOG.md',
        ).writeAsStringSync(changelog(['2.0.0', '1.0.0']));
        final pkg = LockedPackage(
          name: 'local_pkg',
          version: v('1.0.0'),
          dependency: 'direct main',
          source: 'path',
          path: 'local_pkg',
          pathIsRelative: true,
        );
        final s = sources();
        addTearDown(s.close);
        final fetched = await s.fetch(pkg, v('2.0.0'));
        expect(fetched.origin, Origin.path);
        expect(fetched.rangeUnknown, isTrue);
        final log = sliceChangelog(
          pkg: pkg,
          from: v('1.0.0'),
          to: v('2.0.0'),
          fetched: fetched,
        );
        expect(log.confidence, 'low');
        expect(
          log.notices.map((n) => n.key),
          contains('source.pathRangeUnknown'),
        );
      },
    );

    for (final source in ['git', 'sdk']) {
      test('$source: no changelog is shown', () async {
        final pkg = LockedPackage(
          name: 'thing',
          version: v('1.0.0'),
          dependency: 'direct main',
          source: source,
        );
        final s = sources();
        addTearDown(s.close);
        final fetched = await s.fetch(pkg, v('2.0.0'));
        expect(fetched.text, isNull);
        expect(
          fetched.failure,
          isNull,
          reason: 'not an error, just nothing to read',
        );
        final log = sliceChangelog(
          pkg: pkg,
          from: v('1.0.0'),
          to: v('2.0.0'),
          fetched: fetched,
        );
        expect(log.confidence, 'none');
        expect(log.notices.map((n) => n.key), contains('source.noChangelog'));
      });
    }
  });

  group('changelogs that are not UTF-8 or cannot be read (Q-15)', () {
    // 네 경로(--changelog-dir·path·pub 캐시·hosted 아카이브)가 모두 같은 동작이어야 한다:
    // 죽지 않고, 깨진 글자만 U+FFFD 로 바꾸고, source.notUtf8 경고를 남긴다.
    void expectReplacedWithWarning(FetchedChangelog r, Origin origin) {
      expect(r.failure, isNull);
      expect(r.origin, origin);
      expect(r.text, contains('caf� option removed'));
      expect(r.notices, contains(const Notice('source.notUtf8', ['http'])));
      // 깨진 글자가 있어도 구간 자르기와 신호 찾기는 그대로 된다
      final log = sliceChangelog(
        pkg: hosted('http', '1.2.2'),
        from: v('1.2.2'),
        to: v('1.6.0'),
        fetched: r,
      );
      expect(log.entries.map((e) => '${e.version}'), ['1.6.0', '1.5.0']);
      expect(log.strongest, SignalLevel.strong);
      expect(log.notices.map((n) => n.key), contains('source.notUtf8'));
    }

    test('--changelog-dir file', () async {
      final dir = Directory('${tmp.path}/logs')..createSync();
      File('${dir.path}/http.md').writeAsBytesSync(latin1Changelog());
      final s = sources(dir: dir.path, offline: true);
      addTearDown(s.close);
      expectReplacedWithWarning(
        await s.fetch(hosted('http', '1.2.2'), v('1.6.0')),
        Origin.dir,
      );
    });

    test('pub cache file', () async {
      final d = Directory('${cache.path}/hosted/pub.dev/http-1.6.0')
        ..createSync(recursive: true);
      File('${d.path}/CHANGELOG.md').writeAsBytesSync(latin1Changelog());
      final s = sources(offline: true);
      addTearDown(s.close);
      expectReplacedWithWarning(
        await s.fetch(hosted('http', '1.2.2'), v('1.6.0')),
        Origin.cache,
      );
    });

    test('path dependency file', () async {
      final local = Directory('${tmp.path}/http')..createSync();
      File('${local.path}/CHANGELOG.md').writeAsBytesSync(latin1Changelog());
      final pkg = LockedPackage(
        name: 'http',
        version: v('1.2.2'),
        dependency: 'direct main',
        source: 'path',
        path: 'http',
        pathIsRelative: true,
      );
      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(pkg, v('1.6.0'));
      expect(r.origin, Origin.path);
      expect(r.text, contains('caf�'));
      expect(r.notices.map((n) => n.key), [
        'source.pathRangeUnknown',
        'source.notUtf8',
      ]);
    });

    test('hosted archive file (same rule as local files)', () async {
      final server = await FakePubServer.start({
        'http': [FakeVersion('1.6.0', changelogBytes: latin1Changelog())],
      });
      addTearDown(server.close);
      final s = sources();
      addTearDown(s.close);
      expectReplacedWithWarning(
        await s.fetch(hosted('http', '1.2.2', url: server.url), v('1.6.0')),
        Origin.hosted,
      );
    });

    test('a UTF-8 byte order mark does not hide the first heading', () async {
      final dir = Directory('${tmp.path}/logs')..createSync();
      File('${dir.path}/http.md').writeAsBytesSync([
        0xEF,
        0xBB,
        0xBF,
        ...'## 1.6.0\n\n- new\n'.codeUnits,
      ]);
      final s = sources(dir: dir.path, offline: true);
      addTearDown(s.close);
      final r = await s.fetch(hosted('http', '1.2.2'), v('1.6.0'));
      expect(r.notices, isEmpty);
      final log = sliceChangelog(
        pkg: hosted('http', '1.2.2'),
        from: v('1.2.2'),
        to: v('1.6.0'),
        fetched: r,
      );
      expect(log.entries.map((e) => '${e.version}'), ['1.6.0']);
    });

    test(
      'an unreadable file is an "unreadable" failure, not a crash',
      () async {
        final dir = Directory('${tmp.path}/logs')..createSync();
        final file = File('${dir.path}/http.md')
          ..writeAsStringSync('## 1.6.0\n');
        if (!makeUnreadable(file.path)) {
          markTestSkipped('cannot make a file unreadable here (Windows/root)');
          return;
        }
        final s = sources(dir: dir.path, offline: true);
        addTearDown(s.close);
        final r = await s.fetch(hosted('http', '1.2.2'), v('1.6.0'));
        expect(r.text, isNull);
        expect(r.failure?.kind, 'unreadable');
        expect(r.failure?.detail, contains('http.md'));
      },
    );

    test(
      'CLI: Latin-1 changelog gives exit 0 and a warning in en and ko',
      () async {
        final dir = Directory('${tmp.path}/logs')..createSync();
        File('${dir.path}/http.md').writeAsBytesSync(latin1Changelog());
        final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
        for (final (lang, warning) in [
          ('en', 'is not valid UTF-8'),
          ('ko', '올바른 UTF-8 이 아니어서'),
        ]) {
          final (code, c) = await cli(
            [
              'log',
              'http',
              '--to',
              '1.6.0',
              '--lock',
              lock,
              '--changelog-dir',
              dir.path,
              '--lang',
              lang,
            ],
            env: {'LANG': 'C', 'PUB_CACHE': cache.path},
          );
          expect(code, 0, reason: c.err.toString());
          expect(c.out.toString(), contains('caf� option removed'));
          // 패키지 경고는 그 패키지 블록 안(stdout)에 나온다
          expect(c.out.toString(), contains(warning));
          expect(c.err.toString(), isNot(contains('Unhandled exception')));
        }
      },
    );
  });

  group('repository URL and API answers that are not usable', () {
    test('PUBDELTA_HOSTED_URL without a scheme is badUrl, exit 4', () async {
      final lock = writeLock(tmp, {'http': ('1.2.2', 'direct main')});
      for (final (lang, text) in [
        ('en', 'the repository URL is not valid'),
        ('ko', '저장소 주소가 올바르지 않습니다'),
      ]) {
        final (code, c) = await cli(
          ['log', 'http', '--to', '1.6.0', '--lock', lock, '--lang', lang],
          env: {
            'LANG': 'C',
            'PUB_CACHE': cache.path,
            'PUBDELTA_HOSTED_URL': 'mirror.invalid',
          },
        );
        expect(code, 4, reason: c.err.toString());
        expect(c.out.toString(), contains(text));
      }
    });

    test('a non-string archive_url does not crash', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        request.response.write(
          '{"versions":[{"version":"1.6.0","archive_url":5}]}',
        );
        await request.response.close();
      });
      final s = sources();
      addTearDown(s.close);
      final r = await s.fetch(
        hosted('http', '1.2.2', url: 'http://127.0.0.1:${server.port}'),
        v('1.6.0'),
      );
      expect(r.failure?.kind, 'versionNotFound');
    });
  });

  group('cache folder names', () {
    test('match the names pub uses', () {
      expect(hostedDirName('https://pub.dev'), 'pub.dev');
      expect(hostedDirName('http://localhost:8080'), 'localhost%588080');
      expect(hostedDirName('https://example.com/pub/'), 'example.com%47pub');
    });
  });
}
