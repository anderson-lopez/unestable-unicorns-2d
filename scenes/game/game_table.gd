extends Control

# --- CONSTANTES ---
const RIVAL_ZONE_SCENE = preload("res://scenes/game/RivalZone.tscn")
const CARD_SCENE = preload("res://scenes/cards/CardUI.tscn")
const CARD_BACK_TEX = preload("res://assets/textures/cards/reverso/1_reverso.jpg")

# Efectos de sonido (cargados perezosamente en _build_sfx).
const SFX_FILES := {
	"click": "res://assets/audio/click.wav",
	"draw": "res://assets/audio/draw.wav",
	"play": "res://assets/audio/play.wav",
	"neigh": "res://assets/audio/neigh.wav",
	"destroy": "res://assets/audio/destroy.wav",
	"turn": "res://assets/audio/turn.wav",
	"win": "res://assets/audio/win.wav",
	"shuffle": "res://assets/audio/shuffle.wav",
}

# --- REFERENCIAS DE UI ---
@onready var my_hand_container: HBoxContainer = $HandZone/CardsContainer
@onready var my_stable_container: VBoxContainer = $MyStable
@onready var my_upgrades_row: HBoxContainer = $MyStable/UpgradesRow
@onready var my_unicorns_row: HBoxContainer = $MyStable/UnicornsRow

@onready var rivals_container: Control = $RivalsContainer
@onready var info_panel: CardInfoPanel = $UILayer/CardInfoPanel
@onready var card_selector: PanelContainer = $UILayer/CardSelector

# Capa libre donde se posicionan los rivales alrededor de la mesa
var rival_layer: Control

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

# --- Registro de jugadas (log lateral, desplegable) ---
var log_panel: PanelContainer
var log_scroll: ScrollContainer
var log_container: VBoxContainer
var log_collapsed: bool = false
var _log_toggle_btn: Button

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

# --- Capa de animaciones (cartas voladoras) ---
var anim_layer: CanvasLayer

# --- Sonidos (nombre -> AudioStreamPlayer) ---
var _sfx: Dictionary = {}

# --- Estado de selección (para enviar al servidor cuando el usuario clickea) ---
var pending_pick_kind: String = "" # "card", "stable", "player", "binary", "cost"
var pending_cost_payload: Dictionary = {}

# --- Descarte por límite de mano (elección múltiple) ---
var _discard_limit_picked: Array = []

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
	_build_anim_layer()
	_build_sfx()

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
	# El HBox original ya no se usa para posicionar (lo dejamos oculto).
	$RivalsContainer.visible = false

	# Separación clara entre la fila de Ventajas/Desventajas (arriba) y la de
	# Unicornios (abajo) para que no se encimen y se vean limpias.
	$MyStable.add_theme_constant_override("separation", 18)
	$MyStable/UpgradesRow.add_theme_constant_override("separation", 8)
	$MyStable/UnicornsRow.add_theme_constant_override("separation", 8)

	# Capa libre para posicionar a los rivales ALREDEDOR de la mesa
	# (arriba / izquierda / derecha). No usa auto-layout.
	rival_layer = Control.new()
	rival_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	rival_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rival_layer.z_index = 1
	add_child(rival_layer)

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

	# Panel de info en la ESQUINA SUPERIOR IZQUIERDA (turno / fase / acciones / meta).
	var info_box := PanelContainer.new()
	info_box.anchor_left = 0.0; info_box.anchor_right = 0.0
	info_box.anchor_top = 0.0; info_box.anchor_bottom = 0.0
	info_box.offset_left = 12; info_box.offset_top = 10
	info_box.offset_right = 252; info_box.offset_bottom = 136
	var info_sb := StyleBoxFlat.new()
	info_sb.bg_color = Color(0, 0, 0, 0.5)
	info_sb.set_corner_radius_all(6)
	info_sb.set_content_margin_all(10)
	info_box.add_theme_stylebox_override("panel", info_sb)
	hud_layer.add_child(info_box)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	info_box.add_child(vb)

	lbl_turn = Label.new()
	lbl_turn.add_theme_font_size_override("font_size", 18)
	vb.add_child(lbl_turn)
	lbl_phase = Label.new()
	lbl_phase.add_theme_font_size_override("font_size", 15)
	vb.add_child(lbl_phase)
	lbl_actions = Label.new()
	lbl_actions.add_theme_font_size_override("font_size", 15)
	vb.add_child(lbl_actions)
	lbl_deck = Label.new()
	lbl_deck.add_theme_font_size_override("font_size", 14)
	vb.add_child(lbl_deck)

	_build_right_column()
	_build_log_panel()
	_update_hud()

# Columna DERECHA: pilas (Mazo/Descarte/Guardería) + botones (Finalizar Turno, Ver Reglas).
func _build_right_column():
	# Compacta y arriba a la derecha, para dejar libre el CENTRO-derecho al rival.
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	col.anchor_left = 1.0; col.anchor_right = 1.0
	col.anchor_top = 0.0; col.anchor_bottom = 0.0
	col.offset_left = -150; col.offset_right = -10
	col.offset_top = 12; col.offset_bottom = 300
	hud_layer.add_child(col)

	pile_deck_btn = Button.new()
	pile_deck_btn.custom_minimum_size = Vector2(140, 40)
	pile_deck_btn.disabled = true # el mazo de robo es secreto
	col.add_child(pile_deck_btn)

	pile_discard_btn = Button.new()
	pile_discard_btn.custom_minimum_size = Vector2(140, 40)
	pile_discard_btn.pressed.connect(func(): _request_pile_view("discard"))
	col.add_child(pile_discard_btn)

	pile_nursery_btn = Button.new()
	pile_nursery_btn.custom_minimum_size = Vector2(140, 40)
	pile_nursery_btn.pressed.connect(func(): _request_pile_view("nursery"))
	col.add_child(pile_nursery_btn)

	var sep := Control.new()
	sep.custom_minimum_size = Vector2(0, 8)
	col.add_child(sep)

	btn_end_turn = Button.new()
	btn_end_turn.text = "✔ Finalizar Turno"
	btn_end_turn.custom_minimum_size = Vector2(140, 44)
	btn_end_turn.disabled = true
	btn_end_turn.pressed.connect(_on_end_turn_pressed)
	col.add_child(btn_end_turn)

	var btn_rules := Button.new()
	btn_rules.text = "📖 Ver Reglas"
	btn_rules.custom_minimum_size = Vector2(140, 40)
	btn_rules.pressed.connect(_show_rules_viewer)
	col.add_child(btn_rules)

	_refresh_pile_labels()

func _refresh_pile_labels():
	if is_instance_valid(pile_deck_btn):
		pile_deck_btn.text = "🂠 Mazo\n%d" % _count_deck
	if is_instance_valid(pile_discard_btn):
		pile_discard_btn.text = "🗑 Descarte\n%d" % _count_discard
	if is_instance_valid(pile_nursery_btn):
		pile_nursery_btn.text = "👶 Guardería\n%d" % _count_nursery

# Visor de TODAS las reglas/cartas (nombre + tipo + efecto), desplazable.
func _show_rules_viewer():
	_close_modal()
	var panel = _make_modal_panel("📖 Reglas del juego")
	active_modal = panel
	modal_layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(740, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_modal_vbox(panel).add_child(scroll)

	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.custom_minimum_size = Vector2(700, 0)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_color_override("default_color", Color.WHITE)
	rt.text = _rules_card_text()
	scroll.add_child(rt)

	var btn_close := Button.new()
	btn_close.text = "Cerrar"
	btn_close.pressed.connect(_close_modal)
	_modal_vbox(panel).add_child(btn_close)

# Texto de la tarjeta de reglas (objetivo + fases del turno + tipos + relincho).
# Usa la meta de Unicornios CONFIGURADA en esta partida.
func _rules_card_text() -> String:
	var goal: int = GameManager.current_rules.unicorns_to_win
	return "\n".join([
		"[b][color=#ffe070]🎯 OBJETIVO[/color][/b]",
		"Sé el primero en reunir [b][color=#ffe070]%d Unicornios[/color][/b] en tu Establo." % goal,
		"",
		"[b][color=#9ad0ff]🔄 TU TURNO (en orden)[/color][/b]",
		"[b]1. Inicio:[/b] se activan los efectos de \"al inicio de tu turno\".",
		"[b]2. Robo:[/b] roba 1 carta del mazo.",
		"[b]3. Acción:[/b] haz UNA sola cosa:",
		"      • Juega una carta de tu mano, [i]o[/i]",
		"      • Roba una carta (en vez de jugar).",
		"[b]4. Fin:[/b] si tienes más de 7 cartas en mano, descarta hasta quedar en 7.",
		"",
		"[b][color=#c9a0ff]🃏 TIPOS DE CARTA[/color][/b]",
		"[color=#584f8e]●[/color] [b]Unicornio Básico[/b]: sin efectos especiales.",
		"[color=#54b0e5]●[/color] [b]Unicornio Mágico[/b]: tiene un efecto especial.",
		"[color=#c05e97]●[/color] [b]Unicornio Bebé[/b]: viene de la Guardería; cuenta como Unicornio.",
		"[color=#8ed247]●[/color] [b]Magia[/b]: efecto único; luego va al descarte.",
		"[color=#f8752e]●[/color] [b]Ventaja[/b]: efecto positivo permanente en un Establo.",
		"[color=#fbcb44]●[/color] [b]Desventaja[/b]: efecto negativo permanente en un Establo.",
		"[color=#ff4034]●[/color] [b]Relincho[/b]: instantánea; cancela una carta.",
		"",
		"[b][color=#ff6b5e]🔴 RELINCHO (Neigh)[/color][/b]",
		"Juégalo en cualquier momento, [b]incluso fuera de tu turno[/b], para CANCELAR la carta que alguien está jugando. La carta cancelada va al descarte.",
		"Un Relincho puede ser relinchado. El [b]Súperrelincho[/b] no se puede anular.",
		"",
		"[b][color=#9ad0ff]🧩 TÉRMINOS[/color][/b]",
		"[b]Establo[/b]: tu zona de Unicornios y Ventajas/Desventajas.",
		"[b]Guardería[/b]: la pila de Unicornios Bebé.",
	])

# Colorea las palabras clave (colores brillantes para fondo oscuro).
func _colorize_keywords(text: String) -> String:
	var t = text
	var rules = [
		["DESTRUYE", "#ff6b5e"], ["DESTRUIR", "#ff6b5e"],
		["SACRIFICA", "#ff9d5c"], ["SACRIFICAR", "#ff9d5c"],
		["ROBA", "#6bdb6b"], ["ROBAR", "#6bdb6b"],
		["DESCARTA", "#9fb8ff"], ["DESCARTAR", "#9fb8ff"],
		["HURTA", "#cf8bff"], ["HURTAR", "#cf8bff"],
	]
	for r in rules:
		t = t.replace(r[0], "[b][color=%s]%s[/color][/b]" % [r[1], r[0]])
	return t

func _pretty_type(t: GameEnums.CardType) -> String:
	match t:
		GameEnums.CardType.BABY_UNICORN: return "Bebé Unicornio"
		GameEnums.CardType.BASIC_UNICORN: return "Unicornio Básico"
		GameEnums.CardType.MAGICAL_UNICORN: return "Unicornio Mágico"
		GameEnums.CardType.MAGIC_SPELL: return "Magia"
		GameEnums.CardType.INSTANT: return "Relincho"
		GameEnums.CardType.UPGRADE: return "Ventaja"
		GameEnums.CardType.DOWNGRADE: return "Desventaja"
		_: return "Otro"

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

# ==============================================================================
# 📜 REGISTRO DE JUGADAS (log lateral)
# ==============================================================================

func _build_log_panel():
	log_panel = PanelContainer.new()
	# IZQUIERDA, justo DEBAJO del HUD. Corto (no llega al rival izquierdo del centro).
	log_panel.anchor_left = 0.0; log_panel.anchor_right = 0.0
	log_panel.anchor_top = 0.0; log_panel.anchor_bottom = 0.0
	log_panel.offset_left = 12; log_panel.offset_right = 252
	log_panel.offset_top = 145; log_panel.offset_bottom = 360
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	log_panel.add_theme_stylebox_override("panel", sb)
	hud_layer.add_child(log_panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	log_panel.add_child(outer)

	# Fila de título con botón para plegar/desplegar.
	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	var title := Label.new()
	title.text = "📜 Registro"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	_log_toggle_btn = Button.new()
	_log_toggle_btn.text = "▾"
	_log_toggle_btn.tooltip_text = "Mostrar/ocultar el registro"
	_log_toggle_btn.custom_minimum_size = Vector2(30, 0)
	_log_toggle_btn.pressed.connect(_toggle_log)
	title_row.add_child(_log_toggle_btn)

	log_scroll = ScrollContainer.new()
	log_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	log_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	log_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(log_scroll)

	log_container = VBoxContainer.new()
	log_container.add_theme_constant_override("separation", 3)
	log_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	log_scroll.add_child(log_container)

# Pliega/despliega el registro: al plegar, el panel se encoge a solo el título.
func _toggle_log():
	log_collapsed = not log_collapsed
	if is_instance_valid(log_scroll):
		log_scroll.visible = not log_collapsed
	if is_instance_valid(_log_toggle_btn):
		_log_toggle_btn.text = "▸" if log_collapsed else "▾"
	if is_instance_valid(log_panel):
		if log_collapsed:
			log_panel.offset_bottom = 190.0
		else:
			log_panel.offset_bottom = 360.0

# Añade una línea al registro local y hace auto-scroll al fondo.
func _add_log_line(text: String, color: Color = Color.WHITE) -> void:
	if not is_instance_valid(log_container):
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.modulate = color
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(198, 0)
	log_container.add_child(lbl)
	# Podar las líneas más viejas para no crecer sin límite.
	var excess := log_container.get_child_count() - 60
	for _i in range(max(0, excess)):
		var old := log_container.get_child(0)
		log_container.remove_child(old)
		old.queue_free()
	await get_tree().process_frame
	if is_instance_valid(log_scroll):
		var vbar := log_scroll.get_v_scroll_bar()
		if vbar:
			log_scroll.scroll_vertical = int(vbar.max_value)

# RPC: el servidor difunde una línea de registro a todos.
@rpc("authority", "call_local", "reliable")
func client_log_event(text: String, color: Color = Color.WHITE) -> void:
	_add_log_line(text, color)

# Atajo server-side para difundir una línea de registro.
func _server_log(text: String, color: Color = Color.WHITE) -> void:
	if not multiplayer.is_server():
		return
	rpc("client_log_event", text, color)

func _build_modal_layer():
	modal_layer = CanvasLayer.new()
	modal_layer.layer = 10
	add_child(modal_layer)

# ==============================================================================
# 🎬 ANIMACIONES DE MOVIMIENTO (capa overlay)
# ==============================================================================
# Las cartas "vuelan" como nodos temporales en una CanvasLayer aparte. Así el
# movimiento NO pelea con el layout de los HBox/VBox (que reordenan a sus hijos).
# Cada vuelo es puramente cosmético-local; la lógica de red no cambia.

func _build_anim_layer():
	anim_layer = CanvasLayer.new()
	anim_layer.layer = 15 # encima de modales (10), debajo del UILayer (20)
	add_child(anim_layer)

# Crea un AudioStreamPlayer por cada efecto de sonido disponible.
func _build_sfx():
	for key in SFX_FILES:
		var path: String = SFX_FILES[key]
		if not ResourceLoader.exists(path):
			continue
		var player := AudioStreamPlayer.new()
		player.stream = load(path)
		add_child(player)
		_sfx[key] = player

# Reproduce un efecto de sonido por nombre (silencioso si no se cargó).
func _play_sfx(sfx_name: String) -> void:
	if _sfx.has(sfx_name) and is_instance_valid(_sfx[sfx_name]):
		_sfx[sfx_name].play()

# Centro global de un nodo Control (para apuntar vuelos a su posición real).
func _node_center(node: Control) -> Vector2:
	if not is_instance_valid(node):
		return get_viewport_rect().size * 0.5
	return node.global_position + node.size * 0.5

# Textura de una carta por id (cae al reverso si no existe la imagen).
func _card_texture(card_id: int) -> Texture2D:
	var data = CardDatabase.get_card_data(card_id)
	if data and ResourceLoader.exists(data.image_path):
		return load(data.image_path)
	return CARD_BACK_TEX

func _first_rival_center() -> Vector2:
	for pid in rival_stables:
		var z = rival_stables[pid]
		if is_instance_valid(z):
			return _node_center(z)
	return get_viewport_rect().size * 0.5

# Lanza una carta fantasma que viaja de un centro global a otro, escalando de
# tamaño, y se autodestruye al llegar. `on_finish` corre al aterrizar.
func _fly_card(texture: Texture2D, from_center: Vector2, to_center: Vector2,
		from_size: Vector2, to_size: Vector2, duration: float = 0.35,
		on_finish: Callable = Callable()) -> void:
	if not is_instance_valid(anim_layer):
		if on_finish.is_valid(): on_finish.call()
		return
	var ghost := TextureRect.new()
	ghost.texture = texture
	ghost.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ghost.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ghost.size = from_size
	ghost.global_position = from_center - from_size * 0.5
	ghost.z_index = 50
	anim_layer.add_child(ghost)
	var tw := ghost.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ghost, "global_position", to_center - to_size * 0.5, duration)
	tw.tween_property(ghost, "size", to_size, duration)
	tw.chain().tween_callback(func():
		ghost.queue_free()
		if on_finish.is_valid(): on_finish.call()
	)

# Una carta recién añadida a la mano: vuela desde el mazo y se revela al aterrizar.
func _animate_card_into_hand(card: CardUI) -> void:
	if not is_instance_valid(card) or not card.card_data:
		return
	var from := _node_center(pile_deck_btn)
	card.modulate.a = 0.0 # oculta hasta que aterrice el fantasma
	await get_tree().process_frame # dejar que el HBox posicione la carta real
	if not is_instance_valid(card):
		return
	var to := _node_center(card)
	var to_size := card.size
	if to_size == Vector2.ZERO:
		to_size = Vector2(100, 140)
	_fly_card(_card_texture(card.card_data.id), from, to, Vector2(70, 96), to_size, 0.35, func():
		if is_instance_valid(card):
			var tw := card.create_tween()
			tw.tween_property(card, "modulate:a", 1.0, 0.12)
	)

# Una carta jugada desde la mano: vuela hacia su destino (establo o descarte).
func _animate_card_play(card_ui: CardUI) -> void:
	if not is_instance_valid(card_ui) or not card_ui.card_data:
		if is_instance_valid(card_ui): card_ui.queue_free()
		return
	var data: CardData = card_ui.card_data
	var from := _node_center(card_ui)
	var from_size := card_ui.size
	var to: Vector2
	if data.is_downgrade():
		to = _first_rival_center() # los Downgrades van al establo rival
	elif data.is_permanent():
		to = _node_center(my_upgrades_row if data.is_upgrade() else my_unicorns_row)
	else:
		to = _node_center(pile_discard_btn) # magias/instantáneas → descarte
	card_ui.queue_free() # sale de la mano ya
	_fly_card(_card_texture(data.id), from, to, from_size, Vector2(95, 130), 0.4)

# Una carta que sale de MI establo: vuela hacia la pila de descarte.
func _animate_card_to_discard(card: Control) -> void:
	if not is_instance_valid(card):
		return
	var from := _node_center(card)
	var from_size := card.size
	var tex: Texture2D = null
	if card is CardUI and card.card_data:
		tex = _card_texture(card.card_data.id)
	card.queue_free()
	if tex:
		_fly_card(tex, from, _node_center(pile_discard_btn), from_size, Vector2(70, 96), 0.4)

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
	lbl_deck.text = "Meta: %d 🦄" % GameManager.current_rules.unicorns_to_win

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
func _on_phase_changed(phase: int):
	_update_hud()
	# Registrar el cambio de turno una sola vez (al entrar en fase INICIO).
	if phase == GameManager.TurnPhase.START:
		var pname := "—"
		if GameManager.players.has(GameManager.active_player_id):
			pname = GameManager.players[GameManager.active_player_id].name
		_add_log_line("🔄 Turno de %s" % pname, Color(0.7, 0.85, 1.0))
		if GameManager.active_player_id == multiplayer.get_unique_id():
			_play_sfx("turn") # campanita cuando empieza TU turno
func _on_actions_changed(_remaining: int): _update_hud()

func _on_end_turn_pressed():
	btn_end_turn.disabled = true
	_play_sfx("click")
	if multiplayer.is_server():
		GameManager.request_end_turn()
	else:
		GameManager.rpc_id(1, "request_end_turn")

var _vote_tally_label: Label

func _on_game_won(winner_id: int, winner_name: String):
	_update_hud()
	_play_sfx("win")
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
	# Servidor dedicado (árbitro): NO cerrar el peer (mataría el servidor). Solo
	# resetear su estado para volver a aceptar salas; sigue vivo en Render.
	if GameManager.is_dedicated_referee:
		OnlineServer.reset_active_game()
		return
	# Desconectar limpio para que el Lobby muestre la pantalla de login
	# (nombre, IP, unirse) como al principio.
	GameManager.is_game_active = false
	GameManager.players.clear()
	GameManager.online_mode = false
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	get_tree().change_scene_to_file("res://scenes/game/Lobby.tscn")

# ==============================================================================
# 🏗️ CONFIGURACIÓN DE LA MESA
# ==============================================================================

func setup_table():
	var my_id = multiplayer.get_unique_id()
	# Lista ordenada de rivales (para asignarles slots alrededor de la mesa)
	var rival_ids: Array[int] = []
	for p_id in GameManager.players:
		if p_id != my_id:
			rival_ids.append(p_id)
	rival_ids.sort()
	var rival_count := rival_ids.size()
	for i in range(rival_count):
		var p_id = rival_ids[i]
		_create_rival_zone(p_id, GameManager.players[p_id], i, rival_count)
	# El servidor dedicado (árbitro) NO es jugador: no tiene "mi zona".
	if GameManager.is_dedicated_referee:
		print("Servidor árbitro: mesa lista (", rival_count, " jugadores).")
	else:
		print("Configurando mi zona: ", GameManager.players[my_id].name)

# Escala de carta para las zonas rivales según cuántos haya.
func _rival_card_scale(n: int) -> float:
	return 1.0 if n <= 3 else 0.8

# Devuelve {fx, y} para el slot del rival: reparte ARRIBA / IZQUIERDA / DERECHA.
#  - 1 rival  → arriba-centro
#  - 2 rivales → izquierda y derecha
#  - 3 rivales → izquierda, arriba-centro, derecha
# Devuelve la POSICIÓN del rival alrededor de la mesa: "top" / "left" / "right".
#  - 1 rival  → arriba
#  - 2 rivales → izquierda y derecha
#  - 3 rivales → arriba, izquierda, derecha
func _rival_slot(index: int, total: int) -> String:
	match total:
		1:
			return "top"
		2:
			return ["left", "right"][index]
		_:
			return ["top", "left", "right"][index]

func _create_rival_zone(id: int, data: PlayerData, index: int, rival_count: int = 1):
	var rival_zone = RIVAL_ZONE_SCENE.instantiate()
	rival_layer.add_child(rival_zone)
	if rival_zone.has_method("set_card_scale"):
		rival_zone.set_card_scale(_rival_card_scale(rival_count))
	rival_zone.setup(data.name)

	# Posición ALREDEDOR de la mesa: arriba (centro), izquierda o derecha (centradas
	# verticalmente). El panel crece hacia abajo según su contenido.
	var pos := _rival_slot(index, rival_count)
	var half_w := 150.0
	rival_zone.grow_vertical = Control.GROW_DIRECTION_END
	rival_zone.offset_top = 0
	rival_zone.offset_bottom = 0
	match pos:
		"top":
			rival_zone.anchor_left = 0.5; rival_zone.anchor_right = 0.5
			rival_zone.anchor_top = 0.0; rival_zone.anchor_bottom = 0.0
			rival_zone.offset_left = -half_w; rival_zone.offset_right = half_w
			rival_zone.offset_top = 8.0; rival_zone.offset_bottom = 8.0 # pegado al borde superior
			rival_zone.grow_horizontal = Control.GROW_DIRECTION_BOTH
		"left":
			rival_zone.anchor_left = 0.0; rival_zone.anchor_right = 0.0
			rival_zone.anchor_top = 0.40; rival_zone.anchor_bottom = 0.40
			rival_zone.offset_left = 12.0; rival_zone.offset_right = 12.0 + 2.0 * half_w
			rival_zone.grow_horizontal = Control.GROW_DIRECTION_END
		"right":
			rival_zone.anchor_left = 1.0; rival_zone.anchor_right = 1.0
			rival_zone.anchor_top = 0.40; rival_zone.anchor_bottom = 0.40
			rival_zone.offset_left = -(12.0 + 2.0 * half_w); rival_zone.offset_right = -12.0
			rival_zone.grow_horizontal = Control.GROW_DIRECTION_BEGIN

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
	_server_log("🎮 ¡Comienza la partida!", Color(1, 0.9, 0.5))
	GameManager.setup_turn_order()

# ==============================================================================
# 👶 FASE DE SELECCIÓN DE BEBÉS
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_start_baby_selection(available_babies: Array):
	# El servidor árbitro no elige bebé (no es jugador).
	if GameManager.is_dedicated_referee:
		return
	print("Cliente: Abriendo selector de bebés...")
	_play_sfx("shuffle") # las cartas se barajan al empezar
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
	_server_log("▶ %s juega %s" % [p_data.name, card_data.name_es], Color(0.85, 1.0, 0.7))

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
			_server_log("⚡ %s fue relinchada" % card_data.name_es, Color(1, 0.55, 0.45))
			GameManager.discard_pile.append(card_id)
			rpc("client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())
			GameManager.is_resolving = false
			GameManager.consume_action()
			return

	# Determinar destino para Downgrades: el jugador ELIGE a qué rival se la pone.
	# Con 1 solo rival (2 jugadores) va directo, sin preguntar (es obvio).
	var dest_player_id: int = sender_id
	if card_data.is_downgrade():
		dest_player_id = await _server_choose_downgrade_target(sender_id, target_player_id)

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

# Elige a qué rival se le coloca la desventaja.
#  - 0 rivales: a uno mismo (caso borde).
#  - 1 rival (2 jugadores): directo, SIN picker (es obvio).
#  - 2+ rivales: muestra el selector de jugador al que la juega.
# Si el cliente ya mandó un objetivo válido (requested), se respeta.
func _server_choose_downgrade_target(sender_id: int, requested: int) -> int:
	var opponents = GameManager.get_opponents_of(sender_id)
	if opponents.is_empty(): return sender_id
	if requested != -1 and requested != sender_id and requested in opponents:
		return requested
	if opponents.size() == 1:
		return opponents[0]
	var chosen = await EffectProcessor._request_player_pick(sender_id, opponents)
	if chosen == -1 or not (chosen in opponents):
		return opponents[0] # por si cancela: cae al primero (la carta ya se jugó)
	return chosen

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
		var c := add_card_to_hand(id)
		_animate_card_into_hand(c) # reparto inicial: vuelan desde el mazo
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_receive_drawn_batch(card_ids: Array):
	for id in card_ids:
		var c := add_card_to_hand(id)
		_animate_card_into_hand(c) # robo: la carta vuela del mazo a la mano
	if not card_ids.is_empty():
		_play_sfx("draw")
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
	var is_top := card_data.is_upgrade() or card_data.is_downgrade()
	var added := false
	if player_id == my_id:
		if is_top:
			my_upgrades_row.add_child(new_card)
		else:
			my_unicorns_row.add_child(new_card)
		# Footprint real más pequeño (sin truco de 'scale' que dejaba huecos y
		# encimaba filas). Las ventajas/desventajas (fila de arriba) un poco más
		# chicas aún, para que se vean limpias sobre los unicornios.
		if is_top:
			new_card.custom_minimum_size = Vector2(64, 88) # ventajas/desventajas (más chicas)
		else:
			new_card.custom_minimum_size = Vector2(78, 107) # unicornios
		added = true
	elif rival_stables.has(player_id):
		rival_stables[player_id].add_card_to_stable(new_card, is_top)
		added = true
	# Si la carta no se agregó a ningún contenedor (jugador sin zona),
	# la descartamos para NO llamar setup_card fuera del árbol (evita crash de textura null).
	if not added:
		new_card.queue_free()
		return
	new_card.setup_card(card_data)
	new_card.name = "Stable_%d_%d" % [player_id, card_id]
	new_card.set_meta("card_id", card_id) # para localizar/quitar (soporta duplicados)
	# Las cartas del establo nunca se juegan/descartan, pero SÍ se pueden inspeccionar:
	new_card.info_requested.connect(_on_card_info_requested)
	new_card.set_disabled(true)
	# Animación "pop": entra escalando desde pequeño
	_animate_pop_in(new_card)
	# El que juega ya escuchó "play" al clickear; los demás lo oyen al aterrizar.
	if player_id != my_id:
		_play_sfx("play")
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
	_play_sfx("destroy")
	# Buscar en mi establo por metadata (soporta duplicados) → vuela al descarte
	for row in [my_upgrades_row, my_unicorns_row]:
		for child in row.get_children():
			if child.has_meta("card_id") and int(child.get_meta("card_id")) == card_id:
				_animate_card_to_discard(child)
				return
	# Buscar en rivales
	if rival_stables.has(player_id):
		var zone = rival_stables[player_id]
		if zone.has_method("remove_card_from_stable"):
			zone.remove_card_from_stable(card_id)

# Un jugador se desconectó: quitamos su zona rival de la mesa.
@rpc("authority", "call_local", "reliable")
func client_remove_player_zone(player_id: int):
	if rival_stables.has(player_id):
		var zone = rival_stables[player_id]
		if is_instance_valid(zone):
			var tw = create_tween()
			tw.tween_property(zone, "modulate:a", 0.0, 0.3)
			tw.tween_callback(zone.queue_free)
		rival_stables.erase(player_id)
	_update_hud()

@rpc("authority", "call_local", "reliable")
func client_sync_deck_counters(deck_size: int, discard_size: int, nursery_size: int = 0):
	var discard_changed = discard_size != _count_discard
	var nursery_changed = nursery_size != _count_nursery
	_count_deck = deck_size
	_count_discard = discard_size
	_count_nursery = nursery_size
	if is_instance_valid(lbl_deck):
		lbl_deck.text = "Meta: %d 🦄" % GameManager.current_rules.unicorns_to_win
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
		var cap_cid: int = cid
		card_ui.enable_pick_mode(func(): call(callback_name, cap_cid))
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
		var cap_cid: int = cid
		var cap_owner: int = owner_id
		card_ui.enable_pick_mode(func(): _send_stable_pick(cap_cid, cap_owner))
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
	# Listar opciones válidas leyendo MIS cartas visuales (en cliente la data
	# autoritativa está vacía; la fuente fiable son los nodos en pantalla).
	var candidates: Array = []
	var action_enum := action as GameEnums.Action
	var filter_enum := filter as GameEnums.Filter
	var source_ids: Array = []
	if action_enum == GameEnums.Action.DISCARD:
		source_ids = _my_hand_card_ids()
	elif action_enum == GameEnums.Action.SACRIFICE:
		source_ids = _my_stable_card_ids()
	for cid in source_ids:
		var cd := CardDatabase.get_card_data(cid)
		if cd and cd.matches_filter(filter_enum):
			candidates.append(cid)
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
		var cap_cid: int = cid
		var cap_ui: CardUI = card_ui
		card_ui.enable_pick_mode(func(): _toggle_cost_card(cap_cid, cap_ui))

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

# ==============================================================================
# 🗑️ DESCARTE POR LÍMITE DE MANO (el jugador elige qué soltar)
# ==============================================================================

@rpc("authority", "call_local", "reliable")
func client_open_discard_to_limit(amount: int):
	_show_discard_to_limit_picker(amount)

# IDs de las cartas en MI mano, leídos de los nodos visuales (fuente fiable en
# cliente; GameManager.players[mi_id].hand solo está poblado en el servidor).
func _my_hand_card_ids() -> Array:
	var ids: Array = []
	for c in my_hand_container.get_children():
		if c is CardUI and c.card_data:
			ids.append(c.card_data.id)
	return ids

# IDs de las cartas en MI establo (filas visuales).
func _my_stable_card_ids() -> Array:
	var ids: Array = []
	for row in [my_upgrades_row, my_unicorns_row]:
		for c in row.get_children():
			if c is CardUI and c.card_data:
				ids.append(c.card_data.id)
	return ids

func _show_discard_to_limit_picker(amount: int):
	_close_modal()
	var hand_ids := _my_hand_card_ids()
	if hand_ids.is_empty():
		_send_discard_chosen([]) # sin mano visible: el server completará por FIFO
		return
	_discard_limit_picked = []
	var panel = _make_modal_panel("Tu mano supera el límite. Elige %d carta(s) para descartar." % amount)
	active_modal = panel
	panel.set_meta("amount", amount)
	modal_layer.add_child(panel)

	var info_lbl = Label.new()
	info_lbl.text = "Marcadas 0/%d" % amount
	panel.set_meta("info_lbl", info_lbl)
	_modal_vbox(panel).add_child(info_lbl)

	var hbox = _make_scrollable_hbox(_modal_vbox(panel))
	for cid in hand_ids:
		var data = CardDatabase.get_card_data(cid)
		if not data: continue
		var card_ui = CARD_SCENE.instantiate()
		hbox.add_child(card_ui)
		card_ui.setup_card(data)
		card_ui.custom_minimum_size = Vector2(120, 165)
		var cap_cid: int = cid
		var cap_ui: CardUI = card_ui
		card_ui.enable_pick_mode(func(): _toggle_discard_limit_card(cap_cid, cap_ui))

	var btn_confirm = Button.new()
	btn_confirm.text = "Descartar (0/%d)" % amount
	btn_confirm.disabled = true
	btn_confirm.pressed.connect(_confirm_discard_to_limit)
	panel.set_meta("confirm_btn", btn_confirm)
	_modal_vbox(panel).add_child(btn_confirm)

func _toggle_discard_limit_card(card_id: int, card_ui: CardUI):
	if not is_instance_valid(active_modal): return
	var amount: int = active_modal.get_meta("amount", 1)
	if card_id in _discard_limit_picked:
		_discard_limit_picked.erase(card_id)
		card_ui.modulate = Color.WHITE
	else:
		if _discard_limit_picked.size() >= amount:
			return
		_discard_limit_picked.append(card_id)
		card_ui.modulate = Color(1, 0.5, 0.5)
	var info_lbl = active_modal.get_meta("info_lbl", null)
	if is_instance_valid(info_lbl):
		info_lbl.text = "Marcadas %d/%d" % [_discard_limit_picked.size(), amount]
	var btn = active_modal.get_meta("confirm_btn", null)
	if is_instance_valid(btn):
		btn.text = "Descartar (%d/%d)" % [_discard_limit_picked.size(), amount]
		btn.disabled = _discard_limit_picked.size() < amount

func _confirm_discard_to_limit():
	if not is_instance_valid(active_modal): return
	var amount: int = active_modal.get_meta("amount", 1)
	if _discard_limit_picked.size() < amount: return
	var chosen = _discard_limit_picked.duplicate()
	_close_modal()
	_send_discard_chosen(chosen)

func _send_discard_chosen(card_ids: Array):
	if multiplayer.is_server():
		GameManager._on_discard_choice(card_ids)
	else:
		rpc_id(1, "server_discard_chosen", card_ids)

@rpc("any_peer", "reliable")
func server_discard_chosen(card_ids: Array):
	if not multiplayer.is_server(): return
	if multiplayer.get_remote_sender_id() != GameManager.active_player_id: return
	GameManager._on_discard_choice(card_ids)

func _make_modal_panel(title: String) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -400; panel.offset_right = 400
	panel.offset_top = -250; panel.offset_bottom = 250
	# Fondo SÓLIDO oscuro (no transparente) con borde.
	var msb := StyleBoxFlat.new()
	msb.bg_color = Color(0.10, 0.10, 0.13, 1.0)
	msb.set_corner_radius_all(12)
	msb.set_border_width_all(3)
	msb.border_color = Color(0.45, 0.45, 0.55, 1.0)
	panel.add_theme_stylebox_override("panel", msb)
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
	# Solo abrir UI si tengo Neigh en mano. Leemos la mano VISUAL (la data
	# GameManager.players[mi_id].hand está vacía en cliente).
	var my_id = multiplayer.get_unique_id()
	if my_id == playing_player_id: return
	var neigh_in_hand: Array = []
	for cid in _my_hand_card_ids():
		var cd := CardDatabase.get_card_data(cid)
		if cd and cd.is_instant(): neigh_in_hand.append(cid)
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
	# Panel GRANDE y centrado-arriba, imposible de no ver
	neigh_window_panel.anchor_left = 0.5; neigh_window_panel.anchor_right = 0.5
	neigh_window_panel.anchor_top = 0.0; neigh_window_panel.anchor_bottom = 0.0
	neigh_window_panel.offset_left = -360; neigh_window_panel.offset_right = 360
	neigh_window_panel.offset_top = 70; neigh_window_panel.offset_bottom = 300
	var nsb := StyleBoxFlat.new()
	nsb.bg_color = Color(0.12, 0.05, 0.05, 0.97)
	nsb.set_corner_radius_all(14)
	nsb.set_content_margin_all(18)
	nsb.set_border_width_all(5)
	nsb.border_color = Color(1, 0.27, 0.2)
	neigh_window_panel.add_theme_stylebox_override("panel", nsb)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	neigh_window_panel.add_child(vbox)

	# Encabezado llamativo
	var header = Label.new()
	header.text = "⚡ ¡PUEDES RELINCHAR! ⚡"
	header.add_theme_font_size_override("font_size", 28)
	header.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(header)

	var lbl = Label.new()
	lbl.text = "🐴 %s juega: %s" % [player_name, card_name]
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)

	# Cuenta regresiva en vivo
	var countdown = Label.new()
	countdown.name = "Countdown"
	countdown.add_theme_font_size_override("font_size", 22)
	countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(countdown)

	var hint = Label.new()
	hint.text = "(también puedes clickear tu Relincho resaltado en la mano)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.8, 0.8, 0.8)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

	var hb = HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 14)
	vbox.add_child(hb)
	for nid in neighs:
		var btn = Button.new()
		var data = CardDatabase.get_card_data(nid)
		btn.text = "¡%s!" % data.name_es
		btn.custom_minimum_size = Vector2(150, 56)
		var captured_nid = nid
		btn.pressed.connect(func():
			if multiplayer.is_server():
				NeighManager.server_receive_neigh(multiplayer.get_unique_id(), captured_nid)
			else:
				NeighManager.rpc_id(1, "server_receive_neigh_rpc", captured_nid)
			if is_instance_valid(neigh_window_panel): neigh_window_panel.queue_free()
		)
		hb.add_child(btn)
	var btn_skip = Button.new()
	btn_skip.text = "Pasar"
	btn_skip.custom_minimum_size = Vector2(110, 56)
	btn_skip.pressed.connect(func():
		if is_instance_valid(neigh_window_panel): neigh_window_panel.queue_free()
	)
	hb.add_child(btn_skip)

	modal_layer.add_child(neigh_window_panel)

	# Pulso del borde para llamar la atención
	var pulse := neigh_window_panel.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	pulse.tween_property(neigh_window_panel, "modulate", Color(1.25, 1.25, 1.25), 0.5)
	pulse.tween_property(neigh_window_panel, "modulate", Color.WHITE, 0.5)

	# Cuenta regresiva en vivo (Timer hijo → se libera con el panel)
	var secs_left := [int(ceil(secs))]
	countdown.text = "⏳ %d segundos" % secs_left[0]
	var ticker := Timer.new()
	ticker.wait_time = 1.0
	ticker.one_shot = false
	neigh_window_panel.add_child(ticker)
	ticker.timeout.connect(func():
		secs_left[0] -= 1
		if not is_instance_valid(countdown): return
		if secs_left[0] <= 0:
			if is_instance_valid(neigh_window_panel): neigh_window_panel.queue_free()
		else:
			countdown.text = "⏳ %d segundos" % secs_left[0]
			if secs_left[0] <= 5:
				countdown.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	)
	ticker.start()

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
	_play_sfx("neigh")
	var n_name = GameManager.players[neigher_id].name if GameManager.players.has(neigher_id) else "?"
	var orig_card = CardDatabase.get_card_data(original_card_id)
	var n_card = CardDatabase.get_card_data(neigh_card_id)
	var orig_name = orig_card.name_es if orig_card else "?"
	var n_card_name = n_card.name_es if n_card else "?"
	print("⚡ %s usa %s contra %s" % [n_name, n_card_name, orig_name])
	_show_toast("⚡ %s: ¡%s!" % [n_name, n_card_name])
	_add_log_line("⚡ %s relinchó %s" % [n_name, orig_name], Color(1, 0.55, 0.45))

# ==============================================================================
# 🛠️ UTILIDADES
# ==============================================================================

func add_card_to_hand(card_id: int) -> CardUI:
	var data = CardDatabase.get_card_data(card_id)
	if not data: return null
	var new_card = CARD_SCENE.instantiate()
	my_hand_container.add_child(new_card)
	new_card.setup_card(data)
	new_card.name = "Card_%d" % card_id
	new_card.info_requested.connect(_on_card_info_requested)
	new_card.play_requested.connect(_on_card_play_requested)
	new_card.discard_requested.connect(_on_card_discard_requested)
	new_card.set_disabled(true)
	_refresh_hand_interactivity()
	return new_card

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
		# Animación: el Relincho vuela de la mano hacia el descarte
		var from := _node_center(card_ui)
		var from_size := card_ui.size
		card_ui.queue_free()
		_fly_card(_card_texture(card_id), from, _node_center(pile_discard_btn), from_size, Vector2(80, 110), 0.35)
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
	_play_sfx("play")
	_animate_card_play(card_ui) # vuela de la mano a su destino (establo/descarte)

func _show_toast(text: String, duration: float = 2.0):
	# Aviso con fondo oscuro y borde, en la franja superior, que NO estorba
	# (click-through) y se desvanece solo.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.anchor_left = 0.5; panel.anchor_right = 0.5
	panel.anchor_top = 0.16; panel.anchor_bottom = 0.16
	panel.offset_left = -280; panel.offset_right = 280
	panel.offset_top = -28; panel.offset_bottom = 28
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.07, 0.1, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 0.82, 0.35, 0.9)
	panel.add_theme_stylebox_override("panel", sb)
	var toast := Label.new()
	toast.text = text
	toast.add_theme_font_size_override("font_size", 18)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.modulate = Color(1, 0.92, 0.7)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(toast)
	modal_layer.add_child(panel)
	var tw = create_tween()
	tw.tween_interval(duration * 0.6)
	tw.tween_property(panel, "modulate:a", 0.0, duration * 0.4)
	tw.tween_callback(panel.queue_free)

func _on_card_discard_requested(card_ui: CardUI):
	var card_id = card_ui.card_data.id
	var is_my_turn = GameManager.active_player_id == multiplayer.get_unique_id()
	if not is_my_turn or GameManager.current_phase != GameManager.TurnPhase.ACTION: return
	rpc_id(1, "server_discard_card", card_id)
	_animate_card_to_discard(card_ui) # vuela de la mano al descarte

func _clear_debug_cards():
	for child in my_hand_container.get_children():
		child.queue_free()
