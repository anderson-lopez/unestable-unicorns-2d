class_name RoomState extends RefCounted
# Contenedor del estado COMPLETO de UNA partida (una sala).
#
# Hoy GameManager guarda este estado como variables GLOBALES (una sola partida).
# Para multi-sala (Fase 3.3) cada sala tendrá su propio RoomState y el servidor
# tendrá un diccionario { codigo: RoomState }. La migración consiste en mover
# estas variables de GameManager → RoomState y enrutar cada RPC a la sala del emisor.
#
# Este archivo es la BASE: define qué estado es "por sala". Aún NO está cableado
# (GameManager sigue usando sus variables globales). El siguiente paso lo conecta.

# Identidad de la sala
var code: String = ""
var host_id: int = 0

# Jugadores de ESTA sala: { peer_id : PlayerData }
var players: Dictionary = {}

# Reglas de la partida
var rules: GameRules = GameRules.new()

# Estado de juego
var is_active: bool = false
var deck: Array[int] = []
var discard_pile: Array[int] = []
var nursery_deck: Array[int] = []

# Turnos
var turn_order: Array[int] = []
var current_turn_index: int = 0
var active_player_id: int = 0
var actions_remaining: int = 1
var current_phase: int = 0 # GameManager.TurnPhase
var is_resolving: bool = false
var extra_turn_queue: Array[int] = []
# Token que invalida timers de turno obsoletos al cambiar de turno/sala.
var _turn_timer_token: int = 0

# Descarte por límite de mano (entrada del jugador activo)
var pending_discard_ids: Array = []
var pending_discard_done: bool = false

# Pasivos activos en esta sala
var passives: PassiveRegistry = PassiveRegistry.new()

func _init(room_code: String = "", host: int = 0) -> void:
	code = room_code
	host_id = host

# Devuelve los oponentes de un jugador dentro de esta sala.
func opponents_of(player_id: int) -> Array[int]:
	var result: Array[int] = []
	for p in players:
		if p != player_id:
			result.append(p)
	return result

func reset_for_new_match() -> void:
	deck.clear()
	discard_pile.clear()
	nursery_deck.clear()
	turn_order.clear()
	current_turn_index = 0
	active_player_id = 0
	actions_remaining = 1
	extra_turn_queue.clear()
	is_resolving = false
	current_phase = 0
	_turn_timer_token = 0
	pending_discard_ids.clear()
	pending_discard_done = false
	for pid in players:
		players[pid].hand.clear()
		players[pid].stable.clear()
	passives.clear()
	is_active = true
