import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'native_bridge.dart';

class AppRelease {
  const AppRelease({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.sha256sum,
    required this.size,
    required this.notes,
  });
  final String version;
  final int versionCode;
  final Uri apkUrl;
  final String sha256sum;
  final int size;
  final String notes;

  static AppRelease parse(
    Map<String, dynamic> json,
    String repository,
    String tag,
  ) {
    if (json['packageName'] != 'jp.nogut.ytdlp_flutter' ||
        json['schemaVersion'] != 1) {
      throw const FormatException('このアプリ用の更新情報ではありません。');
    }
    final code = json['versionCode'];
    final size = json['size'];
    final hash = json['sha256'];
    final url = Uri.tryParse(json['apkUrl'] as String? ?? '');
    final expectedPrefix =
        'https://github.com/$repository/releases/download/$tag/';
    if (code is! int ||
        code < 1 ||
        size is! int ||
        size < 1 ||
        size > 400 * 1024 * 1024 ||
        hash is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(hash) ||
        url == null ||
        !url.toString().startsWith(expectedPrefix) ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasQuery ||
        url.hasFragment) {
      throw const FormatException('更新情報の形式を確認できません。');
    }
    return AppRelease(
      version: json['version'] as String? ?? tag,
      versionCode: code,
      apkUrl: url,
      sha256sum: hash.toLowerCase(),
      size: size,
      // 旧版用の本文を残した配信情報でも、整形用の更新内容を優先する。
      notes: json['notesMarkdown'] is String
          ? json['notesMarkdown'] as String
          : json['notes'] as String? ?? '',
    );
  }
}

class AppUpdater {
  AppUpdater(this.bridge, {http.Client? client})
    : _client = client ?? http.Client();
  final NativeBridge bridge;
  final http.Client _client;
  static const _allowedHosts = {
    'api.github.com',
    'github.com',
    'release-assets.githubusercontent.com',
    'objects.githubusercontent.com',
  };

  Future<http.StreamedResponse> _get(Uri uri) async {
    for (var hop = 0; hop < 6; hop++) {
      if (uri.scheme != 'https' ||
          !_allowedHosts.contains(uri.host) ||
          uri.userInfo.isNotEmpty ||
          uri.hasPort) {
        throw const FormatException('更新ファイルの接続先が不正です。');
      }
      final request = http.Request('GET', uri)..followRedirects = false;
      request.headers['User-Agent'] = 'Android-movie-Download';
      final response = await _client
          .send(request)
          .timeout(const Duration(seconds: 30));
      if ([301, 302, 303, 307, 308].contains(response.statusCode)) {
        final location = response.headers['location'];
        await response.stream.drain<void>().timeout(
          const Duration(seconds: 30),
        );
        if (location == null) throw const HttpException('更新先の転送情報がありません。');
        uri = uri.resolve(location);
        continue;
      }
      if (response.statusCode == 404) {
        await response.stream.drain<void>();
        throw const HttpException('公開済みの更新リリースが見つかりません。');
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw HttpException('更新を確認できませんでした（HTTP ${response.statusCode}）。');
      }
      return response;
    }
    throw const HttpException('更新先の転送回数が多すぎます。');
  }

  Future<Map<String, dynamic>> _json(Uri uri) async {
    final response = await _get(uri);
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 30),
    )) {
      if (bytes.length + chunk.length > 1024 * 1024) {
        throw const FormatException('更新情報の容量が大きすぎます。');
      }
      bytes.addAll(chunk);
    }
    return Map<String, dynamic>.from(jsonDecode(utf8.decode(bytes)) as Map);
  }

  Future<AppRelease?> check(String repository, int currentCode) async {
    if (!RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$',
    ).hasMatch(repository)) {
      throw const FormatException('設定でGitHubの更新配信先を入力してください。');
    }
    final release = await _json(
      Uri.https('api.github.com', '/repos/$repository/releases/latest'),
    );
    final tag = release['tag_name'] as String;
    if (!RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(tag) ||
        release['draft'] == true ||
        release['prerelease'] == true) {
      throw const FormatException('正式な更新リリースではありません。');
    }
    final assets = (release['assets'] as List).cast<Map<String, dynamic>>();
    final manifests = assets.where((asset) => asset['name'] == 'update.json');
    if (manifests.length != 1) {
      throw const FormatException('update.jsonが見つかりません。');
    }
    final manifestUrl = Uri.parse(
      manifests.single['browser_download_url'] as String,
    );
    if (manifestUrl.toString() !=
        'https://github.com/$repository/releases/download/$tag/update.json') {
      throw const FormatException('更新情報の配信元を確認できません。');
    }
    final parsed = AppRelease.parse(await _json(manifestUrl), repository, tag);
    return parsed.versionCode > currentCode ? parsed : null;
  }

  Future<String> download(
    AppRelease release,
    void Function(double) onProgress,
  ) async {
    final directory = await bridge.call<String>('updateDirectory');
    if (directory == null) throw const FileSystemException('更新用フォルダーを作成できません。');
    final file = File('$directory/update-${release.versionCode}.apk');
    final sink = file.openWrite();
    final digestResult = _DigestSink();
    final digest = sha256.startChunkedConversion(digestResult);
    var received = 0;
    try {
      final response = await _get(release.apkUrl);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        received += chunk.length;
        if (received > release.size) {
          throw const FormatException('更新ファイルの容量が一致しません。');
        }
        digest.add(chunk);
        sink.add(chunk);
        onProgress(received / release.size);
      }
      digest.close();
      await sink.flush();
      await sink.close();
      if (received != release.size ||
          digestResult.value.toString() != release.sha256sum) {
        throw const FormatException('更新ファイルの検証に失敗しました。再度確認してください。');
      }
      return file.path;
    } catch (_) {
      await sink.close();
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  void close() => _client.close();
}

class _DigestSink implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest data) => value = data;
  @override
  void close() {}
}
