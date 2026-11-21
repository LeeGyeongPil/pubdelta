/// Internal modules of the `pubdelta` command line tool.
///
/// This library exists so tests and the MCP server can share code. It is not
/// a stable public API; use the `pubdelta` executable instead.
library;

export 'src/budget.dart';
export 'src/changelog_parser.dart';
export 'src/cli.dart' show runCli, describeArgError, exitUnexpected;
export 'src/hosted_client.dart';
export 'src/i18n.dart';
export 'src/lockfile.dart';
export 'src/mcp_server.dart';
export 'src/outdated.dart';
export 'src/render.dart';
export 'src/report.dart';
export 'src/service.dart';
export 'src/signals.dart';
export 'src/sources.dart';
export 'src/text_file.dart';
export 'src/version.dart';
export 'src/version_range.dart';
