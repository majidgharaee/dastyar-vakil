from pathlib import Path
import base64

root = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.6.0")
assets = root / "app" / "src" / "main" / "assets"
out_dir = root / "manual-build-v60"
out_dir.mkdir(parents=True, exist_ok=True)
out = out_dir / "preview-v060.html"
html = (assets / "index.html").read_text(encoding="utf-8")
html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>' + (assets / "styles.css").read_text(encoding="utf-8") + '</style>')
for marker, filename in [
    ("__LEGAL_DATA_B64__", "legal-data.json"),
    ("__ADDRESS_DATA_B64__", "address-data.json"),
    ("__INFLATION_DATA_B64__", "inflation-data.json"),
    ("__INHERITANCE_DATA_B64__", "inheritance-data.json"),
]:
    html = html.replace(marker, base64.b64encode((assets / filename).read_bytes()).decode("ascii"))
html = html.replace('<script src="app.js" defer></script>', '<script>' + (assets / "app.js").read_text(encoding="utf-8") + '</script>')
out.write_text(html, encoding="utf-8")
print(out)

qa = html.replace("<script>'use strict';", "<script>window.qaErrors=[];window.addEventListener('error',e=>window.qaErrors.push(e.message+' @ '+e.lineno));\n'use strict';", 1)
before, closing = qa.rsplit("</body>", 1)
qa = before + "<script>" + (root / "tools" / "qa_harness_v060.js").read_text(encoding="utf-8") + "</script></body>" + closing
qa_out = out_dir / "qa-v060.html"
qa_out.write_text(qa, encoding="utf-8")
print(qa_out)

def scenario(name: str, javascript: str):
    before, closing = html.rsplit("</body>", 1)
    target = out_dir / f"scenario-{name}.html"
    target.write_text(before + f"<script>window.addEventListener('load',()=>setTimeout(()=>{{{javascript}}},250));</script></body>" + closing, encoding="utf-8")
    print(target)

scenario("addresses", "document.querySelector('[data-page-link=addresses]').click();")
scenario("unity", "showPage('unity');renderUnityYears();")
scenario("opinions", "showPage('opinions');renderOpinionYears();")
scenario("inflation", "showPage('calculators');document.querySelector('[data-calculator=late]').click();")
scenario("inheritance", "showPage('calculators');document.querySelector('[data-calculator=inheritance]').click();")
