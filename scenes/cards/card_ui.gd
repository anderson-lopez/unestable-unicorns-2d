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

# --- REFERENCIAS A NODOS ---
@onready var card_texture: TextureRect = $CardTexture
@onready var highlight: Panel = $Highlight
@onready var hover_detector: Control = $HoverDetector
@onready var ui_container: MarginContainer = $MarginContainer

# Botones
@onready var info_button: BaseButton = $MarginContainer/InfoButton
@onready var play_button: BaseButton = $MarginContainer/ActionButtons/Play
@onready var discard_button: BaseButton = $MarginContainer/ActionButtons/Discard

# --- VARIABLES DE INSTANCIA ---
var card_data: CardData
var is_hovered: bool = false
var is_disabled: bool = false
var is_open: bool = false
# En móvil/táctil usamos TAP para abrir; en escritorio, hover.
var _is_touch: bool = false

func _ready():
	_is_touch = OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()

	# 1. Conexiones de Botones
	info_button.pressed.connect(_on_info_pressed)
	play_button.pressed.connect(_on_play_pressed)
	discard_button.pressed.connect(_on_discard_pressed)

	# 2. Interacción: tap (táctil) o hover (escritorio)
	hover_detector.gui_input.connect(_on_detector_input)
	hover_detector.mouse_entered.connect(_on_mouse_entered)
	hover_detector.mouse_exited.connect(_on_mouse_exited)

	# 3. Estado inicial visual
	highlight.hide()
	ui_container.modulate.a = 0.0 # Botones invisibles al inicio
	_set_buttons_interactive(false) # cerrados: no capturan el toque

	# Pivote al centro para que el zoom se vea bien
	pivot_offset = size / 2

# Tap REAL (dedo) sobre la carta → abre/cierra. En escritorio NO se usa
# (no llegan eventos táctiles reales): allí manda el hover del mouse.
func _on_detector_input(event: InputEvent):
	if event is InputEventScreenTouch and event.pressed:
		_toggle_open()
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
	_open()

func _on_mouse_exited():
	# Escudo anti-parpadeo: si el cursor sigue dentro del rect (sobre un botón), no cerrar.
	var rect = get_global_rect()
	if rect.has_point(get_global_mouse_position()):
		return
	if active_card == self:
		_force_close()
		active_card = null

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
	if info_button: info_button.mouse_filter = f
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
				if not st["dragging"] and on_pick.is_valid():
					on_pick.call()
		elif e is InputEventMouseMotion and st["pressed"]:
			if e.position.distance_to(st["start"]) > 12.0:
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

func _on_info_pressed():
	if card_data: info_requested.emit(card_data)

func _on_play_pressed():
	play_requested.emit(self)

func _on_discard_pressed():
	discard_requested.emit(self)

# --- EXTRA: DESHABILITAR CARTA ---
# El "disabled" significa "no puedes jugarla/descartarla" — pero SÍ puedes verla.
# Cuando está disabled solo se muestra el botón Info (Play/Discard se ocultan).
func set_disabled(value: bool):
	is_disabled = value
	# El detector captura hover Y taps (necesario para móvil).
	hover_detector.mouse_filter = Control.MOUSE_FILTER_STOP
	# Info siempre activo y visible (para leer descripción de cualquier carta)
	if info_button:
		info_button.disabled = false
		info_button.visible = true
	# Play y Discard se OCULTAN cuando la carta no se puede jugar
	if play_button:
		play_button.visible = not is_disabled
		play_button.disabled = is_disabled
	if discard_button:
		discard_button.visible = not is_disabled
		discard_button.disabled = is_disabled
	# Tinte sutil para indicar visualmente que no se puede jugar.
	# IMPORTANTE: conservar el ALFA actual; si la carta está oculta por una
	# animación (modulate.a = 0), no debemos volverla visible aquí.
	var a := modulate.a
	if is_disabled:
		modulate = Color(0.85, 0.85, 0.85, a)
	else:
		modulate = Color(1, 1, 1, a)
