extends Node
class_name CommRouter
##
## 通信路由 — SAY 可达性（听觉半径）与消息投递
##

signal message_delivered(speaker_id: String, target_id: String, text: String, tick: int, recipient_ids: Array)

var _players: Array = []


func register_player(player: Player) -> void:
	if player not in _players:
		_players.append(player)


func all_players() -> Array:
	return _players


func players_in_perception(observer: Player) -> Array:
	var out: Array = []
	var r: int = observer.observation_radius_tiles
	var ot := observer.get_tile_position()
	for p in _players:
		if p == observer:
			continue
		var pt: Vector2i = p.get_tile_position()
		if _tile_distance(ot, pt) <= r:
			out.append(p)
	return out


func deliver_say(speaker: Player, to: String, text: String, tone: String, tick: int) -> Dictionary:
	var target := to.strip_edges()
	if target.is_empty():
		return {"ok": false, "error": "empty target"}
	var recipients: Array = []
	if target == "broadcast":
		for p in _players:
			if p != speaker and _can_hear(speaker, p):
				recipients.append(p)
	else:
		var found: Player = _find_player(target)
		if found == null:
			return {"ok": false, "error": "unknown agent: %s" % target}
		if not _can_hear(speaker, found):
			return {"ok": false, "error": "target out of audio range"}
		recipients.append(found)
	for p in recipients:
		p.receive_say(str(speaker.agent_id), text, tone, tick)
	var recipient_ids: Array = []
	for p in recipients:
		recipient_ids.append(str(p.agent_id))
	message_delivered.emit(str(speaker.agent_id), target, text, tick, recipient_ids)
	return {"ok": true, "error": "", "recipients": recipients.size()}


func _find_player(agent_id: String) -> Player:
	for p in _players:
		if str(p.agent_id) == agent_id:
			return p
	return null


func _can_hear(speaker: Player, listener: Player) -> bool:
	return _tile_distance(speaker.get_tile_position(), listener.get_tile_position()) <= Config.audio_radius()


func _tile_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
