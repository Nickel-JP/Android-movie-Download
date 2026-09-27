import 'package:flutter/services.dart';

class NativeBridge {
  static const _methods = MethodChannel('jp.nogut.ytdlp/methods');
  static const _events = EventChannel('jp.nogut.ytdlp/events');
  Stream<Map<String, dynamic>> get events => _events
      .receiveBroadcastStream()
      .map((event) => Map<String, dynamic>.from(event as Map));
  Future<T?> call<T>(String method, [Map<String, Object?>? args]) =>
      _methods.invokeMethod<T>(method, args);
  Future<Map<String, dynamic>> state() async =>
      Map<String, dynamic>.from((await call<Map>('state')) ?? {});
}
