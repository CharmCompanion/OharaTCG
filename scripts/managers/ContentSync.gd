extends Node

# Once a week, refresh cards, blocks, and the banlist from the official site,
# and pull new matchup notes from onepiecetopdecks.com. Headless tests skip
# this. The updater panel stays hidden.

const STAMP := "user://content_sync.cfg"
const GAP := 7 * 24 * 3600

var _pid := -1

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.get_name() == "Android":
		return
	for arg in OS.get_cmdline_args():
		if arg == "--script":
			return
	var now := int(Time.get_unix_time_from_system())
	if now - _stamp() < GAP:
		return
	var py := _python()
	var script := ProjectSettings.globalize_path("res://tools/refresh_content.py")
	var proj := ProjectSettings.globalize_path("res://")
	if not FileAccess.file_exists(script):
		return
	_pid = OS.create_process(py, [script, proj])
	if _pid <= 0:
		_pid = -1
		_write_stamp(now)

func _process(_delta: float) -> void:
	if _pid <= 0:
		return
	if OS.is_process_running(_pid):
		return
	_pid = -1
	_write_stamp(int(Time.get_unix_time_from_system()))
	var mark := "res://data/meta/refresh_ok.txt"
	if not FileAccess.file_exists(mark):
		return
	var cards := get_node_or_null("/root/CardDatabase")
	if cards != null and cards.has_method("reload"):
		cards.reload()
	var rules := get_node_or_null("/root/RulesManager")
	if rules != null and rules.has_method("reload"):
		rules.reload()

func _python() -> String:
	var bundled := "C:/Users/RY0M/AppData/Local/Programs/Python/Python314/python.exe"
	if FileAccess.file_exists(bundled):
		return bundled
	return "python"

func _stamp() -> int:
	var f := FileAccess.open(STAMP, FileAccess.READ)
	if f == null:
		return 0
	return int(f.get_as_text().strip_edges())

func _write_stamp(now: int) -> void:
	var f := FileAccess.open(STAMP, FileAccess.WRITE)
	if f != null:
		f.store_string(str(now))
