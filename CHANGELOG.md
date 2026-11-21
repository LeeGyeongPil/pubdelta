# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0]

### Added

- `pubdelta plan`: lists packages with a newer version (current, target, bump
  size, dependency kind, retracted / discontinued / advisory flags) from
  `pubspec.lock` and `dart pub outdated --json`, with an offline fallback to
  `dart pub upgrade --offline --dry-run --major-versions`.
- `pubdelta log`: prints only the CHANGELOG entries in (current, target],
  ranked by breaking-change signals (strong, medium, weak), with `--budget`,
  `--fail-on none|breaking|major`, `--from`, `--to`, `--offline` and
  `--changelog-dir`.
- Changelog lookup order: `--changelog-dir`, pub cache, hosted repository
  (`PUBDELTA_HOSTED_URL` overrides the lock file URL).
- Tolerant heading parser (`## 1.6.0`, `## 3.5.0 - date`, `(retracted)`,
  `## [4.7.3]`, `# v1.2.0`, build numbers, pre-releases).
- `pubdelta mcp`: MCP server on stdio with the tools `plan` and `changelog`.
- English and Korean output: `--lang en|ko`, `PUBDELTA_LANG`, `LC_ALL`,
  `LC_MESSAGES`, `LANG`.
- Output formats `text`, `md` and `json`.
- `example/` with sample lock file, outdated JSON and changelog excerpts.
