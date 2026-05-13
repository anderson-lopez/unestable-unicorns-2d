extends Control

# --- CONSTANTES ---
const RIVAL_ZONE_SCENE = preload("res://scenes/game/RivalZone.tscn")
const CARD_SCENE = preload("res://scenes/cards/CardUI.tscn")

# --- REFERENCIAS DE UI ---
@onready var my_hand_container: HBoxContainer = $HandZone/CardsContainer
@onready var my_stable_container: VBoxContainer = $MyStable
@onready var my_upgrades_row: HBoxContainer = $MyStable/UpgradesRow
@onready var my_unicorns_row: HBoxContainer = $MyStable/UnicornsRow

@onready var rivals_container: Control = $RivalsContainer
@onready var info_panel: CardInfoPanel = $UILayer/CardInfoPanel
@onready var card_selector: PanelContainer = $UILayer/CardSelector

@onready var btn_add_random: Button = $DebugUI/BtnAddRandom
@onready var btn_add_magic: Button = $DebugUI/BtnAddMagic

# --- VARIABLES LÓGICAS ---
var rival_stables: Dictionary = {}

# --- HUD construido por código ---
var hud_layer: CanvasLayer
var lbl_turn: Label
var lbl_phase: Label
var lbl_actions: Label
var btn_end_turn: Button
var lbl_deck: Label
var winner_panel: PanelContainer

func _ready():
	if not my_hand_container or not rivals_container or not my_stable_container:
		printerr("ERROR CRÍTICO: Faltan nodos contenedores en GameTable.")
		return

	_clear_debug_cards()
	_build_hud()

	# Botones de Debug — el botón de robar ya no es necesario (auto-draw).
	# Se mantiene oculto por si alguien lo necesita para pruebas.
	btn_add_random.visible = false
	btn_add_magic.pressed.connect(_spawn_magic_card)

	setup_table()

	if multiplayer.is_server():
		_server_start_match_logic()

	# Conexiones a GameManager
	GameManager.turn_changed.connect(_on_turn_changed)
	GameManager.phase_changed.connect(_on_phase_changed)
	GameManager.actions_changed.connect(_on_actions_changed)
	GameManager.game_won.connect(_on_game_won)

# ==============================================================================
# 🖼️ HUD
# ==============================================================================

func _build_hud():
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)

	# Panel superior con info de turno
	var top = PanelContainer.new()
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.anchor_top = 0.0
	top.anchor_bottom = 0.0
	top.offset_left = -250
	top.offset_right = 250
	top.offset_top = 10
	top.offset_bottom = 70
	hud_layer.add_child(top)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(hbox)

	lbl_turn = Label.new()
	lbl_turn.text = "Turno: —"
	lbl_turn.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_turn)

	lbl_phase = Label.new()
	lbl_phase.text = "Fase: —"
	lbl_phase.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_phase)

	lbl_actions = Label.new()
	lbl_actions.text = "Acciones: —"
	lbl_actions.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_actions)

	# Mazo (esquina superior derecha)
	lbl_deck = Label.new()
	lbl_deck.anchor_left = 1.0
	lbl_deck.anchor_right = 1.0
	lbl_deck.offset_left = -180
	lbl_deck.offset_right = -10
	lbl_deck.offset_top = 15
	lbl_deck.offset_bottom = 45
	lbl_deck.add_theme_font_size_override("font_size", 14)
	lbl_deck.text = "Mazo: — | Descarte: —"
	hud_layer.add_child(lbl_deck)

	# Botón Fin de Turno (esquina inferior derecha)
	btn_end_turn = Button.new()
	btn_end_turn.text = "Finalizar Turno"
	btn_end_turn.anchor_left = 1.0
	btn_end_turn.anchor_right = 1.0
	btn_end_turn.anchor_top = 1.0
	btn_end_turn.anchor_bottom = 1.0
	btn_end_turn.offset_left = -180
	btn_end_turn.offset_right = -20
	btn_end_turn.offset_top = -70
	btn_end_turn.offset_bottom = -20
	btn_end_turn.disabled = true
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	hud_layer.add_child(btn_end_turn)

func _update_hud():
	if not is_instance_valid(lbl_turn): return

	var name = "—"
	if GameManager.players.has(GameManager.active_player_id):
		name = GameManager.players[GameManager.active_player_id].name
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	lbl_turn.text = "Turno: %s%s" % [name, "  (TÚ)" if is_my_turn else ""]
	lbl_turn.modulate = Color(1, 0.9, 0.4) if is_my_turn else Color.WHITE

	var phase_names = {
		GameManager.TurnPhase.START: "Inicio",
		GameManager.TurnPhase.DRAW: "Robo",
		GameManager.TurnPhase.ACTION: "Acción",
		GameManager.TurnPhase.END: "Fin"
	}
	lbl_phase.text = "Fase: %s" % phase_names.get(GameManager.current_phase, "?")
	lbl_actions.text = "Acciones: %d" % GameManager.actions_remaining
	lbl_deck.text = "Mazo: %d  |  Descarte: %d" % [GameManager.deck.size(), GameManager.discard_pile.size()]

	# El botón Fin de Turno solo está activo en mi turno, fase ACCION
	var can_end = is_my_turn and GameManager.current_phase == GameManager.TurnPhase.ACTION and GameManager.is_game_active
	btn_end_turn.disabled = not can_end

	_refresh_hand_interactivity()

func _refresh_hand_interactivity():
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	var in_action = GameManager.current_phase == GameManager.TurnPhase.ACTION
	var has_action = GameManager.actions_remaining > 0
	var can_play = is_my_turn and in_action and has_action and GameManager.is_game_active

	for card in my_hand_container.get_children():
		if card is CardUI:
			card.set_disabled(not can_play)

func _on_turn_changed(_player_id: int):
	_update_hud()

func _on_phase_changed(_phase: int):
	_update_hud()

func _on_actions_changed(_remaining: int):
	_update_hud()

func _on_end_turn_pressed():
	btn_end_turn.disabled = true
	if multiplayer.is_server():
		GameManager.request_end_turn()
	else:
		GameManager.rpc_id(1, "request_end_turn")

func _on_game_won(winner_id: int, winner_name: String):
	_update_hud()
	_show_winner_panel(winner_id, winner_name)

func _show_winner_panel(winner_id: int, winner_name: String):
	if is_instance_valid(winner_panel):
		winner_panel.queue_free()
	winner_panel = PanelContainer.new()
	winner_panel.anchor_left = 0.5
	winner_panel.anchor_right = 0.5
	winner_panel.anchor_top = 0.5
	winner_panel.anchor_bottom = 0.5
	winner_panel.offset_left = -200
	winner_panel.offset_right = 200
	winner_panel.offset_top = -80
	winner_panel.offset_bottom = 80
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	winner_panel.add_child(vbox)
	var lbl = Label.new()
	var is_me = winner_id == multiplayer.get_unique_id()
	lbl.text = "🏆 ¡%s gana!" % winner_name if not is_me else "🏆 ¡VICTORIA!"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	hud_layer.add_child(winner_panel)

# ==============================================================================
# 🏗️ CONFIGURACIÓN DE LA MESA
# ==============================================================================

func setup_table():
	var my_id = multiplayer.get_unique_id()

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
	await get_tree().process_frame
	await get_tree().create_timer(1.0).timeout

	print("Servidor: Inicializando mazos...")
	GameManager.initialize_deck()

	print("Servidor: Iniciando Fase de Selección de Bebés...")
	rpc("client_start_baby_selection", GameManager.nursery_deck)

func _server_deal_initial_hands():
	print("Servidor: Todos tienen bebé. Repartiendo manos iniciales...")

	for p_id in GameManager.players:
		var drawn_cards = GameManager.draw_cards(5)
		GameManager.players[p_id].hand = _ids_to_data(drawn_cards)

		rpc_id(p_id, "client_receive_initial_hand", drawn_cards)

		for other_id in GameManager.players:
			if other_id != p_id:
				rpc_id(other_id, "client_update_rival_hand", p_id, 5)

	print("Servidor: Reparto completado. Iniciando primer turno.")
	GameManager.setup_turn_order()

# ==============================================================================
# 👶 FASE DE SELECCIÓN DE BEBÉS
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_start_baby_selection(available_babies: Array):
	print("Cliente: Abriendo selector de bebés...")
	card_selector.open_selection(available_babies, "¡Elige tu Bebé Inicial!")
	var selected_id = await card_selector.card_selected
	rpc_id(1, "server_receive_baby_choice", selected_id)

@rpc("any_peer", "call_local", "reliable")
func server_receive_baby_choice(card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	print("Servidor: Jugador ", sender_id, " eligió el bebé ID ", card_id)

	if GameManager.players.has(sender_id):
		var card_data = CardDatabase.get_card_data(card_id)
		GameManager.players[sender_id].stable.append(card_data)
		rpc("client_card_entered_stable", sender_id, card_id)

	var all_ready = true
	for p_id in GameManager.players:
		if GameManager.players[p_id].stable.is_empty():
			all_ready = false
			break

	if all_ready:
		_server_deal_initial_hands()

# ==============================================================================
# 🃏 ACCIONES DE JUEGO (JUGAR / DESCARTAR)
# ==============================================================================

# El cliente envía qué carta quiere jugar y, si aplica, en qué establo objetivo
# (target_player_id = -1 si quiere que el servidor decida automáticamente)
@rpc("any_peer", "call_local", "reliable")
func server_play_card(card_id: int, target_player_id: int = -1):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()

	# --- VALIDACIONES ---
	if not GameManager.is_game_active:
		printerr("Servidor: Partida no activa")
		return
	if sender_id != GameManager.active_player_id:
		printerr("Servidor: ", sender_id, " intenta jugar fuera de turno")
		return
	if GameManager.current_phase != GameManager.TurnPhase.ACTION:
		printerr("Servidor: Carta jugada fuera de fase ACTION")
		return
	if GameManager.actions_remaining <= 0:
		printerr("Servidor: Sin acciones restantes")
		return

	var card_data = CardDatabase.get_card_data(card_id)
	if not card_data: return

	# Verificar que el jugador tenga la carta en mano
	var p_data: PlayerData = GameManager.players.get(sender_id)
	if not p_data: return
	var has_card = false
	for c in p_data.hand:
		if c.id == card_id:
			has_card = true
			break
	if not has_card:
		printerr("Servidor: ", sender_id, " intenta jugar carta que no tiene: ", card_id)
		return

	print("Servidor: Jugador ", sender_id, " JUEGA ", card_data.name_es)

	# 1. Quitar de la mano
	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_update_rival_hand", sender_id, new_size)

	# 2. Determinar destino del establo
	var dest_player_id := sender_id
	if card_data.is_downgrade():
		dest_player_id = _resolve_downgrade_target(sender_id, target_player_id)

	# 3. Aplicar
	if card_data.is_permanent():
		if GameManager.players.has(dest_player_id):
			GameManager.players[dest_player_id].stable.append(card_data)
		rpc("client_card_entered_stable", dest_player_id, card_id)

		# Comprobar victoria si entró un unicornio
		if card_data.is_unicorn():
			if GameManager.check_win_condition():
				return # Fin de partida, no consumir más acciones
	else:
		# Magia o Relincho → descarte (los efectos llegarán en Fase 2)
		GameManager.discard_pile.append(card_id)

	# 4. Consumir acción (si llega a 0 GameManager avanza a END automáticamente)
	GameManager.consume_action()

func _resolve_downgrade_target(sender_id: int, requested: int) -> int:
	var opponents = GameManager.get_opponents_of(sender_id)
	if opponents.is_empty():
		return sender_id # Caso degenerado (solo 1 jugador) → cae sobre sí
	if requested != -1 and requested != sender_id and requested in opponents:
		return requested
	# Auto-target: primer oponente disponible
	return opponents[0]

@rpc("any_peer", "call_local", "reliable")
func server_discard_card(card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()

	if sender_id != GameManager.active_player_id:
		printerr("Servidor: ", sender_id, " intenta descartar fuera de turno")
		return
	if GameManager.current_phase != GameManager.TurnPhase.ACTION:
		printerr("Servidor: Descarte fuera de fase ACTION")
		return

	print("Servidor: Jugador ", sender_id, " DESCARTA ", card_id)

	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	GameManager.discard_pile.append(card_id)

	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_update_rival_hand", sender_id, new_size)

# ==============================================================================
# 🎨 EVENTOS VISUALES (CLIENTE)
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_receive_initial_hand(card_ids: Array):
	for id in card_ids:
		add_card_to_hand(id)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_receive_drawn_card(card_id: int):
	add_card_to_hand(card_id)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_update_rival_hand(rival_id: int, new_count: int):
	if rival_stables.has(rival_id):
		rival_stables[rival_id].update_hand_visuals(new_count)
	GameManager.hand_size_changed.emit(rival_id, new_count)

# Forzar descarte visual al fin de turno (límite de mano)
@rpc("authority", "call_local", "reliable")
func client_force_discard(card_id: int):
	for child in my_hand_container.get_children():
		if child is CardUI and child.card_data and child.card_data.id == card_id:
			var tween = create_tween()
			tween.tween_property(child, "modulate:a", 0.0, 0.25)
			tween.tween_callback(child.queue_free)
			break
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_card_entered_stable(player_id: int, card_id: int):
	var my_id = multiplayer.get_unique_id()
	var card_data = CardDatabase.get_card_data(card_id)

	var new_card = CARD_SCENE.instantiate()

	if player_id == my_id:
		if card_data.is_upgrade() or card_data.is_downgrade():
			my_upgrades_row.add_child(new_card)
		else:
			my_unicorns_row.add_child(new_card)

		new_card.custom_minimum_size = Vector2(120, 165)
		new_card.scale = Vector2(0.8, 0.8)
		new_card.set_disabled(true)
	else:
		if rival_stables.has(player_id):
			rival_stables[player_id].add_card_to_stable(new_card)

	new_card.setup_card(card_data)
	GameManager.stable_changed.emit(player_id)
	_update_hud()

# ==============================================================================
# 🛠️ UTILIDADES
# ==============================================================================

func add_card_to_hand(card_id: int):
	var data = CardDatabase.get_card_data(card_id)
	if not data: return

	var new_card = CARD_SCENE.instantiate()
	my_hand_container.add_child(new_card)

	new_card.setup_card(data)
	new_card.name = "Card_%d" % card_id

	new_card.info_requested.connect(_on_card_info_requested)
	new_card.play_requested.connect(_on_card_play_requested)
	new_card.discard_requested.connect(_on_card_discard_requested)

	# Inicialmente bloqueada hasta que sea mi turno+fase ACCION
	new_card.set_disabled(true)
	_refresh_hand_interactivity()

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

# --- SIGNAL HANDLERS LOCALES ---

func _on_card_info_requested(data: CardData):
	info_panel.show_card_info(data)

func _on_card_play_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id

	# Validación local previa al RPC
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	if not is_my_turn or GameManager.current_phase != GameManager.TurnPhase.ACTION:
		print("No puedes jugar fuera de tu turno / fase ACCION")
		return
	if GameManager.actions_remaining <= 0:
		print("Sin acciones restantes")
		return

	rpc_id(1, "server_play_card", card_id, -1)

	# Animación local inmediata (predicción)
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _on_card_discard_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id

	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	if not is_my_turn or GameManager.current_phase != GameManager.TurnPhase.ACTION:
		return

	rpc_id(1, "server_discard_card", card_id)

	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _clear_debug_cards():
	for child in my_hand_container.get_children():
		child.queue_free()

func _spawn_magic_card():
	add_card_to_hand(3)
