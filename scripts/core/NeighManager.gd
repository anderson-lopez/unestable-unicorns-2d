extends Node
# Autoload: gestiona la ventana de Relinchos al jugar una carta.
# Server-side: pregunta a quien tenga Neigh si quiere usarlo durante N segundos.

const WINDOW_SECONDS: float = 15.0

# Wrappers para RPCs visuales que viven en game_table
func _table_rpc(method, p1 = null, p2 = null, p3 = null, p4 = null):
	if not GameManager.game_table: return
	var args = [method]
	for p in [p1, p2, p3, p4]:
		if p != null: args.append(p)
	GameManager.game_table.callv("rpc", args)

func _table_rpc_id(target_id: int, method, p1 = null, p2 = null, p3 = null, p4 = null):
	if not GameManager.game_table: return
	var args = [target_id, method]
	for p in [p1, p2, p3, p4]:
		if p != null: args.append(p)
	GameManager.game_table.callv("rpc_id", args)

var pending_card_id: int = -1
var pending_player_id: int = -1
var pending_super: bool = false # si la pila va por super-neigh
var window_open: bool = false
var responses: Dictionary = {} # peer_id -> response (true/false)
# Quiénes pueden relinchar esta jugada y quiénes ya PASARON (no relinchan).
# Cuando todos pasan, la ventana se cierra al instante (sin esperar 15s).
var eligible_ids: Array[int] = []
var passed_ids: Dictionary = {} # peer_id -> true

# Abre ventana. Devuelve true si la carta original FUE cancelada.
func open_window(card_id: int, playing_player_id: int) -> bool:
	if not multiplayer.is_server(): return false
	pending_card_id = card_id
	pending_player_id = playing_player_id
	pending_super = false
	responses.clear()

	var card_data = CardDatabase.get_card_data(card_id)
	if not card_data: return false

	# Si el dueño tiene Yay (PREVENT_NEIGH_ON_OWNER), no se puede Relinchar
	if EffectProcessor.passives.owner_immune_to_neigh(playing_player_id):
		return false

	# Buscar quién puede responder (tiene Neigh en mano y puede jugarlo)
	var eligible: Array[int] = []
	for pid in GameManager.players:
		if pid == playing_player_id: continue
		if not EffectProcessor.passives.can_play_instant(pid): continue
		var p: PlayerData = GameManager.players[pid]
		var has_neigh = false
		for c in p.hand:
			if c.is_instant():
				has_neigh = true; break
		if has_neigh:
			eligible.append(pid)

	if eligible.is_empty():
		return false

	# Abrir ventana
	window_open = true
	eligible_ids = eligible.duplicate()
	passed_ids.clear()
	for pid in eligible:
		_table_rpc_id(pid, "client_open_neigh_window",
			card_id, playing_player_id, WINDOW_SECONDS)

	# Esperar respuesta o timeout
	var cancelled = await _await_neigh_response()
	window_open = false
	_table_rpc(&"client_close_neigh_window")
	return cancelled

func _await_neigh_response() -> bool:
	var t := 0.0
	while t < WINDOW_SECONDS:
		await Engine.get_main_loop().process_frame
		t += Engine.get_main_loop().root.get_process_delta_time()
		# ¿Alguien jugó Neigh?
		if pending_super:
			# Significa que recibimos un neigh y abrimos super-window
			return await _handle_neigh_chain()
		# ¿TODOS los que podían relinchar ya pasaron? → cerrar al instante.
		if _all_eligible_passed():
			return false
	return false

# True si cada jugador que podía relinchar ya pulsó "Pasar".
func _all_eligible_passed() -> bool:
	if eligible_ids.is_empty(): return false
	for pid in eligible_ids:
		if not passed_ids.has(pid):
			return false
	return true

# RPC: un cliente avisa que NO va a relinchar (pasó).
@rpc("any_peer", "call_local", "reliable")
func server_receive_pass_rpc():
	if not multiplayer.is_server(): return
	server_receive_pass(multiplayer.get_remote_sender_id())

func server_receive_pass(player_id: int):
	if not window_open: return
	if player_id in eligible_ids:
		passed_ids[player_id] = true

# RPC: cliente envía su Neigh al servidor
@rpc("any_peer", "call_local", "reliable")
func server_receive_neigh_rpc(neigh_card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	server_receive_neigh(sender_id, neigh_card_id)

# Llamado por server cuando un cliente responde con un Neigh
func server_receive_neigh(neigher_id: int, neigh_card_id: int):
	if not window_open: return
	# Validar
	var card = CardDatabase.get_card_data(neigh_card_id)
	if not card or not card.is_instant(): return
	var p = GameManager.players.get(neigher_id)
	if not p: return
	var has_it = false
	for c in p.hand:
		if c.id == neigh_card_id:
			has_it = true; break
	if not has_it: return
	# Remover de mano
	for j in range(p.hand.size()):
		if p.hand[j].id == neigh_card_id:
			p.hand.remove_at(j); break
	GameManager.discard_pile.append(neigh_card_id)
	_table_rpc(&"client_card_left_hand", neigher_id, neigh_card_id)
	for pid in GameManager.players:
		_table_rpc_id(pid, "client_sync_hand_size", neigher_id, p.hand.size())
	# Anunciar
	_table_rpc(&"client_announce_neigh", neigher_id, neigh_card_id, pending_player_id, pending_card_id)
	# Marca para que open_window resuelva en cadena
	pending_super = true
	pending_player_id = neigher_id
	pending_card_id = neigh_card_id

# Cuando alguien juega un Neigh durante una ventana abierta, abrimos otra ventana
# para que se pueda jugar super-neigh sobre él.
func _handle_neigh_chain() -> bool:
	var card = CardDatabase.get_card_data(pending_card_id)
	# Super Neigh no puede ser cancelado
	if card and card.effects.size() > 0 and card.effects[0].condition == GameEnums.Condition.CANNOT_BE_NEIGHED:
		# Cadena termina; la carta cancelada queda cancelada
		return true # la carta original quedó cancelada (porque el último neigh ganó)
	# Si es un Neigh normal, alguien podría super-neighearlo
	pending_super = false
	var counter_cancelled = await open_window(pending_card_id, pending_player_id)
	# Si el último Neigh fue counter-neigheado → la carta original NO se cancela
	# Si nadie respondió → el Neigh resuelve → la carta original SÍ se cancela
	return not counter_cancelled
