import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ytdlp_flutter/main.dart';
import 'package:ytdlp_flutter/services/app_controller.dart';
import 'package:ytdlp_flutter/services/native_bridge.dart';

const _shorts = 'https://youtube.com/shorts/-WcGAdKTQGo?si=W9Kfp7wGwafNow9f';
const _methods = MethodChannel('jp.nogut.ytdlp/methods');
const _events = MethodChannel('jp.nogut.ytdlp/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic>? pending;
  List<MethodCall> calls = [];
  Map<String, dynamic> collection = {'kind': 'single', 'title': 'ショート動画'};

  setUpAll(() async {
    for (final entry in {
      'Roboto': Platform.environment['UPDATE_PREVIEW_FONT'],
      'MaterialIcons': Platform.environment['UPDATE_PREVIEW_ICON_FONT'],
    }.entries) {
      if (entry.value == null) continue;
      final bytes = await File(entry.value!).readAsBytes();
      final font = FontLoader(entry.key)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await font.load();
    }
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls = [];
    pending = null;
    collection = {'kind': 'single', 'title': 'ショート動画'};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_events, (_) async => null);
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      if (call.method == 'state') return {'tasks': [], ...?pending};
      if (call.method == 'inspectCollection') return collection;
      if (call.method == 'consumeShare' &&
          (call.arguments as Map)['shareId'] == pending?['shareId']) {
        pending = null;
      }
      return null;
    });
  });
  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(_methods, null);
    messenger.setMockMethodCallHandler(_events, null);
  });

  Future<AppController> open(
    WidgetTester tester, {
    bool initialize = true,
    ThemeMode mode = ThemeMode.dark,
    Size size = const Size(393, 852),
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final controller = AppController(NativeBridge())..themeMode = mode;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const Key('sharePreview'),
        child: DownloadApp(controller: controller),
      ),
    );
    if (initialize) await controller.initialize();
    controller.themeMode = mode;
    controller.notifyListeners();
    await tester.pumpAndSettle();
    return controller;
  }

  Future<void> preview(WidgetTester tester, String name) async {
    final directory = Platform.environment['UPDATE_PREVIEW_DIR'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const Key('sharePreview')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(directory).create(recursive: true);
        await File(
          '$directory/$name.png',
        ).writeAsBytes(data!.buffer.asUint8List());
      } finally {
        image.dispose();
      }
    });
  }

  testWidgets('起動時の共有は初期化後にURLを入力し、確認前は取得しない', (tester) async {
    pending = {'sharedUrl': 'ショート動画\n$_shorts', 'shareId': 'cold'};
    final controller = await open(tester, initialize: false);
    expect(find.text('ダウンロードしますか？'), findsNothing);
    await controller.initialize();
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('videoUrl')))
          .controller!
          .text,
      _shorts,
    );
    expect(controller.sharedUrlRevision, 1);
    expect(
      calls.any(
        (call) =>
            call.method == 'inspectCollection' || call.method == 'enqueue',
      ),
      false,
    );
    await tester.tap(find.byKey(const Key('shareDownload')));
    await tester.pumpAndSettle();
    final request =
        calls.singleWhere((call) => call.method == 'enqueue').arguments as Map;
    expect(request['url'], _shorts);
    expect(request['height'], 2160);
    expect(request['fps'], 60);
    expect(request['mode'], 'video');
    expect(find.text('ダウンロード履歴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('キャンセルは保存せずURLを残し、同じURLの再共有も確認する', (tester) async {
    final controller = await open(tester);
    pending = {'sharedUrl': _shorts, 'shareId': 'first'};
    await controller.refresh();
    await tester.pumpAndSettle();
    await preview(tester, 'share-dark');
    await tester.tap(find.byKey(const Key('shareCancel')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('videoUrl')))
          .controller!
          .text,
      _shorts,
    );
    expect(calls.any((call) => call.method == 'enqueue'), false);
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsNothing);
    pending = {'sharedUrl': _shorts, 'shareId': 'second'};
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsOneWidget);
    expect(controller.sharedUrlRevision, 2);
  });

  testWidgets('処理中の共有を保留し、保存形式の選択後に確認する', (tester) async {
    final controller = await open(tester);
    await tester.tap(find.text('MP3'));
    await tester.pumpAndSettle();
    final completion = Completer<void>();
    final busy = controller.run(() => completion.future);
    pending = {'sharedUrl': _shorts, 'shareId': 'busy'};
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsNothing);
    completion.complete();
    await busy;
    await tester.pumpAndSettle();
    expect(find.text('MP3 ・ 320 kbps'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shareDownload')));
    await tester.pumpAndSettle();
    final request =
        calls.singleWhere((call) => call.method == 'enqueue').arguments as Map;
    expect(request['mode'], 'mp3');
    expect(request['bitrate'], 320);
  });

  testWidgets('確認中の新しい共有を、前のURLへの承認だけで保存しない', (tester) async {
    final controller = await open(tester);
    pending = {'sharedUrl': _shorts, 'shareId': 'one'};
    await controller.refresh();
    await tester.pumpAndSettle();
    pending = {'sharedUrl': 'https://example.org/new.mp4', 'shareId': 'two'};
    await controller.refresh();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('shareDownload')));
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('https://example.org/new.mp4'),
      ),
      findsOneWidget,
    );
    expect(calls.any((call) => call.method == 'enqueue'), false);
  });

  testWidgets('他の画面を閉じるまで共有確認を待ち、共有リストは選択画面へ進む', (tester) async {
    final controller = await open(tester);
    await tester.tap(find.text('画質'));
    await tester.pumpAndSettle();
    pending = {'sharedUrl': 'https://example.org/list', 'shareId': 'list'};
    await controller.refresh();
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsNothing);
    await tester.tap(find.text('1080p'));
    await tester.pumpAndSettle();
    expect(find.text('ダウンロードしますか？'), findsOneWidget);
    collection = {
      'kind': 'playlist',
      'title': '共有リスト',
      'entries': [
        {
          'key': '1',
          'title': '動画1',
          'url': 'https://example.org/1.mp4',
          'available': true,
        },
      ],
      'offset': 0,
      'nextOffset': 1,
      'hasMore': false,
    };
    await tester.tap(find.byKey(const Key('shareDownload')));
    await tester.pumpAndSettle();
    expect(find.text('保存する動画を選択'), findsOneWidget);
    expect(find.text('選択した0件を保存'), findsOneWidget);
    expect(
      calls.any(
        (call) => call.method == 'enqueue' || call.method == 'enqueueMany',
      ),
      false,
    );
  });

  testWidgets('URLを含まない共有は確認・保存を行わず、再表示を防ぐ', (tester) async {
    pending = {'sharedUrl': '動画のタイトルだけ', 'shareId': 'invalid'};
    final controller = await open(tester);
    expect(find.text('ダウンロードしますか？'), findsNothing);
    expect(find.text('HTTPまたはHTTPSのメディアURLを入力してください。'), findsOneWidget);
    expect(calls.any((call) => call.method == 'enqueue'), false);
    expect(controller.sharedUrl, isNull);
  });

  testWidgets('明暗テーマ・小型画面・大きな文字でも共有確認を操作できる', (tester) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      pending = {'sharedUrl': _shorts, 'shareId': mode.name};
      await open(tester, mode: mode, size: const Size(360, 640), scale: 1.6);
      expect(
        find.byKey(const Key('shareDownload')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('shareCancel')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      if (mode == ThemeMode.light) await preview(tester, 'share-light-large');
      await tester.tap(find.byKey(const Key('shareCancel')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
