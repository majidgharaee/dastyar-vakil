# تغییرات دستیار وکیل 10.0.0

## داده و اتصال ابری

- منبع اصلی فهرست حقوقی از فایل ثابت `legal-data.json` به `public.legal_catalog_current`، `public.search_legal_catalog` و `public.legal_category_catalog_counts` منتقل شد.
- منبع اصلی نشانی‌ها از `address-data.json` به `public.directory_current`، `public.search_directory`، `public.directory_group_counts` و `public.directory_subgroup_counts` منتقل شد.
- برای هر دو مجموعه، cache پایدار SQLite و fallback آفلاین اضافه شد؛ شکست شبکه cache سالم قبلی را پاک نمی‌کند.
- اپ فقط کلید عمومی Supabase با قالب `sb_publishable_...` را می‌پذیرد. service-role و secret در کلاینت، سورس و artifact وجود ندارد.

## کنترل علمی منابع حقوقی

- وضعیت‌های `content_status`، `verification_status` و `rag_eligible` در کارت و صفحه جزئیات منبع نمایش داده می‌شوند.
- مدخل‌های `catalog_only` صریحاً «فقط عنوان» معرفی می‌شوند.
- prompt هوش مصنوعی استفاده مستند از هر رکورد `rag_eligible=false`، `catalog_only` یا `unverified` را منع می‌کند.
- دسته‌بندی‌های `pending_qa` با هشدار مستقل نشان داده می‌شوند.

## Directory

- گروه‌ها و زیرگروه‌ها از شمارنده‌های داینامیک backend خوانده و cache می‌شوند.
- نشانی، تلفن، وضعیت فعالیت، سطح اطمینان، وضعیت راستی‌آزمایی، منبع و لینک نقشه در cache آفلاین نگهداری می‌شوند.
- عضویت‌های چندگانه گروه/زیرگروه در فیلتر آفلاین حفظ می‌شوند.

## ارتقا و سازگاری

- package بدون تغییر: `ir.dadban.app`.
- نسخه جدید: `versionName=10.0.0` و `versionCode=11`.
- SharedPreferences رمزگذاری‌شده، Android Keystore alias و داده‌های محلی v9 حذف یا reset نمی‌شوند.
- cacheهای ابری در دیتابیس‌های مستقل نگهداری می‌شوند و جای داده‌های حرفه‌ای کاربر را نمی‌گیرند.
- APK و AAB با همان گواهی انتشار v9 امضا می‌شوند.

## دیتابیس

- migrationهای اعمال‌شده 018 تا 028 از ledger واقعی پروژه DEV به `supabase/migrations/` mirror شدند.
