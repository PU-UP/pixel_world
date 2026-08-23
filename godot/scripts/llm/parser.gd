class_name LlmParser
##
## 解析 OpenAI 兼容 tool_calls 响应 → action dict
##

const AgentActions = preload("res://scripts/agent/actions.gd")


static func parse_response(body: Dictionary) -> Dictionary:
	if body.is_empty():
		return _fail("empty response body")
	var choices: Array = body.get("choices", [])
	if choices.is_empty():
		return _fail("no choices in response", _extract_error(body))
	var message: Dictionary = choices[0].get("message", {})
	var tool_calls: Array = message.get("tool_calls", [])
	if tool_calls.is_empty():
		return _fail("no tool_calls (function calling required)", str(message.get("content", "")))
	var fn: Dictionary = tool_calls[0].get("function", {})
	var kind: String = normalize_kind(str(fn.get("name", "")))
	var args_raw: String = str(fn.get("arguments", "{}"))
	var parsed: Variant = JSON.parse_string(args_raw)
	var args: Dictionary = normalize_tool_args(kind, parsed)
	if args.is_empty() and typeof(parsed) != TYPE_DICTIONARY:
		return _fail("tool arguments not a JSON object: %s" % args_raw, str(message.get("content", "")))
	var action := {"kind": kind, "params": args}
	var validation: Dictionary = AgentActions.validate(action)
	if not validation["ok"]:
		return _fail(validation["error"], str(message.get("content", "")))
	return {
		"ok": true,
		"action": action,
		"raw_text": str(message.get("content", "")),
		"error": "",
	}


## 修复 LLM 常见畸形参数（如 PICK_UP 返回 ["berry_bush"]）
static func normalize_tool_args(kind: String, parsed: Variant) -> Dictionary:
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed.duplicate(true)
	if typeof(parsed) == TYPE_ARRAY:
		if parsed.is_empty():
			return {}
		var first: Variant = parsed[0]
		var s: String = str(first).strip_edges()
		match kind:
			AgentActions.KIND_PICK_UP, AgentActions.KIND_DROP:
				return {"item": s}
			AgentActions.KIND_OBSERVE:
				return {"target": s}
			AgentActions.KIND_USE:
				var on_val: String = "self"
				if parsed.size() > 1:
					on_val = str(parsed[1]).strip_edges()
				return {"item": s, "on": on_val}
			AgentActions.KIND_GIVE:
				if parsed.size() >= 2:
					return {"item": s, "to": str(parsed[1]).strip_edges()}
				return {"item": s}
		return {}
	if typeof(parsed) == TYPE_STRING:
		var text: String = parsed.strip_edges()
		match kind:
			AgentActions.KIND_PICK_UP, AgentActions.KIND_DROP:
				return {"item": text}
			AgentActions.KIND_OBSERVE:
				return {"target": text}
			AgentActions.KIND_SAY:
				return {"to": "broadcast", "text": text}
	return {}


## 常见 tool 名拼写纠错（如 MAY_TO → MOVE_TO）
static func normalize_kind(kind: String) -> String:
	var k: String = kind.strip_edges().to_upper()
	match k:
		"MAY_TO", "MOTE_TO", "MOVETO", "MOVE":
			return AgentActions.KIND_MOVE_TO
	return kind.strip_edges()


static func _extract_error(body: Dictionary) -> String:
	if body.has("error"):
		var err: Variant = body["error"]
		if typeof(err) == TYPE_DICTIONARY:
			return str(err.get("message", err))
		return str(err)
	return ""


static func _fail(error: String, raw_text: String = "") -> Dictionary:
	return {"ok": false, "action": {}, "raw_text": raw_text, "error": error}
