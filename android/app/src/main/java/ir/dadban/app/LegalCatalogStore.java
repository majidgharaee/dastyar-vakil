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
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.UUID;

final class LegalCatalogStore extends SQLiteOpenHelper {
    private static final String DB_NAME = "legal_catalog_v1.db";
    private static final int DB_VERSION = 1;
    private static final int PAGE_SIZE = 1000;
    private static final int MAX_PAGE_BYTES = 5_000_000;

    LegalCatalogStore(Context context) {
        super(context, DB_NAME, null, DB_VERSION);
    }

    @Override
    public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE catalog_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
        db.execSQL("CREATE TABLE taxonomies (" +
                "id TEXT PRIMARY KEY, code TEXT NOT NULL UNIQUE, name_fa TEXT NOT NULL, " +
                "taxonomy_kind TEXT, app_default INTEGER NOT NULL DEFAULT 0, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE TABLE categories (" +
                "id TEXT PRIMARY KEY, taxonomy_id TEXT NOT NULL, taxonomy_code TEXT NOT NULL, " +
                "taxonomy_name_fa TEXT, taxonomy_kind TEXT, parent_id TEXT, category_code TEXT, " +
                "name_fa TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE INDEX categories_taxonomy_sort_idx ON categories(taxonomy_code, sort_order, name_fa)");
        db.execSQL("CREATE TABLE authorities (" +
                "id TEXT PRIMARY KEY, canonical_title TEXT NOT NULL, normalized_title TEXT, " +
                "authority_type_code TEXT NOT NULL, authority_type_name_fa TEXT, " +
                "content_status_code TEXT NOT NULL, verification_status_code TEXT NOT NULL, " +
                "effect_status_code TEXT NOT NULL, has_full_text INTEGER NOT NULL DEFAULT 0, " +
                "entity_resolution_review INTEGER NOT NULL DEFAULT 0, updated_at TEXT, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE INDEX authorities_title_idx ON authorities(normalized_title)");
        db.execSQL("CREATE INDEX authorities_type_idx ON authorities(authority_type_code)");
        db.execSQL("CREATE TABLE authority_categories (" +
                "authority_id TEXT NOT NULL, category_id TEXT NOT NULL, taxonomy_code TEXT NOT NULL, " +
                "relation_kind TEXT, confidence REAL, sync_marker TEXT NOT NULL, " +
                "PRIMARY KEY(authority_id, category_id, taxonomy_code))");
        db.execSQL("CREATE INDEX authority_categories_category_idx ON authority_categories(category_id, authority_id)");
        db.execSQL("CREATE INDEX authority_categories_authority_idx ON authority_categories(authority_id)");
    }

    @Override
    public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        throw new IllegalStateException("Unsupported legal catalog DB upgrade path: " + oldVersion + " -> " + newVersion);
    }

    JSONObject syncFromSupabase(String baseUrl, String publishableKey) throws IOException, JSONException {
        validateEndpoint(baseUrl, publishableKey);
        final String marker = UUID.randomUUID().toString();
        final SQLiteDatabase db = getWritableDatabase();
        int authorityCount = 0;
        int categoryCount = 0;
        int linkCount = 0;

        db.beginTransaction();
        try {
            JSONArray taxonomies = fetchArray(baseUrl, publishableKey,
                    "/rest/v1/legal_catalog_taxonomies_v1" +
                    "?select=id,code,name_fa,taxonomy_kind,app_default" +
                    "&order=app_default.desc,name_fa.asc&limit=5000");
            for (int i = 0; i < taxonomies.length(); i++) {
                JSONObject x = taxonomies.getJSONObject(i);
                ContentValues v = new ContentValues();
                v.put("id", x.getString("id"));
                v.put("code", x.getString("code"));
                v.put("name_fa", x.optString("name_fa", ""));
                putNullable(v, "taxonomy_kind", x.optString("taxonomy_kind", null));
                v.put("app_default", x.optBoolean("app_default", false) ? 1 : 0);
                v.put("sync_marker", marker);
                db.insertWithOnConflict("taxonomies", null, v, SQLiteDatabase.CONFLICT_REPLACE);
            }

            JSONArray categories = fetchArray(baseUrl, publishableKey,
                    "/rest/v1/legal_catalog_categories_v1" +
                    "?select=id,taxonomy_id,taxonomy_code,taxonomy_name_fa,taxonomy_kind,parent_id,category_code,name_fa,sort_order" +
                    "&order=taxonomy_code.asc,sort_order.asc,name_fa.asc&limit=5000");
            for (int i = 0; i < categories.length(); i++) {
                JSONObject x = categories.getJSONObject(i);
                ContentValues v = new ContentValues();
                v.put("id", x.getString("id"));
                v.put("taxonomy_id", x.getString("taxonomy_id"));
                v.put("taxonomy_code", x.getString("taxonomy_code"));
                putNullable(v, "taxonomy_name_fa", x.optString("taxonomy_name_fa", null));
                putNullable(v, "taxonomy_kind", x.optString("taxonomy_kind", null));
                putNullable(v, "parent_id", x.isNull("parent_id") ? null : x.optString("parent_id", null));
                putNullable(v, "category_code", x.isNull("category_code") ? null : x.optString("category_code", null));
                v.put("name_fa", x.optString("name_fa", ""));
                v.put("sort_order", x.optInt("sort_order", 0));
                v.put("sync_marker", marker);
                db.insertWithOnConflict("categories", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                categoryCount++;
            }

            for (int offset = 0; ; offset += PAGE_SIZE) {
                JSONArray page = fetchArray(baseUrl, publishableKey,
                        "/rest/v1/legal_catalog_authorities_v1" +
                        "?select=id,canonical_title,normalized_title,authority_type_code,authority_type_name_fa," +
                        "content_status_code,verification_status_code,effect_status_code,has_full_text,entity_resolution_review,updated_at" +
                        "&order=id.asc&limit=" + PAGE_SIZE + "&offset=" + offset);
                for (int i = 0; i < page.length(); i++) {
                    JSONObject x = page.getJSONObject(i);
                    ContentValues v = new ContentValues();
                    v.put("id", x.getString("id"));
                    v.put("canonical_title", x.optString("canonical_title", ""));
                    v.put("normalized_title", x.optString("normalized_title", ""));
                    v.put("authority_type_code", x.optString("authority_type_code", "other"));
                    v.put("authority_type_name_fa", x.optString("authority_type_name_fa", "سایر"));
                    v.put("content_status_code", x.optString("content_status_code", "catalog_only"));
                    v.put("verification_status_code", x.optString("verification_status_code", "unverified"));
                    v.put("effect_status_code", x.optString("effect_status_code", "unknown"));
                    v.put("has_full_text", x.optBoolean("has_full_text", false) ? 1 : 0);
                    v.put("entity_resolution_review", x.optBoolean("entity_resolution_review", false) ? 1 : 0);
                    putNullable(v, "updated_at", x.isNull("updated_at") ? null : x.optString("updated_at", null));
                    v.put("sync_marker", marker);
                    db.insertWithOnConflict("authorities", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                    authorityCount++;
                }
                if (page.length() < PAGE_SIZE) break;
            }

            for (int offset = 0; ; offset += PAGE_SIZE) {
                JSONArray page = fetchArray(baseUrl, publishableKey,
                        "/rest/v1/legal_catalog_authority_categories_v1" +
                        "?select=authority_id,category_id,taxonomy_code,relation_kind,confidence" +
                        "&order=authority_id.asc&limit=" + PAGE_SIZE + "&offset=" + offset);
                for (int i = 0; i < page.length(); i++) {
                    JSONObject x = page.getJSONObject(i);
                    ContentValues v = new ContentValues();
                    v.put("authority_id", x.getString("authority_id"));
                    v.put("category_id", x.getString("category_id"));
                    v.put("taxonomy_code", x.getString("taxonomy_code"));
                    putNullable(v, "relation_kind", x.isNull("relation_kind") ? null : x.optString("relation_kind", null));
                    if (x.isNull("confidence")) v.putNull("confidence");
                    else v.put("confidence", x.optDouble("confidence"));
                    v.put("sync_marker", marker);
                    db.insertWithOnConflict("authority_categories", null, v, SQLiteDatabase.CONFLICT_REPLACE);
                    linkCount++;
                }
                if (page.length() < PAGE_SIZE) break;
            }

            db.delete("authority_categories", "sync_marker<>?", new String[]{marker});
            db.delete("authorities", "sync_marker<>?", new String[]{marker});
            db.delete("categories", "sync_marker<>?", new String[]{marker});
            db.delete("taxonomies", "sync_marker<>?", new String[]{marker});
            putMeta(db, "last_sync_marker", marker);
            putMeta(db, "last_synced_at", Long.toString(System.currentTimeMillis()));
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }

        JSONObject stats = getStats();
        stats.put("synced_authorities", authorityCount);
        stats.put("synced_categories", categoryCount);
        stats.put("synced_links", linkCount);
        return stats;
    }

    JSONArray getCategories() throws JSONException {
        SQLiteDatabase db = getReadableDatabase();
        String taxonomy = getDefaultTaxonomyCode(db);
        JSONArray out = new JSONArray();
        if (taxonomy.isEmpty()) return out;

        try (Cursor c = db.rawQuery(
                "SELECT c.id,c.name_fa,c.parent_id,c.sort_order,COUNT(ac.authority_id) " +
                "FROM categories c LEFT JOIN authority_categories ac " +
                "ON ac.category_id=c.id AND ac.taxonomy_code=c.taxonomy_code " +
                "WHERE c.taxonomy_code=? GROUP BY c.id,c.name_fa,c.parent_id,c.sort_order " +
                "ORDER BY c.sort_order,c.name_fa",
                new String[]{taxonomy})) {
            while (c.moveToNext()) {
                JSONObject x = new JSONObject();
                x.put("id", c.getString(0));
                x.put("name", c.getString(1));
                x.put("parent_id", c.isNull(2) ? JSONObject.NULL : c.getString(2));
                x.put("sort_order", c.getInt(3));
                x.put("count", c.getInt(4));
                x.put("taxonomy_code", taxonomy);
                out.put(x);
            }
        }
        return out;
    }

    JSONArray queryAuthorities(String categoryId, String query, int offset, int requestedLimit) throws JSONException {
        int limit = Math.max(1, Math.min(100, requestedLimit));
        int safeOffset = Math.max(0, offset);
        String normalizedQuery = normalize(query);
        SQLiteDatabase db = getReadableDatabase();
        JSONArray out = new JSONArray();

        StringBuilder sql = new StringBuilder(
                "SELECT DISTINCT a.id,a.canonical_title,a.authority_type_code,a.authority_type_name_fa," +
                "a.content_status_code,a.verification_status_code,a.effect_status_code," +
                "a.has_full_text,a.entity_resolution_review,a.updated_at " +
                "FROM authorities a ");
        java.util.ArrayList<String> args = new java.util.ArrayList<>();
        if (categoryId != null && !categoryId.trim().isEmpty()) {
            sql.append("JOIN authority_categories ac ON ac.authority_id=a.id ");
        }
        sql.append("WHERE 1=1 ");
        if (categoryId != null && !categoryId.trim().isEmpty()) {
            sql.append("AND ac.category_id=? ");
            args.add(categoryId.trim());
        }
        if (!normalizedQuery.isEmpty()) {
            sql.append("AND a.normalized_title LIKE ? ");
            args.add("%" + normalizedQuery + "%");
        }
        sql.append("ORDER BY a.canonical_title LIMIT ? OFFSET ?");
        args.add(Integer.toString(limit));
        args.add(Integer.toString(safeOffset));

        try (Cursor c = db.rawQuery(sql.toString(), args.toArray(new String[0]))) {
            while (c.moveToNext()) out.put(authorityFromCursor(c));
        }
        return out;
    }

    JSONObject getAuthority(String id) throws JSONException {
        if (id == null || id.length() > 80) return null;
        SQLiteDatabase db = getReadableDatabase();
        try (Cursor c = db.rawQuery(
                "SELECT a.id,a.canonical_title,a.authority_type_code,a.authority_type_name_fa," +
                "a.content_status_code,a.verification_status_code,a.effect_status_code," +
                "a.has_full_text,a.entity_resolution_review,a.updated_at " +
                "FROM authorities a WHERE a.id=? LIMIT 1",
                new String[]{id})) {
            return c.moveToFirst() ? authorityFromCursor(c) : null;
        }
    }

    JSONObject getStats() throws JSONException {
        SQLiteDatabase db = getReadableDatabase();
        JSONObject out = new JSONObject();
        out.put("authorities", scalarInt(db, "SELECT COUNT(*) FROM authorities"));
        out.put("categories", scalarInt(db, "SELECT COUNT(*) FROM categories"));
        out.put("links", scalarInt(db, "SELECT COUNT(*) FROM authority_categories"));
        out.put("default_taxonomy", getDefaultTaxonomyCode(db));
        out.put("last_synced_at", getMeta(db, "last_synced_at"));
        return out;
    }

    private JSONObject authorityFromCursor(Cursor c) throws JSONException {
        JSONObject x = new JSONObject();
        x.put("id", c.getString(0));
        x.put("title", c.getString(1));
        x.put("type_code", c.getString(2));
        x.put("type_label", c.getString(3));
        x.put("content_status", c.getString(4));
        x.put("verification_status", c.getString(5));
        x.put("effect_status", c.getString(6));
        x.put("has_full_text", c.getInt(7) == 1);
        x.put("review", c.getInt(8) == 1);
        x.put("updated_at", c.isNull(9) ? JSONObject.NULL : c.getString(9));
        return x;
    }

    private JSONArray fetchArray(String baseUrl, String key, String path) throws IOException, JSONException {
        HttpURLConnection connection = null;
        try {
            URL url = new URL(baseUrl.replaceAll("/+$", "") + path);
            connection = (HttpURLConnection) url.openConnection();
            connection.setConnectTimeout(15_000);
            connection.setReadTimeout(20_000);
            connection.setInstanceFollowRedirects(false);
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Accept", "application/json");
            connection.setRequestProperty("apikey", key);
            connection.setRequestProperty("User-Agent", "DastyarVakil/10");
            int status = connection.getResponseCode();
            if (status < 200 || status >= 300) {
                throw new IOException("Catalog endpoint returned HTTP " + status);
            }
            try (InputStream input = connection.getInputStream()) {
                return new JSONArray(readBounded(input, MAX_PAGE_BYTES));
            }
        } finally {
            if (connection != null) connection.disconnect();
        }
    }

    private String readBounded(InputStream input, int maxBytes) throws IOException {
        ByteArrayOutputStream out = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int total = 0;
        int n;
        while ((n = input.read(buffer)) != -1) {
            total += n;
            if (total > maxBytes) throw new IOException("Catalog response exceeded safety limit");
            out.write(buffer, 0, n);
        }
        return out.toString(StandardCharsets.UTF_8.name());
    }

    private void validateEndpoint(String baseUrl, String key) throws IOException {
        if (baseUrl == null || key == null) throw new IOException("Cloud catalog is not configured");
        URL url = new URL(baseUrl);
        String host = url.getHost() == null ? "" : url.getHost().toLowerCase(Locale.ROOT);
        if (!"https".equalsIgnoreCase(url.getProtocol()) || !host.endsWith(".supabase.co")) {
            throw new IOException("Invalid cloud catalog endpoint");
        }
        if (!key.matches("^sb_publishable_[A-Za-z0-9_-]{20,}$")) {
            throw new IOException("Publishable cloud key is not configured");
        }
    }

    private static void putNullable(ContentValues values, String key, String value) {
        if (value == null) values.putNull(key);
        else values.put(key, value);
    }

    private static String normalize(String value) {
        if (value == null) return "";
        return value
                .replace('ي', 'ی')
                .replace('ى', 'ی')
                .replace('ك', 'ک')
                .replace('\u200c', ' ')
                .replace('\u200f', ' ')
                .replaceAll("[ًٌٍَُِّْـ]", "")
                .replaceAll("[\\s\\u00A0]+", " ")
                .trim()
                .toLowerCase(Locale.ROOT);
    }

    private String getDefaultTaxonomyCode(SQLiteDatabase db) {
        try (Cursor c = db.rawQuery(
                "SELECT code FROM taxonomies ORDER BY app_default DESC, code LIMIT 1", null)) {
            return c.moveToFirst() ? c.getString(0) : "";
        }
    }

    private int scalarInt(SQLiteDatabase db, String sql) {
        try (Cursor c = db.rawQuery(sql, null)) {
            return c.moveToFirst() ? c.getInt(0) : 0;
        }
    }

    private static void putMeta(SQLiteDatabase db, String key, String value) {
        ContentValues v = new ContentValues();
        v.put("key", key);
        v.put("value", value == null ? "" : value);
        db.insertWithOnConflict("catalog_meta", null, v, SQLiteDatabase.CONFLICT_REPLACE);
    }

    private static String getMeta(SQLiteDatabase db, String key) {
        try (Cursor c = db.rawQuery("SELECT value FROM catalog_meta WHERE key=? LIMIT 1", new String[]{key})) {
            return c.moveToFirst() ? c.getString(0) : "";
        }
    }
}
