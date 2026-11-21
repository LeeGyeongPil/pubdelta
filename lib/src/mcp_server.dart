import 'dart:convert';

import 'i18n.dart';
import 'outdated.dart';
import 'render.dart';
import 'report.dart';
import 'service.dart';
import 'version.dart';

/// Protocol versions this server can speak; the newest is the default.
const List<String> supportedProtocolVersions = [
  '2025-06-18',
  '2025-03-26',
  '2024-11-05',
];

/// A small MCP server over stdio (one JSON-RPC message per line).
///
/// It implements only what a tools-only server needs: `initialize`, `ping`,
/// `tools/list` and `tools/call`. Tool texts are English unless
/// `PUBDELTA_LANG` says otherwise.
class McpServer {
  McpServer({required this.env, this.runner = defaultRunner})
    : lang = resolveLang(env: env);

  final Map<String, String> env;
  final ProcessRunner runner;
  final Lang lang;

  /// Reads lines from [lines] until the stream ends, answering on [out].
  Future<void> serve(Stream<String> lines, StringSink out) async {
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      Map<String, Object?>? response;
      try {
        response = await handleLine(line);
      } catch (e) {
        // handleLine 이 이미 막지만, 한 요청의 실패로 서버가 끝나는 일은 없게 한 번 더 막는다
        response = _error(
          null,
          -32603,
          'Internal error: ${describeUnexpected(e)}',
        );
      }
      if (response != null) out.writeln(jsonEncode(response));
    }
  }

  /// Handles one JSON-RPC message; returns the response, or null for
  /// notifications.
  Future<Map<String, Object?>?> handleLine(String line) async {
    final Object? message;
    try {
      message = jsonDecode(line);
    } on FormatException {
      return _error(null, -32700, 'Parse error');
    }
    if (message is! Map<String, Object?>) {
      return _error(null, -32600, 'Invalid Request');
    }
    final id = message['id'];
    final method = message['method'];
    if (method is! String) return _error(id, -32600, 'Invalid Request');
    final isNotification = !message.containsKey('id');
    final params =
        message['params'] is Map<String, Object?>
            ? message['params'] as Map<String, Object?>
            : <String, Object?>{};

    switch (method) {
      case 'initialize':
        final asked = params['protocolVersion'];
        return _ok(id, {
          'protocolVersion':
              supportedProtocolVersions.contains(asked)
                  ? asked
                  : supportedProtocolVersions.first,
          'capabilities': {'tools': {}},
          'serverInfo': {'name': 'pubdelta', 'version': pubdeltaVersion},
        });
      case 'ping':
        return _ok(id, {});
      case 'tools/list':
        return _ok(id, {'tools': _tools});
      case 'tools/call':
        return _ok(id, await _callTool(params));
    }
    if (isNotification) return null; // e.g. notifications/initialized
    return _error(id, -32601, 'Method not found: $method');
  }

  Future<Map<String, Object?>> _callTool(Map<String, Object?> params) async {
    final name = params['name'];
    final args =
        params['arguments'] is Map<String, Object?>
            ? params['arguments'] as Map<String, Object?>
            : <String, Object?>{};
    try {
      switch (name) {
        case 'plan':
          return _text([await _plan(args)]);
        case 'changelog':
          return await _changelog(args);
      }
      return _text([
        tr(lang, 'mcp.unknownTool', ['$name']),
      ], isError: true);
    } on PubdeltaException catch (e) {
      return _text([e.message(lang)], isError: true);
    } on _BadArgument catch (e) {
      return _text([
        tr(lang, 'mcp.badArgument', [e.name, e.value]),
      ], isError: true);
    } catch (e) {
      // 예상하지 못한 예외도 이 요청만 오류로 답하고 서버는 계속 산다 (CLI 의 종료 코드 6 과 같은 문구)
      return _text([
        tr(lang, 'error.unexpected', [describeUnexpected(e)]),
      ], isError: true);
    }
  }

  PlanRequest _planRequest(Map<String, Object?> args) {
    final dir = _string(args, 'projectDir') ?? '.';
    final mode = _string(args, 'mode') ?? 'resolvable';
    // CLI 와 같다: dev 는 항상 포함하고 include 는 그 위에 더한다
    final include = _stringList(args, 'include') ?? const <String>[];
    for (final kind in include) {
      if (kind != 'dev' && kind != 'transitive') {
        throw _BadArgument('include', kind);
      }
    }
    return PlanRequest(
      lockFile: _string(args, 'lockFile') ?? '$dir/pubspec.lock',
      outdatedFile: _string(args, 'outdatedFile'),
      mode: Mode.values.firstWhere(
        (m) => m.name == mode,
        orElse: () => throw _BadArgument('mode', mode),
      ),
      include: {'dev', ...include},
      environment: env,
      runner: runner,
    );
  }

  Future<String> _plan(Map<String, Object?> args) async {
    final plan = await buildPlan(_planRequest(args));
    return renderPlan(plan.entries, plan.notices, Format.md, lang);
  }

  Future<Map<String, Object?>> _changelog(Map<String, Object?> args) async {
    final packages = _stringList(args, 'packages') ?? const [];
    final budget = args['budget'];
    final formatName = _string(args, 'format') ?? 'md';
    if (formatName != 'md' && formatName != 'json') {
      throw _BadArgument('format', formatName);
    }
    final hosted = env['PUBDELTA_HOSTED_URL'];
    final report = await runLog(
      LogRequest(
        plan: _planRequest(args),
        packages: packages,
        all: packages.isEmpty,
        from: _string(args, 'from'),
        to: _string(args, 'to'),
        changelogDir: _string(args, 'changelogDir'),
        offline: args['offline'] == true,
        hostedOverride: (hosted == null || hosted.isEmpty) ? null : hosted,
      ),
      budget: budget is int && budget > 0 ? budget : null,
      format: formatName == 'json' ? Format.json : Format.md,
      lang: lang,
    );
    final extra =
        formatName == 'json'
            ? const <String>[]
            : [for (final n in report.result.notices) n.text(lang)];
    return _text([
      report.text,
      ...extra,
    ], isError: report.result.failures.isNotEmpty);
  }
}

/// A tool argument with a value we do not accept (reported as
/// `mcp.badArgument`). Our own type, so an unrelated [ArgumentError] from
/// deeper code is not mistaken for a bad argument.
class _BadArgument implements Exception {
  _BadArgument(this.name, this.value);

  final String name;
  final String value;
}

String? _string(Map<String, Object?> args, String key) {
  final v = args[key];
  return v is String && v.isNotEmpty ? v : null;
}

List<String>? _stringList(Map<String, Object?> args, String key) {
  final v = args[key];
  if (v is List<Object?>) return [for (final x in v) '$x'];
  return null;
}

Map<String, Object?> _ok(Object? id, Map<String, Object?> result) => {
  'jsonrpc': '2.0',
  'id': id,
  'result': result,
};

Map<String, Object?> _error(Object? id, int code, String message) => {
  'jsonrpc': '2.0',
  'id': id,
  'error': {'code': code, 'message': message},
};

Map<String, Object?> _text(List<String> texts, {bool isError = false}) => {
  'content': [
    for (final t in texts) {'type': 'text', 'text': t},
  ],
  'isError': isError,
};

const Map<String, Object?> _projectDirProp = {
  'type': 'string',
  'description':
      'Directory that contains pubspec.lock (default: current directory).',
};

final List<Map<String, Object?>> _tools = [
  {
    'name': 'plan',
    'description':
        'List the packages in a Dart or Flutter project that have a newer '
        'version, from the locked version to the upgrade target, with '
        'bump size (0.x minor counts as major) and retracted, discontinued '
        'and advisory flags. Reads pubspec.lock and runs `dart pub outdated`.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'projectDir': _projectDirProp,
        'mode': {
          'type': 'string',
          'enum': ['upgradable', 'resolvable', 'latest'],
          'description':
              'Which pub outdated column is the target '
              '(default resolvable).',
        },
        'include': {
          'type': 'array',
          'items': {
            'type': 'string',
            'enum': ['dev', 'transitive'],
          },
          'description':
              'Extra dependency kinds. Direct main and dev are always '
              'included; add "transitive" for indirect dependencies.',
        },
      },
    },
  },
  {
    'name': 'changelog',
    'description':
        'Return only the CHANGELOG entries between the locked version '
        '(excluded) and the upgrade target (included) for each package, '
        'with breaking-change signals first (strong, medium, weak). Use it '
        'before upgrading dependencies. Set budget (estimated tokens) to '
        'keep the answer short; omitted entries are listed.',
    'inputSchema': {
      'type': 'object',
      'properties': {
        'projectDir': _projectDirProp,
        'packages': {
          'type': 'array',
          'items': {'type': 'string'},
          'description':
              'Package names; empty means all direct dependencies '
              'that have an upgrade.',
        },
        'from': {
          'type': 'string',
          'description': 'Override the current version (one package only).',
        },
        'to': {
          'type': 'string',
          'description': 'Override the target version (one package only).',
        },
        'budget': {
          'type': 'integer',
          'description': 'Maximum estimated tokens (characters / 4).',
        },
        'format': {
          'type': 'string',
          'enum': ['md', 'json'],
          'description': 'Output format (default md).',
        },
        'offline': {
          'type': 'boolean',
          'description':
              'Do not use the network; read only pub cache and '
              'changelogDir.',
        },
        'changelogDir': {
          'type': 'string',
          'description':
              'Directory with <package>.md changelog files that '
              'take priority.',
        },
        'outdatedFile': {
          'type': 'string',
          'description':
              'Use a saved `dart pub outdated --json` file instead '
              'of running it.',
        },
      },
    },
  },
];
