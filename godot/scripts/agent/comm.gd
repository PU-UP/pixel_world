extends Node
class_name CommRouter
##
## 通信路由 — SAY 可达性（听觉半径）与消息投递
##

signal message_delivered(speaker_id: String, target_id: String, text: String, tick: int, recipient_ids: Array)
signal item_given(giver_id: String, receiver_id: String, item_id: String, tick: int)
signal map_share_merged(sharer_id: String, receiver_id: String, tiles_merged: int, tick: int)

var _players: Array = []
var _share_offers: Dictionary = {}


func register_player(player: Player) -> void:
	if player not in _players:
		_players.append(player)


func all_players() -> Array:
	return _players


func players_in_perception(observer: Player) -> Array:
	var out: Array = []
	var r: int = observer.observation_radius_tiles
	var ot := observer.get_tile_position()
	var world = observer.game_world()
	for p in _players:
		if p == observer:
			continue
		var pt: Vector2i = p.get_tile_position()
		if _tile_distance(ot, pt) > r:
			continue
		if world != null and not world.has_line_of_sight(ot, pt):
			continue
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
	return {"ok": true, "error": "", "recipients": recipients.size(), "recipient_ids": recipient_ids}


func deliver_give(giver: Player, to_agent_id: String, item_id: String, tick: int) -> Dictionary:
	var target := to_agent_id.strip_edges()
	var item := item_id.strip_edges()
	if target.is_empty() or item.is_empty():
		return {"ok": false, "error": "empty target or item"}
	if not giver.inventory.has(item):
		return {"ok": false, "error": "not carrying item: %s" % item}
	var receiver: Player = _find_player(target)
	if receiver == null:
		return {"ok": false, "error": "unknown agent: %s" % target}
	if not _can_hear(giver, receiver):
		return {"ok": false, "error": "target out of audio range"}
	giver.inventory.erase(item)
	receiver.receive_item(str(giver.agent_id), item, tick)
	item_given.emit(str(giver.agent_id), target, item, tick)
	return {"ok": true, "error": ""}


func deliver_share_map(sharer: Player, to_agent_id: String, tick: int) -> Dictionary:
	var target_id := to_agent_id.strip_edges()
	if target_id.is_empty():
		return {"ok": false, "error": "empty target"}
	var receiver: Player = _find_player(target_id)
	if receiver == null:
		return {"ok": false, "error": "unknown agent: %s" % target_id}
	if not _can_hear(sharer, receiver):
		return {"ok": false, "error": "target out of audio range"}
	var from_id: String = str(sharer.agent_id)
	var offer_key: String = "%s|%s" % [from_id, target_id]
	var recip_key: String = "%s|%s" % [target_id, from_id]
	var window: int = int(Config.exploration_cfg().get("share_consensus_ticks", 60))
	if _share_offers.has(recip_key) and tick - int(_share_offers[recip_key]) <= window:
		var merged: int = _merge_exploration(sharer, receiver)
		_share_offers.erase(recip_key)
		map_share_merged.emit(from_id, target_id, merged, tick)
		return {"ok": true, "error": "", "merged": merged, "mutual": true}
	_share_offers[offer_key] = tick
	receiver.receive_share_offer(from_id, tick)
	return {"ok": true, "error": "", "merged": 0, "mutual": false, "pending": true}


func _merge_exploration(a: Player, b: Player) -> int:
	if a.exploration == null or b.exploration == null:
		return 0
	var added_ab: int = b.exploration.merge_from(a.exploration)
	var added_ba: int = a.exploration.merge_from(b.exploration)
	return added_ab + added_ba


func players_in_audio(observer: Player) -> Array:
	var out: Array = []
	for p in _players:
		if p != observer and _can_hear(observer, p):
			out.append(p)
	return out


func find_player(agent_id: String) -> Player:
	return _find_player(agent_id.strip_edges())


func resolve_agent_id(alias: String) -> String:
	var key := alias.strip_edges().to_lower()
	if key.is_empty() or key == "broadcast":
		return alias.strip_edges()
	var exact: Array = []
	var prefix: Array = []
	for p in _players:
		var id: String = str(p.agent_id)
		var low := id.to_lower()
		if low == key:
			return id
		if key.length() >= 3 and low.begins_with(key):
			prefix.append(id)
	if prefix.size() == 1:
		return str(prefix[0])
	return alias.strip_edges()


func _find_player(agent_id: String) -> Player:
	for p in _players:
		if str(p.agent_id) == agent_id:
			return p
	return null


func _can_hear(speaker: Player, listener: Player) -> bool:
	return _tile_distance(speaker.get_tile_position(), listener.get_tile_position()) <= Config.audio_radius()


func _tile_distance(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)
