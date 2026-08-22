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
	var kind: String = str(fn.get("name", ""))
	var args_raw: String = str(fn.get("arguments", "{}"))
	var args: Variant = JSON.parse_string(args_raw)
	if typeof(args) != TYPE_DICTIONARY:
		return _fail("tool arguments not a JSON object: %s" % args_raw)
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


static func _extract_error(body: Dictionary) -> String:
	if body.has("error"):
		var err: Variant = body["error"]
		if typeof(err) == TYPE_DICTIONARY:
			return str(err.get("message", err))
		return str(err)
	return ""


static func _fail(error: String, raw_text: String = "") -> Dictionary:
	return {"ok": false, "action": {}, "raw_text": raw_text, "error": error}
