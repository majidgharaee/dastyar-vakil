#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(r"F:\Codex\Dadban\work\dastyar-vakil-0.7.0")
JS = (ROOT / "app/src/main/assets/app.js").read_text(encoding="utf-8")
JAVA = (ROOT / "app/src/main/java/ir/dadban/app/MainActivity.java").read_text(encoding="utf-8")
BUILD = (ROOT / "tools/build_release_v070.ps1").read_text(encoding="utf-8")

checks = {
    "pin_change_step_up": "requireFreshAuth(state.officeSecurity.pinEnabled?'تغییر رمز دفتر':'افزودن رمز دفتر'" in JS,
    "pin_disable_step_up": "requireFreshAuth('غیرفعال‌کردن رمز دفتر'" in JS,
    "device_factor_step_up": "requireFreshAuth(wanted?'فعال‌کردن قفل دستگاه':'غیرفعال‌کردن قفل دستگاه'" in JS,
    "delete_step_up": "requireFreshAuth('تأیید نهایی حذف همه اطلاعات',eraseLocalAccount)" in JS,
    "one_shot_action": "pendingSensitiveAction=null" in JS and "completeSensitiveAction" in JS,
    "auth_timeout": "120000" in JS and "cancelSensitiveAction" in JS,
    "pin_kdf": "PBKDF2" in JS and "210000" in JS and "legacyPinHash" in JS,
    "notification_gate": "if (!hasNotificationPermission())" in JAVA and "requestNotificationPermissionIfNeeded();\n                return false;" in JAVA,
    "aad_binding": "cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8))" in JAVA,
    "key_erasure": "keyStore.deleteEntry(KEY_ALIAS)" in JAVA,
    "release_signing_fail_closed": all(name in BUILD for name in ("DV_KEYSTORE_PATH","DV_KEY_ALIAS","DV_KEYSTORE_PASSWORD","DV_KEY_PASSWORD","DV_SIGNER_SHA256")),
    "debug_credentials_absent": "pass:" + "android" not in BUILD and "dadban-" + "debug.keystore" not in BUILD,
    "unverified_addresses_hidden": "trustedCatalog=verifiedPlaces" in JS,
    "browser_plaintext_fallback_removed": "localStorage.getItem(`lawyer_${key}`)" not in JS and "localStorage.setItem(`lawyer_${key}`" not in JS,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print("PASS: " + ", ".join(checks))
