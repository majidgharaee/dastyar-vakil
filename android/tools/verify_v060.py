#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import zipfile
from collections import Counter
from pathlib import Path

ROOT = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.6.0")
ASSETS = ROOT / "app" / "src" / "main" / "assets"
APK = ROOT / "manual-build-v60" / "Dastyar-Vakil-v0.6.0-debug.apk"
SDK = Path(r"F:\Codex\Dadban\work\android-toolchain\sdk")
AAPT = SDK / "build-tools" / "36.0.0" / "aapt.exe"
APKSIGNER = SDK / "build-tools" / "36.0.0" / "apksigner.bat"


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


index = (ASSETS / "index.html").read_text(encoding="utf-8")
script = (ASSETS / "app.js").read_text(encoding="utf-8")
manifest = (ROOT / "app" / "src" / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")
addresses = json.loads((ASSETS / "address-data.json").read_text(encoding="utf-8"))
legal = json.loads((ASSETS / "legal-data.json").read_text(encoding="utf-8"))
inflation = json.loads((ASSETS / "inflation-data.json").read_text(encoding="utf-8"))
inheritance = json.loads((ASSETS / "inheritance-data.json").read_text(encoding="utf-8"))

require(APK.exists() and APK.stat().st_size > 500_000, "APK missing or implausibly small")
require('android:versionCode="8"' in manifest and 'android:versionName="0.6.0"' in manifest, "manifest version mismatch")
for removed in ("هشدار اعتبار نشانی", "قوانین با متن کامل", "به‌روزرسانی محتوای آفلاین", "موضوع را بدون نام", "درباره محتوای حقوقی", "درخواست حذف اطلاعات ارسالی", "درباره ما و ارتباط با سازنده"):
    require(removed not in index, f"removed UI text remains: {removed}")
require('data-page="address-category"' in index and 'id="addressCategorySummary"' in index, "category-first address UI missing")
require('data-page="opinions"' in index and 'id="opinionYearGrid"' in index, "opinion year UI missing")
require('id="inflationDataPayload"' in index and 'id="inheritanceDataPayload"' in index, "offline calculator payloads missing")
for function_name in ("calculateInflation", "calculateInheritance", "renderOpinionYears", "openOpinionYear"):
    require(f"function {function_name}" in script, f"missing {function_name}")

records = addresses["records"]
require(len(records) == 342 and len(addresses["categories"]) == 14, "address coverage mismatch")
visible = lambda r: " ".join(str(r[k]) for k in ("title", "address", "phone", "mapQuery"))
require(not any(re.search(r"[A-Za-z\x00-\x1f\u200e\u200f\ufeff]", visible(r)) for r in records), "garbled/Latin/control character remains in visible address data")
actual_counts = Counter(r["category"] for r in records)
require(all(actual_counts[x["title"]] == x["count"] for x in addresses["categories"]), "address category counts mismatch")

unity = [x for x in legal if x.get("type") == "unity"]
opinions = [x for x in legal if x.get("type") == "opinion"]
require(len(unity) == 110 and len(opinions) == 2323, "legal index counts changed unexpectedly")
require(set(x.get("year") for x in unity) == {str(y) for y in range(1396, 1406)}, "unity decisions do not cover all ten years")
require(all(x.get("status") == "متن کامل منبع" and len(x.get("content", "")) >= 400 for x in unity), "unity full-text invariant failed")
require(all(x.get("status") == "نمایه و چکیده؛ متن کامل در منبع" for x in opinions), "opinion previews are mislabeled")

require(len(inflation["years"]) == 31, "inflation year count mismatch")
require(sum(v is not None for y in inflation["years"].values() for v in y["months"].values()) == 365, "inflation month coverage mismatch")
require(inflation["years"]["1403"]["months"]["فروردین"] == 1125.8, "1403 Farvardin index mismatch")
require(inflation["years"]["1404"]["months"]["اسفند"] == 2481.3, "1404 Esfand index mismatch")
require(len(inheritance["rules"]) == 16 and len(inheritance["sourceNotes"]) == 149, "inheritance source extraction mismatch")

badging = subprocess.check_output([str(AAPT), "dump", "badging", str(APK)], text=True, encoding="utf-8", errors="replace")
require("versionCode='8'" in badging and "versionName='0.6.0'" in badging, "APK version metadata mismatch")
java_home = Path(r"F:\Codex\Dadban\work\android-toolchain\jdk\jdk-17.0.20.1+1")
verify_env = os.environ.copy()
verify_env["JAVA_HOME"] = str(java_home)
verify_env["PATH"] = str(java_home / "bin") + os.pathsep + verify_env.get("PATH", "")
verify = subprocess.check_output([str(APKSIGNER), "verify", "--verbose", str(APK)], text=True, encoding="utf-8", errors="replace", env=verify_env)
require("Verified using v2 scheme (APK Signature Scheme v2): true" in verify, "APK v2 signature verification failed")

with zipfile.ZipFile(APK) as archive:
    names = set(archive.namelist())
    for filename in ("legal-data.json", "address-data.json", "inflation-data.json", "inheritance-data.json", "index.html", "app.js", "styles.css"):
        member = "assets/" + filename
        require(member in names, f"APK asset missing: {filename}")
        require(sha(archive.read(member)) == sha((ASSETS / filename).read_bytes()), f"APK asset differs from source: {filename}")

print(json.dumps({
    "status": "PASS", "apkBytes": APK.stat().st_size, "addresses": len(records),
    "addressCategories": len(addresses["categories"]), "unity": len(unity), "opinions": len(opinions),
    "inflationYears": len(inflation["years"]), "inflationMonths": 365,
    "inheritanceRules": len(inheritance["rules"]), "apkAssetsMatched": 7,
}, ensure_ascii=False, indent=2))
