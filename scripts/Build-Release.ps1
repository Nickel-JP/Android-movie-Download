param(
    [string]$Version = '1.0.0',
    [int]$BuildNumber = 1,
    [string]$Repository = 'Nickel-JP/Android-movie-Download',
    [string]$ToolchainRoot = 'D:\Tools\YtDlpFlutter'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Use-Toolchain.ps1') -ToolchainRoot $ToolchainRoot
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ($Version -notmatch '^\d+\.\d+\.\d+$' -or $BuildNumber -lt 1) { throw 'バージョン指定を確認してください。' }
if (-not (Test-Path -LiteralPath (Join-Path $taskProject 'android\key.properties'))) { throw 'ローカル署名設定が必要です。' }
Push-Location $taskProject
try {
    flutter analyze
    if ($LASTEXITCODE -ne 0) { throw 'Flutterの静的解析に失敗しました。' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Flutterテストに失敗しました。' }
    flutter build apk --release --target-platform android-arm64 --build-name $Version --build-number $BuildNumber "--dart-define=UPDATE_REPOSITORY=$Repository"
    if ($LASTEXITCODE -ne 0) { throw 'APKビルドに失敗しました。' }
    $taskSigner = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\apksigner.bat'
    $taskSourceApk = Join-Path $taskProject 'build\app\outputs\flutter-apk\app-release.apk'
    & $taskSigner verify $taskSourceApk
    if ($LASTEXITCODE -ne 0) { throw 'APKの署名検証に失敗しました。' }
    & (Join-Path $PSScriptRoot 'Build-Webp16k.ps1') -ToolchainRoot $ToolchainRoot
    $taskPatched = Join-Path $taskProject 'build\app-native-patched.apk'
    $taskAligned = Join-Path $taskProject 'build\app-native-aligned.apk'
    python (Join-Path $PSScriptRoot 'Patch-ApkNative.py') --source-apk $taskSourceApk --output-apk $taskPatched --library-directory (Join-Path $ToolchainRoot 'native-build\webp-arm64')
    if ($LASTEXITCODE -ne 0) { throw 'ネイティブ互換性の反映に失敗しました。' }
    & (Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\zipalign.exe') -f 4 $taskPatched $taskAligned
    if ($LASTEXITCODE -ne 0) { throw 'APKの配置検証に失敗しました。' }
    $taskDist = Join-Path $taskProject 'dist'
    New-Item -ItemType Directory -Path $taskDist -Force | Out-Null
    $taskApk = Join-Path $taskDist "Android-movie-Download-v$Version-arm64.apk"
    $taskKeys = @{}
    Get-Content -LiteralPath (Join-Path $taskProject 'android\key.properties') | ForEach-Object {
        if ($_ -match '^([^#=]+)=(.*)$') { $taskKeys[$Matches[1].Trim()] = $Matches[2] }
    }
    $env:YT_SIGN_STORE_PASSWORD = $taskKeys['storePassword']
    $env:YT_SIGN_KEY_PASSWORD = $taskKeys['keyPassword']
    try {
        & $taskSigner sign --ks $taskKeys['storeFile'] --ks-key-alias $taskKeys['keyAlias'] --ks-pass env:YT_SIGN_STORE_PASSWORD --key-pass env:YT_SIGN_KEY_PASSWORD --out $taskApk $taskAligned
        if ($LASTEXITCODE -ne 0) { throw '配布APKの署名に失敗しました。' }
    } finally { Remove-Item Env:YT_SIGN_STORE_PASSWORD; Remove-Item Env:YT_SIGN_KEY_PASSWORD }
    & $taskSigner verify $taskApk
    if ($LASTEXITCODE -ne 0) { throw '配布APKの署名検証に失敗しました。' }
    & (Join-Path $PSScriptRoot 'New-UpdateManifest.ps1') -ApkPath $taskApk -Version $Version -VersionCode $BuildNumber -Repository $Repository
    Write-Output "配布用APK: $taskApk"
} finally { Pop-Location }
