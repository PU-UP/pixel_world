class_name ActionExecutor
##
## 行动原语执行器 — 校验后交给 player 队列
##

const AgentActions = preload("res://scripts/agent/actions.gd")


static func execute(player: Player, action: Dictionary) -> Dictionary:
	var validation: Dictionary = AgentActions.validate(action)
	if not validation["ok"]:
		return {"ok": false, "error": validation["error"]}
	if action["kind"] not in AgentActions.IMPLEMENTED_KINDS:
		return {"ok": false, "error": "unimplemented kind: %s" % action["kind"]}
	player.enqueue_action(action)
	return {"ok": true, "error": ""}
