extends Node
# Autoload: SERVIDOR DEDICADO multi-sala (para Render).
# Maneja salas con código único. Cada peer pertenece a UNA sala.
# Varias salas pueden estar en partida simultáneamente: cada sala tiene su propio
# RoomState y el servidor usa ONE instancia de GameTable que enruta por sala.
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
# code -> { "host": peer_id, "players": { peer_id: {name,avatar_id} }, "started": bool, "state": RoomState }
var rooms: Dictionary = {}
# peer_id -> code  (en qué sala está cada conexión)
var peer_room: Dictionary = {}

# Evita cargar la escena de juego más de una vez en el servidor.
var _server_game_loaded: bool = false
# Salas pendientes de inicializar (la escena todavía no está cargada).
var _pending_starts: Array[String] = []

# --- Estado del CLIENTE ---
var my_room_code: String = ""
var my_room_players: Array = [] # [{id, name}]
var server_url: String = ""

func _ready():
	var args := OS.get_cmdline_user_args()
	if "--dedicated" in OS.get_cmdline_args() or "dedicated" in args or OS.has_environment("UU_DEDICATED"):
		call_deferred("start_dedicated_server")

# ==============================================================================
# 🖥️ SERVIDOR DEDICADO
# ==============================================================================

func start_dedicated_server():
	is_dedicated = true
	var port := PORT
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
	for _try in range(50):
		var code := ""
		for i in range(CODE_LEN):
			code += CODE_CHARS[randi() % CODE_CHARS.length()]
		if not rooms.has(code):
			return code
	return _generate_code() + CODE_CHARS[randi() % CODE_CHARS.length()]

func _remove_peer_from_room(id: int):
	if not peer_room.has(id): return
	var code: String = peer_room[id]
	peer_room.erase(id)
	if not rooms.has(code): return
	rooms[code]["players"].erase(id)
	if rooms[code]["players"].is_empty():
		rooms.erase(code)
		print("OnlineServer: sala ", code, " cerrada (vacía)")
	else:
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
		var pdata = rooms[code]["players"][pid]
		list.append({"id": pid, "name": pdata["name"], "avatar_id": pdata.get("avatar_id", 1), "host": pid == host_id})
	return list

# Helper: RoomState del peer dado (usado por GameManager._get_rs_for).
func get_room_state_for_peer(peer_id: int) -> RoomState:
	if not peer_room.has(peer_id): return null
	var code: String = peer_room[peer_id]
	if not rooms.has(code): return null
	return rooms[code].get("state")

func room_state_by_code(code: String) -> RoomState:
	if not rooms.has(code): return null
	return rooms[code].get("state")

# --- RPCs servidor (cliente → servidor) ---

@rpc("any_peer", "reliable")
func req_create_room(player_name: String, avatar_id: int = 1):
	if not is_dedicated: return
	var sender := multiplayer.get_remote_sender_id()
	if peer_room.has(sender):
		rpc_id(sender, "_recv_room_error", "Ya estás en una sala.")
		return
	var code := _generate_code()
	var state := RoomState.new(code, sender)
	rooms[code] = {
		"host": sender,
		"players": {sender: {"name": player_name, "avatar_id": avatar_id}},
		"started": false,
		"state": state
	}
	peer_room[sender] = code
	print("OnlineServer: sala creada ", code, " por ", sender)
	rpc_id(sender, "_recv_room_joined", code, _room_players_array(code))

@rpc("any_peer", "reliable")
func req_join_room(code: String, player_name: String, avatar_id: int = 1):
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
	rooms[code]["players"][sender] = {"name": player_name, "avatar_id": avatar_id}
	peer_room[sender] = code
	rpc_id(sender, "_recv_room_joined", code, _room_players_array(code))
	_broadcast_room_players(code)

@rpc("any_peer", "reliable")
func req_start_room(rules_dict: Dictionary = {}):
	if not is_dedicated: return
	var sender := multiplayer.get_remote_sender_id()
	if not peer_room.has(sender): return
	var code: String = peer_room[sender]
	if not rooms.has(code): return
	if rooms[code]["host"] != sender: return
	if rooms[code]["started"]:
		return  # ya iniciada
	if rooms[code]["players"].size() < MIN_TO_START:
		rpc_id(sender, "_recv_room_error", "Faltan jugadores (mínimo %d)." % MIN_TO_START)
		return
	_start_game_for_room(code, rules_dict)

func _start_game_for_room(code: String, rules_dict: Dictionary = {}):
	if not rooms.has(code): return
	rooms[code]["started"] = true

	var rs: RoomState = rooms[code]["state"]

	# Reglas
	rs.rules = GameRules.new()
	if not rules_dict.is_empty():
		rs.rules.from_dictionary(rules_dict)

	# Poblar rs.players con los jugadores reales de la sala
	rs.players.clear()
	var roster: Array = []
	for pid in rooms[code]["players"]:
		var pdata = rooms[code]["players"][pid]
		var pd = PlayerData.new(pid, pdata["name"], pdata.get("avatar_id", 1))
		rs.players[pid] = pd
		roster.append({"id": pid, "name": pdata["name"], "avatar_id": pdata.get("avatar_id", 1)})
	rs.is_active = true

	print("OnlineServer: partida iniciada en sala ", code, " — meta=", rs.rules.unicorns_to_win, " | tiempo/turno=", rs.rules.turn_time_seconds, "s")

	# Marcar servidor como árbitro dedicado (se activa una sola vez)
	GameManager.is_dedicated_referee = true

	# Sincronizar roster y reglas a los clientes de esta sala
	for pid in rooms[code]["players"]:
		GameManager.rpc_id(pid, "online_sync_roster", roster)
		GameManager.rpc_id(pid, "sync_rules", rs.rules.to_dictionary())

	# Decirle a los clientes que carguen su mesa
	for pid in rooms[code]["players"]:
		rpc_id(pid, "_recv_room_started", code)

	# Servidor: iniciar lógica de la sala
	if _server_game_loaded and GameManager.game_table:
		# GameTable ya cargado → iniciar directamente
		GameManager.game_table.call_deferred("_start_for_room", rs)
	else:
		# Guardar sala pendiente y cargar la escena (solo la primera vez)
		_pending_starts.append(code)
		if not _server_game_loaded:
			_server_game_loaded = true
			get_tree().change_scene_to_file(GameManager.game_scene_path)

# Llamado por game_table._ready() en el servidor para procesar las salas pendientes.
func flush_pending_starts():
	var pending = _pending_starts.duplicate()
	_pending_starts.clear()
	for code in pending:
		var rs = room_state_by_code(code)
		if rs and rs.is_active and GameManager.game_table:
			GameManager.game_table._start_for_room(rs)

# Limpia el estado de una sala terminada (llamado desde game_table al final).
func reset_room(code: String):
	if rooms.has(code):
		rooms[code]["started"] = false
		var rs: RoomState = rooms[code].get("state")
		if rs: rs.is_active = false

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

func create_room(player_name: String, avatar_id: int = 1):
	rpc_id(1, "req_create_room", player_name, avatar_id)

func join_room(code: String, player_name: String, avatar_id: int = 1):
	rpc_id(1, "req_join_room", code, player_name, avatar_id)

func start_room():
	rpc_id(1, "req_start_room", GameManager.current_rules.to_dictionary())

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
