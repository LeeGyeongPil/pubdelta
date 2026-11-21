import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import 'i18n.dart';
import 'mcp_server.dart';
import 'outdated.dart';
import 'render.dart';
import 'report.dart';
import 'service.dart';
import 'version.dart';

/// Runs the `pubdelta` command line and returns the exit code.
///
/// Exit codes: 0 ok, 1 `--fail-on` tripped, 2 usage error, 3 input error,
/// 4 a changelog could not be obtained, 5 `pub outdated` and its fallback
/// both failed, 6 unexpected internal error (a bug; reported in one line in
/// the chosen language instead of a stack trace).
///
/// [out], [err], [env] and [runner] can be replaced in tests.
Future<int> runCli(
  List<String> args, {
  Map<String, String>? env,
  StringSink? out,
  StringSink? err,
  Stream<String>? stdinLines,
  ProcessRunner runner = defaultRunner,
}) async {
  final environment = env ?? Platform.environment;
  final stdoutSink = out ?? stdout;
  final stderrSink = err ?? stderr;
  final lang = resolveLang(flag: _scanLangFlag(args), env: environment);
  try {
    return await _run(
      args,
      lang,
      environment,
      stdoutSink,
      stderrSink,
      stdinLines,
      runner,
    );
  } catch (e) {
    // 마지막 그물: 여기까지 온 예외는 사용자가 고칠 입력 문제가 아니라 버그다.
    // 스택 트레이스·exit 255 대신 고른 언어의 한 줄과 정해진 종료 코드 6.
    stderrSink.writeln(
      tr(lang, 'error.prefix', [
        tr(lang, 'error.unexpected', [describeUnexpected(e)]),
      ]),
    );
    return exitUnexpected;
  }
}

/// Exit code for an unexpected internal error.
const int exitUnexpected = 6;

Future<int> _run(
  List<String> args,
  Lang lang,
  Map<String, String> environment,
  StringSink stdoutSink,
  StringSink stderrSink,
  Stream<String>? stdinLines,
  ProcessRunner runner,
) async {
  final parser = _topParser(lang);
  final ArgResults top;
  try {
    top = parser.parse(args);
  } on ArgParserException catch (e) {
    // e.message 는 args 패키지의 영어 문구라 쓰지 않는다 — 종류를 가려 메시지 표에서 고른다.
    return _usageError(
      stderrSink,
      lang,
      describeArgError(e, parser, args, lang),
    );
  }

  if (top['version'] == true) {
    stdoutSink.writeln('pubdelta $pubdeltaVersion');
    return 0;
  }
  final command = top.command;
  if (command == null) {
    if (top.rest.isNotEmpty) {
      return _usageError(
        stderrSink,
        lang,
        tr(lang, 'usage.unknownCommand', [top.rest.first]),
      );
    }
    stdoutSink.writeln(_topHelp(lang, parser));
    return top['help'] == true ? 0 : 2;
  }
  if (command['help'] == true) {
    stdoutSink.writeln(tr(lang, 'help.${command.name}'));
    stdoutSink.writeln(_commandParser(command.name!, lang).usage);
    return 0;
  }
  final swallowed = _optionThatSwallowedAnOption(
    command,
    parser.commands[command.name]!,
  );
  if (swallowed != null) {
    return _usageError(
      stderrSink,
      lang,
      tr(lang, 'usage.missingValue', [swallowed]),
    );
  }

  try {
    switch (command.name) {
      case 'plan':
        return await _runPlan(
          command,
          lang,
          environment,
          stdoutSink,
          stderrSink,
          runner,
        );
      case 'log':
        return await _runLog(
          command,
          lang,
          environment,
          stdoutSink,
          stderrSink,
          runner,
        );
      case 'mcp':
        final lines =
            stdinLines ??
            stdin
                // 클라이언트가 UTF-8 이 아닌 바이트를 보내도 서버가 죽지 않게 한다
                .transform(const Utf8Decoder(allowMalformed: true))
                .transform(const LineSplitter());
        await McpServer(
          env: environment,
          runner: runner,
        ).serve(lines, stdoutSink);
        return 0;
    }
  } on _UsageError catch (e) {
    return _usageError(stderrSink, lang, e.message);
  } on PubdeltaException catch (e) {
    stderrSink.writeln(tr(lang, 'error.prefix', [e.message(lang)]));
    return e.exitCode;
  }
  return 2;
}

class _UsageError implements Exception {
  _UsageError(this.message);

  final String message;
}

int _usageError(StringSink err, Lang lang, String message) {
  err.writeln(tr(lang, 'usage.error', [message]));
  err.writeln(tr(lang, 'usage.hint'));
  return 2;
}

/// Turns a parse error of the args package into a sentence from our own
/// message tables.
///
/// The args package only knows English (`e.message`), so that text is never
/// shown. Instead we look up the option named by `e.argumentName` in the
/// parser of the (sub)command that failed and decide the kind of mistake
/// ourselves: unknown option, `--no-` on an option that cannot be turned off,
/// a value given to a flag, a missing value, or a value that is not allowed.
/// Anything else gets a general "invalid option or value" message.
String describeArgError(
  ArgParserException e,
  ArgParser top,
  List<String> args,
  Lang lang,
) {
  // 1) 오류가 난 (하위) 명령의 파서와 그 이름 (예: "pubdelta log")
  var parser = top;
  for (final name in e.commands) {
    parser = parser.commands[name] ?? parser;
  }
  final where = ['pubdelta', ...e.commands].join(' ');
  final raw = e.argumentName;
  if (raw == null || raw.isEmpty) {
    return tr(lang, 'usage.badArgument', [args.join(' ')]);
  }

  // 2) 문제의 인자가 가리키는 옵션 찾기: --name, --no-name, -x
  Option? option;
  var negated = false;
  if (raw.startsWith('--')) {
    final name = raw.substring(2);
    option = parser.options[name];
    if (option == null && name.startsWith('no-')) {
      option = parser.options[name.substring(3)];
      negated = option != null;
    }
  } else if (raw.startsWith('-') && raw.length == 2) {
    option = parser.findByAbbreviation(raw.substring(1));
  }

  // 3) 종류별 메시지
  if (option == null) return tr(lang, 'usage.unknownOption', [raw, where]);
  if (negated) {
    return tr(lang, 'usage.cannotNegate', [raw, '--${option.name}']);
  }
  if (option.isFlag) return tr(lang, 'usage.flagNoValue', [raw]);
  final bad = _firstDisallowedValue(args, option);
  // 값 자리에 다른 옵션(--lang 등)이 왔으면 값을 빠뜨린 것으로 본다
  if (bad == null || bad.startsWith('--')) {
    return tr(lang, 'usage.missingValue', ['--${option.name}']);
  }
  return tr(lang, 'usage.badValue', [
    bad,
    '--${option.name}',
    (option.allowed ?? const <String>[]).join(', '),
  ]);
}

/// The first value given to [option] in [args] that is not in its allowed
/// list, or null when there is none (then the value itself was missing).
String? _firstDisallowedValue(List<String> args, Option option) {
  final allowed = option.allowed;
  if (allowed == null) return null; // 허용 목록이 없으면 값이 빠진 경우뿐이다
  final long = '--${option.name}';
  final short = option.abbr == null ? null : '-${option.abbr}';
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--') break;
    String value;
    if (arg.startsWith('$long=')) {
      value = arg.substring(long.length + 1);
    } else if (arg == long || arg == short) {
      if (i + 1 >= args.length) return null; // 값 없이 끝남
      value = args[++i];
    } else {
      continue;
    }
    // 여러 값 옵션(--include dev,transitive)은 쉼표로 나눠 하나씩 본다
    final parts =
        option.isMultiple && option.splitCommas ? value.split(',') : [value];
    for (final part in parts) {
      if (!allowed.contains(part)) return part;
    }
  }
  return null;
}

/// The args package takes the next word as an option's value even when it is
/// another option (`--lock --offline` sets lock to "--offline"). That is
/// almost always a forgotten value, so it is reported as one. Returns the
/// option name (`--lock`) or null.
String? _optionThatSwallowedAnOption(ArgResults results, ArgParser parser) {
  for (final option in parser.options.values) {
    if (option.isFlag || !results.wasParsed(option.name)) continue;
    final value = results[option.name];
    final values = value is List ? value : [value];
    if (values.any((v) => v is String && v.startsWith('--'))) {
      return '--${option.name}';
    }
  }
  return null;
}

/// Finds `--lang x` / `--lang=x` before the real parse, so that usage errors
/// and help texts already use the chosen language.
String? _scanLangFlag(List<String> args) {
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--') break;
    if (a.startsWith('--lang=')) return a.substring(7);
    // "--lang --help" 처럼 값 자리에 다른 옵션이 오면 언어로 보지 않는다
    if (a == '--lang' && i + 1 < args.length && !args[i + 1].startsWith('-')) {
      return args[i + 1];
    }
  }
  return null;
}

// --------------------------------------------------------------- parsers

void _addCommon(ArgParser p, Lang lang) {
  p
    ..addOption(
      'lang',
      allowed: ['en', 'ko'],
      help: tr(lang, 'opt.lang'),
      valueHelp: 'en|ko',
    )
    ..addFlag('help', abbr: 'h', negatable: false, help: tr(lang, 'opt.help'));
}

void _addPlanOptions(ArgParser p, Lang lang) {
  p
    ..addOption('lock', help: tr(lang, 'opt.lock'), valueHelp: 'file')
    ..addOption(
      'outdated',
      help: tr(lang, 'opt.outdated'),
      valueHelp: 'file.json',
    )
    ..addOption(
      'mode',
      allowed: ['upgradable', 'resolvable', 'latest'],
      help: tr(lang, 'opt.mode'),
    )
    ..addMultiOption(
      'include',
      allowed: ['dev', 'transitive'],
      help: tr(lang, 'opt.include'),
    )
    ..addOption(
      'format',
      allowed: ['text', 'md', 'json'],
      help: tr(lang, 'opt.format'),
    );
}

ArgParser _commandParser(String name, Lang lang) {
  final p = ArgParser();
  _addCommon(p, lang);
  if (name == 'plan' || name == 'log') _addPlanOptions(p, lang);
  if (name == 'log') {
    p
      ..addFlag('all', negatable: false, help: tr(lang, 'opt.all'))
      ..addOption('from', help: tr(lang, 'opt.from'), valueHelp: 'version')
      ..addOption('to', help: tr(lang, 'opt.to'), valueHelp: 'version')
      ..addOption(
        'changelog-dir',
        help: tr(lang, 'opt.changelogDir'),
        valueHelp: 'dir',
      )
      ..addFlag('offline', negatable: false, help: tr(lang, 'opt.offline'))
      ..addOption('budget', help: tr(lang, 'opt.budget'), valueHelp: 'tokens')
      ..addOption(
        'fail-on',
        allowed: ['none', 'breaking', 'major'],
        help: tr(lang, 'opt.failOn'),
      );
  }
  return p;
}

ArgParser _topParser(Lang lang) {
  final p = ArgParser();
  _addCommon(p, lang);
  p.addFlag('version', negatable: false, help: tr(lang, 'opt.version'));
  for (final name in const ['plan', 'log', 'mcp']) {
    p.addCommand(name, _commandParser(name, lang));
  }
  return p;
}

String _topHelp(Lang lang, ArgParser parser) =>
    '${tr(lang, 'help.top')}\n\n${parser.usage}';

// -------------------------------------------------------------- commands

/// Defaults live here, not in the parser: the args package would append an
/// English "(default ...)" to the help text, which breaks `--lang ko`.
///
/// `--include` adds to the default: direct dev dependencies are always in,
/// so `--include transitive` shows main, dev and transitive packages.
Set<String> _includeOf(ArgResults r) {
  final given = r['include'] as List<String>;
  return {'dev', ...given};
}

PlanRequest _planRequest(
  ArgResults r,
  Map<String, String> env,
  ProcessRunner runner,
) {
  return PlanRequest(
    lockFile: (r['lock'] as String?) ?? 'pubspec.lock',
    outdatedFile: r['outdated'] as String?,
    mode: Mode.values.byName((r['mode'] as String?) ?? 'resolvable'),
    include: _includeOf(r),
    environment: env,
    runner: runner,
  );
}

Future<int> _runPlan(
  ArgResults r,
  Lang lang,
  Map<String, String> env,
  StringSink out,
  StringSink err,
  ProcessRunner runner,
) async {
  if (r.rest.isNotEmpty) {
    throw _UsageError(tr(lang, 'usage.unexpectedArgs', [r.rest.join(' ')]));
  }
  final format = Format.values.byName((r['format'] as String?) ?? 'text');
  final plan = await buildPlan(_planRequest(r, env, runner));
  out.writeln(renderPlan(plan.entries, plan.notices, format, lang));
  if (format != Format.json) {
    for (final n in plan.notices) {
      err.writeln('${tr(lang, 'warning.prefix')} ${n.text(lang)}');
    }
  }
  return 0;
}

Future<int> _runLog(
  ArgResults r,
  Lang lang,
  Map<String, String> env,
  StringSink out,
  StringSink err,
  ProcessRunner runner,
) async {
  final all = r['all'] == true;
  final packages = r.rest;
  if (!all && packages.isEmpty) {
    throw _UsageError(tr(lang, 'usage.needPackages'));
  }
  if (all && packages.isNotEmpty) {
    throw _UsageError(tr(lang, 'usage.allAndPackages'));
  }
  final from = r['from'] as String?;
  final to = r['to'] as String?;
  if ((from != null || to != null) && (all || packages.length != 1)) {
    throw _UsageError(tr(lang, 'usage.fromToSingle'));
  }
  int? budget;
  if (r['budget'] != null) {
    budget = int.tryParse(r['budget'] as String);
    if (budget == null || budget <= 0) {
      throw _UsageError(tr(lang, 'usage.badBudget', [r['budget'] as String]));
    }
  }
  final format = Format.values.byName((r['format'] as String?) ?? 'text');
  final failOn = FailOn.values.byName((r['fail-on'] as String?) ?? 'none');
  final hosted = env['PUBDELTA_HOSTED_URL'];

  final report = await runLog(
    LogRequest(
      plan: _planRequest(r, env, runner),
      packages: packages,
      all: all,
      from: from,
      to: to,
      changelogDir: r['changelog-dir'] as String?,
      offline: r['offline'] == true,
      hostedOverride: (hosted == null || hosted.isEmpty) ? null : hosted,
      onFetch: (name) => err.writeln(tr(lang, 'progress.fetching', [name])),
    ),
    budget: budget,
    format: format,
    lang: lang,
  );

  out.writeln(report.text);
  if (format != Format.json) {
    for (final n in report.result.notices) {
      err.writeln('${tr(lang, 'warning.prefix')} ${n.text(lang)}');
    }
  }
  if (report.result.failures.isNotEmpty) {
    err.writeln(
      tr(lang, 'log.failed', [
        '${report.result.failures.length}',
        report.result.failures.keys.join(', '),
      ]),
    );
    return 4;
  }
  if (report.trips(failOn)) {
    final names = failOn == FailOn.breaking ? report.breaking : report.majors;
    err.writeln(tr(lang, 'failon.tripped', [failOn.name, names.join(', ')]));
    return 1;
  }
  return 0;
}
