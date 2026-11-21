## 6.1.0

- `recommended`:
  - added [use_null_aware_elements] (https://github.com/dart-lang/core/issues/899)
  - added [no_wildcard_variable_uses] (https://github.com/dart-lang/core/issues/832)
- Run `dart format` with the new style.

[use_null_aware_elements]: https://dart.dev/lints/use_null_aware_elements
[no_wildcard_variable_uses]: https://dart.dev/lints/no_wildcard_variable_uses

## 6.0.0

- `core`:
  - added [strict_top_level_inference] (https://github.com/dart-lang/core/issues/836)
- `recommended`:
  - added [unnecessary_underscores] (https://github.com/dart-lang/core/issues/856)
- Require Dart 3.8.

[strict_top_level_inference]: https://dart.dev/lints/strict_top_level_inference
[unnecessary_underscores]: https://dart.dev/lints/unnecessary_underscores

## 5.1.1

- Updated the SDK lower bound to 3.6.
- Move to `dart-lang/core` monorepo.

## 5.1.0

- `core`:
  - added [unintended_html_in_doc_comment] (https://github.com/dart-lang/lints/issues/192)
- Updated the SDK lower bound to 3.6 (dev).

[unintended_html_in_doc_comment]: https://dart.dev/lints/unintended_html_in_doc_comment

## 5.0.0

- `recommended`:
  - added [invalid_runtime_check_with_js_interop_types] (https://github.com/dart-lang/lints/issues/188)
  - added [unnecessary_library_name] (https://github.com/dart-lang/lints/issues/181)
  - removed [avoid_null_checks_in_equality_operators] (https://github.com/dart-lang/lints/issues/200)
- Updated the SDK lower-bound to 3.5.

[invalid_runtime_check_with_js_interop_types]: https://dart.dev/tools/linter-rules/invalid_runtime_check_with_js_interop_types
[unnecessary_library_name]: https://dart.dev/lints/unnecessary_library_name
[avoid_null_checks_in_equality_operators]: https://dart.dev/tools/linter-rules/avoid_null_checks_in_equality_operators

## 4.0.0

- `core`:
  - added `library_annotations` (https://github.com/dart-lang/lints/issues/177)
  - added `no_wildcard_variable_uses` (https://github.com/dart-lang/lints/issues/139)
  - removed `package_prefixed_library_names` (https://github.com/dart-lang/lints/issues/172)
- `recommended`:
  - removed `library_names` (https://github.com/dart-lang/lints/issues/181)
- Updated the SDK lower-bound to 3.1.
- Add a section on upgrading to the latest lint set to the readme.
