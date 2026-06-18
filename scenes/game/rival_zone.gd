extends PanelContainer

# Cámara Espía: al tocar/clickear una carta revelada del rival, avisamos a la mesa
# para abrir su detalle grande.
signal reveal_card_clicked(card_id: int)

@onready var name_label: Label = $VBoxContainer/TopInfo/NameLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/TopInfo/HandContainer
@onready var stable_container: HBoxContainer = $VBoxContainer/StableContainer

# Carga la textura del reverso (La 1 es la estándar para mano)
const CARD_BACK_TEXTURE = preload("res://assets/textures/cards/reverso/1_reverso.jpg")

# Fila para ventajas/desventajas, creada por código ENCIMA de la de unicornios.
var upgrades_row: HBoxContainer
# Escala de cartas (se reduce cuando hay muchos jugadores para que quepan).
var card_scale: float = 1.0
# Avatar (círculo placeholder) + marcador de unicornios "X/7".
var avatar_circle: Panel
var score_label: Label

var stable_sep: VSeparator

func _ready():
	_build_content_row()
	_build_avatar()
	_apply_panel_style()

# Círculo de avatar (placeholder 🦄, luego se reemplaza por imagen) + marcador X/7.
func _build_avatar():
	var top := name_label.get_parent() # TopInfo (HBox)
	top.add_theme_constant_override("separation", 8)
	avatar_circle = Panel.new()
	avatar_circle.custom_minimum_size = Vector2(40, 40)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.22, 0.18, 0.34)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.75, 0.62, 0.95)
	avatar_circle.add_theme_stylebox_override("panel", sb)
	var em := Label.new()
	em.text = "🦄"
	em.set_anchors_preset(Control.PRESET_FULL_RECT)
	em.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	em.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	em.add_theme_font_size_override("font_size", 22)
	em.mouse_filter = Control.MOUSE_FILTER_IGNORE
	avatar_circle.add_child(em)
	top.add_child(avatar_circle)
	top.move_child(avatar_circle, 0)
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label = Label.new()
	score_label.text = "0/7"
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(score_label)
	top.move_child(score_label, 2) # avatar, nombre, marcador, [espaciador], mano
	# Espaciador para empujar la mano (dorsos) a la derecha de la cabecera.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	top.move_child(spacer, 3)

# Actualiza el marcador "X/7".
func set_score(count: int, goal: int):
	if is_instance_valid(score_label):
		score_label.text = "%d/%d" % [count, goal]

# Cuenta los unicornios en el establo de este rival (Gordicornio cuenta 2).
func count_unicorns() -> int:
	var total := 0
	for child in stable_container.get_children():
		if child.has_meta("card_id"):
			var d = CardDatabase.get_card_data(int(child.get_meta("card_id")))
			if d:
				total += d.unicorn_count_value()
	return total

# Fondo sólido oscuro con borde para que cada establo rival se distinga de la mesa.
func _apply_panel_style():
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.106, 0.075, 0.22, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = Color(0.55, 0.46, 0.82, 0.95) # violeta (los míos van en dorado)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)

# Pone ventajas/desventajas y unicornios en UNA sola fila, separadas por una
# línea (como el mockup): [ventajas/desventajas] | [unicornios].
func _build_content_row():
	var vbox := stable_container.get_parent()
	vbox.add_theme_constant_override("separation", 6)
	var content := HBoxContainer.new()
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 8)
	vbox.add_child(content)
	# Fila de ventajas/desventajas (izquierda).
	upgrades_row = HBoxContainer.new()
	upgrades_row.add_theme_constant_override("separation", 4)
	content.add_child(upgrades_row)
	# Línea separadora (oculta hasta que haya alguna ventaja/desventaja).
	stable_sep = VSeparator.new()
	stable_sep.visible = false
	content.add_child(stable_sep)
	# Reubicamos la fila de unicornios (del escenario) dentro de la misma fila.
	stable_container.get_parent().remove_child(stable_container)
	stable_container.add_theme_constant_override("separation", 4)
	content.add_child(stable_container)

# Muestra la línea solo si hay ventajas/desventajas (si no, sería una rayita suelta).
func _update_sep():
	if is_instance_valid(stable_sep) and is_instance_valid(upgrades_row):
		stable_sep.visible = upgrades_row.get_child_count() > 0

# Ajusta el tamaño de las cartas (1.0 normal; <1 para muchos jugadores).
func set_card_scale(s: float):
	card_scale = s

func setup(player_name: String):
	name_label.text = player_name
	update_hand_visuals(0) # Empieza vacía

var hand_revealed: bool = false

func update_hand_visuals(count: int):
	# Si la mano está revelada (Cámara Espía), no pintamos dorsos:
	# la fuente de verdad es reveal_hand().
	if hand_revealed:
		return

	# 1. Borrar lo que había antes
	for child in hand_container.get_children():
		child.queue_free()

	# 2. Crear nuevas cartas boca abajo
	for i in range(count):
		var card_back = TextureRect.new()
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		card_back.custom_minimum_size = Vector2(40 * card_scale, 60 * card_scale)
		hand_container.add_child(card_back)

# Cámara Espía: muestra la mano del rival BOCA ARRIBA.
func reveal_hand(card_ids: Array):
	hand_revealed = true
	for child in hand_container.get_children():
		child.queue_free()
	for cid in card_ids:
		var data = CardDatabase.get_card_data(cid)
		var tex = TextureRect.new()
		if data and ResourceLoader.exists(data.image_path):
			tex.texture = load(data.image_path)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.custom_minimum_size = Vector2(50 * card_scale, 72 * card_scale)
		# Clicable/tocable: abre el detalle de ESA carta (Cámara Espía).
		tex.mouse_filter = Control.MOUSE_FILTER_STOP
		tex.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		tex.tooltip_text = "Toca para ver"
		tex.gui_input.connect(_on_reveal_card_input.bind(cid))
		hand_container.add_child(tex)

# Detecta clic/toque sobre una carta revelada y avisa a la mesa.
func _on_reveal_card_input(event: InputEvent, card_id: int) -> void:
	if (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventScreenTouch and event.pressed):
		reveal_card_clicked.emit(card_id)

func hide_hand_reveal(count: int):
	hand_revealed = false
	update_hand_visuals(count)

func add_card_to_stable(card_node: Node, is_top_row: bool = false):
	# Tamaño compacto (escalado según cantidad de jugadores).
	if card_node is Control:
		card_node.custom_minimum_size = Vector2(58 * card_scale, 78 * card_scale)
	# Ventajas/desventajas a la izquierda; unicornios a la derecha.
	if is_top_row and is_instance_valid(upgrades_row):
		upgrades_row.add_child(card_node)
	else:
		stable_container.add_child(card_node)
	_update_sep()

# Elimina visualmente una carta del establo del rival por su card_id.
# Busca por metadata "card_id" (soporta cartas duplicadas por el multiplicador)
# en ambas filas; cae a comparar por nombre como respaldo.
func remove_card_from_stable(card_id: int):
	for row in [upgrades_row, stable_container]:
		if not is_instance_valid(row):
			continue
		for child in row.get_children():
			if child.has_meta("card_id") and int(child.get_meta("card_id")) == card_id:
				_fade_and_free(child)
				return
	for row in [upgrades_row, stable_container]:
		if not is_instance_valid(row):
			continue
		for child in row.get_children():
			var parts = str(child.name).split("_")
			if parts.size() > 0 and parts[parts.size() - 1] == str(card_id):
				_fade_and_free(child)
				return

func _fade_and_free(node: Node) -> void:
	var tw = node.create_tween()
	tw.tween_property(node, "modulate:a", 0.0, 0.2)
	tw.tween_callback(node.queue_free)
	tw.tween_callback(_update_sep)
