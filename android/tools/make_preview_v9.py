from pathlib import Path
import base64

root = Path(__file__).resolve().parents[1]
assets = root / "app" / "src" / "main" / "assets"
out_dir = root / "qa-v9"
out_dir.mkdir(parents=True, exist_ok=True)
html = (assets / "index.html").read_text(encoding="utf-8")
html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>' + (assets / "styles.css").read_text(encoding="utf-8") + '</style>')
for marker, filename in [
    ("__LEGAL_DATA_B64__", "legal-data.json"),
    ("__ADDRESS_DATA_B64__", "address-data.json"),
    ("__INFLATION_DATA_B64__", "inflation-data.json"),
    ("__INHERITANCE_DATA_B64__", "inheritance-data.json"),
]:
    html = html.replace(marker, base64.b64encode((assets / filename).read_bytes()).decode("ascii"))
html = html.replace('<script src="app.js" defer></script>', '<script>window.qaErrors=[];window.addEventListener("error",e=>window.qaErrors.push(e.message+" @ "+e.lineno));</script><script>' + (assets / "app.js").read_text(encoding="utf-8") + '</script>')
(out_dir / "preview-v9.html").write_text(html, encoding="utf-8")
before, closing = html.rsplit("</body>", 1)
qa = before + "<script>" + (root / "tools" / "qa_harness_v9.js").read_text(encoding="utf-8") + "</script></body>" + closing
(out_dir / "qa-v9.html").write_text(qa, encoding="utf-8")
security_html = html.replace('<script>window.qaErrors=[];', '<script>localStorage.clear();</script><script>window.qaErrors=[];', 1)
security_body, security_tail = security_html.rsplit("</body>", 1)
security_qa = security_body + "<script>" + (root / "tools" / "security_ui_harness_v070.js").read_text(encoding="utf-8") + "</script></body>" + security_tail
(out_dir / "security-qa-v9.html").write_text(security_qa, encoding="utf-8")

def scenario(name: str, javascript: str):
    body, tail = html.rsplit("</body>", 1)
    (out_dir / f"scenario-{name}.html").write_text(body + f"<script>window.addEventListener('load',()=>setTimeout(()=>{{{javascript}}},350));</script></body>" + tail, encoding="utf-8")

scenario("home", "showPage('home');")
scenario("calculators", "showPage('calculators');")
scenario("addresses", "showPage('addresses');")
scenario("unity", "showPage('unity');renderUnityYears();")
scenario("opinions", "showPage('opinions');renderOpinionYears();")
scenario("assistant", "showPage('assistant');")
scenario("about", "showPage('about');")
scenario("law-categories", "showPage('library');document.querySelector('[data-filter=law]').click();")
scenario("law-detail", "openDocument(laws.find(x=>normalizeSearch(x.title).includes('قانون مدنی')).id);")
print(out_dir)
