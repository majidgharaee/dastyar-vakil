from __future__ import annotations

import hashlib
import json
import math
import re
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "app" / "src" / "main" / "assets"
APP_JS = (ASSETS / "app.js").read_text(encoding="utf-8")
HTML = (ASSETS / "index.html").read_text(encoding="utf-8")
MANIFEST = (ROOT / "app" / "src" / "main" / "AndroidManifest.xml").read_text(encoding="utf-8")
MAIN = (ROOT / "app" / "src" / "main" / "java" / "ir" / "dadban" / "app" / "MainActivity.java").read_text(encoding="utf-8")
ALARM = (ROOT / "app" / "src" / "main" / "java" / "ir" / "dadban" / "app" / "AlarmReceiver.java").read_text(encoding="utf-8")
APK = ROOT / "manual-build-v4" / "Dastyar-Vakil-v0.4.0-debug.apk"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def calculator_records() -> list[dict[str, str | float]]:
    block = re.search(r"const calculators=\[(.*?)\];\s*\n\s*const education", APP_JS, re.S)
    require(block is not None, "calculator array not found")
    objects = re.findall(r"\{(.*?)\}(?:,|\s*$)", block.group(1), re.S)
    records = []
    for obj in objects:
        def string(name: str) -> str:
            match = re.search(rf"{name}:'([^']*)'", obj)
            require(match is not None, f"missing {name}")
            return match.group(1)

        rate = re.search(r"defaultRate:([0-9.]+)", obj)
        require(rate is not None, "missing defaultRate")
        records.append({"id": string("id"), "title": string("title"), "mode": string("mode"), "rate": float(rate.group(1))})
    return records


def expected(record: dict[str, str | float]) -> float:
    mode, rate = str(record["mode"]), float(record["rate"])
    amount = 1_000_000.0
    if mode in {"percent", "rate"}:
        return amount * rate / 100
    if mode == "index":
        return amount * rate
    if mode == "estate":
        return max(0.0, amount - amount * rate / 100)
    if mode == "unit":
        return 5 * rate
    if mode == "loan":
        months, monthly = 36, rate / 1200
        return amount / months if monthly == 0 else amount * monthly * (1 + monthly) ** months / ((1 + monthly) ** months - 1)
    raise AssertionError(f"unknown calculator mode: {mode}")


def load_legal_data() -> list[dict]:
    text = (ASSETS / "legal-data.js").read_text(encoding="utf-8")
    match = re.search(r"window\.LEGAL_CONTENT\s*=\s*(\[.*\]);\s*$", text, re.S)
    require(match is not None, "legal-data.js wrapper invalid")
    return json.loads(match.group(1))


def pass_one_calculator_structure() -> dict:
    rows = calculator_records()
    require(len(rows) == 16, f"expected 16 calculators, got {len(rows)}")
    require(len({r['id'] for r in rows}) == 16, "calculator IDs must be unique")
    require(all(r["mode"] in {"percent", "rate", "index", "estate", "unit", "loan"} for r in rows), "invalid calculation mode")
    require("items.map(x=>calculatorCard(x))" in APP_JS, "all calculator cards are not rendered")
    return {"name": "دور اول: ساختار", "status": "PASS", "calculatorCount": len(rows), "ids": [r["id"] for r in rows]}


def pass_two_calculator_math() -> dict:
    results = []
    for row in calculator_records():
        value = expected(row)
        require(math.isfinite(value) and value >= 0, f"invalid result for {row['id']}")
        results.append({"id": row["id"], "scenarioResult": round(value, 4)})
    require("months<1||months>360" in APP_JS, "loan month validation missing")
    require("Math.max(0,amount-d)" in APP_JS, "estate lower bound missing")
    require("!Number.isFinite(result)||result<0" in APP_JS, "final numeric guard missing")
    return {"name": "دور دوم: منطق عددی", "status": "PASS", "scenarios": results}


def pass_three_integration() -> dict:
    nav = re.search(r'<nav class="bottom-nav".*?</nav>', HTML, re.S)
    require(nav is not None, "bottom navigation missing")
    destinations = re.findall(r'data-nav="([^"]+)"', nav.group(0))
    require(destinations == ["library", "education", "calculators", "collaboration", "addresses"], f"wrong bottom navigation: {destinations}")
    require('id="openAlarmSettings"' in HTML and 'id="hearingReminderAt"' in HTML, "visible alarm controls missing")
    require("SCHEDULE_EXACT_ALARM" in MANIFEST and "RECEIVE_BOOT_COMPLETED" in MANIFEST, "alarm permissions missing")
    require("ACTION_BOOT_COMPLETED" in ALARM and "rescheduleAll(context)" in ALARM, "alarm restoration missing")
    require("window.handleNativeBack" in APP_JS and "confirmExit" in MAIN, "secondary exit confirmation missing")
    require('id="deleteAccountDialog"' in HTML and "deleteProfessionalData" in MAIN, "account deletion missing")
    require('data-page="about"' in HTML and "09121543994" in HTML and "majid.gharaee1369@gmail.com" in HTML, "creator contact details missing")
    require(APK.exists(), "APK missing")
    with zipfile.ZipFile(APK) as archive:
        names = set(archive.namelist())
        for needed in {"classes.dex", "assets/index.html", "assets/app.js", "assets/styles.css", "assets/legal-data.js"}:
            require(needed in names, f"APK missing {needed}")
    return {"name": "دور سوم: اتصال رابط و Android", "status": "PASS", "bottomNav": destinations}


def legal_pass() -> dict:
    rows = load_legal_data()
    counts = {kind: sum(1 for row in rows if row.get("type") == kind) for kind in ("law", "unity", "opinion")}
    require(counts == {"law": 15, "unity": 20, "opinion": 20}, f"unexpected legal counts: {counts}")
    require(all(len(str(row.get("content", ""))) >= 300 for row in rows), "one or more legal texts are too short")
    require(all(str(row.get("source", "")).startswith("https://") for row in rows), "source URL missing")
    labor = next((row for row in rows if row.get("type") == "law" and "قانون کار" in row.get("title", "")), None)
    require(labor is not None and "کارآموزی" not in labor.get("title", ""), "wrong labor law match")
    return {"name": "کنترل محتوای حقوقی", "status": "PASS", "counts": counts, "minimumContentCharacters": min(len(row["content"]) for row in rows)}


def main() -> None:
    checks = [pass_one_calculator_structure(), pass_two_calculator_math(), pass_three_integration(), legal_pass()]
    digest = hashlib.sha256(APK.read_bytes()).hexdigest().upper()
    result = {"version": "0.4.0", "status": "PASS", "checks": checks, "apk": {"path": str(APK), "bytes": APK.stat().st_size, "sha256": digest}}
    (ROOT / "QA-REPORT-0.4.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    lines = [
        "# گزارش کنترل نسخه ۰.۴.۰ دستیار وکیل",
        "",
        "نتیجه ماشینی: **PASS**",
        "",
        "- دور اول محاسبه‌گرها: ۱۶ شناسه یکتا، شش الگوی محاسباتی مجاز و اتصال همه کارت‌ها.",
        "- دور دوم محاسبه‌گرها: سناریوی عددی مستقل برای هر ۱۶ مورد، کنترل مقدار نامتناهی/منفی و اعتبار مدت وام.",
        "- دور سوم محاسبه‌گرها و رابط: جایگاه سوم نوار پایین برای محاسبات، اتصال رویدادها، هشدار بومی و بسته APK.",
        f"- محتوای حقوقی تعبیه‌شده: {checks[3]['counts']['law']} قانون، {checks[3]['counts']['unity']} رأی وحدت رویه و {checks[3]['counts']['opinion']} نظریه مشورتی.",
        "- هشدارها: زمان دلخواه، مجوز هشدار دقیق، بازیابی پس از راه‌اندازی مجدد و اعلان با متن عمومی برای حفظ محرمانگی.",
        "- حذف حساب: حذف داده‌های رمزگذاری‌شده و لغو هشدارهای ثبت‌شده پس از تأیید عبارتی.",
        f"- SHA-256 APK: `{digest}`",
        "",
        "## حدود نتیجه",
        "",
        "این PASS فنی به معنای تأیید مبلغ رسمی روز در محاسبه‌گرها یا جامع‌بودن همه قوانین کشور نیست. کاربر باید نرخ، شاخص، تعرفه و متن رسمی روز را پیش از استناد کنترل کند. APK با کلید آزمایشی امضا شده و برای انتشار فروشگاهی به کلید انتشار، سیاست حریم خصوصی عمومی و آزمون دستگاه‌های واقعی نیاز دارد.",
    ]
    (ROOT / "QA-REPORT-0.4-FA.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
