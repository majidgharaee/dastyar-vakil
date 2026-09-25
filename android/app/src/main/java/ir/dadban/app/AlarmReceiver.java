package ir.dadban.app;

import android.app.AlarmManager;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Build;

import java.util.Map;

public final class AlarmReceiver extends BroadcastReceiver {
    private static final String CHANNEL_ID = "lawyer_hearings";
    private static final String ALARM_PREFS = "lawyer_alarm_schedule_v1";
    private static final String EXTRA_REMINDER_ID = "reminderId";

    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent == null ? null : intent.getAction();
        if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                || Intent.ACTION_MY_PACKAGE_REPLACED.equals(action)
                || AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED.equals(action)) {
            rescheduleAll(context);
            return;
        }

        String reminderId = intent == null ? null : intent.getStringExtra(EXTRA_REMINDER_ID);
        int notificationId = intent == null ? 1001 : intent.getIntExtra("notificationId", 1001);
        if (reminderId != null) context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE).edit().remove(reminderId).apply();
        NotificationManager manager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager == null) return;

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "یادآوری وقت‌های رسیدگی",
                    NotificationManager.IMPORTANCE_HIGH
            );
            channel.setDescription("هشدارهای محلی و محرمانه مربوط به وقت رسیدگی");
            channel.enableVibration(true);
            manager.createNotificationChannel(channel);
        }

        Intent openIntent = new Intent(context, MainActivity.class)
                .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent contentIntent = PendingIntent.getActivity(
                context,
                notificationId,
                openIntent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE
        );

        android.app.Notification.Builder builder = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? new android.app.Notification.Builder(context, CHANNEL_ID)
                : new android.app.Notification.Builder(context);
        builder.setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("یادآوری دستیار وکیل")
                .setContentText("زمان یک یادآوری ثبت‌شده فرا رسیده است. برای مشاهده، برنامه را باز کنید.")
                .setContentIntent(contentIntent)
                .setAutoCancel(true)
                .setCategory(android.app.Notification.CATEGORY_REMINDER)
                .setVisibility(android.app.Notification.VISIBILITY_PRIVATE)
                .setPriority(android.app.Notification.PRIORITY_HIGH);
        manager.notify(notificationId, builder.build());
    }

    public static boolean schedule(Context context, String id, long triggerAtMillis) {
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        if (manager == null || id == null || id.isEmpty()) return false;
        PendingIntent pendingIntent = pendingIntent(context, id, PendingIntent.FLAG_UPDATE_CURRENT);
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && manager.canScheduleExactAlarms()) {
                manager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                manager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
            } else {
                manager.setExact(AlarmManager.RTC_WAKEUP, triggerAtMillis, pendingIntent);
            }
            context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE).edit()
                    .putLong(id, triggerAtMillis).apply();
            return true;
        } catch (SecurityException error) {
            return false;
        }
    }

    public static void cancel(Context context, String id) {
        AlarmManager manager = (AlarmManager) context.getSystemService(Context.ALARM_SERVICE);
        PendingIntent pendingIntent = pendingIntent(context, id, PendingIntent.FLAG_NO_CREATE);
        if (manager != null && pendingIntent != null) {
            manager.cancel(pendingIntent);
            pendingIntent.cancel();
        }
        context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE).edit().remove(id).apply();
    }

    public static void cancelAll(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE);
        for (String id : prefs.getAll().keySet()) cancel(context, id);
        prefs.edit().clear().apply();
    }

    private static void rescheduleAll(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(ALARM_PREFS, Context.MODE_PRIVATE);
        long now = System.currentTimeMillis();
        for (Map.Entry<String, ?> entry : prefs.getAll().entrySet()) {
            long at = entry.getValue() instanceof Long ? (Long) entry.getValue() : 0L;
            if (at > now) schedule(context, entry.getKey(), at);
            else prefs.edit().remove(entry.getKey()).apply();
        }
    }

    private static PendingIntent pendingIntent(Context context, String id, int flags) {
        Intent intent = new Intent(context, AlarmReceiver.class)
                .putExtra(EXTRA_REMINDER_ID, id)
                .putExtra("notificationId", requestCode(id));
        return PendingIntent.getBroadcast(context, requestCode(id), intent,
                flags | PendingIntent.FLAG_IMMUTABLE);
    }

    private static int requestCode(String id) {
        return 10_000 + (id.hashCode() & 0x3fffffff);
    }
}
