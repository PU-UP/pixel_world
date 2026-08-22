extends Node
class_name Persona
##
## Agent 人格基线 + 漂移（P6）
##

@export var agent_id: StringName = &"player"
@export var display_name: String = "Player"
@export var base_traits: Dictionary = {
	"curiosity": 0.5,
	"sociability": 0.5,
	"bravery": 0.5,
}
@export var starting_biography: String = ""

var trait_drift: Dictionary = {}


func current_traits() -> Dictionary:
	var out: Dictionary = {}
	var max_drift: float = float(Config.persona_drift_cfg().get("max_per_trait", 0.15))
	for k in base_traits:
		var base_v: float = float(base_traits[k])
		var d: float = float(trait_drift.get(k, 0.0))
		out[k] = clampf(base_v + d, base_v - max_drift, base_v + max_drift)
	return out


func apply_reflection_drift(social_interactions: int = 0) -> void:
	var jitter: float = float(Config.persona_drift_cfg().get("reflection_jitter", 0.02))
	var max_drift: float = float(Config.persona_drift_cfg().get("max_per_trait", 0.15))
	var social_boost: float = clampf(float(social_interactions) * 0.005, 0.0, 0.02)
	for k in base_traits:
		var delta: float = randf_range(-jitter, jitter) + social_boost
		if k == "sociability":
			delta += social_boost
		var cur: float = float(trait_drift.get(k, 0.0))
		trait_drift[k] = clampf(cur + delta, -max_drift, max_drift)


func describe() -> String:
	var bio := ""
	if not starting_biography.is_empty():
		bio = " — %s" % starting_biography
	return "[%s] %s%s — traits=%s" % [agent_id, display_name, bio, str(current_traits())]
