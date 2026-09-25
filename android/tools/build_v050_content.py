from __future__ import annotations

import json
import re
from pathlib import Path


ROOT = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.5.0")
ASSETS = ROOT / "app" / "src" / "main" / "assets"
OCR = Path(r"C:\Users\User\Documents\Codex\2026-09-23\legal-app-v050\tmp\pdfs220")


CATEGORIES = {
    1: "واحدهای ستادی دادگستری استان تهران",
    2: "واحدهای قضایی شهر تهران", 3: "واحدهای قضایی شهر تهران",
    4: "نواحی دادسرای عمومی و انقلاب تهران", 5: "نواحی دادسرای عمومی و انقلاب تهران",
    6: "مجتمع‌های شورای حل اختلاف شهر، بخش‌ها و شهرستان‌های استان تهران",
    7: "مجتمع‌های شورای حل اختلاف شهر، بخش‌ها و شهرستان‌های استان تهران",
    8: "مجتمع‌های شورای حل اختلاف شهر، بخش‌ها و شهرستان‌های استان تهران",
    9: "مجتمع‌های شورای حل اختلاف شهر، بخش‌ها و شهرستان‌های استان تهران",
    10: "دادسرای عمومی و انقلاب شهرستان‌های استان تهران",
    11: "دادگاه‌های انقلاب اسلامی استان تهران",
    12: "سازمان‌ها و ارگان‌های تابعه قوه قضاییه مستقر در تهران",
    13: "سازمان‌ها و ارگان‌های تابعه قوه قضاییه مستقر در تهران",
    14: "سازمان‌ها و ارگان‌های تابعه قوه قضاییه مستقر در تهران",
    15: "دفاتر خدمات قضایی تهران", 16: "دفاتر خدمات قضایی تهران",
    17: "ندامتگاه‌های استان تهران",
    18: "نشانی کلانتری‌ها و مراجع انتظامی استان تهران",
    19: "نشانی کلانتری‌ها و مراجع انتظامی استان تهران",
    20: "نشانی کلانتری‌ها و مراجع انتظامی استان تهران",
    21: "نشانی کلانتری‌ها و مراجع انتظامی استان تهران",
    22: "ادارات ثبت اسناد و املاک و اجرای ثبت تهران",
    23: "مراکز پزشکی قانونی تهران",
    24: "کانون‌های وکلای دادگستری کشور", 25: "کانون‌های وکلای دادگستری کشور",
    26: "شعب دادگاه صلح شهر تهران", 27: "شعب دادگاه صلح شهر تهران",
}


def clean(text: str) -> str:
    text = text.replace("\ufeff", " ").replace("\u200e", " ").replace("\u200f", " ")
    text = re.sub(r"[\x00-\x1f]+", " ", text)
    text = re.sub(r"\s+", " ", text).strip(" -–—_|،؛")
    return text


def build_legal_json() -> int:
    source_path = ASSETS / "legal-data.js"
    if not source_path.exists():
        source_path = ROOT / "tools" / "legacy-legal-data.js"
    source = source_path.read_text(encoding="utf-8")
    match = re.search(r"window\.LEGAL_CONTENT\s*=\s*(\[.*\])\s*;?\s*$", source, re.S)
    if not match:
        raise RuntimeError("legal-data.js wrapper was not recognized")
    records = json.loads(match.group(1))
    (ASSETS / "legal-data.json").write_text(
        json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    return len(records)


def looks_meaningful(text: str) -> bool:
    if len(text) < 28 or "CamScanner" in text:
        return False
    compact = re.sub(r"\s", "", text)
    persian = len(re.findall(r"[\u0600-\u06ff]", text))
    return persian >= 12 and len(compact) >= 22


def build_address_json() -> int:
    records = []
    for page in range(1, 28):
        raw = (OCR / f"p4-{page:02d}.txt").read_text(encoding="utf-8", errors="replace")
        raw = raw.replace("\r", "")
        chunks = re.split(r"\n\s*\n+", raw)
        for idx, chunk in enumerate(chunks, 1):
            lines = [clean(line) for line in chunk.splitlines()]
            lines = [line for line in lines if line and "CamScanner" not in line]
            text = clean(" | ".join(lines))
            if not looks_meaningful(text):
                continue
            title = clean(lines[0])[:180]
            phones = re.findall(r"(?:۰۲۱|021)?[\s-]?[۰-۹0-9]{7,11}", text)
            phone = clean(phones[0]) if phones else ""
            category = CATEGORIES[page]
            if page == 11 and any(word in text for word in ("سازمان", "اداره کل", "تعزیرات", "روزنامه رسمی", "کارشناسان")):
                category = "سازمان‌ها و ارگان‌های تابعه قوه قضاییه مستقر در تهران"
            if page == 17 and not any(word in text for word in ("ندامتگاه", "زندان", "بازداشتگاه")):
                category = "نشانی کلانتری‌ها و مراجع انتظامی استان تهران"
            if page == 23 and "اوقاف" in text:
                category = "ادارات اوقاف تهران"
            records.append({
                "id": f"pdf-{page:02d}-{idx:03d}",
                "category": category,
                "page": page,
                "title": title or f"رکورد صفحه {page}",
                "address": text,
                "phone": phone,
                "mapQuery": clean(text.replace("تلفن", "").replace("فکس", ""))[:300],
                "source": "فایل فهرست نشانی‌های مرتبط حقوقی",
                "verification": "نیازمند بازبینی پیش از مراجعه",
            })
    (ASSETS / "address-data.json").write_text(
        json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8"
    )
    return len(records)


if __name__ == "__main__":
    legal_count = build_legal_json()
    address_count = build_address_json()
    print(json.dumps({"legal": legal_count, "addresses": address_count}, ensure_ascii=False))
