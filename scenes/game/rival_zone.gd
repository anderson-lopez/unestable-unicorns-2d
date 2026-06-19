extends PanelContainer

# Cámara Espía: al tocar/clickear una carta revelada del rival, avisamos a la mesa
# para abrir su detalle grande.
signal reveal_card_clicked(card_id: int)

@onready var name_label: Label = $VBoxContainer/TopInfo/NameLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/TopInfo/HandContainer
@onready var stable_container: HBoxContainer = $VBoxContainer/ContentRow/StableContainer
@onready var upgrades_row: HBoxContainer = $VBoxContainer/ContentRow/UpgradesRow
@onready var score_label: Label = $VBoxContainer/TopInfo/ScoreLabel
@onready var stable_sep: VSeparator = $VBoxContainer/ContentRow/StableSep
@onready var hand_count_label: Label = $VBoxContainer/TopInfo/HandCountLabel
@onready var avatar_image: TextureRect = $VBoxContainer/TopInfo/AvatarCircle/AvatarImage
@onready var avatar_emoji: Label = $VBoxContainer/TopInfo/AvatarCircle/EmojiLabel

const CARD_BACK_TEXTURE = preload("res://assets/textures/cards/reverso/1_reverso.jpg")

var card_scale: float = 1.0

func _ready():
	update_hand_visuals(0)


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


# Muestra la línea solo si hay ventajas/desventajas (si no, sería una rayita suelta).
func _update_sep():
	if is_instance_valid(stable_sep) and is_instance_valid(upgrades_row):
		stable_sep.visible = upgrades_row.get_child_count() > 0

# Ajusta el tamaño de las cartas (1.0 normal; <1 para muchos jugadores).
func set_card_scale(s: float):
	card_scale = s

func setup(player_name: String, avatar_id: int = 1):
	name_label.text = player_name
	_apply_avatar(avatar_id)
	update_hand_visuals(0) # Empieza vacía

func _apply_avatar(avatar_id: int) -> void:
	var path := _avatar_path(avatar_id)
	if path != "":
		avatar_image.texture = load(path)
		avatar_image.visible = true
		avatar_emoji.visible = false
	else:
		avatar_image.visible = false
		avatar_emoji.visible = true

static func _avatar_path(id: int) -> String:
	for ext in ["svg", "png"]:
		var p := "res://assets/textures/avatars/avatar-%d.%s" % [id, ext]
		if ResourceLoader.exists(p): return p
	return ""

var hand_revealed: bool = false

func update_hand_visuals(count: int):
	if is_instance_valid(hand_count_label):
		hand_count_label.text = "mano: %d" % count
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
	if is_instance_valid(hand_count_label):
		hand_count_label.text = "mano: %d" % card_ids.size()
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
