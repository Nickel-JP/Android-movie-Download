param([string]$ToolchainRoot = 'D:\Tools\YtDlpFlutter')
$ErrorActionPreference = 'Stop'
$taskFlutter = Join-Path $ToolchainRoot 'flutter\bin\flutter.bat'
$taskSdk = Join-Path $ToolchainRoot 'android-sdk'
$taskJdk = Get-ChildItem -LiteralPath (Join-Path $ToolchainRoot 'jdk17') -Directory | Select-Object -First 1 -ExpandProperty FullName
if (-not (Test-Path -LiteralPath $taskFlutter)) { throw 'Flutter SDKが見つかりません。' }
$env:JAVA_HOME = $taskJdk
$env:ANDROID_HOME = $taskSdk
$env:ANDROID_SDK_ROOT = $taskSdk
$env:FLUTTER_SUPPRESS_ANALYTICS = 'true'
$env:PYTHONIOENCODING = 'utf-8'
$env:PUB_CACHE = Join-Path $ToolchainRoot 'pub-cache'
$env:PATH = "$ToolchainRoot\flutter\bin;$taskJdk\bin;$taskSdk\platform-tools;$env:PATH"
