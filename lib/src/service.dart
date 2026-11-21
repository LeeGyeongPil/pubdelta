import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'changelog_parser.dart';
import 'hosted_client.dart';
import 'i18n.dart';
import 'lockfile.dart';
import 'outdated.dart';
import 'signals.dart';
import 'sources.dart';
import 'version_range.dart';

/// Inputs shared by `plan` and `log`.
class PlanRequest {
  const PlanRequest({
    required this.lockFile,
    this.outdatedFile,
    this.mode = Mode.resolvable,
    this.include = const {'dev'},
    this.environment = const {},
    this.runner = defaultRunner,
  });

  final String lockFile;
  final String? outdatedFile;
  final Mode mode;
  final Set<String> include;
  final Map<String, String> environment;
  final ProcessRunner runner;

  String get projectDir => File(lockFile).absolute.parent.path;
}

/// Result of [buildPlan].
class PlanResult {
  PlanResult(this.entries, this.notices);

  final List<PlanEntry> entries;
  final List<Notice> notices;
}

/// Reads the lock file and upgrade information and decides from -> to.
Future<PlanResult> buildPlan(PlanRequest request) async {
  final locked = await readLockfile(request.lockFile);
  final outdated = await loadOutdated(
    projectDir: request.projectDir,
    outdatedFile: request.outdatedFile,
    environment: request.environment,
    runner: request.runner,
  );
  final entries = buildPlanEntries(
    locked,
    outdated.info,
    mode: request.mode,
    include: request.include,
  );
  return PlanResult(entries, outdated.notices);
}

/// One changelog entry inside the (from, to] range.
class Entry {
  Entry({
    required this.version,
    required this.title,
    required this.tags,
    required this.signals,
    required this.body,
    required this.major,
    this.trimmed = false,
    this.fallbackLines,
  });

  final Version version;

  /// Heading text from the changelog. For a fallback entry this is a fixed
  /// English label kept for JSON; text/md output use [fallbackLines] instead
  /// and translate it (entry.fallback).
  final String title;

  /// Set only when the changelog had no version headings and this entry
  /// carries the first N lines of the file instead.
  final int? fallbackLines;
  final Set<String> tags;
  final List<Signal> signals;
  final String body;

  /// True when this version starts a new breaking unit (new major, or new
  /// minor for 0.x) compared with the version before it.
  final bool major;

  /// True when the budget cut the body down to the signal lines.
  final bool trimmed;

  SignalLevel? get strongest => strongestLevel(signals);

  Entry withBody(String newBody, {bool trimmed = true}) => Entry(
    version: version,
    title: title,
    tags: tags,
    signals: signals,
    body: newBody,
    major: major,
    trimmed: trimmed,
    fallbackLines: fallbackLines,
  );
}

/// The sliced changelog of one package.
class PackageLog {
  PackageLog({
    required this.name,
    required this.dependency,
    required this.source,
    required this.from,
    required this.to,
    required this.bump,
    required this.flags,
    required this.confidence,
    required this.origin,
    required this.entries,
    required this.missingInChangelog,
    required this.notices,
  });

  final String name;
  final String dependency;
  final String source;
  final Version from;
  final Version to;
  final Bump bump;
  final List<String> flags;

  /// `high`, `medium`, `low` or `none`.
  final String confidence;
  final Origin origin;

  /// Newest first.
  final List<Entry> entries;

  /// Versions in the range that the hosted API lists but the changelog lacks.
  final List<String> missingInChangelog;
  final List<Notice> notices;

  SignalLevel? get strongest {
    SignalLevel? best;
    for (final e in entries) {
      final s = e.strongest;
      if (s != null && (best == null || s.index < best.index)) best = s;
    }
    return best;
  }

  PackageLog withEntries(List<Entry> newEntries) => PackageLog(
    name: name,
    dependency: dependency,
    source: source,
    from: from,
    to: to,
    bump: bump,
    flags: flags,
    confidence: confidence,
    origin: origin,
    entries: newEntries,
    missingInChangelog: missingInChangelog,
    notices: notices,
  );
}

/// Result of [buildLog] before the budget is applied.
class LogResult {
  LogResult(this.packages, this.notices, this.failures);

  final List<PackageLog> packages;

  /// Run-level notices (outdated fallback, up-to-date packages).
  final List<Notice> notices;

  /// Packages whose changelog could not be obtained, with the reason.
  final Map<String, FetchFailure> failures;
}

/// Inputs for [buildLog].
class LogRequest {
  const LogRequest({
    required this.plan,
    this.packages = const [],
    this.all = false,
    this.from,
    this.to,
    this.changelogDir,
    this.offline = false,
    this.hostedOverride,
    this.onFetch,
  });

  final PlanRequest plan;

  /// Package names; ignored when [all] is true.
  final List<String> packages;
  final bool all;
  final String? from;
  final String? to;
  final String? changelogDir;
  final bool offline;
  final String? hostedOverride;
  final void Function(String name)? onFetch;
}

/// Builds the sliced changelogs for the requested packages.
Future<LogResult> buildLog(LogRequest request) async {
  final locked = await readLockfile(request.plan.lockFile);
  final byName = {for (final p in locked) p.name: p};
  final notices = <Notice>[
    if (request.changelogDir != null)
      Notice('log.usingDir', [request.changelogDir!]),
  ];

  final fromFlag =
      request.from == null ? null : parseVersion(request.from!, what: '--from');
  final toFlag =
      request.to == null ? null : parseVersion(request.to!, what: '--to');

  // Targets: (package, from, to).
  final targets = <(LockedPackage, Version, Version)>[];

  if (!request.all) {
    for (final name in request.packages) {
      if (!byName.containsKey(name)) {
        throw PubdeltaException(3, 'input.unknownPackage', [name]);
      }
    }
  }

  final needsPlan = request.all || toFlag == null;
  PlanResult? plan;
  if (needsPlan) {
    plan = await buildPlan(
      PlanRequest(
        lockFile: request.plan.lockFile,
        outdatedFile: request.plan.outdatedFile,
        mode: request.plan.mode,
        // 이름으로 고른 패키지는 종류(dev·transitive)와 상관없이 목표 버전을 찾는다
        include:
            request.all
                ? request.plan.include
                : {...request.plan.include, 'dev', 'transitive'},
        environment: request.plan.environment,
        runner: request.plan.runner,
      ),
    );
    notices.addAll(plan.notices);
  }

  if (request.all) {
    for (final e in plan!.entries) {
      targets.add((e.package, e.from, e.to));
    }
  } else {
    for (final name in request.packages) {
      final pkg = byName[name]!;
      final from = fromFlag ?? pkg.version;
      Version? to = toFlag;
      if (to == null) {
        for (final e in plan!.entries) {
          if (e.name == name) to = e.to;
        }
      }
      if (to == null || to == from) {
        notices.add(Notice('log.upToDate', [name, '$from']));
        continue;
      }
      validateRange(from, to, package: name);
      targets.add((pkg, from, to));
    }
  }

  final flagsByName = <String, List<String>>{
    if (plan != null)
      for (final e in plan.entries) e.name: e.flags,
  };

  final sources = ChangelogSources(
    projectDir: request.plan.projectDir,
    environment: request.plan.environment,
    changelogDir: request.changelogDir,
    offline: request.offline,
    hostedOverride: request.hostedOverride,
    onFetch: request.onFetch,
  );
  final packages = <PackageLog>[];
  final failures = <String, FetchFailure>{};
  try {
    for (final (pkg, from, to) in targets) {
      final fetched = await sources.fetch(pkg, to);
      if (fetched.failure != null) failures[pkg.name] = fetched.failure!;
      packages.add(
        sliceChangelog(
          pkg: pkg,
          from: from,
          to: to,
          fetched: fetched,
          flags: flagsByName[pkg.name] ?? const [],
        ),
      );
    }
  } finally {
    sources.close();
  }

  packages.sort(_comparePackages);
  return LogResult(packages, notices, failures);
}

int _comparePackages(PackageLog a, PackageLog b) {
  final sa = a.strongest?.index ?? 99;
  final sb = b.strongest?.index ?? 99;
  if (sa != sb) return sa.compareTo(sb);
  final ma = a.bump == Bump.major ? 0 : 1;
  final mb = b.bump == Bump.major ? 0 : 1;
  if (ma != mb) return ma.compareTo(mb);
  return a.name.compareTo(b.name);
}

/// Cuts a fetched changelog down to (from, to] and attaches signals.
///
/// This is the core of the tool and has no I/O, so tests call it directly.
PackageLog sliceChangelog({
  required LockedPackage pkg,
  required Version from,
  required Version to,
  required FetchedChangelog fetched,
  List<String> flags = const [],
}) {
  final notices = <Notice>[...fetched.notices];
  final failure = fetched.failure;
  if (failure != null) {
    notices.add(Notice('fetch.${failure.kind}', [pkg.name, failure.detail]));
  }
  final text = fetched.text;
  final bump = classifyBump(from, to);

  PackageLog result(
    String confidence,
    List<Entry> entries, [
    List<String> missing = const [],
  ]) => PackageLog(
    name: pkg.name,
    dependency: pkg.dependency,
    source: pkg.source,
    from: from,
    to: to,
    bump: bump,
    flags: flags,
    confidence: confidence,
    origin: fetched.origin,
    entries: entries,
    missingInChangelog: missing,
    notices: notices,
  );

  if (text == null) return result('none', const []);

  final parsed = parseChangelog(text);
  notices.addAll(parsed.notices);

  if (parsed.isFallback) {
    // 빈 파일이면 보여 줄 줄이 없다 — 0줄 항목을 만들지 않고 경고(parse.empty)만 남긴다.
    if (parsed.fallbackLines.isEmpty) return result('low', const []);
    final count = parsed.fallbackLines.length;
    return result('low', [
      Entry(
        version: to,
        // JSON 용 고정 이름. 화면(text·md)에서는 fallbackLines 로 언어별 제목을 만든다.
        title: '(first $count lines)',
        tags: const {},
        signals: detectSignals(parsed.fallbackLines),
        body: parsed.fallbackLines.join('\n'),
        major: false,
        fallbackLines: count,
      ),
    ]);
  }

  // All versions up to `to`, ascending, to find each entry's predecessor.
  final known =
      <Version>{
          ...parsed.sections.map((s) => s.version),
        }.where((v) => v <= to).toList()
        ..sort();

  final inside =
      parsed.sections.where((s) => inRange(s.version, from, to)).toList()
        ..sort((a, b) => b.version.compareTo(a.version));

  final entries = <Entry>[];
  for (final s in inside) {
    var prev = from;
    for (final v in known) {
      if (v < s.version) prev = v > prev ? v : prev;
    }
    entries.add(
      Entry(
        version: s.version,
        title: s.title,
        tags: s.tags,
        signals: detectSignals(s.lines),
        body: s.lines.join('\n'),
        major: classifyBump(prev, s.version) == Bump.major,
      ),
    );
  }

  final present = {for (final s in parsed.sections) s.version};
  final missing = <String>[];
  for (final versionText in fetched.apiVersions) {
    try {
      final v = Version.parse(versionText);
      if (inRange(v, from, to) && !present.contains(v)) {
        missing.add(versionText);
      }
    } on FormatException {
      continue;
    }
  }
  missing.sort((a, b) => Version.parse(b).compareTo(Version.parse(a)));

  var confidence = 'high';
  if (fetched.rangeUnknown) {
    confidence = 'low';
  } else if (!present.contains(to) || !present.contains(from)) {
    confidence = 'medium';
  }
  if (entries.isEmpty && from < to) {
    notices.add(Notice('log.noEntriesInRange', [pkg.name, '$from', '$to']));
    if (confidence == 'high') confidence = 'medium';
  }
  return result(confidence, entries, missing);
}
