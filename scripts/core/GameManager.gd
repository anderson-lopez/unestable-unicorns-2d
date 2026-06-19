extends Node

# --- SEÑALES ---
signal player_connected(player_data: PlayerData)
signal player_disconnected(player_id: int)
signal game_started # Cuando el host da "Iniciar Partida"
signal game_error(message: String)
signal rules_updated
signal turn_changed(player_id: int)
signal phase_changed(new_phase: TurnPhase)
signal actions_changed(remaining: int)
signal game_won(winner_id: int, winner_name: String)
@warning_ignore("unused_signal")
signal hand_size_changed(player_id: int, new_size: int)
@warning_ignore("unused_signal")
signal stable_changed(player_id: int)

# --- VARIABLES DE ESTADO ---
# Diccionario: { peer_id : PlayerData }
var players: Dictionary = {}
var local_player_info: Dictionary = {"name": "Player"}
var current_rules: GameRules = GameRules.new()
var is_game_active: bool = false
var game_scene_path: String = "res://scenes/game/GameTable.tscn"

# Mazos y Turnos (usados en modo LAN; en modo online los valores viven en RoomState)
var deck: Array[int] = []
var discard_pile: Array[int] = []
var nursery_deck: Array[int] = []
var turn_order: Array[int] = []
var current_turn_index: int = 0
var active_player_id: int = 0
var actions_remaining: int = 1

enum TurnPhase { START, DRAW, ACTION, END }
var current_phase: TurnPhase = TurnPhase.START

var is_resolving: bool = false

var _pending_discard_ids: Array = []
var _pending_discard_done: bool = false

# Referencia global a la mesa de juego (la setea game_table en su _ready)
var game_table: Node = null

# --- ONLINE (servidor dedicado / Render) ---
var online_mode: bool = false
var is_dedicated_referee: bool = false

var extra_turn_queue: Array[int] = []
# (LAN) Token de timer de turno; en online cada RoomState tiene el suyo.
var _turn_timer_token: int = 0

# RoomState del juego LAN (creado en host_game para unificar el código server-side).
var _lan_rs: RoomState = null

# Configuración de Red
const PORT = 7777
const MAX_CLIENTS = 3 # 3 clientes + host = 4 jugadores máximo (1 arriba, 2 a los lados)
const JOIN_TIMEOUT_SECONDS = 15.0

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ==============================================================================
# 🔄 SISTEMA DE TURNOS Y MAZOS
# ==============================================================================

func initialize_deck(rs: RoomState):
	rs.deck.clear()
	rs.nursery_deck.clear()
	rs.discard_pile.clear()

	var mult: int = clampi(rs.rules.deck_multiplier, 1, 5)

	for card_id in CardDatabase.database:
		var data = CardDatabase.database[card_id]
		if data.type == GameEnums.CardType.REFERENCE:
			continue
		if data.is_nursery:
			rs.nursery_deck.append(card_id)
			continue
		for _i in range(mult):
			rs.deck.append(card_id)

	rs.deck.shuffle()

	print("Servidor: Mazos listos (mazo x", mult, ").")
	print(" - Robo: ", rs.deck.size(), " cartas.")
	print(" - Guardería: ", rs.nursery_deck.size(), " bebés disponibles.")

func setup_turn_order(rs: RoomState):
	rs.turn_order.assign(rs.players.keys())
	rs.turn_order.sort()
	rs.current_turn_index = 0

	if not rs.turn_order.is_empty():
		_server_start_turn(rs.turn_order[0], rs)

# --- FLUJO DEL TURNO (server-authoritative) ---

func _server_start_turn(player_id: int, rs: RoomState):
	if not multiplayer.is_server(): return

	if not rs.players.has(player_id):
		print("Servidor: jugador ", player_id, " ya no existe, saltando turno")
		rs.turn_order.erase(player_id)
		rs.extra_turn_queue.erase(player_id)
		if rs.turn_order.is_empty():
			print("Servidor: no quedan jugadores"); return
		rs.current_turn_index = rs.current_turn_index % rs.turn_order.size()
		_server_start_turn(rs.turn_order[rs.current_turn_index], rs)
		return

	rs.active_player_id = player_id
	rs.actions_remaining = 1
	rs.current_phase = TurnPhase.START

	print("Servidor: --- TURNO de ", rs.players[player_id].name, " [sala:", rs.code, "] ---")

	_rpc_room(rs, "sync_turn_state", [player_id, TurnPhase.START, rs.actions_remaining])
	if game_table:
		game_table.server_refresh_visible_hands(rs)
	await EffectProcessor.resolve_on_turn_start(player_id, rs)

	if not rs.is_active: return
	await get_tree().create_timer(0.4).timeout
	if not rs.is_active: return
	_server_advance_to_draw_phase(rs)

func queue_extra_turn(rs: RoomState, player_id: int) -> void:
	if not multiplayer.is_server(): return
	rs.extra_turn_queue.append(player_id)

func _server_advance_to_draw_phase(rs: RoomState):
	if not multiplayer.is_server(): return
	rs.current_phase = TurnPhase.DRAW
	_rpc_room(rs, "sync_turn_state", [rs.active_player_id, TurnPhase.DRAW, rs.actions_remaining])

	var drawn_ids = draw_cards(rs, 1)
	if not drawn_ids.is_empty():
		var card_id = drawn_ids[0]
		if rs.players.has(rs.active_player_id):
			var card_data = CardDatabase.get_card_data(card_id)
			rs.players[rs.active_player_id].hand.append(card_data)
			if game_table:
				game_table.rpc_id(rs.active_player_id, "client_receive_drawn_batch", [card_id])
				var new_size = rs.players[rs.active_player_id].hand.size()
				for p in rs.players:
					if p != rs.active_player_id:
						game_table.rpc_id(p, "client_sync_hand_size", rs.active_player_id, new_size)
				_table_rpc_room(rs, "client_sync_deck_counters", [rs.deck.size(), rs.discard_pile.size(), rs.nursery_deck.size()])

	await get_tree().create_timer(0.3).timeout
	if not rs.is_active: return
	_server_advance_to_action_phase(rs)

func _server_advance_to_action_phase(rs: RoomState):
	if not multiplayer.is_server(): return
	rs.current_phase = TurnPhase.ACTION
	_rpc_room(rs, "sync_turn_state", [rs.active_player_id, TurnPhase.ACTION, rs.actions_remaining])
	_start_turn_timer(rs)

# Arranca el temporizador del turno (si está configurado). El servidor manda los
# segundos a los clientes (para la cuenta atrás visible) y, al agotarse, pasa el
# turno automáticamente. 0 = infinito (sin límite).
func _start_turn_timer(rs: RoomState):
	if not multiplayer.is_server(): return
	rs._turn_timer_token += 1
	var secs: int = rs.rules.turn_time_seconds
	if game_table:
		_table_rpc_room(rs, "client_set_turn_timer", [secs, rs.active_player_id])
	if secs > 0:
		_run_turn_timer(rs, rs._turn_timer_token, secs)

func _run_turn_timer(rs: RoomState, token: int, secs: int) -> void:
	await get_tree().create_timer(float(secs)).timeout
	if token != rs._turn_timer_token or not rs.is_active: return
	while rs.is_resolving:
		await get_tree().create_timer(0.5).timeout
		if token != rs._turn_timer_token or not rs.is_active: return
	if token == rs._turn_timer_token and rs.is_active and rs.current_phase == TurnPhase.ACTION:
		if game_table:
			_table_rpc_room(rs, "client_log_event", ["⏱ Tiempo agotado — el turno pasa automáticamente", Color(1, 0.7, 0.4)])
		_server_advance_to_end_phase(rs)

# Envía un RPC a los peers de la sala usando métodos definidos en GameManager.
func _rpc_room(rs: RoomState, method: StringName, args: Array = []) -> void:
	for pid in rs.players:
		match args.size():
			0: rpc_id(pid, method)
			1: rpc_id(pid, method, args[0])
			2: rpc_id(pid, method, args[0], args[1])
			3: rpc_id(pid, method, args[0], args[1], args[2])
			4: rpc_id(pid, method, args[0], args[1], args[2], args[3])
			_: printerr("_rpc_room: demasiados args para ", method)

# Envía un RPC a los peers de la sala usando métodos definidos en game_table.
func _table_rpc_room(rs: RoomState, method: StringName, args: Array = []) -> void:
	if not game_table: return
	for pid in rs.players:
		match args.size():
			0: game_table.rpc_id(pid, method)
			1: game_table.rpc_id(pid, method, args[0])
			2: game_table.rpc_id(pid, method, args[0], args[1])
			3: game_table.rpc_id(pid, method, args[0], args[1], args[2])
			4: game_table.rpc_id(pid, method, args[0], args[1], args[2], args[3])
			_: printerr("_table_rpc_room: demasiados args para ", method)

# Devuelve el RoomState del peer dado. LAN → _lan_rs; online → consulta OnlineServer.
func _get_rs_for(peer_id: int) -> RoomState:
	if _lan_rs != null:
		return _lan_rs
	if is_dedicated_referee and has_node("/root/OnlineServer"):
		return get_node("/root/OnlineServer").get_room_state_for_peer(peer_id)
	return null

@rpc("any_peer", "call_local", "reliable")
func request_end_turn():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	var rs := _get_rs_for(sender_id)
	if not rs: return
	if sender_id != rs.active_player_id:
		printerr("Servidor: ", sender_id, " intenta terminar turno ajeno")
		return
	if rs.current_phase != TurnPhase.ACTION:
		printerr("Servidor: Solicitud de Fin de Turno fuera de fase ACTION")
		return
	if rs.is_resolving:
		printerr("Servidor: no puedes terminar turno con un efecto en curso")
		return
	_server_advance_to_end_phase(rs)

func _server_advance_to_end_phase(rs: RoomState):
	if not multiplayer.is_server(): return
	rs._turn_timer_token += 1
	rs.current_phase = TurnPhase.END
	if game_table:
		_table_rpc_room(rs, "client_set_turn_timer", [0, rs.active_player_id])
	_rpc_room(rs, "sync_turn_state", [rs.active_player_id, TurnPhase.END, 0])

	var player: PlayerData = rs.players.get(rs.active_player_id)
	if player:
		var limit = rs.rules.hand_limit
		var excess = player.hand.size() - limit
		if excess > 0:
			await _resolve_hand_limit_discard(rs, player, excess)
		if not rs.is_active: return
		var new_size = player.hand.size() if rs.players.has(rs.active_player_id) else 0
		if game_table:
			for p in rs.players:
				if p != rs.active_player_id:
					game_table.rpc_id(p, "client_sync_hand_size", rs.active_player_id, new_size)
			_table_rpc_room(rs, "client_sync_deck_counters", [rs.deck.size(), rs.discard_pile.size(), rs.nursery_deck.size()])

	if not rs.is_active: return
	await get_tree().create_timer(0.4).timeout
	if not rs.is_active: return
	_server_next_turn(rs)

# Pide al jugador activo que elija qué cartas descartar para volver al límite.
# Si no hay UI (tests) o no responde a tiempo, completa por FIFO (las primeras).
func _resolve_hand_limit_discard(rs: RoomState, player: PlayerData, excess: int) -> void:
	if not multiplayer.is_server(): return
	var chooser_id := rs.active_player_id
	if game_table:
		rs.pending_discard_ids = []
		rs.pending_discard_done = false
		game_table.rpc_id(chooser_id, "client_open_discard_to_limit", excess)
		var elapsed := 0.0
		while not rs.pending_discard_done and elapsed < 30.0:
			await get_tree().create_timer(0.25).timeout
			elapsed += 0.25
			if not rs.players.has(chooser_id):
				return
	if not rs.players.has(chooser_id):
		return
	var valid: Array = []
	if game_table:
		for cid in rs.pending_discard_ids:
			if cid in valid: continue
			for c in player.hand:
				if c.id == cid:
					valid.append(cid); break
	if valid.size() < excess:
		for c in player.hand:
			if c.id in valid: continue
			valid.append(c.id)
			if valid.size() >= excess: break
	valid = valid.slice(0, excess)
	for cid in valid:
		for i in range(player.hand.size()):
			if player.hand[i].id == cid:
				player.hand.remove_at(i)
				rs.discard_pile.append(cid)
				if game_table:
					game_table.rpc_id(chooser_id, "client_force_discard", cid)
				break

# Recibe la elección de descarte del jugador activo (llamado desde game_table con rs).
func _on_discard_choice(rs: RoomState, card_ids: Array) -> void:
	rs.pending_discard_ids = card_ids
	rs.pending_discard_done = true

func _server_next_turn(rs: RoomState):
	if not multiplayer.is_server(): return
	if rs.turn_order.is_empty(): return

	if not rs.extra_turn_queue.is_empty():
		var extra_player = rs.extra_turn_queue.pop_front()
		print("Servidor: Turno EXTRA para ", rs.players[extra_player].name)
		_server_start_turn(extra_player, rs)
		return

	rs.current_turn_index = (rs.current_turn_index + 1) % rs.turn_order.size()
	_server_start_turn(rs.turn_order[rs.current_turn_index], rs)

func consume_action(rs: RoomState) -> void:
	if not multiplayer.is_server(): return
	rs.actions_remaining = max(0, rs.actions_remaining - 1)
	_rpc_room(rs, "sync_actions_remaining", [rs.actions_remaining])
	if rs.actions_remaining == 0 and rs.current_phase == TurnPhase.ACTION:
		_server_advance_to_end_phase(rs)

func grant_extra_action(rs: RoomState, amount: int = 1) -> void:
	if not multiplayer.is_server(): return
	rs.actions_remaining += amount
	_rpc_room(rs, "sync_actions_remaining", [rs.actions_remaining])

@rpc("authority", "call_local", "reliable")
func sync_turn_state(player_id: int, phase: int, actions: int):
	active_player_id = player_id
	current_phase = phase
	actions_remaining = actions
	turn_changed.emit(player_id)
	phase_changed.emit(phase)
	actions_changed.emit(actions)

@rpc("authority", "call_local", "reliable")
func sync_actions_remaining(actions: int):
	actions_remaining = actions
	actions_changed.emit(actions)

func reset_for_new_match(rs: RoomState):
	if not multiplayer.is_server(): return
	rs.reset_for_new_match()

# --- Mazo / Descarte ---

func draw_cards(rs: RoomState, amount: int) -> Array[int]:
	var drawn: Array[int] = []
	for i in range(amount):
		if rs.deck.is_empty():
			_refill_deck_from_discard(rs)
			if rs.deck.is_empty(): break
		drawn.append(rs.deck.pop_back())
	return drawn

func _refill_deck_from_discard(rs: RoomState):
	if rs.discard_pile.is_empty(): return
	print("Servidor: Rebarajando descarte...")
	rs.deck.append_array(rs.discard_pile)
	rs.discard_pile.clear()
	rs.deck.shuffle()

# ==============================================================================
# 🏆 CONDICIÓN DE VICTORIA
# ==============================================================================

func check_win_condition(rs: RoomState) -> bool:
	if not multiplayer.is_server(): return false
	if not rs.is_active: return false

	for p_id in rs.players:
		if rs.passives.unicorns_are_pandas(p_id):
			continue
		var unicorn_count = 0
		for card in rs.players[p_id].stable:
			unicorn_count += card.unicorn_count_value()
		if unicorn_count >= rs.rules.unicorns_to_win:
			print("check_win: ", rs.players[p_id].name, " tiene ", unicorn_count, " unicornios >= meta ", rs.rules.unicorns_to_win, " -> GANA")
			rs.is_active = false
			_rpc_room(rs, "announce_winner", [p_id, rs.players[p_id].name])
			return true
	return false

@rpc("authority", "call_local", "reliable")
func announce_winner(winner_id: int, winner_name: String):
	is_game_active = false
	game_won.emit(winner_id, winner_name)
	print("🏆 ¡", winner_name, " GANA LA PARTIDA!")
	if game_table and game_table.has_method("_add_log_line"):
		game_table._add_log_line("🏆 %s gana la partida" % winner_name, Color(1, 0.9, 0.3))

# ==============================================================================
# 🌐 LÓGICA DE CONEXIÓN (HOSTING / JOINING)
# ==============================================================================

func host_game(player_name: String, rules: GameRules):
	local_player_info["name"] = player_name
	current_rules = rules

	# Red por WebSocket (funciona en escritorio, móvil y web; y permite el
	# servidor en la nube tipo Render).
	var peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_server(PORT)

	if error != OK:
		game_error.emit("No se pudo crear el servidor: " + str(error))
		return

	multiplayer.multiplayer_peer = peer
	print("Servidor WebSocket iniciado en puerto ", PORT)

	_register_player(1, local_player_info)

# Convierte una entrada del usuario en una URL WebSocket válida.
#   "127.0.0.1"           -> "ws://127.0.0.1:7777"
#   "192.168.1.5:7777"    -> "ws://192.168.1.5:7777"
#   "ws://x" / "wss://x"  -> se usa tal cual (para servidores en la nube)
func _make_ws_url(addr: String) -> String:
	addr = addr.strip_edges()
	if addr.is_empty():
		addr = "127.0.0.1"
	if addr.begins_with("ws://") or addr.begins_with("wss://"):
		return addr
	# Si no trae puerto, le agregamos el por defecto
	if not addr.contains(":"):
		addr = "%s:%d" % [addr, PORT]
	return "ws://" + addr

func join_game(player_name: String, ip: String):
	local_player_info["name"] = player_name

	var url := _make_ws_url(ip)

	var peer = WebSocketMultiplayerPeer.new()
	var error = peer.create_client(url)

	if error != OK:
		game_error.emit("No se pudo conectar: " + str(error))
		return

	multiplayer.multiplayer_peer = peer
	print("Intentando conectar a ", url)
	_watch_join_timeout(peer)

# Si tras JOIN_TIMEOUT_SECONDS seguimos en estado CONNECTING con este mismo peer,
# la conexión nunca se estableció (URL mal, servidor caído, firewall): abortamos.
func _watch_join_timeout(peer: MultiplayerPeer) -> void:
	await get_tree().create_timer(JOIN_TIMEOUT_SECONDS).timeout
	if multiplayer.multiplayer_peer == peer and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTING:
		printerr("Timeout de conexión al servidor")
		game_error.emit("No se pudo conectar (tiempo agotado).\nRevisa la IP y que el host tenga la sala abierta en la misma red.")
		multiplayer.multiplayer_peer = null

# Devuelve la primera IPv4 de red local (192.168.x / 10.x / 172.16-31.x).
# Útil para mostrarle al host qué dirección compartir con los demás jugadores.
func get_local_ip() -> String:
	for addr in IP.get_local_addresses():
		if addr.count(".") != 3:
			continue # descartar IPv6
		if addr.begins_with("127."):
			continue
		if addr.begins_with("192.168.") or addr.begins_with("10."):
			return addr
		# Rango privado 172.16.0.0 – 172.31.255.255
		if addr.begins_with("172."):
			var second := addr.split(".")[1].to_int()
			if second >= 16 and second <= 31:
				return addr
	return "127.0.0.1"

# ==============================================================================
# 🤝 HANDSHAKE
# ==============================================================================

func _on_peer_connected(id: int):
	print("Nuevo peer detectado: ", id)

func _on_connected_ok():
	print("¡Conexión exitosa al servidor!")
	# En modo online (salas con código) NO se auto-registra: el flujo de sala
	# (OnlineServer) gestiona quién entra a la partida.
	if online_mode:
		return
	rpc_id(1, "register_player_request", local_player_info)

func _on_connected_fail():
	game_error.emit("Fallo la conexión al servidor")
	multiplayer.multiplayer_peer = null

func _on_server_disconnected():
	game_error.emit("El servidor se ha desconectado")
	players.clear()
	is_game_active = false
	multiplayer.multiplayer_peer = null

@rpc("any_peer", "reliable")
func register_player_request(info: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	print("Solicitud de registro recibida de: ", sender_id)

	# Límite de jugadores (WebSocket no lo limita solo). host + MAX_CLIENTS.
	if players.size() >= (MAX_CLIENTS + 1) or is_game_active:
		print("Servidor: sala llena o partida en curso, rechazando ", sender_id)
		rpc_id(sender_id, "kicked_from_server", "La sala está llena o la partida ya empezó.")
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(sender_id)
		return

	_register_player(sender_id, info)

	# Enviar todos los jugadores existentes al recién llegado.
	for p_id in players:
		rpc_id(sender_id, "register_player_client", p_id, {"name": players[p_id].name, "avatar_id": players[p_id].avatar_id})

	# Notificar a los peers ya conectados sobre el recién llegado.
	# (El host ya lo registró localmente, así que se salta p_id == 1.)
	var new_info := {"name": players[sender_id].name, "avatar_id": players[sender_id].avatar_id}
	for p_id in players:
		if p_id != sender_id and p_id != 1:
			rpc_id(p_id, "register_player_client", sender_id, new_info)

	rpc_id(sender_id, "sync_rules", current_rules.to_dictionary())

# El servidor avisa al cliente que fue rechazado (sala llena / partida en curso).
@rpc("authority", "reliable")
func kicked_from_server(reason: String):
	game_error.emit(reason)
	multiplayer.multiplayer_peer = null

@rpc("authority", "reliable")
func register_player_client(id: int, info: Dictionary):
	_register_player(id, info)

# ONLINE (servidor dedicado): el servidor envía el roster COMPLETO a cada cliente
# antes de cargar la mesa, para que GameManager.players exista igual en todos.
# roster = [{ "id": int, "name": String }, ...]
@rpc("authority", "reliable")
func online_sync_roster(roster: Array):
	players.clear()
	for entry in roster:
		_register_player(int(entry["id"]), {"name": String(entry["name"]), "avatar_id": int(entry.get("avatar_id", 1))})
	print("Roster online sincronizado: ", players.size(), " jugadores.")

@rpc("authority", "reliable")
func sync_rules(rules_dict: Dictionary):
	current_rules.from_dictionary(rules_dict)
	rules_updated.emit()
	print("Reglas sincronizadas. Unicornios para ganar: ", current_rules.unicorns_to_win)

func update_rules_broadcast():
	if multiplayer.is_server():
		rpc("sync_rules", current_rules.to_dictionary())

# ==============================================================================
# ⚙️ LÓGICA INTERNA
# ==============================================================================

func _register_player(id: int, info: Dictionary):
	var new_player = PlayerData.new(id, info["name"], info.get("avatar_id", 1))
	players[id] = new_player
	player_connected.emit(new_player)
	print("Jugador registrado: ", info["name"], " [ID: ", id, "] [avatar: ", new_player.avatar_id, "]")

func _on_peer_disconnected(id: int):
	var rs: RoomState = _get_rs_for(id) if multiplayer.is_server() else null

	var pname := "Un jugador"
	if players.has(id):
		pname = players[id].name
		print("Jugador desconectado: ", pname)
		players.erase(id)
		player_disconnected.emit(id)

	if not multiplayer.is_server(): return
	if rs == null or not rs.is_active: return

	rs.players.erase(id)

	if game_table:
		_table_rpc_room(rs, "client_toast", ["⚠ %s se desconectó" % pname])
		_table_rpc_room(rs, "client_log_event", ["⚠ %s se desconectó" % pname, Color(1, 0.6, 0.3)])
		_table_rpc_room(rs, "client_remove_player_zone", [id])

	if rs.is_resolving:
		EffectProcessor.target_picked.emit(-1, -1)
		EffectProcessor.cost_paid.emit(false, [])
		rs.is_resolving = false

	if rs.players.size() <= 1:
		_end_match_last_player_standing(rs)
		return

	var was_active := rs.active_player_id == id
	rs.turn_order.erase(id)
	rs.extra_turn_queue.erase(id)
	if rs.turn_order.is_empty(): return
	if was_active:
		rs.current_turn_index = rs.current_turn_index % rs.turn_order.size()
		_server_start_turn(rs.turn_order[rs.current_turn_index], rs)

func _end_match_last_player_standing(rs: RoomState):
	if not multiplayer.is_server(): return
	if rs.players.is_empty(): return
	var last_id: int = rs.players.keys()[0]
	print("Servidor: solo queda ", rs.players[last_id].name, " → gana por abandono")
	rs.is_active = false
	_rpc_room(rs, "announce_winner", [last_id, rs.players[last_id].name + " (por abandono)"])

func get_opponents_of(rs: RoomState, player_id: int) -> Array[int]:
	return rs.opponents_of(player_id)

# ==============================================================================
# 🏁 INICIO DEL JUEGO
# ==============================================================================

func start_game():
	if not multiplayer.is_server(): return

	if players.size() < 2:
		print("Servidor: se necesitan al menos 2 jugadores para empezar")
		return

	_lan_rs = RoomState.new("lan", 1)
	_lan_rs.rules = current_rules
	for p_id in players:
		_lan_rs.players[p_id] = players[p_id]
	_lan_rs.is_active = true

	multiplayer.multiplayer_peer.refuse_new_connections = true
	is_game_active = true
	rpc("load_game_scene")

@rpc("authority", "call_local", "reliable")
func load_game_scene():
	print("Cargando escena de juego...")
	is_game_active = true
	get_tree().change_scene_to_file(game_scene_path)

@rpc("authority", "reliable")
func client_start_game():
	is_game_active = true
	game_started.emit()
	print("¡EL JUEGO HA COMENZADO!")
