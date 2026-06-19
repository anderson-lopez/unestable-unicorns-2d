class_name CardUI extends Control

# --- VARIABLE ESTÁTICA (EL ÁRBITRO) ---
# Esta variable es compartida por TODAS las cartas. 
# Solo una carta puede ser "la activa" a la vez.
static var active_card: CardUI = null 

# --- SEÑALES ---
signal info_requested(card_data)
signal play_requested(card_ui)
signal discard_requested(card_ui)
signal card_hovered(card_ui)
signal card_exited(card_ui)
signal drag_started(card_ui: CardUI, global_pos: Vector2)
signal drag_moved(card_ui: CardUI, global_pos: Vector2)
signal drag_ended(card_ui: CardUI, global_pos: Vector2)

# --- REFERENCIAS A NODOS ---
@onready var card_texture: TextureRect = $CardTexture
@onready var highlight: Panel = $Highlight
@onready var hover_detector: Control = $HoverDetector
@onready var ui_container: MarginContainer = $MarginContainer

# Botones
@onready var play_button: BaseButton = $MarginContainer/ActionButtons/Play
@onready var discard_button: BaseButton = $MarginContainer/ActionButtons/Discard

# --- VARIABLES DE INSTANCIA ---
var card_data: CardData
var is_hovered: bool = false
var is_disabled: bool = false
var is_open: bool = false
# En móvil/táctil usamos TAP para abrir; en escritorio, hover.
var _is_touch: bool = false
const DRAG_THRESHOLD: float = 16.0
const TAP_MAX_SECS: float = 0.30
var _pressing: bool = false
var _press_global_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _dragging: bool = false

func _ready():
	_is_touch = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

	# 1. Conexiones de Botones
	play_button.pressed.connect(_on_play_pressed)
	discard_button.pressed.connect(_on_discard_pressed)

	# 2. Interacción: tap (táctil) o hover (escritorio)
	hover_detector.gui_input.connect(_on_detector_input)
	hover_detector.mouse_entered.connect(_on_mouse_entered)
	hover_detector.mouse_exited.connect(_on_mouse_exited)

	# 3. Estado inicial visual
	highlight.hide()
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE  # visual puro, no bloquea clics
	ui_container.modulate.a = 0.0 # Botones invisibles al inicio
	_set_buttons_interactive(false) # cerrados: no capturan el toque

	# 4. Botones compactos: con el padding grande del tema, "Jugar Carta" hacía
	# que la carta no pudiera achicarse. Los hacemos pequeños para que la mano
	# quede compacta y en abanico apretado.
	_compact_button(play_button, 11)
	if ui_container:
		ui_container.add_theme_constant_override("margin_left", 5)
		ui_container.add_theme_constant_override("margin_right", 5)
		ui_container.add_theme_constant_override("margin_top", 5)
		ui_container.add_theme_constant_override("margin_bottom", 5)

	# Pivote al centro para que el zoom se vea bien
	pivot_offset = size / 2

# Tap REAL (dedo) sobre la carta → abre/cierra. En escritorio NO se usa
# (no llegan eventos táctiles reales): allí manda el hover del mouse.
func _on_detector_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_global_pos = event.global_position
			_press_time = Time.get_ticks_msec() / 1000.0
		# Release ya fue manejado en _input (se dispara primero). Solo aceptamos
		# para evitar que el click se propague a elementos debajo de la carta.
		hover_detector.accept_event()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_pressing = true
			_dragging = false
			_press_global_pos = event.position
			_press_time = Time.get_ticks_msec() / 1000.0
		# Release manejado en _input.
		hover_detector.accept_event()

func _toggle_open():
	if is_open:
		_force_close()
		if active_card == self: active_card = null
	else:
		_open()

func setup_card(data: CardData):
	card_data = data

	# Robustez: si @onready aún no corrió (carta fuera del árbol), usamos get_node.
	var tex: TextureRect = card_texture if card_texture else get_node_or_null("CardTexture")
	if tex and ResourceLoader.exists(data.image_path):
		tex.texture = load(data.image_path)

	_update_highlight_color(data.type)

# --- LÓGICA DE INTERACCIÓN (CORE) ---

# Abrir la carta (zoom + mostrar botones).
func _open():
	if active_card and active_card != self:
		active_card._force_close()

	active_card = self
	is_open = true
	is_hovered = true
	card_hovered.emit(self)

	z_index = 10
	highlight.show()
	_set_buttons_interactive(true)

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	var open_scale = 1.1 if not is_disabled else 1.05
	tween.tween_property(self, "scale", Vector2(open_scale, open_scale), 0.1)
	tween.tween_property(ui_container, "modulate:a", 1.0, 0.1)

func _on_mouse_entered():
	# El hover SIEMPRE abre la carta. En escritorio = mouse real; en móvil el
	# motor emula el mouse desde el toque (emulate_mouse_from_touch), así que
	# tocar una carta también dispara este "entered" y la abre.
	if _dragging: return
	_open()

func _on_mouse_exited():
	# Escudo anti-parpadeo: si el cursor sigue dentro del rect (sobre un botón), no cerrar.
	var rect = get_global_rect()
	if rect.has_point(get_global_mouse_position()):
		return
	if active_card == self:
		_force_close()
		active_card = null

func _input(event: InputEvent):
	if not _pressing: return
	if event is InputEventMouseMotion:
		var pos: Vector2 = (event as InputEventMouseMotion).global_position
		if _dragging:
			drag_moved.emit(self, pos)
			get_viewport().set_input_as_handled()
		elif pos.distance_to(_press_global_pos) > DRAG_THRESHOLD:
			_dragging = true
			if is_open: _force_close()
			if active_card == self: active_card = null
			drag_started.emit(self, pos)
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var pos: Vector2 = (event as InputEventScreenDrag).position
		if _dragging:
			drag_moved.emit(self, pos)
			get_viewport().set_input_as_handled()
		elif pos.distance_to(_press_global_pos) > DRAG_THRESHOLD:
			_dragging = true
			if is_open: _force_close()
			if active_card == self: active_card = null
			drag_started.emit(self, pos)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var pos: Vector2 = (event as InputEventMouseButton).global_position
		if _dragging:
			_dragging = false
			_pressing = false
			drag_ended.emit(self, pos)
			get_viewport().set_input_as_handled()
		elif _pressing:
			_pressing = false
			# _input dispara antes que gui_input, así que emitimos aquí el detalle.
			var elapsed := Time.get_ticks_msec() / 1000.0 - _press_time
			if elapsed < TAP_MAX_SECS and not _is_touch and card_data:
				info_requested.emit(card_data)
	elif event is InputEventScreenTouch and not event.pressed:
		var pos: Vector2 = (event as InputEventScreenTouch).position
		if _dragging:
			_dragging = false
			_pressing = false
			drag_ended.emit(self, pos)
			get_viewport().set_input_as_handled()
		elif _pressing:
			_pressing = false
			var elapsed := Time.get_ticks_msec() / 1000.0 - _press_time
			if elapsed < TAP_MAX_SECS:
				_toggle_open()

# Cierra la carta suavemente.
func _force_close():
	is_open = false
	is_hovered = false
	card_exited.emit(self)

	z_index = 0
	highlight.hide()
	_set_buttons_interactive(false)

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(ui_container, "modulate:a", 0.0, 0.1)

# Cuando la carta está CERRADA, los botones (aunque transparentes) NO deben
# capturar el toque — así el primer tap abre la carta. Al abrir, sí reciben.
func _set_buttons_interactive(on: bool):
	var f := Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
	if play_button: play_button.mouse_filter = f
	if discard_button: discard_button.mouse_filter = f

# --- LÓGICA DE COLORES ---

func _update_highlight_color(type: GameEnums.CardType):
	var target_color = Color.WHITE
	
	match type:
		GameEnums.CardType.INSTANT: target_color = Color("#ff4034") # Rojo Neigh
		GameEnums.CardType.MAGIC_SPELL: target_color = Color("#8ed247") # Verde Magia
		GameEnums.CardType.MAGICAL_UNICORN: target_color = Color("#54b0e5") # Azul Mágico
		GameEnums.CardType.UPGRADE: target_color = Color("#f8752e") # Naranja Mejora
		GameEnums.CardType.DOWNGRADE: target_color = Color("#fbcb44") # Amarillo Degradación
		GameEnums.CardType.BABY_UNICORN: target_color = Color("#c05e97") # Rosa Bebé
		GameEnums.CardType.BASIC_UNICORN: target_color = Color("#584f8e") # Gris Básico
		_: target_color = Color.WHITE

	# Aplicamos el color usando self_modulate.
	var hl: Panel = highlight if highlight else get_node_or_null("Highlight")
	if hl:
		hl.self_modulate = target_color

# --- LÓGICA DE BOTONES ---

# --- MODO SELECCIÓN (para pickers) ---
# Toda la carta se vuelve un botón: un click/tap la elige directamente.
# Evita el "hover para ver el botón" (incómodo en escritorio, imposible en móvil).
func enable_pick_mode(on_pick: Callable):
	# Overlay a toda la carta que distingue TAP (elegir) de ARRASTRE (scrollear el modal).
	# Con emulate_mouse_from_touch el dedo llega como eventos de mouse, así que manejando
	# mouse alcanza para escritorio Y móvil. Sin esto, en el APK no se podía hacer scroll
	# horizontal en los pickers (la carta se "comía" el arrastre).
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(overlay)
	var st := {"pressed": false, "dragging": false, "start": Vector2.ZERO}
	overlay.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT:
			if e.pressed:
				st["pressed"] = true
				st["dragging"] = false
				st["start"] = e.position
			elif st["pressed"]:
				st["pressed"] = false
				# TAP = soltar CERCA de donde se tocó (tolerante al micro-movimiento
				# del dedo). Antes, cualquier jitter > umbral lo marcaba como arrastre
				# y NO seleccionaba → el efecto quedaba esperando y el turno se colgaba.
				if e.position.distance_to(st["start"]) <= 24.0 and on_pick.is_valid():
					on_pick.call()
		elif e is InputEventMouseMotion and st["pressed"]:
			if e.position.distance_to(st["start"]) > 18.0:
				st["dragging"] = true
			if st["dragging"]:
				var sc := _find_scroll_ancestor()
				if sc:
					sc.scroll_horizontal -= int(e.relative.x)
					sc.scroll_vertical -= int(e.relative.y)
	)
	# En modo picker no usamos hover/zoom ni los botones internos.
	if hover_detector: hover_detector.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ui_container: ui_container.visible = false
	if highlight: highlight.show()

# Sube por el árbol buscando el ScrollContainer que contiene a esta carta.
func _find_scroll_ancestor() -> ScrollContainer:
	var n: Node = get_parent()
	while n != null:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null

# Reduce el padding del botón (el tema usa márgenes grandes) conservando
# colores/borde. Así "Jugar Carta" ocupa mucho menos y la carta se encoge.
func _compact_button(b: Button, fs: int):
	if not b: return
	b.add_theme_font_size_override("font_size", fs)
	b.custom_minimum_size = Vector2(0, 0)
	for s in ["normal", "hover", "pressed", "disabled"]:
		var sb := b.get_theme_stylebox(s, "Button")
		if sb is StyleBoxFlat:
			var c: StyleBoxFlat = sb.duplicate()
			c.content_margin_left = 8.0
			c.content_margin_right = 8.0
			c.content_margin_top = 4.0
			c.content_margin_bottom = 4.0
			b.add_theme_stylebox_override(s, c)

func _on_play_pressed():
	play_requested.emit(self)

func _on_discard_pressed():
	discard_requested.emit(self)

# --- EXTRA: DESHABILITAR CARTA ---
# El "disabled" significa "no puedes jugarla/descartarla" — pero SÍ puedes verla.
# Cuando está disabled solo se muestra el botón Info (Play/Discard se ocultan).
func set_disabled(value: bool):
	is_disabled = value
	hover_detector.mouse_filter = Control.MOUSE_FILTER_STOP
	# Play se OCULTA cuando la carta no se puede jugar; el detalle se abre con clic.
	if play_button:
		play_button.visible = not is_disabled
		play_button.disabled = is_disabled
	if discard_button:
		discard_button.visible = false
		discard_button.disabled = true
	var a := modulate.a
	if is_disabled:
		modulate = Color(0.85, 0.85, 0.85, a)
	else:
		modulate = Color(1, 1, 1, a)
