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

func _ready():
	# 1. Conexiones de Botones
	info_button.pressed.connect(_on_info_pressed)
	play_button.pressed.connect(_on_play_pressed)
	discard_button.pressed.connect(_on_discard_pressed)
	
	# 2. Conexiones de Hover
	hover_detector.mouse_entered.connect(_on_mouse_entered)
	hover_detector.mouse_exited.connect(_on_mouse_exited)
	
	# 3. Estado inicial visual
	highlight.hide()
	ui_container.modulate.a = 0.0 # Botones invisibles al inicio
	
	# Importante: Pivote al centro para que el zoom se vea bien
	pivot_offset = size / 2

func setup_card(data: CardData):
	card_data = data
	
	if ResourceLoader.exists(data.image_path):
		card_texture.texture = load(data.image_path) 
	
	_update_highlight_color(data.type)

# --- LÓGICA DE INTERACCIÓN (CORE) ---

func _on_mouse_entered():
	# Permitimos hover SIEMPRE para que se pueda ver el botón de Info,
	# pero los botones de Play/Discard se desactivan internamente cuando is_disabled.

	# Si otra carta está abierta, la cerramos
	if active_card and active_card != self:
		active_card._force_close()

	active_card = self
	is_hovered = true
	card_hovered.emit(self)

	# Visuales: z_index alto para asegurar que la carta hovered queda encima
	z_index = 10
	highlight.show()

	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	var hover_scale = 1.1 if not is_disabled else 1.05
	tween.tween_property(self, "scale", Vector2(hover_scale, hover_scale), 0.1)
	tween.tween_property(ui_container, "modulate:a", 1.0, 0.1)

func _on_mouse_exited():
	# --- EL ESCUDO ANTI-PARPADEO ---
	# Preguntamos a Godot: "¿El mouse está dentro de mi rectángulo global?"
	# Si la respuesta es SÍ, significa que el mouse está sobre un botón nuestro.
	# Entonces IGNORAMOS la señal de salida. ¡No cerramos nada!
	var rect = get_global_rect()
	if rect.has_point(get_global_mouse_position()):
		return
	# -------------------------------

	# Si realmente el mouse se salió del cuadrado...
	if active_card == self:
		_force_close()
		active_card = null

# Función auxiliar para cerrar la carta suavemente
func _force_close():
	is_hovered = false
	card_exited.emit(self)
	
	z_index = 0
	highlight.hide()
	
	var tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1)
	tween.tween_property(ui_container, "modulate:a", 0.0, 0.1)

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
	# IMPORTANTE: El StyleBox del panel Highlight debe tener el borde BLANCO
	# para que esto funcione correctamente.
	highlight.self_modulate = target_color

# --- LÓGICA DE BOTONES ---

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
	# Asegurar que el hover funciona aunque la carta esté disabled
	hover_detector.mouse_filter = Control.MOUSE_FILTER_PASS
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
	# Tinte sutil para indicar visualmente que no se puede jugar
	if is_disabled:
		modulate = Color(0.85, 0.85, 0.85)
	else:
		modulate = Color.WHITE
