# گزارش QA دستیار وکیل 10.0.0

تاریخ آزمون: 1405-07-03 / 2026-09-25

## نتیجه

نسخه 10.0.0 از نظر build، lint، دسترسی عمومی API، کنترل منبع AI، حفظ داده محلی و امضای انتشار قبول شد. آزمون نصب و تعامل روی دستگاه فیزیکی انجام نشد، زیرا دستگاه یا emulator متصل در محیط build وجود نداشت؛ آزمون UI با Edge/Playwright در viewport موبایل اجرا شد.

## build و سازگاری ارتقا

- `assembleDebug`: PASS
- Android lint: PASS با صفر error
- `assembleRelease` و R8/minification: PASS
- `bundleRelease`: PASS
- package: `ir.dadban.app` بدون تغییر
- `versionName=10.0.0`, `versionCode=11`
- گواهی release با هویت امضای مورد تأیید v9 کنترل شد؛ APK دارای امضای v1/v2/v3 و AAB دارای امضای JAR معتبر است.
- مسیرهای ذخیره داده حرفه‌ای v9 و کلید Android Keystore بدون حذف یا تغییر باقی مانده‌اند.

## آزمون API با نقش عمومی اپ

همه endpointهای زیر با publishable key و بدون service-role پاسخ HTTP 200 دادند:

- `legal_catalog_current`
- `legal_category_catalog_counts`
- `search_legal_catalog`
- `directory_current`
- `directory_group_counts`
- `directory_subgroup_counts`
- `search_directory`

شمارش مشاهده‌شده:

- کاتالوگ حقوقی: 1196
- دسته‌های حقوقی: 65
- `catalog_only`: 1196
- `unverified`: 1196
- `rag_eligible`: 0
- Directory canonical: 399
- گروه‌ها: 13
- زیرگروه‌ها: 68

## آزمون UI، محتوا و امنیت

- harness نسخه 10: PASS 14/14
- fallback محتوایی v9: 25 متن قانون، 305 رأی وحدت رویه و 2323 نمایه نظریه مشورتی، همگی حفظ شدند.
- نمایش دسته‌های ابری حقوقی و Directory: PASS
- نمایش مستقل `catalog_only`, `unverified`, `rag_eligible=false`: PASS
- هشدار منع استناد AI برای رکورد غیرمجاز: PASS
- نمایش هشدار Directory برای `needs_verification`: PASS
- حفظ رکورد داده محلی کاربر در چرخه بارگذاری: PASS
- JavaScript runtime errors: صفر
- Security Advisor پروژه Supabase: صفر finding
- secret scan: هیچ مقدار service-role، `sb_secret_`، private key، database URL یا token خصوصی پیدا نشد؛ نام نقش `service_role` در SQL migration صرفاً مجوز سمت سرور است.

## محدودیت و اقدام پس از تحویل

- نصب مستقیم APK روی یک دستگاه v9 واقعی و آزمون upgrade-in-place باید پیش از انتشار عمومی انجام شود.
- داده فعلی کاتالوگ صرفاً عنوان است؛ تا زمانی که متن رسمی و verification وارد نشده، مقدار `rag_eligible` باید صفر بماند.
- Performance Advisor فقط unused-indexهای INFO در محیط DEV کم‌ترافیک گزارش می‌کند؛ برای جلوگیری از حذف زودهنگام indexهای معماری، تغییری اعمال نشد.
