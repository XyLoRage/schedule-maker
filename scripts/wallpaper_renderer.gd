extends Node
## Renders wallpaper images off-screen with a SubViewport and saves one PNG per date
## into user://wallpapers/YYYY-MM-DD.png. The Android plugin picks today's file each day.

signal progress(done: int, total: int)

const PAINTER := preload("res://scripts/wallpaper_painter.gd")
const OUT_DIR := "user://wallpapers"

var _viewport: SubViewport
var _painter: Control
var busy := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_painter = PAINTER.new()
	_viewport.add_child(_painter)


## Wallpaper resolution: the phone's screen in portrait, or 1080x2400 on desktop.
func wallpaper_size() -> Vector2i:
	if OS.has_feature("mobile"):
		var s := DisplayServer.screen_get_size()
		return Vector2i(mini(s.x, s.y), maxi(s.x, s.y))
	return Vector2i(1080, 2400)


func load_background() -> Texture2D:
	var path: String = Store.settings.get("background", "")
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Renders a single date and returns the image.
func render_day(date: String, bg: Texture2D = null) -> Image:
	var size := wallpaper_size()
	_viewport.size = size
	_painter.size = Vector2(size)
	_painter.date = date
	_painter.background = bg
	_painter.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _viewport.get_texture().get_image()


## Renders today plus the next N days to disk and deletes files for past days.
## Returns the absolute folder path (for the Android plugin).
func render_all(days: int) -> String:
	busy = true
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var bg := load_background()
	var today: String = Store.today()
	for i in days:
		var date: String = Store.add_days(today, i)
		var img: Image = await render_day(date, bg)
		img.save_png("%s/%s.png" % [OUT_DIR, date])
		progress.emit(i + 1, days)
	_cleanup(today)
	busy = false
	return ProjectSettings.globalize_path(OUT_DIR)


func path_for(date: String) -> String:
	return ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, date])


func _cleanup(today: String) -> void:
	var dir := DirAccess.open(OUT_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		if f.ends_with(".png") and f.get_basename() < today:
			dir.remove(f)
