$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$release = Join-Path $project 'release-v9'
$stage = Join-Path $project 'delivery-v9'
$zip = Join-Path $release 'Dastyar-Vakil-v9.0.0-delivery.zip'
$sourceZip = Join-Path $release 'Dastyar-Vakil-v9.0.0-source.zip'

$projectFull = [IO.Path]::GetFullPath($project).TrimEnd('\') + '\'
foreach ($candidate in @($stage, (Join-Path $project 'source-v9-package'))) {
    $resolved = [IO.Path]::GetFullPath($candidate)
    if (-not $resolved.StartsWith($projectFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to modify a path outside the project: $resolved"
    }
}

if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage | Out-Null

$files = @(
    (Join-Path $release 'Dastyar-Vakil-v9.0.0-release.apk'),
    (Join-Path $release 'Dastyar-Vakil-v9.0.0-release.aab'),
    (Join-Path $project 'README.md'),
    (Join-Path $project 'SECURITY.md'),
    (Join-Path $project 'PRIVACY.md'),
    (Join-Path $project 'CONTENT-SOURCES.md'),
    (Join-Path $project 'FINAL-QA-REPORT-v9.md')
)
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "Missing delivery file: $file" }
    Copy-Item -LiteralPath $file -Destination $stage
}

$manifestItems = Get-ChildItem -LiteralPath $stage -File | Sort-Object Name | ForEach-Object {
    [ordered]@{ name = $_.Name; bytes = $_.Length; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $_.FullName).Hash }
}
$manifest = [ordered]@{
    product = 'Dastyar Vakil'
    versionName = '9.0.0'
    versionCode = 10
    generatedAt = (Get-Date).ToUniversalTime().ToString('o')
    files = @($manifestItems)
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $stage 'MANIFEST.json') -Encoding UTF8

if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal

$sourceStage = Join-Path $project 'source-v9-package'
if (Test-Path -LiteralPath $sourceStage) { Remove-Item -LiteralPath $sourceStage -Recurse -Force }
New-Item -ItemType Directory -Path $sourceStage | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'app') -Destination $sourceStage -Recurse
Copy-Item -LiteralPath (Join-Path $project 'tools') -Destination $sourceStage -Recurse
Copy-Item -LiteralPath (Join-Path $project 'build.gradle'),(Join-Path $project 'settings.gradle'),(Join-Path $project 'gradle.properties'),(Join-Path $project '.gitignore'),(Join-Path $project 'README.md'),(Join-Path $project 'SECURITY.md'),(Join-Path $project 'PRIVACY.md'),(Join-Path $project 'CONTENT-SOURCES.md'),(Join-Path $project 'FINAL-QA-REPORT-v9.md') -Destination $sourceStage
Get-ChildItem -LiteralPath $sourceStage -Recurse -Directory -Force | Where-Object { $_.Name -in @('build','.gradle','release-v9','delivery-v9','qa-v9') } | Sort-Object FullName -Descending | Remove-Item -Recurse -Force
Get-ChildItem -LiteralPath $sourceStage -Recurse -File -Force | Where-Object { $_.Name -in @('local.properties') -or $_.Extension -in @('.jks','.keystore','.p12','.pfx') -or $_.Name -match 'credential|password|secret' } | Remove-Item -Force
if (Test-Path -LiteralPath $sourceZip) { Remove-Item -LiteralPath $sourceZip -Force }
Compress-Archive -Path (Join-Path $sourceStage '*') -DestinationPath $sourceZip -CompressionLevel Optimal

$expected = @('CONTENT-SOURCES.md','Dastyar-Vakil-v9.0.0-release.aab','Dastyar-Vakil-v9.0.0-release.apk','FINAL-QA-REPORT-v9.md','MANIFEST.json','PRIVACY.md','README.md','SECURITY.md') | Sort-Object
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try { $actual = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') } | ForEach-Object { [IO.Path]::GetFileName($_.FullName) } | Sort-Object) } finally { $archive.Dispose() }
if (($expected -join '|') -ne ($actual -join '|')) { throw "Delivery ZIP allowlist mismatch: $($actual -join ', ')" }

Get-Item -LiteralPath $zip,$sourceZip | Select-Object FullName,Length,LastWriteTime
