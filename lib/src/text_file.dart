import 'dart:convert';
import 'dart:io';

/// Text read by [readTextFile] or [decodeText].
class TextFile {
  const TextFile(this.text, {this.hadInvalidUtf8 = false});

  final String text;

  /// True when some bytes were not valid UTF-8 and were replaced with U+FFFD.
  final bool hadInvalidUtf8;
}

/// A file that exists but cannot be read (permission denied, a directory,
/// an I/O error, ...).
class UnreadableFile implements Exception {
  UnreadableFile(this.path, this.reason);

  final String path;

  /// The operating system's reason; a fact, not a sentence of ours.
  final String reason;

  @override
  String toString() => '$path: $reason';
}

/// The one place where pubdelta reads a text file from disk.
///
/// Every input file goes through here — lock file, saved outdated JSON,
/// `--changelog-dir` files, path dependencies and the pub cache — so they all
/// behave the same:
///
/// * bytes that are not valid UTF-8 never throw; they become U+FFFD and
///   [TextFile.hadInvalidUtf8] is set, and the caller decides whether that is
///   a warning (changelogs) or an input error (lock file, outdated file);
/// * a UTF-8 byte order mark is dropped, so a first `## 1.0.0` heading is
///   still found;
/// * file-system errors become one exception type, [UnreadableFile].
Future<TextFile> readTextFile(File file) async {
  final List<int> bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException catch (e) {
    final os = e.osError?.message ?? '';
    throw UnreadableFile(file.path, os.isNotEmpty ? os : e.message);
  }
  return decodeText(bytes);
}

/// Decodes [bytes] as UTF-8 the same way as [readTextFile] (also used for
/// changelogs inside downloaded archives).
TextFile decodeText(List<int> bytes) {
  // UTF-8 BOM(EF BB BF)는 버린다 — 남아 있으면 첫 머리글을 못 찾는다
  final hasBom =
      bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final body = hasBom ? bytes.sublist(3) : bytes;
  try {
    return TextFile(utf8.decode(body));
  } on FormatException {
    // Latin-1 등 UTF-8 이 아닌 파일: 죽지 않고 깨진 바이트만 U+FFFD 로 바꾼다
    return TextFile(
      const Utf8Decoder(allowMalformed: true).convert(body),
      hadInvalidUtf8: true,
    );
  }
}
