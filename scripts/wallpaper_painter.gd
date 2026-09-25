extends Control
## Draws one day's wallpaper: the day's events and upcoming due dates on top of the background.
## The top ~35% is left clear so the lock screen clock doesn't cover anything.

var date: String = ""
var background: Texture2D = null

const INK := Color("#f7f5f0")
const INK_SOFT := Color(0.97, 0.96, 0.94, 0.72)
const CARD := Color(0.07, 0.08, 0.12, 0.62)
const RED := Color("#ff6b6b")
const AMBER := Color("#ffc857")
const GREEN := Color("#7ee0b0")


func _draw() -> void:
	if date == "":
		return
	var w := size.x
	var h := size.y
	var s := w / 1080.0 # scale everything from a 1080-wide design
	var font: Font = ThemeDB.fallback_font

	_draw_background(w, h)

	var margin := 64.0 * s
	var card_top := h * 0.36
	var card_bottom := h - 150.0 * s
	var card := Rect2(margin, card_top, w - margin * 2, card_bottom - card_top)
	var box := StyleBoxFlat.new()
	box.bg_color = CARD
	box.set_corner_radius_all(int(48 * s))
	draw_style_box(box, card)

	var x := card.position.x + 56 * s
	var inner_w := card.size.x - 112 * s
	var y := card.position.y + 110 * s

	# Header: weekday + date
	var d := Time.get_date_dict_from_unix_time(Store.date_to_unix(date))
	var months := ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	draw_string(font, Vector2(x, y), Store.WEEKDAY_NAMES[d["weekday"]].to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, int(76 * s), INK)
	y += 62 * s
	draw_string(font, Vector2(x, y), "%s %d" % [months[d["month"] - 1], d["day"]], HORIZONTAL_ALIGNMENT_LEFT, -1, int(40 * s), INK_SOFT)
	y += 80 * s

	var limit_y := card.end.y - 60 * s
	var due := Store.upcoming_assignments(date, 14)
	var events := Store.events_for_date(date)

	# Reserve room for the due list so a busy day doesn't push it off the card.
	var due_rows := mini(due.size(), 4)
	var due_block := 0.0
	if due_rows > 0:
		due_block = 90 * s + due_rows * 104 * s
	var events_limit := limit_y - due_block

	# Schedule
	y = _section_title(font, x, y, "SCHEDULE", s)
	if events.is_empty():
		draw_string(font, Vector2(x, y + 36 * s), "Nothing scheduled — free day", HORIZONTAL_ALIGNMENT_LEFT, -1, int(36 * s), INK_SOFT)
		y += 76 * s
	else:
		var shown := 0
		for e in events:
			if y + 96 * s > events_limit and shown < events.size():
				var left := events.size() - shown
				draw_string(font, Vector2(x, y + 34 * s), "+%d more" % left, HORIZONTAL_ALIGNMENT_LEFT, -1, int(32 * s), INK_SOFT)
				y += 60 * s
				break
			var col := Color(e.get("color", "#6c8cff"))
			draw_rect(Rect2(x, y, 10 * s, 76 * s), col)
			var time_text := Store.pretty_time(e.get("start", ""))
			if e.get("end", "") != "":
				time_text += " – " + Store.pretty_time(e["end"])
			draw_string(font, Vector2(x + 34 * s, y + 30 * s), time_text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * s), INK_SOFT)
			draw_string(font, Vector2(x + 34 * s, y + 72 * s), _fit(font, e.get("title", ""), inner_w - 34 * s, int(40 * s)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(40 * s), INK)
			y += 100 * s
			shown += 1

	# Due dates
	if due_rows > 0:
		y = maxf(y + 20 * s, events_limit)
		y = _section_title(font, x, y, "DUE SOON", s)
		for i in due_rows:
			var a: Dictionary = due[i]
			var urgency := Store.due_urgency(a, date)
			var col: Color = [RED, AMBER, GREEN][urgency]
			draw_circle(Vector2(x + 10 * s, y + 26 * s), 10 * s, col)
			draw_string(font, Vector2(x + 38 * s, y + 38 * s), _fit(font, a.get("title", ""), inner_w - 38 * s, int(38 * s)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(38 * s), INK)
			var sub := Store.due_text(a, date)
			var note: String = a.get("notes", "").strip_edges().split("\n")[0]
			if note != "":
				sub += "  ·  " + note
			draw_string(font, Vector2(x + 38 * s, y + 80 * s), _fit(font, sub, inner_w - 38 * s, int(30 * s)), HORIZONTAL_ALIGNMENT_LEFT, -1, int(30 * s), col.lerp(INK, 0.35))
			y += 104 * s
		if due.size() > due_rows:
			draw_string(font, Vector2(x, y + 20 * s), "+%d more assignments" % (due.size() - due_rows), HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), INK_SOFT)


func _section_title(font: Font, x: float, y: float, text: String, s: float) -> float:
	draw_string(font, Vector2(x, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(28 * s), Color(1, 1, 1, 0.55))
	return y + 30 * s


func _draw_background(w: float, h: float) -> void:
	if background != null:
		# Scale to cover the whole screen, cropping the overflow.
		var tex_size := background.get_size()
		var k := maxf(w / tex_size.x, h / tex_size.y)
		var draw_size := tex_size * k
		draw_texture_rect(background, Rect2((Vector2(w, h) - draw_size) / 2.0, draw_size), false)
		return
	# Default: soft diagonal gradient
	var top := Color("#28305a")
	var bottom := Color("#0f1220")
	var accent := Color("#ff7a59")
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([top, top.lerp(accent, 0.35), bottom, bottom]))


## Shortens text with "…" so it fits in max_width.
func _fit(font: Font, text: String, max_width: float, font_size: int) -> String:
	if font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= max_width:
		return text
	var t := text
	while t.length() > 1 and font.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > max_width:
		t = t.left(t.length() - 1)
	return t.strip_edges() + "…"
