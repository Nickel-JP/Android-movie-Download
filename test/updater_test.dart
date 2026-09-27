import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ytdlp_flutter/services/app_updater.dart';
import 'package:ytdlp_flutter/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const repository = 'owner/app';
  Map<String, dynamic> manifest() => {
    'schemaVersion': 1,
    'packageName': 'jp.nogut.ytdlp_flutter',
    'version': '1.1.0',
    'versionCode': 2,
    'size': 100,
    'sha256': List.filled(64, 'a').join(),
    'apkUrl': 'https://github.com/owner/app/releases/download/v1.1.0/app.apk',
    'notes': '更新内容',
  };
  test('整形用の更新内容を優先し、旧形式の更新情報も読める', () {
    final rich = AppRelease.parse(
      {...manifest(), 'notesMarkdown': '## 更新内容\n\n- 表示を改善'},
      repository,
      'v1.1.0',
    );
    expect(rich.notes, '## 更新内容\n\n- 表示を改善');
    final legacy = AppRelease.parse(manifest(), repository, 'v1.1.0');
    expect(legacy.notes, '更新内容');
    final invalidOptional = AppRelease.parse(
      {...manifest(), 'notesMarkdown': 123},
      repository,
      'v1.1.0',
    );
    expect(invalidOptional.notes, '更新内容');
  });
  test('別アプリ・配信元・検証情報が不正な更新を拒否する', () {
    for (final change in [
      {'packageName': 'other.application'},
      {'sha256': 'invalid'},
      {'apkUrl': 'https://attacker.invalid/app.apk'},
      {'versionCode': 0},
      {'size': 500 * 1024 * 1024},
    ]) {
      expect(
        () =>
            AppRelease.parse({...manifest(), ...change}, repository, 'v1.1.0'),
        throwsFormatException,
      );
    }
  });
  test('GitHub最新リリースを確認し、versionCodeで更新を判定する', () async {
    final updater = AppUpdater(
      NativeBridge(),
      client: MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response(
            jsonEncode({
              'tag_name': 'v1.1.0',
              'draft': false,
              'prerelease': false,
              'assets': [
                {
                  'name': 'update.json',
                  'browser_download_url':
                      'https://github.com/owner/app/releases/download/v1.1.0/update.json',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(manifest()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    addTearDown(updater.close);
    expect((await updater.check(repository, 1))?.versionCode, 2);
    expect(await updater.check(repository, 2), isNull);
    expect(await updater.check(repository, 3), isNull);
  });
  test('HTTPSからHTTPへの転送を拒否する', () async {
    final updater = AppUpdater(
      NativeBridge(),
      client: MockClient(
        (_) async => http.Response(
          '',
          302,
          headers: {'location': 'http://github.com/owner/app'},
        ),
      ),
    );
    addTearDown(updater.close);
    await expectLater(updater.check(repository, 1), throwsFormatException);
  });
  test('取得したAPKのハッシュを検証し、破損したファイルを削除する', () async {
    final temporary = await Directory.systemTemp.createTemp('amd-update-test-');
    addTearDown(() async => temporary.delete(recursive: true));
    const channel = MethodChannel('jp.nogut.ytdlp/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => temporary.path);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final data = utf8.encode('APKテストデータ');
    final release = AppRelease.parse(
      {
        ...manifest(),
        'size': data.length,
        'sha256': sha256.convert(data).toString(),
      },
      repository,
      'v1.1.0',
    );
    final valid = AppUpdater(
      NativeBridge(),
      client: MockClient((_) async => http.Response.bytes(data, 200)),
    );
    addTearDown(valid.close);
    final path = await valid.download(release, (_) {});
    expect(await File(path).readAsBytes(), data);
    final corrupted = AppUpdater(
      NativeBridge(),
      client: MockClient(
        (_) async => http.Response.bytes(List.filled(data.length, 0), 200),
      ),
    );
    addTearDown(corrupted.close);
    await expectLater(
      corrupted.download(release, (_) {}),
      throwsFormatException,
    );
    expect(await File(path).exists(), isFalse);
  });
}
