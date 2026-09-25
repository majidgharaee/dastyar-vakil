from pathlib import Path
import base64

root = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.5.0")
assets = root / "app" / "src" / "main" / "assets"
out = root / "manual-build-v50" / "preview-v050.html"
html = (assets / "index.html").read_text(encoding="utf-8")
html = html.replace('<link rel="stylesheet" href="styles.css">', '<style>' + (assets / "styles.css").read_text(encoding="utf-8") + '</style>')
for marker, filename in [("__LEGAL_DATA_B64__", "legal-data.json"), ("__ADDRESS_DATA_B64__", "address-data.json")]:
    html = html.replace(marker, base64.b64encode((assets / filename).read_bytes()).decode("ascii"))
html = html.replace('<script src="app.js" defer></script>', '<script>' + (assets / "app.js").read_text(encoding="utf-8") + '</script>')
out.write_text(html, encoding="utf-8")
print(out)
