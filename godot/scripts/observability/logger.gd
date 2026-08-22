extends Node
class_name ObservabilityLogger
##
## 决策日志 → data/logs/{session}.jsonl
##

var _session_id: String = ""
var _log_path: String = ""


func _ready() -> void:
	_session_id = Time.get_datetime_string_from_system().replace(":", "-")
	var log_dir := Config.repo_root().path_join("data/logs")
	DirAccess.make_dir_recursive_absolute(log_dir)
	_log_path = log_dir.path_join("%s.jsonl" % _session_id)


func log_decision(entry: Dictionary) -> void:
	if _log_path.is_empty():
		return
	var file := FileAccess.open(_log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(_log_path, FileAccess.WRITE)
	if file == null:
		push_warning("[Logger] cannot open %s" % _log_path)
		return
	file.seek_end()
	file.store_line(JSON.stringify(entry))
	file.close()


func session_path() -> String:
	return _log_path
