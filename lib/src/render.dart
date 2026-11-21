import 'dart:convert';

import 'i18n.dart';
import 'outdated.dart';
import 'service.dart';
import 'signals.dart';

/// Output formats of `plan` and `log`.
enum Format { text, md, json }

/// A changelog entry the budget left out.
class Omitted {
  const Omitted(this.name, this.version);

  final String name;
  final String version;
}

/// Everything `renderLog` needs.
class LogOutput {
  const LogOutput({
    required this.packages,
    this.omitted = const [],
    this.estimatedTokens = 0,
    this.notices = const [],
  });

  final List<PackageLog> packages;
  final List<Omitted> omitted;
  final int estimatedTokens;

  /// Run-level notices; shown in JSON (text and md print them on stderr).
  final List<Notice> notices;
}

String _kind(String dependency) =>
    dependency.startsWith('direct ') ? dependency.substring(7) : dependency;

// ---------------------------------------------------------------- plan

/// Renders the `plan` command output.
String renderPlan(
  List<PlanEntry> entries,
  List<Notice> notices,
  Format format,
  Lang lang,
) {
  switch (format) {
    case Format.json:
      return jsonEncode({
        'schema': 1,
        'packages': [
          for (final e in entries)
            {
              'name': e.name,
              'dependency': e.package.dependency,
              'source': e.package.source,
              'from': '${e.from}',
              'to': '${e.to}',
              'bump': e.bump.name,
              'flags': e.flags,
            },
        ],
        'warnings': _noticesJson(notices, lang),
      });
    case Format.md:
      return _planMarkdown(entries, lang);
    case Format.text:
      return _planText(entries, lang);
  }
}

List<List<String>> _planRows(List<PlanEntry> entries, Lang lang) => [
  for (final e in entries)
    [
      e.name,
      '${e.from}',
      '${e.to}',
      tr(lang, 'bump.${e.bump.name}'),
      tr(lang, 'dep.${_kind(e.package.dependency)}'),
      e.flags.map((f) => tr(lang, 'flag.$f')).join(', '),
    ],
];

List<String> _planHeader(Lang lang) => [
  tr(lang, 'col.package'),
  tr(lang, 'col.current'),
  tr(lang, 'col.target'),
  tr(lang, 'col.bump'),
  tr(lang, 'col.kind'),
  tr(lang, 'col.flags'),
];

String _planText(List<PlanEntry> entries, Lang lang) {
  if (entries.isEmpty) return tr(lang, 'plan.empty');
  final rows = [_planHeader(lang), ..._planRows(entries, lang)];
  final widths = List<int>.filled(6, 0);
  for (final row in rows) {
    for (var i = 0; i < row.length; i++) {
      final w = _width(row[i]);
      if (w > widths[i]) widths[i] = w;
    }
  }
  final buffer = StringBuffer();
  for (final row in rows) {
    final cells = <String>[
      for (var i = 0; i < row.length; i++) _pad(row[i], widths[i]),
    ];
    buffer.writeln(cells.join('  ').trimRight());
  }
  return buffer.toString().trimRight();
}

String _planMarkdown(List<PlanEntry> entries, Lang lang) {
  final buffer = StringBuffer('# ${tr(lang, 'plan.title')}\n\n');
  if (entries.isEmpty) {
    buffer.write(tr(lang, 'plan.empty'));
    return buffer.toString();
  }
  final header = _planHeader(lang);
  buffer.writeln('| ${header.join(' | ')} |');
  buffer.writeln('|${List.filled(header.length, '---').join('|')}|');
  for (final row in _planRows(entries, lang)) {
    buffer.writeln('| ${row.join(' | ')} |');
  }
  return buffer.toString().trimRight();
}

/// Display width: Hangul and other wide characters take two columns.
int _width(String s) {
  var w = 0;
  for (final r in s.runes) {
    w +=
        (r >= 0x1100 && r <= 0x11FF) ||
                (r >= 0x3000 && r <= 0xD7A3) ||
                (r >= 0xFF00 && r <= 0xFF60)
            ? 2
            : 1;
  }
  return w;
}

String _pad(String s, int width) => s + ' ' * (width - _width(s));

// ----------------------------------------------------------------- log

/// Renders the `log` command output.
String renderLog(LogOutput out, Format format, Lang lang) {
  switch (format) {
    case Format.json:
      return _logJson(out, lang);
    case Format.md:
      return _logMarkdown(out, lang);
    case Format.text:
      return _logText(out, lang);
  }
}

String _header(PackageLog p, Lang lang) {
  final parts = <String>[
    tr(lang, 'dep.${_kind(p.dependency)}'),
    tr(lang, 'pkg.confidence', [tr(lang, 'conf.${p.confidence}')]),
    if (p.flags.isNotEmpty) p.flags.map((f) => tr(lang, 'flag.$f')).join(', '),
  ];
  return '${p.name} ${p.from} → ${p.to} (${tr(lang, 'bump.${p.bump.name}')})'
      '  ${parts.join(' · ')}';
}

/// Strong, medium and weak lines of a package for the summary at its top.
List<String> _signalSummary(PackageLog p, Lang lang, {int max = 8}) {
  // Entries are newest first; collect level by level so that, inside a
  // level, newer versions stay first (List.sort is not stable).
  final items = <(SignalLevel, String, String)>[];
  for (final level in SignalLevel.values) {
    for (final e in p.entries) {
      for (final s in e.signals) {
        if (s.level == level) {
          items.add((level, '${e.version}', cleanSignalLine(s.line)));
        }
      }
    }
  }
  final lines = <String>[];
  for (final (level, version, line) in items.take(max)) {
    lines.add('${tr(lang, 'level.${level.name}')} $version: $line');
  }
  if (items.length > max) {
    lines.add(tr(lang, 'pkg.moreSignals', ['${items.length - max}']));
  }
  return lines;
}

String _omittedLine(List<Omitted> omitted, Lang lang) {
  const shown = 10;
  final names = omitted.take(shown).map((o) => '${o.name}@${o.version}');
  final more =
      omitted.length > shown
          ? tr(lang, 'omitted.more', ['${omitted.length - shown}'])
          : '';
  return tr(lang, 'omitted.line', [
    '${omitted.length}',
    names.join(', '),
    more,
  ]);
}

String _logText(LogOutput out, Lang lang) {
  final b = StringBuffer();
  if (out.packages.isEmpty) {
    b.writeln(tr(lang, 'log.empty'));
  }
  for (final p in out.packages) {
    b.writeln(_header(p, lang));
    for (final line in _signalSummary(p, lang)) {
      b.writeln('  ! $line');
    }
    for (final n in p.notices) {
      b.writeln('  ${tr(lang, 'warning.prefix')} ${n.text(lang)}');
    }
    if (p.missingInChangelog.isNotEmpty) {
      b.writeln(
        '  ${tr(lang, 'note.prefix')} ${tr(lang, 'pkg.missing', [p.missingInChangelog.join(', ')])}',
      );
    }
    for (final e in p.entries) {
      b.writeln('  == ${_entryHeading(e, lang)}');
      if (e.body.isNotEmpty) {
        for (final line in e.body.split('\n')) {
          b.writeln(line.isEmpty ? '' : '    $line');
        }
      }
    }
    b.writeln();
  }
  if (out.omitted.isNotEmpty) b.writeln(_omittedLine(out.omitted, lang));
  b.write(tr(lang, 'tokens.line', ['${out.estimatedTokens}']));
  return b.toString();
}

String _logMarkdown(LogOutput out, Lang lang) {
  final b = StringBuffer('# ${tr(lang, 'log.title')}\n\n');
  if (out.packages.isEmpty) {
    b.writeln(tr(lang, 'log.empty'));
    b.writeln();
  }
  for (final p in out.packages) {
    b.writeln(
      '## ${p.name} ${p.from} → ${p.to} (${tr(lang, 'bump.${p.bump.name}')})',
    );
    b.writeln();
    final parts = <String>[
      tr(lang, 'dep.${_kind(p.dependency)}'),
      tr(lang, 'pkg.confidence', [tr(lang, 'conf.${p.confidence}')]),
      if (p.flags.isNotEmpty)
        p.flags.map((f) => tr(lang, 'flag.$f')).join(', '),
    ];
    b.writeln('_${parts.join(' · ')}_');
    b.writeln();
    final summary = _signalSummary(p, lang);
    for (final line in summary) {
      b.writeln('- $line');
    }
    if (summary.isNotEmpty) b.writeln();
    for (final n in p.notices) {
      b.writeln('> ${tr(lang, 'warning.prefix')} ${n.text(lang)}');
    }
    if (p.missingInChangelog.isNotEmpty) {
      b.writeln(
        '> ${tr(lang, 'note.prefix')} ${tr(lang, 'pkg.missing', [p.missingInChangelog.join(', ')])}',
      );
    }
    if (p.notices.isNotEmpty || p.missingInChangelog.isNotEmpty) b.writeln();
    for (final e in p.entries) {
      b.writeln('### ${_entryHeading(e, lang)}');
      b.writeln();
      if (e.body.isNotEmpty) {
        b.writeln(e.body);
        b.writeln();
      }
    }
  }
  if (out.omitted.isNotEmpty) {
    b.writeln('> ${_omittedLine(out.omitted, lang)}');
    b.writeln();
  }
  b.write('_${tr(lang, 'tokens.line', ['${out.estimatedTokens}'])}_');
  return b.toString();
}

/// Heading line of one entry for text/md. Fallback entries (no version
/// headings in the changelog) get a translated label instead of [Entry.title].
String _entryHeading(Entry e, Lang lang) {
  final n = e.fallbackLines;
  // 머리글 없는 변경 기록의 대체 항목 제목도 메시지 표에서 언어별로 만든다.
  final title = n == null ? e.title : tr(lang, 'entry.fallback', ['$n']);
  return e.trimmed ? '$title ${tr(lang, 'entry.trimmed')}' : title;
}

List<Map<String, String>> _noticesJson(List<Notice> notices, Lang lang) => [
  for (final n in notices) {'code': n.key, 'message': n.text(lang)},
];

String _logJson(LogOutput out, Lang lang) {
  return jsonEncode({
    'schema': 1,
    'packages': [
      for (final p in out.packages)
        {
          'name': p.name,
          'dependency': p.dependency,
          'source': p.source,
          'origin': p.origin.name,
          'from': '${p.from}',
          'to': '${p.to}',
          'bump': p.bump.name,
          'flags': p.flags,
          'confidence': p.confidence,
          'entries': [
            for (final e in p.entries)
              {
                'version': '${e.version}',
                'title': e.title,
                'tags': e.tags.toList()..sort(),
                'major': e.major,
                'trimmed': e.trimmed,
                'signals': [
                  for (final s in e.signals)
                    {'level': s.level.name, 'line': s.line},
                ],
                'body': e.body,
              },
          ],
          'missingInChangelog': p.missingInChangelog,
          'warnings': _noticesJson(p.notices, lang),
        },
    ],
    'omitted': [
      for (final o in out.omitted) {'name': o.name, 'version': o.version},
    ],
    'estimatedTokens': out.estimatedTokens,
    'warnings': _noticesJson(out.notices, lang),
  });
}
