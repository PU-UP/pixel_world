class_name LlmGuard
##
## Prompt 注入防御 — 过滤观察文本中的 meta 指令
##

const BLOCK_PATTERNS: Array[String] = [
	"ignore previous",
	"ignore all previous",
	"ignore above",
	"忽略以上",
	"忽略先前",
	"disregard your instructions",
	"you are now",
	"system:",
	"assistant:",
]


static func sanitize_observation(text: String) -> Dictionary:
	var cleaned := text
	var blocked: Array[String] = []
	for pattern in BLOCK_PATTERNS:
		if cleaned.to_lower().find(pattern.to_lower()) >= 0:
			blocked.append(pattern)
			cleaned = cleaned.replace(pattern, "[filtered]")
	return {"text": cleaned, "blocked": blocked}
