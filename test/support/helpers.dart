import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';

/// Writes a lock file for hosted packages into [dir] and returns its path.
///
/// [packages] maps a name to `(version, dependency)`.
String writeLock(
  Directory dir,
  Map<String, (String, String)> packages, {
  String url = 'https://pub.dev',
  String extra = '',
}) {
  final b = StringBuffer('packages:\n');
  packages.forEach((name, spec) {
    b.write('''
  $name:
    dependency: "${spec.$2}"
    description:
      name: $name
      sha256: "${'0' * 64}"
      url: "$url"
    source: hosted
    version: "${spec.$1}"
''');
  });
  b.write(extra);
  b.write('sdks:\n  dart: ">=3.0.0 <4.0.0"\n');
  final file = File('${dir.path}/pubspec.lock')
    ..writeAsStringSync(b.toString());
  return file.path;
}

/// A locked hosted package for tests that call the sources directly.
LockedPackage hosted(
  String name,
  String version, {
  String url = 'https://pub.dev',
  String dependency = 'direct main',
}) => LockedPackage(
  name: name,
  version: Version.parse(version),
  dependency: dependency,
  source: 'hosted',
  hostedUrl: url,
);

/// A CHANGELOG saved as Latin-1, not UTF-8: "é" is the single byte 0xE9.
/// pub accepts such files with only a warning, so real packages have them.
List<int> latin1Changelog() => latin1.encode(
  '## 1.6.0\n\n- **Breaking** café option removed\n\n'
  '## 1.5.0\n\n- résumé support\n',
);

/// Makes the file at [path] unreadable for this user. Returns false where
/// that is not possible (Windows, or running as root, who can read anyway),
/// so a test can skip only that one check.
bool makeUnreadable(String path) {
  if (Platform.isWindows) return false;
  final r = Process.runSync('chmod', ['000', path]);
  if (r.exitCode != 0) return false;
  try {
    File(path).readAsBytesSync();
    return false; // root 는 권한과 상관없이 읽을 수 있다
  } on FileSystemException {
    return true;
  }
}

/// Captures what the CLI prints.
class Captured {
  final StringBuffer out = StringBuffer();
  final StringBuffer err = StringBuffer();
}

/// Runs the CLI in-process with a fixed environment.
///
/// By default the language is pinned to English so that tests do not depend
/// on the machine's `LANG`.
Future<(int, Captured)> cli(
  List<String> args, {
  Map<String, String> env = const {'LANG': 'C'},
  ProcessRunner runner = defaultRunner,
}) async {
  final c = Captured();
  final code = await runCli(
    args,
    env: env,
    out: c.out,
    err: c.err,
    runner: runner,
  );
  return (code, c);
}
