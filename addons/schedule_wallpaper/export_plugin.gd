@tool
extends EditorPlugin
## Adds the ScheduleWallpaper Android library (AAR) to Android exports that use a Gradle build.
## Build the AAR once with android_plugin/build_plugin.bat; it lands in bin/.

var _export_plugin: AndroidExportPlugin


func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null


class AndroidExportPlugin extends EditorExportPlugin:
	const AAR := "schedule_wallpaper/bin/ScheduleWallpaper-release.aar"

	func _get_name() -> String:
		return "ScheduleWallpaper"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
		if FileAccess.file_exists("res://addons/" + AAR):
			return PackedStringArray([AAR])
		push_warning("ScheduleWallpaper AAR not built yet: the daily auto-change is off in this export. Run android_plugin/build_plugin.bat.")
		return PackedStringArray()
