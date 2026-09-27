param(
    [string]$Version = '1.0.0',
    [string]$Repository = 'Nickel-JP/Android-movie-Download',
    [switch]$Draft
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskApk = Join-Path $taskRoot "dist\Android-movie-Download-v$Version-arm64.apk"
$taskManifestPath = Join-Path $taskRoot 'dist\update.json'
$taskNotes = Join-Path $taskRoot "docs\release-notes\v$Version.md"
$taskManifest = Get-Content -LiteralPath $taskManifestPath -Raw | ConvertFrom-Json
if ($taskManifest.version -ne $Version -or $taskManifest.apkUrl -notlike "https://github.com/$Repository/releases/download/v$Version/*") { throw '更新情報とリリース先が一致しません。' }
if ((Get-FileHash -LiteralPath $taskApk -Algorithm SHA256).Hash.ToLowerInvariant() -ne $taskManifest.sha256) { throw 'APKのハッシュが更新情報と一致しません。' }
$taskArguments = @('release','create',"v$Version",$taskApk,$taskManifestPath,'--repo',$Repository,
    '--title',"Android movie Download $Version",'--notes-file',$taskNotes)
if ($Draft) { $taskArguments += '--draft' }
& gh @taskArguments
if ($LASTEXITCODE -ne 0) { throw 'GitHub Releaseを作成できませんでした。' }
