import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ytdlp_flutter/main.dart';
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
      find.text('GitHub：Nickel-JP/Android-movie-Download'),
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
    await tester.enterText(find.byType(TextField), 'https://youtu.be/example');
    await tester.tap(find.text('MP3'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('startDownload')));
    await tester.pumpAndSettle();
    expect(request?['mode'], 'mp3');
    expect(request?['bitrate'], 320);
    expect(request?['url'], 'https://youtu.be/example');
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
}
