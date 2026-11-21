## 2.7.0

* Remove sorting of the `allowedHelp` argument in usage output. Ordering will
  depend on key order for the passed `Map`.
* Fix the repository URL in `pubspec.yaml`.
* Added option `hideNegatedUsage` to `ArgParser.flag()` allowing a flag to be
  `negatable` without showing it in the usage text.
* Fixed #101, adding check for mandatory when using `.option()`.

## 2.6.0

* Added source argument when throwing a `ArgParserException`.
* Fix inconsistent `FormatException` messages
* Require Dart 3.3
* Move to `dart-lang/core` monorepo.

## 2.5.0

* Introduce new typed `ArgResults` `flag(String)`, `option(String)`, and
  `multiOption(String)` methods.
* Require Dart 3.0.
