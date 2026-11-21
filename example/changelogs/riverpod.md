## 3.5.0 - 2026-11-06

- `ProviderObserver`s are no longer notified when a provider's future
  completes after the provider was disposed. This stops `providerDidFail` from
  reporting disposal errors, such as when an `autoDispose` provider awaiting
  another provider's `.future` is disposed mid-load (#4706).
- Added `ProviderDisposedException`. `provider.future` now completes with it
  instead of a `StateError` when the provider is disposed before emitting a value.
- Fix resuming a paused subscription scheduling a provider refresh while its dependency graph is still being flushed, which could throw `setState() or markNeedsBuild() called during build` in Flutter with diamond-shaped dependencies. (thanks to @yazanmg)
- Fix `StreamProvider`/`StreamNotifier` retaining obsolete dependency subscriptions across rebuilds until the stream closes, even after emitting data.
- `AsyncValueIsLoadingException` now has a public constructor. (thanks to @uveshm003)
- `debugTrackProviderCreation` is now exported by `package:riverpod/misc.dart`.
- Devtools now retain only the current provider snapshot by default. Set
  `debugTrackProviderHistory = true` (imported from `package:riverpod/misc.dart`)
  to opt into time-travel history; setting it back to `false` releases previous
  frames.
- Devtools inspection caches are released when their client closes or stops
  renewing its session for 30 seconds, including after an abrupt disconnect.
- Deprecated `Ref.exist`.
- Added `provider.exist`, which is listenable.
  This enables writing `ref.listen(provider.exist, ...)`.
- Fix the deprecated `container.exists`/`ref.exists` returning `false` from a
  scoped container for a provider mounted in an ancestor but never read through
  that scope (#4785).
- Fix `selectAsync` notifying a closed subscription after an upstream refresh.
- Fixed `ref.read`/`container.read` of `provider.listenable` throwing an internal `StateError` on `.value`; it now throws a clear one explaining `.listenable` needs `ref.watch`, `ref.listen` or `container.listen` instead (thanks to @Yasser-Ameur)
- Fixed a debug-only infinite loop in the circular-dependency check. Closing a
  dependency ring left the offending subscription in the graph, so a subsequent
  rebuild could make the check walk the cycle forever. The subscription is now
  removed when the check throws, and the walk keeps a visited set. (thanks to @chiliec)
- Migrated Material imports to `package:material_ui/material_ui.dart` and added
  `material_ui` as a dependency.
- Updated the DevTools extension to use Material UI themes and localizations.

## 3.4.3 - 2026-09-04

- Upgraded `analyzer` to `<15.0.0`
- Depend on `test_api` instead of `test`. Riverpod only used `addTearDown`, which
  `test` re-exports unchanged from `test_api`, so `ProviderContainer.test` is
  unaffected. This removes 34 transitive packages from the dependency graph of
  every project that uses Riverpod, including `analyzer`, whose version ceiling
  was blocking other tooling. (thanks to @samithahansaka)

## 3.4.2 - 2026-07-28

Fix a different source of `markNeedsBuild` error. Those are tricky!

## 3.4.1 - 2026-07-26

- Update devtool extension

## 3.4.0 - 2026-07-26

- Deprecated `SyncProviderTransformerMixin`. It is replaced by the newly added APIs
- Devtool-only: Better support for scoped providers with multiple overrides.
- Upgraded `analyzer` to `<15.0.0`
- Added `CustomProviderListenable`, a slightly simplified way of making custom provider extensions
- Added the ability to do `ValueListenable<int> listenable = ref.watch(counterProvider.listenable)`.
  This uses the new `pkg:listen`.
- Fix `invalidate`/`refresh` not finding providers and families when called
  from a scoped `ProviderContainer`/`ProviderScope` with overrides, if the
  provider was never read through that scope. (thanks to @itsUndefined)
- Fix markNeedsBuild exception when flushing a provider inside Widget lifecycle
- Fix `invalidate`/`refresh` not finding providers and families when called
  from a scoped `ProviderScope` with overrides, if the provider was never
  read through that scope. (thanks to @itsUndefined)
- Fixed a listener leak if `ConsumerState.dispose` threw.
