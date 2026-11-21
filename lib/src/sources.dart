import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'hosted_client.dart';
import 'i18n.dart';
import 'lockfile.dart';
import 'text_file.dart';

/// Where a changelog came from.
enum Origin { dir, cache, hosted, path, none }

/// What [ChangelogSources.fetch] found for one package.
class FetchedChangelog {
  FetchedChangelog({
    this.text,
    this.origin = Origin.none,
    this.rangeUnknown = false,
    this.apiVersions = const [],
    this.notices = const [],
    this.failure,
  });

  /// The changelog text, or null when none could be read.
  final String? text;
  final Origin origin;

  /// True for path dependencies: we cannot know which versions the local file
  /// covers.
  final bool rangeUnknown;

  /// Versions the hosted API lists (empty when the API was not asked).
  final List<String> apiVersions;
  final List<Notice> notices;

  /// Set when the changelog is unavailable and the user should act on it.
  final FetchFailure? failure;
}

/// Finds a changelog for a package, in this order:
///
/// 1. `--changelog-dir <dir>/<name>.md`
/// 2. path dependency: the local `CHANGELOG.md` (range unknown); git and sdk
///    dependencies have no changelog to read
/// 3. the pub cache: the lowest cached version that is at least `to`
/// 4. unless offline: the hosted repository (API, then archive)
class ChangelogSources {
  ChangelogSources({
    required this.projectDir,
    required this.environment,
    this.changelogDir,
    this.offline = false,
    this.hostedOverride,
    HostedClient? client,
    this.onFetch,
  }) : _client = client ?? HostedClient();

  final String projectDir;
  final Map<String, String> environment;
  final String? changelogDir;
  final bool offline;

  /// `PUBDELTA_HOSTED_URL` or `--hosted-url`: use this repository instead of
  /// the one in the lock file.
  final String? hostedOverride;

  /// Called before a network request, e.g. to print progress.
  final void Function(String name)? onFetch;

  final HostedClient _client;
  final Map<String, List<HostedVersion>> _apiCache = {};

  Future<FetchedChangelog> fetch(LockedPackage pkg, Version to) async {
    if (changelogDir != null) {
      final file = File('$changelogDir${Platform.pathSeparator}${pkg.name}.md');
      if (await file.exists()) {
        return _readLocal(pkg.name, file, Origin.dir);
      }
    }

    switch (pkg.source) {
      case 'path':
        return _fromPath(pkg);
      case 'git':
      case 'sdk':
        return FetchedChangelog(
          notices: [
            Notice('source.noChangelog', [pkg.name, pkg.source]),
          ],
        );
    }

    final hostedUrl = pkg.hostedUrl ?? 'https://pub.dev';
    final cached = await _fromCache(pkg.name, hostedUrl, to);
    if (cached != null) return cached;

    if (offline) {
      // 안내 문구가 "dart pub cache add <이름> --version <목표>" 를 보여 주도록 목표 버전을 넘긴다
      return FetchedChangelog(failure: FetchFailure('offline', '$to'));
    }
    return _fromHosted(pkg.name, hostedOverride ?? hostedUrl, to);
  }

  /// Reads a changelog from disk ([readTextFile]). A file that is not valid
  /// UTF-8 is still used, with a warning; a file that cannot be read at all
  /// is an `unreadable` failure (exit 4), never a crash.
  Future<FetchedChangelog> _readLocal(
    String name,
    File file,
    Origin origin, {
    bool rangeUnknown = false,
    List<Notice> notices = const [],
  }) async {
    final TextFile read;
    try {
      read = await readTextFile(file);
    } on UnreadableFile catch (e) {
      return FetchedChangelog(failure: FetchFailure('unreadable', '$e'));
    }
    return FetchedChangelog(
      text: read.text,
      origin: origin,
      rangeUnknown: rangeUnknown,
      notices: [
        ...notices,
        if (read.hadInvalidUtf8) Notice('source.notUtf8', [name]),
      ],
    );
  }

  Future<FetchedChangelog> _fromPath(LockedPackage pkg) async {
    final raw = pkg.path;
    if (raw == null) {
      return FetchedChangelog(
        notices: [
          Notice('source.noChangelog', [pkg.name, 'path']),
        ],
      );
    }
    final dir =
        (pkg.pathIsRelative || !Directory(raw).isAbsolute)
            ? '$projectDir${Platform.pathSeparator}$raw'
            : raw;
    final file = await _findChangelogFile(Directory(dir));
    if (file == null) {
      return FetchedChangelog(
        notices: [
          Notice('source.noChangelog', [pkg.name, 'path']),
        ],
      );
    }
    return _readLocal(
      pkg.name,
      file,
      Origin.path,
      rangeUnknown: true,
      notices: [
        Notice('source.pathRangeUnknown', [pkg.name]),
      ],
    );
  }

  Future<FetchedChangelog?> _fromCache(
    String name,
    String hostedUrl,
    Version to,
  ) async {
    final root = pubCacheDir(environment);
    if (root == null) return null;
    final hostDir = Directory(
      '$root${Platform.pathSeparator}hosted${Platform.pathSeparator}${hostedDirName(hostedUrl)}',
    );
    if (!await hostDir.exists()) return null;

    Version? best;
    Directory? bestDir;
    for (final entity in await _listOrEmpty(hostDir)) {
      if (entity is! Directory) continue;
      final base = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (!base.startsWith('$name-')) continue;
      final Version v;
      try {
        v = Version.parse(base.substring(name.length + 1));
      } on FormatException {
        continue;
      }
      if (v < to) continue;
      if (best == null || v < best) {
        best = v;
        bestDir = entity;
      }
    }
    if (bestDir == null) return null;
    final file = await _findChangelogFile(bestDir);
    if (file == null) return null;
    return _readLocal(name, file, Origin.cache);
  }

  Future<FetchedChangelog> _fromHosted(
    String name,
    String baseUrl,
    Version to,
  ) async {
    try {
      onFetch?.call(name);
      final versions =
          _apiCache[name] ??= await _client.versions(baseUrl, name);
      HostedVersion? target;
      for (final v in versions) {
        try {
          if (Version.parse(v.version) == to) target = v;
        } on FormatException {
          continue;
        }
      }
      if (target == null || target.archiveUrl == null) {
        throw FetchFailure('versionNotFound', '$name $to');
      }
      final read = await _client.changelogFromArchive(target.archiveUrl!);
      return FetchedChangelog(
        text: read.text,
        origin: Origin.hosted,
        apiVersions: [for (final v in versions) v.version],
        notices: [
          if (read.hadInvalidUtf8) Notice('source.notUtf8', [name]),
        ],
      );
    } on FetchFailure catch (f) {
      return FetchedChangelog(failure: f);
    }
  }

  /// Releases the HTTP client.
  void close() => _client.close();
}

Future<File?> _findChangelogFile(Directory dir) async {
  if (!await dir.exists()) return null;
  final pattern = RegExp(
    r'^changelog(\.md|\.markdown|\.txt)?$',
    caseSensitive: false,
  );
  for (final entity in await _listOrEmpty(dir)) {
    if (entity is File && pattern.hasMatch(entity.uri.pathSegments.last)) {
      return entity;
    }
  }
  return null;
}

/// Lists [dir]; a folder that cannot be listed (permission denied, removed
/// meanwhile) counts as empty, so that source is skipped instead of crashing.
Future<List<FileSystemEntity>> _listOrEmpty(Directory dir) async {
  try {
    return await dir.list(followLinks: false).toList();
  } on FileSystemException {
    return const [];
  }
}

/// The pub cache directory: `PUB_CACHE`, else `~/.pub-cache` (Windows:
/// `%LOCALAPPDATA%\Pub\Cache`). Null when it cannot be determined.
String? pubCacheDir(Map<String, String> env) {
  final explicit = env['PUB_CACHE'];
  if (explicit != null && explicit.isNotEmpty) return explicit;
  if (Platform.isWindows) {
    final local = env['LOCALAPPDATA'];
    return local == null ? null : '$local\\Pub\\Cache';
  }
  final home = env['HOME'];
  return home == null ? null : '$home/.pub-cache';
}

/// Folder name pub uses for a hosted repository inside the cache: the URL
/// without its scheme, with `<>:"\/|?*%` percent-encoded.
String hostedDirName(String url) {
  final noScheme = url.replaceFirst(RegExp(r'^https?://'), '');
  final trimmed =
      noScheme.endsWith('/')
          ? noScheme.substring(0, noScheme.length - 1)
          : noScheme;
  return trimmed.replaceAllMapped(
    RegExp(r'[<>:"\\/|?*%]'),
    (m) => '%${m[0]!.codeUnitAt(0)}',
  );
}
