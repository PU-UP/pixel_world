class_name DecisionPrompt
##
## LLM 决策 prompt 模板
##

const AgentActions = preload("res://scripts/agent/actions.gd")


static func build_messages(
	persona_desc: String,
	observation: String,
	status: String,
	action_log: PackedStringArray,
	memory_lines: PackedStringArray = [],
) -> Array:
	var system := """You are an autonomous agent in a 2D pixel island world.
Each game tick you must choose exactly ONE action using the provided tool.
Only use implemented actions. In the current build only MOVE_TO is available.
Coordinates are tile positions (integers). You cannot walk on water, trees, or mountains.
Respond ONLY via tool/function call — no free-form answer."""
	var user_parts: PackedStringArray = []
	user_parts.append("=== Persona ===\n%s" % persona_desc)
	user_parts.append("=== Status ===\n%s" % status)
	user_parts.append("=== Observation (nearby terrain) ===\n%s" % observation)
	if memory_lines.size() > 0:
		user_parts.append("=== Relevant memories ===\n%s" % "\n".join(memory_lines))
	if action_log.size() > 0:
		user_parts.append("=== Recent actions ===\n%s" % "\n".join(action_log))
	user_parts.append("=== Task ===\nChoose your next action for this tick.")
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": "\n\n".join(user_parts)},
	]


static func tool_definitions() -> Array:
	var tools: Array = []
	for kind in AgentActions.IMPLEMENTED_KINDS:
		if not AgentActions.SCHEMAS.has(kind):
			continue
		var schema: Dictionary = AgentActions.SCHEMAS[kind]
		var props: Dictionary = {}
		for f in schema["required"]:
			var t: int = schema["types"][f]
			props[f] = {"type": "integer" if t == TYPE_INT else "string"}
		tools.append({
			"type": "function",
			"function": {
				"name": kind,
				"description": schema["desc"],
				"parameters": {
					"type": "object",
					"properties": props,
					"required": schema["required"],
				},
			},
		})
	return tools
