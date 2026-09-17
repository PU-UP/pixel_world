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
	goal_text: String = "",
	frontier_lines: PackedStringArray = [],
) -> Array:
	var system := """You are an autonomous agent planning the next stretch of activity on a 2D pixel island.
Write a numbered list of 5-7 short steps you intend to follow, in Simplified Chinese (简体中文).
Each step MUST start with one action primitive: MOVE_TO, SAY, PICK_UP, USE, GIVE, OBSERVE, SLEEP, WAIT, SHARE_MAP, EMOTE.
MOVE_TO steps MUST include walkable tile coordinates like (32,50) or a named region. Prefer listed frontier tiles over wandering nearby.
SAY/GIVE/SHARE_MAP only if someone is currently in sight.
PICK_UP of food gathers every matching item in sight. USE food to eat. Non-food items cannot change the island yet.
Example: "1. MOVE_TO 前往南滩 (48,75)"
You have an immutable goal to stay alive. Death is irreversible; there is no suicide action.
Health falls at dawn from consecutive missed night sleep or days without food; health 0 is death.
Dusk/night sleep restores energy; dawn/day sleep barely does. Eating restores satiety, not a substitute for sleep.
One step per line, format: "1. ..." """
	var parts: PackedStringArray = []
	parts.append("=== Persona ===\n%s" % persona_desc)
	parts.append("=== Status ===\n%s" % status)
	parts.append("=== Observation ===\n%s" % observation)
	if frontier_lines.size() > 0:
		parts.append("=== Unexplored frontier (MOVE_TO) ===\n%s" % ", ".join(frontier_lines))
	if relationship_lines.size() > 0:
		parts.append("=== Relationships (nearby) ===\n%s" % "\n".join(relationship_lines))
	if not goal_text.is_empty():
		parts.append("=== Goals ===\n%s" % goal_text)
	if recent_actions.size() > 0:
		parts.append("=== Recent actions ===\n%s" % "\n".join(recent_actions))
	parts.append("=== Task ===\nGenerate your plan for the next while.")
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": "\n\n".join(parts)},
	]
