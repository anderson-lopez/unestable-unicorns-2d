extends PanelContainer

@onready var name_label: Label = $VBoxContainer/TopInfo/NameLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/TopInfo/HandContainer
@onready var stable_container: HBoxContainer = $VBoxContainer/StableContainer

# Carga la textura del reverso (La 1 es la estándar para mano)
const CARD_BACK_TEXTURE = preload("res://assets/textures/cards/reverso/1_reverso.jpg")

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
		card_back.custom_minimum_size = Vector2(40, 60)
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
		tex.custom_minimum_size = Vector2(44, 64)
		hand_container.add_child(tex)

func hide_hand_reveal(count: int):
	hand_revealed = false
	update_hand_visuals(count)

func add_card_to_stable(card_node: Node):
	# Ajustamos el tamaño para que quepan muchas
	if card_node is Control:
		card_node.custom_minimum_size = Vector2(60, 80) # Más pequeñas para rivales
		# card_node.scale = Vector2(0.5, 0.5) # Opcional

	stable_container.add_child(card_node)

# Elimina visualmente una carta del establo del rival por su card_id.
# Los nodos se nombran "Stable_<player>_<card_id>", así que comparamos el
# último segmento del nombre.
func remove_card_from_stable(card_id: int):
	for child in stable_container.get_children():
		var parts = str(child.name).split("_")
		if parts.size() > 0 and parts[parts.size() - 1] == str(card_id):
			var tw = child.create_tween()
			tw.tween_property(child, "modulate:a", 0.0, 0.2)
			tw.tween_callback(child.queue_free)
			return
