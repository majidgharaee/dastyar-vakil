$ErrorActionPreference = 'Stop'

$project = Split-Path -Parent $PSScriptRoot
$sdk = 'F:\Codex\Dadban\work\android-toolchain\sdk'
$jdk = 'F:\Codex\Dadban\work\android-toolchain\jdk\jdk-17.0.20.1+1'
$gradle = 'F:\Codex\Dadban\work\android-toolchain\gradle\gradle-9.4.1\bin\gradle.bat'
$required = @('DV_KEYSTORE_PATH','DV_KEY_ALIAS','DV_KEYSTORE_PASSWORD','DV_KEY_PASSWORD','DV_SIGNER_SHA256')
foreach ($name in $required) {
    if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name))) {
        throw "Missing required release-signing environment variable: $name"
    }
}
$debugAlias = 'android' + 'debugkey'
if ($env:DV_KEY_ALIAS -eq $debugAlias) { throw 'Debug signing aliases are forbidden for release builds.' }
$keystore = [IO.Path]::GetFullPath($env:DV_KEYSTORE_PATH)
if (-not (Test-Path -LiteralPath $keystore -PathType Leaf)) { throw 'Release keystore does not exist.' }
$expectedDigest = ($env:DV_SIGNER_SHA256 -replace '[^0-9A-Fa-f]','').ToUpperInvariant()
if ($expectedDigest.Length -ne 64) { throw 'DV_SIGNER_SHA256 must contain one SHA-256 certificate digest.' }

$env:JAVA_HOME = $jdk
$env:ANDROID_HOME = $sdk
$env:ANDROID_SDK_ROOT = $sdk
$env:Path = "$(Join-Path $jdk 'bin');$env:Path"
& $gradle --no-daemon --console=plain assembleRelease
if ($LASTEXITCODE -ne 0) { throw 'Gradle release build failed.' }

$builtApk = Join-Path $project 'app\build\outputs\apk\release\app-release-unsigned.apk'
if (-not (Test-Path -LiteralPath $builtApk -PathType Leaf)) { throw 'Gradle did not produce the optimized unsigned release APK.' }
$out = Join-Path $project 'release-v070'
New-Item -ItemType Directory -Force -Path $out | Out-Null
$apk = Join-Path $out 'Dastyar-Vakil-v0.7.0-release.apk'
$apksigner = Join-Path $sdk 'build-tools\36.0.0\apksigner.bat'
& $apksigner sign --ks $keystore --ks-key-alias $env:DV_KEY_ALIAS --ks-pass env:DV_KEYSTORE_PASSWORD --key-pass env:DV_KEY_PASSWORD --v1-signing-enabled true --v2-signing-enabled true --v3-signing-enabled true --v4-signing-enabled false --out $apk $builtApk
if ($LASTEXITCODE -ne 0) { throw 'Release signing failed.' }
$certificate = (& $apksigner verify --verbose --print-certs $apk) -join "`n"
if ($LASTEXITCODE -ne 0) { throw 'Signature verification failed.' }
$actual = [regex]::Match($certificate,'SHA-256 digest:\s*([0-9A-Fa-f:]+)').Groups[1].Value -replace ':',''
if ($actual.ToUpperInvariant() -ne $expectedDigest) { Remove-Item -LiteralPath $apk -Force; throw 'Signer certificate digest does not match the approved release identity.' }
if ($certificate -notmatch 'Verified using v2 scheme \(APK Signature Scheme v2\): true') { Remove-Item -LiteralPath $apk -Force; throw 'APK Signature Scheme v2 is required.' }
Get-Item -LiteralPath $apk | Select-Object FullName,Length,LastWriteTime
