package ir.dadban.app;

import android.Manifest;
import android.app.Activity;
import android.app.AlarmManager;
import android.app.AlertDialog;
import android.app.KeyguardManager;
import android.app.PendingIntent;
import android.hardware.biometrics.BiometricPrompt;
import android.print.PrintManager;
import android.content.ActivityNotFoundException;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.CancellationSignal;
import android.provider.Settings;
import android.util.Base64;
import android.view.View;
import android.view.WindowManager;
import android.window.OnBackInvokedDispatcher;
import android.webkit.JavascriptInterface;
import android.webkit.JsResult;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.Executor;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import org.json.JSONArray;
import org.json.JSONObject;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

public final class MainActivity extends Activity {
    private static final int REQUEST_CREATE_WORD = 4101;
    private static final int REQUEST_DEVICE_CREDENTIAL = 4102;
    private static final int REQUEST_NOTIFICATIONS = 4103;
    private static final String KEY_ALIAS = "lawyer_assistant_secure_store_v1";
    private static final String PREFS_NAME = "lawyer_ciphertext_v1";
    private static final long AUTO_LOCK_DELAY_MS = 30_000L;
    private static final int AI_TIMEOUT_MS = 45_000;
    private static final Set<String> AI_PROVIDERS = new HashSet<>(Arrays.asList("openrouter", "groq", "huggingface"));
    private static final Set<String> ALLOWED_EXTERNAL_HOSTS = new HashSet<>(Arrays.asList(
            "chatgpt.com", "www.chatgpt.com", "qavanin.ir", "www.qavanin.ir",
            "rrk.ir", "www.rrk.ir", "eadil.com", "www.eadil.com",
            "rc.majlis.ir", "www.rc.majlis.ir", "nezamat.ir", "www.nezamat.ir",
            "lawlex.ir", "www.lawlex.ir", "1ghazi.pro", "www.1ghazi.pro",
            "google.com", "www.google.com", "maps.google.com"
    ));

    private WebView webView;
    private WebView printWebView;
    private final ExecutorService aiExecutor = Executors.newFixedThreadPool(3);
    private byte[] pendingWordBytes;
    private long backgroundedAt;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_SECURE);
        getWindow().getDecorView().setLayoutDirection(View.LAYOUT_DIRECTION_RTL);

        webView = new WebView(this);
        webView.setLayoutDirection(View.LAYOUT_DIRECTION_RTL);
        setContentView(webView);

        android.webkit.WebSettings settings = webView.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(false);
        settings.setDatabaseEnabled(false);
        settings.setCacheMode(android.webkit.WebSettings.LOAD_NO_CACHE);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setSupportMultipleWindows(false);
        settings.setBuiltInZoomControls(false);
        settings.setDisplayZoomControls(false);
        settings.setTextZoom(100);
        settings.setMediaPlaybackRequiresUserGesture(true);
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            settings.setMixedContentMode(android.webkit.WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            settings.setSafeBrowsingEnabled(true);
        }

        WebView.setWebContentsDebuggingEnabled(false);
        CookieManager.getInstance().setAcceptCookie(false);
        android.webkit.WebStorage.getInstance().deleteAllData();
        webView.clearCache(true);
        webView.clearFormData();
        webView.addJavascriptInterface(new NativeBridge(), "LawyerApp");
        webView.setWebViewClient(new SecureWebViewClient());
        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public boolean onJsAlert(WebView view, String url, String message, JsResult result) {
                Toast.makeText(MainActivity.this, message, Toast.LENGTH_LONG).show();
                result.confirm();
                return true;
            }
        });

        loadBundledApp();
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                    OnBackInvokedDispatcher.PRIORITY_DEFAULT,
                    this::handleBackPressed
            );
        }
    }

    private void loadBundledApp() {
        try {
            String html = readAsset("index.html");
            String styles = readAsset("styles.css");
            String legalData = Base64.encodeToString(readAsset("legal-data.json").getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
            String addressData = Base64.encodeToString(readAsset("address-data.json").getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
            String inflationData = Base64.encodeToString(readAsset("inflation-data.json").getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
            String inheritanceData = Base64.encodeToString(readAsset("inheritance-data.json").getBytes(StandardCharsets.UTF_8), Base64.NO_WRAP);
            String script = readAsset("app.js");
            html = html.replace("<link rel=\"stylesheet\" href=\"styles.css\">", "<style>" + styles + "</style>");
            html = html.replace("__LEGAL_DATA_B64__", legalData);
            html = html.replace("__ADDRESS_DATA_B64__", addressData);
            html = html.replace("__INFLATION_DATA_B64__", inflationData);
            html = html.replace("__INHERITANCE_DATA_B64__", inheritanceData);
            html = html.replace("<script src=\"app.js\" defer></script>", "<script>" + script + "</script>");
            webView.loadDataWithBaseURL("https://app.local/", html, "text/html", "UTF-8", null);
        } catch (IOException error) {
            toast("بارگذاری رابط برنامه ناموفق بود.");
        }
    }

    private String readAsset(String name) throws IOException {
        try (InputStream input = getAssets().open(name); ByteArrayOutputStream output = new ByteArrayOutputStream()) {
            byte[] buffer = new byte[8192];
            int count;
            while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
            return output.toString("UTF-8");
        }
    }

    private final class SecureWebViewClient extends WebViewClient {
        @Override
        public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
            Uri uri = request.getUrl();
            if ("file".equalsIgnoreCase(uri.getScheme())) return false;
            openExternalUri(uri);
            return true;
        }

        @Override
        @SuppressWarnings("deprecation")
        public boolean shouldOverrideUrlLoading(WebView view, String url) {
            Uri uri = Uri.parse(url);
            if ("file".equalsIgnoreCase(uri.getScheme())) return false;
            openExternalUri(uri);
            return true;
        }

    }

    private final class NativeBridge {
        @JavascriptInterface
        public String secureGet(String key) {
            if (!isAllowedStorageKey(key)) return "";
            return decryptPreference(key);
        }

        @JavascriptInterface
        public boolean securePut(String key, String value) {
            if (!isAllowedStorageKey(key) || value == null || value.length() > 2_000_000) return false;
            return encryptPreference(key, value);
        }

        @JavascriptInterface
        public void authenticateDevice() {
            runOnUiThread(MainActivity.this::showDeviceAuthentication);
        }

        @JavascriptInterface
        public boolean scheduleReminder(String id, long triggerAtMillis, String title, String text) {
            if (triggerAtMillis <= System.currentTimeMillis() || id == null || id.length() > 40) return false;
            if (!hasNotificationPermission()) {
                requestNotificationPermissionIfNeeded();
                return false;
            }
            return AlarmReceiver.schedule(MainActivity.this, id, triggerAtMillis);
        }

        @JavascriptInterface
        public void cancelReminder(String id) {
            if (id == null || id.length() > 40) return;
            AlarmReceiver.cancel(MainActivity.this, id);
        }

        @JavascriptInterface
        public boolean canScheduleExactReminders() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true;
            AlarmManager manager = (AlarmManager) getSystemService(Context.ALARM_SERVICE);
            return manager != null && manager.canScheduleExactAlarms();
        }

        @JavascriptInterface
        public void openAlarmSettings() {
            runOnUiThread(() -> {
                requestNotificationPermissionIfNeeded();
                try {
                    Intent intent;
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        intent = new Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
                                Uri.parse("package:" + getPackageName()));
                    } else {
                        intent = new Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                .putExtra(Settings.EXTRA_APP_PACKAGE, getPackageName());
                    }
                    startActivity(intent);
                } catch (ActivityNotFoundException error) {
                    startActivity(new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:" + getPackageName())));
                }
            });
        }

        @JavascriptInterface
        public void exportWord(String fileName, String documentXml) {
            if (documentXml == null || documentXml.length() > 5_000_000) return;
            runOnUiThread(() -> {
                try {
                    pendingWordBytes = createDocx(documentXml);
                    Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType("application/vnd.openxmlformats-officedocument.wordprocessingml.document")
                            .putExtra(Intent.EXTRA_TITLE, safeFileName(fileName, "گزارش-دستیار-وکیل.docx"));
                    startActivityForResult(intent, REQUEST_CREATE_WORD);
                } catch (IOException error) {
                    toast("ساخت فایل Word ناموفق بود.");
                }
            });
        }

        @JavascriptInterface
        public void printHtml(String title, String html) {
            if (html == null || html.length() > 5_000_000) return;
            runOnUiThread(() -> createPrintJob(limit(title, 80), html));
        }

        @JavascriptInterface
        public void openExternal(String url) {
            if (url == null || url.length() > 4096) return;
            runOnUiThread(() -> openExternalUri(Uri.parse(url)));
        }

        @JavascriptInterface
        public void shareText(String title, String text) {
            if (text == null || text.isEmpty() || text.length() > 50_000) return;
            runOnUiThread(() -> {
                Intent intent = new Intent(Intent.ACTION_SEND)
                        .setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, limit(title, 120))
                        .putExtra(Intent.EXTRA_TEXT, text);
                startActivity(Intent.createChooser(intent, "اشتراک‌گذاری امن"));
            });
        }

        @JavascriptInterface
        public void openDialer(String phone) {
            if (phone == null) return;
            String safe = phone.replaceAll("[^0-9+#*]", "");
            if (safe.isEmpty() || safe.length() > 24) return;
            runOnUiThread(() -> {
                try {
                    startActivity(new Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", safe, null)));
                } catch (ActivityNotFoundException error) {
                    toast("شماره‌گیر در دسترس نیست.");
                }
            });
        }

        @JavascriptInterface
        public void openMap(String query) {
            if (query == null || query.trim().isEmpty() || query.length() > 400) return;
            runOnUiThread(() -> {
                Uri geo = Uri.parse("geo:0,0?q=" + Uri.encode(query.trim()));
                try {
                    startActivity(new Intent(Intent.ACTION_VIEW, geo));
                } catch (ActivityNotFoundException error) {
                    openExternalUri(Uri.parse("https://www.google.com/maps/search/?api=1&query=" + Uri.encode(query.trim())));
                }
            });
        }

        @JavascriptInterface
        public void composeEmail(String to, String subject, String body) {
            if (!"majid.gharaee1369@gmail.com".equalsIgnoreCase(to)) return;
            runOnUiThread(() -> {
                Intent intent = new Intent(Intent.ACTION_SENDTO, Uri.fromParts("mailto", to, null))
                        .putExtra(Intent.EXTRA_SUBJECT, limit(subject, 160))
                        .putExtra(Intent.EXTRA_TEXT, limit(body, 5000));
                try {
                    startActivity(intent);
                } catch (ActivityNotFoundException error) {
                    toast("برنامه ایمیل در دسترس نیست.");
                }
            });
        }

        @JavascriptInterface
        public void confirmExit() {
            runOnUiThread(MainActivity.this::showExitConfirmation);
        }

        @JavascriptInterface
        public boolean saveAiCredential(String provider, String apiKey) {
            if (!AI_PROVIDERS.contains(provider) || apiKey == null) return false;
            String trimmed = apiKey.trim();
            if (trimmed.isEmpty()) {
                getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().remove("ai_key_" + provider).apply();
                return true;
            }
            if (trimmed.length() < 12 || trimmed.length() > 512 || trimmed.matches(".*\\s+.*")) return false;
            return encryptPreference("ai_key_" + provider, trimmed);
        }

        @JavascriptInterface
        public boolean hasAiCredential(String provider) {
            return AI_PROVIDERS.contains(provider) && !decryptPreference("ai_key_" + provider).isEmpty();
        }

        @JavascriptInterface
        public void askLegalAi(String provider, String model, String prompt, String requestId) {
            if (!AI_PROVIDERS.contains(provider) || prompt == null || prompt.isEmpty() || prompt.length() > 12_000
                    || requestId == null || requestId.length() > 80 || model == null || !model.matches("[A-Za-z0-9._:/-]{2,120}")) {
                sendAiResult(requestId, false, "درخواست نامعتبر است.");
                return;
            }
            String apiKey = decryptPreference("ai_key_" + provider);
            if (apiKey.isEmpty()) {
                sendAiResult(requestId, false, "کلید این ارائه‌دهنده تنظیم نشده است.");
                return;
            }
            aiExecutor.execute(() -> performAiRequest(provider, model, prompt, requestId, apiKey));
        }

        @JavascriptInterface
        public void deleteProfessionalData() {
            AlarmReceiver.cancelAll(MainActivity.this);
            pendingWordBytes = null;
            getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().clear().commit();
            try {
                KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
                keyStore.load(null);
                if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS);
            } catch (Exception ignored) {
                // Preferences are already removed; a stale orphan key contains no recoverable application data.
            }
        }
    }

    private boolean isAllowedStorageKey(String key) {
        return key != null && Arrays.asList(
                "clients", "matters", "hearings", "notes", "calculations", "officeSecurity", "officeAuthThrottle",
                "userProfile", "legalOrders", "typingOrders", "collaborators", "addresses", "aiSettings"
        ).contains(key);
    }

    private void performAiRequest(String provider, String model, String prompt, String requestId, String apiKey) {
        HttpURLConnection connection = null;
        try {
            String endpoint;
            if ("openrouter".equals(provider)) endpoint = "https://openrouter.ai/api/v1/chat/completions";
            else if ("groq".equals(provider)) endpoint = "https://api.groq.com/openai/v1/chat/completions";
            else endpoint = "https://router.huggingface.co/v1/chat/completions";
            connection = (HttpURLConnection) new URL(endpoint).openConnection();
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod("POST");
            connection.setConnectTimeout(AI_TIMEOUT_MS);
            connection.setReadTimeout(AI_TIMEOUT_MS);
            connection.setDoOutput(true);
            connection.setRequestProperty("Content-Type", "application/json; charset=utf-8");
            connection.setRequestProperty("Authorization", "Bearer " + apiKey);
            if ("openrouter".equals(provider)) {
                connection.setRequestProperty("HTTP-Referer", "https://dastyar-vakil.local");
                connection.setRequestProperty("X-Title", "Dastyar Vakil");
            }
            JSONObject body = new JSONObject();
            body.put("model", model);
            body.put("temperature", 0.15);
            body.put("max_tokens", 1800);
            JSONArray messages = new JSONArray();
            messages.put(new JSONObject().put("role", "system").put("content",
                    "شما دستیار پژوهش حقوق ایران هستید. پاسخ را فارسی، محتاط، منبع محور و ساختاریافته بنویسید. از جعل ماده، رأی، نظریه، تاریخ یا منبع خودداری کنید. هر عدم قطعیت را صریح بگویید؛ میان اطلاعات، تحلیل و پیشنهاد تفکیک کنید؛ و یادآور شوید متن رسمی روز و اسناد پرونده باید توسط وکیل کنترل شود."));
            messages.put(new JSONObject().put("role", "user").put("content", prompt));
            body.put("messages", messages);
            byte[] bytes = body.toString().getBytes(StandardCharsets.UTF_8);
            connection.setFixedLengthStreamingMode(bytes.length);
            try (OutputStream output = connection.getOutputStream()) { output.write(bytes); }
            int code = connection.getResponseCode();
            InputStream stream = code >= 200 && code < 300 ? connection.getInputStream() : connection.getErrorStream();
            StringBuilder raw = new StringBuilder();
            if (stream != null) try (BufferedReader reader = new BufferedReader(new InputStreamReader(stream, StandardCharsets.UTF_8))) {
                String line; while ((line = reader.readLine()) != null && raw.length() < 300_000) raw.append(line);
            }
            if (code < 200 || code >= 300) throw new IOException("HTTP " + code + ": " + limit(raw.toString(), 500));
            JSONObject response = new JSONObject(raw.toString());
            JSONArray choices = response.optJSONArray("choices");
            String answer = choices == null || choices.length() == 0 ? "" : choices.getJSONObject(0).getJSONObject("message").optString("content", "");
            if (answer.trim().isEmpty()) throw new IOException("پاسخ معتبری از سرویس دریافت نشد.");
            sendAiResult(requestId, true, answer.trim());
        } catch (Exception error) {
            sendAiResult(requestId, false, "ارتباط با سرویس ناموفق بود: " + limit(error.getMessage(), 500));
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private void sendAiResult(String requestId, boolean success, String message) {
        if (webView == null) return;
        String safeId = JSONObject.quote(requestId == null ? "" : requestId);
        String safeMessage = JSONObject.quote(message == null ? "" : message);
        runOnUiThread(() -> webView.evaluateJavascript(
                "window.onLegalAiResult&&window.onLegalAiResult(" + safeId + "," + success + "," + safeMessage + ")", null));
    }

    private SecretKey getOrCreateSecretKey() throws Exception {
        KeyStore keyStore = KeyStore.getInstance("AndroidKeyStore");
        keyStore.load(null);
        if (keyStore.containsAlias(KEY_ALIAS)) return ((KeyStore.SecretKeyEntry) keyStore.getEntry(KEY_ALIAS, null)).getSecretKey();
        KeyGenerator generator = KeyGenerator.getInstance("AES", "AndroidKeyStore");
        android.security.keystore.KeyGenParameterSpec spec = new android.security.keystore.KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                android.security.keystore.KeyProperties.PURPOSE_ENCRYPT | android.security.keystore.KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true)
                .build();
        generator.init(spec);
        return generator.generateKey();
    }

    private boolean encryptPreference(String key, String value) {
        try {
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, getOrCreateSecretKey());
            cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
            byte[] ciphertext = cipher.doFinal(value.getBytes(StandardCharsets.UTF_8));
            String packed = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + "." + Base64.encodeToString(ciphertext, Base64.NO_WRAP);
            return getSharedPreferences(PREFS_NAME, MODE_PRIVATE).edit().putString(key, packed).commit();
        } catch (Exception error) {
            return false;
        }
    }

    private String decryptPreference(String key) {
        try {
            String packed = getSharedPreferences(PREFS_NAME, MODE_PRIVATE).getString(key, "");
            if (packed == null || packed.isEmpty()) return "";
            String[] parts = packed.split("\\.", 2);
            if (parts.length != 2) return "";
            byte[] iv = Base64.decode(parts[0], Base64.NO_WRAP);
            byte[] ciphertext = Base64.decode(parts[1], Base64.NO_WRAP);
            try {
                Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
                cipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), new GCMParameterSpec(128, iv));
                cipher.updateAAD(key.getBytes(StandardCharsets.UTF_8));
                return new String(cipher.doFinal(ciphertext), StandardCharsets.UTF_8);
            } catch (Exception legacyCiphertext) {
                Cipher legacyCipher = Cipher.getInstance("AES/GCM/NoPadding");
                legacyCipher.init(Cipher.DECRYPT_MODE, getOrCreateSecretKey(), new GCMParameterSpec(128, iv));
                String plaintext = new String(legacyCipher.doFinal(ciphertext), StandardCharsets.UTF_8);
                encryptPreference(key, plaintext);
                return plaintext;
            }
        } catch (Exception error) {
            return "";
        }
    }

    private void showDeviceAuthentication() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            try {
                BiometricPrompt.Builder builder = new BiometricPrompt.Builder(this)
                        .setTitle("بازکردن دستیار وکیل")
                        .setSubtitle("اثر انگشت یا قفل امن دستگاه را تأیید کنید");
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    builder.setAllowedAuthenticators(
                            android.hardware.biometrics.BiometricManager.Authenticators.BIOMETRIC_STRONG |
                                    android.hardware.biometrics.BiometricManager.Authenticators.DEVICE_CREDENTIAL
                    );
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    builder.setDeviceCredentialAllowed(true);
                } else {
                    builder.setNegativeButton("استفاده از پترن یا PIN", getMainExecutor(), (dialog, which) -> showDeviceCredential());
                }
                BiometricPrompt prompt = builder.build();
                Executor executor = getMainExecutor();
                prompt.authenticate(new CancellationSignal(), executor, new BiometricPrompt.AuthenticationCallback() {
                    @Override public void onAuthenticationSucceeded(BiometricPrompt.AuthenticationResult result) { sendAuthResult(true, ""); }
                    @Override public void onAuthenticationError(int code, CharSequence message) {
                        sendAuthResult(false, message == null ? "احراز هویت انجام نشد." : message.toString());
                    }
                    @Override public void onAuthenticationFailed() { toast("اثر انگشت شناسایی نشد."); }
                });
                return;
            } catch (Exception ignored) {
                showDeviceCredential();
                return;
            }
        }
        showDeviceCredential();
    }

    private void showDeviceCredential() {
        KeyguardManager manager = (KeyguardManager) getSystemService(Context.KEYGUARD_SERVICE);
        if (manager == null || !manager.isDeviceSecure()) {
            sendAuthResult(false, "ابتدا قفل امن دستگاه را در تنظیمات Android فعال کنید.");
            return;
        }
        Intent intent = manager.createConfirmDeviceCredentialIntent("بازکردن دستیار وکیل", "پترن، PIN یا رمز دستگاه را وارد کنید");
        if (intent != null) startActivityForResult(intent, REQUEST_DEVICE_CREDENTIAL);
        else sendAuthResult(false, "قفل دستگاه در دسترس نیست.");
    }

    private void sendAuthResult(boolean success, String message) {
        String safeMessage = message == null ? "" : message.replace("\\", "\\\\").replace("'", "\\'").replace("\n", " ");
        webView.evaluateJavascript("window.onDeviceAuthResult(" + success + ",'" + safeMessage + "')", null);
    }

    private void requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            runOnUiThread(() -> requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQUEST_NOTIFICATIONS));
        }
    }

    private boolean hasNotificationPermission() {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU
                || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED;
    }

    private void openExternalUri(Uri uri) {
        if (uri == null || !"https".equalsIgnoreCase(uri.getScheme()) || !ALLOWED_EXTERNAL_HOSTS.contains(uri.getHost())) {
            toast("برای امنیت، فقط پیوندهای HTTPS تأییدشده باز می‌شوند.");
            return;
        }
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE));
        } catch (ActivityNotFoundException error) {
            toast("مرورگری برای بازکردن پیوند پیدا نشد.");
        }
    }

    private void createPrintJob(String title, String html) {
        printWebView = new WebView(this);
        printWebView.getSettings().setJavaScriptEnabled(false);
        printWebView.getSettings().setAllowFileAccess(false);
        printWebView.getSettings().setAllowContentAccess(false);
        printWebView.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView view, String url) {
                PrintManager manager = (PrintManager) getSystemService(Context.PRINT_SERVICE);
                if (manager != null) manager.print(
                        title,
                        view.createPrintDocumentAdapter(title),
                        new android.print.PrintAttributes.Builder().build()
                );
            }
        });
        printWebView.loadDataWithBaseURL("https://local.invalid/", html, "text/html", "UTF-8", null);
    }

    private byte[] createDocx(String documentXml) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        try (ZipOutputStream zip = new ZipOutputStream(bytes)) {
            addZipEntry(zip, "[Content_Types].xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\"><Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/><Override PartName=\"/word/document.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/><Override PartName=\"/word/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/></Types>");
            addZipEntry(zip, "_rels/.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"word/document.xml\"/></Relationships>");
            addZipEntry(zip, "word/_rels/document.xml.rels", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/></Relationships>");
            addZipEntry(zip, "word/styles.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?><w:styles xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii=\"Tahoma\" w:hAnsi=\"Tahoma\" w:cs=\"Tahoma\"/><w:sz w:val=\"22\"/><w:rtl/></w:rPr></w:rPrDefault><w:pPrDefault><w:pPr><w:bidi/><w:jc w:val=\"right\"/></w:pPr></w:pPrDefault></w:docDefaults><w:style w:type=\"paragraph\" w:styleId=\"Title\"><w:name w:val=\"Title\"/><w:rPr><w:b/><w:sz w:val=\"36\"/></w:rPr></w:style><w:style w:type=\"paragraph\" w:styleId=\"Heading1\"><w:name w:val=\"Heading 1\"/><w:rPr><w:b/><w:sz w:val=\"28\"/><w:color w:val=\"17324D\"/></w:rPr></w:style></w:styles>");
            addZipEntry(zip, "word/document.xml", documentXml);
        }
        return bytes.toByteArray();
    }

    private void addZipEntry(ZipOutputStream zip, String name, String content) throws IOException {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(content.getBytes(StandardCharsets.UTF_8));
        zip.closeEntry();
    }

    private String safeFileName(String candidate, String fallback) {
        if (candidate == null) return fallback;
        String safe = candidate.replaceAll("[\\\\/:*?\"<>|\\r\\n]", "-").trim();
        return safe.isEmpty() || safe.length() > 120 ? fallback : safe;
    }

    private String limit(String value, int maximum) {
        if (value == null) return "";
        return value.length() <= maximum ? value : value.substring(0, maximum);
    }

    private void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_LONG).show();
    }

    private void handleBackPressed() {
        if (webView == null) {
            showExitConfirmation();
            return;
        }
        webView.evaluateJavascript(
                "(function(){try{return typeof window.handleNativeBack==='function'?window.handleNativeBack():'exit';}catch(e){return 'exit';}})()",
                result -> {
                    if (result == null || "\"exit\"".equals(result) || "null".equals(result)) {
                        showExitConfirmation();
                    }
                }
        );
    }

    private void showExitConfirmation() {
        if (isFinishing() || isDestroyed()) return;
        new AlertDialog.Builder(this)
                .setTitle("خروج از دستیار وکیل")
                .setMessage("آیا قصد خروج از برنامه را دارید؟")
                .setNegativeButton("خیر، بمان", null)
                .setPositiveButton("بله، خارج شو", (dialog, which) -> finishAndRemoveTask())
                .setCancelable(true)
                .show();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_DEVICE_CREDENTIAL) {
            sendAuthResult(resultCode == RESULT_OK, resultCode == RESULT_OK ? "" : "احراز هویت لغو شد.");
            return;
        }
        if (requestCode == REQUEST_CREATE_WORD && resultCode == RESULT_OK && data != null && data.getData() != null && pendingWordBytes != null) {
            try (OutputStream output = getContentResolver().openOutputStream(data.getData(), "w")) {
                if (output == null) throw new IOException("No output stream");
                output.write(pendingWordBytes);
                output.flush();
                toast("فایل Word با موفقیت ذخیره شد.");
            } catch (IOException error) {
                toast("ذخیره فایل Word ناموفق بود.");
            } finally {
                pendingWordBytes = null;
            }
        }
    }

    @Override protected void onSaveInstanceState(Bundle outState) { super.onSaveInstanceState(outState); }
    @Override protected void onStop() { super.onStop(); if (!isChangingConfigurations()) backgroundedAt = System.currentTimeMillis(); }
    @Override protected void onResume() { super.onResume(); if (backgroundedAt > 0 && System.currentTimeMillis() - backgroundedAt >= AUTO_LOCK_DELAY_MS && webView != null) webView.evaluateJavascript("window.lockOfficeIfNeeded&&window.lockOfficeIfNeeded()", null); backgroundedAt = 0; }
    @Override public void onBackPressed() { handleBackPressed(); }
    @Override protected void onDestroy() { aiExecutor.shutdownNow(); if (printWebView != null) printWebView.destroy(); if (webView != null) { webView.removeJavascriptInterface("LawyerApp"); webView.loadUrl("about:blank"); webView.destroy(); webView = null; } super.onDestroy(); }
}
