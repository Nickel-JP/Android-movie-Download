enum SaveMode {
  video('動画'),
  mp3('MP3'),
  wav('WAV');

  const SaveMode(this.label);
  final String label;
}

class DownloadOptions {
  const DownloadOptions({
    this.mode = SaveMode.video,
    this.height = 2160,
    this.fps = 60,
    this.bitrate = 320,
    this.container = 'mp4',
  });
  final SaveMode mode;
  final int height;
  final int fps;
  final int bitrate;
  final String container;
  Map<String, Object> toMap(String url) => {
    'url': normalizeVideoUrl(url),
    'mode': mode.name,
    'height': height,
    'fps': fps,
    'bitrate': bitrate,
    'container': container,
  };
}

String normalizeVideoUrl(String text) {
  final trimmed = text.trim();
  final match = RegExp(
    r'https?://[^\s<>]+',
    caseSensitive: false,
  ).firstMatch(trimmed);
  final value =
      !RegExp(r'\s').hasMatch(trimmed) &&
          RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)
      ? trimmed
      : (match?.group(0) ?? trimmed).replaceFirst(RegExp(r'[)\]。、]+$'), '');
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
    throw const FormatException('HTTPまたはHTTPSのメディアURLを入力してください。');
  }
  // スキーム・ポート・クエリ・フラグメントは、サイト側が必要とする可能性があるため保持する。
  return uri.toString();
}

class DownloadTask {
  DownloadTask(Map<String, dynamic> data)
    : id = data['id'] as String,
      url = data['url'] as String? ?? '',
      title = data['title'] as String? ?? '動画',
      status = data['status'] as String? ?? 'queued',
      progress = (data['progress'] as num? ?? 0).toDouble(),
      message = data['message'] as String? ?? '',
      outputUri = data['outputUri'] as String?,
      mode = data['mode'] as String? ?? 'video';
  final String id;
  final String url;
  final String title;
  final String status;
  final double progress;
  final String message;
  final String? outputUri;
  final String mode;
  bool get active =>
      ['queued', 'running', 'processing', 'saving'].contains(status);
  String get statusLabel => switch (status) {
    'queued' => '待機中',
    'running' => 'ダウンロード中',
    'processing' => '結合・変換中',
    'saving' => '保存中',
    'completed' => '保存完了',
    'cancelled' => 'キャンセル',
    'interrupted' => '中断されました',
    _ => '失敗',
  };
}
