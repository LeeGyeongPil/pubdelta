import 'render.dart';
import 'service.dart';
import 'signals.dart';

/// Rough token count: characters divided by four, rounded up.
///
/// This is an approximation; real tokenizers differ by model and language.
int estimateTokens(String text) => (text.length / 4).ceil();

/// What [applyBudget] returns.
class BudgetResult {
  BudgetResult(this.packages, this.omitted, this.estimatedTokens);

  final List<PackageLog> packages;
  final List<Omitted> omitted;
  final int estimatedTokens;
}

/// Order in which entries are kept: strong signal, medium signal, a new
/// breaking unit, weak signal, everything else.
int _rank(Entry e) {
  final s = e.strongest;
  if (s == SignalLevel.strong) return 0;
  if (s == SignalLevel.medium) return 1;
  if (e.major) return 2;
  if (s == SignalLevel.weak) return 3;
  return 4;
}

/// Measures the tokens of a rendering; supplied by the caller so the budget
/// logic does not depend on a format or language.
typedef Measure =
    int Function(List<PackageLog> packages, List<Omitted> omitted);

/// Keeps entries in priority order while the estimated output stays within
/// [budget] tokens, and lists every dropped entry.
///
/// Priority: strong > medium > major > weak > rest; newest version first
/// inside a rank. An entry that does not fit whole is tried again with only
/// its signal lines (`trimmed`). Package headers are always kept, so a budget
/// smaller than the headers alone cannot be met.
BudgetResult applyBudget(
  List<PackageLog> packages,
  int budget,
  Measure measure,
) {
  packages = [
    for (final p in packages)
      p.withEntries([
        for (final e in p.entries)
          e.withBody(shortenLinks(e.body), trimmed: false),
      ]),
  ];

  // Candidates as (package index, entry index).
  final candidates = <(int, int)>[
    for (var pi = 0; pi < packages.length; pi++)
      for (var ei = 0; ei < packages[pi].entries.length; ei++) (pi, ei),
  ];
  candidates.sort((a, b) {
    final ea = packages[a.$1].entries[a.$2];
    final eb = packages[b.$1].entries[b.$2];
    final r = _rank(ea).compareTo(_rank(eb));
    if (r != 0) return r;
    final v = eb.version.compareTo(ea.version);
    if (v != 0) return v;
    final p = a.$1.compareTo(b.$1);
    return p != 0 ? p : a.$2.compareTo(b.$2);
  });

  final chosen = <(int, int), Entry>{};

  List<PackageLog> build(Map<(int, int), Entry> pick) => [
    for (var pi = 0; pi < packages.length; pi++)
      packages[pi].withEntries([
        for (var ei = 0; ei < packages[pi].entries.length; ei++)
          if (pick.containsKey((pi, ei))) pick[(pi, ei)]!,
      ]),
  ];

  List<Omitted> omittedFor(Map<(int, int), Entry> pick) => [
    for (final c in candidates)
      if (!pick.containsKey(c))
        Omitted(packages[c.$1].name, '${packages[c.$1].entries[c.$2].version}'),
  ];

  bool fits(Map<(int, int), Entry> pick) =>
      measure(build(pick), omittedFor(pick)) <= budget;

  for (final c in candidates) {
    final full = packages[c.$1].entries[c.$2];
    chosen[c] = full;
    if (fits(chosen)) continue;
    chosen.remove(c);
    if (full.signals.isEmpty) continue;
    final compact = full.withBody(
      full.signals.map((s) => s.line.trim()).join('\n'),
    );
    chosen[c] = compact;
    if (!fits(chosen)) chosen.remove(c);
  }

  final kept = build(chosen);
  final omitted = omittedFor(chosen);
  return BudgetResult(kept, omitted, measure(kept, omitted));
}
