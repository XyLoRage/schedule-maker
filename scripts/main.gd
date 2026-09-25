extends Control
## The whole app UI, built in code: Schedule, Due Dates and Wallpaper pages with a bottom nav.

const RendererScript := preload("res://scripts/wallpaper_renderer.gd")
const AndroidWallpaper := preload("res://scripts/android_wallpaper.gd")

# Palette
const BG := Color("#12141d")
const SURFACE := Color("#1c1f2b")
const SURFACE_2 := Color("#262a3a")
const TEXT := Color("#f4f1ea")
const MUTED := Color("#9aa0b4")
const ACCENT := Color("#ff7a59")
const BLUE := Color("#6c8cff")
const RED := Color("#ff6b6b")
const AMBER := Color("#ffc857")
const GREEN := Color("#35c28f")

var renderer: RendererScript
var pages: Array[Control] = []
var nav_buttons: Array[Button] = []

# Schedule page
var selected_date: String
var week_strip: HBoxContainer
var day_title: Label
var event_list: VBoxContainer

# Due page
var due_list: VBoxContainer

# Wallpaper page
var preview: TextureRect
var wp_status: Label
var auto_check: CheckButton
var which_option: OptionButton
var file_dialog: FileDialog

var _refresh_timer: Timer
var _refresh_pending := false
var _last_date := ""
var _overlay: Control = null


func _ready() -> void:
	selected_date = Store.today()
	theme = _make_theme()

	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	renderer = RendererScript.new()
	add_child(renderer)

	_refresh_timer = Timer.new()
	_refresh_timer.one_shot = true
	_refresh_timer.wait_time = 0.8
	_refresh_timer.timeout.connect(_refresh_wallpapers)
	add_child(_refresh_timer)

	var safe := MarginContainer.new()
	safe.set_anchors_preset(PRESET_FULL_RECT)
	var top_pad := 24
	if OS.has_feature("mobile"):
		top_pad = 64
	safe.add_theme_constant_override("margin_top", top_pad)
	safe.add_theme_constant_override("margin_left", 0)
	safe.add_theme_constant_override("margin_right", 0)
	safe.add_theme_constant_override("margin_bottom", 0)
	add_child(safe)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 0)
	safe.add_child(root)

	var content := Control.new()
	content.size_flags_vertical = SIZE_EXPAND_FILL
	root.add_child(content)

	pages = [_build_schedule_page(), _build_due_page(), _build_wallpaper_page()]
	for p in pages:
		p.set_anchors_preset(PRESET_FULL_RECT)
		content.add_child(p)

	root.add_child(_build_nav())
	_show_page(0)

	Store.changed.connect(_on_data_changed)
	_refresh_all_lists()
	_last_date = Store.today()
	# Render and apply once the first frame is up.
	_queue_wallpaper_refresh(0.3)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		# Coming back to the app: if the day changed, move everything to the new date.
		if Store.today() != _last_date:
			_last_date = Store.today()
			selected_date = _last_date
			_refresh_all_lists()
		_queue_wallpaper_refresh(0.3)


func _on_data_changed() -> void:
	_refresh_all_lists()
	_queue_wallpaper_refresh()


func _refresh_all_lists() -> void:
	_refresh_week_strip()
	_refresh_events()
	_refresh_due()


# ================================================================ navigation

func _build_nav() -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(SURFACE, 0, 12))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)
	var labels := ["Schedule", "Due Dates", "Wallpaper"]
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.flat = true
		b.custom_minimum_size = Vector2(0, 88)
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.pressed.connect(_show_page.bind(i))
		row.add_child(b)
		nav_buttons.append(b)
	return panel


func _show_page(i: int) -> void:
	for j in pages.size():
		pages[j].visible = j == i
		nav_buttons[j].add_theme_color_override("font_color", ACCENT if j == i else MUTED)
		nav_buttons[j].add_theme_color_override("font_hover_color", ACCENT if j == i else TEXT)


# ================================================================ schedule page

func _build_schedule_page() -> Control:
	var page := _page("Schedule")
	var body: VBoxContainer = page.get_meta("body")

	var week_row := HBoxContainer.new()
	week_row.add_theme_constant_override("separation", 6)
	var prev := _small_button("‹")
	prev.pressed.connect(func(): _select_date(Store.add_days(selected_date, -7)))
	week_row.add_child(prev)
	week_strip = HBoxContainer.new()
	week_strip.size_flags_horizontal = SIZE_EXPAND_FILL
	week_strip.add_theme_constant_override("separation", 6)
	week_row.add_child(week_strip)
	var next := _small_button("›")
	next.pressed.connect(func(): _select_date(Store.add_days(selected_date, 7)))
	week_row.add_child(next)
	body.add_child(week_row)

	var title_row := HBoxContainer.new()
	day_title = _label("", 30, TEXT)
	day_title.size_flags_horizontal = SIZE_EXPAND_FILL
	title_row.add_child(day_title)
	var today_btn := _small_button("Today")
	today_btn.pressed.connect(func(): _select_date(Store.today()))
	title_row.add_child(today_btn)
	body.add_child(title_row)

	event_list = VBoxContainer.new()
	event_list.add_theme_constant_override("separation", 12)
	body.add_child(_scroll(event_list))

	var add := _primary_button("+  Add to schedule")
	add.pressed.connect(func(): _open_event_editor({}))
	body.add_child(add)
	return page


func _select_date(date: String) -> void:
	selected_date = date
	_refresh_week_strip()
	_refresh_events()


func _refresh_week_strip() -> void:
	if week_strip == null:
		return
	for c in week_strip.get_children():
		c.queue_free()
	# Week starts on Monday
	var wd := Store.weekday(selected_date)
	var monday := Store.add_days(selected_date, -((wd + 6) % 7))
	for i in 7:
		var date := Store.add_days(monday, i)
		var d := Time.get_date_dict_from_unix_time(Store.date_to_unix(date))
		var b := Button.new()
		b.text = "%s\n%d" % [Store.WEEKDAY_SHORT[d["weekday"]].left(2), d["day"]]
		b.size_flags_horizontal = SIZE_EXPAND_FILL
		b.custom_minimum_size = Vector2(0, 96)
		b.add_theme_font_size_override("font_size", 22)
		var is_sel := date == selected_date
		var is_today := date == Store.today()
		var fill := ACCENT if is_sel else SURFACE
		b.add_theme_stylebox_override("normal", _box(fill, 14, 4))
		b.add_theme_stylebox_override("hover", _box(fill.lightened(0.08), 14, 4))
		b.add_theme_stylebox_override("pressed", _box(fill.darkened(0.1), 14, 4))
		b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		if is_today and not is_sel:
			var sb := _box(SURFACE, 14, 4)
			sb.border_color = ACCENT
			sb.set_border_width_all(2)
			b.add_theme_stylebox_override("normal", sb)
		if not Store.events_for_date(date).is_empty() and not is_sel:
			b.add_theme_color_override("font_color", TEXT)
		else:
			b.add_theme_color_override("font_color", TEXT if is_sel else MUTED)
		b.pressed.connect(_select_date.bind(date))
		week_strip.add_child(b)
	var label := Store.pretty_date(selected_date)
	if selected_date == Store.today():
		label = "Today · " + label
	day_title.text = label


func _refresh_events() -> void:
	if event_list == null:
		return
	for c in event_list.get_children():
		c.queue_free()
	var events := Store.events_for_date(selected_date)
	if events.is_empty():
		event_list.add_child(_empty_note("Nothing on this day yet.\nTap “Add to schedule” to add a class, practice, or anything else."))
		return
	for e in events:
		event_list.add_child(_event_card(e))


func _event_card(e: Dictionary) -> Control:
	var card := _card_button()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(row)

	var bar := ColorRect.new()
	bar.color = Color(e.get("color", "#6c8cff"))
	bar.custom_minimum_size = Vector2(8, 0)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(bar)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(col)
	var time_text := Store.pretty_time(e.get("start", ""))
	if e.get("end", "") != "":
		time_text += " – " + Store.pretty_time(e["end"])
	col.add_child(_label(time_text, 22, MUTED))
	var title := _label(e.get("title", ""), 30, TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	col.add_child(_label(_repeat_text(e), 20, MUTED))

	_on_tap(card, func(): _open_event_editor(e.duplicate(true)))
	return card


func _repeat_text(e: Dictionary) -> String:
	if e.get("repeat", "daily") == "once":
		return "One time · " + Store.pretty_date(e.get("date", Store.today()))
	var days: Array = e.get("days", [])
	if days.size() == 7:
		return "Every day"
	if days.size() == 5 and not (0 in days) and not (6 in days):
		return "Weekdays"
	var names: Array[String] = []
	for d in [1, 2, 3, 4, 5, 6, 0]:
		if d in days:
			names.append(Store.WEEKDAY_SHORT[d])
	return "Every " + ", ".join(names)


# ================================================================ due dates page

func _build_due_page() -> Control:
	var page := _page("Due Dates")
	var body: VBoxContainer = page.get_meta("body")
	due_list = VBoxContainer.new()
	due_list.add_theme_constant_override("separation", 12)
	body.add_child(_scroll(due_list))
	var add := _primary_button("+  Add assignment")
	add.pressed.connect(func(): _open_assignment_editor({}))
	body.add_child(add)
	return page


func _refresh_due() -> void:
	if due_list == null:
		return
	for c in due_list.get_children():
		c.queue_free()
	var list := Store.sorted_assignments()
	if list.is_empty():
		due_list.add_child(_empty_note("No assignments yet.\nAdd one with its due date. You can write notes under the title."))
		return
	var shown_done_header := false
	for a in list:
		if a.get("done", false) and not shown_done_header:
			due_list.add_child(_label("Done", 22, MUTED))
			shown_done_header = true
		due_list.add_child(_assignment_card(a))


func _assignment_card(a: Dictionary) -> Control:
	var today := Store.today()
	var done: bool = a.get("done", false)
	var urgency := Store.due_urgency(a, today)
	var tone: Color = [RED, AMBER, GREEN][urgency]
	if done:
		tone = MUTED

	var card := _card_button()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(row)

	row.add_child(_done_toggle(a["id"], done))

	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.mouse_filter = MOUSE_FILTER_IGNORE
	row.add_child(col)

	var title := _label(a.get("title", ""), 30, MUTED if done else TEXT)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(title)
	var notes: String = a.get("notes", "").strip_edges()
	if notes != "":
		var n := _label(notes, 22, MUTED)
		n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		n.max_lines_visible = 4
		col.add_child(n)
	var due_line := Store.pretty_date(a.get("due", today))
	if a.get("due_time", "") != "":
		due_line += " · " + Store.pretty_time(a["due_time"])
	var status := "Done" if done else Store.due_text(a, today)
	col.add_child(_label("%s   —   %s" % [status, due_line], 22, tone))

	_on_tap(card, func(): _open_assignment_editor(a.duplicate(true)))
	return card


# ================================================================ wallpaper page

func _build_wallpaper_page() -> Control:
	var page := _page("Wallpaper")
	var body: VBoxContainer = page.get_meta("body")

	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 16)

	preview = TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size = Vector2(0, 620)
	inner.add_child(preview)

	wp_status = _label("", 22, MUTED)
	wp_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	wp_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	inner.add_child(wp_status)

	var apply_btn := _primary_button("Set as wallpaper now")
	apply_btn.pressed.connect(func(): _refresh_wallpapers())
	inner.add_child(apply_btn)

	auto_check = CheckButton.new()
	auto_check.text = "Change automatically every day"
	auto_check.button_pressed = Store.settings.get("auto_daily", true)
	auto_check.toggled.connect(func(on):
		Store.settings["auto_daily"] = on
		if not on:
			AndroidWallpaper.disable_daily()
		Store.save_data())
	inner.add_child(auto_check)

	var which_row := HBoxContainer.new()
	which_row.add_child(_label("Screen", 26, TEXT))
	which_option = OptionButton.new()
	which_option.size_flags_horizontal = SIZE_EXPAND_FILL
	which_option.add_item("Home + lock screen", 3)
	which_option.add_item("Lock screen only", 2)
	which_option.add_item("Home screen only", 1)
	which_option.select(which_option.get_item_index(int(Store.settings.get("which", 3))))
	which_option.item_selected.connect(func(idx):
		Store.settings["which"] = which_option.get_item_id(idx)
		Store.save_data())
	which_row.add_child(which_option)
	inner.add_child(which_row)

	var bg_row := HBoxContainer.new()
	bg_row.add_theme_constant_override("separation", 12)
	var pick := _secondary_button("Choose background")
	pick.size_flags_horizontal = SIZE_EXPAND_FILL
	pick.pressed.connect(_pick_background)
	bg_row.add_child(pick)
	var clear := _secondary_button("Use default")
	clear.pressed.connect(func():
		Store.settings["background"] = ""
		Store.save_data())
	bg_row.add_child(clear)
	inner.add_child(bg_row)

	body.add_child(_scroll(inner))

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
	file_dialog.file_selected.connect(_on_background_chosen)
	add_child(file_dialog)
	return page


func _pick_background() -> void:
	if OS.get_name() == "Android":
		OS.request_permissions()
	file_dialog.popup_centered_ratio(0.9)


func _on_background_chosen(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		wp_status.text = "Couldn't open that image. Try a PNG or JPG from your gallery."
		return
	# Keep a private copy so the image still works if the original moves.
	var target: Vector2i = renderer.wallpaper_size()
	var k := maxf(float(target.x) / img.get_width(), float(target.y) / img.get_height())
	if k < 1.0:
		img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
	img.save_png("user://background.png")
	Store.settings["background"] = "user://background.png"
	Store.save_data()


func _queue_wallpaper_refresh(delay: float = 0.8) -> void:
	_refresh_timer.start(delay)


## Renders the next days' wallpapers, updates the preview and sets today's wallpaper.
func _refresh_wallpapers() -> void:
	if renderer.busy:
		_refresh_pending = true
		return
	wp_status.text = "Making wallpapers…"
	var days: int = Store.settings.get("days_ahead", 14)
	var folder: String = await renderer.render_all(days)
	var today := Store.today()
	var today_path: String = renderer.path_for(today)
	var img := Image.load_from_file(today_path)
	if img != null and not img.is_empty():
		preview.texture = ImageTexture.create_from_image(img)

	var which: int = Store.settings.get("which", 3)
	var ready_until := Store.pretty_date(Store.add_days(today, days - 1))
	if not AndroidWallpaper.is_android():
		wp_status.text = "Preview of today's wallpaper. On your Android phone this becomes the wallpaper.\nWallpapers ready until %s." % ready_until
	elif Store.settings.get("auto_daily", true) and AndroidWallpaper.has_plugin():
		AndroidWallpaper.enable_daily(folder, which)
		wp_status.text = "Wallpaper set. It changes by itself every day until %s. Open the app once in a while to keep it going." % ready_until
	elif AndroidWallpaper.apply(today_path, which):
		if AndroidWallpaper.has_plugin():
			wp_status.text = "Wallpaper set for today."
		else:
			wp_status.text = "Wallpaper set for today. It updates each time you open the app (the daily plugin isn't in this build)."
	else:
		wp_status.text = "Couldn't set the wallpaper. Check that the Set Wallpaper permission is on in the Android export."

	if _refresh_pending:
		_refresh_pending = false
		_queue_wallpaper_refresh(0.1)


# ================================================================ editors

func _open_event_editor(e: Dictionary) -> void:
	var is_new := e.is_empty()
	if is_new:
		var wd := Store.weekday(selected_date)
		e = {"id": "", "title": "", "start": "08:00", "end": "09:00", "repeat": "daily",
			"days": [wd], "date": selected_date, "color": Store.EVENT_COLORS[Store.events.size() % Store.EVENT_COLORS.size()]}
	var form := _open_sheet("New schedule item" if is_new else "Edit schedule item")

	var title := LineEdit.new()
	title.placeholder_text = "Title (e.g. Math class)"
	title.text = e.get("title", "")
	form.add_child(title)

	form.add_child(_label("Starts", 22, MUTED))
	var start_picker := _time_picker(e.get("start", "08:00"))
	form.add_child(start_picker)
	var has_end := CheckButton.new()
	has_end.text = "Ends at"
	has_end.button_pressed = e.get("end", "") != ""
	form.add_child(has_end)
	var end_picker := _time_picker(e.get("end", "") if e.get("end", "") != "" else "09:00")
	end_picker.visible = has_end.button_pressed
	has_end.toggled.connect(func(on): end_picker.visible = on)
	form.add_child(end_picker)

	# Repeat type
	var type_row := HBoxContainer.new()
	type_row.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	var daily_btn := _toggle("Repeats", group)
	var once_btn := _toggle("One time", group)
	type_row.add_child(daily_btn)
	type_row.add_child(once_btn)
	form.add_child(type_row)

	var days_row := HBoxContainer.new()
	days_row.add_theme_constant_override("separation", 6)
	var day_buttons := {}
	for d in [1, 2, 3, 4, 5, 6, 0]:
		var b := _toggle(Store.WEEKDAY_SHORT[d].left(2), null)
		b.button_pressed = d in e.get("days", [])
		days_row.add_child(b)
		day_buttons[d] = b
	var quick_row := HBoxContainer.new()
	quick_row.add_theme_constant_override("separation", 8)
	for preset in [["Every day", [0, 1, 2, 3, 4, 5, 6]], ["Weekdays", [1, 2, 3, 4, 5]], ["Weekends", [0, 6]]]:
		var qb := _small_button(preset[0])
		qb.size_flags_horizontal = SIZE_EXPAND_FILL
		qb.pressed.connect(func():
			for d in day_buttons:
				day_buttons[d].button_pressed = d in preset[1])
		quick_row.add_child(qb)
	form.add_child(days_row)
	form.add_child(quick_row)

	var date_picker := _date_picker(e.get("date", selected_date))
	form.add_child(date_picker)

	var sync_type := func():
		var once := once_btn.button_pressed
		days_row.visible = not once
		quick_row.visible = not once
		date_picker.visible = once
	daily_btn.toggled.connect(func(_on): sync_type.call())
	once_btn.toggled.connect(func(_on): sync_type.call())
	if e.get("repeat", "daily") == "once":
		once_btn.button_pressed = true
	else:
		daily_btn.button_pressed = true
	sync_type.call()

	# Color
	var color_row := HBoxContainer.new()
	color_row.add_theme_constant_override("separation", 10)
	var color_group := ButtonGroup.new()
	var chosen := {"color": e.get("color", Store.EVENT_COLORS[0])}
	for c in Store.EVENT_COLORS:
		var sw := Button.new()
		sw.toggle_mode = true
		sw.button_group = color_group
		sw.custom_minimum_size = Vector2(64, 64)
		sw.add_theme_stylebox_override("normal", _box(Color(c), 32, 0))
		sw.add_theme_stylebox_override("hover", _box(Color(c).lightened(0.1), 32, 0))
		var ring := _box(Color(c), 32, 0)
		ring.border_color = TEXT
		ring.set_border_width_all(4)
		sw.add_theme_stylebox_override("pressed", ring)
		sw.add_theme_stylebox_override("hover_pressed", ring)
		sw.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		sw.button_pressed = c == chosen["color"]
		sw.pressed.connect(func(): chosen["color"] = c)
		color_row.add_child(sw)
	form.add_child(color_row)

	var error := _label("", 22, RED)
	form.add_child(error)

	var on_save := func():
		var t := title.text.strip_edges()
		if t == "":
			error.text = "Give it a title."
			return
		var days: Array = []
		for d in day_buttons:
			if day_buttons[d].button_pressed:
				days.append(d)
		if daily_btn.button_pressed and days.is_empty():
			error.text = "Pick at least one day."
			return
		e["title"] = t
		e["start"] = start_picker.get_meta("value").call()
		e["end"] = end_picker.get_meta("value").call() if has_end.button_pressed else ""
		e["repeat"] = "once" if once_btn.button_pressed else "daily"
		e["days"] = days
		e["date"] = date_picker.get_meta("value").call()
		e["color"] = chosen["color"]
		_close_sheet()
		if e["repeat"] == "once":
			selected_date = e["date"]
		Store.upsert_event(e)
	var on_delete := Callable()
	if not is_new:
		on_delete = func():
			_close_sheet()
			Store.delete_event(e["id"])
	_sheet_buttons(form, on_save, on_delete)


func _open_assignment_editor(a: Dictionary) -> void:
	var is_new := a.is_empty()
	if is_new:
		a = {"id": "", "title": "", "notes": "", "due": Store.add_days(Store.today(), 1), "due_time": "23:59", "done": false}
	var form := _open_sheet("New assignment" if is_new else "Edit assignment")

	var title := LineEdit.new()
	title.placeholder_text = "Title (e.g. History essay)"
	title.text = a.get("title", "")
	form.add_child(title)

	var notes := TextEdit.new()
	notes.placeholder_text = "Notes (pages, requirements, links…)"
	notes.text = a.get("notes", "")
	notes.custom_minimum_size = Vector2(0, 180)
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	form.add_child(notes)

	form.add_child(_label("Due date", 22, MUTED))
	var date_picker := _date_picker(a.get("due", Store.today()))
	form.add_child(date_picker)

	var has_time := CheckButton.new()
	has_time.text = "Due at a specific time"
	has_time.button_pressed = a.get("due_time", "") != ""
	form.add_child(has_time)
	var time_picker := _time_picker(a.get("due_time", "") if a.get("due_time", "") != "" else "23:59")
	time_picker.visible = has_time.button_pressed
	has_time.toggled.connect(func(on): time_picker.visible = on)
	form.add_child(time_picker)

	var error := _label("", 22, RED)
	form.add_child(error)

	var on_save := func():
		var t := title.text.strip_edges()
		if t == "":
			error.text = "Give it a title."
			return
		a["title"] = t
		a["notes"] = notes.text.strip_edges()
		a["due"] = date_picker.get_meta("value").call()
		a["due_time"] = time_picker.get_meta("value").call() if has_time.button_pressed else ""
		_close_sheet()
		Store.upsert_assignment(a)
	var on_delete := Callable()
	if not is_new:
		on_delete = func():
			_close_sheet()
			Store.delete_assignment(a["id"])
	_sheet_buttons(form, on_save, on_delete)


## Opens a full-screen sheet and returns the VBox to put fields in.
func _open_sheet(heading: String) -> VBoxContainer:
	_close_sheet()
	var overlay := ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.set_anchors_preset(PRESET_FULL_RECT)
	overlay.mouse_filter = MOUSE_FILTER_STOP
	add_child(overlay)
	_overlay = overlay

	var margin := MarginContainer.new()
	margin.set_anchors_preset(PRESET_FULL_RECT)
	var top := 40
	if OS.has_feature("mobile"):
		top = 80
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", top)
	overlay.add_child(margin)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(SURFACE, 28, 28))
	margin.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 16)
	scroll.add_child(form)
	form.add_child(_label(heading, 36, TEXT))
	return form


func _sheet_buttons(form: VBoxContainer, on_save: Callable, on_delete: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	if on_delete.is_valid():
		var del := _secondary_button("Delete")
		del.add_theme_color_override("font_color", RED)
		del.pressed.connect(on_delete)
		row.add_child(del)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	var cancel := _secondary_button("Cancel")
	cancel.pressed.connect(_close_sheet)
	row.add_child(cancel)
	var save := _primary_button("Save")
	save.size_flags_horizontal = SIZE_FILL
	save.custom_minimum_size = Vector2(160, 84)
	save.pressed.connect(on_save)
	row.add_child(save)
	form.add_child(row)


func _close_sheet() -> void:
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null


# ================================================================ pickers

## Hour / minute / AM-PM dropdowns. get_meta("value").call() returns "HH:MM".
func _time_picker(hhmm: String) -> HBoxContainer:
	var parts := hhmm.split(":")
	var h := int(parts[0]) if parts.size() == 2 else 8
	var m := int(parts[1]) if parts.size() == 2 else 0
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var hour := OptionButton.new()
	for i in range(1, 13):
		hour.add_item(str(i), i)
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	hour.select(h12 - 1)
	hour.size_flags_horizontal = SIZE_EXPAND_FILL

	var minute := OptionButton.new()
	var minute_values := [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55]
	if not (m in minute_values):
		minute_values.append(m)
		minute_values.sort()
	for v in minute_values:
		minute.add_item("%02d" % v, v)
	minute.select(minute_values.find(m))
	minute.size_flags_horizontal = SIZE_EXPAND_FILL

	var ampm := OptionButton.new()
	ampm.add_item("AM", 0)
	ampm.add_item("PM", 1)
	ampm.select(0 if h < 12 else 1)
	ampm.size_flags_horizontal = SIZE_EXPAND_FILL

	row.add_child(hour)
	row.add_child(_label(":", 30, MUTED))
	row.add_child(minute)
	row.add_child(ampm)
	row.set_meta("value", func() -> String:
		var hh := hour.get_selected_id() % 12
		if ampm.get_selected_id() == 1:
			hh += 12
		return "%02d:%02d" % [hh, minute.get_selected_id()])
	return row


## Date stepper: « ‹ Wed, Sep 30 › ». get_meta("value").call() returns "YYYY-MM-DD".
func _date_picker(date: String) -> HBoxContainer:
	var state := {"date": date if Store.is_valid_date(date) else Store.today()}
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := _label("", 28, TEXT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	var update := func(): label.text = Store.pretty_date(state["date"])
	for step in [[-7, "«"], [-1, "‹"]]:
		var b := _small_button(step[1])
		b.pressed.connect(func():
			state["date"] = Store.add_days(state["date"], step[0])
			update.call())
		row.add_child(b)
	row.add_child(label)
	for step in [[1, "›"], [7, "»"]]:
		var b := _small_button(step[1])
		b.pressed.connect(func():
			state["date"] = Store.add_days(state["date"], step[0])
			update.call())
		row.add_child(b)
	update.call()
	row.set_meta("value", func() -> String: return state["date"])
	return row


# ================================================================ small UI helpers

func _page(heading: String) -> Control:
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 16)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	margin.add_child(body)
	body.add_child(_label(heading, 44, TEXT))
	margin.set_meta("body", body)
	return margin


func _scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = SIZE_EXPAND_FILL
	s.add_child(child)
	return s


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = MOUSE_FILTER_IGNORE
	return l


func _empty_note(text: String) -> Label:
	var l := _label(text, 24, MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 200)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## Round "mark as done" button: an empty ring, or a filled circle with a check mark.
func _done_toggle(id: String, done: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = done
	b.custom_minimum_size = Vector2(60, 60)
	b.size_flags_vertical = SIZE_SHRINK_CENTER
	var ring := _box(Color(0, 0, 0, 0), 30, 0)
	ring.border_color = MUTED
	ring.set_border_width_all(3)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, ring)
	for st in ["pressed", "hover_pressed"]:
		b.add_theme_stylebox_override(st, _box(GREEN, 30, 0))
	b.draw.connect(func():
		if b.button_pressed:
			b.draw_polyline(PackedVector2Array([Vector2(17, 31), Vector2(26, 40), Vector2(44, 21)]), Color.WHITE, 5.0, true))
	b.toggled.connect(func(on): Store.set_assignment_done(id, on))
	return b


## A rounded card that grows with its content. Use _on_tap() to make it clickable.
func _card_button() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _box(SURFACE, 20, 20))
	# PASS lets the ScrollContainer still receive drags that start on the card.
	p.mouse_filter = MOUSE_FILTER_PASS
	return p


## Calls 'action' when the control is tapped (not when the finger drags to scroll).
func _on_tap(c: Control, action: Callable) -> void:
	var state := {"down": Vector2.ZERO, "pressed": false}
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
			if ev.pressed:
				state["down"] = ev.global_position
				state["pressed"] = true
			elif state["pressed"]:
				state["pressed"] = false
				if ev.global_position.distance_to(state["down"]) < 24:
					action.call())


func _primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 92)
	b.add_theme_stylebox_override("normal", _box(ACCENT, 20, 12))
	b.add_theme_stylebox_override("hover", _box(ACCENT.lightened(0.08), 20, 12))
	b.add_theme_stylebox_override("pressed", _box(ACCENT.darkened(0.1), 20, 12))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color("#1a1208"))
	b.add_theme_color_override("font_hover_color", Color("#1a1208"))
	b.add_theme_color_override("font_pressed_color", Color("#1a1208"))
	return b


func _secondary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 84)
	return b


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(64, 72)
	return b


func _toggle(text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	if group != null:
		b.button_group = group
	b.size_flags_horizontal = SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_stylebox_override("pressed", _box(BLUE, 16, 8))
	b.add_theme_stylebox_override("hover_pressed", _box(BLUE.lightened(0.08), 16, 8))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_pressed_color", Color.WHITE)
	return b


func _box(color: Color, radius: int, pad: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb


func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 26
	for kind in ["Button", "OptionButton", "CheckBox", "CheckButton"]:
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_hover_color", kind, TEXT)
		t.set_color("font_pressed_color", kind, TEXT)
		t.set_color("font_focus_color", kind, TEXT)
	for kind in ["Button", "OptionButton"]:
		t.set_stylebox("normal", kind, _box(SURFACE_2, 16, 14))
		t.set_stylebox("hover", kind, _box(SURFACE_2.lightened(0.06), 16, 14))
		t.set_stylebox("pressed", kind, _box(SURFACE_2.darkened(0.1), 16, 14))
		t.set_stylebox("focus", kind, StyleBoxEmpty.new())
	for kind in ["LineEdit", "TextEdit"]:
		t.set_stylebox("normal", kind, _box(BG, 14, 16))
		t.set_stylebox("focus", kind, _box(BG.lightened(0.04), 14, 16))
		t.set_color("font_color", kind, TEXT)
		t.set_color("font_placeholder_color", kind, MUTED)
	t.set_constant("minimum_character_width", "LineEdit", 4)
	t.set_color("font_color", "Label", TEXT)
	var popup := _box(SURFACE_2, 14, 10)
	t.set_stylebox("panel", "PopupMenu", popup)
	t.set_font_size("font_size", "PopupMenu", 30)
	t.set_constant("v_separation", "PopupMenu", 18)
	return t
