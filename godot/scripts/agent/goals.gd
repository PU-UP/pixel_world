extends Node
class_name AgentGoals
##
## 当前目标 + 长期目标 — 持久化到 data/goals/
##

var agent_id: String = ""
var current_goal: String = ""
var long_term_goal: String = ""


func open(id: String) -> void:
	agent_id = id
	var path: String = _file_path()
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY:
			current_goal = str(parsed.get("current_goal", "")).strip_edges()
			long_term_goal = str(parsed.get("long_term_goal", "")).strip_edges()
			return
	current_goal = ""
	long_term_goal = ""


func seed_from_config(cfg: Dictionary) -> void:
	if not long_term_goal.is_empty() or not current_goal.is_empty():
		return
	if cfg.has("long_term_goal"):
		long_term_goal = str(cfg.get("long_term_goal", "")).strip_edges()
	if cfg.has("current_goal"):
		current_goal = str(cfg.get("current_goal", "")).strip_edges()
	if long_term_goal.is_empty():
		long_term_goal = _default_long_term(str(cfg.get("id", "")))
	if current_goal.is_empty():
		current_goal = _default_current(str(cfg.get("id", "")))


func set_current(text: String) -> void:
	current_goal = text.strip_edges()
	_save()


func set_long_term(text: String) -> void:
	long_term_goal = text.strip_edges()
	_save()


func format_for_prompt() -> String:
	var parts: PackedStringArray = PackedStringArray()
	if not long_term_goal.is_empty():
		parts.append("长期目标: %s" % long_term_goal)
	if not current_goal.is_empty():
		parts.append("当前目标: %s" % current_goal)
	return "\n".join(parts)


func _file_path() -> String:
	return Config.repo_root().path_join("data/goals").path_join("%s.json" % agent_id)


func _save() -> void:
	if agent_id.is_empty():
		return
	var dir: String = Config.repo_root().path_join("data/goals")
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(_file_path(), FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"current_goal": current_goal,
		"long_term_goal": long_term_goal,
	}, "\t"))


static func _default_long_term(id: String) -> String:
	match id:
		"explorer":
			return "绘制整座荒岛的完整地图并标注可通行路线"
		"scout":
			return "掌握全岛地形与视野制高点，及时通报异动"
		"sage":
			return "与岛上众人深谈，从对话中理解这座岛与人的故事"
		"wanderer":
			return "漫游全岛，在海滩与林间寻找志趣相投的同伴"
		"guardian":
			return "守护岛上所有人的安全，熟悉每一处地形边界"
		_:
			return "探索并理解这座荒岛"


static func _default_current(id: String) -> String:
	match id:
		"explorer":
			return "扩展已探索区域，记录地形与路线"
		"scout":
			return "占据制高点侦察周边，留意异常"
		"sage":
			return "寻找可交谈的对象，分享见闻与思考"
		"wanderer":
			return "沿海岸与草地随意漫游，偶遇有趣之事"
		"guardian":
			return "巡逻熟悉区域，确认同伴安全"
		_:
			return "观察周围环境并决定下一步行动"
