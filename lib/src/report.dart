import 'budget.dart';
import 'i18n.dart';
import 'render.dart';
import 'service.dart';
import 'signals.dart';
import 'version_range.dart';

/// `--fail-on` levels.
enum FailOn { none, breaking, major }

/// A finished `log` run: the text to print plus facts the caller needs for
/// exit codes.
class LogReport {
  LogReport({
    required this.text,
    required this.result,
    required this.estimatedTokens,
    required this.breaking,
    required this.majors,
  });

  final String text;
  final LogResult result;
  final int estimatedTokens;

  /// Packages with a strong signal (before the budget cut anything).
  final List<String> breaking;

  /// Packages with a major bump (0.x minor counts) or a strong signal.
  final List<String> majors;

  /// Whether `--fail-on [level]` should fail the run.
  bool trips(FailOn level) {
    switch (level) {
      case FailOn.none:
        return false;
      case FailOn.breaking:
        return breaking.isNotEmpty;
      case FailOn.major:
        return majors.isNotEmpty;
    }
  }
}

/// Builds, budgets and renders the changelog report.
///
/// CLI and MCP both call this, so their output is identical.
Future<LogReport> runLog(
  LogRequest request, {
  int? budget,
  Format format = Format.md,
  Lang lang = Lang.en,
}) async {
  final result = await buildLog(request);

  int measure(List<PackageLog> packages, List<Omitted> omitted) =>
      estimateTokens(
        renderLog(
          LogOutput(
            packages: packages,
            omitted: omitted,
            estimatedTokens: 99999,
            notices: result.notices,
          ),
          format,
          lang,
        ),
      );

  List<PackageLog> shown = result.packages;
  List<Omitted> omitted = const [];
  int tokens;
  if (budget != null) {
    final b = applyBudget(result.packages, budget, measure);
    shown = b.packages;
    omitted = b.omitted;
    tokens = b.estimatedTokens;
  } else {
    tokens = measure(shown, omitted);
  }

  final text = renderLog(
    LogOutput(
      packages: shown,
      omitted: omitted,
      estimatedTokens: tokens,
      notices: result.notices,
    ),
    format,
    lang,
  );

  final breaking = <String>[];
  final majors = <String>[];
  for (final p in result.packages) {
    final strong = p.strongest == SignalLevel.strong;
    if (strong) breaking.add(p.name);
    if (strong || p.bump == Bump.major) majors.add(p.name);
  }
  return LogReport(
    text: text,
    result: result,
    estimatedTokens: tokens,
    breaking: breaking,
    majors: majors,
  );
}
