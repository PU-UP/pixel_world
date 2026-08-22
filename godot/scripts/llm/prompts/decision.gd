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
	nearby_agent_ids: PackedStringArray = [],
	heard_lines: PackedStringArray = [],
	plan_lines: PackedStringArray = [],
	relationship_lines: PackedStringArray = [],
	item_lines: PackedStringArray = [],
) -> Array:
	var system := """You are an autonomous agent in a 2D pixel island world with other agents.
Each game tick you must choose exactly ONE action using the provided tool.
Available actions: MOVE_TO (walk to tile x,y), SAY (talk to agent_id or broadcast),
PICK_UP (item id on ground within range), DROP (item id from your inventory),
USE (item from inventory; on = self, agent_id, or nearby item id),
GIVE (item from inventory to nearby agent_id within audio range),
OBSERVE (target = agent_id or item id for extra details).
SAY and GIVE only reach agents within audio range. Use nearby agent ids from the prompt.
PICK_UP requires being within 1 tile of the item. Check items list for ids.
If a nearby agent is marked familiar (high familiarity), prefer greeting them with SAY when appropriate.
Follow your current plan when possible, but adapt to new observations.
Coordinates are tile positions (integers). You cannot walk on water, trees, or mountains.
Respond ONLY via tool/function call — no free-form answer."""
	var user_parts: PackedStringArray = []
	user_parts.append("=== Persona ===\n%s" % persona_desc)
	user_parts.append("=== Status ===\n%s" % status)
	user_parts.append("=== Observation (terrain + nearby agents) ===\n%s" % observation)
	if plan_lines.size() > 0:
		user_parts.append("=== Current plan (remaining steps) ===\n%s" % "\n".join(plan_lines))
	if nearby_agent_ids.size() > 0:
		user_parts.append("=== Nearby agent ids (for SAY.to) ===\n%s" % ", ".join(nearby_agent_ids))
	if relationship_lines.size() > 0:
		user_parts.append("=== Relationships (nearby) ===\n%s" % "\n".join(relationship_lines))
	if item_lines.size() > 0:
		user_parts.append("=== Ground items (nearby, for PICK_UP.item) ===\n%s" % "\n".join(item_lines))
	if heard_lines.size() > 0:
		user_parts.append("=== Recently heard speech ===\n%s" % "\n".join(heard_lines))
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
		if kind == AgentActions.KIND_SAY:
			props["tone"] = {"type": "string", "description": "optional tone, e.g. friendly, curious"}
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
