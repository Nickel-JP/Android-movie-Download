import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/download.dart';
import 'native_bridge.dart';

class AppController extends ChangeNotifier {
  AppController(this.bridge);
  final NativeBridge bridge;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  SharedPreferences? _preferences;
  List<DownloadTask> tasks = [];
  String engineVersion = '準備中';
  String appVersion = '1.0.0';
  int versionCode = 1;
  String repository = const String.fromEnvironment(
    'UPDATE_REPOSITORY',
    defaultValue: 'Nickel-JP/Android-movie-Download',
  );
  String? sharedUrl;
  int sharedUrlRevision = 0;
  String? error;
  bool busy = false;
  bool ready = false;
  bool hasCookies = false;
  ThemeMode themeMode = ThemeMode.system;

  Future<void> initialize() async {
    try {
      _preferences = await SharedPreferences.getInstance();
      repository = _preferences!.getString('repository') ?? repository;
      final themeIndex =
          _preferences!.getInt('themeMode') ?? ThemeMode.system.index;
      themeMode =
          ThemeMode.values[themeIndex.clamp(0, ThemeMode.values.length - 1)];
      _subscription = bridge.events.listen(
        (event) {
          if (event['type'] == 'share') {
            sharedUrl = event['url'] as String?;
            sharedUrlRevision++;
            notifyListeners();
          } else {
            _applyState(event);
          }
        },
        onError: (Object e) {
          error = readableError(e);
          notifyListeners();
        },
      );
      _applyState(await bridge.state());
      await bridge.call('initialize');
      await refresh();
      ready = true;
    } catch (e) {
      error = readableError(e);
    }
    notifyListeners();
  }

  void _applyState(Map<String, dynamic> state) {
    if (state['tasks'] is List) {
      tasks = (state['tasks'] as List)
          .map((data) => DownloadTask(Map<String, dynamic>.from(data as Map)))
          .toList()
          .reversed
          .toList();
    }
    engineVersion = state['engineVersion'] as String? ?? engineVersion;
    appVersion = state['appVersion'] as String? ?? appVersion;
    versionCode = state['versionCode'] as int? ?? versionCode;
    hasCookies = state['hasCookies'] as bool? ?? hasCookies;
    final incoming = state['sharedUrl'] as String?;
    if (incoming != null && incoming.isNotEmpty && incoming != sharedUrl) {
      sharedUrl = incoming;
      sharedUrlRevision++;
    }
    notifyListeners();
  }

  Future<void> refresh() async => _applyState(await bridge.state());
  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    error = null;
    notifyListeners();
    try {
      await operation();
    } catch (e) {
      error = readableError(e);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> download(String url, DownloadOptions options) => run(() async {
    await bridge.call('enqueue', options.toMap(url));
    await refresh();
  });
  Future<void> cancel(String id) => run(() async {
    await bridge.call('cancel', {'id': id});
    await refresh();
  });
  Future<void> retry(String id) => run(() async {
    await bridge.call('retry', {'id': id});
    await refresh();
  });
  Future<void> saveRepository(String value) async {
    final normalized = value
        .trim()
        .replaceFirst(RegExp(r'^https://github\.com/'), '')
        .replaceFirst(RegExp(r'/$'), '');
    if (!RegExp(
      r'^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$',
    ).hasMatch(normalized)) {
      throw const FormatException('GitHubのowner/repository形式で入力してください。');
    }
    await _preferences?.setString('repository', normalized);
    repository = normalized;
    notifyListeners();
  }

  static String readableError(Object e) {
    if (e is FormatException) return e.message;
    if (e is PlatformException) return e.message ?? '操作を完了できませんでした。';
    return e.toString().replaceFirst(RegExp(r'^Exception: '), '');
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _preferences?.setInt('themeMode', mode.index);
    themeMode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
