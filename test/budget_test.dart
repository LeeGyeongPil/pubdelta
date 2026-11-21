import 'dart:io';

import 'package:pub_semver/pub_semver.dart';
import 'package:pubdelta/pubdelta.dart';
import 'package:test/test.dart';

PackageLog slice(String name, String from, String to) {
  return sliceChangelog(
    pkg: LockedPackage(
      name: name,
      version: Version.parse(from),
      dependency: 'direct main',
      source: 'hosted',
      hostedUrl: 'https://pub.dev',
    ),
    from: Version.parse(from),
    to: Version.parse(to),
    fetched: FetchedChangelog(
      text: File('example/changelogs/$name.md').readAsStringSync(),
      origin: Origin.dir,
    ),
  );
}

List<PackageLog> packages() => [
  slice('firebase_core', '4.14.0', '5.2.0'),
  slice('http', '1.2.2', '1.6.0'),
  slice('lints', '4.0.0', '6.1.0'),
  slice('riverpod', '3.4.0', '3.5.0'),
  slice('dio', '5.9.2', '5.11.1'),
];

int measure(List<PackageLog> p, List<Omitted> o) => estimateTokens(
  renderLog(
    LogOutput(packages: p, omitted: o, estimatedTokens: 99999),
    Format.md,
    Lang.en,
  ),
);

Set<String> kept(BudgetResult r) => {
  for (final p in r.packages)
    for (final e in p.entries) '${p.name}@${e.version}',
};

void main() {
  test('estimateTokens is characters / 4 rounded up', () {
    expect(estimateTokens(''), 0);
    expect(estimateTokens('abcd'), 1);
    expect(estimateTokens('abcde'), 2);
  });

  test('the result stays within the budget', () {
    for (final budget in [600, 1200, 2500, 5000]) {
      final r = applyBudget(packages(), budget, measure);
      expect(r.estimatedTokens, lessThanOrEqualTo(budget), reason: '$budget');
    }
  });

  test('strong entries are kept before weak and plain ones', () {
    final r = applyBudget(packages(), 1200, measure);
    final k = kept(r);
    expect(k, contains('http@1.6.0'), reason: 'strong');
    expect(k, contains('firebase_core@5.0.0'), reason: 'strong');
    expect(k, isNot(contains('dio@5.10.0')), reason: 'plain entries go first');
    expect(r.omitted, isNotEmpty);
  });

  test(
    'every dropped entry is listed in omitted; nothing is lost silently',
    () {
      final all = packages();
      final total = all.fold<int>(0, (n, p) => n + p.entries.length);
      final r = applyBudget(all, 1500, measure);
      expect(kept(r).length + r.omitted.length, total);
      for (final o in r.omitted) {
        expect(kept(r), isNot(contains('${o.name}@${o.version}')));
      }
    },
  );

  test('a big budget keeps everything and omits nothing', () {
    final r = applyBudget(packages(), 1000000, measure);
    expect(r.omitted, isEmpty);
  });

  test('an entry that does not fit whole is cut down to its signal lines', () {
    var sawTrimmed = false;
    for (final budget in [300, 400, 500, 600, 700, 800]) {
      final r = applyBudget(packages(), budget, measure);
      for (final p in r.packages) {
        for (final e in p.entries.where((e) => e.trimmed)) {
          sawTrimmed = true;
          expect(e.signals, isNotEmpty);
          expect(e.body.split('\n'), [
            for (final s in e.signals) s.line.trim(),
          ]);
        }
      }
      expect(r.estimatedTokens, lessThanOrEqualTo(budget));
    }
    expect(sawTrimmed, isTrue, reason: 'some budget must force trimming');
  });

  test('melos links are shortened', () {
    final r = applyBudget(packages(), 100000, measure);
    final fb = r.packages.firstWhere((p) => p.name == 'firebase_core');
    final body = fb.entries.first.body;
    expect(body, contains('(#18968)'));
    expect(body, isNot(contains('https://github.com/firebase')));
  });

  group('rendering of the omitted list', () {
    final r = applyBudget(packages(), 900, measure);

    LogOutput output() => LogOutput(
      packages: r.packages,
      omitted: r.omitted,
      estimatedTokens: r.estimatedTokens,
    );

    test('text says omitted (en) and the Korean text says 생략', () {
      expect(renderLog(output(), Format.text, Lang.en), contains('omitted: '));
      expect(renderLog(output(), Format.text, Lang.ko), contains('생략: '));
    });

    test('json has an omitted array with name and version', () {
      final json = renderLog(output(), Format.json, Lang.en);
      expect(json, contains('"omitted":[{"name":'));
      expect(json, contains('"estimatedTokens":${r.estimatedTokens}'));
    });
  });
}
