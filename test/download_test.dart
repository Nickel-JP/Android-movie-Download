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
      'http://www.nicovideo.jp/watch/sm9',
    );
  });
  test('サイトを限定せずスキーム・ポート・クエリ・フラグメントを保持する', () {
    for (final value in [
      'https://vimeo.com/123456',
      'https://www.twitch.tv/videos/123456',
      'https://www.dailymotion.com/video/example',
      'https://example.org/video.mp4?token=abc#fragment',
      'http://localhost:8080/video.mp4',
      'http://127.0.0.1:1234/clip.mp4',
      'https://example.org/file(with-parentheses)',
    ]) {
      expect(normalizeVideoUrl(value), value);
    }
  });
  test('不正なURLや認証情報付きURLを拒否する', () {
    for (final value in [
      'https://user:pass@youtube.com/watch?v=x',
      'file:///tmp/video',
      'ftp://example.org/video',
      'https:///video',
      'https://example.org:0/video',
      'https://example.org:70000/video',
    ]) {
      expect(() => normalizeVideoUrl(value), throwsFormatException);
    }
  });
}
