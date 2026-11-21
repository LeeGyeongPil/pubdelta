/// How sure we are that a line announces a breaking change.
///
/// Ordered from most to least certain, so `level.index` can be used for
/// sorting (lower is stronger).
enum SignalLevel { strong, medium, weak }

/// One changelog line that looks like a breaking-change announcement.
class Signal {
  const Signal(this.level, this.line);

  final SignalLevel level;

  /// The original line, trimmed.
  final String line;
}

// strong: explicit "breaking" markers.
final List<RegExp> _strong = [
  RegExp(r'\*\*\s*breaking(?:\s+changes?)?\s*\*\*', caseSensitive: false),
  RegExp(r'\bBREAKING\b'), // upper case only: "breaking any class" is prose
  RegExp(r'^\s*#{2,6}\s*breaking\b', caseSensitive: false),
  RegExp(r'release has breaking changes', caseSensitive: false),
];

// medium: removals and the phrase "breaking change(s)".
final List<RegExp> _medium = [
  RegExp(
    r'^\s*[-*+]\s+(?:\*\*[^*]+\*\*:?\s*)?(?:removed?|removes)\b',
    caseSensitive: false,
  ),
  RegExp(r'^\s*#{2,6}\s*removed\b', caseSensitive: false),
  RegExp(r'\bbreaking\s+changes?\b', caseSensitive: false),
];
final RegExp _negatedBreaking = RegExp(
  r'\b(?:no|without|non|zero)[- ]breaking\b',
  caseSensitive: false,
);

// weak: deprecations.
final RegExp _weak = RegExp(r'\bdeprecat\w*', caseSensitive: false);

/// Scans body lines of one changelog entry.
///
/// The text above the first version heading (a preamble such as "Breaking
/// changes might happen in major and minor versions") is never passed in, so
/// it cannot cause false alarms. A bare word `breaking` is not a signal.
List<Signal> detectSignals(Iterable<String> bodyLines) {
  final found = <Signal>[];
  for (final raw in bodyLines) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final level = _levelOf(line);
    if (level != null) found.add(Signal(level, line));
  }
  return found;
}

SignalLevel? _levelOf(String line) {
  if (_strong.any((r) => r.hasMatch(line))) return SignalLevel.strong;
  final negated = _negatedBreaking.hasMatch(line);
  for (final r in _medium) {
    if (r.hasMatch(line) && !(negated && r.pattern.contains('breaking'))) {
      return SignalLevel.medium;
    }
  }
  if (_weak.hasMatch(line)) return SignalLevel.weak;
  return null;
}

/// The strongest level among [signals], or null when there is none.
SignalLevel? strongestLevel(Iterable<Signal> signals) {
  SignalLevel? best;
  for (final s in signals) {
    if (best == null || s.level.index < best.index) best = s.level;
  }
  return best;
}

final RegExp _prLink = RegExp(r'\(\[(#\d+)\]\(https?://[^)\s]+\)\)');
final RegExp _commitLink = RegExp(r'\[([0-9a-f]{7,40})\]\(https?://[^)\s]+\)');

/// Shortens generated commit and issue links:
/// `([#123](https://...))` becomes `(#123)`, `[d0fec9cc](https://...)`
/// becomes `d0fec9cc`.
String shortenLinks(String text) {
  return text.replaceAllMapped(_prLink, (m) => '(${m[1]})').replaceAllMapped(
    _commitLink,
    (m) {
      final hash = m[1]!;
      return hash.length > 8 ? hash.substring(0, 8) : hash;
    },
  );
}

/// Strips a leading list marker and long links so a signal line reads well
/// in a summary.
String cleanSignalLine(String line) {
  var s = shortenLinks(line.trim()).replaceFirst(RegExp(r'^[-*+>]\s+'), '');
  if (s.length > 160) s = '${s.substring(0, 157)}...';
  return s;
}
