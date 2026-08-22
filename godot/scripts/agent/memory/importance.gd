class_name MemoryImportance
##
## 记忆重要性评分 — AGENTS.md §5.1 简化实现
##

const BASE: Dictionary = {
	"injury": 0.9,
	"attack": 0.9,
	"social": 0.6,
	"item": 0.5,
	"action": 0.35,
	"decision": 0.4,
	"observation": 0.15,
	"movement": 0.2,
	"reflection": 0.75,
	"plan": 0.55,
	"ambient": 0.05,
}


static func base_for_category(category: String) -> float:
	return float(BASE.get(category, 0.1))


static func score(
	category: String,
	recency_ticks: int,
	time_window_ticks: int,
	emotional_intensity: float = 0.0,
	social_relevance: float = 0.0,
	goal_relevance: float = 0.0,
) -> float:
	var base := base_for_category(category)
	var recency := 1.0
	if time_window_ticks > 0:
		recency = clampf(1.0 - float(recency_ticks) / float(time_window_ticks), 0.0, 1.0)
	var novelty := 0.3 * recency
	var emotional := 0.2 * clampf(emotional_intensity, 0.0, 1.0)
	var social := 0.2 * clampf(social_relevance, 0.0, 1.0)
	var goal := 0.1 * clampf(goal_relevance, 0.0, 1.0)
	return clampf(base + novelty + emotional + social + goal, 0.0, 1.0)
