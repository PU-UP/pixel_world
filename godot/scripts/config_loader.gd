extends Node
##
## 加载仓库根 config/*.yaml 与 .env（autoload: Config）
##

var llm: Dictionary = {}
var runtime: Dictionary = {}
var agents: Dictionary = {}
var world_cfg: Dictionary = {}
var world_items: Dictionary = {}
var world_ground_spawns: Array = []
var world_regions: Array = []
var world_events: Array = []

var _env: Dictionary = {}


func _ready() -> void:
	load_all()


func repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").simplify_path()


func load_all() -> void:
	var root := repo_root()
	_load_env(root.path_join(".env"))
	llm = _load_yaml_file(root.path_join("config/llm.yaml")).get("llm", {})
	runtime = _load_yaml_file(root.path_join("config/runtime.yaml"))
	agents = _load_yaml_file(root.path_join("config/agents.yaml"))
	var world_file: Dictionary = _load_yaml_file(root.path_join("config/world.yaml"))
	world_cfg = world_file.get("world", {})
	world_items = world_file.get("items", {})
	world_ground_spawns = world_file.get("ground_items", [])
	world_regions = world_file.get("regions", [])
	world_events = world_file.get("events", [])
	if _env.has("MINIMAX_BASE_URL"):
		llm["base_url"] = _env["MINIMAX_BASE_URL"]
	if _env.has("MINIMAX_MODEL"):
		llm["model"] = _env["MINIMAX_MODEL"]


func env_get(key: String, default: String = "") -> String:
	return str(_env.get(key, default))


func llm_api_key() -> String:
	var env_name := str(llm.get("api_key_env", "MINIMAX_API_KEY"))
	return env_get(env_name, "")


func tick_hz() -> float:
	return float(runtime.get("tick", {}).get("hz", 2.0))


func llm_concurrency() -> int:
	return int(runtime.get("llm", {}).get("concurrency", llm.get("max_concurrent", 4)))


func control_mode() -> String:
	return str(runtime.get("control", {}).get("mode", "agent"))


func decision_skip_while_walking() -> bool:
	return bool(runtime.get("decision", {}).get("skip_while_walking", false))


func decision_cfg() -> Dictionary:
	return runtime.get("decision", {})


func decision_repeat_say_block_ticks() -> int:
	return int(decision_cfg().get("repeat_say_block_ticks", 40))


func decision_min_ticks_between() -> int:
	return int(decision_cfg().get("min_ticks_between", 0))


func decision_max_say_chars() -> int:
	return int(decision_cfg().get("max_say_chars", 180))


func decision_wait_max_ticks() -> int:
	return int(decision_cfg().get("wait_max_ticks", 20))


func observer_default_god() -> bool:
	return bool(runtime.get("observer", {}).get("default_god", true))


func observer_god_vision_overlay() -> bool:
	return bool(runtime.get("observer", {}).get("god_vision_overlay", true))


func time_cfg() -> Dictionary:
	return runtime.get("time", {})


func time_enabled() -> bool:
	return bool(time_cfg().get("enabled", true))


func time_day_length_ticks() -> int:
	return maxi(1, int(time_cfg().get("day_length_ticks", 240)))


func time_night_perception_scale() -> float:
	return clampf(float(time_cfg().get("night_perception_scale", 0.6)), 0.2, 1.0)


func time_sleep_max_ticks() -> int:
	return maxi(1, int(time_cfg().get("sleep_max_ticks", 240)))


func time_phase_bar_width() -> int:
	return clampi(int(time_cfg().get("phase_bar_width", 8)), 4, 16)


func save_cfg() -> Dictionary:
	return runtime.get("save", {})


func movement_cfg() -> Dictionary:
	return runtime.get("movement", {})


func exploration_cfg() -> Dictionary:
	return runtime.get("exploration", {})


func exploration_stale_overlay() -> bool:
	return bool(exploration_cfg().get("stale_overlay", true))


func exploration_stale_tint() -> Color:
	var raw: Variant = exploration_cfg().get("stale_tint", [0.85, 0.12, 0.62, 0.55])
	if typeof(raw) != TYPE_ARRAY or raw.size() < 3:
		return Color(0.85, 0.12, 0.62, 0.55)
	var a: float = float(raw[3]) if raw.size() >= 4 else 0.55
	return Color(float(raw[0]), float(raw[1]), float(raw[2]), a)


func agent_config() -> Dictionary:
	var list: Array = all_agents()
	if list.is_empty():
		return {}
	return list[0]


func all_agents() -> Array:
	return agents.get("agents", [])


func starting_agent_count() -> int:
	return int(runtime.get("agent", {}).get("starting_agents", 1))


func audio_radius() -> int:
	return int(runtime.get("agent", {}).get("audio_radius", 10))


func perception_los_enabled() -> bool:
	return bool(runtime.get("agent", {}).get("los", true))


func perception_los_block_names() -> Array:
	var raw: Variant = runtime.get("agent", {}).get("los_block", ["tree", "mountain"])
	if typeof(raw) != TYPE_ARRAY:
		return ["tree", "mountain"]
	return raw


func memory_cfg() -> Dictionary:
	return runtime.get("memory", {})


func memory_reflection_cfg() -> Dictionary:
	return memory_cfg().get("reflection", {})


func memory_retrieval_cfg() -> Dictionary:
	return memory_cfg().get("retrieval", {})


func planning_cfg() -> Dictionary:
	return runtime.get("planning", {})


func relationships_cfg() -> Dictionary:
	return runtime.get("relationships", {})


func persona_drift_cfg() -> Dictionary:
	return runtime.get("persona_drift", {})


func observability_cfg() -> Dictionary:
	return runtime.get("observability", {})


func world_item_pickup_radius() -> int:
	return int(world_cfg.get("item_pickup_radius", 1))


func world_item_defs() -> Dictionary:
	return world_items


func world_ground_item_spawns() -> Array:
	return world_ground_spawns


func world_region_defs() -> Array:
	return world_regions


func world_event_defs() -> Array:
	return world_events


func _load_env(path: String) -> void:
	_env.clear()
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.is_empty() or line.begins_with("#"):
			continue
		var eq := line.find("=")
		if eq < 1:
			continue
		_env[line.substr(0, eq).strip_edges()] = line.substr(eq + 1).strip_edges()
	f.close()


func _load_yaml_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[Config] missing: %s" % path)
		return {}
	var parsed: Variant = _parse_yaml(FileAccess.get_file_as_string(path))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func _parse_yaml(text: String) -> Variant:
	var lines: PackedStringArray = text.split("\n")
	return _parse_block(lines, 0, -1)[0]


func _parse_block(lines: PackedStringArray, start: int, parent_indent: int) -> Array:
	var result: Dictionary = {}
	var i := start
	while i < lines.size():
		var raw := lines[i]
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			i += 1
			continue
		var indent := _line_indent(raw)
		if parent_indent >= 0 and indent <= parent_indent:
			break
		var colon := line.find(":")
		if colon < 0:
			i += 1
			continue
		var key := line.substr(0, colon).strip_edges()
		var rest := line.substr(colon + 1).strip_edges()
		if rest.is_empty():
			var child_start := i + 1
			var peek := _peek_line(lines, child_start)
			if peek.begins_with("- "):
				var list_result: Array = _parse_list_block(lines, child_start, indent)
				result[key] = list_result[0]
				i = int(list_result[1])
			else:
				var child: Array = _parse_block(lines, child_start, indent)
				result[key] = child[0]
				i = int(child[1])
		else:
			result[key] = _parse_scalar(rest)
			i += 1
	return [result, i]


func _parse_list_block(lines: PackedStringArray, start: int, parent_indent: int) -> Array:
	var items: Array = []
	var i := start
	while i < lines.size():
		var raw := lines[i]
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with("#"):
			i += 1
			continue
		var indent := _line_indent(raw)
		if parent_indent >= 0 and indent <= parent_indent:
			break
		if not line.begins_with("- "):
			break
		var item_text := line.substr(2).strip_edges()
		if item_text.find(":") >= 0 and not item_text.begins_with("["):
			var item_dict: Dictionary = {}
			var kc := item_text.find(":")
			var ik := item_text.substr(0, kc).strip_edges()
			var iv := item_text.substr(kc + 1).strip_edges()
			if iv.is_empty():
				var child: Array = _parse_block(lines, i + 1, indent + 2)
				item_dict[ik] = child[0]
				i = int(child[1])
			else:
				item_dict[ik] = _parse_scalar(iv)
				i += 1
			while i < lines.size():
				var raw2 := lines[i]
				var line2 := raw2.strip_edges()
				if line2.is_empty() or line2.begins_with("#"):
					i += 1
					continue
				var ind2 := _line_indent(raw2)
				if ind2 <= indent:
					break
				if line2.begins_with("- "):
					break
				var c2 := line2.find(":")
				if c2 < 0:
					break
				var k2 := line2.substr(0, c2).strip_edges()
				var v2 := line2.substr(c2 + 1).strip_edges()
				if v2.is_empty():
					var child2: Array = _parse_block(lines, i + 1, ind2)
					item_dict[k2] = child2[0]
					i = int(child2[1])
				else:
					item_dict[k2] = _parse_scalar(v2)
					i += 1
			items.append(item_dict)
		else:
			items.append(_parse_scalar(item_text))
			i += 1
	return [items, i]


func _peek_line(lines: PackedStringArray, start: int) -> String:
	var i := start
	while i < lines.size():
		var line := lines[i].strip_edges()
		if line.is_empty() or line.begins_with("#"):
			i += 1
			continue
		return line
	return ""


func _line_indent(line: String) -> int:
	var n := 0
	for c in line:
		if c == " ":
			n += 1
		elif c == "\t":
			n += 4
		else:
			break
	return n


func _parse_scalar(s: String) -> Variant:
	var comment := s.find(" #")
	if comment >= 0:
		s = s.substr(0, comment).strip_edges()
	if s.begins_with("[") and s.ends_with("]"):
		var inner := s.substr(1, s.length() - 2).strip_edges()
		if inner.is_empty():
			return []
		var arr: Array = []
		for p in inner.split(","):
			arr.append(_parse_scalar(p.strip_edges()))
		return arr
	if s == "true":
		return true
	if s == "false":
		return false
	if s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	if s.is_valid_int():
		return int(s)
	if s.is_valid_float():
		return float(s)
	return s
