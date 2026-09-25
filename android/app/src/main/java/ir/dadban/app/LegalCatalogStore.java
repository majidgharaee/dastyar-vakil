package ir.dadban.app;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Locale;
import java.util.UUID;

final class LegalCatalogStore extends SQLiteOpenHelper {
    private static final String DB_NAME = "legal_catalog_v1.db";
    private static final int DB_VERSION = 2;
    private static final int PAGE_SIZE = 500;
    private static final int MAX_PAGE_BYTES = 5_000_000;

    LegalCatalogStore(Context context) { super(context, DB_NAME, null, DB_VERSION); }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
        createCloudTables(db);
    }

    private static void createCloudTables(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE categories (category_code TEXT PRIMARY KEY, category_id TEXT, name_fa TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, total_count INTEGER NOT NULL DEFAULT 0, catalog_only_count INTEGER NOT NULL DEFAULT 0, full_text_count INTEGER NOT NULL DEFAULT 0, official_verified_count INTEGER NOT NULL DEFAULT 0, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE TABLE authorities (id TEXT PRIMARY KEY, title TEXT NOT NULL, normalized_title TEXT NOT NULL, authority_type_code TEXT NOT NULL, authority_type_name_fa TEXT, category_code TEXT, category_name_fa TEXT, subtopic TEXT, content_status_code TEXT NOT NULL, verification_status_code TEXT NOT NULL, effect_status_code TEXT NOT NULL, has_text INTEGER NOT NULL DEFAULT 0, rag_eligible INTEGER NOT NULL DEFAULT 0, official_verified INTEGER NOT NULL DEFAULT 0, category_review_status TEXT, category_verified INTEGER NOT NULL DEFAULT 0, master_sort_order INTEGER NOT NULL DEFAULT 999999999, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE INDEX authorities_title_idx ON authorities(normalized_title)");
        db.execSQL("CREATE INDEX authorities_category_sort_idx ON authorities(category_code, master_sort_order)");
        db.execSQL("CREATE INDEX authorities_rag_idx ON authorities(rag_eligible)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion < 2) {
            db.execSQL("DROP TABLE IF EXISTS authority_categories");
            db.execSQL("DROP TABLE IF EXISTS taxonomies");
            db.execSQL("DROP TABLE IF EXISTS categories");
            db.execSQL("DROP TABLE IF EXISTS authorities");
            createCloudTables(db);
        }
    }

    JSONObject syncFromSupabase(String baseUrl, String publishableKey) throws IOException, JSONException {
        validateEndpoint(baseUrl, publishableKey);
        String marker = UUID.randomUUID().toString();
        SQLiteDatabase db = getWritableDatabase();
        int authorityCount = 0, categoryCount = 0;
        db.beginTransaction();
        try {
            JSONArray categories = requestArray(baseUrl, publishableKey,
                    "/rest/v1/legal_category_catalog_counts?select=category_id,category_code,category_name_fa,sort_order,total_count,catalog_only_count,full_text_count,official_verified_count&order=sort_order.asc,category_name_fa.asc", null);
            for (int i = 0; i < categories.length(); i++) {
                JSONObject x = categories.getJSONObject(i);
                ContentValues v = new ContentValues();
                v.put("category_code", x.optString("category_code", ""));
                putNullable(v, "category_id", nullable(x, "category_id"));
                v.put("name_fa", x.optString("category_name_fa", ""));
                v.put("sort_order", x.optInt("sort_order", 0));
                v.put("total_count", x.optInt("total_count", 0));
                v.put("catalog_only_count", x.optInt("catalog_only_count", 0));
                v.put("full_text_count", x.optInt("full_text_count", 0));
                v.put("official_verified_count", x.optInt("official_verified_count", 0));
                v.put("sync_marker", marker);
                db.insertWithOnConflict("categories", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                categoryCount++;
            }
            for (int offset = 0; ; offset += PAGE_SIZE) {
                JSONArray page = requestArray(baseUrl, publishableKey,
                        "/rest/v1/legal_catalog_current?select=authority_id,authority_type_code,authority_type_name_fa,title,content_status_code,verification_status_code,effect_status_code,category_code,category_name_fa,subtopic,has_text,rag_eligible,official_verified,master_sort_order,category_review_status,category_verified&order=master_sort_order.asc,title.asc&limit=" + PAGE_SIZE + "&offset=" + offset, null);
                for (int i = 0; i < page.length(); i++) {
                    JSONObject x = page.getJSONObject(i);
                    ContentValues v = new ContentValues();
                    v.put("id", x.getString("authority_id"));
                    String title = x.optString("title", "");
                    v.put("title", title);
                    v.put("normalized_title", normalize(title));
                    v.put("authority_type_code", x.optString("authority_type_code", "other_legal_document"));
                    putNullable(v, "authority_type_name_fa", nullable(x, "authority_type_name_fa"));
                    putNullable(v, "category_code", nullable(x, "category_code"));
                    putNullable(v, "category_name_fa", nullable(x, "category_name_fa"));
                    putNullable(v, "subtopic", nullable(x, "subtopic"));
                    v.put("content_status_code", x.optString("content_status_code", "catalog_only"));
                    v.put("verification_status_code", x.optString("verification_status_code", "unverified"));
                    v.put("effect_status_code", x.optString("effect_status_code", "unknown"));
                    v.put("has_text", x.optBoolean("has_text", false) ? 1 : 0);
                    v.put("rag_eligible", x.optBoolean("rag_eligible", false) ? 1 : 0);
                    v.put("official_verified", x.optBoolean("official_verified", false) ? 1 : 0);
                    putNullable(v, "category_review_status", nullable(x, "category_review_status"));
                    v.put("category_verified", x.optBoolean("category_verified", false) ? 1 : 0);
                    v.put("master_sort_order", x.optInt("master_sort_order", 999999999));
                    v.put("sync_marker", marker);
                    db.insertWithOnConflict("authorities", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                    authorityCount++;
                }
                if (page.length() < PAGE_SIZE) break;
            }
            JSONObject probe = new JSONObject();
            probe.put("p_query", "قانون مدنی"); probe.put("p_limit", 1); probe.put("p_offset", 0);
            requestArray(baseUrl, publishableKey, "/rest/v1/rpc/search_legal_catalog", probe);
            db.delete("authorities", "sync_marker<>?", new String[]{marker});
            db.delete("categories", "sync_marker<>?", new String[]{marker});
            putMeta(db, "last_synced_at", Long.toString(System.currentTimeMillis()));
            putMeta(db, "source", "public.legal_catalog_current/search_legal_catalog/legal_category_catalog_counts");
            db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
        JSONObject stats = getStats();
        stats.put("synced_authorities", authorityCount); stats.put("synced_categories", categoryCount);
        return stats;
    }

    JSONArray getCategories() throws JSONException {
        JSONArray out = new JSONArray();
        try (Cursor c = getReadableDatabase().rawQuery("SELECT category_code,name_fa,total_count,catalog_only_count,full_text_count,official_verified_count FROM categories ORDER BY sort_order,name_fa", null)) {
            while (c.moveToNext()) {
                JSONObject x = new JSONObject();
                x.put("id", c.getString(0)); x.put("code", c.getString(0)); x.put("name", c.getString(1));
                x.put("count", c.getInt(2)); x.put("catalog_only_count", c.getInt(3));
                x.put("full_text_count", c.getInt(4)); x.put("official_verified_count", c.getInt(5)); out.put(x);
            }
        }
        return out;
    }

    JSONArray queryAuthorities(String categoryCode, String query, int offset, int requestedLimit) throws JSONException {
        int limit = Math.max(1, Math.min(100, requestedLimit)), safeOffset = Math.max(0, offset);
        String normalizedQuery = normalize(query);
        StringBuilder sql = new StringBuilder("SELECT id,title,authority_type_code,authority_type_name_fa,category_code,category_name_fa,subtopic,content_status_code,verification_status_code,effect_status_code,has_text,rag_eligible,official_verified,category_review_status,category_verified,master_sort_order FROM authorities WHERE 1=1 ");
        ArrayList<String> args = new ArrayList<>();
        if (categoryCode != null && !categoryCode.trim().isEmpty()) { sql.append("AND category_code=? "); args.add(categoryCode.trim()); }
        if (!normalizedQuery.isEmpty()) { sql.append("AND normalized_title LIKE ? "); args.add("%" + normalizedQuery + "%"); }
        sql.append("ORDER BY master_sort_order,title LIMIT ? OFFSET ?"); args.add(Integer.toString(limit)); args.add(Integer.toString(safeOffset));
        JSONArray out = new JSONArray();
        try (Cursor c = getReadableDatabase().rawQuery(sql.toString(), args.toArray(new String[0]))) { while (c.moveToNext()) out.put(authorityFromCursor(c)); }
        return out;
    }

    JSONObject getAuthority(String id) throws JSONException {
        if (id == null || id.length() > 80) return null;
        try (Cursor c = getReadableDatabase().rawQuery("SELECT id,title,authority_type_code,authority_type_name_fa,category_code,category_name_fa,subtopic,content_status_code,verification_status_code,effect_status_code,has_text,rag_eligible,official_verified,category_review_status,category_verified,master_sort_order FROM authorities WHERE id=? LIMIT 1", new String[]{id})) {
            return c.moveToFirst() ? authorityFromCursor(c) : null;
        }
    }

    JSONObject getStats() throws JSONException {
        SQLiteDatabase db = getReadableDatabase(); JSONObject out = new JSONObject();
        out.put("authorities", scalarInt(db, "SELECT COUNT(*) FROM authorities"));
        out.put("categories", scalarInt(db, "SELECT COUNT(*) FROM categories"));
        out.put("catalog_only", scalarInt(db, "SELECT COUNT(*) FROM authorities WHERE content_status_code='catalog_only'"));
        out.put("unverified", scalarInt(db, "SELECT COUNT(*) FROM authorities WHERE verification_status_code='unverified'"));
        out.put("rag_eligible", scalarInt(db, "SELECT COUNT(*) FROM authorities WHERE rag_eligible=1"));
        out.put("last_synced_at", getMeta(db, "last_synced_at")); out.put("source", getMeta(db, "source")); return out;
    }

    private JSONObject authorityFromCursor(Cursor c) throws JSONException {
        JSONObject x = new JSONObject();
        x.put("id", c.getString(0)); x.put("title", c.getString(1)); x.put("type_code", c.getString(2));
        x.put("type_label", c.isNull(3) ? "مرجع حقوقی" : c.getString(3));
        x.put("category_code", c.isNull(4) ? JSONObject.NULL : c.getString(4)); x.put("category_name", c.isNull(5) ? JSONObject.NULL : c.getString(5));
        x.put("subtopic", c.isNull(6) ? JSONObject.NULL : c.getString(6)); x.put("content_status", c.getString(7));
        x.put("verification_status", c.getString(8)); x.put("effect_status", c.getString(9)); x.put("has_text", c.getInt(10) == 1);
        x.put("has_full_text", "full_text".equals(c.getString(7))); x.put("rag_eligible", c.getInt(11) == 1);
        x.put("official_verified", c.getInt(12) == 1); x.put("category_review_status", c.isNull(13) ? JSONObject.NULL : c.getString(13));
        x.put("category_verified", c.getInt(14) == 1); x.put("master_sort_order", c.getInt(15)); return x;
    }

    private JSONArray requestArray(String baseUrl, String key, String path, JSONObject body) throws IOException, JSONException {
        HttpURLConnection connection = null;
        try {
            connection = (HttpURLConnection)new URL(baseUrl.replaceAll("/+$", "") + path).openConnection();
            connection.setConnectTimeout(15_000); connection.setReadTimeout(30_000); connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod(body == null ? "GET" : "POST"); connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("apikey", key); connection.setRequestProperty("Authorization", "Bearer " + key);
            connection.setRequestProperty("User-Agent", "DastyarVakil/10.0.0");
            if (body != null) { connection.setDoOutput(true); connection.setRequestProperty("Content-Type", "application/json; charset=utf-8"); try (OutputStream output = connection.getOutputStream()) { output.write(body.toString().getBytes(StandardCharsets.UTF_8)); } }
            int status = connection.getResponseCode(); if (status < 200 || status >= 300) throw new IOException("Legal catalog API returned HTTP " + status);
            try (InputStream input = connection.getInputStream()) { return new JSONArray(readBounded(input, MAX_PAGE_BYTES)); }
        } finally { if (connection != null) connection.disconnect(); }
    }

    static void validateEndpoint(String baseUrl, String key) throws IOException {
        if (baseUrl == null || key == null) throw new IOException("Cloud data is not configured");
        URL url = new URL(baseUrl); String host = url.getHost() == null ? "" : url.getHost().toLowerCase(Locale.ROOT);
        if (!"https".equalsIgnoreCase(url.getProtocol()) || !host.endsWith(".supabase.co")) throw new IOException("Invalid cloud endpoint");
        if (!key.matches("^sb_publishable_[A-Za-z0-9_-]{20,}$")) throw new IOException("Only a Supabase publishable key is accepted by the Android client");
    }

    static String readBounded(InputStream input, int maxBytes) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream(); byte[] buffer = new byte[8192]; int total = 0, n;
        while ((n = input.read(buffer)) != -1) { total += n; if (total > maxBytes) throw new IOException("Cloud response exceeded safety limit"); out.write(buffer, 0, n); }
        return out.toString(StandardCharsets.UTF_8.name());
    }

    static String normalize(String value) {
        if (value == null) return "";
        return value.replace('ي', 'ی').replace('ى', 'ی').replace('ك', 'ک').replace('\u200c', ' ').replace('\u200f', ' ').replaceAll("[ًٌٍَُِّْـ]", "").replaceAll("[\\s\\u00A0]+", " ").trim().toLowerCase(Locale.ROOT);
    }

    private static String nullable(JSONObject x, String key) { return x.isNull(key) ? null : x.optString(key, null); }
    private static void putNullable(ContentValues v, String key, String value) { if (value == null) v.putNull(key); else v.put(key, value); }
    private int scalarInt(SQLiteDatabase db, String sql) { try (Cursor c = db.rawQuery(sql, null)) { return c.moveToFirst() ? c.getInt(0) : 0; } }
    private static void putMeta(SQLiteDatabase db, String key, String value) { ContentValues v = new ContentValues(); v.put("key", key); v.put("value", value == null ? "" : value); db.insertWithOnConflict("catalog_meta", null, v, SQLiteDatabase.CONFLICT_REPLACE); }
    private static String getMeta(SQLiteDatabase db, String key) { try (Cursor c = db.rawQuery("SELECT value FROM catalog_meta WHERE key=? LIMIT 1", new String[]{key})) { return c.moveToFirst() ? c.getString(0) : ""; } }
}
