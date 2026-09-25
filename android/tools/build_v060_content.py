#!/usr/bin/env python3
"""Build the v0.6 offline datasets from the user-supplied sources.

The script deliberately distinguishes between full-text court decisions and
the indexed previews of advisory opinions.  It never labels an excerpt as a
full text.  Address OCR is filtered to a conservative Persian character set;
uncertain item names receive a neutral page/entry label instead of exposing
garbled OCR as an institution name.
"""

from __future__ import annotations

import html
import json
import re
import time
import urllib.parse
import urllib.request
from pathlib import Path
from zipfile import ZipFile

from lxml import etree
from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "app" / "src" / "main" / "assets"
ADDRESS_OCR = Path(r"C:\Users\User\Documents\Codex\2026-09-23\legal-app-v060\tmp\addresses-halves")
INFLATION_PDF = Path(r"C:\Users\User\Desktop\شاخص تورم بانک مرکزی.pdf")
INHERITANCE_DOCX = Path(r"C:\Users\User\Desktop\خلاصه ترتیب سهم الارث و طبقات مختلف به صورت دسته بندی شده.docx")
UA = "DastyarVakil/0.6 (offline legal data builder)"


PAGE_CATEGORIES = {
    1: "واحدهای ستادی دادگستری استان تهران",
    2: "واحدهای قضایی شهر تهران", 3: "واحدهای قضایی شهر تهران",
    4: "نواحی دادسرای عمومی و انقلاب تهران", 5: "نواحی دادسرای عمومی و انقلاب تهران",
    6: "مجتمع‌های شورای حل اختلاف تهران و شهرستان‌ها",
    7: "مجتمع‌های شورای حل اختلاف تهران و شهرستان‌ها",
    8: "مجتمع‌های شورای حل اختلاف تهران و شهرستان‌ها",
    9: "مجتمع‌های شورای حل اختلاف تهران و شهرستان‌ها",
    10: "دادسراهای عمومی و انقلاب شهرستان‌های استان تهران",
    11: "دادگاه‌های انقلاب اسلامی استان تهران",
    12: "سازمان‌ها و نهادهای تابعه قوه قضاییه در تهران",
    13: "سازمان‌ها و نهادهای تابعه قوه قضاییه در تهران",
    14: "سازمان‌ها و نهادهای تابعه قوه قضاییه در تهران",
    15: "دفاتر خدمات الکترونیک قضایی تهران", 16: "دفاتر خدمات الکترونیک قضایی تهران",
    17: "زندان‌ها و ندامتگاه‌های استان تهران",
    18: "کلانتری‌ها و مراجع انتظامی استان تهران",
    19: "کلانتری‌ها و مراجع انتظامی استان تهران",
    20: "کلانتری‌ها و مراجع انتظامی استان تهران",
    21: "کلانتری‌ها و مراجع انتظامی استان تهران",
    22: "ادارات ثبت اسناد و املاک و اجرای ثبت تهران",
    23: "مراکز پزشکی قانونی و ادارات اوقاف تهران",
    24: "کانون‌های وکلای دادگستری کشور", 25: "کانون‌های وکلای دادگستری کشور",
    26: "شعب دادگاه صلح شهر تهران", 27: "شعب دادگاه صلح شهر تهران",
}

COMMON_FIXES = {
    "ي": "ی", "ك": "ک", "ۀ": "ه", "ؤ": "و",
    "نهران": "تهران", "ثهران": "تهران", "تهرزن": "تهران", "آهرا": "تهران",
    "اسنان": "استان", "دادکستری": "دادگستری", "داد گستری": "دادگستری",
    "قضابی": "قضایی", "فضابی": "قضایی", "قشسابی": "قضایی", "فسایی": "قضایی",
    "مجنمع": "مجتمع", "جنمع": "مجتمع", "نمع": "مجتمع",
    "عیابان": "خیابان", "خبابان": "خیابان", "ثلفن": "تلفن", "تافن": "تلفن",
    "حللوی": "حقوقی", "حفوقی": "حقوقی", "حانوقی": "حقوقی", "کبفری": "کیفری",
    "فضات": "قضات", "داد گاه": "دادگاه", "کدیستی": "کدپستی", "کدیسنی": "کدپستی",
    "داد گستر ی": "دادگستری", "عمینی": "خمینی", "ساخنمان": "ساختمان",
    "پست فضایی": "پست قضایی", "صلع": "ضلع", "مجامع": "مجتمع", "طبله": "طبقه",
    "زررزمین": "زیرزمین", "فشسابی": "قضایی", "دادگاه ها یک": "دادگاه کیفری یک",
}

TITLE_MARKERS = (
    "دادگستری", "دادگاه", "دادسرا", "مجتمع", "کانون وکلا", "کانون وکلای",
    "کلانتری", "پلیس", "پزشکی قانونی", "اداره ثبت", "اجرای ثبت", "دفتر خدمات",
    "زندان", "ندامتگاه", "بازداشتگاه", "شورای حل اختلاف", "سازمان", "اداره کل",
    "دفتر حمایت", "ابلاغ", "نظارت", "معاونت", "مرکز",
)


def get(url: str) -> tuple[bytes, dict[str, str]]:
    last_error = None
    for attempt in range(4):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=180) as response:
                return response.read(8_000_000), dict(response.headers)
        except Exception as error:
            last_error = error
            time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Source fetch failed after retries: {url}: {last_error}")


def strip_html(value: str) -> str:
    value = html.unescape(re.sub(r"<[^>]+>", " ", value or ""))
    value = re.sub(r"[\u200c\u200e\u200f\ufeff]", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def fa_to_en(value: str) -> str:
    return value.translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789"))


def normalize_ocr(value: str) -> str:
    value = value.replace("\u200c", " ").replace("\ufeff", " ")
    for bad, good in COMMON_FIXES.items():
        value = value.replace(bad, good)
    # Keep only Persian/Arabic letters, digits and conservative punctuation.
    value = re.sub(r"[^\u0600-\u06ff۰-۹0-9\s،؛:()./\-–—]", " ", value)
    value = re.sub(r"\s+", " ", value).strip(" -–—،؛|_")
    return value


def title_quality(value: str) -> bool:
    if not (5 <= len(value) <= 145):
        return False
    letters = re.findall(r"[\u0600-\u06ff]", value)
    if len(letters) < 5 or not any(marker in value for marker in TITLE_MARKERS):
        return False
    noisy = re.findall(r"(?:\b[آ-ی]\b\s*){3,}|[۰-۹]{5,}", value)
    return not noisy


def display_title_quality(value: str) -> bool:
    """Reject OCR fragments that look like an address or a broken heading."""
    if re.search(r"[۰-۹0-9]", value):
        return False
    if any(word in value for word in ("خیابان", "کوچه", "پلاک", "طبقه", "تلفن", "فکس", "رسیده", "روبه روی", "کدپستی", ":", "(", ")")):
        return False
    if len(re.findall(r"\b[آ-ی]\b", value)) > 1:
        return False
    safe_prefix = re.match(r"^(?:اداره(?: کل)?|معاونت|دفتر|ابلاغ|نظارت|هیأت|مرکز|کلینیک|مجتمع|دادگاه|دادسرا|کانون|کلانتری|پلیس|پزشکی قانونی|اجرای ثبت|زندان|ندامتگاه|شورای حل اختلاف|سازمان|واحد)", value)
    words = value.split()
    return bool(safe_prefix) and 2 <= len(words) <= 14 and title_quality(value)


def build_addresses() -> dict:
    records: list[dict] = []
    category_counts: dict[str, int] = {v: 0 for v in dict.fromkeys(PAGE_CATEGORIES.values())}
    for page in range(1, 28):
        category = PAGE_CATEGORIES[page]
        for side in ("R", "L"):
            src = ADDRESS_OCR / f"page-{page:02d}-{side}-p6.txt"
            lines = [normalize_ocr(x) for x in src.read_text(encoding="utf-8", errors="replace").splitlines()]
            lines = [x for x in lines if len(x) >= 3 and "کم اسکنر" not in x and "CamScanner" not in x]
            starts = [i for i, line in enumerate(lines) if title_quality(line) and not any(k in line for k in ("خیابان", "تلفن", "فکس", "کدپستی"))]
            for pos, start in enumerate(starts):
                end = starts[pos + 1] if pos + 1 < len(starts) else min(len(lines), start + 8)
                block = [x for x in lines[start:end] if x]
                if not block:
                    continue
                title = block[0]
                address_lines = [x for x in block[1:] if len(x) > 5]
                address = "، ".join(address_lines[:6])
                if len(address) < 12:
                    continue
                category_counts[category] += 1
                ordinal = category_counts[category]
                if not display_title_quality(title):
                    title = f"{category} — مورد {ordinal}"
                phones = re.findall(r"(?:۰?۲۱|021)?[\s-]?[۰-۹0-9]{7,11}", address)
                phone = re.sub(r"\s", "", phones[0]) if phones else ""
                records.append({
                    "id": f"addr-{page:02d}-{side.lower()}-{ordinal:03d}",
                    "category": category,
                    "page": page,
                    "side": side,
                    "title": title,
                    "address": address,
                    "phone": phone,
                    "mapQuery": re.sub(r"(?:تلفن|فکس|کدپستی).*", "", address)[:280].strip(" ،"),
                    "source": "فهرست نشانی‌های مرتبط حقوقی",
                    "verification": "بازخوانی و پالایش نویسه‌ای نسخه ۰.۶",
                })
    payload = {
        "categories": [{"title": k, "count": category_counts[k]} for k in category_counts],
        "records": records,
        "qa": {
            "recordCount": len(records),
            "visibleFieldsContainLatinLetters": any(
                re.search(r"[A-Za-z]", " ".join(str(r[k]) for k in ("title", "address", "phone", "mapQuery")))
                for r in records
            ),
            "sourcePages": 27,
        },
    }
    (ASSETS / "address-data.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return payload["qa"]


def number(value: str):
    if value == "-":
        return None
    return float(value.replace("/", "."))


def build_inflation() -> dict:
    text = PdfReader(str(INFLATION_PDF)).pages[0].extract_text(extraction_mode="layout")
    months = ["فروردین", "اردیبهشت", "خرداد", "تیر", "مرداد", "شهریور", "مهر", "آبان", "آذر", "دی", "بهمن", "اسفند"]
    years = {}
    for line in text.splitlines():
        if not re.search(r"\b(?:13|14)\d{2}\s*$", line):
            continue
        parts = line.split()
        if len(parts) != 15:
            raise RuntimeError(f"Unexpected inflation row: {parts}")
        year = parts[-1]
        change, average = number(parts[0]), number(parts[1])
        monthly = list(reversed([number(v) for v in parts[2:14]]))
        years[year] = {"average": average, "changePercent": change, "months": dict(zip(months, monthly))}
    payload = {
        "baseYear": 1395,
        "formula": "اصل دین × شاخص زمان پرداخت ÷ شاخص زمان سررسید",
        "months": months,
        "years": years,
        "coverage": {"from": 1375, "to": 1405, "lastAvailable": "مرداد ۱۴۰۵"},
        "source": "شاخص تورم بانک مرکزی.pdf؛ جدول ارسالی کاربر با درج dadhesab.com",
    }
    (ASSETS / "inflation-data.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return {"years": len(years), "monthsWithValues": sum(v is not None for y in years.values() for v in y["months"].values())}


def docx_paragraphs(path: Path) -> list[str]:
    with ZipFile(path) as archive:
        root = etree.fromstring(archive.read("word/document.xml"))
    ns = {"w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main"}
    out = []
    for paragraph in root.xpath(".//w:p", namespaces=ns):
        text = "".join(paragraph.xpath(".//w:t/text()", namespaces=ns)).strip()
        text = re.sub(r"\s+", " ", text)
        if text:
            out.append(text)
    return out


def build_inheritance() -> dict:
    notes = docx_paragraphs(INHERITANCE_DOCX)
    payload = {
        "source": "خلاصه ترتیب سهم الارث و طبقات مختلف به صورت دسته بندی شده.docx و چهار تصویر جدول ارسالی کاربر",
        "legalScope": "مواد ۸۶۱ تا ۹۴۹ قانون مدنی؛ محاسبه پس از کسر حقوق و دیون مقدم ترکه",
        "supportedEngine": "طبقه اول شامل زوج یا زوجه، پدر، مادر، پسر و دختر",
        "rules": [
            {"case": "زوج با وجود اولاد", "share": "۱/۴"},
            {"case": "زوج بدون اولاد", "share": "۱/۲"},
            {"case": "زوجه با وجود اولاد", "share": "۱/۸"},
            {"case": "زوجه بدون اولاد", "share": "۱/۴"},
            {"case": "یک دختر و نبود پسر", "share": "۱/۲ به فرض؛ باقیمانده حسب ترکیب وراث"},
            {"case": "دو دختر یا بیشتر و نبود پسر", "share": "۲/۳ به فرض؛ باقیمانده حسب ترکیب وراث"},
            {"case": "پسر و دختر", "share": "باقیمانده به نسبت دو سهم پسر و یک سهم دختر"},
            {"case": "مادر با وجود اولاد یا حاجب", "share": "۱/۶"},
            {"case": "پدر با وجود اولاد", "share": "۱/۶ و در برخی ترکیب‌ها رد/باقیمانده طبق قانون"},
            {"case": "فقط پدر و مادر", "share": "مادر ۱/۳ و پدر ۲/۳؛ با لحاظ حاجب مادر"},
            {"case": "یک خواهر یا برادر مادری", "share": "۱/۶"},
            {"case": "چند خواهر یا برادر مادری", "share": "۱/۳ مشترک و مساوی"},
            {"case": "خواهر و برادر ابوینی یا ابی", "share": "مذکر دو برابر مؤنث"},
            {"case": "جد و جده مادری", "share": "سهم شاخه مادری بالسویه"},
            {"case": "عمو و عمه یا دایی و خاله", "share": "بر پایه شاخه پدری/مادری و قواعد طبقه سوم"},
            {"case": "استثنای پسرعموی ابوینی و عموی ابی", "share": "پسرعموی ابوینی مانع ارث عموی ابی است"},
        ],
        "sourceNotes": notes,
    }
    (ASSETS / "inheritance-data.json").write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    return {"paragraphs": len(notes), "rules": len(payload["rules"])}


def parse_year(value: str) -> str | None:
    value = fa_to_en(strip_html(value))
    match = re.search(r"\b(13\d{2}|14\d{2})[/.\-]", value)
    return match.group(1) if match else None


def build_unity_records() -> list[dict]:
    output = []
    for page in range(1, 22):
        url = f"https://nezamat.ir/wp-json/wp/v2/posts?categories=115&per_page=30&page={page}&_fields=id,link,title,content,date"
        body, _ = get(url)
        posts = json.loads(body)
        for post in posts:
            title = strip_html(post.get("title", {}).get("rendered", ""))
            title_ascii = fa_to_en(title)
            if "وحدت رویه" not in title or "دیوان عالی" not in title:
                continue
            year = parse_year(title)
            if not year or not 1370 <= int(year) <= 1405:
                continue
            content = strip_html(post.get("content", {}).get("rendered", ""))
            if len(content) < 400:
                continue
            num = re.search(r"شماره\s+([۰-۹0-9]+)", title)
            output.append({
                "id": f"unity-{post['id']}", "type": "unity", "typeLabel": "رأی وحدت رویه",
                "title": title, "meta": f"سال {year} • متن کامل آفلاین",
                "summary": content[:260].rstrip(" .،") + "…", "materials": f"شماره {num.group(1) if num else post['id']}",
                "source": post["link"], "status": "متن کامل منبع", "content": content, "year": year,
            })
        time.sleep(0.1)
    unique = {x["id"]: x for x in output}
    return sorted(unique.values(), key=lambda x: (x["year"], fa_to_en(x["title"])), reverse=True)


def opinion_page(year: int, page: int) -> tuple[list[dict], int]:
    url = f"https://lawlex.ir/opinions?year={year}&page={page}"
    body, _ = get(url)
    source = body.decode("utf-8", "replace")
    max_page = max([int(x) for x in re.findall(rf"/opinions\?year={year}&amp;page=(\d+)", source)] or [1])
    pattern = re.compile(r'<a class="row" href="(/opinions/opinion-[^"]+)">\s*<div class="row-title">(.*?)</div>\s*<div class="row-meta">(.*?)</div>\s*<div class="row-preview">(.*?)</div>', re.S)
    items = []
    for href, title, meta, preview in pattern.findall(source):
        title, meta, preview = strip_html(title), strip_html(meta), strip_html(preview)
        items.append({
            "id": "opinion-" + href.rsplit("opinion-", 1)[-1], "type": "opinion", "typeLabel": "نظریه مشورتی",
            "title": title, "meta": f"سال {year} • نمایه آفلاین", "summary": preview,
            "materials": meta, "source": "https://lawlex.ir" + href,
            "status": "نمایه و چکیده؛ متن کامل در منبع", "content": preview, "year": str(year),
        })
    return items, max_page


def build_opinion_records() -> list[dict]:
    output = []
    for year in range(1396, 1406):
        first, max_page = opinion_page(year, 1)
        output.extend(first)
        for page in range(2, max_page + 1):
            items, _ = opinion_page(year, page)
            output.extend(items)
            time.sleep(0.04)
    unique = {x["id"]: x for x in output}
    return sorted(unique.values(), key=lambda x: (x["year"], fa_to_en(x["title"])), reverse=True)


def build_legal() -> dict:
    base = json.loads((ASSETS / "legal-data.json").read_text(encoding="utf-8"))
    retained = [x for x in base if x.get("type") not in {"unity", "opinion"}]
    unity = build_unity_records()
    # The Lawlex year endpoint currently exposes only a subset of recent years.
    # Preserve previously retrieved opinions instead of silently replacing a
    # larger verified index with a sparse response.
    opinions = [x for x in base if x.get("type") == "opinion"]
    records = retained + unity + opinions
    (ASSETS / "legal-data.json").write_text(json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    years = range(1370, 1406)
    return {
        "total": len(records), "unity": len(unity), "opinions": len(opinions),
        "unityByYear": {str(y): sum(x["year"] == str(y) for x in unity) for y in years},
        "opinionByYear": {str(y): sum(x["year"] == str(y) for x in opinions) for y in years},
        "opinionCoverageNote": "Lawlex listing index; full text is not claimed for indexed previews",
    }


if __name__ == "__main__":
    result = {
        "inflation": build_inflation(),
        "inheritance": build_inheritance(),
        "addresses": build_addresses(),
        "legal": build_legal(),
    }
    report = ROOT / "CONTENT-COVERAGE-v0.6.0.json"
    report.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False, indent=2))
