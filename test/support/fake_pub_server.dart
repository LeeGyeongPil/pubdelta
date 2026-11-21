import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// One published version on the fake repository.
class FakeVersion {
  const FakeVersion(
    this.version, {
    this.changelog,
    this.changelogBytes,
    this.retracted = false,
  });

  final String version;

  /// CHANGELOG.md content inside the archive; null means no such file.
  final String? changelog;

  /// Raw CHANGELOG.md bytes (e.g. Latin-1); used instead of [changelog].
  final List<int>? changelogBytes;
  final bool retracted;
}

/// A tiny pub hosted repository on 127.0.0.1 (practice mock for tests).
///
/// Serves `/api/packages/<name>`, `/api/archives/<name>-<version>.tar.gz` and
/// answers 404 for `/api/packages/<name>/advisories`, like pub.dev does for
/// packages without advisories.
class FakePubServer {
  FakePubServer._(this._server, this.packages);

  final HttpServer _server;
  final Map<String, List<FakeVersion>> packages;

  /// Every request path seen so far.
  final List<String> requests = [];

  String get url => 'http://127.0.0.1:${_server.port}';

  static Future<FakePubServer> start(
    Map<String, List<FakeVersion>> packages,
  ) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakePubServer._(server, packages);
    server.listen(fake._handle);
    return fake;
  }

  Future<void> close() => _server.close(force: true);

  Map<String, Object?> _versionJson(String name, FakeVersion v) => {
    'version': v.version,
    'retracted': v.retracted,
    'archive_url':
        '$url/api/archives/$name-${Uri.encodeComponent(v.version)}.tar.gz',
    'pubspec': {
      'name': name,
      'version': v.version,
      'environment': {'sdk': '^3.0.0'},
    },
  };

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    requests.add(path);
    final response = request.response;

    final api = RegExp(r'^/api/packages/([^/]+)$').firstMatch(path);
    if (api != null && packages.containsKey(api[1])) {
      final name = api[1]!;
      final versions = packages[name]!;
      final body = jsonEncode({
        'name': name,
        'latest': _versionJson(name, versions.last),
        'versions': [for (final v in versions) _versionJson(name, v)],
      });
      response.headers.contentType = ContentType(
        'application',
        'vnd.pub.v2+json',
      );
      response.write(body);
      await response.close();
      return;
    }

    // `request.uri.path` is still percent-encoded: `+` arrives as `%2B`.
    final archive = RegExp(
      r'^/api/archives/([^/-]+)-(.+)\.tar\.gz$',
    ).firstMatch(Uri.decodeComponent(path));
    if (archive != null && packages.containsKey(archive[1])) {
      final match =
          packages[archive[1]]!.where((v) => v.version == archive[2]).toList();
      if (match.isNotEmpty) {
        final bytes = _tarGz(match.first);
        response.headers.contentType = ContentType.binary;
        response.add(bytes);
        await response.close();
        return;
      }
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  List<int> _tarGz(FakeVersion v) {
    final archive = Archive();
    final pubspec = utf8.encode('name: fake\nversion: ${v.version}\n');
    archive.addFile(ArchiveFile('pubspec.yaml', pubspec.length, pubspec));
    if (v.changelogBytes != null || v.changelog != null) {
      final bytes = v.changelogBytes ?? utf8.encode(v.changelog!);
      archive.addFile(ArchiveFile('CHANGELOG.md', bytes.length, bytes));
    }
    final tar = TarEncoder().encodeBytes(archive);
    return GZipEncoder().encodeBytes(tar);
  }
}
