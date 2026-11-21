import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'i18n.dart';
import 'lockfile.dart';
import 'text_file.dart';
import 'version_range.dart';

/// Which `pub outdated` column to use as the upgrade target.
enum Mode { upgradable, resolvable, latest }

/// What `dart pub outdated --json` (or the dry-run fallback) says about one
/// package.
class OutdatedInfo {
  const OutdatedInfo({
    this.current,
    this.upgradable,
    this.resolvable,
    this.latest,
    this.discontinued = false,
    this.retracted = false,
    this.advisory = false,
  });

  final Version? current;
  final Version? upgradable;
  final Version? resolvable;
  final Version? latest;
  final bool discontinued;
  final bool retracted;
  final bool advisory;

  /// The target for [mode]; falls back to the next-best column.
  Version? target(Mode mode) {
    switch (mode) {
      case Mode.upgradable:
        return upgradable;
      case Mode.resolvable:
        return resolvable ?? upgradable;
      case Mode.latest:
        return latest ?? resolvable ?? upgradable;
    }
  }
}

/// One package that has an upgrade target.
class PlanEntry {
  const PlanEntry({
    required this.package,
    required this.from,
    required this.to,
    required this.bump,
    required this.flags,
  });

  final LockedPackage package;
  final Version from;
  final Version to;
  final Bump bump;

  /// `retracted`, `discontinued`, `advisory`.
  final List<String> flags;

  String get name => package.name;
}

/// Runs an external program; replaceable in tests.
typedef ProcessRunner =
    Future<ProcessResult> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

Future<ProcessResult> defaultRunner(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  // 하위 프로세스 출력에 UTF-8 이 아닌 바이트가 섞여도 예외로 죽지 않게 한다
  const decoder = Utf8Decoder(allowMalformed: true);
  final out = process.stdout.transform(decoder).join();
  final err = process.stderr.transform(decoder).join();
  try {
    final code = await process.exitCode.timeout(processTimeout);
    return ProcessResult(process.pid, code, await out, await err);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    // 기다리지 않는 출력 Future 의 오류가 처리 안 된 예외가 되지 않게 한다
    out.ignore();
    err.ignore();
    return ProcessResult(
      process.pid,
      124,
      '',
      // 사용자에게 보일 수 있으니 메시지 키로 둔다(보여 줄 때 번역)
      messageRef('outdated.timedOut', ['${processTimeout.inSeconds}']),
    );
  }
}

/// How long `dart pub ...` may run before it is killed and the fallback or
/// the exit-5 advice is used. Tests may shorten it.
Duration processTimeout = const Duration(seconds: 120);

/// Result of [loadOutdated].
class OutdatedResult {
  OutdatedResult(this.info, this.notices);

  final Map<String, OutdatedInfo> info;
  final List<Notice> notices;
}

Version? _versionOf(Object? column) {
  if (column is Map && column['version'] is String) {
    try {
      return Version.parse(column['version'] as String);
    } on FormatException {
      return null;
    }
  }
  return null;
}

/// Parses the output of `dart pub outdated --json`.
Map<String, OutdatedInfo> parseOutdatedJson(String text) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw PubdeltaException(5, 'outdated.badJson', const []);
  }
  if (decoded is! Map || decoded['packages'] is! List) {
    throw PubdeltaException(5, 'outdated.badJson', const []);
  }
  final result = <String, OutdatedInfo>{};
  for (final item in decoded['packages'] as List<Object?>) {
    if (item is! Map || item['package'] is! String) continue;
    result[item['package'] as String] = OutdatedInfo(
      current: _versionOf(item['current']),
      upgradable: _versionOf(item['upgradable']),
      resolvable: _versionOf(item['resolvable']),
      latest: _versionOf(item['latest']),
      discontinued: item['isDiscontinued'] == true,
      retracted: item['isCurrentRetracted'] == true,
      advisory: item['isCurrentAffectedByAdvisory'] == true,
    );
  }
  return result;
}

final RegExp _dryRunLine = RegExp(
  r'^>\s+(\S+)\s+(\S+)(?:\s+\(was\s+(\S+)\))?',
  multiLine: true,
);

/// Parses `dart pub upgrade --dry-run` text such as `> http 1.6.0 (was 1.2.2)`.
///
/// Only upgrade lines (`>`) count; the same version is used for every mode.
Map<String, OutdatedInfo> parseDryRun(String text) {
  final result = <String, OutdatedInfo>{};
  for (final m in _dryRunLine.allMatches(text)) {
    final to = _tryParse(m.group(2)!);
    if (to == null) continue;
    result[m.group(1)!] = OutdatedInfo(
      current: m.group(3) == null ? null : _tryParse(m.group(3)!),
      upgradable: to,
      resolvable: to,
      latest: to,
    );
  }
  return result;
}

Version? _tryParse(String s) {
  try {
    return Version.parse(s);
  } on FormatException {
    return null;
  }
}

/// Gets upgrade information for the project in [projectDir].
///
/// Order: [outdatedFile] if given; else `dart pub outdated --json`; if that
/// fails (no network, TLS interception, ...) `dart pub upgrade --offline
/// --dry-run --major-versions` with a warning. Both failing is exit code 5.
Future<OutdatedResult> loadOutdated({
  required String projectDir,
  String? outdatedFile,
  Map<String, String>? environment,
  ProcessRunner runner = defaultRunner,
}) async {
  if (outdatedFile != null) {
    final file = File(outdatedFile);
    if (!await file.exists()) {
      throw PubdeltaException(3, 'input.noOutdatedFile', [outdatedFile]);
    }
    final TextFile read;
    try {
      read = await readTextFile(file);
    } on UnreadableFile catch (e) {
      throw PubdeltaException(3, 'input.cannotRead', [outdatedFile, e.reason]);
    }
    // dart pub outdated --json 은 UTF-8 JSON 을 낸다 — 아니면 잘못 저장된 파일
    if (read.hadInvalidUtf8) {
      throw PubdeltaException(5, 'outdated.badFile', [outdatedFile]);
    }
    final Map<String, OutdatedInfo> parsed;
    try {
      parsed = parseOutdatedJson(read.text);
    } on PubdeltaException {
      throw PubdeltaException(5, 'outdated.badFile', [outdatedFile]);
    }
    return OutdatedResult(parsed, [
      Notice('outdated.fromFile', [outdatedFile]),
    ]);
  }

  String firstFailure = '';
  try {
    final r = await runner(
      'dart',
      ['pub', 'outdated', '--json'],
      workingDirectory: projectDir,
      environment: environment,
    );
    if (r.exitCode == 0) {
      return OutdatedResult(parseOutdatedJson('${r.stdout}'), []);
    }
    firstFailure = _firstLine('${r.stderr}');
  } on ProcessException catch (e) {
    firstFailure = e.message;
  } on PubdeltaException catch (e) {
    // 영어로 굳히지 않고 메시지 키로 넘겨, 보여 줄 때 고른 언어로 바뀌게 한다.
    firstFailure = messageRef(e.key, e.args);
  }

  try {
    final r = await runner(
      'dart',
      ['pub', 'upgrade', '--offline', '--dry-run', '--major-versions'],
      workingDirectory: projectDir,
      environment: environment,
    );
    if (r.exitCode == 0) {
      return OutdatedResult(parseDryRun('${r.stdout}'), [
        Notice('outdated.fallback', [firstFailure]),
      ]);
    }
    throw PubdeltaException(5, 'outdated.failed', [
      firstFailure,
      _firstLine('${r.stderr}'),
    ]);
  } on ProcessException catch (e) {
    throw PubdeltaException(5, 'outdated.failed', [firstFailure, e.message]);
  }
}

String _firstLine(String text) {
  for (final line in text.split('\n')) {
    if (line.trim().isNotEmpty) return line.trim();
  }
  return messageRef('outdated.noOutput');
}

/// Builds plan entries for locked packages that have an upgrade target.
///
/// [include] may contain `dev` and `transitive`; direct main (and overridden)
/// packages are always included.
List<PlanEntry> buildPlanEntries(
  List<LockedPackage> locked,
  Map<String, OutdatedInfo> info, {
  required Mode mode,
  Set<String> include = const {'dev'},
}) {
  final entries = <PlanEntry>[];
  for (final pkg in locked) {
    if (pkg.dependency == 'direct dev' && !include.contains('dev')) continue;
    if (!pkg.isDirect && !include.contains('transitive')) continue;
    final i = info[pkg.name];
    if (i == null) continue;
    final to = i.target(mode);
    if (to == null || to <= pkg.version) continue;
    entries.add(
      PlanEntry(
        package: pkg,
        from: pkg.version,
        to: to,
        bump: classifyBump(pkg.version, to),
        flags: [
          if (i.retracted) 'retracted',
          if (i.discontinued) 'discontinued',
          if (i.advisory) 'advisory',
        ],
      ),
    );
  }
  entries.sort((a, b) => a.name.compareTo(b.name));
  return entries;
}
