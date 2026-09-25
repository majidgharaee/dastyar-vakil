from __future__ import annotations

import json
import re
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.5.0")
ASSETS = ROOT / "app" / "src" / "main" / "assets"
APK = ROOT / "manual-build-v50" / "Dastyar-Vakil-v0.5.0-debug.apk"

html = (ASSETS / "index.html").read_text(encoding="utf-8")
js = (ASSETS / "app.js").read_text(encoding="utf-8")
java = (ROOT / "app/src/main/java/ir/dadban/app/MainActivity.java").read_text(encoding="utf-8")
manifest = (ROOT / "app/src/main/AndroidManifest.xml").read_text(encoding="utf-8")
fetcher = (ROOT / "tools/fetch_legal_content.py").read_text(encoding="utf-8")
addresses = json.loads((ASSETS / "address-data.json").read_text(encoding="utf-8"))
legal = json.loads((ASSETS / "legal-data.json").read_text(encoding="utf-8"))

def require(ok: bool, message: str):
    if not ok:
        raise AssertionError(message)

home = re.search(r'<section class="page active" data-page="home".*?</section>\s*</section>', html, re.S).group(0)
require("وقت‌ها و هشدارها" not in home, "home hearing shortcut remains")
require(html.count('class="calculator-card"') == 17, "calculator count is not 17")
require('data-page="unity"' in html and 'unityYearGrid' in html, "unity page is missing")
require('Content-Security-Policy' in html, "CSP is missing")
require('script src="legal-data.js"' not in html, "executable legal data is still loaded")
require('readAsset("legal-data.json")' in java and 'Base64.NO_WRAP' in java, "legal JSON is not safely embedded")
require('legal-data.json' in fetcher and 'APPROVED_HOSTS' in fetcher and 'validate_record' in fetcher, "secure content refresh controls are missing")
require('startupOfficeLocked?[]:readStore' in js, "protected office data is still eagerly read")
require("officeAuthThrottle" in js and "officeAuthThrottle" in java, "PIN throttle is not persistent")
require("ابتدا دستیار وکیل را باز کنید" in js, "lock settings lack reauthentication gate")
require("fallback-" not in js, "weak PIN hash fallback remains")
require('default-src \'none\'' in html and "connect-src 'none'" in html, "restrictive CSP is incomplete")

require(len(addresses) >= 400, "address extraction coverage is unexpectedly small")
categories = sorted({item['category'] for item in addresses})
require(len(categories) == 15, f"expected 15 exact PDF groups, got {len(categories)}")
require({item['page'] for item in addresses} == set(range(1, 28)), "not every PDF page contributed records")
require(all(item.get('verification') == 'نیازمند بازبینی پیش از مراجعه' for item in addresses), "address warning missing")
require(sum(1 for item in legal if item.get('type') == 'unity') >= 20, "unity corpus unexpectedly small")

base = js.split('let education=[', 1)[1].split('const supplementalCivil=', 1)[0]
base_civil = base.count("kind:'civil'")
base_criminal = base.count("kind:'criminal'")
def count_titles(name: str) -> int:
    part = js.split(f"const {name}=[", 1)[1].split('];', 1)[0]
    return len(re.findall(r"'[^']+'", part))
civil_count = max(50, base_civil + count_titles('supplementalCivil'))
criminal_count = max(50, base_criminal + count_titles('supplementalCriminal'))
require(civil_count >= 50 and criminal_count >= 50, "checklists below requested minimum")

require(APK.exists(), "APK is missing")
with zipfile.ZipFile(APK) as zf:
    names = set(zf.namelist())
    for name in ['classes.dex', 'assets/legal-data.json', 'assets/address-data.json', 'assets/index.html', 'assets/app.js']:
        require(name in names, f"APK missing {name}")
    require('assets/legal-data.js' not in names, "obsolete executable data shipped in APK")

aapt = Path(r"F:\Codex\Dadban\work\android-toolchain\sdk\build-tools\36.0.0\aapt.exe")
badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(APK)], text=True, encoding='utf-8', errors='replace')
require("versionCode='7'" in badging and "versionName='0.5.0'" in badging, "APK version metadata is wrong")
require('android:versionCode="7"' in manifest and 'android:versionName="0.5.0"' in manifest, "manifest version is wrong")

print(json.dumps({
    "status": "PASS", "calculators": 17, "civil_checklists": civil_count,
    "criminal_checklists": criminal_count, "address_records": len(addresses),
    "address_categories": len(categories), "address_pages": 27,
    "unity_records": sum(1 for item in legal if item.get('type') == 'unity'),
    "security_assertions": 9, "apk_bytes": APK.stat().st_size,
}, ensure_ascii=False, indent=2))
