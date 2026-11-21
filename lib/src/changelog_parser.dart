import 'package:pub_semver/pub_semver.dart';

import 'i18n.dart';

/// One released version found in a changelog.
class Section {
  Section({
    required this.version,
    required this.title,
    required this.tags,
    required this.lines,
  });

  /// Parsed version from the heading.
  final Version version;

  /// Heading text without the leading `#`s, e.g. `3.5.0 - 2026-11-06`.
  final String title;

  /// Markers found after the version, e.g. `retracted`.
  final Set<String> tags;

  /// Body lines below the heading (leading and trailing blank lines removed).
  final List<String> lines;
}

/// Result of [parseChangelog].
class ParsedChangelog {
  ParsedChangelog({
    required this.sections,
    required this.notices,
    required this.fallbackLines,
  });

  /// Version sections in file order.
  final List<Section> sections;

  /// Things worth telling the user (skipped headings and so on).
  final List<Notice> notices;

  /// When the file has no version heading at all: its first lines, so the
  /// user still sees something. Empty otherwise.
  final List<String> fallbackLines;

  bool get isFallback => sections.isEmpty;
}

/// How many leading lines are returned when no version heading is found.
const int fallbackLineCount = 40;

final RegExp _heading = RegExp(r'^(#{1,6})\s+(.*?)\s*#*\s*$');
final RegExp _versionTitle = RegExp(
  r'^(?:version\s+)?\[?v?(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?)\]?(.*)$',
  caseSensitive: false,
);
final RegExp _fence = RegExp(r'^\s*(```|~~~)');

/// Parses a changelog written in any of the common heading styles.
///
/// Recognized: `## 1.6.0`, `## 3.5.0 - 2026-11-06`, `## 6.1.3 (retracted)`,
/// `## [4.7.3]`, `# v1.2.0`, `## 6.1.5+1` and pre-releases. Headings that are
/// not versions (`# CHANGELOG`, `## Unreleased`) are skipped with a notice.
ParsedChangelog parseChangelog(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n');

  // First pass: find heading lines outside code fences.
  final headingAt = <int, Match>{};
  var inFence = false;
  for (var i = 0; i < lines.length; i++) {
    if (_fence.hasMatch(lines[i])) {
      inFence = !inFence;
      continue;
    }
    if (inFence) continue;
    final m = _heading.firstMatch(lines[i]);
    if (m != null) headingAt[i] = m;
  }

  // The level of the first version heading decides which non-version
  // headings end a section (deeper ones, like `### Fixed`, stay inside).
  int? versionLevel;
  for (final entry in headingAt.entries) {
    if (_versionTitle.hasMatch(entry.value.group(2)!)) {
      versionLevel = entry.value.group(1)!.length;
      break;
    }
  }

  final sections = <Section>[];
  final notices = <Notice>[];

  String? title;
  Version? version;
  Set<String> tags = {};
  var body = <String>[];

  void closeSection() {
    if (version != null) {
      sections.add(
        Section(
          version: version!,
          title: title!,
          tags: tags,
          lines: _trimBlank(body),
        ),
      );
    }
    version = null;
    body = <String>[];
  }

  for (var i = 0; i < lines.length; i++) {
    final m = headingAt[i];
    if (m != null) {
      final headingText = m.group(2)!;
      final level = m.group(1)!.length;
      final vm = _versionTitle.firstMatch(headingText);
      Version? parsed;
      if (vm != null) {
        try {
          parsed = Version.parse(vm.group(1)!);
        } on FormatException {
          parsed = null;
        }
      }
      if (parsed != null) {
        closeSection();
        version = parsed;
        title = headingText;
        tags = _tagsFrom(vm!.group(2) ?? '');
        continue;
      }
      if (versionLevel == null || level <= versionLevel) {
        closeSection();
        final lower = headingText.toLowerCase();
        if (lower.contains('unreleased') || lower.contains('upcoming')) {
          notices.add(Notice('parse.unreleased', [headingText]));
        } else {
          notices.add(Notice('parse.skippedHeading', [headingText]));
        }
        continue;
      }
    }
    if (version != null) body.add(lines[i]);
  }
  closeSection();

  if (sections.isEmpty) {
    final head = _trimBlank(
      lines.skip(_firstNonBlank(lines)).take(fallbackLineCount).toList(),
    );
    // 경고에는 실제로 보여 주는 줄 수를 적는다(짧은 파일이면 40보다 적다).
    notices.add(
      head.isEmpty
          ? const Notice('parse.empty')
          : Notice('parse.noVersionHeadings', ['${head.length}']),
    );
    return ParsedChangelog(
      sections: const [],
      notices: notices,
      fallbackLines: head,
    );
  }
  return ParsedChangelog(
    sections: sections,
    notices: notices,
    fallbackLines: const [],
  );
}

Set<String> _tagsFrom(String rest) {
  final lower = rest.toLowerCase();
  final tags = <String>{};
  if (lower.contains('retracted')) tags.add('retracted');
  if (lower.contains('yanked')) tags.add('yanked');
  return tags;
}

int _firstNonBlank(List<String> lines) {
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim().isNotEmpty) return i;
  }
  return 0;
}

List<String> _trimBlank(List<String> lines) {
  var start = 0;
  var end = lines.length;
  while (start < end && lines[start].trim().isEmpty) {
    start++;
  }
  while (end > start && lines[end - 1].trim().isEmpty) {
    end--;
  }
  return lines.sublist(start, end);
}
