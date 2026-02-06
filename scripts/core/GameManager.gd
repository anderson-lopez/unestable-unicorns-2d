extends Node

# --- SEÑALES ---
signal player_connected(player_data: PlayerData)
signal player_disconnected(player_id: int)
signal game_started # Cuando el host da "Iniciar Partida"
signal game_error(message: String)
signal rules_updated
signal turn_changed(player_id: int)
signal phase_changed(new_phase: TurnPhase)

# --- VARIABLES DE ESTADO ---
# Diccionario: { peer_id : PlayerData }
var players: Dictionary = {}
var local_player_info: Dictionary = {"name": "Player"} # Info temporal antes de conectar
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

enum TurnPhase { START, DRAW, ACTION, END }
var current_phase: TurnPhase = TurnPhase.START

# Configuración de Red
const PORT = 7777
const MAX_CLIENTS = 4 # Puedes subirlo si quieres más caos

func _ready():
	# Conectamos señales nativas de Godot para el arbol de escenas
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
	
	# Recorremos TODA la base de datos y clasificamos
	for card_id in CardDatabase.database:
		var data = CardDatabase.database[card_id]
		
		if data.is_nursery:
			# Si es bebé, va a la guardería
			nursery_deck.append(card_id)
		else:
			# Si es normal, va al mazo de robo
			deck.append(card_id)
	
	# Solo barajamos el mazo de robo, la guardería es una lista pública
	deck.shuffle()
	
	print("Servidor: Mazos listos.")
	print(" - Robo: ", deck.size(), " cartas.")
	print(" - Guardería: ", nursery_deck.size(), " bebés disponibles.")

# Función para inicializar el orden (Llamar al iniciar la partida)
func setup_turn_order():
	# --- CORRECCIÓN CRÍTICA AQUÍ ---
	# Usamos .assign() porque players.keys() devuelve un Array genérico
	# y turn_order espera Array[int].
	turn_order.assign(players.keys())
	
	turn_order.sort() # O .shuffle() si quieres orden aleatorio
	current_turn_index = 0
	
	if not turn_order.is_empty():
		active_player_id = turn_order[0]
		current_phase = TurnPhase.START
		print("Servidor: Orden de turnos: ", turn_order)
		rpc("sync_turn_state", active_player_id, current_phase)

# Función para pasar turno
func next_turn():
	if turn_order.is_empty(): return
	
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	active_player_id = turn_order[current_turn_index]
	current_phase = TurnPhase.START
	
	print("Servidor: Turno de ", players[active_player_id].name)
	rpc("sync_turn_state", active_player_id, current_phase)

@rpc("authority", "call_local", "reliable")
func sync_turn_state(player_id: int, phase: int):
	active_player_id = player_id
	current_phase = phase
	turn_changed.emit(player_id)
	phase_changed.emit(phase)

func draw_cards(amount: int) -> Array[int]:
	var drawn: Array[int] = []
	for i in range(amount):
		if deck.is_empty():
			_refill_deck_from_discard()
			if deck.is_empty(): break # No hay más cartas en el juego
		
		drawn.append(deck.pop_back())
	return drawn

func _refill_deck_from_discard():
	if discard_pile.is_empty(): return
	print("Servidor: Rebarajando descarte...")
	deck.append_array(discard_pile)
	discard_pile.clear()
	deck.shuffle()

# ==============================================================================
# 🌐 LÓGICA DE CONEXIÓN (HOSTING / JOINING)
# ==============================================================================

# Llamar esto desde el botón "Crear Partida" del Menú Principal
func host_game(player_name: String, rules: GameRules):
	local_player_info["name"] = player_name
	current_rules = rules # Guardamos las reglas que configuró el Host
	
	var peer = ENetMultiplayerPeer.new()
	var error = peer.create_server(PORT, MAX_CLIENTS)
	
	if error != OK:
		game_error.emit("No se pudo crear el servidor: " + str(error))
		return
		
	multiplayer.multiplayer_peer = peer
	print("Servidor iniciado. Esperando jugadores...")
	
	# Registrar al Host como el primer jugador (ID 1 siempre es el Host)
	_register_player(1, local_player_info)

# Llamar esto desde el botón "Unirse a Partida"
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
# 🤝 HANDSHAKE (SALUDO INICIAL Y REGISTRO)
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

# --- RPCs (Llamadas Remotas) ---

@rpc("any_peer", "reliable")
func register_player_request(info: Dictionary):
	var sender_id = multiplayer.get_remote_sender_id()
	print("Solicitud de registro recibida de: ", sender_id)
	
	# 1. Registrar al nuevo en el Servidor
	_register_player(sender_id, info)
	
	# 2. Enviar al nuevo jugador la lista de los que YA estaban
	for p_id in players:
		rpc_id(sender_id, "register_player_client", p_id, {"name": players[p_id].name})
	
	# 3. Enviar al nuevo jugador las REGLAS de la partida
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

# ==============================================================================
# 🏁 INICIO DEL JUEGO
# ==============================================================================

func start_game():
	if not multiplayer.is_server(): return
	
	multiplayer.multiplayer_peer.refuse_new_connections = true
	rpc("load_game_scene")

@rpc("authority", "call_local", "reliable")
func load_game_scene():
	print("Cargando escena de juego...")
	get_tree().change_scene_to_file(game_scene_path)

@rpc("authority", "reliable")
func client_start_game():
	is_game_active = true
	game_started.emit()
	print("¡EL JUEGO HA COMENZADO!")
