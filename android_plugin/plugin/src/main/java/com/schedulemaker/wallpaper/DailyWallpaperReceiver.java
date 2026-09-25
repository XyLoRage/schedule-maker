package com.schedulemaker.wallpaper;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

/** Wakes up at midnight / hourly / after reboot / on clock changes and sets today's wallpaper. */
public class DailyWallpaperReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        final Context ctx = context.getApplicationContext();
        if (!WallpaperScheduler.isEnabled(ctx)) return;
        final boolean force = !WallpaperScheduler.ACTION_TICK.equals(intent.getAction());
        final PendingResult result = goAsync();
        new Thread(() -> {
            try {
                WallpaperScheduler.applyToday(ctx, force);
                WallpaperScheduler.schedule(ctx);
            } finally {
                result.finish();
            }
        }).start();
    }
}
