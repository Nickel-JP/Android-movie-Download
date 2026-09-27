param(
    [Parameter(Mandatory)][string]$ApkPath,
    [Parameter(Mandatory)][string]$Version,
    [Parameter(Mandatory)][int]$VersionCode,
    [string]$Repository = 'Nickel-JP/Android-movie-Download',
    [string]$NotesFile = ''
)
$ErrorActionPreference = 'Stop'
if ($Repository -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$') { throw 'GitHub配信先が不正です。' }
$taskFile = Get-Item -LiteralPath $ApkPath
$taskAapt = Join-Path $env:ANDROID_HOME 'build-tools\36.0.0\aapt.exe'
$taskBadging = & $taskAapt dump badging $taskFile.FullName
if ($LASTEXITCODE -ne 0) { throw 'APK情報を取得できません。' }
$taskPackage = $taskBadging | Select-String -Pattern "^package: name='jp.nogut.ytdlp_flutter' versionCode='$VersionCode' versionName='$Version'"
if (-not $taskPackage) { throw 'APKと更新情報のパッケージ・バージョンが一致しません。' }
if ([string]::IsNullOrWhiteSpace($NotesFile)) {
    $NotesFile = Join-Path $PSScriptRoot "..\docs\release-notes\v$Version.md"
}
$taskNotes = if (Test-Path -LiteralPath $NotesFile) { Get-Content -LiteralPath $NotesFile -Raw } else { "バージョン $Version の更新です。" }
# 旧版の文字列表示にも読みやすい本文を配信し、新版には元の書式を渡す。
$taskPlainNotes = $taskNotes -replace '\A\s*# Android movie Download[^\r\n]*\r?\n\s*', ''
$taskPlainNotes = $taskPlainNotes -replace '(?m)^#{1,6}\s+', '' -replace '(?m)^\s*[-*+]\s+', '• '
$taskPlainNotes = $taskPlainNotes -replace '\*\*([^*\r\n]+)\*\*', '$1' -replace '`([^`\r\n]+)`', '$1'
$taskPlainNotes = $taskPlainNotes -replace '\[([^\]]+)\]\(([^)\r\n]+)\)', '$1（$2）'
$taskManifest = [ordered]@{
    schemaVersion = 1
    packageName = 'jp.nogut.ytdlp_flutter'
    version = $Version
    versionCode = $VersionCode
    apkUrl = "https://github.com/$Repository/releases/download/v$Version/$([Uri]::EscapeDataString($taskFile.Name))"
    size = $taskFile.Length
    sha256 = (Get-FileHash -LiteralPath $taskFile.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    notes = $taskPlainNotes.Trim()
    notesMarkdown = $taskNotes.Trim()
}
$taskOutput = Join-Path $taskFile.DirectoryName 'update.json'
$taskManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $taskOutput -Encoding utf8
Write-Output "更新情報: $taskOutput"
