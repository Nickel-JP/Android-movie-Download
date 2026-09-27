import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'services/app_controller.dart';
import 'services/native_bridge.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    for (final entry in {
      'youtubedl-android': 'GPL-3.0.txt',
      'yt-dlp': 'yt-dlp.txt',
      'FFmpeg': 'FFmpeg.txt',
      'libwebp': 'libwebp.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/licenses/${entry.value}'));
    }
  });
  final controller = AppController(NativeBridge());
  runApp(DownloadApp(controller: controller));
  unawaited(controller.initialize());
}

class DownloadApp extends StatelessWidget {
  const DownloadApp({super.key, required this.controller});
  final AppController controller;

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff285be0),
          brightness: brightness,
          surface: dark ? const Color(0xff1b2029) : Colors.white,
        ).copyWith(
          primary: dark ? const Color(0xffa8bdff) : const Color(0xff285be0),
          secondaryContainer: dark
              ? const Color(0xff263650)
              : const Color(0xffeaf0ff),
          onSecondaryContainer: dark
              ? const Color(0xffd5e1ff)
              : const Color(0xff285be0),
          onSurface: dark ? const Color(0xffedf0f5) : const Color(0xff19212d),
          onSurfaceVariant: dark
              ? const Color(0xffa6b0c0)
              : const Color(0xff687588),
          outlineVariant: dark
              ? const Color(0xff323a47)
              : const Color(0xffe2e6ed),
        );
    return ThemeData(
      brightness: brightness,
      colorScheme: colors,
      useMaterial3: true,
      scaffoldBackgroundColor: dark
          ? const Color(0xff121720)
          : const Color(0xfff5f6f8),
      appBarTheme: AppBarTheme(
        backgroundColor: dark
            ? const Color(0xff121720)
            : const Color(0xfff5f6f8),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        filled: true,
        fillColor: colors.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xff285be0),
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.outlineVariant),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primary.withValues(alpha: 0.12),
        height: 72,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(fontSize: 12, color: colors.onSurface),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => MaterialApp(
      title: 'Android movie Download',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: controller.themeMode,
      home: HomeScreen(controller: controller),
    ),
  );
}
