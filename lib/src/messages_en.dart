/// English message table. Keep the key set identical to `messages_ko.dart`
/// (a test enforces it). `{0}`, `{1}`, ... are filled by `tr()`.
const Map<String, String> messagesEn = {
  // errors and usage
  'error.prefix': 'error: {0}',
  'error.unexpected':
      'unexpected error ({0}). This is a bug in pubdelta; please report it with the command you ran.',
  'usage.error': 'pubdelta: {0}',
  'usage.hint': 'Run "pubdelta --help" for usage.',
  'usage.unknownCommand': 'unknown command "{0}"',
  'usage.unexpectedArgs': 'unexpected arguments: {0}',
  'usage.needPackages':
      'give at least one package name or use --all (example: pubdelta log http)',
  'usage.allAndPackages': 'use either package names or --all, not both',
  'usage.fromToSingle': '--from and --to work with exactly one package name',
  'usage.badBudget': '--budget needs a positive whole number, got "{0}"',
  // option parse errors (our own words instead of the args package's English)
  'usage.unknownOption': '"{1}" has no option "{0}"',
  'usage.missingValue': 'option "{0}" needs a value',
  'usage.badValue': '"{0}" is not a valid value for {1} (choose from: {2})',
  'usage.flagNoValue': 'flag "{0}" does not take a value',
  'usage.cannotNegate': '"{0}" is not valid: {1} cannot be turned off',
  'usage.badArgument': 'invalid option or value: {0}',

  // help
  'help.top':
      'pubdelta - show only the CHANGELOG entries between the version '
      'you use and the version you upgrade to.\n\n'
      'Usage: pubdelta <command> [options]\n\n'
      'Commands:\n'
      '  plan   list packages with a newer version (current -> target)\n'
      '  log    print the CHANGELOG entries in (current, target], '
      'breaking-change signals first\n'
      '  mcp    run an MCP server on stdio for coding agents\n\n'
      'Global options:',
  'help.plan':
      'Usage: pubdelta plan [options]\n'
      'List packages that have a newer version, from the locked version to '
      'the target.',
  'help.log':
      'Usage: pubdelta log <package>... | --all [options]\n'
      'Print the CHANGELOG entries after the locked version up to the '
      'target, strongest breaking-change signals first.',
  'help.mcp':
      'Usage: pubdelta mcp\n'
      'Run an MCP server on stdio with the tools "plan" and "changelog".',
  'opt.lang':
      'Output language (default: PUBDELTA_LANG, then LC_ALL, LC_MESSAGES, LANG; otherwise en).',
  'opt.help': 'Show this help.',
  'opt.version': 'Print the version.',
  'opt.lock': 'Path to pubspec.lock (default: pubspec.lock).',
  'opt.outdated':
      'Use a saved "dart pub outdated --json" file instead of running it.',
  'opt.mode': 'Which pub outdated column is the target (default: resolvable).',
  'opt.include':
      'Also include these dependency kinds, comma separated. Direct main and dev are always included; add "transitive" for indirect ones (default: none extra).',
  'opt.format': 'Output format (default: text).',
  'opt.all': 'All packages that have an upgrade.',
  'opt.from': 'Current version (default: from pubspec.lock). One package only.',
  'opt.to': 'Target version (default: from the plan). One package only.',
  'opt.changelogDir':
      'Directory with <package>.md changelogs; they are used first.',
  'opt.offline': 'Never use the network (pub cache and --changelog-dir only).',
  'opt.budget':
      'Keep the output within about this many tokens (estimated as characters / 4).',
  'opt.failOn':
      'Exit with code 1 when a strong breaking signal (breaking) or also a '
      'major bump (major) is found (default: none).',

  // input errors
  'input.badVersion': 'cannot read {0} "{1}" as a version (example: 1.2.3).',
  'input.toBeforeFrom':
      '{0}: target {2} is lower than current {1}. Check --from/--to or the lock file.',
  'input.noLock':
      'lock file not found: {0}. Run "dart pub get" first or pass --lock <path>.',
  'input.lockInvalid':
      'cannot read lock file {0}: {1}. Re-create it with "dart pub get".',
  'input.noOutdatedFile': 'outdated file not found: {0}.',
  'input.cannotRead':
      'cannot read {0} ({1}). Check that it is a file you are allowed to read.',
  'read.notUtf8': 'the file is not valid UTF-8 text',
  'lock.noPackages': 'there is no "packages" map',
  'lock.notMap': 'package "{0}" is not a map',
  'lock.badVersion': 'package "{0}" has version "{1}"',
  'input.unknownPackage':
      'package "{0}" is not in the lock file. Check the spelling; "pubdelta plan --include transitive" lists known packages.',

  // outdated
  'outdated.badFile':
      'The file {0} is not valid "dart pub outdated --json" output. Recreate it with: dart pub outdated --json > {0}',
  'outdated.badJson':
      '"dart pub outdated --json" did not print the expected JSON.',
  'outdated.fallback':
      '"dart pub outdated" failed ({0}); using "dart pub upgrade --offline --dry-run --major-versions" instead. Only versions in the pub cache are visible.',
  'outdated.failed':
      '"dart pub outdated" failed ({0}) and so did the offline fallback ({1}). Check your network/TLS settings, or pass --outdated <file.json>.',
  'outdated.noOutput': 'no error output',
  'outdated.timedOut': 'timed out after {0} seconds and was stopped',
  'outdated.fromFile':
      'upgrade targets come from the saved file {0}, not from a live "dart pub outdated" (sample data when this is example/outdated.json).',

  // parsing and sources
  'parse.unreleased': 'skipped unreleased section "{0}".',
  'parse.skippedHeading': 'skipped heading that is not a version: "{0}".',
  'parse.noVersionHeadings':
      'no version headings found; showing the first {0} lines (low confidence).',
  'parse.empty':
      'the CHANGELOG is empty; there is nothing to show (low confidence).',
  'source.noChangelog':
      '{0}: {1} dependencies have no changelog that pubdelta can read.',
  'source.notUtf8':
      '{0}: the CHANGELOG is not valid UTF-8; characters that could not be read were replaced with �.',
  'source.pathRangeUnknown':
      '{0}: path dependency, the local CHANGELOG may not match the locked version range (range unknown).',
  'fetch.tls':
      '{0}: TLS error ({1}). A proxy may be intercepting HTTPS. Use --changelog-dir <dir> with <package>.md files, set PUBDELTA_HOSTED_URL to a mirror, or warm the pub cache (PUB_CACHE) and use --offline.',
  'fetch.connection':
      '{0}: cannot connect ({1}). Use --changelog-dir <dir>, set PUBDELTA_HOSTED_URL to a reachable mirror, or use --offline with a warm pub cache.',
  'fetch.timeout':
      '{0}: timed out ({1}). Try again, or use --changelog-dir / PUBDELTA_HOSTED_URL.',
  'fetch.http':
      '{0}: the repository returned an error ({1}). Check PUBDELTA_HOSTED_URL or use --changelog-dir.',
  'fetch.notFound':
      '{0}: not found on the repository ({1}). Check the package name and the hosted URL in the lock file.',
  'fetch.versionNotFound':
      '{0}: the repository does not list the target version ({1}). Pass --to with a published version.',
  'fetch.noChangelog':
      '{0}: the package archive has no CHANGELOG file ({1}). Read its release notes manually or use --changelog-dir.',
  'fetch.offline':
      '{0}: target version {1} is not in the pub cache and --offline is set. Put it there with "dart pub cache add {0} --version {1}", or pass --changelog-dir.',
  'fetch.badJson':
      '{0}: the package information is not valid JSON ({1}). Check PUBDELTA_HOSTED_URL or use --changelog-dir.',
  'fetch.noVersions':
      '{0}: the package information lists no versions ({1}). Check PUBDELTA_HOSTED_URL or use --changelog-dir.',
  'fetch.badArchive':
      '{0}: the package archive could not be read ({1}). Try again, or use --changelog-dir.',
  'fetch.tooLarge':
      '{0}: the download is larger than the size limit ({1}). Use --changelog-dir.',
  'fetch.badUrl':
      '{0}: the repository URL is not valid ({1}). Check PUBDELTA_HOSTED_URL or the hosted URL in the lock file (it needs http:// or https:// and a host).',
  'fetch.unreadable':
      '{0}: the changelog file cannot be read ({1}). Check its permissions, or pass --changelog-dir with a readable copy.',

  // MCP tool errors
  'mcp.unknownTool': 'unknown tool "{0}" (available: plan, changelog)',
  'mcp.badArgument': 'argument "{0}" has an invalid value: {1}',

  // log
  'log.upToDate': '{0}: already at the target version {1}, nothing to show.',
  'log.noEntriesInRange':
      '{0}: no changelog entries between {1} and {2}; the changelog may not list these versions.',
  'log.usingDir':
      'changelogs are read from {0} first; they may be sample data (example/changelogs).',
  'log.empty': 'Nothing to show: no package has an upgrade target.',
  'log.title': 'Upgrade notes',
  'log.failed':
      '{0} package(s) have no changelog ({1}). See the warnings above. Exit code 4.',
  'failon.tripped': '--fail-on {0}: found in {1}.',
  'progress.fetching': 'fetching {0} ...',

  // plan output
  'plan.title': 'Upgrade plan',
  'plan.empty': 'Everything is at its upgrade target.',
  'col.package': 'Package',
  'col.current': 'Current',
  'col.target': 'Target',
  'col.bump': 'Bump',
  'col.kind': 'Kind',
  'col.flags': 'Flags',
  'bump.major': 'major',
  'bump.minor': 'minor',
  'bump.patch': 'patch',
  'bump.prerelease': 'prerelease',
  'bump.build': 'build',
  'bump.none': 'none',
  'dep.main': 'direct main',
  'dep.dev': 'direct dev',
  'dep.overridden': 'direct overridden',
  'dep.transitive': 'transitive',
  'flag.retracted': 'retracted',
  'flag.discontinued': 'discontinued',
  'flag.advisory': 'advisory',

  // log output
  'pkg.confidence': 'confidence: {0}',
  'conf.high': 'high',
  'conf.medium': 'medium',
  'conf.low': 'low',
  'conf.none': 'none',
  'pkg.moreSignals': '... and {0} more signal lines',
  'pkg.missing': 'versions published but missing from the changelog: {0}',
  'level.strong': 'STRONG',
  'level.medium': 'MEDIUM',
  'level.weak': 'WEAK',
  'warning.prefix': 'warning:',
  'note.prefix': 'note:',
  'entry.trimmed': '(trimmed to signal lines)',
  'entry.fallback': '(first {0} lines)',
  'omitted.line': 'omitted: {0} entries ({1}{2})',
  'omitted.more': ', and {0} more',
  'tokens.line': 'estimated tokens: ~{0} (characters / 4, approximate)',
};
