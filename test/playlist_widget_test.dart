import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytdlp_flutter/main.dart';
import 'package:ytdlp_flutter/models/download.dart';
import 'package:ytdlp_flutter/models/media_list.dart';
import 'package:ytdlp_flutter/screens/playlist_screen.dart';
import 'package:ytdlp_flutter/services/app_controller.dart';
import 'package:ytdlp_flutter/services/native_bridge.dart';

Map<String, dynamic> page({bool more = false, int offset = 0}) => {
  'kind': 'playlist',
  'title': 'テストリスト',
  'hasMore': more,
  'nextOffset': offset + 2,
  'maximum': 1000,
  'entries': List.generate(
    2,
    (i) => {
      'key': '${offset + i + 1}',
      'title': '動画${offset + i + 1}',
      'index': offset + i + 1,
      'url': 'https://example.org/${offset + i + 1}.mp4',
      'available': true,
    },
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('jp.nogut.ytdlp/methods');
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  testWidgets('左チェックボックスで個別選択・個別解除・全選択・全解除できる', (tester) async {
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistScreen(
          controller: controller,
          url: 'https://example.org/list',
          initialPage: MediaListPage(page()),
          options: const DownloadOptions(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('選択した0件を保存'), findsOneWidget);
    final tile = find.byKey(const ValueKey('playlistEntry:1'));
    final check = find.descendant(of: tile, matching: find.byType(Checkbox));
    expect(tester.getCenter(check).dx, lessThan(tester.getCenter(tile).dx));
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('選択した1件を保存'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('選択した0件を保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('playlistSelectAll')));
    await tester.pumpAndSettle();
    expect(find.text('選択した2件を保存'), findsOneWidget);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('選択した1件を保存'), findsOneWidget);
    await tester.tap(find.byKey(const Key('playlistClearAll')));
    await tester.pumpAndSettle();
    expect(find.text('選択した0件を保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全選択は続きも取得し、選択した項目だけを保存キューに送る', (tester) async {
    List<dynamic>? sent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'inspectCollection') return page(offset: 2);
          if (call.method == 'enqueueMany') {
            sent = (call.arguments as Map)['items'] as List;
          }
          if (call.method == 'state') return {'tasks': []};
          return null;
        });
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlaylistScreen(
          controller: controller,
          url: 'https://example.org/list',
          initialPage: MediaListPage(page(more: true)),
          options: const DownloadOptions(mode: SaveMode.mp3),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlistSelectAll')));
    await tester.pumpAndSettle();
    expect(find.text('選択した4件を保存'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('playlistEntry:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('playlistSaveSelected')));
    await tester.pumpAndSettle();
    expect(sent!.length, 3);
    expect(sent!.map((entry) => (entry as Map)['url']), [
      'https://example.org/1.mp4',
      'https://example.org/3.mp4',
      'https://example.org/4.mp4',
    ]);
    expect(sent!.every((entry) => (entry as Map)['mode'] == 'mp3'), isTrue);
  });

  testWidgets('リストURLの確認から一覧画面へ進み、保存前は未選択で表示する', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'inspectCollection' ? page() : null,
        );
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(DownloadApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('videoUrl')),
      'https://example.org/list',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('URL・リストを確認'));
    await tester.pumpAndSettle();
    expect(find.text('保存する動画を選択'), findsOneWidget);
    expect(find.text('選択した0件を保存'), findsOneWidget);
    expect(find.byType(Checkbox), findsNWidgets(2));
  });
}
