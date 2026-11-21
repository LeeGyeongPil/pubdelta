import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'text_file.dart';
import 'version.dart';

/// Every [FetchFailure.kind]. Each one has a `fetch.<kind>` message in both
/// message tables (a test checks this).
const List<String> fetchFailureKinds = [
  'tls',
  'connection',
  'timeout',
  'http',
  'notFound',
  'versionNotFound',
  'noChangelog',
  'offline',
  'badJson',
  'noVersions',
  'badArchive',
  'tooLarge',
  'badUrl',
  'unreadable',
];

/// Why a changelog could not be fetched; turned into a message by the caller.
///
/// [detail] holds only language-neutral facts (a URL, a status code, an
/// error text from the system); the sentence around it comes from the
/// `fetch.<kind>` message in the user's language.
class FetchFailure implements Exception {
  FetchFailure(this.kind, this.detail)
    : assert(fetchFailureKinds.contains(kind), 'unknown kind $kind');

  /// One of [fetchFailureKinds].
  final String kind;
  final String detail;

  @override
  String toString() => '$kind: $detail';
}

/// One published version as listed by `/api/packages/<name>`.
class HostedVersion {
  const HostedVersion(this.version, this.archiveUrl, this.retracted);

  final String version;
  final String? archiveUrl;
  final bool retracted;
}

/// Largest archive we are willing to download (bytes).
const int maxArchiveBytes = 64 * 1024 * 1024;

final RegExp _changelogName = RegExp(
  r'^(?:[^/]+/)?changelog(?:\.md|\.markdown|\.txt)?$',
  caseSensitive: false,
);

/// Minimal client for a pub hosted repository (pub.dev or a mirror).
///
/// It only reads the public API: package info and package archives.
class HostedClient {
  HostedClient({this.timeout = const Duration(seconds: 60)}) {
    _http =
        HttpClient()
          ..userAgent = 'pubdelta/$pubdeltaVersion'
          ..connectionTimeout = timeout;
  }

  final Duration timeout;
  late final HttpClient _http;

  /// Lists the published versions of [name] on [baseUrl].
  Future<List<HostedVersion>> versions(String baseUrl, String name) async {
    final uri = _parseUrl(
      '${_trim(baseUrl)}/api/packages/${Uri.encodeComponent(name)}',
    );
    final bytes = await _get(uri);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      throw FetchFailure('badJson', '$uri');
    }
    if (json is! Map || json['versions'] is! List) {
      throw FetchFailure('noVersions', '$uri');
    }
    final result = <HostedVersion>[];
    for (final v in json['versions'] as List<Object?>) {
      if (v is Map && v['version'] is String) {
        final archive = v['archive_url'];
        result.add(
          HostedVersion(
            v['version'] as String,
            // 문자열이 아닌 값(숫자·객체)이 와도 형 변환 오류로 죽지 않는다
            archive is String ? archive : null,
            v['retracted'] == true,
          ),
        );
      }
    }
    return result;
  }

  /// Downloads the archive at [archiveUrl] and returns its CHANGELOG text,
  /// decoded like a local file ([decodeText]).
  Future<TextFile> changelogFromArchive(String archiveUrl) async {
    final bytes = await _get(_parseUrl(archiveUrl));
    final List<int>? content;
    try {
      content = _findChangelog(bytes);
    } on ArchiveException catch (e) {
      throw FetchFailure('badArchive', '$archiveUrl: ${e.message}');
    } on FormatException catch (e) {
      throw FetchFailure('badArchive', '$archiveUrl: ${e.message}');
    } on RangeError catch (e) {
      // 잘린 아카이브는 범위 오류로 끝나기도 한다 — 버그가 아니라 받은 파일 문제
      throw FetchFailure('badArchive', '$archiveUrl: ${e.message}');
    }
    if (content == null) throw FetchFailure('noChangelog', archiveUrl);
    return decodeText(content);
  }

  List<int>? _findChangelog(List<int> bytes) {
    final tarBytes = GZipDecoder().decodeBytes(bytes);
    final archive = TarDecoder().decodeBytes(tarBytes);
    for (final file in archive.files) {
      if (file.isFile && _changelogName.hasMatch(file.name)) {
        return file.content as List<int>;
      }
    }
    return null;
  }

  Future<List<int>> _get(Uri uri) async {
    try {
      final request = await _http.getUrl(uri).timeout(timeout);
      request.headers.set('accept', 'application/vnd.pub.v2+json');
      final response = await request.close().timeout(timeout);
      if (response.statusCode == 404) {
        await response.drain<void>();
        throw FetchFailure('notFound', '$uri');
      }
      if (response.statusCode != 200) {
        await response.drain<void>();
        throw FetchFailure('http', 'HTTP ${response.statusCode}, $uri');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(timeout)) {
        builder.add(chunk);
        if (builder.length > maxArchiveBytes) {
          throw FetchFailure('tooLarge', '$uri');
        }
      }
      return builder.takeBytes();
    } on HandshakeException catch (e) {
      throw FetchFailure('tls', '${uri.host}: ${e.message}');
    } on TlsException catch (e) {
      throw FetchFailure('tls', '${uri.host}: ${e.message}');
    } on SocketException catch (e) {
      throw FetchFailure('connection', '${uri.host}:${uri.port}: ${e.message}');
    } on HttpException catch (e) {
      throw FetchFailure('connection', '$uri: ${e.message}');
    } on TimeoutException {
      throw FetchFailure('timeout', '$uri');
    } on ArgumentError {
      // HttpClient 는 호스트 없는 주소·http(s) 가 아닌 scheme 을 ArgumentError 로 거부한다
      throw FetchFailure('badUrl', '$uri');
    }
  }

  /// Releases sockets; call when done.
  void close() => _http.close(force: true);
}

/// Parses a repository or archive URL; a malformed one is a [FetchFailure]
/// (`badUrl`), not a crash.
Uri _parseUrl(String url) {
  try {
    return Uri.parse(url);
  } on FormatException {
    throw FetchFailure('badUrl', url);
  }
}

String _trim(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;
