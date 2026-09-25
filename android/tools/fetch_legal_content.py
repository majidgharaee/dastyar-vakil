#!/usr/bin/env python3
"""Build the offline legal library used by Dastyar Vakil.

The generated JSON keeps the full rendered text, source URL and retrieval date.
It deliberately reports its finite coverage instead of claiming to mirror every
Iranian legal source. Run this script again before each release.
"""

from __future__ import annotations

import html
import json
import re
import time
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from html.parser import HTMLParser
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "app" / "src" / "main" / "assets" / "legal-data.json"
UA = "DastyarVakilLegalLibrary/0.5 (+offline legal research index)"
RETRIEVED = "۱۴۰۵/۰۶/۳۰"
APPROVED_HOSTS = {"nezamat.ir", "www.nezamat.ir", "1ghazi.pro", "www.1ghazi.pro", "lawlex.ir", "www.lawlex.ir"}


def get(url: str) -> str:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname not in APPROVED_HOSTS or parsed.username or parsed.password:
        raise ValueError(f"Unapproved source URL: {url}")
    request = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(request, timeout=60) as response:
        final = urllib.parse.urlparse(response.geturl())
        if final.scheme != "https" or final.hostname not in APPROVED_HOSTS:
            raise ValueError(f"Unapproved redirect target: {response.geturl()}")
        payload = response.read(5_000_001)
        if len(payload) > 5_000_000:
            raise ValueError("Source response exceeds 5 MB")
        return payload.decode("utf-8", "replace")


def validate_record(record: dict) -> None:
    required = {"id", "type", "title", "content", "source"}
    if not required.issubset(record):
        raise ValueError(f"Record missing fields: {record.get('id', '?')}")
    if record["type"] not in {"law", "unity", "opinion"}:
        raise ValueError(f"Unexpected record type: {record['type']}")
    for key in required:
        value = str(record[key])
        if len(value) > 1_500_000 or re.search(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", value):
            raise ValueError(f"Unsafe or oversized {key}: {record.get('id', '?')}")
    source = urllib.parse.urlparse(record["source"])
    if source.scheme != "https" or source.hostname not in APPROVED_HOSTS:
        raise ValueError(f"Unapproved record source: {record['source']}")


def clean(value: str) -> str:
    value = html.unescape(re.sub(r"<[^>]+>", " ", value or ""))
    value = re.sub(r"[\u200c\u200f\ufeff]", " ", value)
    return re.sub(r"\s+", " ", value).strip()


class TextExtractor(HTMLParser):
    def __init__(self, selector_class: str | None = None):
        super().__init__(convert_charrefs=True)
        self.selector_class = selector_class
        self.depth = 0
        self.capture = selector_class is None
        self.skip = 0
        self.parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag in {"script", "style", "svg", "nav", "footer"}:
            self.skip += 1
            return
        if self.selector_class and not self.capture:
            classes = set(attrs.get("class", "").split())
            if self.selector_class in classes:
                self.capture = True
                self.depth = 1
                return
        elif self.capture:
            self.depth += 1
        if self.capture and tag in {"p", "div", "section", "article", "h1", "h2", "h3", "h4", "li", "br", "tr"}:
            self.parts.append("\n")

    def handle_endtag(self, tag):
        if tag in {"script", "style", "svg", "nav", "footer"} and self.skip:
            self.skip -= 1
            return
        if self.capture:
            self.depth -= 1
            if self.selector_class and self.depth <= 0:
                self.capture = False

    def handle_data(self, data):
        if self.capture and not self.skip:
            self.parts.append(data)

    def text(self) -> str:
        value = html.unescape("".join(self.parts)).replace("\r", "")
        value = re.sub(r"[ \t\u200c\u200f\ufeff]+", " ", value)
        value = re.sub(r"\n\s*\n+", "\n\n", value)
        return value.strip()


class LinkExtractor(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.links: list[tuple[str, str]] = []
        self.href: str | None = None
        self.text_parts: list[str] = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            self.href = dict(attrs).get("href")
            self.text_parts = []

    def handle_data(self, data):
        if self.href is not None:
            self.text_parts.append(data)

    def handle_endtag(self, tag):
        if tag == "a" and self.href is not None:
            self.links.append((self.href, clean(" ".join(self.text_parts))))
            self.href = None


def normalize(value: str) -> str:
    value = clean(value).replace("ي", "ی").replace("ك", "ک")
    return re.sub(r"[^\wآ-ی]+", " ", value).strip().lower()


def wp_search(title: str) -> dict:
    query = urllib.parse.quote(title)
    url = f"https://nezamat.ir/wp-json/wp/v2/search?search={query}&per_page=100"
    results = json.loads(get(url))
    wanted = normalize(title)
    if not results:
        raise RuntimeError(f"No Nezamat result for {title}")

    def score(item: dict) -> tuple[float, int]:
        candidate = normalize(item.get("title", ""))
        exact = int(candidate == wanted)
        starts = int(candidate.startswith(wanted) or wanted.startswith(candidate))
        return exact * 10 + starts * 3 + SequenceMatcher(None, wanted, candidate).ratio(), -len(candidate)

    return max(results, key=score)


def wp_law(title: str, item_id: str) -> dict:
    result = wp_search(title)
    post = json.loads(get(f"https://nezamat.ir/wp-json/wp/v2/posts/{result['id']}"))
    rendered = post.get("content", {}).get("rendered", "")
    extractor = TextExtractor()
    extractor.feed(rendered)
    text = extractor.text()
    if len(text) < 400:
        raise RuntimeError(f"Nezamat text too short for {title}: {len(text)}")
    actual_title = clean(post.get("title", {}).get("rendered", title))
    return {
        "id": item_id,
        "type": "law",
        "typeLabel": "قانون",
        "title": actual_title,
        "meta": f"متن کامل آفلاین • بازیابی {RETRIEVED}",
        "summary": text[:220].rstrip(" .،") + "…",
        "materials": "جست‌وجو در متن کامل و شماره مواد",
        "source": post.get("link") or result.get("url"),
        "status": "متن کامل منبع",
        "content": text,
    }


LAW_TITLES = [
    ("قانون مدنی", "full-law-civil"),
    ("قانون آیین دادرسی دادگاههای عمومی و انقلاب در امور مدنی", "full-law-civil-procedure"),
    ("قانون اجرای احکام مدنی", "full-law-civil-enforcement"),
    ("قانون حمایت خانواده مصوب ۱۳۹۱", "full-law-family"),
    ("قانون نحوه اجرای محکومیت های مالی", "full-law-financial-judgments"),
    ("قانون صدور چک", "full-law-cheque"),
    ("قانون کار مصوب ۱۳۶۹", "full-law-labor"),
    ("قانون تجارت الکترونیکی", "full-law-ecommerce"),
    ("قانون ثبت اسناد و املاک", "full-law-registration"),
    ("قانون داوری تجاری بین المللی", "full-law-arbitration"),
    ("قانون مسئولیت مدنی", "full-law-liability"),
    ("قانون الزام به ثبت رسمی معاملات اموال غیرمنقول", "full-law-mandatory-registration"),
    ("قانون مجازات اسلامی مصوب ۱۳۹۲", "full-law-penal"),
    ("کتاب پنجم قانون مجازات اسلامی تعزیرات و مجازات های بازدارنده", "full-law-taazirat"),
    ("قانون آیین دادرسی کیفری", "full-law-criminal-procedure"),
]


def title_from_page(page: str) -> str:
    match = re.search(r"<title>(.*?)</title>", page, re.I | re.S)
    return clean(match.group(1).split("|")[0]) if match else "سند حقوقی"


def latest_rulings(limit: int = 20) -> list[dict]:
    base = "https://1ghazi.pro"
    page = get(base + "/section/rulings")
    links = LinkExtractor()
    links.feed(page)
    output, seen = [], set()
    for href, label in links.links:
        if not re.fullmatch(r"/item/\d+", href or "") or "وحدت رویه" not in label:
            continue
        number_match = re.search(r"شماره\s+([۰-۹0-9]+)", label)
        number = number_match.group(1) if number_match else href.rsplit("/", 1)[-1]
        if number in seen:
            continue
        seen.add(number)
        source = base + href
        item_page = get(source)
        extractor = TextExtractor("ruling-document")
        extractor.feed(item_page)
        text = extractor.text()
        if len(text) < 500:
            continue
        title = title_from_page(item_page)
        output.append({
            "id": f"unity-{number}", "type": "unity", "typeLabel": "رأی وحدت رویه",
            "title": title, "meta": f"متن کامل آفلاین • بازیابی {RETRIEVED}",
            "summary": text[:220].rstrip(" .،") + "…", "materials": f"شماره {number}",
            "source": source, "status": "متن کامل منبع", "content": text,
        })
        if len(output) >= limit:
            break
        time.sleep(0.12)
    return output


def latest_opinions(limit: int = 20) -> list[dict]:
    base = "https://lawlex.ir"
    page = get(base + "/opinions?year=1404")
    links = LinkExtractor()
    links.feed(page)
    output, seen = [], set()
    for href, label in links.links:
        if not re.fullmatch(r"/opinions/opinion-[\w-]+", href or "") or href in seen:
            continue
        seen.add(href)
        source = base + href
        item_page = get(source)
        extractor = TextExtractor("article-text")
        extractor.feed(item_page)
        text = extractor.text()
        if len(text) < 250:
            continue
        title = title_from_page(item_page)
        number = clean(label).split("مورخ")[0].replace("نظریه مشورتی", "").strip()
        output.append({
            "id": f"opinion-{len(output)+1}", "type": "opinion", "typeLabel": "نظریه مشورتی",
            "title": title, "meta": f"متن کامل پرسش و پاسخ • بازیابی {RETRIEVED}",
            "summary": text[:220].rstrip(" .،") + "…", "materials": number,
            "source": source, "status": "متن کامل منبع", "content": text,
        })
        if len(output) >= limit:
            break
        time.sleep(0.12)
    return output


def main() -> None:
    records: list[dict] = []
    failures: list[str] = []
    for title, item_id in LAW_TITLES:
        try:
            records.append(wp_law(title, item_id))
            print(f"LAW OK: {title}")
        except Exception as error:
            failures.append(f"{title}: {error}")
            print(f"LAW FAILED: {title}: {error}")
    try:
        rulings = latest_rulings()
        records.extend(rulings)
        print(f"RULINGS OK: {len(rulings)}")
    except Exception as error:
        failures.append(f"rulings: {error}")
    try:
        opinions = latest_opinions()
        records.extend(opinions)
        print(f"OPINIONS OK: {len(opinions)}")
    except Exception as error:
        failures.append(f"opinions: {error}")

    for record in records:
        validate_record(record)
    OUT.write_text(json.dumps(records, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    manifest = {
        "retrieved": RETRIEVED,
        "recordCount": len(records),
        "lawCount": sum(r["type"] == "law" for r in records),
        "unityCount": sum(r["type"] == "unity" for r in records),
        "opinionCount": sum(r["type"] == "opinion" for r in records),
        "failures": failures,
        "sources": sorted({r["source"] for r in records}),
    }
    (ROOT / "LEGAL-CONTENT-MANIFEST-0.5.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
