# 第三者ライブラリ

| ライブラリ | 用途 | 参照元 |
|---|---|---|
| Flutter | 画面とDart実行環境 | https://github.com/flutter/flutter |
| youtubedl-android 0.18.1 | Android版Python・yt-dlp・QuickJSの導入 | https://github.com/yausername/youtubedl-android/tree/0.18.1 |
| 同プロジェクトのFFmpegモジュール | 映像・音声の結合、変換 | https://github.com/yausername/youtubedl-android/blob/0.18.1/BUILD_FFMPEG.md |
| yt-dlp 2026.08.19（同梱版） | 動画取得 | https://github.com/yt-dlp/yt-dlp/tree/2026.08.19 |
| FFmpeg | メディア処理 | https://github.com/FFmpeg/FFmpeg |
| Termux packages | ネイティブ実行環境のビルド元 | https://github.com/termux/termux-packages |
| libwebp 1.6.0 | Android 15のネイティブ互換性への対応 | https://github.com/webmproject/libwebp/tree/4fa21912338357f89e4fd51cf2368325b59e9bd9 |
| http・crypto・shared_preferences | 通信、更新検証、設定保存 | https://pub.dev/ |
| flutter_markdown_plus 1.0.12・markdown 7.3.1 | 更新内容の見出し・箇条書き・強調表示 | https://github.com/foresightmobile/flutter_markdown_plus |

バージョンは`pubspec.lock`とAndroidのGradle設定で固定しています。youtubedl-android 0.18.1は上流でプレリリースとして扱われているため、このアプリの検証結果を基準に採用しています。

アプリ内ではFlutterの登録済みライブラリに加え、youtubedl-android・yt-dlp・FFmpegのライセンスを表示します。Python・QuickJSやFFmpegの依存部品は同梱配布物のライセンスにも従います。
