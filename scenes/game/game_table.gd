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

# --- Pilas visibles (Mazo / Descarte / Guardería) ---
var pile_deck_btn: Button
var pile_discard_btn: Button
var pile_nursery_btn: Button
var _count_deck: int = 0
var _count_discard: int = 0
var _count_nursery: int = 0

# --- Pickers/Modals dinámicos ---
var modal_layer: CanvasLayer
var active_modal: Control = null

# --- Estado de selección (para enviar al servidor cuando el usuario clickea) ---
var pending_pick_kind: String = "" # "card", "stable", "player", "binary", "cost"
var pending_cost_payload: Dictionary = {}

# --- Estado de ventana Neigh activa (permite jugar Neighs desde la mano) ---
var neigh_window_active: bool = false
var neigh_window_card_id: int = -1
var neigh_window_player_id: int = -1

func _ready():
	if not my_hand_container or not rivals_container or not my_stable_container:
		printerr("ERROR CRÍTICO: Faltan nodos contenedores en GameTable.")
		return

	# Registrarse globalmente para que EffectProcessor pueda llamar RPCs
	GameManager.game_table = self

	_clear_debug_cards()
	_build_hud()
	_build_modal_layer()

	# Subimos la capa del UILayer (CardInfoPanel + CardSelector) por encima de
	# hud_layer (5) y modal_layer (10) para que el panel de info siempre se vea.
	var ui_layer_node = $UILayer
	if ui_layer_node is CanvasLayer:
		ui_layer_node.layer = 20

	# z-index ordering: las cartas de la MANO siempre se dibujan POR ENCIMA
	# de las del establo. Así un hover sobre una carta del campo nunca tapa
	# a las de la mano del jugador.
	$HandZone.z_index = 100
	$MyStable.z_index = 1
	$RivalsContainer.z_index = 1

	# Ocultar los botones de debug ("Obtener Carta Magica" / "Limpiar mesa")
	if has_node("DebugUI"):
		$DebugUI.visible = false

	setup_table()

	if multiplayer.is_server():
		# Limpiar registry de pasivos al iniciar partida
		EffectProcessor.reset()
		_server_start_match_logic()

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

	var top = PanelContainer.new()
	top.anchor_left = 0.5; top.anchor_right = 0.5
	top.offset_left = -260; top.offset_right = 260
	top.offset_top = 10; top.offset_bottom = 70
	hud_layer.add_child(top)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 30)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_child(hbox)

	lbl_turn = Label.new()
	lbl_turn.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_turn)
	lbl_phase = Label.new()
	lbl_phase.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_phase)
	lbl_actions = Label.new()
	lbl_actions.add_theme_font_size_override("font_size", 18)
	hbox.add_child(lbl_actions)

	lbl_deck = Label.new()
	lbl_deck.anchor_left = 1.0; lbl_deck.anchor_right = 1.0
	lbl_deck.offset_left = -360; lbl_deck.offset_right = -10
	lbl_deck.offset_top = 15; lbl_deck.offset_bottom = 45
	lbl_deck.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl_deck.add_theme_font_size_override("font_size", 14)
	hud_layer.add_child(lbl_deck)

	btn_end_turn = Button.new()
	btn_end_turn.text = "Finalizar Turno"
	btn_end_turn.anchor_left = 1.0; btn_end_turn.anchor_right = 1.0
	btn_end_turn.anchor_top = 1.0; btn_end_turn.anchor_bottom = 1.0
	btn_end_turn.offset_left = -180; btn_end_turn.offset_right = -20
	btn_end_turn.offset_top = -70; btn_end_turn.offset_bottom = -20
	btn_end_turn.disabled = true
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	hud_layer.add_child(btn_end_turn)

	_build_piles()
	_update_hud()

# Tres pilas clicables en el lado izquierdo: Mazo, Descarte, Guardería.
func _build_piles():
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.anchor_left = 0.0; col.anchor_right = 0.0
	col.anchor_top = 0.5; col.anchor_bottom = 0.5
	col.offset_left = 12; col.offset_right = 132
	col.offset_top = -90; col.offset_bottom = 90
	hud_layer.add_child(col)

	pile_deck_btn = Button.new()
	pile_deck_btn.custom_minimum_size = Vector2(120, 54)
	pile_deck_btn.disabled = true # el mazo de robo es secreto
	col.add_child(pile_deck_btn)

	pile_discard_btn = Button.new()
	pile_discard_btn.custom_minimum_size = Vector2(120, 54)
	pile_discard_btn.pressed.connect(func(): _request_pile_view("discard"))
	col.add_child(pile_discard_btn)

	pile_nursery_btn = Button.new()
	pile_nursery_btn.custom_minimum_size = Vector2(120, 54)
	pile_nursery_btn.pressed.connect(func(): _request_pile_view("nursery"))
	col.add_child(pile_nursery_btn)

	_refresh_pile_labels()

func _refresh_pile_labels():
	if is_instance_valid(pile_deck_btn):
		pile_deck_btn.text = "🂠 Mazo\n%d" % _count_deck
	if is_instance_valid(pile_discard_btn):
		pile_discard_btn.text = "🗑 Descarte\n%d" % _count_discard
	if is_instance_valid(pile_nursery_btn):
		pile_nursery_btn.text = "👶 Guardería\n%d" % _count_nursery

# Abre el visor de pila SOLO para quien lo pidió.
func _request_pile_view(which: String):
	if multiplayer.is_server():
		# El host tiene los datos localmente → abrir directo (sin RPC, sin broadcast)
		var ids: Array = []
		if which == "discard": ids = GameManager.discard_pile.duplicate()
		elif which == "nursery": ids = GameManager.nursery_deck.duplicate()
		client_open_pile_view(which, ids)
	else:
		# El cliente pide los datos al servidor; este responde SOLO a él
		rpc_id(1, "server_request_pile", which)

func _build_modal_layer():
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 10
	add_child(modal_layer)

func _update_hud():
	if not is_instance_valid(lbl_turn): return
	var player_name = "—"
	if GameManager.players.has(GameManager.active_player_id):
		player_name = GameManager.players[GameManager.active_player_id].name
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	var suffix = "  (TÚ)" if is_my_turn else ""
	lbl_turn.text = "Turno: %s%s" % [player_name, suffix]
	lbl_turn.modulate = Color(1, 0.9, 0.4) if is_my_turn else Color.WHITE

	var phase_names = {
		GameManager.TurnPhase.START: "Inicio",
		GameManager.TurnPhase.DRAW: "Robo",
		GameManager.TurnPhase.ACTION: "Acción",
		GameManager.TurnPhase.END: "Fin"
	}
	lbl_phase.text = "Fase: %s" % phase_names.get(GameManager.current_phase, "?")
	lbl_actions.text = "Acciones: %d" % GameManager.actions_remaining
	lbl_deck.text = "Meta: %d 🦄  |  Mazo: %d  |  Descarte: %d" % [
		GameManager.current_rules.unicorns_to_win, GameManager.deck.size(), GameManager.discard_pile.size()]

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
			# Caso especial: ventana Neigh abierta → los Instants quedan habilitados
			# aunque no sea mi turno, así puedo clickearlos desde la mano.
			if neigh_window_active and card.card_data and card.card_data.is_instant():
				card.set_disabled(false)
				card.modulate = Color(1.2, 1.1, 0.4) # tinte amarillo "puedes Neighear"
			else:
				card.set_disabled(not can_play)

func _on_turn_changed(_player_id: int): _update_hud()
func _on_phase_changed(_phase: int): _update_hud()
func _on_actions_changed(_remaining: int): _update_hud()

func _on_end_turn_pressed():
	btn_end_turn.disabled = true
	if multiplayer.is_server():
		GameManager.request_end_turn()
	else:
		GameManager.rpc_id(1, "request_end_turn")

var _vote_tally_label: Label

func _on_game_won(winner_id: int, winner_name: String):
	_update_hud()
	_show_endgame_panel(winner_id, winner_name)

func _show_endgame_panel(winner_id: int, winner_name: String):
	if is_instance_valid(winner_panel): winner_panel.queue_free()
	winner_panel = PanelContainer.new()
	winner_panel.anchor_left = 0.5; winner_panel.anchor_right = 0.5
	winner_panel.anchor_top = 0.5; winner_panel.anchor_bottom = 0.5
	winner_panel.offset_left = -240; winner_panel.offset_right = 240
	winner_panel.offset_top = -130; winner_panel.offset_bottom = 130
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	winner_panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var lbl = Label.new()
	var is_me = winner_id == multiplayer.get_unique_id()
	lbl.text = "🏆 ¡VICTORIA!" if is_me else "🏆 ¡%s gana!" % winner_name
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	var prompt = Label.new()
	prompt.text = "¿Qué hacemos? (votación)"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(prompt)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	vbox.add_child(hb)
	var btn_rematch = Button.new()
	btn_rematch.text = "🔄 Revancha"
	btn_rematch.custom_minimum_size = Vector2(160, 50)
	btn_rematch.pressed.connect(func(): _cast_endgame_vote("rematch", btn_rematch, hb))
	hb.add_child(btn_rematch)
	var btn_lobby = Button.new()
	btn_lobby.text = "🚪 Ir al Lobby"
	btn_lobby.custom_minimum_size = Vector2(160, 50)
	btn_lobby.pressed.connect(func(): _cast_endgame_vote("lobby", btn_lobby, hb))
	hb.add_child(btn_lobby)

	_vote_tally_label = Label.new()
	_vote_tally_label.text = "Votos: 0/%d" % GameManager.players.size()
	_vote_tally_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_vote_tally_label)

	hud_layer.add_child(winner_panel)

func _cast_endgame_vote(choice: String, _btn: Button, buttons_box: HBoxContainer):
	# Bloquear ambos botones tras votar
	for b in buttons_box.get_children():
		if b is Button: b.disabled = true
	if multiplayer.is_server():
		_server_record_vote(multiplayer.get_unique_id(), choice)
	else:
		rpc_id(1, "server_cast_vote", choice)

@rpc("any_peer", "reliable")
func server_cast_vote(choice: String):
	if not multiplayer.is_server(): return
	_server_record_vote(multiplayer.get_remote_sender_id(), choice)

var _endgame_votes: Dictionary = {}

func _server_record_vote(voter_id: int, choice: String):
	if voter_id == 0: voter_id = 1 # host por llamada local
	_endgame_votes[voter_id] = choice
	rpc("client_update_vote_tally", _endgame_votes.size(), GameManager.players.size())
	if _endgame_votes.size() >= GameManager.players.size():
		var all_rematch = true
		for v in _endgame_votes.values():
			if v != "rematch": all_rematch = false
		_endgame_votes.clear()
		if all_rematch:
			_server_restart_match()
		else:
			rpc("client_go_to_lobby")

@rpc("authority", "call_local", "reliable")
func client_update_vote_tally(count: int, total: int):
	if is_instance_valid(_vote_tally_label):
		_vote_tally_label.text = "Votos: %d/%d" % [count, total]

func _server_restart_match():
	GameManager.reset_for_new_match()
	GameManager.rpc("load_game_scene") # recarga GameTable y re-inicia la partida

@rpc("authority", "call_local", "reliable")
func client_go_to_lobby():
	# Desconectar limpio para que el Lobby muestre la pantalla de login
	# (nombre, IP, unirse) como al principio.
	GameManager.is_game_active = false
	GameManager.players.clear()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/game/Lobby.tscn")

# ==============================================================================
# 🏗️ CONFIGURACIÓN DE LA MESA
# ==============================================================================

func setup_table():
	var my_id = multiplayer.get_unique_id()
	for p_id in GameManager.players:
		if p_id == my_id:
			print("Configurando mi zona: ", GameManager.players[p_id].name)
		else:
			_create_rival_zone(p_id, GameManager.players[p_id])

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
	# Limpiar manos/establos (importante para revanchas)
	for pid in GameManager.players:
		GameManager.players[pid].hand.clear()
		GameManager.players[pid].stable.clear()
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
				rpc_id(other_id, "client_sync_hand_size", p_id, 5)
	# Sync inicial de contadores de pilas
	rpc("client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())
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
	if GameManager.players.has(sender_id):
		var card_data = CardDatabase.get_card_data(card_id)
		GameManager.players[sender_id].stable.append(card_data)
		EffectProcessor.passives.on_card_entered_stable(sender_id, card_data)
		rpc("client_card_entered_stable_visual", sender_id, card_id)
	var all_ready = true
	for p_id in GameManager.players:
		if GameManager.players[p_id].stable.is_empty():
			all_ready = false; break
	if all_ready:
		_server_deal_initial_hands()

# ==============================================================================
# 🃏 ACCIONES DE JUEGO (JUGAR / DESCARTAR)
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func server_play_card(card_id: int, target_player_id: int = -1):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()

	if not GameManager.is_game_active: return
	if sender_id != GameManager.active_player_id:
		printerr("Servidor: fuera de turno"); return
	if GameManager.current_phase != GameManager.TurnPhase.ACTION:
		printerr("Servidor: fuera de fase ACTION"); return
	if GameManager.actions_remaining <= 0:
		printerr("Servidor: sin acciones"); return
	# Lock: si hay un efecto resolviéndose, ignorar (evita doble-jugada / desync)
	if GameManager.is_resolving:
		printerr("Servidor: efecto en curso, jugada ignorada")
		rpc_id(sender_id, "client_reject_play", card_id, "Espera a que termine el efecto actual")
		return

	var card_data = CardDatabase.get_card_data(card_id)
	if not card_data: return

	# Validar posesión
	var p_data: PlayerData = GameManager.players.get(sender_id)
	if not p_data: return
	var has_card = false
	for c in p_data.hand:
		if c.id == card_id:
			has_card = true; break
	if not has_card:
		printerr("Servidor: ", sender_id, " no tiene la carta ", card_id); return

	# Pasivas que bloquean jugar este tipo de carta
	if card_data.is_upgrade() and not EffectProcessor.passives.can_play_upgrade(sender_id):
		print("Servidor: bloqueado por PREVENT_PLAY_UPGRADE"); return
	if card_data.is_instant() and not EffectProcessor.passives.can_play_instant(sender_id):
		print("Servidor: bloqueado por PREVENT_PLAY_NEIGH"); return
	# Queen Bee (2ª ed.): si OTRO jugador tiene la Reina, NADIE más puede meter
	# básicos en su establo. Rechazamos la jugada y devolvemos la carta a la mano.
	if card_data.is_basic_unicorn():
		if EffectProcessor.passives.basic_unicorns_blocked_against(sender_id, GameManager.players.keys()):
			print("Servidor: bloqueado por Reina del Baile (Queen Bee)")
			rpc_id(sender_id, "client_reject_play", card_id, "El Unicornio Reina bloquea los básicos")
			return

	print("Servidor: ", sender_id, " JUEGA ", card_data.name_es)

	# Activar lock de resolución
	GameManager.is_resolving = true

	# Quitar de la mano
	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_sync_hand_size", sender_id, new_size)

	# Ventana NEIGH (los Instants no son cancelables — son ellos los que cancelan)
	if not card_data.is_instant():
		var cancelled = await NeighManager.open_window(card_id, sender_id)
		if cancelled:
			print("Servidor: carta ", card_data.name_es, " fue NEIGH'd")
			GameManager.discard_pile.append(card_id)
			rpc("client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())
			GameManager.is_resolving = false
			GameManager.consume_action()
			return

	# Determinar destino para Downgrades
	var dest_player_id: int = sender_id
	if card_data.is_downgrade():
		dest_player_id = _resolve_downgrade_target(sender_id, target_player_id)

	# Resolver efectos
	if card_data.is_permanent():
		# Entra al establo
		if GameManager.players.has(dest_player_id):
			GameManager.players[dest_player_id].stable.append(card_data)
		rpc("client_card_entered_stable_visual", dest_player_id, card_id)
		# on_enter_stable triggers + registro de pasivos
		await EffectProcessor.resolve_on_enter_stable(card_data, dest_player_id)
	else:
		# Magic Spell o Instant: efectos on_play, después al descarte
		await EffectProcessor.resolve_on_play(card_data, sender_id)
		GameManager.discard_pile.append(card_id)

	# Liberar lock antes de chequear victoria/consumir acción
	GameManager.is_resolving = false
	rpc("client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())

	# VICTORIA: comprobar SIEMPRE tras resolver (un efecto pudo robar/revivir un unicornio)
	if GameManager.check_win_condition():
		return

	GameManager.consume_action()

func _resolve_downgrade_target(sender_id: int, requested: int) -> int:
	var opponents = GameManager.get_opponents_of(sender_id)
	if opponents.is_empty(): return sender_id
	if requested != -1 and requested != sender_id and requested in opponents:
		return requested
	return opponents[0]

@rpc("any_peer", "call_local", "reliable")
func server_discard_card(card_id: int):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id != GameManager.active_player_id: return
	if GameManager.current_phase != GameManager.TurnPhase.ACTION: return
	if GameManager.is_resolving: return
	var new_size = _server_remove_card_from_hand(sender_id, card_id)
	GameManager.discard_pile.append(card_id)
	rpc("client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())
	for p in GameManager.players:
		if p != sender_id:
			rpc_id(p, "client_sync_hand_size", sender_id, new_size)

# ==============================================================================
# 🎨 RPCs visuales (cliente)
# ==============================================================================

# Mensaje breve que el servidor puede enviar a un jugador concreto.
@rpc("authority", "call_local", "reliable")
func client_toast(msg: String):
	_show_toast(msg)

@rpc("authority", "call_local", "reliable")
func client_receive_initial_hand(card_ids: Array):
	for id in card_ids:
		add_card_to_hand(id)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_receive_drawn_batch(card_ids: Array):
	for id in card_ids:
		add_card_to_hand(id)
	_update_hud()

# El servidor rechazó la jugada: devolvemos la carta a la mano (deshacer predicción).
@rpc("authority", "call_local", "reliable")
func client_reject_play(card_id: int, reason: String):
	add_card_to_hand(card_id)
	_show_toast("⚠ " + reason)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_replace_hand(card_ids: Array):
	for c in my_hand_container.get_children(): c.queue_free()
	for id in card_ids: add_card_to_hand(id)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_sync_hand_size(player_id: int, new_size: int):
	if rival_stables.has(player_id):
		rival_stables[player_id].update_hand_visuals(new_size)
	GameManager.hand_size_changed.emit(player_id, new_size)

# Cámara Espía: el servidor revela la mano de player_id a los demás.
@rpc("authority", "call_local", "reliable")
func client_reveal_rival_hand(player_id: int, card_ids: Array):
	if rival_stables.has(player_id):
		rival_stables[player_id].reveal_hand(card_ids)

# Servidor: difunde las manos de quienes tengan HAND_VISIBLE (Cámara Espía).
func server_refresh_visible_hands():
	if not multiplayer.is_server(): return
	var revealed = EffectProcessor.passives.players_with(GameEnums.Condition.HAND_VISIBLE)
	for vp_id in revealed:
		var p = GameManager.players.get(vp_id)
		if not p: continue
		var ids: Array = []
		for c in p.hand: ids.append(c.id)
		# Enviar a TODOS menos al dueño (él ya ve su mano)
		for pid in GameManager.players:
			if pid != vp_id:
				rpc_id(pid, "client_reveal_rival_hand", vp_id, ids)

@rpc("authority", "call_local", "reliable")
func client_card_left_hand(player_id: int, card_id: int):
	if player_id == multiplayer.get_unique_id():
		for child in my_hand_container.get_children():
			if child is CardUI and child.card_data and child.card_data.id == card_id:
				var tween = create_tween()
				tween.tween_property(child, "modulate:a", 0.0, 0.2)
				tween.tween_callback(child.queue_free)
				break
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_force_discard(card_id: int):
	client_card_left_hand(multiplayer.get_unique_id(), card_id)

@rpc("authority", "call_local", "reliable")
func client_card_entered_stable_visual(player_id: int, card_id: int):
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
	else:
		if rival_stables.has(player_id):
			rival_stables[player_id].add_card_to_stable(new_card)
	new_card.setup_card(card_data)
	new_card.name = "Stable_%d_%d" % [player_id, card_id]
	# Las cartas del establo nunca se juegan/descartan, pero SÍ se pueden inspeccionar:
	new_card.info_requested.connect(_on_card_info_requested)
	new_card.set_disabled(true)
	# Animación "pop": entra escalando desde pequeño
	_animate_pop_in(new_card)
	GameManager.stable_changed.emit(player_id)
	_update_hud()

# Animación de entrada: fade-in suave.
# NO tocamos 'scale' porque las cartas viven dentro de contenedores (HBox) que
# controlan el layout, y animar scale ahí dejaba la carta "a medias".
func _animate_pop_in(card: Control):
	card.modulate.a = 0.0
	var tw = card.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(card, "modulate:a", 1.0, 0.25)

@rpc("authority", "call_local", "reliable")
func client_card_left_stable(player_id: int, card_id: int):
	var target_name = "Stable_%d_%d" % [player_id, card_id]
	# Buscar en mi establo
	for row in [my_upgrades_row, my_unicorns_row]:
		for child in row.get_children():
			if child.name == target_name:
				var tween = create_tween()
				tween.tween_property(child, "modulate:a", 0.0, 0.2)
				tween.tween_callback(child.queue_free)
				return
	# Buscar en rivales
	if rival_stables.has(player_id):
		var zone = rival_stables[player_id]
		if zone.has_method("remove_card_from_stable"):
			zone.remove_card_from_stable(card_id)

@rpc("authority", "call_local", "reliable")
func client_sync_deck_counters(deck_size: int, discard_size: int, nursery_size: int = 0):
	var discard_changed = discard_size != _count_discard
	var nursery_changed = nursery_size != _count_nursery
	_count_deck = deck_size
	_count_discard = discard_size
	_count_nursery = nursery_size
	if is_instance_valid(lbl_deck):
		lbl_deck.text = "Mazo: %d  |  Descarte: %d" % [deck_size, discard_size]
	_refresh_pile_labels()
	# Pulso visual al cambiar
	if discard_changed and is_instance_valid(pile_discard_btn):
		_pulse(pile_discard_btn)
	if nursery_changed and is_instance_valid(pile_nursery_btn):
		_pulse(pile_nursery_btn)

func _pulse(node: Control):
	# Flash de color (no scale, para no romper el layout del contenedor)
	node.modulate = Color(1.5, 1.4, 0.6)
	var tw = node.create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_property(node, "modulate", Color.WHITE, 0.35)

# --- Visor de pilas (Descarte / Guardería) ---

@rpc("any_peer", "reliable")
func server_request_pile(which: String):
	if not multiplayer.is_server(): return
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0: return # llamada local del host se maneja aparte
	var ids: Array = []
	if which == "discard":
		ids = GameManager.discard_pile.duplicate()
	elif which == "nursery":
		ids = GameManager.nursery_deck.duplicate()
	rpc_id(sender_id, "client_open_pile_view", which, ids)

# Sin call_local: solo se ejecuta en el cliente destino del rpc_id (o por llamada directa del host).
@rpc("authority", "reliable")
func client_open_pile_view(which: String, ids: Array):
	var title = "Pila de Descarte" if which == "discard" else "Guardería (Bebés)"
	if ids.is_empty():
		_show_toast("La pila está vacía")
		return
	_close_modal()
	var panel = _make_modal_panel("%s — %d carta(s)" % [title, ids.size()])
	active_modal = panel
	modal_layer.add_child(panel)
	var hbox = _make_scrollable_hbox(_modal_vbox(panel))
	for cid in ids:
		var data = CardDatabase.get_card_data(cid)
		if not data: continue
		var card_ui = CARD_SCENE.instantiate()
		hbox.add_child(card_ui)
		card_ui.setup_card(data)
		card_ui.custom_minimum_size = Vector2(120, 165)
		card_ui.set_disabled(true) # solo visualización
		card_ui.info_requested.connect(_on_card_info_requested)
	var btn_close = Button.new()
	btn_close.text = "Cerrar"
	btn_close.pressed.connect(_close_modal)
	_modal_vbox(panel).add_child(btn_close)

# ==============================================================================
# 🎯 PICKERS / MODALES (cliente)
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_open_card_pick(card_ids: Array, prompt: String, allow_cancel: bool):
	pending_pick_kind = "card"
	_show_card_picker(card_ids, prompt, allow_cancel, "_send_card_pick")

@rpc("authority", "call_local", "reliable")
func client_open_stable_target_pick(candidates: Array, prompt: String):
	pending_pick_kind = "stable"
	# candidates es Array de Dictionary {"owner_id":..., "card_id":...}
	# Mostramos en grid mostrando el dueño en cada carta
	_show_stable_picker(candidates, prompt)

@rpc("authority", "call_local", "reliable")
func client_open_player_pick(candidates: Array, prompt: String):
	pending_pick_kind = "player"
	_show_player_picker(candidates, prompt)

@rpc("authority", "call_local", "reliable")
func client_open_binary_choice(labels: Array):
	pending_pick_kind = "binary"
	_show_binary_choice(labels)

@rpc("authority", "call_local", "reliable")
func client_open_cost_pay(action: int, amount: int, filter: int, msg: String, optional: bool):
	pending_pick_kind = "cost"
	pending_cost_payload = {"action": action, "amount": amount, "filter": filter, "picked": []}
	_show_cost_picker(action, amount, filter, msg, optional)

# --- Construcción de los modales ---

func _close_modal():
	if is_instance_valid(active_modal):
		active_modal.queue_free()
	active_modal = null

func _show_card_picker(card_ids: Array, prompt: String, allow_cancel: bool, callback_name: String):
	_close_modal()
	var panel = _make_modal_panel(prompt)
	active_modal = panel
	modal_layer.add_child(panel)
	var hbox = _make_scrollable_hbox(_modal_vbox(panel))
	for cid in card_ids:
		var data = CardDatabase.get_card_data(cid)
		if not data: continue
		var card_ui = CARD_SCENE.instantiate()
		hbox.add_child(card_ui)
		card_ui.setup_card(data)
		card_ui.custom_minimum_size = Vector2(140, 195)
		card_ui.play_button.text = "ELEGIR"
		card_ui.discard_button.hide()
		card_ui.play_requested.connect(func(_c):
			call(callback_name, cid)
		)
		card_ui.info_requested.connect(_on_card_info_requested)
	if allow_cancel:
		var btn_cancel = Button.new()
		btn_cancel.text = "Cancelar"
		btn_cancel.pressed.connect(func(): _send_card_pick(-1))
		_modal_vbox(panel).add_child(btn_cancel)

func _show_stable_picker(candidates: Array, prompt: String):
	_close_modal()
	var panel = _make_modal_panel(prompt)
	active_modal = panel
	modal_layer.add_child(panel)
	var hbox = _make_scrollable_hbox(_modal_vbox(panel))
	for cand in candidates:
		var owner_id = cand["owner_id"]
		var cid = cand["card_id"]
		var data = CardDatabase.get_card_data(cid)
		if not data: continue
		var vb = VBoxContainer.new()
		hbox.add_child(vb)
		var owner_lbl = Label.new()
		var owner_name = GameManager.players[owner_id].name if GameManager.players.has(owner_id) else "?"
		owner_lbl.text = "→ %s" % owner_name
		vb.add_child(owner_lbl)
		var card_ui = CARD_SCENE.instantiate()
		vb.add_child(card_ui)
		card_ui.setup_card(data)
		card_ui.custom_minimum_size = Vector2(130, 180)
		card_ui.play_button.text = "ELEGIR"
		card_ui.discard_button.hide()
		card_ui.play_requested.connect(func(_c):
			_send_stable_pick(cid, owner_id)
		)
		card_ui.info_requested.connect(_on_card_info_requested)
	var btn_cancel = Button.new()
	btn_cancel.text = "Cancelar"
	btn_cancel.pressed.connect(func(): _send_stable_pick(-1, -1))
	_modal_vbox(panel).add_child(btn_cancel)

func _show_player_picker(player_ids: Array, prompt: String):
	_close_modal()
	var panel = _make_modal_panel(prompt)
	active_modal = panel
	modal_layer.add_child(panel)
	var vbox_buttons = VBoxContainer.new()
	_modal_vbox(panel).add_child(vbox_buttons)
	for pid in player_ids:
		var btn = Button.new()
		var pname = GameManager.players[pid].name if GameManager.players.has(pid) else "?"
		btn.text = pname
		btn.pressed.connect(func(): _send_player_pick(pid))
		vbox_buttons.add_child(btn)

func _show_binary_choice(labels: Array):
	_close_modal()
	var panel = _make_modal_panel("Elige una opción")
	active_modal = panel
	modal_layer.add_child(panel)
	var hb = HBoxContainer.new()
	_modal_vbox(panel).add_child(hb)
	for i in labels.size():
		var btn = Button.new()
		btn.text = labels[i]
		var idx = i
		btn.pressed.connect(func(): _send_binary_pick(idx))
		hb.add_child(btn)

func _show_cost_picker(action: int, amount: int, filter: int, msg: String, optional: bool):
	_close_modal()
	var panel = _make_modal_panel(msg)
	active_modal = panel
	modal_layer.add_child(panel)
	# Listar opciones válidas según action + filter
	var candidates: Array = []
	var my_id = multiplayer.get_unique_id()
	var p = GameManager.players.get(my_id)
	var action_enum := action as GameEnums.Action
	var filter_enum := filter as GameEnums.Filter
	if p:
		if action_enum == GameEnums.Action.DISCARD:
			for c in p.hand:
				if c.matches_filter(filter_enum): candidates.append(c.id)
		elif action_enum == GameEnums.Action.SACRIFICE:
			for c in p.stable:
				if c.matches_filter(filter_enum): candidates.append(c.id)
	pending_cost_payload["candidates"] = candidates
	pending_cost_payload["needed"] = amount
	pending_cost_payload["picked"] = []

	# CASO BORDE: no hay cartas válidas para pagar el coste.
	# Si es opcional, declinar. Si es obligatorio pero imposible, también declinar
	# (no se puede forzar lo imposible) para evitar soft-lock.
	if candidates.is_empty():
		_close_modal()
		if multiplayer.is_server():
			EffectProcessor.cost_paid.emit(false, [])
		else:
			EffectProcessor.rpc_id(1, "server_cost_response", false, [])
		return

	var info_lbl = Label.new()
	info_lbl.name = "InfoLbl"
	info_lbl.text = "Selecciona %d/%d carta(s). Click en una carta para marcarla." % [0, amount]
	_modal_vbox(panel).add_child(info_lbl)

	var hbox = _make_scrollable_hbox(_modal_vbox(panel))
	for cid in candidates:
		var data = CardDatabase.get_card_data(cid)
		if not data: continue
		var card_ui = CARD_SCENE.instantiate()
		hbox.add_child(card_ui)
		card_ui.setup_card(data)
		card_ui.custom_minimum_size = Vector2(120, 165)
		card_ui.play_button.text = "Marcar"
		card_ui.discard_button.hide()
		card_ui.play_requested.connect(func(c_ui):
			_toggle_cost_card(cid, c_ui)
		)
		card_ui.info_requested.connect(_on_card_info_requested)

	var hbtn = HBoxContainer.new()
	_modal_vbox(panel).add_child(hbtn)
	var btn_pay = Button.new()
	btn_pay.name = "PayBtn"
	btn_pay.text = "Pagar (0/%d)" % amount
	btn_pay.disabled = true # se habilita al marcar suficientes
	btn_pay.pressed.connect(_confirm_cost_pay)
	hbtn.add_child(btn_pay)
	if optional:
		var btn_skip = Button.new()
		btn_skip.text = "No pagar"
		btn_skip.pressed.connect(_skip_cost_pay)
		hbtn.add_child(btn_skip)
	# Guardamos referencias para actualizar el estado al marcar
	pending_cost_payload["info_lbl"] = info_lbl
	pending_cost_payload["pay_btn"] = btn_pay

func _toggle_cost_card(card_id: int, card_ui: CardUI):
	var picked: Array = pending_cost_payload.get("picked", [])
	var needed: int = pending_cost_payload["needed"]
	if card_id in picked:
		picked.erase(card_id)
		card_ui.modulate = Color.WHITE
	else:
		if picked.size() >= needed:
			return # ya lleno
		picked.append(card_id)
		card_ui.modulate = Color(0.4, 1, 0.4)
	pending_cost_payload["picked"] = picked

	# Actualizar label y botón
	var info_lbl = pending_cost_payload.get("info_lbl")
	var pay_btn = pending_cost_payload.get("pay_btn")
	if is_instance_valid(info_lbl):
		info_lbl.text = "Selecciona %d/%d carta(s). Click en una carta para marcarla." % [picked.size(), needed]
	if is_instance_valid(pay_btn):
		pay_btn.text = "Pagar (%d/%d)" % [picked.size(), needed]
		pay_btn.disabled = picked.size() < needed

func _confirm_cost_pay():
	var picked = pending_cost_payload.get("picked", [])
	if picked.size() < pending_cost_payload["needed"]:
		return # no completó
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.cost_paid.emit(true, picked)
	else:
		EffectProcessor.rpc_id(1, "server_cost_response", true, picked)

func _skip_cost_pay():
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.cost_paid.emit(false, [])
	else:
		EffectProcessor.rpc_id(1, "server_cost_response", false, [])

func _make_modal_panel(title: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -400; panel.offset_right = 400
	panel.offset_top = -250; panel.offset_bottom = 250
	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)
	var lbl = Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	# Guardamos la referencia del vbox como metadata para que los callers lo accedan
	panel.set_meta("vbox", vbox)
	return panel

func _modal_vbox(panel: PanelContainer) -> VBoxContainer:
	return panel.get_meta("vbox") as VBoxContainer

# Crea un ScrollContainer con scroll horizontal y un HBox dentro.
# Devuelve el HBox para que el caller añada cartas.
# El usuario puede arrastrar (mouse o dedo) horizontalmente.
func _make_scrollable_hbox(parent: Container) -> HBoxContainer:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 240) # altura suficiente para una carta
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(scroll)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	scroll.add_child(hbox)
	return hbox

# --- Envío de respuesta de picker al servidor ---

func _send_card_pick(card_id: int):
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.target_picked.emit(card_id, -1)
	else:
		EffectProcessor.rpc_id(1, "server_pick_response", card_id, -1)

func _send_stable_pick(card_id: int, owner_id: int):
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.target_picked.emit(card_id, owner_id)
	else:
		EffectProcessor.rpc_id(1, "server_pick_response", card_id, owner_id)

func _send_player_pick(player_id: int):
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.target_picked.emit(player_id, -1)
	else:
		EffectProcessor.rpc_id(1, "server_pick_response", player_id, -1)

func _send_binary_pick(idx: int):
	_close_modal()
	if multiplayer.is_server():
		EffectProcessor.target_picked.emit(idx, -1)
	else:
		EffectProcessor.rpc_id(1, "server_pick_response", idx, -1)

# ==============================================================================
# ⚡ VENTANA NEIGH (cliente)
# ==============================================================================

var neigh_window_panel: Control = null

@rpc("authority", "call_local", "reliable")
func client_open_neigh_window(card_id: int, playing_player_id: int, secs: float):
	# Solo abrir UI si tengo Neigh en mano
	var my_id = multiplayer.get_unique_id()
	if my_id == playing_player_id: return
	var p = GameManager.players.get(my_id)
	if not p: return
	var neigh_in_hand: Array = []
	for c in p.hand:
		if c.is_instant(): neigh_in_hand.append(c.id)
	if neigh_in_hand.is_empty(): return

	# Marcar ventana activa para permitir click desde la mano también
	neigh_window_active = true
	neigh_window_card_id = card_id
	neigh_window_player_id = playing_player_id
	_refresh_hand_interactivity() # ilumina los Neighs

	var card_data = CardDatabase.get_card_data(card_id)
	var player_name = GameManager.players[playing_player_id].name
	_show_neigh_panel(card_data.name_es, player_name, neigh_in_hand, secs)

func _show_neigh_panel(card_name: String, player_name: String, neighs: Array, secs: float):
	if is_instance_valid(neigh_window_panel): neigh_window_panel.queue_free()
	neigh_window_panel = PanelContainer.new()
	neigh_window_panel.anchor_left = 0.5; neigh_window_panel.anchor_right = 0.5
	neigh_window_panel.anchor_top = 0.0; neigh_window_panel.anchor_bottom = 0.0
	neigh_window_panel.offset_left = -300; neigh_window_panel.offset_right = 300
	neigh_window_panel.offset_top = 90; neigh_window_panel.offset_bottom = 220
	var vbox = VBoxContainer.new()
	neigh_window_panel.add_child(vbox)
	var lbl = Label.new()
	lbl.text = "🐴 %s está jugando %s\n¿Relinchar? (%.0fs)" % [player_name, card_name, secs]
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hb)
	for nid in neighs:
		var btn = Button.new()
		var data = CardDatabase.get_card_data(nid)
		btn.text = "¡%s!" % data.name_es
		var captured_nid = nid
		btn.pressed.connect(func():
			if multiplayer.is_server():
				NeighManager.server_receive_neigh(multiplayer.get_unique_id(), captured_nid)
			else:
				NeighManager.rpc_id(1, "server_receive_neigh_rpc", captured_nid)
			neigh_window_panel.queue_free()
		)
		hb.add_child(btn)
	var btn_skip = Button.new()
	btn_skip.text = "Pasar"
	btn_skip.pressed.connect(func(): neigh_window_panel.queue_free())
	vbox.add_child(btn_skip)
	modal_layer.add_child(neigh_window_panel)
	# Auto-cerrar tras secs
	var t := get_tree().create_timer(secs)
	t.timeout.connect(func():
		if is_instance_valid(neigh_window_panel):
			neigh_window_panel.queue_free()
	)

@rpc("authority", "call_local", "reliable")
func client_close_neigh_window():
	if is_instance_valid(neigh_window_panel):
		neigh_window_panel.queue_free()
	# Limpiar estado de ventana activa
	neigh_window_active = false
	neigh_window_card_id = -1
	neigh_window_player_id = -1
	_refresh_hand_interactivity() # restaura tinte/disabled normal

@rpc("authority", "call_local", "reliable")
func client_announce_neigh(neigher_id: int, neigh_card_id: int, _original_player_id: int, original_card_id: int):
	var n_name = GameManager.players[neigher_id].name
	var orig_card = CardDatabase.get_card_data(original_card_id)
	var n_card = CardDatabase.get_card_data(neigh_card_id)
	print("⚡ %s usa %s contra %s" % [n_name, n_card.name_es, orig_card.name_es])
	# Pequeño toast visual
	var toast = Label.new()
	toast.text = "⚡ %s: ¡%s!" % [n_name, n_card.name_es]
	toast.add_theme_font_size_override("font_size", 22)
	toast.anchor_left = 0.5; toast.anchor_right = 0.5
	toast.anchor_top = 0.4; toast.anchor_bottom = 0.4
	toast.offset_left = -200; toast.offset_right = 200
	toast.offset_top = 0; toast.offset_bottom = 40
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	modal_layer.add_child(toast)
	var tw = create_tween()
	tw.tween_property(toast, "modulate:a", 0.0, 1.5)
	tw.tween_callback(toast.queue_free)

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
	new_card.set_disabled(true)
	_refresh_hand_interactivity()

func _server_remove_card_from_hand(player_id: int, card_id: int) -> int:
	if not GameManager.players.has(player_id): return -1
	var p_data = GameManager.players[player_id]
	var idx = -1
	for i in range(p_data.hand.size()):
		if p_data.hand[i].id == card_id:
			idx = i; break
	if idx != -1:
		p_data.hand.remove_at(idx)
	return p_data.hand.size()

func _ids_to_data(ids: Array[int]) -> Array[CardData]:
	var list: Array[CardData] = []
	for id in ids:
		var d = CardDatabase.get_card_data(id)
		if d: list.append(d)
	return list

func _on_card_info_requested(data: CardData):
	info_panel.show_card_info(data)

func _on_card_play_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id

	# --- CASO ESPECIAL: ventana Neigh activa + carta Instant ---
	# Permite jugar el Neigh desde la mano como respuesta sin pasar por el modal.
	if neigh_window_active and card_ui.card_data.is_instant():
		if multiplayer.is_server():
			NeighManager.server_receive_neigh(multiplayer.get_unique_id(), card_id)
		else:
			NeighManager.rpc_id(1, "server_receive_neigh_rpc", card_id)
		# Cierra el modal de Neigh si está abierto (visual)
		if is_instance_valid(neigh_window_panel):
			neigh_window_panel.queue_free()
		# Animación de salida
		var tw = create_tween()
		tw.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
		tw.tween_callback(card_ui.queue_free)
		return

	# --- BLOQUEO: no permitir jugar Neighs sin contexto ---
	# Los Relinchos solo se juegan como RESPUESTA a otra carta. Si no hay
	# ventana Neigh activa, mostramos un mensaje y no consumimos la carta.
	if card_ui.card_data.is_instant():
		_show_toast("⚠ Los Relinchos solo se juegan como respuesta")
		return

	# --- FLUJO NORMAL DE TURNO ---
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	if not is_my_turn or GameManager.current_phase != GameManager.TurnPhase.ACTION:
		print("No puedes jugar ahora"); return
	if GameManager.actions_remaining <= 0:
		print("Sin acciones"); return
	rpc_id(1, "server_play_card", card_id, -1)
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _show_toast(text: String, duration: float = 2.0):
	var toast = Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 18)
	toast.anchor_left = 0.5; toast.anchor_right = 0.5
	toast.anchor_top = 0.5; toast.anchor_bottom = 0.5
	toast.offset_left = -250; toast.offset_right = 250
	toast.offset_top = -20; toast.offset_bottom = 20
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.modulate = Color(1, 0.8, 0.3)
	modal_layer.add_child(toast)
	var tw = create_tween()
	tw.tween_interval(duration * 0.6)
	tw.tween_property(toast, "modulate:a", 0.0, duration * 0.4)
	tw.tween_callback(toast.queue_free)

func _on_card_discard_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	if not is_my_turn or GameManager.current_phase != GameManager.TurnPhase.ACTION: return
	rpc_id(1, "server_discard_card", card_id)
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2)
	tween.tween_callback(card_ui.queue_free)

func _clear_debug_cards():
	for child in my_hand_container.get_children():
		child.queue_free()
