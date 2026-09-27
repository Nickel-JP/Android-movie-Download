import 'package:flutter_test/flutter_test.dart';
import 'package:ytdlp_flutter/models/download.dart';

void main() {
  test('共有テキストから動画URLを取り込む', () {
    expect(
      normalizeVideoUrl('動画 https://youtu.be/abc?si=xyz を共有'),
      'https://youtu.be/abc?si=xyz',
    );
    expect(
      normalizeVideoUrl('http://www.nicovideo.jp/watch/sm9'),
      'https://www.nicovideo.jp/watch/sm9',
    );
  });
  test('偽装ドメインや認証情報付きURLを拒否する', () {
    for (final value in [
      'https://youtube.com.attacker.invalid/watch?v=x',
      'https://user:pass@youtube.com/watch?v=x',
      'file:///tmp/video',
      'https://localhost/video',
      'https://youtube.com:1234/watch?v=x',
    ]) {
      expect(() => normalizeVideoUrl(value), throwsFormatException);
    }
  });
}
