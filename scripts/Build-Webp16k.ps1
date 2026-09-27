param([string]$ToolchainRoot = 'D:\Tools\YtDlpFlutter')
$ErrorActionPreference = 'Stop'
$taskSource = Join-Path $ToolchainRoot 'native-sources\libwebp'
$taskBuild = Join-Path $ToolchainRoot 'native-build\webp-arm64'
$taskSdk = Join-Path $ToolchainRoot 'android-sdk'
$taskCmake = Join-Path $taskSdk 'cmake\3.22.1\bin\cmake.exe'
$taskNdk = Join-Path $taskSdk 'ndk\28.2.13676358'
if (-not (Test-Path -LiteralPath $taskSource)) {
    git clone --depth 1 --branch v1.6.0 https://github.com/webmproject/libwebp.git $taskSource
    if ($LASTEXITCODE -ne 0) { throw 'libwebpの取得に失敗しました。' }
}
$taskRevision = git -C $taskSource rev-parse HEAD
if ($taskRevision -ne '4fa21912338357f89e4fd51cf2368325b59e9bd9') { throw 'libwebpのソース版が一致しません。' }
if (git -C $taskSource status --porcelain) { throw 'libwebpのソースに未検証の変更があります。' }
$taskOptions = @('-S',$taskSource,'-B',$taskBuild,'-G','Ninja',
    "-DCMAKE_MAKE_PROGRAM=$($taskSdk.Replace('\','/'))/cmake/3.22.1/bin/ninja.exe",
    "-DCMAKE_TOOLCHAIN_FILE=$($taskNdk.Replace('\','/'))/build/cmake/android.toolchain.cmake",
    '-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-29','-DCMAKE_BUILD_TYPE=Release',
    '-DBUILD_SHARED_LIBS=ON','-DWEBP_BUILD_LIBWEBPMUX=ON',
    '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384')
foreach ($taskOption in @('ANIM_UTILS','CWEBP','DWEBP','GIF2WEBP','IMG2WEBP','VWEBP','WEBPINFO','WEBPMUX','EXTRAS')) {
    $taskOptions += "-DWEBP_BUILD_$taskOption=OFF"
}
& $taskCmake @taskOptions
if ($LASTEXITCODE -ne 0) { throw 'ネイティブライブラリの構成に失敗しました。' }
& $taskCmake --build $taskBuild --parallel 8
if ($LASTEXITCODE -ne 0) { throw 'ネイティブライブラリのビルドに失敗しました。' }
Write-Output "ネイティブライブラリ: $taskBuild"
