extends Control

# --- CONSTANTES ---
const RIVAL_ZONE_SCENE = preload("res://scenes/game/RivalZone.tscn")
const CARD_SCENE = preload("res://scenes/cards/CardUI.tscn")

# --- REFERENCIAS DE UI ---
# Zona del Jugador (Mano y Establo)
@onready var my_hand_container: HBoxContainer = $HandZone/CardsContainer
@onready var my_stable_container: VBoxContainer = $MyStable 
@onready var my_upgrades_row: HBoxContainer = $MyStable/UpgradesRow
@onready var my_unicorns_row: HBoxContainer = $MyStable/UnicornsRow

# Zona Global
@onready var rivals_container: Control = $RivalsContainer 
@onready var info_panel: CardInfoPanel = $UILayer/CardInfoPanel
@onready var card_selector: PanelContainer = $UILayer/CardSelector

# Botones Debug
@onready var btn_add_random: Button = $DebugUI/BtnAddRandom
@onready var btn_add_magic: Button = $DebugUI/BtnAddMagic

# --- VARIABLES LÓGICAS ---
var rival_stables: Dictionary = {}

func _ready():
	# Verificaciones de seguridad visual
	if not my_hand_container or not rivals_container or not my_stable_container:
		printerr("ERROR CRÍTICO: Faltan nodos contenedores en la escena GameTable.")
		return

	# Limpieza inicial
	_clear_debug_cards()
	
	# Configurar Botones de Debug
	btn_add_random.pressed.connect(func(): rpc_id(1, "server_request_draw"))
	btn_add_magic.pressed.connect(_spawn_magic_card)
	
	# Configurar Mesa Multijugador
	setup_table()
	
	# Solo el HOST inicia la secuencia de partida
	if multiplayer.is_server():
		_server_start_match_logic()
	GameManager.turn_changed.connect(_on_turn_changed)

func _on_turn_changed(player_id: int):
	var my_id = multiplayer.get_unique_id()
	if player_id == my_id:
		print("¡ES MI TURNO!")
		# Aquí habilitaremos tus botones, haremos brillar tu avatar, etc.
		btn_add_random.disabled = false # Ejemplo: Solo puedes robar en tu turno
	else:
		print("Es el turno del rival: ", player_id)
		# Bloqueamos controles para que no juegues fuera de turno
		btn_add_random.disabled = true

# ==============================================================================
# 🏗️ CONFIGURACIÓN DE LA MESA (SETUP)
# ==============================================================================

func setup_table():
	var my_id = multiplayer.get_unique_id()
	
	# Crear zonas para cada jugador conectado
	for p_id in GameManager.players:
		var p_data = GameManager.players[p_id]
		
		if p_id == my_id:
			print("Configurando mi zona: ", p_data.name)
		else:
			_create_rival_zone(p_id, p_data)

func _create_rival_zone(id: int, data: PlayerData):
	var rival_zone = RIVAL_ZONE_SCENE.instantiate()
	rivals_container.add_child(rival_zone)
	rival_zone.setup(data.name)
	rival_stables[id] = rival_zone

# ==============================================================================
# 🎮 CICLO DE JUEGO (SERVIDOR)
# ==============================================================================

func _server_start_match_logic():
	# Esperar a que todos carguen la escena
	await get_tree().process_frame 
	await get_tree().create_timer(1.0).timeout
	
	print("Servidor: Inicializando mazos...")
	GameManager.initialize_deck()
	
	print("Servidor: Iniciando Fase de Selección de Bebés...")
	# Paso 1: Pedir a todos que elijan su bebé
	rpc("client_start_baby_selection", GameManager.nursery_deck)

# Se llama cuando TODOS han elegido su bebé
func _server_deal_initial_hands():
	print("Servidor: Todos tienen bebé. Repartiendo manos iniciales...")
	
	for p_id in GameManager.players:
		var drawn_cards = GameManager.draw_cards(5)
		
		# Actualizar lógica
		GameManager.players[p_id].hand = _ids_to_data(drawn_cards)
		
		# Enviar cartas al dueño
		rpc_id(p_id, "client_receive_initial_hand", drawn_cards)
		
		# Avisar a rivales (para que dibujen dorsos)
		for other_id in GameManager.players:
			if other_id != p_id:
				rpc_id(other_id, "client_update_rival_hand_size", p_id, 5)
	
	print("Servidor: Reparto completado. Iniciando primer turno.")
	GameManager.setup_turn_order()

# ==============================================================================
# 👶 FASE DE SELECCIÓN DE BEBÉS (RPCs)
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_start_baby_selection(available_babies: Array):
	print("Cliente: Abriendo selector de bebés...")
	# Abrimos la ventana de selección
	card_selector.open_selection(available_babies, "¡Elige tu Bebé Inicial!")
	
	# Esperamos a que el jugador haga clic en una carta
	var selected_id = await card_selector.card_selected
	
	# Enviamos la respuesta al servidor
	rpc_id(1, "server_receive_baby_choice", selected_id)

@rpc("any_peer", "call_local", "reliable")
func server_receive_baby_choice(card_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	print("Servidor: Jugador ", sender_id, " eligió el bebé ID ", card_id)
	
	# 1. Colocar bebé en el establo directamente
	if GameManager.players.has(sender_id):
		var card_data = CardDatabase.get_card_data(card_id)
		GameManager.players[sender_id].stable.append(card_data)
		
		# Avisar a todos para que aparezca visualmente
		rpc("client_card_entered_stable", sender_id, card_id)
	
	# 2. Verificar si todos han elegido ya
	var all_ready = true
	for p_id in GameManager.players:
		if GameManager.players[p_id].stable.is_empty():
			all_ready = false
			break
	
	# 3. Si todos listos, repartir mano
	if all_ready:
		_server_deal_initial_hands()

# ==============================================================================
# 🃏 ACCIONES DE JUEGO (JUGAR, ROBAR, DESCARTAR)
# ==============================================================================

# --- ROBAR CARTA ---
@rpc("any_peer", "call_local", "reliable")
func server_request_draw():
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	var drawn_ids = GameManager.draw_cards(1)
	if drawn_ids.is_empty(): return
	
	var new_card_id = drawn_ids[0]
	
	# Lógica
	var p_data = GameManager.players[sender_id]
	var card_data = CardDatabase.get_card_data(new_card_id)
	p_data.hand.append(card_data)
	
	# Visuales
	rpc_id(sender_id, "client_receive_single_card", new_card_id)
	
	var new_size = p_data.hand.size()
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_update_rival_hand_size", sender_id, new_size)

# --- JUGAR CARTA ---
@rpc("any_peer", "call_local", "reliable")
func server_play_card(card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	var card_data = CardDatabase.get_card_data(card_id)
	if not card_data: return

	print("Servidor: Jugador ", sender_id, " JUEGA ", card_data.name_es)

	# 1. Quitar de la mano
	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	
	# 2. Sincronizar mano rival
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_update_rival_hand_size", sender_id, new_size)
	
	# 3. Efecto según tipo
	if _is_permanent_card(card_data.type):
		# Va al establo
		rpc("client_card_entered_stable", sender_id, card_id)
		if GameManager.players.has(sender_id):
			GameManager.players[sender_id].stable.append(card_data)
	else:
		# Es magia/relincho -> Descarte directo (Por ahora)
		GameManager.discard_pile.append(card_id)
		# Aquí iría el RPC para mostrar el efecto visual de la magia

# --- DESCARTAR CARTA ---
@rpc("any_peer", "call_local", "reliable")
func server_discard_card(card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	
	print("Servidor: Jugador ", sender_id, " DESCARTA ", card_id)
	
	# 1. Quitar de mano y mover a pila lógica
	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	GameManager.discard_pile.append(card_id)
	
	# 2. Sincronizar rivales
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_update_rival_hand_size", sender_id, new_size)

# ==============================================================================
# 🎨 EVENTOS VISUALES (CLIENTE)
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_receive_initial_hand(card_ids: Array):
	for id in card_ids:
		add_card_to_hand(id)

@rpc("authority", "call_local", "reliable")
func client_receive_single_card(card_id: int):
	add_card_to_hand(card_id)

@rpc("authority", "call_local", "reliable")
func client_update_rival_hand_size(rival_id: int, new_count: int):
	if rival_stables.has(rival_id):
		rival_stables[rival_id].update_hand_visuals(new_count)

@rpc("authority", "call_local", "reliable")
func client_card_entered_stable(player_id: int, card_id: int):
	var my_id = multiplayer.get_unique_id()
	var card_data = CardDatabase.get_card_data(card_id)
	
	# 1. Crear Carta Visual
	var new_card = CARD_SCENE.instantiate()
	
	# 2. Ubicarla en el contenedor correcto
	if player_id == my_id:
		# ES MI ESTABLO: Decidimos fila según tipo
		if _is_upgrade_or_downgrade(card_data.type):
			my_upgrades_row.add_child(new_card)
		else:
			my_unicorns_row.add_child(new_card)
			
		# Ajustes visuales propios
		new_card.custom_minimum_size = Vector2(120, 165)
		new_card.scale = Vector2(0.8, 0.8)
		new_card.set_disabled(true)
		
	else:
		# ES UN RIVAL
		if rival_stables.has(player_id):
			rival_stables[player_id].add_card_to_stable(new_card)
	
	# 3. Cargar datos visuales (SIEMPRE AL FINAL)
	new_card.setup_card(card_data)

# ==============================================================================
# 🛠️ FUNCIONES INTERNAS Y UTILIDADES
# ==============================================================================

func add_card_to_hand(card_id: int):
	var data = CardDatabase.get_card_data(card_id)
	if not data: return

	var new_card = CARD_SCENE.instantiate()
	my_hand_container.add_child(new_card)
	
	new_card.setup_card(data)
	new_card.name = "Card_%d" % card_id
	
	# Conexiones locales
	new_card.info_requested.connect(_on_card_info_requested)
	new_card.play_requested.connect(_on_card_play_requested)
	new_card.discard_requested.connect(_on_card_discard_requested)

func _server_remove_card_from_hand(player_id: int, card_id: int) -> int:
	if not GameManager.players.has(player_id): return -1
	var p_data = GameManager.players[player_id]
	
	var idx = -1
	for i in range(p_data.hand.size()):
		if p_data.hand[i].id == card_id:
			idx = i
			break
	
	if idx != -1:
		p_data.hand.remove_at(idx)
	else:
		printerr("Servidor Warning: Intento de borrar carta inexistente en mano.")
		
	return p_data.hand.size()

func _ids_to_data(ids: Array[int]) -> Array[CardData]:
	var list: Array[CardData] = []
	for id in ids:
		var d = CardDatabase.get_card_data(id)
		if d: list.append(d)
	return list

func _is_permanent_card(type: GameEnums.CardType) -> bool:
	return type == GameEnums.CardType.BABY_UNICORN or \
		   type == GameEnums.CardType.BASIC_UNICORN or \
		   type == GameEnums.CardType.MAGICAL_UNICORN or \
		   type == GameEnums.CardType.UPGRADE or \
		   type == GameEnums.CardType.DOWNGRADE

func _is_upgrade_or_downgrade(type: GameEnums.CardType) -> bool:
	return type == GameEnums.CardType.UPGRADE or \
		   type == GameEnums.CardType.DOWNGRADE

# --- SIGNAL HANDLERS LOCALES ---

func _on_card_info_requested(data: CardData):
	info_panel.show_card_info(data)

func _on_card_play_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id
	rpc_id(1, "server_play_card", card_id)
	
	# Animación local inmediata (Predicción)
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _on_card_discard_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id
	rpc_id(1, "server_discard_card", card_id)
	
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _clear_debug_cards():
	for child in my_hand_container.get_children():
		child.queue_free()

func _spawn_magic_card():
	add_card_to_hand(3)
