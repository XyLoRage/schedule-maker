package com.schedulemaker.wallpaper;

import android.app.AlarmManager;
import android.app.PendingIntent;
import android.app.WallpaperManager;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.util.Log;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.Locale;

/** Picks today's pre-rendered image and sets it; schedules the next check. */
final class WallpaperScheduler {
    static final String TAG = "ScheduleWallpaper";
    static final String ACTION_TICK = "com.schedulemaker.wallpaper.TICK";

    private static final String PREFS = "schedule_wallpaper";
    private static final String KEY_FOLDER = "folder";
    private static final String KEY_WHICH = "which";
    private static final String KEY_ENABLED = "enabled";
    private static final String KEY_LAST = "last_applied";

    private WallpaperScheduler() {}

    private static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    static void saveSettings(Context ctx, String folder, int which, boolean enabled) {
        prefs(ctx).edit()
                .putString(KEY_FOLDER, folder)
                .putInt(KEY_WHICH, which)
                .putBoolean(KEY_ENABLED, enabled)
                .apply();
    }

    static void setEnabled(Context ctx, boolean enabled) {
        prefs(ctx).edit().putBoolean(KEY_ENABLED, enabled).apply();
    }

    static boolean isEnabled(Context ctx) {
        return prefs(ctx).getBoolean(KEY_ENABLED, false);
    }

    static String today() {
        return new SimpleDateFormat("yyyy-MM-dd", Locale.US).format(new Date());
    }

    /** Applies today's image. Unless forced, does nothing if today was already applied. */
    static boolean applyToday(Context ctx, boolean force) {
        SharedPreferences p = prefs(ctx);
        if (!p.getBoolean(KEY_ENABLED, false)) return false;
        String folder = p.getString(KEY_FOLDER, null);
        if (folder == null) return false;
        String today = today();
        if (!force && today.equals(p.getString(KEY_LAST, ""))) return true;

        File file = new File(folder, today + ".png");
        if (!file.exists()) {
            file = newestUpTo(new File(folder), today);
            if (file == null) {
                Log.w(TAG, "No wallpaper image for " + today);
                return false;
            }
        }
        boolean ok = applyFile(ctx, file, p.getInt(KEY_WHICH, 3));
        if (ok) p.edit().putString(KEY_LAST, today).apply();
        return ok;
    }

    /** If the app hasn't been opened for a while, use the latest image that isn't in the future. */
    private static File newestUpTo(File dir, String today) {
        File[] files = dir.listFiles();
        if (files == null) return null;
        File best = null;
        for (File f : files) {
            String name = f.getName();
            if (!name.endsWith(".png")) continue;
            String date = name.substring(0, name.length() - 4);
            if (date.compareTo(today) <= 0 && (best == null || name.compareTo(best.getName()) > 0)) {
                best = f;
            }
        }
        return best;
    }

    static boolean applyFile(Context ctx, File file, int which) {
        Bitmap bitmap = BitmapFactory.decodeFile(file.getAbsolutePath());
        if (bitmap == null) {
            Log.w(TAG, "Could not decode " + file);
            return false;
        }
        int flags = 0;
        if ((which & 1) != 0) flags |= WallpaperManager.FLAG_SYSTEM;
        if ((which & 2) != 0) flags |= WallpaperManager.FLAG_LOCK;
        if (flags == 0) flags = WallpaperManager.FLAG_SYSTEM | WallpaperManager.FLAG_LOCK;
        try {
            WallpaperManager.getInstance(ctx).setBitmap(bitmap, null, true, flags);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "Setting wallpaper failed", e);
            return false;
        } finally {
            bitmap.recycle();
        }
    }

    private static PendingIntent tickIntent(Context ctx, int requestCode) {
        Intent intent = new Intent(ctx, DailyWallpaperReceiver.class).setAction(ACTION_TICK);
        return PendingIntent.getBroadcast(ctx, requestCode, intent,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /** One alarm just after midnight, plus an hourly backup in case the phone was asleep. */
    static void schedule(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;

        Calendar midnight = Calendar.getInstance();
        midnight.add(Calendar.DAY_OF_YEAR, 1);
        midnight.set(Calendar.HOUR_OF_DAY, 0);
        midnight.set(Calendar.MINUTE, 0);
        midnight.set(Calendar.SECOND, 5);
        midnight.set(Calendar.MILLISECOND, 0);
        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, midnight.getTimeInMillis(), tickIntent(ctx, 1));

        am.setInexactRepeating(AlarmManager.RTC, System.currentTimeMillis() + AlarmManager.INTERVAL_HOUR,
                AlarmManager.INTERVAL_HOUR, tickIntent(ctx, 2));
    }

    static void cancel(Context ctx) {
        AlarmManager am = (AlarmManager) ctx.getSystemService(Context.ALARM_SERVICE);
        if (am == null) return;
        am.cancel(tickIntent(ctx, 1));
        am.cancel(tickIntent(ctx, 2));
    }
}
