extends RefCounted
## Sets the phone wallpaper.
## 1) If the ScheduleWallpaper Android plugin is in the build, it is used. It can also change
##    the wallpaper by itself every day (at midnight, after reboot, or when the clock changes),
##    even when the app is closed.
## 2) Otherwise, Godot's JavaClassWrapper calls Android's WallpaperManager directly. That works
##    without the plugin but only while the app is open.

const PLUGIN := "ScheduleWallpaper"
const HOME := 1
const LOCK := 2
const BOTH := 3


static func is_android() -> bool:
	return OS.get_name() == "Android"


static func has_plugin() -> bool:
	return Engine.has_singleton(PLUGIN)


## Sets the image at 'abs_path' as wallpaper right now. Returns true on success.
static func apply(abs_path: String, which: int = BOTH) -> bool:
	if not is_android():
		return false
	if has_plugin():
		return Engine.get_singleton(PLUGIN).applyWallpaper(abs_path, which)
	return _apply_with_java(abs_path, which)


## Turns on the automatic daily change. 'folder' holds files named YYYY-MM-DD.png.
static func enable_daily(folder: String, which: int = BOTH) -> bool:
	if not has_plugin():
		return false
	Engine.get_singleton(PLUGIN).enableDaily(folder, which)
	return true


static func disable_daily() -> void:
	if has_plugin():
		Engine.get_singleton(PLUGIN).disableDaily()


static func _apply_with_java(abs_path: String, which: int) -> bool:
	if not Engine.has_singleton("AndroidRuntime"):
		push_warning("AndroidRuntime singleton missing (needs Godot 4.4+).")
		return false
	var activity = Engine.get_singleton("AndroidRuntime").getActivity()
	var wm_class = JavaClassWrapper.wrap("android.app.WallpaperManager")
	var bf_class = JavaClassWrapper.wrap("android.graphics.BitmapFactory")
	if wm_class == null or bf_class == null or activity == null:
		return false
	var wm = wm_class.getInstance(activity)
	var bitmap = bf_class.decodeFile(abs_path)
	if wm == null or bitmap == null:
		push_warning("Could not load wallpaper image: " + abs_path)
		return false
	# setBitmap(Bitmap, Rect visibleCrop, boolean allowBackup, int which)
	var result = wm.setBitmap(bitmap, null, true, which)
	var err = JavaClassWrapper.get_exception()
	if err != null:
		push_warning("setBitmap with flags failed, trying home screen only: " + str(err))
		wm.setBitmap(bitmap)
		return JavaClassWrapper.get_exception() == null
	return result != null
