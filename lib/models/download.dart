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
  final match = RegExp(r'https?://[^\s<>]+').firstMatch(text.trim());
  final value = (match?.group(0) ?? text.trim()).replaceFirst(
    RegExp(r'[)\]。、]+$'),
    '',
  );
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443 && uri.port != 80)) {
    throw const FormatException('YouTubeまたはニコニコ動画のURLを入力してください。');
  }
  const roots = ['youtube.com', 'youtu.be', 'nicovideo.jp', 'nico.ms'];
  if (!roots.any(
    (root) =>
        uri.host.toLowerCase() == root ||
        uri.host.toLowerCase().endsWith('.$root'),
  )) {
    throw const FormatException('対応サイトはYouTubeとニコニコ動画です。');
  }
  return uri.replace(scheme: 'https', port: 443).removeFragment().toString();
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
