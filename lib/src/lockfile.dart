import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'i18n.dart';
import 'text_file.dart';

/// One entry of `pubspec.lock`.
class LockedPackage {
  const LockedPackage({
    required this.name,
    required this.version,
    required this.dependency,
    required this.source,
    this.hostedUrl,
    this.path,
    this.pathIsRelative = false,
  });

  final String name;

  /// The exact version in use.
  final Version version;

  /// Raw lock value: `direct main`, `direct dev`, `direct overridden`,
  /// `transitive`.
  final String dependency;

  /// `hosted`, `git`, `path` or `sdk`.
  final String source;

  /// For hosted packages: the repository URL (default `https://pub.dev`).
  final String? hostedUrl;

  /// For path packages: the directory from the lock file.
  final String? path;
  final bool pathIsRelative;

  /// Short kind used in output: `main`, `dev`, `overridden` or `transitive`.
  String get kind =>
      dependency.startsWith('direct ') ? dependency.substring(7) : dependency;

  bool get isDirect => dependency.startsWith('direct ');
}

/// Reads and parses a lock file; errors are [PubdeltaException]s (exit 3).
Future<List<LockedPackage>> readLockfile(String path) async {
  final file = File(path);
  if (!await file.exists()) {
    throw PubdeltaException(3, 'input.noLock', [path]);
  }
  final TextFile read;
  try {
    read = await readTextFile(file);
  } on UnreadableFile catch (e) {
    throw PubdeltaException(3, 'input.cannotRead', [path, e.reason]);
  }
  // pub 이 쓰는 잠금 파일은 항상 UTF-8 이다 — 아니면 다른 파일이거나 깨진 것
  if (read.hadInvalidUtf8) {
    throw PubdeltaException(3, 'input.lockInvalid', [
      path,
      messageRef('read.notUtf8'),
    ]);
  }
  return parseLockfile(read.text, source: path);
}

/// Parses the text of a `pubspec.lock`.
List<LockedPackage> parseLockfile(
  String text, {
  String source = 'pubspec.lock',
}) {
  final Object? doc;
  try {
    doc = loadYaml(text);
  } on YamlException catch (e) {
    throw PubdeltaException(3, 'input.lockInvalid', [source, e.message]);
  }
  if (doc is! YamlMap || doc['packages'] is! YamlMap) {
    throw PubdeltaException(3, 'input.lockInvalid', [
      source,
      messageRef('lock.noPackages'),
    ]);
  }
  final packages = doc['packages'] as YamlMap;
  final result = <LockedPackage>[];
  for (final entry in packages.entries) {
    final name = '${entry.key}';
    final value = entry.value;
    if (value is! YamlMap) {
      throw PubdeltaException(3, 'input.lockInvalid', [
        source,
        messageRef('lock.notMap', [name]),
      ]);
    }
    final versionText = '${value['version']}';
    final Version version;
    try {
      version = Version.parse(versionText);
    } on FormatException {
      throw PubdeltaException(3, 'input.lockInvalid', [
        source,
        messageRef('lock.badVersion', [name, versionText]),
      ]);
    }
    final src = '${value['source'] ?? 'hosted'}';
    final description = value['description'];
    String? url;
    String? path;
    var relative = false;
    if (description is YamlMap) {
      if (src == 'hosted') url = '${description['url'] ?? 'https://pub.dev'}';
      if (src == 'path') {
        path = description['path'] == null ? null : '${description['path']}';
        relative = description['relative'] == true;
      }
    }
    result.add(
      LockedPackage(
        name: name,
        version: version,
        dependency: '${value['dependency'] ?? 'transitive'}',
        source: src,
        hostedUrl: url,
        path: path,
        pathIsRelative: relative,
      ),
    );
  }
  return result;
}
