# Android movie Download

Flutterで作成した、yt-dlp対応サイトの動画・音声を保存するAndroid向けダウンローダーです。

## 機能

- URL入力・Android共有先からの取り込みと「ダウンロードしますか？」の確認
- YouTube ShortsのURLと共有パラメーターに対応
- プレイリスト・ミックスの一覧表示、左チェックボックス、全選択・全解除・個別選択と解除
- サイトを限定せず、HTTP／HTTPSのURLをyt-dlpで解析。直接の動画・音声URLにも対応
- 配信品質の範囲内で、最大4K／60fpsの動画をMP4またはMKVで保存
- MP3は128／192／256／320kbps、WAVは非圧縮PCMで保存
- 進捗通知、バックグラウンド処理、キャンセル、再試行、履歴
- 保存先は `Download/Android movie Download`
- 画面下に固定した開始ボタン、履歴の絞り込み、ライト・ダーク表示
- Netscape形式のCookieファイル取り込み
- アプリ内からyt-dlpを更新
- GitHub Releasesからアプリ更新を確認し、Androidのインストール確認画面を開く
- 更新内容の見出し・箇条書き表示、スクロール中も操作できる更新ボタン

4K／60fpsは元動画の配信品質が上限です。MP3 320kbpsやWAVへの変換で元音源以上の音質にはなりません。動画形式は再圧縮せずに変更するため、再生には保存されたコーデックに対応するプレーヤーが必要です。

## 対応環境

画面例：[ライト表示](docs/images/light.png) / [ダーク表示](docs/images/dark.png)。UI設計は [設計記録](docs/DESIGN.md) を参照してください。

- Android 10以降、arm64端末向けの配布APK
- ユーザー指定端末：A301SH・Android 15（実機は未接続）
- Flutter 3.47.5／Dart 3.13.4、Java 17、Android SDK 36
- 配布ビルドにはNDK 28.2.13676358・CMake 3.22.1・Pythonも使用
- プロジェクト：`D:\Codex\ytdlp_flutter`
- 開発ツール：`D:\Tools\YtDlpFlutter`

対応サイトはアプリ内のyt-dlpの版に従います。[yt-dlpの対応サイト](https://github.com/yt-dlp/yt-dlp/blob/master/supportedsites.md) を参照してください。取得可否はサイト側のアクセス制限・ログイン状態・仕様変更にも依存します。Cookieはサイトを限定せず取り込めます。

プレイリスト・ミックスURLは「URL・リストを確認」から一覧を開き、保存したい項目を選択できます。リストと待機中のキューは最大1000件です。現在配信中のライブ動画は対象外です。認証情報を直接埋め込んだURLや、HTTP／HTTPS以外のスキームは受け付けません。

## インストールと更新

動画アプリやブラウザーの「共有」で **Android movie Download** を選ぶと、URLを入力して「ダウンロードしますか？」と表示します。確認すると現在の保存形式・画質で保存を開始します。キャンセル後もURLは残るため、設定を変更して保存できます。共有されたリストは動画の選択画面へ進みます。

共有確認の表示例：[ダーク](docs/images/share-dark.png) / [大きな文字・ライト](docs/images/share-light-large.png)。Android標準の共有先に登録していますが、送信元アプリ独自の共有メニューでの表示順は送信元に従います。

初回はGitHub Releasesのarm64版APKを端末にダウンロードし、Androidの確認画面からインストールします。

以降はアプリの「設定」→「アップデートを確認」から更新できます。変更内容の確認後に更新ファイルを取得し、検証後にAndroidのインストール確認画面を開きます。初回の更新時は、このアプリからのインストール許可が必要です。同じ署名の新しいバージョンで上書きするため、設定と履歴は保持されます。

更新画面の表示例：[ライト](docs/images/update-light.png) / [ダーク](docs/images/update-dark.png)。1.0.3より前のアプリから更新する際は、旧版のレイアウトで記号を除いた更新内容を表示します。

更新配信先は `Nickel-JP/Android-movie-Download` です。yt-dlpだけの更新にはアプリ本体の再インストールは不要です。

## 開発・ビルド

```powershell
Set-Location D:\Codex\ytdlp_flutter
. .\scripts\Use-Toolchain.ps1
flutter pub get
flutter analyze
flutter test
flutter build apk --debug --target-platform android-x64
```

署名済み配布版の作成：

```powershell
.\scripts\Build-Release.ps1 -Version 1.0.4 -BuildNumber 5
```

`dist/` にAPKと `update.json` を生成します。ローカルの `android/key.properties` が必要です。署名設定とキーはGitの管理対象から除外しています。

次のバージョンでは `Version` と `BuildNumber` を増やし、同じ署名設定でビルドしてください。`docs/release-notes/v<Version>.md` に変更内容、互換性、検証結果を記載し、APKと更新情報を同じGitHub Releaseに添付します。

```powershell
.\scripts\Publish-Release.ps1 -Version 1.0.4
```

更新情報のバージョン・容量・ハッシュは実際のAPKと照合します。APKの署名・パッケージ名・バージョンはインストール前にも確認します。

## 構成

- `lib/`：Flutter画面、状態管理、GitHub更新処理
- `android/app/src/main/kotlin/`：yt-dlp連携、バックグラウンド処理、保存、インストール連携
- `test/`：URL・更新情報・更新ファイル・画面操作のテスト
- `android/app/src/test/`：画質・fps上限のテスト
- `scripts/`：署名済みAPK、更新情報、GitHub Releaseの作成

## 検証結果

最新の結果と未検証事項は [検証記録](docs/VALIDATION.md) を参照してください。A301SH実機と16KBページサイズ環境での動作は未検証です。

## ライセンス

このプロジェクトはGPL-3.0で提供します。主要な依存ライブラリのライセンスはアプリ内と `assets/licenses/` に含めています。参照元は [第三者ライブラリ](docs/THIRD_PARTY.md) に記載しています。
