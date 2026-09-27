import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ytdlp_flutter/main.dart';
import 'package:ytdlp_flutter/screens/home_screen.dart';
import 'package:ytdlp_flutter/screens/update_dialog.dart';
import 'package:ytdlp_flutter/services/app_controller.dart';
import 'package:ytdlp_flutter/services/app_updater.dart';
import 'package:ytdlp_flutter/services/native_bridge.dart';

const _sampleNotes = '''
# Android movie Download 1.0.3

## 更新画面を見やすく

- **見出しと箇条書き**を読みやすく表示します。
- 長い更新内容をスクロールしても、更新ボタンを操作できます。
- ライト・ダーク表示に対応します。

## 互換性

- 設定と履歴は引き継がれます。
- Android 10以降のarm64端末向けです。

## 検証

- 小型画面と大きな文字での表示を確認しました。
''';

AppRelease _release(String notes) => AppRelease(
  version: '1.0.3',
  versionCode: 4,
  apkUrl: Uri.parse(
    'https://github.com/owner/app/releases/download/v1.0.3/app.apk',
  ),
  sha256sum: 'a' * 64,
  size: (71.4 * 1024 * 1024).round(),
  notes: notes,
);

Future<void> _openDialog(
  WidgetTester tester, {
  String notes = _sampleNotes,
  ThemeMode mode = ThemeMode.dark,
  Size size = const Size(393, 852),
  double textScale = 1,
  void Function(bool?)? onClosed,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = AppController(NativeBridge())
    ..ready = true
    ..appVersion = '1.0.2'
    ..themeMode = mode;
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    RepaintBoundary(
      key: const Key('updatePreview'),
      child: DownloadApp(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('設定'));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(HomeScreen));
  showDialog<bool>(
    context: context,
    builder: (_) =>
        UpdateDialog(release: _release(notes), currentVersion: '1.0.2'),
  ).then((result) => onClosed?.call(result));
  await tester.pumpAndSettle();
}

// 目視確認時だけ、実フォントによる画面を指定先へ出力する。
Future<void> _savePreview(WidgetTester tester, String name) async {
  final directory = Platform.environment['UPDATE_PREVIEW_DIR'];
  if (directory == null) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(const Key('updatePreview')),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final fontPath = Platform.environment['UPDATE_PREVIEW_FONT'];
    if (fontPath != null) {
      final bytes = await File(fontPath).readAsBytes();
      final font = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await font.load();
    }
    final iconFontPath = Platform.environment['UPDATE_PREVIEW_ICON_FONT'];
    if (iconFontPath != null) {
      final bytes = await File(iconFontPath).readAsBytes();
      final font = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await font.load();
    }
  });

  testWidgets('更新内容の見出し・箇条書き・強調を整形する', (tester) async {
    await _openDialog(tester);
    expect(find.text('更新画面を見やすく', findRichText: true), findsOneWidget);
    expect(find.text('1.0.2 → 1.0.3'), findsOneWidget);
    expect(find.text('71.4 MB'), findsOneWidget);
    final text = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');
    expect(text, contains('見出しと箇条書き'));
    expect(text, isNot(contains('##')));
    expect(text, isNot(contains('**')));
    expect(text, isNot(contains('# Android movie Download')));
    expect(tester.takeException(), isNull);
    await _savePreview(tester, 'update-dark');
  });

  testWidgets('長い更新内容をスクロールしても容量と操作ボタンは固定する', (tester) async {
    final notes = List.generate(
      40,
      (index) => '- 更新内容 $index を確認できます。',
    ).join('\n');
    await _openDialog(
      tester,
      notes: '## 長い更新内容\n\n$notes',
      size: const Size(360, 640),
    );
    final confirm = find.byKey(const Key('updateConfirm'));
    final capacity = find.byKey(const Key('updateDownloadSize'));
    final beforeButton = tester.getTopLeft(confirm);
    final beforeCapacity = tester.getTopLeft(capacity);
    await tester.drag(
      find.byKey(const Key('updateNotesScroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    final scroll = tester.widget<SingleChildScrollView>(
      find.byKey(const Key('updateNotesScroll')),
    );
    expect(scroll.controller!.offset, greaterThan(0));
    expect(tester.getTopLeft(confirm), beforeButton);
    expect(tester.getTopLeft(capacity), beforeCapacity);
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('小型画面・横向き・大きな文字と明暗テーマで操作できる', (tester) async {
    for (final size in [const Size(360, 640), const Size(640, 360)]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await _openDialog(tester, mode: mode, size: size, textScale: 1.6);
        expect(
          find.byKey(const Key('updateConfirm')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('updateLater')).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.tap(find.byKey(const Key('updateLater')));
        await tester.pumpAndSettle();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    }
    await _openDialog(tester, mode: ThemeMode.light);
    await _savePreview(tester, 'update-light');
  });

  testWidgets('更新内容が空でも説明を表示し、確認と延期の結果を返す', (tester) async {
    bool? result;
    await _openDialog(tester, notes: '', onClosed: (value) => result = value);
    expect(
      find.text('今回の更新に詳しい変更内容はありません。', findRichText: true),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('updateLater')));
    await tester.pumpAndSettle();
    expect(result, false);
    await tester.pumpWidget(const SizedBox.shrink());
    await _openDialog(tester, onClosed: (value) => result = value);
    await tester.tap(find.byKey(const Key('updateConfirm')));
    await tester.pumpAndSettle();
    expect(result, true);
  });
}
