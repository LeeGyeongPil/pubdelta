import 'package:pub_semver/pub_semver.dart';

import 'i18n.dart';

/// How far apart two versions are, using Dart's rules.
///
/// For `0.x` versions a minor change is the breaking unit, so it counts as
/// [major] (`^0.13.6` means `<0.14.0`).
enum Bump { major, minor, patch, prerelease, build, none }

/// Parses [text] with `pub_semver`, or throws an input error naming [what].
Version parseVersion(String text, {String what = 'version'}) {
  try {
    return Version.parse(text.trim());
  } on FormatException {
    throw PubdeltaException(3, 'input.badVersion', [what, text]);
  }
}

/// Classifies the step from [from] to [to].
Bump classifyBump(Version from, Version to) {
  if (from == to) return Bump.none;
  if (from.major != to.major) return Bump.major;
  if (from.major == 0 && from.minor != to.minor) return Bump.major;
  if (from.minor != to.minor) return Bump.minor;
  if (from.patch != to.patch) return Bump.patch;
  if (from.preRelease.join('.') != to.preRelease.join('.')) {
    return Bump.prerelease;
  }
  return Bump.build;
}

/// True when [v] is inside the half-open range (from, to].
///
/// [from] is excluded because it is the version already in use.
bool inRange(Version v, Version from, Version to) => v > from && v <= to;

/// Throws an input error when [to] is lower than [from].
void validateRange(Version from, Version to, {String? package}) {
  if (to < from) {
    throw PubdeltaException(3, 'input.toBeforeFrom', [
      package ?? '-',
      '$from',
      '$to',
    ]);
  }
}
