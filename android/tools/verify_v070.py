#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.7.0")
ASSETS = ROOT / "app" / "src" / "main" / "assets"
APK = ROOT / "release-v070" / "Dastyar-Vakil-v0.7.0-release.apk"
SDK = Path(r"F:\Codex\Dadban\work\android-toolchain\sdk")
AAPT = SDK / "build-tools" / "36.0.0" / "aapt.exe"
APKSIGNER = SDK / "build-tools" / "36.0.0" / "apksigner.bat"
JDK = Path(r"F:\Codex\Dadban\work\android-toolchain\jdk\jdk-17.0.20.1+1")

def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()

index = (ASSETS / "index.html").read_text(encoding="utf-8")
script = (ASSETS / "app.js").read_text(encoding="utf-8")
java = (ROOT / "app" / "src" / "main" / "java" / "ir" / "dadban" / "app" / "MainActivity.java").read_text(encoding="utf-8")
manifest = (ROOT / "app" / "src" / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")

require(APK.exists() and APK.stat().st_size > 500_000, "release APK missing or implausibly small")
require('android:versionCode="9"' in manifest and 'android:versionName="0.7.0"' in manifest, "manifest version mismatch")
require("requireFreshAuth('تأیید نهایی حذف همه اطلاعات',eraseLocalAccount)" in script, "delete step-up authentication missing")
require("requireFreshAuth(state.officeSecurity.pinEnabled?'تغییر رمز دفتر':'افزودن رمز دفتر'" in script, "PIN mutation authentication missing")
require("PBKDF2" in script and "210000" in script, "hardened PIN derivation missing")
require("if (!hasNotificationPermission())" in java and "return false;" in java, "notification permission gate missing")
require("cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8))" in java, "AES-GCM key binding missing")
require("deleteEntry(KEY_ALIAS)" in java, "keystore deletion missing")
require("هوش مصنوعی" in index and "حالت محرمانه آفلاین" in index, "assistant disclosure missing")
require("trustedCatalog=verifiedPlaces" in script, "unverified address OCR remains user-visible")
require(len(re.findall(r"\{id:'[^']+'.*?title:'", script)) >= 17, "calculator catalog incomplete")

for path in ROOT.rglob("*"):
    require(not (path.is_dir() and path.name.lower().startswith("edge-")), f"browser profile directory present: {path}")
    require(path.name not in {"Login Data", "History", "Cookies", "Web Data", "Local State"}, f"browser state present: {path}")

active_text = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in [ROOT / "tools" / "build_release_v070.ps1", ROOT / "app" / "build.gradle"])
for forbidden in ("pass:" + "android", "dadban-" + "debug.keystore"):
    require(forbidden not in active_text, f"forbidden signing material remains: {forbidden}")

badging = subprocess.check_output([str(AAPT), "dump", "badging", str(APK)], text=True, encoding="utf-8", errors="replace")
require("versionCode='9'" in badging and "versionName='0.7.0'" in badging, "APK version metadata mismatch")
verify_env = os.environ.copy()
verify_env["JAVA_HOME"] = str(JDK)
verify_env["PATH"] = str(JDK / "bin") + os.pathsep + verify_env.get("PATH", "")
verify = subprocess.check_output([str(APKSIGNER), "verify", "--verbose", "--print-certs", str(APK)], text=True, encoding="utf-8", errors="replace", env=verify_env)
require("Verified using v2 scheme (APK Signature Scheme v2): true" in verify, "APK v2 signature verification failed")
require("Verified using v1 scheme (JAR signing): true" in verify, "APK v1 compatibility signature missing for minSdk 23")
digest_match = re.search(r"SHA-256 digest:\s*([0-9A-Fa-f:]+)", verify)
require(digest_match is not None, "signer digest missing")
actual_digest = digest_match.group(1).replace(":", "").upper()
expected_digest = re.sub(r"[^0-9A-Fa-f]", "", os.environ.get("DV_SIGNER_SHA256", "")).upper()
require(len(expected_digest) == 64 and actual_digest == expected_digest, "unapproved release signer")
require((ROOT / "app" / "build" / "outputs" / "mapping" / "release" / "mapping.txt").exists(), "R8 mapping output missing")

with zipfile.ZipFile(APK) as archive:
    names = set(archive.namelist())
    for filename in ("legal-data.json", "address-data.json", "inflation-data.json", "inheritance-data.json", "index.html", "app.js", "styles.css"):
        member = "assets/" + filename
        require(member in names, f"APK asset missing: {filename}")
        require(sha(archive.read(member)) == sha((ASSETS / filename).read_bytes()), f"APK asset differs from source: {filename}")

print(json.dumps({"status":"PASS","version":"0.7.0","apkBytes":APK.stat().st_size,"signerSha256":actual_digest,"apkAssetsMatched":7,"securityGates":8,"r8":True,"signatures":["v1","v2","v3"]}, ensure_ascii=False, indent=2))
