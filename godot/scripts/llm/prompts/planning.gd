class_name PlanningPrompt
##
## 计划生成 prompt — AGENTS.md §5.4
##


static func build_messages(
	persona_desc: String,
	status: String,
	observation: String,
	recent_actions: PackedStringArray,
	relationship_lines: PackedStringArray,
) -> Array:
	var system := """You are an autonomous agent planning the next stretch of activity on a 2D pixel island.
Write a numbered list of 5-7 short steps you intend to follow, in Simplified Chinese (简体中文).
Steps may reference action primitives by English name: MOVE_TO (tile x,y), SAY (to agent_id or broadcast), PICK_UP, DROP, USE, GIVE, OBSERVE.
MOVE_TO coordinates must be walkable tiles — not water, trees, or mountains.
Example step: "1. MOVE_TO 前往沙滩 (32,50)，向 scout 用 SAY 打招呼"
Prefer social steps (SAY) when you know familiar agents nearby.
One step per line, format: "1. ..." """
	var parts: PackedStringArray = []
	parts.append("=== Persona ===\n%s" % persona_desc)
	parts.append("=== Status ===\n%s" % status)
	parts.append("=== Observation ===\n%s" % observation)
	if relationship_lines.size() > 0:
		parts.append("=== Relationships (nearby) ===\n%s" % "\n".join(relationship_lines))
	if recent_actions.size() > 0:
		parts.append("=== Recent actions ===\n%s" % "\n".join(recent_actions))
	parts.append("=== Task ===\nGenerate your plan for the next while.")
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": "\n\n".join(parts)},
	]
