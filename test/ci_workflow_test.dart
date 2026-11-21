// Static checks that keep the CI definition, the test settings, pubspec.yaml
// and pubspec.lock in agreement. If someone switches CI back to `stable` or
// drops the integration tag, plain `dart test` fails here first.
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

/// The SDK version CI uses; the local checks were made with it too.
const pinnedSdk = '3.8.1';

/// Steps CI must run, in this order (the same ones as README "Development").
const expectedRuns = [
  'dart pub get',
  'dart format --output=none --set-exit-if-changed .',
  'dart analyze',
  'dart test',
];

YamlMap readYaml(String path) =>
    loadYaml(File(path).readAsStringSync()) as YamlMap;

void main() {
  final ci = readYaml('.github/workflows/ci.yml');
  final jobs = (ci['jobs'] as YamlMap).values.cast<YamlMap>().toList();
  final steps =
      [for (final job in jobs) ...(job['steps'] as YamlList)].cast<YamlMap>();

  group('ci.yml', () {
    test('runs on a fixed runner image with a time limit', () {
      for (final job in jobs) {
        expect(job['runs-on'], 'ubuntu-24.04');
        expect(job['timeout-minutes'], isA<int>());
      }
    });

    test('has no schedule trigger', () {
      // package:yaml 은 `on` 을 문자열 키로 읽지만, YAML 1.1 식 true 도 받아 준다
      final on = ci['on'] ?? ci[true];
      expect(on, isA<YamlMap>());
      expect((on as YamlMap).containsKey('schedule'), isFalse);
      expect(on.keys, containsAll(['push', 'pull_request']));
    });

    test('uses exactly the pinned action versions', () {
      final uses = [
        for (final s in steps)
          if (s['uses'] != null) s['uses'] as String,
      ];
      expect(uses, ['actions/checkout@v6.1.0', 'dart-lang/setup-dart@v1.8.2']);
    });

    test('pins the Dart SDK to $pinnedSdk, not a channel', () {
      final setup = steps.singleWhere(
        (s) => '${s['uses']}'.startsWith('dart-lang/setup-dart@'),
      );
      final sdk = '${(setup['with'] as YamlMap)['sdk']}';
      expect(sdk, isNot(anyOf('stable', 'beta', 'dev', 'main')));
      expect(sdk, pinnedSdk);
    });

    test('runs pub get, format, analyze and test in this order', () {
      final runs = [
        for (final s in steps)
          if (s['run'] != null) '${s['run']}'.trim(),
      ];
      expect(runs, expectedRuns);
    });

    test('the test step does not run skipped or tagged tests', () {
      final testRun = steps
          .map((s) => '${s['run'] ?? ''}')
          .singleWhere((r) => r.trim().startsWith('dart test'));
      for (final banned in [
        '-t ',
        '--tags',
        '--run-skipped',
        '-P',
        '--preset',
      ]) {
        expect(testRun, isNot(contains(banned)));
      }
    });
  });

  group('SDK constraints', () {
    final pinned = Version.parse(pinnedSdk);

    test('pubspec.yaml environment.sdk allows the CI SDK', () {
      final pubspec = readYaml('pubspec.yaml');
      final sdk = (pubspec['environment'] as YamlMap)['sdk'] as String;
      expect(VersionConstraint.parse(sdk).allows(pinned), isTrue, reason: sdk);
    });

    test('pubspec.lock sdks.dart allows the CI SDK', () {
      final lock = readYaml('pubspec.lock');
      final sdk = (lock['sdks'] as YamlMap)['dart'] as String;
      expect(VersionConstraint.parse(sdk).allows(pinned), isTrue, reason: sdk);
    });
  });

  group('dart_test.yaml', () {
    test('skips the integration tag with a reason', () {
      final config = readYaml('dart_test.yaml');
      final tag = (config['tags'] as YamlMap)['integration'] as YamlMap;
      final skip = tag['skip'];
      expect(skip, isA<String>());
      expect((skip as String).trim(), isNotEmpty);
      expect(skip, contains('--run-skipped -t integration'));
    });

    test('tests that start the real pub carry the integration tag', () {
      // 실제 pub 를 띄우는 시험 = buildPlan( 를 부르면서 PUB_HOSTED_URL 을 넘기는 파일
      final self = 'ci_workflow_test.dart';
      final files = Directory('test')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('_test.dart'))
          .where((f) => !f.path.endsWith(self));
      final realPub = [
        for (final f in files)
          if (f.readAsStringSync() case final src
              when src.contains('buildPlan(') && src.contains('PUB_HOSTED_URL'))
            (f.path, src),
      ];
      expect(realPub, isNotEmpty, reason: 'plan_test.dart has one');
      final tagged = RegExp(
        r'''tags:\s*(\[\s*)?['"]integration['"]|@Tags\(\s*\[\s*['"]integration['"]''',
      );
      for (final (path, src) in realPub) {
        expect(tagged.hasMatch(src), isTrue, reason: path);
      }
    });
  });
}
