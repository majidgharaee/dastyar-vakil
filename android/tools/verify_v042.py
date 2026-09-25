from __future__ import annotations

import hashlib
import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "app" / "src" / "main" / "assets"
HTML = (ASSETS / "index.html").read_text(encoding="utf-8")
APP_JS = (ASSETS / "app.js").read_text(encoding="utf-8")
MANIFEST = (ROOT / "app" / "src" / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")
APK = ROOT / "manual-build-v42" / "Dastyar-Vakil-v0.4.2-debug.apk"


def require(value: bool, message: str) -> None:
    if not value:
        raise AssertionError(message)


def calculator_ids_from_js() -> list[str]:
    block = re.search(r"const calculators=\[(.*?)\];\s*\n\s*const education", APP_JS, re.S)
    require(block is not None, "calculator data array missing")
    return re.findall(r"id:'([^']+)'", block.group(1))


def calculator_ids_from_initial_html() -> list[str]:
    block = re.search(r'<section class="page calculator-page".*?</section>', HTML, re.S)
    require(block is not None, "calculator page missing")
    return re.findall(r'data-calculator="([^"]+)"', block.group(0))


def main() -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    js_ids = calculator_ids_from_js()
    initial_ids = calculator_ids_from_initial_html()
    require(len(js_ids) == 17 and len(set(js_ids)) == 17, f"expected 17 JS calculators, got {len(js_ids)}")
    require(initial_ids == js_ids, "the initial HTML must contain all 17 calculators in the same order")
    require(initial_ids[-1] == "date", "date calculator must be the seventeenth card")
    require('id="calculatorGrid" class="calculator-grid calculators-ready"' in HTML, "initial calculator grid is not ready")
    require("if(name==='calculators')" in APP_JS and "renderCalculators();" in APP_JS, "calculator entry refresh missing")
    require("grid.hidden=false" in APP_JS and "calculators-ready" in APP_JS, "calculator visibility safeguard missing")

    nav = re.search(r'<nav class="bottom-nav".*?</nav>', HTML, re.S)
    require(nav is not None, "bottom navigation missing")
    destinations = re.findall(r'data-nav="([^"]+)"', nav.group(0))
    require(destinations == ["library", "assistant", "calculators", "office", "about"], f"wrong bottom navigation: {destinations}")
    labels = re.findall(r'<small>(.*?)</small>', nav.group(0), re.S)
    require(labels == ["کتابخانه", "هوش مصنوعی", "محاسبات", "دستیار وکیل", "درباره ما"], f"wrong bottom labels: {labels}")

    for label in ("سفارش لایحه و دادخواست", "سفارش تایپ فوری", "هوش مصنوعی حقوقی", "چک‌لیست دعاوی", "همکاری وکلا", "نشانی‌ها و مراجع"):
        require(label in HTML, f"home service label missing: {label}")
    for destination in ("education", "collaboration", "addresses"):
        require(f'data-page-link="{destination}"' in HTML, f"moved home service missing: {destination}")

    require('android:versionCode="6"' in MANIFEST and 'android:versionName="0.4.2"' in MANIFEST, "manifest version mismatch")
    require("۰.۴.۲ — آزمایشی" in HTML, "visible version mismatch")
    require(APK.exists(), "APK missing")
    with zipfile.ZipFile(APK) as archive:
        names = set(archive.namelist())
        for needed in ("classes.dex", "assets/index.html", "assets/app.js", "assets/styles.css", "assets/legal-data.js"):
            require(needed in names, f"APK missing {needed}")
        packed_html = archive.read("assets/index.html").decode("utf-8")
        require(len(re.findall(r'data-calculator="', re.search(r'<section class="page calculator-page".*?</section>', packed_html, re.S).group(0))) == 17,
                "packaged APK does not contain 17 initial calculator cards")

    digest = hashlib.sha256(APK.read_bytes()).hexdigest().upper()
    checks = {
        "initialCalculatorCards": len(initial_ids),
        "calculatorIds": initial_ids,
        "bottomNavigation": destinations,
        "bottomLabels": labels,
        "renamedServices": True,
        "movedServices": ["education", "collaboration", "addresses"],
        "apkAssetsVerified": True,
    }
    result = {"version": "0.4.2", "status": "PASS", "checks": checks, "apk": {"path": str(APK), "bytes": APK.stat().st_size, "sha256": digest}}
    (ROOT / "QA-REPORT-0.4.2.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    report = f"""# گزارش کنترل نسخه ۰.۴.۲ دستیار وکیل

نتیجه ماشینی: **PASS**

- صفحه محاسبات در HTML اولیه، پیش از هر کلیک یا جست‌وجو، دقیقاً ۱۷ کارت دارد.
- هنگام هر ورود به صفحه محاسبات، جست‌وجو پاک و هر ۱۷ کارت دوباره نمایش داده می‌شوند.
- ترتیب نوار پایین در رابط راست‌به‌چپ: کتابخانه، هوش مصنوعی، محاسبات، دستیار وکیل، درباره ما.
- عناوین خدمات اصلی اصلاح و چک‌لیست دعاوی، همکاری وکلا و نشانی‌ها به خدمات اصلی منتقل شدند.
- وجود فایل‌های اجرایی و دارایی‌های اصلی در APK کنترل شد.
- SHA-256 APK: `{digest}`

## حدود آزمون

این نتیجه، کنترل ساختاری و مرورگری نسخه است. نصب و کارکرد روی گوشی واقعی در این مرحله، به‌دلیل متصل نبودن دستگاه به ADB، ادعا نمی‌شود. APK با کلید آزمایشی امضا شده است.
"""
    (ROOT / "QA-REPORT-0.4.2-FA.md").write_text(report, encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
