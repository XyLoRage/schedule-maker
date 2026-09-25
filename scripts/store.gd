extends Node
## Saves and loads everything the app knows: schedule events, assignments and settings.
## Dates are stored as "YYYY-MM-DD" strings and times as "HH:MM" strings.

signal changed

const SAVE_PATH := "user://data.json"
const DAY_SECONDS := 86400
const WEEKDAY_NAMES := ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
const WEEKDAY_SHORT := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
const MONTH_SHORT := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const EVENT_COLORS := ["#6c8cff", "#ff7a59", "#35c28f", "#f5b83d", "#c46cff", "#ff5c8a"]

## Event: {id, title, start, end, repeat ("daily" | "once"), days [weekday ints, 0 = Sunday], date, color}
var events: Array = []
## Assignment: {id, title, notes, due (date), due_time, done}
var assignments: Array = []
## which: 1 = home screen, 2 = lock screen, 3 = both
var settings := {
	"background": "",
	"auto_daily": true,
	"which": 3,
	"days_ahead": 14,
}


func _ready() -> void:
	load_data()


# ---------------------------------------------------------------- saving

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var text := FileAccess.get_file_as_string(SAVE_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Save file was unreadable; starting fresh.")
		return
	events = parsed.get("events", [])
	assignments = parsed.get("assignments", [])
	var saved_settings: Dictionary = parsed.get("settings", {})
	for key in saved_settings:
		settings[key] = saved_settings[key]
	# JSON turns ints into floats; fix the weekday lists.
	for e in events:
		var fixed: Array = []
		for d in e.get("days", []):
			fixed.append(int(d))
		e["days"] = fixed
	settings["which"] = int(settings["which"])
	settings["days_ahead"] = int(settings["days_ahead"])


func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Could not save: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify({
		"events": events,
		"assignments": assignments,
		"settings": settings,
	}, "\t"))
	f.close()
	changed.emit()


func new_id() -> String:
	return "%d_%d" % [Time.get_unix_time_from_system() * 1000, randi() % 100000]


# ---------------------------------------------------------------- events

func upsert_event(e: Dictionary) -> void:
	_upsert(events, e)


func delete_event(id: String) -> void:
	events = events.filter(func(x): return x["id"] != id)
	save_data()


func events_for_date(date: String) -> Array:
	var wd := weekday(date)
	var out: Array = []
	for e in events:
		if e.get("repeat", "daily") == "once":
			if e.get("date", "") == date:
				out.append(e)
		elif wd in e.get("days", []):
			out.append(e)
	out.sort_custom(func(a, b): return a.get("start", "") < b.get("start", ""))
	return out


# ---------------------------------------------------------------- assignments

func upsert_assignment(a: Dictionary) -> void:
	_upsert(assignments, a)


func delete_assignment(id: String) -> void:
	assignments = assignments.filter(func(x): return x["id"] != id)
	save_data()


func set_assignment_done(id: String, done: bool) -> void:
	for a in assignments:
		if a["id"] == id:
			a["done"] = done
	save_data()


## Assignments sorted by due date; unfinished ones first.
func sorted_assignments() -> Array:
	var out := assignments.duplicate()
	out.sort_custom(func(a, b):
		if a.get("done", false) != b.get("done", false):
			return not a.get("done", false)
		var ka: String = a.get("due", "") + " " + a.get("due_time", "23:59")
		var kb: String = b.get("due", "") + " " + b.get("due_time", "23:59")
		return ka < kb)
	return out


## Unfinished assignments due within 'window' days of 'date' (overdue ones included).
func upcoming_assignments(date: String, window: int = 14) -> Array:
	var out: Array = []
	for a in sorted_assignments():
		if a.get("done", false):
			continue
		if days_between(date, a.get("due", date)) <= window:
			out.append(a)
	return out


func _upsert(list: Array, item: Dictionary) -> void:
	if not item.has("id") or item["id"] == "":
		item["id"] = new_id()
	for i in list.size():
		if list[i]["id"] == item["id"]:
			list[i] = item
			save_data()
			return
	list.append(item)
	save_data()


# ---------------------------------------------------------------- dates

func today() -> String:
	return Time.get_date_string_from_system()


func date_to_unix(date: String) -> int:
	return Time.get_unix_time_from_datetime_string(date + "T00:00:00")


func add_days(date: String, n: int) -> String:
	return Time.get_date_string_from_unix_time(date_to_unix(date) + n * DAY_SECONDS)


func days_between(from_date: String, to_date: String) -> int:
	return int(round(float(date_to_unix(to_date) - date_to_unix(from_date)) / DAY_SECONDS))


func weekday(date: String) -> int:
	return Time.get_date_dict_from_unix_time(date_to_unix(date))["weekday"]


func is_valid_date(date: String) -> bool:
	var parts := date.split("-")
	if parts.size() != 3 or not parts[0].is_valid_int() or not parts[1].is_valid_int() or not parts[2].is_valid_int():
		return false
	var m := int(parts[1])
	var d := int(parts[2])
	return m >= 1 and m <= 12 and d >= 1 and d <= 31 and add_days(date, 0) == date


## "Wed, Sep 30"
func pretty_date(date: String) -> String:
	var d := Time.get_date_dict_from_unix_time(date_to_unix(date))
	return "%s, %s %d" % [WEEKDAY_SHORT[d["weekday"]], MONTH_SHORT[d["month"] - 1], d["day"]]


## "8:30 AM"
func pretty_time(hhmm: String) -> String:
	var parts := hhmm.split(":")
	if parts.size() != 2:
		return hhmm
	var h := int(parts[0])
	var m := int(parts[1])
	var suffix := "AM" if h < 12 else "PM"
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, suffix]


## Countdown text for an assignment as seen on 'date', e.g. "Due tomorrow", "3 days overdue".
func due_text(a: Dictionary, date: String) -> String:
	var n := days_between(date, a.get("due", date))
	var t := ""
	if a.get("due_time", "") != "":
		t = " at " + pretty_time(a["due_time"])
	if n < -1:
		return "%d days overdue" % -n
	if n == -1:
		return "Overdue since yesterday"
	if n == 0:
		return "Due today" + t
	if n == 1:
		return "Due tomorrow" + t
	return "Due in %d days" % n


## 0 = overdue/today (red), 1 = soon (amber, within 3 days), 2 = later
func due_urgency(a: Dictionary, date: String) -> int:
	var n := days_between(date, a.get("due", date))
	if n <= 0:
		return 0
	if n <= 3:
		return 1
	return 2
