$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$apk = Join-Path $project 'release-v070\Dastyar-Vakil-v0.7.0-release.apk'
if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'Verified release APK is missing.' }
$delivery = Join-Path $project 'delivery-v070'
if (Test-Path -LiteralPath $delivery) { Remove-Item -LiteralPath $delivery -Recurse -Force }
New-Item -ItemType Directory -Path $delivery | Out-Null
Copy-Item -LiteralPath $apk -Destination $delivery
foreach ($name in @('README.md','SECURITY.md','PRIVACY.md','CONTENT-SOURCES.md','FINAL-QA-REPORT.md')) { Copy-Item -LiteralPath (Join-Path $project $name) -Destination $delivery }
foreach ($path in Get-ChildItem -LiteralPath $delivery -Recurse -Force) {
    if ($path.Name -match '^(edge-|Login Data$|History$|Cookies$|Web Data$|Local State$)' -or $path.Extension -in @('.jks','.keystore','.p12','.pem')) {
        throw "Forbidden delivery artifact: $($path.FullName)"
    }
}
$manifest = Get-ChildItem -LiteralPath $delivery -File | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
}
$manifest | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $delivery 'MANIFEST.json') -Encoding utf8
Compress-Archive -Path (Join-Path $delivery '*') -DestinationPath (Join-Path $project 'Dastyar-Vakil-v0.7.0-delivery.zip') -Force
$sourceStage = Join-Path $project 'source-v070'
if (Test-Path -LiteralPath $sourceStage) { Remove-Item -LiteralPath $sourceStage -Recurse -Force }
New-Item -ItemType Directory -Path $sourceStage,(Join-Path $sourceStage 'tools') | Out-Null
New-Item -ItemType Directory -Path (Join-Path $sourceStage 'app') | Out-Null
Copy-Item -LiteralPath (Join-Path $project 'app\src') -Destination (Join-Path $sourceStage 'app\src') -Recurse
foreach ($name in @('build.gradle','proguard-rules.pro')) {
    Copy-Item -LiteralPath (Join-Path $project "app\$name") -Destination (Join-Path $sourceStage 'app')
}
foreach ($name in @('build.gradle','settings.gradle','gradle.properties','.gitignore','README.md','SECURITY.md','PRIVACY.md','CONTENT-SOURCES.md','FINAL-QA-REPORT.md')) {
    Copy-Item -LiteralPath (Join-Path $project $name) -Destination $sourceStage
}
foreach ($name in @('build_release_v070.ps1','verify_v070.py','security_regression_v070.py','package_delivery_v070.ps1','make_preview_v070.py','qa_harness_v070.js','security_ui_harness_v070.js')) {
    Copy-Item -LiteralPath (Join-Path $project "tools\$name") -Destination (Join-Path $sourceStage 'tools')
}
foreach ($path in Get-ChildItem -LiteralPath $sourceStage -Recurse -Force) {
    if ($path.Name -match '^(edge-|Login Data$|History$|Cookies$|Web Data$|Local State$)' -or $path.Extension -in @('.jks','.keystore','.p12','.pem')) {
        throw "Forbidden source artifact: $($path.FullName)"
    }
}
if (Test-Path -LiteralPath (Join-Path $sourceStage 'app\build')) { throw 'Gradle build intermediates entered the source package.' }
Compress-Archive -Path (Join-Path $sourceStage '*') -DestinationPath (Join-Path $project 'Dastyar-Vakil-v0.7.0-source.zip') -Force
Get-Item -LiteralPath (Join-Path $project 'Dastyar-Vakil-v0.7.0-delivery.zip'),(Join-Path $project 'Dastyar-Vakil-v0.7.0-source.zip') | Select-Object FullName,Length,LastWriteTime
