package ir.dadban.app;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.UUID;

final class DirectoryStore extends SQLiteOpenHelper {
    private static final String DB_NAME = "legal_directory_v1.db";
    private static final int DB_VERSION = 2;
    private static final int PAGE_SIZE = 500;
    private static final int MAX_PAGE_BYTES = 5_000_000;

    DirectoryStore(Context context) { super(context, DB_NAME, null, DB_VERSION); }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE directory_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL)");
        db.execSQL("CREATE TABLE groups_cache (group_code TEXT PRIMARY KEY, group_id TEXT, group_name TEXT NOT NULL, sort_order INTEGER NOT NULL DEFAULT 0, entity_count INTEGER NOT NULL DEFAULT 0, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE TABLE subgroups_cache (subgroup_code TEXT PRIMARY KEY, subgroup_id TEXT, subgroup_name TEXT NOT NULL, group_code TEXT NOT NULL, group_name TEXT, sort_order INTEGER NOT NULL DEFAULT 0, entity_count INTEGER NOT NULL DEFAULT 0, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE INDEX subgroups_group_sort_idx ON subgroups_cache(group_code,sort_order,subgroup_name)");
        db.execSQL("CREATE TABLE entities_cache (entity_id TEXT PRIMARY KEY, name TEXT NOT NULL, normalized_text TEXT NOT NULL, status_code TEXT, province TEXT, county TEXT, city TEXT, municipal_region TEXT, jurisdiction_scope TEXT, address TEXT, postal_code TEXT, hours_text TEXT, operational_status TEXT, confidence_level TEXT, verification_status TEXT, source_date_text TEXT, source_name TEXT, source_url TEXT, map_url TEXT, lawyer_use TEXT, project_scope TEXT, notes TEXT, geocode_status TEXT, primary_group_code TEXT, primary_group_name TEXT, primary_subgroup_code TEXT, primary_subgroup_name TEXT, classifications TEXT NOT NULL DEFAULT '[]', phone TEXT, official_verified INTEGER NOT NULL DEFAULT 0, verification_required INTEGER NOT NULL DEFAULT 0, coordinate_verified INTEGER NOT NULL DEFAULT 0, primary_external_id TEXT, updated_at TEXT, sync_marker TEXT NOT NULL)");
        db.execSQL("CREATE INDEX entities_group_name_idx ON entities_cache(primary_group_code,name)");
        db.execSQL("CREATE INDEX entities_subgroup_idx ON entities_cache(primary_subgroup_code)");
        db.execSQL("CREATE INDEX entities_search_idx ON entities_cache(normalized_text)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion < 2) db.execSQL("ALTER TABLE entities_cache ADD COLUMN classifications TEXT NOT NULL DEFAULT '[]'");
    }

    JSONObject syncFromSupabase(String baseUrl, String publishableKey) throws IOException, JSONException {
        LegalCatalogStore.validateEndpoint(baseUrl, publishableKey);
        String marker = UUID.randomUUID().toString(); SQLiteDatabase db = getWritableDatabase();
        int entityCount = 0, groupCount = 0, subgroupCount = 0;
        db.beginTransaction();
        try {
            JSONArray groups = requestArray(baseUrl, publishableKey, "/rest/v1/directory_group_counts?select=group_id,group_code,group_name,sort_order,entity_count&order=sort_order.asc,group_name.asc", null);
            for (int i=0;i<groups.length();i++) { JSONObject x=groups.getJSONObject(i); ContentValues v=new ContentValues(); v.put("group_code",x.optString("group_code","")); putNullable(v,"group_id",nullable(x,"group_id")); v.put("group_name",x.optString("group_name","")); v.put("sort_order",x.optInt("sort_order",0)); v.put("entity_count",x.optInt("entity_count",0)); v.put("sync_marker",marker); db.insertWithOnConflict("groups_cache",null,v,SQLiteDatabase.CONFLICT_REPLACE); groupCount++; }
            JSONArray subgroups = requestArray(baseUrl, publishableKey, "/rest/v1/directory_subgroup_counts?select=subgroup_id,subgroup_code,subgroup_name,group_code,group_name,sort_order,entity_count&order=group_code.asc,sort_order.asc,subgroup_name.asc", null);
            for (int i=0;i<subgroups.length();i++) { JSONObject x=subgroups.getJSONObject(i); ContentValues v=new ContentValues(); v.put("subgroup_code",x.optString("subgroup_code","")); putNullable(v,"subgroup_id",nullable(x,"subgroup_id")); v.put("subgroup_name",x.optString("subgroup_name","")); v.put("group_code",x.optString("group_code","")); putNullable(v,"group_name",nullable(x,"group_name")); v.put("sort_order",x.optInt("sort_order",0)); v.put("entity_count",x.optInt("entity_count",0)); v.put("sync_marker",marker); db.insertWithOnConflict("subgroups_cache",null,v,SQLiteDatabase.CONFLICT_REPLACE); subgroupCount++; }
            for(int offset=0;;offset+=PAGE_SIZE) {
                JSONArray page=requestArray(baseUrl,publishableKey,"/rest/v1/directory_current?select=entity_id,name,status_code,province,county,city,municipal_region,jurisdiction_scope,address,postal_code,hours_text,operational_status,confidence_level,verification_status,source_date_text,source_name,source_url,map_url,lawyer_use,project_scope,notes,geocode_status,primary_group_code,primary_group_name,primary_subgroup_code,primary_subgroup_name,classifications,phone,official_verified,verification_required,coordinate_verified,primary_external_id,updated_at&order=name.asc&limit="+PAGE_SIZE+"&offset="+offset,null);
                for(int i=0;i<page.length();i++) { JSONObject x=page.getJSONObject(i); ContentValues v=new ContentValues(); String name=x.optString("name",""); String address=x.optString("address",""); v.put("entity_id",x.getString("entity_id")); v.put("name",name); v.put("normalized_text",LegalCatalogStore.normalize(name+" "+address+" "+x.optString("jurisdiction_scope","")+" "+x.optString("lawyer_use","")+" "+x.optString("phone",""))); copy(v,x,"status_code","province","county","city","municipal_region","jurisdiction_scope","address","postal_code","hours_text","operational_status","confidence_level","verification_status","source_date_text","source_name","source_url","map_url","lawyer_use","project_scope","notes","geocode_status","primary_group_code","primary_group_name","primary_subgroup_code","primary_subgroup_name","phone","primary_external_id","updated_at"); v.put("classifications",x.optJSONArray("classifications") == null ? "[]" : x.optJSONArray("classifications").toString()); v.put("official_verified",x.optBoolean("official_verified",false)?1:0); v.put("verification_required",x.optBoolean("verification_required",false)?1:0); v.put("coordinate_verified",x.optBoolean("coordinate_verified",false)?1:0); v.put("sync_marker",marker); db.insertWithOnConflict("entities_cache",null,v,SQLiteDatabase.CONFLICT_REPLACE); entityCount++; }
                if(page.length()<PAGE_SIZE)break;
            }
            JSONObject probe=new JSONObject(); probe.put("p_query","دادگستری"); probe.put("p_limit",1); probe.put("p_offset",0); requestArray(baseUrl,publishableKey,"/rest/v1/rpc/search_directory",probe);
            db.delete("entities_cache","sync_marker<>?",new String[]{marker}); db.delete("subgroups_cache","sync_marker<>?",new String[]{marker}); db.delete("groups_cache","sync_marker<>?",new String[]{marker});
            putMeta(db,"last_synced_at",Long.toString(System.currentTimeMillis())); putMeta(db,"source","public.directory_current/search_directory/directory_group_counts/directory_subgroup_counts"); db.setTransactionSuccessful();
        } finally { db.endTransaction(); }
        JSONObject stats=getStats(); stats.put("synced_entities",entityCount); stats.put("synced_groups",groupCount); stats.put("synced_subgroups",subgroupCount); return stats;
    }

    JSONArray getGroups() throws JSONException { JSONArray out=new JSONArray(); try(Cursor c=getReadableDatabase().rawQuery("SELECT group_code,group_name,entity_count FROM groups_cache ORDER BY sort_order,group_name",null)){ while(c.moveToNext()){ JSONObject x=new JSONObject(); x.put("code",c.getString(0)); x.put("name",c.getString(1)); x.put("count",c.getInt(2)); out.put(x); } } return out; }
    JSONArray getSubgroups(String groupCode) throws JSONException { JSONArray out=new JSONArray(); try(Cursor c=getReadableDatabase().rawQuery("SELECT subgroup_code,subgroup_name,entity_count FROM subgroups_cache WHERE group_code=? ORDER BY sort_order,subgroup_name",new String[]{groupCode==null?"":groupCode})){ while(c.moveToNext()){ JSONObject x=new JSONObject(); x.put("code",c.getString(0)); x.put("name",c.getString(1)); x.put("count",c.getInt(2)); out.put(x); } } return out; }

    JSONArray queryEntities(String groupCode,String subgroupCode,String query,int offset,int requestedLimit) throws JSONException {
        int limit=Math.max(1,Math.min(100,requestedLimit)),safeOffset=Math.max(0,offset); String n=LegalCatalogStore.normalize(query); StringBuilder sql=new StringBuilder("SELECT entity_id,name,status_code,city,jurisdiction_scope,address,operational_status,confidence_level,verification_status,source_date_text,source_name,source_url,map_url,lawyer_use,project_scope,primary_group_code,primary_group_name,primary_subgroup_code,primary_subgroup_name,phone,official_verified,verification_required,coordinate_verified,primary_external_id FROM entities_cache WHERE 1=1 "); ArrayList<String> args=new ArrayList<>();
        if(groupCode!=null&&!groupCode.trim().isEmpty()){sql.append("AND (primary_group_code=? OR classifications LIKE ?) ");args.add(groupCode.trim());args.add("%\"group_code\":\""+groupCode.trim()+"\"%");} if(subgroupCode!=null&&!subgroupCode.trim().isEmpty()){sql.append("AND (primary_subgroup_code=? OR classifications LIKE ?) ");args.add(subgroupCode.trim());args.add("%\"subgroup_code\":\""+subgroupCode.trim()+"\"%");} if(!n.isEmpty()){sql.append("AND normalized_text LIKE ? ");args.add("%"+n+"%");} sql.append("ORDER BY name LIMIT ? OFFSET ?");args.add(Integer.toString(limit));args.add(Integer.toString(safeOffset)); JSONArray out=new JSONArray(); try(Cursor c=getReadableDatabase().rawQuery(sql.toString(),args.toArray(new String[0]))){while(c.moveToNext())out.put(entityFromCursor(c));} return out;
    }

    JSONObject getEntity(String id) throws JSONException { if(id==null||id.length()>80)return null; try(Cursor c=getReadableDatabase().rawQuery("SELECT entity_id,name,status_code,city,jurisdiction_scope,address,operational_status,confidence_level,verification_status,source_date_text,source_name,source_url,map_url,lawyer_use,project_scope,primary_group_code,primary_group_name,primary_subgroup_code,primary_subgroup_name,phone,official_verified,verification_required,coordinate_verified,primary_external_id FROM entities_cache WHERE entity_id=? LIMIT 1",new String[]{id})){return c.moveToFirst()?entityFromCursor(c):null;} }
    JSONObject getStats() throws JSONException { SQLiteDatabase db=getReadableDatabase(); JSONObject x=new JSONObject(); x.put("entities",scalarInt(db,"SELECT COUNT(*) FROM entities_cache")); x.put("groups",scalarInt(db,"SELECT COUNT(*) FROM groups_cache")); x.put("subgroups",scalarInt(db,"SELECT COUNT(*) FROM subgroups_cache")); x.put("needs_verification",scalarInt(db,"SELECT COUNT(*) FROM entities_cache WHERE verification_required=1")); x.put("last_synced_at",getMeta(db,"last_synced_at")); x.put("source",getMeta(db,"source")); return x; }

    private JSONObject entityFromCursor(Cursor c) throws JSONException { JSONObject x=new JSONObject(); x.put("id",c.getString(0)); x.put("name",c.getString(1)); x.put("status_code",nullable(c,2)); x.put("city",nullable(c,3)); x.put("jurisdiction_scope",nullable(c,4)); x.put("address",nullable(c,5)); x.put("operational_status",nullable(c,6)); x.put("confidence_level",nullable(c,7)); x.put("verification_status",nullable(c,8)); x.put("source_date_text",nullable(c,9)); x.put("source_name",nullable(c,10)); x.put("source_url",nullable(c,11)); x.put("map_url",nullable(c,12)); x.put("lawyer_use",nullable(c,13)); x.put("project_scope",nullable(c,14)); x.put("group_code",nullable(c,15)); x.put("group_name",nullable(c,16)); x.put("subgroup_code",nullable(c,17)); x.put("subgroup_name",nullable(c,18)); x.put("phone",nullable(c,19)); x.put("official_verified",c.getInt(20)==1); x.put("verification_required",c.getInt(21)==1); x.put("coordinate_verified",c.getInt(22)==1); x.put("external_id",nullable(c,23)); return x; }

    private JSONArray requestArray(String baseUrl,String key,String path,JSONObject body)throws IOException,JSONException { HttpURLConnection c=null; try{c=(HttpURLConnection)new URL(baseUrl.replaceAll("/+$","")+path).openConnection();c.setConnectTimeout(15_000);c.setReadTimeout(30_000);c.setInstanceFollowRedirects(false);c.setRequestMethod(body==null?"GET":"POST");c.setRequestProperty("Accept","application/json");c.setRequestProperty("apikey",key);c.setRequestProperty("Authorization","Bearer "+key);c.setRequestProperty("User-Agent","DastyarVakil/10.0.0");if(body!=null){c.setDoOutput(true);c.setRequestProperty("Content-Type","application/json; charset=utf-8");try(OutputStream o=c.getOutputStream()){o.write(body.toString().getBytes(StandardCharsets.UTF_8));}}int status=c.getResponseCode();if(status<200||status>=300)throw new IOException("Directory API returned HTTP "+status);try(InputStream in=c.getInputStream()){return new JSONArray(LegalCatalogStore.readBounded(in,MAX_PAGE_BYTES));}}finally{if(c!=null)c.disconnect();} }
    private static void copy(ContentValues v,JSONObject x,String...keys){for(String key:keys)putNullable(v,key,nullable(x,key));}
    private static String nullable(JSONObject x,String key){return x.isNull(key)?null:x.optString(key,null);} private static Object nullable(Cursor c,int i){return c.isNull(i)?JSONObject.NULL:c.getString(i);} private static void putNullable(ContentValues v,String key,String value){if(value==null)v.putNull(key);else v.put(key,value);} private int scalarInt(SQLiteDatabase db,String sql){try(Cursor c=db.rawQuery(sql,null)){return c.moveToFirst()?c.getInt(0):0;}} private static void putMeta(SQLiteDatabase db,String key,String value){ContentValues v=new ContentValues();v.put("key",key);v.put("value",value==null?"":value);db.insertWithOnConflict("directory_meta",null,v,SQLiteDatabase.CONFLICT_REPLACE);} private static String getMeta(SQLiteDatabase db,String key){try(Cursor c=db.rawQuery("SELECT value FROM directory_meta WHERE key=? LIMIT 1",new String[]{key})){return c.moveToFirst()?c.getString(0):"";}}
}
