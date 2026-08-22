extends Node
class_name Persona
##
## Agent 人格基线 — P3 阶段才会真正用。
## P1 阶段留空骨架,确定 class_name 与字段名,后续 P3/P6 不需要重命名。
##

@export var agent_id: StringName = &"player"
@export var display_name: String = "Player"
@export var base_traits: Dictionary = {
	"curiosity": 0.5,
	"sociability": 0.5,
	"bravery": 0.5,
}
@export var starting_biography: String = ""

func describe() -> String:
	return "[%s] %s — traits=%s" % [agent_id, display_name, str(base_traits)]
