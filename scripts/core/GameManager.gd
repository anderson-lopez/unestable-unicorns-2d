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

# Mazos y Turnos
var deck: Array[int] = []
var discard_pile: Array[int] = []
var nursery_deck: Array[int] = []
var turn_order: Array[int] = []
var current_turn_index: int = 0
var active_player_id: int = 0
var actions_remaining: int = 1

enum TurnPhase { START, DRAW, ACTION, END }
var current_phase: TurnPhase = TurnPhase.START

# Lock: true mientras un efecto se está resolviendo (esperando inputs de UI).
# Evita que el jugador juegue otra carta a la mitad de una resolución (desync).
var is_resolving: bool = false

# Referencia global a la mesa de juego (la setea game_table en su _ready)
var game_table: Node = null

# Cola de turnos extra (Change of Luck etc.)
var extra_turn_queue: Array[int] = []

# Configuración de Red
const PORT = 7777
const MAX_CLIENTS = 4

func _ready():
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_ok)
	multiplayer.connection_failed.connect(_on_connected_fail)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ==============================================================================
# 🔄 SISTEMA DE TURNOS Y MAZOS
# ==============================================================================

func initialize_deck():
	deck.clear()
	nursery_deck.clear()
	discard_pile.clear()

	for card_id in CardDatabase.database:
		var data = CardDatabase.database[card_id]
		if data.type == GameEnums.CardType.REFERENCE:
			continue # Cartas de referencia no van al mazo
		if data.is_nursery:
			nursery_deck.append(card_id)
		else:
			deck.append(card_id)

	deck.shuffle()

	print("Servidor: Mazos listos.")
	print(" - Robo: ", deck.size(), " cartas.")
	print(" - Guardería: ", nursery_deck.size(), " bebés disponibles.")

func setup_turn_order():
	turn_order.assign(players.keys())
	turn_order.sort()
	current_turn_index = 0

	if not turn_order.is_empty():
		_server_start_turn(turn_order[0])

# --- FLUJO DEL TURNO (server-authoritative) ---

func _server_start_turn(player_id: int):
	if not multiplayer.is_server(): return

	# Si el jugador no existe (se desconectó), pasar al siguiente
	if not players.has(player_id):
		print("Servidor: jugador ", player_id, " ya no existe, saltando turno")
		turn_order.erase(player_id)
		extra_turn_queue.erase(player_id)
		if turn_order.is_empty():
			print("Servidor: no quedan jugadores"); return
		current_turn_index = current_turn_index % turn_order.size()
		_server_start_turn(turn_order[current_turn_index])
		return

	active_player_id = player_id
	actions_remaining = 1

	print("Servidor: --- TURNO de ", players[player_id].name, " ---")

	# Fase START
	rpc("sync_turn_state", player_id, TurnPhase.START, actions_remaining)
	# Cámara Espía: refrescar manos visibles al inicio de cada turno
	if game_table:
		game_table.server_refresh_visible_hands()
	# Dispara efectos on_turn_start del establo (recurrentes)
	await EffectProcessor.resolve_on_turn_start(player_id)

	if not is_game_active: return
	await get_tree().create_timer(0.4).timeout
	if not is_game_active: return
	_server_advance_to_draw_phase()

# Encola un turno extra (Change of Luck): después del END del turno actual,
# en vez de pasar al siguiente, el mismo jugador juega otra vez.
func queue_extra_turn(player_id: int) -> void:
	if not multiplayer.is_server(): return
	extra_turn_queue.append(player_id)

func _server_advance_to_draw_phase():
	if not multiplayer.is_server(): return
	rpc("sync_turn_state", active_player_id, TurnPhase.DRAW, actions_remaining)

	# Robo automático de 1 carta
	var drawn_ids = draw_cards(1)
	if not drawn_ids.is_empty():
		var card_id = drawn_ids[0]
		if players.has(active_player_id):
			var card_data = CardDatabase.get_card_data(card_id)
			players[active_player_id].hand.append(card_data)
			# Enviar al dueño
			if game_table:
				game_table.rpc_id(active_player_id, "client_receive_drawn_batch", [card_id])
				var new_size = players[active_player_id].hand.size()
				for p in players:
					if p != active_player_id:
						game_table.rpc_id(p, "client_sync_hand_size", active_player_id, new_size)
				game_table.rpc("client_sync_deck_counters", deck.size(), discard_pile.size(), nursery_deck.size())

	await get_tree().create_timer(0.3).timeout
	if not is_game_active: return
	_server_advance_to_action_phase()

func _server_advance_to_action_phase():
	if not multiplayer.is_server(): return
	rpc("sync_turn_state", active_player_id, TurnPhase.ACTION, actions_remaining)

@rpc("any_peer", "call_local", "reliable")
func request_end_turn():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != active_player_id:
		printerr("Servidor: ", sender_id, " intenta terminar turno ajeno")
		return
	if current_phase != TurnPhase.ACTION:
		printerr("Servidor: Solicitud de Fin de Turno fuera de fase ACTION")
		return
	if is_resolving:
		printerr("Servidor: no puedes terminar turno con un efecto en curso")
		return
	_server_advance_to_end_phase()

func _server_advance_to_end_phase():
	if not multiplayer.is_server(): return
	rpc("sync_turn_state", active_player_id, TurnPhase.END, 0)

	# Aplicar límite de mano
	var player: PlayerData = players.get(active_player_id)
	if player:
		var limit = current_rules.hand_limit
		while player.hand.size() > limit:
			var card: CardData = player.hand.pop_front()
			discard_pile.append(card.id)
			if game_table:
				game_table.rpc_id(active_player_id, "client_force_discard", card.id)
		var new_size = player.hand.size()
		if game_table:
			for p in players:
				if p != active_player_id:
					game_table.rpc_id(p, "client_sync_hand_size", active_player_id, new_size)
			game_table.rpc("client_sync_deck_counters", deck.size(), discard_pile.size(), nursery_deck.size())

	await get_tree().create_timer(0.4).timeout
	if not is_game_active: return
	_server_next_turn()

func _server_next_turn():
	if not multiplayer.is_server(): return
	if turn_order.is_empty(): return

	# ¿Hay un turno extra encolado?
	if not extra_turn_queue.is_empty():
		var extra_player = extra_turn_queue.pop_front()
		print("Servidor: Turno EXTRA para ", players[extra_player].name)
		_server_start_turn(extra_player)
		return

	current_turn_index = (current_turn_index + 1) % turn_order.size()
	_server_start_turn(turn_order[current_turn_index])

# Llamado por server_play_card en game_table cuando se consume una acción
func consume_action() -> void:
	if not multiplayer.is_server(): return
	actions_remaining = max(0, actions_remaining - 1)
	rpc("sync_actions_remaining", actions_remaining)
	if actions_remaining == 0 and current_phase == TurnPhase.ACTION:
		_server_advance_to_end_phase()

# Suma acciones extra (Double Dutch en Fase 2)
func grant_extra_action(amount: int = 1) -> void:
	if not multiplayer.is_server(): return
	actions_remaining += amount
	rpc("sync_actions_remaining", actions_remaining)

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

# Reinicia el estado para una nueva partida (revancha) manteniendo a los jugadores.
func reset_for_new_match():
	if not multiplayer.is_server(): return
	deck.clear()
	discard_pile.clear()
	nursery_deck.clear()
	turn_order.clear()
	current_turn_index = 0
	active_player_id = 0
	extra_turn_queue.clear()
	is_resolving = false
	current_phase = TurnPhase.START
	for pid in players:
		players[pid].hand.clear()
		players[pid].stable.clear()
	is_game_active = true

# --- Mazo / Descarte ---

func draw_cards(amount: int) -> Array[int]:
	var drawn: Array[int] = []
	for i in range(amount):
		if deck.is_empty():
			_refill_deck_from_discard()
			if deck.is_empty(): break
		drawn.append(deck.pop_back())
	return drawn

func _refill_deck_from_discard():
	if discard_pile.is_empty(): return
	print("Servidor: Rebarajando descarte...")
	deck.append_array(discard_pile)
	discard_pile.clear()
	deck.shuffle()

# ==============================================================================
# 🏆 CONDICIÓN DE VICTORIA
# ==============================================================================

func check_win_condition() -> bool:
	if not multiplayer.is_server(): return false
	if not is_game_active: return false

	for p_id in players:
		# Pandamonio: tus unicornios cuentan como pandas → NO cuentan para ganar
		if EffectProcessor.passives.unicorns_are_pandas(p_id):
			continue
		var unicorn_count = 0
		for card in players[p_id].stable:
			unicorn_count += card.unicorn_count_value()
		if unicorn_count >= current_rules.unicorns_to_win:
			rpc("announce_winner", p_id, players[p_id].name)
			return true
	return false

@rpc("authority", "call_local", "reliable")
func announce_winner(winner_id: int, winner_name: String):
	is_game_active = false
	game_won.emit(winner_id, winner_name)
	print("🏆 ¡", winner_name, " GANA LA PARTIDA!")

# ==============================================================================
# 🌐 LÓGICA DE CONEXIÓN (HOSTING / JOINING)
# ==============================================================================

func host_game(player_name: String, rules: GameRules):
	local_player_info["name"] = player_name
	current_rules = rules

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)

	if error != OK:
		game_error.emit("No se pudo crear el servidor: " + str(error))
		return

	multiplayer.multiplayer_peer = peer
	print("Servidor iniciado. Esperando jugadores...")

	_register_player(1, local_player_info)

func join_game(player_name: String, ip: String):
	local_player_info["name"] = player_name

	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_client(ip, PORT)

	if error != OK:
		game_error.emit("No se pudo conectar: " + str(error))
		return

	multiplayer.multiplayer_peer = peer
	print("Intentando conectar a ", ip)

# ==============================================================================
# 🤝 HANDSHAKE
# ==============================================================================

func _on_peer_connected(id: int):
	print("Nuevo peer detectado: ", id)

func _on_connected_ok():
	print("¡Conexión exitosa al servidor!")
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

	_register_player(sender_id, info)

	for p_id in players:
		rpc_id(sender_id, "register_player_client", p_id, {"name": players[p_id].name})

	rpc_id(sender_id, "sync_rules", current_rules.to_dictionary())

@rpc("authority", "reliable")
func register_player_client(id: int, info: Dictionary):
	_register_player(id, info)

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
	var new_player = PlayerData.new(id, info["name"])
	players[id] = new_player
	player_connected.emit(new_player)
	print("Jugador registrado: ", info["name"], " [ID: ", id, "]")

func _on_peer_disconnected(id: int):
	if players.has(id):
		print("Jugador desconectado: ", players[id].name)
		players.erase(id)
		player_disconnected.emit(id)

func get_opponents_of(player_id: int) -> Array[int]:
	var result: Array[int] = []
	for p in players:
		if p != player_id:
			result.append(p)
	return result

# ==============================================================================
# 🏁 INICIO DEL JUEGO
# ==============================================================================

func start_game():
	if not multiplayer.is_server(): return

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
