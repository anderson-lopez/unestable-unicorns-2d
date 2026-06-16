extends Node
# Autoload: SERVIDOR DEDICADO multi-sala (para Render).
# Maneja salas con código único. Cada peer pertenece a UNA sala.
# Este archivo es SOLO matchmaking (crear/unirse/listar salas). La lógica de la
# partida por-sala se conecta en pasos posteriores.
#
# Modos:
#   - DEDICATED (servidor en Render): arranca con --dedicated o variable env.
#     Crea el servidor WebSocket y gestiona todas las salas.
#   - CLIENTE: el juego normal; usa rpc_id(1, ...) para pedir crear/unirse a sala.

signal room_created(code: String)
signal room_joined(code: String, players: Array)
signal room_players_updated(players: Array)
signal room_error(message: String)
signal room_game_started(code: String)

const PORT := 7777
const MAX_PER_ROOM := 4
const MIN_TO_START := 2
const CODE_CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" # sin I,O,0,1 (confusión)
const CODE_LEN := 4

# --- Estado SOLO del servidor dedicado ---
var is_dedicated := false
# code -> { "host": peer_id, "players": { peer_id: name }, "started": bool }
var rooms: Dictionary = {}
# peer_id -> code  (en qué sala está cada conexión)
var peer_room: Dictionary = {}
# Opción 🅰️: UNA partida a la vez. Mientras hay una partida activa, no se crean
# salas nuevas (así todos los conectados son los de esa partida y los broadcast
# de RPCs visuales son seguros).
var game_in_progress := false
var active_room_code := ""

# --- Estado del CLIENTE ---
var my_room_code: String = ""
var my_room_players: Array = [] # [{id, name}]
var server_url: String = ""

func _ready():
	# Arranque como servidor dedicado si se pide por argumento o variable de entorno.
	var args := OS.get_cmdline_user_args()
	if "--dedicated" in OS.get_cmdline_args() or "dedicated" in args or OS.has_environment("UU_DEDICATED"):
		call_deferred("start_dedicated_server")

# ==============================================================================
# 🖥️ SERVIDOR DEDICADO
# ==============================================================================

func start_dedicated_server():
	is_dedicated = true
	var port := PORT
	# Render asigna el puerto en la variable PORT.
	if OS.has_environment("PORT"):
		port = int(OS.get_environment("PORT"))

	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		push_error("OnlineServer: no se pudo crear el servidor en puerto %d (err %d)" % [port, err])
		return
	multiplayer.multiplayer_peer = peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	print("🖥️  SERVIDOR DEDICADO escuchando en puerto ", port)

func _on_peer_connected(id: int):
	print("OnlineServer: peer conectado ", id)

func _on_peer_disconnected(id: int):
	print("OnlineServer: peer desconectado ", id)
	_remove_peer_from_room(id)

func _generate_code() -> String:
	# Código único de CODE_LEN caracteres (sin Date/Random prohibidos: usamos randi).
	for _try in range(50):
		var code := ""
		for i in range(CODE_LEN):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not rooms.has(code):
			return code
	# Fallback improbable: alarga
	return _generate_code() + CODE_CHARS[randi() % CODE_CHARS.length()]

func _remove_peer_from_room(id: int):
	if not peer_room.has(id): return
	var code: String = peer_room[id]
	peer_room.erase(id)
	if not rooms.has(code): return
	rooms[code]["players"].erase(id)
	if rooms[code]["players"].is_empty():
		rooms.erase(code) # sala vacía → se elimina
		print("OnlineServer: sala ", code, " cerrada (vacía)")
		# Si era la partida activa, el servidor vuelve a aceptar salas.
		# (No recargamos escena: el próximo _start_game_for_room recarga GameTable.)
		if code == active_room_code:
			reset_active_game()
	else:
		# Si se fue el host, pasa el host al siguiente.
		if rooms[code]["host"] == id:
			rooms[code]["host"] = rooms[code]["players"].keys()[0]
		_broadcast_room_players(code)

func _broadcast_room_players(code: String):
	if not rooms.has(code): return
	var list := _room_players_array(code)
	for pid in rooms[code]["players"]:
		rpc_id(pid, "_recv_room_players", list)

func _room_players_array(code: String) -> Array:
	var list: Array = []
	if not rooms.has(code): return list
	var host_id: int = rooms[code]["host"]
	for pid in rooms[code]["players"]:
		list.append({"id": pid, "name": rooms[code]["players"][pid], "host": pid == host_id})
	return list

# --- RPCs servidor (cliente → servidor) ---

@rpc("any_peer", "reliable")
func req_create_room(player_name: String):
	if not is_dedicated: return
	var sender := multiplayer.get_remote_sender_id()
	# Una partida a la vez: si ya hay una sala/partida, no se crean más.
	if game_in_progress or not rooms.is_empty():
		rpc_id(sender, "_recv_room_error", "El servidor está ocupado con otra sala. Intenta más tarde o únete con su código.")
		return
	var code := _generate_code()
	# Cada sala lleva su propio RoomState (estado de partida por-sala, Fase 3.3).
	var state := RoomState.new(code, sender)
	rooms[code] = {"host": sender, "players": {sender: player_name}, "started": false, "state": state}
	peer_room[sender] = code
	print("OnlineServer: sala creada ", code, " por ", sender)
	rpc_id(sender, "_recv_room_joined", code, _room_players_array(code))

# Helper de enrutado (Fase 3.3): obtiene el RoomState de la sala de un peer.
func room_state_of(peer_id: int) -> RoomState:
	if not peer_room.has(peer_id): return null
	var code: String = peer_room[peer_id]
	if not rooms.has(code): return null
	return rooms[code].get("state")

func room_state_by_code(code: String) -> RoomState:
	if not rooms.has(code): return null
	return rooms[code].get("state")

@rpc("any_peer", "reliable")
func req_join_room(code: String, player_name: String):
	if not is_dedicated: return
	var sender := multiplayer.get_remote_sender_id()
	code = code.strip_edges().to_upper()
	if not rooms.has(code):
		rpc_id(sender, "_recv_room_error", "La sala '%s' no existe." % code)
		return
	if rooms[code]["started"]:
		rpc_id(sender, "_recv_room_error", "La partida en '%s' ya empezó." % code)
		return
	if rooms[code]["players"].size() >= MAX_PER_ROOM:
		rpc_id(sender, "_recv_room_error", "La sala '%s' está llena." % code)
		return
	rooms[code]["players"][sender] = player_name
	peer_room[sender] = code
	rpc_id(sender, "_recv_room_joined", code, _room_players_array(code))
	_broadcast_room_players(code)

@rpc("any_peer", "reliable")
func req_start_room():
	if not is_dedicated: return
	var sender := multiplayer.get_remote_sender_id()
	if not peer_room.has(sender): return
	var code: String = peer_room[sender]
	if not rooms.has(code): return
	if rooms[code]["host"] != sender:
		return # solo el host inicia
	if rooms[code]["players"].size() < MIN_TO_START:
		rpc_id(sender, "_recv_room_error", "Faltan jugadores (mínimo %d)." % MIN_TO_START)
		return
	if game_in_progress:
		rpc_id(sender, "_recv_room_error", "Ya hay una partida en curso.")
		return
	_start_game_for_room(code)

# Arranca la partida de una sala EN EL SERVIDOR DEDICADO (Opción 🅰️):
#  - Registra a los jugadores de la sala en GameManager (el servidor NO es jugador).
#  - El servidor carga la mesa para correr la lógica y RETRANSMITIR los RPCs visuales.
#  - Los clientes de la sala cargan su mesa al recibir _recv_room_started.
func _start_game_for_room(code: String):
	if not rooms.has(code): return
	game_in_progress = true
	active_room_code = code
	rooms[code]["started"] = true

	# Cierra la puerta: no entran más peers mientras dure la partida.
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.refuse_new_connections = true

	# Reglas FRESCAS para la partida online (meta = 7 unicornios por defecto). El
	# servidor de Render vive mucho tiempo y, sin esto, podría arrastrar reglas
	# viejas (p. ej. meta = 0/1 → alguien "gana" al instante en la selección de bebés).
	GameManager.current_rules = GameRules.new()
	print("OnlineServer: meta de la partida = ", GameManager.current_rules.unicorns_to_win, " unicornios")

	# Registrar a los jugadores reales en GameManager (el servidor/peer 1 NO).
	GameManager.players.clear()
	GameManager.is_dedicated_referee = true
	GameManager.is_game_active = true
	var roster: Array = []
	for pid in rooms[code]["players"]:
		GameManager._register_player(pid, {"name": rooms[code]["players"][pid]})
		roster.append({"id": pid, "name": rooms[code]["players"][pid]})

	# Sincronizar el roster COMPLETO a cada cliente de la sala (antes de cargar la
	# mesa) para que GameManager.players exista igual en todos.
	for pid in rooms[code]["players"]:
		GameManager.rpc_id(pid, "online_sync_roster", roster)
		# También las reglas (para que el HUD muestre la meta correcta).
		GameManager.rpc_id(pid, "sync_rules", GameManager.current_rules.to_dictionary())

	# Avisar a los clientes de la sala para que carguen su mesa (llega después del
	# roster por ser RPCs fiables y ordenados).
	for pid in rooms[code]["players"]:
		rpc_id(pid, "_recv_room_started", code)

	# El servidor también carga la mesa: necesita el nodo /root/GameTable con los
	# RPCs visuales para retransmitir, y allí su _ready dispara la lógica de inicio.
	print("OnlineServer: partida iniciada en sala ", code, " (", rooms[code]["players"].size(), " jugadores)")
	get_tree().change_scene_to_file(GameManager.game_scene_path)

# Reinicia el estado del servidor al terminar la partida (vuelve a aceptar salas).
func reset_active_game():
	game_in_progress = false
	active_room_code = ""
	GameManager.is_dedicated_referee = false
	GameManager.is_game_active = false
	GameManager.players.clear()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.refuse_new_connections = false

# ==============================================================================
# 📡 CLIENTE
# ==============================================================================

func connect_to_server(url: String):
	server_url = url
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		room_error.emit("No se pudo conectar al servidor online.")
		return
	multiplayer.multiplayer_peer = peer

func create_room(player_name: String):
	rpc_id(1, "req_create_room", player_name)

func join_room(code: String, player_name: String):
	rpc_id(1, "req_join_room", code, player_name)

func start_room():
	rpc_id(1, "req_start_room")

# --- RPCs cliente (servidor → cliente) ---

@rpc("authority", "reliable")
func _recv_room_joined(code: String, players: Array):
	my_room_code = code
	my_room_players = players
	room_joined.emit(code, players)

@rpc("authority", "reliable")
func _recv_room_players(players: Array):
	my_room_players = players
	room_players_updated.emit(players)

@rpc("authority", "reliable")
func _recv_room_error(message: String):
	room_error.emit(message)

@rpc("authority", "reliable")
func _recv_room_started(code: String):
	room_game_started.emit(code)
