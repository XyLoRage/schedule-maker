package com.schedulemaker.wallpaper;

import android.app.Activity;
import android.content.Context;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;

/**
 * Godot singleton "ScheduleWallpaper".
 * GDScript: Engine.get_singleton("ScheduleWallpaper").applyWallpaper(path, which)
 * which: 1 = home screen, 2 = lock screen, 3 = both.
 */
public class ScheduleWallpaperPlugin extends GodotPlugin {

    public ScheduleWallpaperPlugin(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "ScheduleWallpaper";
    }

    private Context context() {
        Activity activity = getActivity();
        return activity != null ? activity.getApplicationContext() : null;
    }

    /** Sets the given PNG as wallpaper right now. */
    @UsedByGodot
    public boolean applyWallpaper(String absolutePath, int which) {
        Context ctx = context();
        if (ctx == null) return false;
        return WallpaperScheduler.applyFile(ctx, new File(absolutePath), which);
    }

    /**
     * Turns on the daily change. `folder` holds images named YYYY-MM-DD.png.
     * Applies today's image immediately and schedules the midnight update.
     */
    @UsedByGodot
    public boolean enableDaily(String folder, int which) {
        Context ctx = context();
        if (ctx == null) return false;
        WallpaperScheduler.saveSettings(ctx, folder, which, true);
        boolean ok = WallpaperScheduler.applyToday(ctx, true);
        WallpaperScheduler.schedule(ctx);
        return ok;
    }

    @UsedByGodot
    public void disableDaily() {
        Context ctx = context();
        if (ctx == null) return;
        WallpaperScheduler.setEnabled(ctx, false);
        WallpaperScheduler.cancel(ctx);
    }

    @UsedByGodot
    public boolean isDailyEnabled() {
        Context ctx = context();
        return ctx != null && WallpaperScheduler.isEnabled(ctx);
    }
}
