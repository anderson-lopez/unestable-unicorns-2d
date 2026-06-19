extends Node
# Autoload: gestiona la ventana de Relinchos al jugar una carta.
# Server-side: pregunta a quien tenga Neigh si quiere usarlo durante N segundos.

const WINDOW_SECONDS: float = 15.0

func _table_rpc(rs: RoomState, method, p1 = null, p2 = null, p3 = null, p4 = null) -> void:
	if not GameManager.game_table: return
	for pid in rs.players:
		var args = [pid, method]
		for p in [p1, p2, p3, p4]:
			if p != null: args.append(p)
		GameManager.game_table.callv("rpc_id", args)

func _table_rpc_id(target_id: int, method, p1 = null, p2 = null, p3 = null, p4 = null):
	if not GameManager.game_table: return
	var args = [target_id, method]
	for p in [p1, p2, p3, p4]:
		if p != null: args.append(p)
	GameManager.game_table.callv("rpc_id", args)

func _pname(rs: RoomState, pid: int) -> String:
	if rs.players.has(pid):
		return rs.players[pid].name
	return "Jugador %d" % pid

func _neigh_log(rs: RoomState, text: String) -> void:
	_table_rpc(rs, "client_log_event", text, Color(1, 0.7, 0.4))

var pending_card_id: int = -1
var pending_player_id: int = -1
var pending_super: bool = false
var window_open: bool = false
var responses: Dictionary = {}
var eligible_ids: Array[int] = []
var passed_ids: Dictionary = {}

# Abre ventana. Devuelve true si la carta original FUE cancelada.
func open_window(card_id: int, playing_player_id: int, rs: RoomState) -> bool:
	if not multiplayer.is_server(): return false
	pending_card_id = card_id
	pending_player_id = playing_player_id
	pending_super = false
	responses.clear()

	var card_data = CardDatabase.get_card_data(card_id)
	if not card_data: return false

	if rs.passives.owner_immune_to_neigh(playing_player_id):
		_neigh_log(rs, "🛡️ %s no se puede relinchar (inmune)" % card_data.name_es)
		return false

	var eligible: Array[int] = []
	for pid in rs.players:
		if pid == playing_player_id: continue
		var p: PlayerData = rs.players[pid]
		var has_neigh = false
		for c in p.hand:
			if c.is_instant():
				has_neigh = true; break
		var can_instant = rs.passives.can_play_instant(pid)
		print("NeighManager: ", _pname(rs, pid), " has_neigh=", has_neigh, " can_play_instant=", can_instant)
		if has_neigh and not can_instant:
			_neigh_log(rs, "🐌 %s tiene Relincho pero no puede usarlo" % _pname(rs, pid))
		if can_instant and has_neigh:
			eligible.append(pid)

	if eligible.is_empty():
		return false

	window_open = true
	eligible_ids = eligible.duplicate()
	passed_ids.clear()
	for pid in eligible:
		_table_rpc_id(pid, "client_open_neigh_window",
			card_id, playing_player_id, WINDOW_SECONDS)

	var cancelled = await _await_neigh_response(rs)
	window_open = false
	_table_rpc(rs, &"client_close_neigh_window")
	return cancelled

func _await_neigh_response(rs: RoomState) -> bool:
	var t := 0.0
	while t < WINDOW_SECONDS:
		await Engine.get_main_loop().process_frame
		t += Engine.get_main_loop().root.get_process_delta_time()
		if pending_super:
			return await _handle_neigh_chain(rs)
		if _all_eligible_passed():
			return false
	return false

func _all_eligible_passed() -> bool:
	if eligible_ids.is_empty(): return false
	for pid in eligible_ids:
		if not passed_ids.has(pid):
			return false
	return true

@rpc("any_peer", "call_local", "reliable")
func server_receive_pass_rpc():
	if not multiplayer.is_server(): return
	server_receive_pass(multiplayer.get_remote_sender_id())

func server_receive_pass(player_id: int):
	if not window_open: return
	if player_id in eligible_ids:
		passed_ids[player_id] = true

@rpc("any_peer", "call_local", "reliable")
func server_receive_neigh_rpc(neigh_card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var rs := GameManager._get_rs_for(sender_id)
	if not rs: return
	server_receive_neigh(sender_id, neigh_card_id, rs)

func server_receive_neigh(neigher_id: int, neigh_card_id: int, rs: RoomState):
	if not window_open: return
	var card = CardDatabase.get_card_data(neigh_card_id)
	if not card or not card.is_instant(): return
	var p = rs.players.get(neigher_id)
	if not p: return
	var has_it = false
	for c in p.hand:
		if c.id == neigh_card_id:
			has_it = true; break
	if not has_it: return
	for j in range(p.hand.size()):
		if p.hand[j].id == neigh_card_id:
			p.hand.remove_at(j); break
	rs.discard_pile.append(neigh_card_id)
	_table_rpc(rs, &"client_card_left_hand", neigher_id, neigh_card_id)
	for pid in rs.players:
		_table_rpc_id(pid, "client_sync_hand_size", neigher_id, p.hand.size())
	_table_rpc(rs, &"client_announce_neigh", neigher_id, neigh_card_id, pending_player_id, pending_card_id)
	pending_super = true
	pending_player_id = neigher_id
	pending_card_id = neigh_card_id

func _handle_neigh_chain(rs: RoomState) -> bool:
	var card = CardDatabase.get_card_data(pending_card_id)
	if card and card.effects.size() > 0 and card.effects[0].condition == GameEnums.Condition.CANNOT_BE_NEIGHED:
		return true
	pending_super = false
	var counter_cancelled = await open_window(pending_card_id, pending_player_id, rs)
	return not counter_cancelled
