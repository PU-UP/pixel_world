class_name DecisionPrompt
##
## LLM 决策 prompt + 上下文感知 tool schema（enum 限制合法 target）
##

const AgentActions = preload("res://scripts/agent/actions.gd")


static func build_messages(
	persona_desc: String,
	observation: String,
	status: String,
	memory_lines: PackedStringArray = [],
	perception_agent_ids: PackedStringArray = [],
	audio_agent_ids: PackedStringArray = [],
	observe_agent_ids: PackedStringArray = [],
	ground_item_ids: PackedStringArray = [],
	heard_lines: PackedStringArray = [],
	plan_lines: PackedStringArray = [],
	relationship_lines: PackedStringArray = [],
	item_lines: PackedStringArray = [],
	pending_reply_line: String = "",
	last_say_text: String = "",
	walkable_near_lines: PackedStringArray = [],
	blocked_move_lines: PackedStringArray = [],
	goal_lines: PackedStringArray = [],
) -> Array:
	var system := """You are an autonomous agent in a 2D pixel island world with other agents.
Each game tick you must choose exactly ONE action using the provided tool.
Only tools listed in the request are available — pick one of them.
MOVE_TO uses tile coordinates (integers). You cannot walk on water, trees, or mountains.
Do not MOVE_TO another agent's exact tile — stand on an adjacent walkable tile to talk.
If target is visible but not in audio range, use MOVE_TO to approach before SAY/GIVE.
If someone spoke to you (=== Pending reply ===), respond with SAY using NEW words.
WAIT to stand still for a few ticks when you have nothing urgent to do.
EMOTE shows a short emoji visible to agents in sight (0 ticks). Use Unicode emoji or a short token.
SLEEP until a future tick (usually next dawn) when it is dusk or night; vision shrinks at night.
SAY.text MUST be Simplified Chinese (简体中文), concise (under 120 Chinese characters).
Use SHARE_MAP when you agree to exchange explored map areas with an agent in audio range.
Respond ONLY via tool/function call — no free-form answer."""
	var user_parts: PackedStringArray = []
	user_parts.append("=== Persona ===\n%s" % persona_desc)
	user_parts.append("=== Status ===\n%s" % status)
	user_parts.append("=== Observation (terrain + nearby) ===\n%s" % observation)
	if plan_lines.size() > 0:
		user_parts.append("=== Current plan (remaining steps) ===\n%s" % "\n".join(plan_lines))
	if walkable_near_lines.size() > 0:
		user_parts.append(
			"=== Walkable tiles near you (MOVE_TO targets) ===\n%s" % ", ".join(walkable_near_lines)
		)
	if blocked_move_lines.size() > 0:
		user_parts.append(
			"=== Failed MOVE_TO tiles (do NOT retry) ===\n%s" % "\n".join(blocked_move_lines)
		)
	if perception_agent_ids.size() > 0:
		user_parts.append("=== Perception agent ids ===\n%s" % ", ".join(perception_agent_ids))
	if audio_agent_ids.size() > 0:
		user_parts.append("=== Audio range agent ids (SAY.to / GIVE.to) ===\n%s" % ", ".join(audio_agent_ids))
	else:
		user_parts.append("=== Audio range agent ids ===\n(none — use broadcast or MOVE_TO closer)")
	if observe_agent_ids.size() > 0:
		user_parts.append("=== OBSERVE legal agent ids ===\n%s" % ", ".join(observe_agent_ids))
	if ground_item_ids.size() > 0:
		user_parts.append("=== OBSERVE / PICK_UP legal item ids ===\n%s" % ", ".join(ground_item_ids))
	if item_lines.size() > 0:
		user_parts.append("=== Ground items (detail) ===\n%s" % "\n".join(item_lines))
	if not pending_reply_line.is_empty():
		user_parts.append(
			"=== Pending reply (must answer with SAY, new content) ===\n%s" % pending_reply_line
		)
	if not last_say_text.is_empty():
		user_parts.append("=== Your last SAY (do not repeat) ===\n%s" % last_say_text)
	if heard_lines.size() > 0:
		user_parts.append("=== Recently heard speech ===\n%s" % "\n".join(heard_lines))
	if relationship_lines.size() > 0:
		user_parts.append("=== Relationships (nearby) ===\n%s" % "\n".join(relationship_lines))
	if goal_lines.size() > 0:
		user_parts.append("=== Goals ===\n%s" % "\n".join(goal_lines))
	if memory_lines.size() > 0:
		user_parts.append("=== Relevant memories ===\n%s" % "\n".join(memory_lines))
	user_parts.append("=== Task ===\nChoose your next action for this tick.")
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": "\n\n".join(user_parts)},
	]


static func tool_definitions_for_context(
	audio_agent_ids: PackedStringArray,
	perception_agent_ids: PackedStringArray,
	ground_item_ids: PackedStringArray,
	pickup_item_ids: PackedStringArray,
	inventory: Array,
) -> Array:
	var tools: Array = []
	tools.append(_fn(
		AgentActions.KIND_MOVE_TO,
		AgentActions.SCHEMAS[AgentActions.KIND_MOVE_TO]["desc"],
		{
			"x": {"type": "integer", "description": "destination tile x"},
			"y": {"type": "integer", "description": "destination tile y"},
		},
		["x", "y"],
	))
	var say_to: Array = ["broadcast"]
	for id in audio_agent_ids:
		say_to.append(id)
	tools.append(_fn(
		AgentActions.KIND_SAY,
		"SAY to broadcast or an agent within audio range",
		{
			"to": {"type": "string", "enum": say_to},
			"text": {"type": "string", "description": "简体中文对话内容"},
			"tone": {"type": "string", "description": "语气，如：友好、平静"},
		},
		["to", "text"],
	))
	tools.append(_fn(
		AgentActions.KIND_EMOTE,
		"Show a short emoji visible to agents in sight (0 ticks)",
		{
			"emoji": {"type": "string", "description": "emoji or short emote, max %d chars" % Config.emote_max_chars()},
		},
		["emoji"],
	))
	var observe_targets: Array = _merge_ids(perception_agent_ids, ground_item_ids)
	if observe_targets.size() > 0:
		tools.append(_fn(
			AgentActions.KIND_OBSERVE,
			"Observe a nearby agent or ground item id",
			{
				"target": {"type": "string", "enum": observe_targets},
			},
			["target"],
		))
	if pickup_item_ids.size() > 0:
		tools.append(_fn(
			AgentActions.KIND_PICK_UP,
			"Pick up a ground item within 1 tile",
			{
				"item": {"type": "string", "enum": _array_from_packed(pickup_item_ids)},
			},
			["item"],
		))
	if inventory.size() > 0:
		var inv_enum: Array = _array_from_packed(_unique_strings(inventory))
		tools.append(_fn(
			AgentActions.KIND_DROP,
			"Drop an item from inventory",
			{"item": {"type": "string", "enum": inv_enum}},
			["item"],
		))
		var use_on: Array = ["self"]
		for id in perception_agent_ids:
			use_on.append(id)
		for id in ground_item_ids:
			use_on.append(id)
		tools.append(_fn(
			AgentActions.KIND_USE,
			"Use an inventory item",
			{
				"item": {"type": "string", "enum": inv_enum},
				"on": {"type": "string", "enum": use_on},
			},
			["item", "on"],
		))
		if audio_agent_ids.size() > 0:
			tools.append(_fn(
				AgentActions.KIND_GIVE,
				"Give inventory item to agent within audio range",
				{
					"item": {"type": "string", "enum": inv_enum},
					"to": {"type": "string", "enum": _array_from_packed(audio_agent_ids)},
				},
				["item", "to"],
			))
	if audio_agent_ids.size() > 0:
		tools.append(_fn(
			AgentActions.KIND_SHARE_MAP,
			"Offer to share your explored map with an agent (mutual SHARE_MAP merges gray areas)",
			{
				"to": {"type": "string", "enum": _array_from_packed(audio_agent_ids)},
			},
			["to"],
		))
	var max_wait: int = Config.decision_wait_max_ticks()
	tools.append(_fn(
		AgentActions.KIND_WAIT,
		"Stay idle for N ticks (1-%d). Use when waiting for others or pausing." % max_wait,
		{
			"ticks": {"type": "integer", "description": "ticks to wait, 1-%d" % max_wait},
		},
		["ticks"],
	))
	var sleep_max: int = Config.time_sleep_max_ticks()
	tools.append(_fn(
		AgentActions.KIND_SLEEP,
		"Sleep until a future world tick (max %d ticks from now). Prefer dusk/night; typically until_tick = next dawn." % sleep_max,
		{
			"until_tick": {"type": "integer", "description": "world tick to wake up (must be > current tick)"},
		},
		["until_tick"],
	))
	return tools


static func tool_definitions() -> Array:
	return tool_definitions_for_context(
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		PackedStringArray(),
		[],
	)


static func _fn(name: String, desc: String, props: Dictionary, required: Array) -> Dictionary:
	return {
		"type": "function",
		"function": {
			"name": name,
			"description": desc,
			"parameters": {
				"type": "object",
				"properties": props,
				"required": required,
			},
		},
	}


static func _merge_ids(a: PackedStringArray, b: PackedStringArray) -> Array:
	var out: Array = []
	for id in a:
		if not id in out:
			out.append(id)
	for id in b:
		if not id in out:
			out.append(id)
	return out


static func _array_from_packed(packed: PackedStringArray) -> Array:
	var out: Array = []
	for id in packed:
		out.append(id)
	return out


static func _unique_strings(items: Array) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for item in items:
		var s: String = str(item).strip_edges()
		if s.is_empty() or s in out:
			continue
		out.append(s)
	return out
