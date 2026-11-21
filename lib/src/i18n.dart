import 'messages_en.dart';
import 'messages_ko.dart';

/// Output languages. Anything that is not Korean is English.
enum Lang { en, ko }

/// Picks the language: `--lang` flag > `PUBDELTA_LANG` > `LC_ALL` >
/// `LC_MESSAGES` > `LANG`. The first non-empty value decides; a value that
/// starts with `ko` means Korean, everything else English.
Lang resolveLang({String? flag, required Map<String, String> env}) {
  if (flag != null && flag.isNotEmpty) return _fromText(flag);
  for (final key in const ['PUBDELTA_LANG', 'LC_ALL', 'LC_MESSAGES', 'LANG']) {
    final value = env[key];
    if (value != null && value.isNotEmpty) return _fromText(value);
  }
  return Lang.en;
}

Lang _fromText(String value) =>
    value.toLowerCase().startsWith('ko') ? Lang.ko : Lang.en;

/// The message table for [lang] (same keys in both languages).
Map<String, String> messageTable(Lang lang) =>
    lang == Lang.ko ? messagesKo : messagesEn;

/// Looks up [key] and fills `{0}`, `{1}`, ... with [args].
///
/// An argument made with [messageRef] is itself translated first, so one
/// translated message can sit inside another (no English text leaks into a
/// Korean sentence).
String tr(Lang lang, String key, [List<String> args = const []]) {
  var text = messageTable(lang)[key] ?? messagesEn[key] ?? key;
  for (var i = 0; i < args.length; i++) {
    text = text.replaceAll('{$i}', _resolveArg(lang, args[i]));
  }
  return text;
}

// 메시지 안에 다른 메시지를 넣을 때 쓰는 표시. 일반 텍스트에는 나오지 않는 제어 문자.
const String _refStart = '\u0001';
const String _refSeparator = '\u0002';

/// An argument for [tr], [Notice] or [PubdeltaException] that stands for the
/// message [key] (with [args]) and is translated when it is shown.
String messageRef(String key, [List<String> args = const []]) =>
    [_refStart + key, ...args].join(_refSeparator);

String _resolveArg(Lang lang, String arg) {
  if (!arg.startsWith(_refStart)) return arg;
  final parts = arg.substring(_refStart.length).split(_refSeparator);
  return tr(lang, parts.first, parts.sublist(1));
}

/// A warning or hint that is translated when it is shown.
class Notice {
  const Notice(this.key, [this.args = const []]);

  final String key;
  final List<String> args;

  String text(Lang lang) => tr(lang, key, args);

  @override
  bool operator ==(Object other) =>
      other is Notice &&
      other.key == key &&
      other.args.join('\u0000') == args.join('\u0000');

  @override
  int get hashCode => Object.hash(key, args.join('\u0000'));
}

/// An error the user can fix. [exitCode] follows the CLI contract:
/// 2 usage, 3 input, 4 changelog unavailable, 5 outdated failed.
class PubdeltaException implements Exception {
  PubdeltaException(this.exitCode, this.key, [this.args = const []]);

  final int exitCode;
  final String key;
  final List<String> args;

  String message(Lang lang) => tr(lang, key, args);

  @override
  String toString() => message(Lang.en);
}

/// A one-line, language-neutral description of an unexpected error (its
/// type and message, no stack trace) for the `error.unexpected` message.
String describeUnexpected(Object e) {
  final text = '$e'.split('\n').first.trim();
  final type = '${e.runtimeType}';
  if (text.isEmpty) return type;
  return text.startsWith(type) ? text : '$type: $text';
}
