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
Write a numbered list of 5-7 short steps you intend to follow.
Steps must use only available actions: MOVE_TO (tile x,y), SAY (to agent_id or broadcast).
Prefer social steps (SAY hello) when you know familiar agents nearby.
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
