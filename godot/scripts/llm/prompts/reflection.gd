class_name ReflectionPrompt
##
## 反思 prompt 模板 — AGENTS.md §5.3
##


static func build_messages(persona_desc: String, recent_memories: Array) -> Array:
	var system := """You are an autonomous agent reflecting on recent experiences in a 2D pixel island world.
Summarize what you learned about yourself, others, and the world.
Be concise (2-4 sentences). Write in first person."""
	var lines: PackedStringArray = []
	for mem in recent_memories:
		lines.append("[t%d|%s] %s" % [
			int(mem.get("tick", -1)),
			str(mem.get("category", "?")),
			str(mem.get("text", "")),
		])
	var user := "=== Persona ===\n%s\n\n=== Recent memories ===\n%s\n\n=== Task ===\nWhat new understanding do you form?" % [
		persona_desc,
		"\n".join(lines) if lines.size() > 0 else "(none)",
	]
	return [
		{"role": "system", "content": system},
		{"role": "user", "content": user},
	]
