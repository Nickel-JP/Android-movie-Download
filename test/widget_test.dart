import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytdlp_flutter/main.dart';
import 'package:ytdlp_flutter/models/download.dart';
import 'package:ytdlp_flutter/services/app_controller.dart';
import 'package:ytdlp_flutter/services/native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('保存画面と設定画面が小型端末で表示できる', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(DownloadApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('新しいダウンロード'), findsOneWidget);
    expect(find.text('4K（2160p）'), findsOneWidget);
    expect(find.byKey(const Key('startDownload')), findsOneWidget);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    expect(find.text('アップデートを確認'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('詳細設定'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('詳細設定'));
    await tester.pumpAndSettle();
    expect(
      find.text('https://github.com/Nickel-JP/Android-movie-Download'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('共有されたURLとMP3の保存要求がAndroid連携へ渡る', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<dynamic, dynamic>? request;
    const channel = MethodChannel('jp.nogut.ytdlp/methods');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'enqueue') request = call.arguments as Map;
          if (call.method == 'state') return {'tasks': []};
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    await tester.pumpWidget(DownloadApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'http://example.org:8080/audio.mp3?token=abc',
    );
    await tester.tap(find.text('MP3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startDownload')));
    await tester.pumpAndSettle();
    expect(request?['mode'], 'mp3');
    expect(request?['bitrate'], 320);
    expect(request?['url'], 'http://example.org:8080/audio.mp3?token=abc');
    expect(find.text('ダウンロード履歴'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('大きな文字・明暗テーマ・キーボード表示でも開始ボタンを操作できる', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = AppController(NativeBridge())..ready = true;
    addTearDown(controller.dispose);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await controller.setThemeMode(mode);
      await tester.pumpWidget(DownloadApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.enterText(
        find.byType(TextField),
        'https://youtu.be/example',
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      final button = find.byKey(const Key('startDownload'));
      expect(button.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      tester.view.resetViewInsets();
    }
    addTearDown(tester.view.resetViewInsets);
  });

  testWidgets('失敗した履歴のエラー全文を開き明示操作でコピーできる', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final message = [
      'Input #0, mov,mp4: ダウンロードした動画',
      ...List.generate(30, (index) => '検査ログ $index'),
      '最終原因: 動画の読み取りに失敗しました。',
    ].join('\n');
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final controller = AppController(NativeBridge())
      ..ready = true
      ..tasks = [
        DownloadTask({
          'id': 'failed-task',
          'title': '動画の検査',
          'status': 'failed',
          'message': message,
        }),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(DownloadApp(controller: controller));
    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('errorDetailsText')), findsNothing);
    expect(tester.widget<Text>(find.text(message)).maxLines, 3);
    expect(copiedText, isNull);

    await tester.tap(find.text('エラー詳細'));
    await tester.pumpAndSettle();
    final details = tester.widget<SelectableText>(
      find.byKey(const Key('errorDetailsText')),
    );
    expect(details.data, message);
    expect(details.maxLines, isNull);
    expect(copiedText, isNull);
    final scrollable = find
        .descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Scrollable),
        )
        .first;
    final scrollState = tester.state<ScrollableState>(scrollable);
    expect(scrollState.position.maxScrollExtent, greaterThan(0));
    scrollState.position.jumpTo(scrollState.position.maxScrollExtent);
    await tester.pumpAndSettle();
    expect(find.text('コピー').hitTestable(), findsOneWidget);
    await tester.tap(find.text('コピー'));
    await tester.pumpAndSettle();
    expect(copiedText, message);
    expect(find.text('コピーしました'), findsOneWidget);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('中断エラーの詳細は小型画面と大きい文字でも閉じられる', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final message = List.filled(30, '中断の詳細: 処理を続けられませんでした。').join('\n');
    final controller = AppController(NativeBridge())
      ..ready = true
      ..tasks = [
        DownloadTask({
          'id': 'interrupted-task',
          'title': '中断された動画',
          'status': 'interrupted',
          'message': message,
        }),
      ];
    addTearDown(controller.dispose);
    await tester.pumpWidget(DownloadApp(controller: controller));
    await tester.tap(find.text('履歴'));
    await tester.pumpAndSettle();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('エラー詳細'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    // ensureVisible によるスクロール位置を描画へ反映してから操作する。
    await tester.pumpAndSettle();
    expect(find.text('エラー詳細').hitTestable(), findsOneWidget);
    await tester.tap(find.text('エラー詳細'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SelectableText>(find.byKey(const Key('errorDetailsText')))
          .data,
      message,
    );
    expect(find.text('閉じる').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('閉じる'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
