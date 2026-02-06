extends PanelContainer

@onready var name_label: Label = $VBoxContainer/TopInfo/NameLabel
@onready var hand_container: HBoxContainer = $VBoxContainer/TopInfo/HandContainer
@onready var stable_container: HBoxContainer = $VBoxContainer/StableContainer

# Carga la textura del reverso (La 1 es la estándar para mano)
const CARD_BACK_TEXTURE = preload("res://assets/textures/cards/reverso/1_reverso.jpg")

func setup(player_name: String):
	name_label.text = player_name
	update_hand_visuals(0) # Empieza vacía

func update_hand_visuals(count: int):
	# 1. Borrar lo que había antes
	for child in hand_container.get_children():
		child.queue_free()
	
	# 2. Crear nuevas cartas boca abajo
	for i in range(count):
		var card_back = TextureRect.new()
		card_back.texture = CARD_BACK_TEXTURE
		card_back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		card_back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Tamaño pequeñito para que quepan
		card_back.custom_minimum_size = Vector2(40, 60) 
		
		hand_container.add_child(card_back)

func add_card_to_stable(card_node: Node):
	# Ajustamos el tamaño para que quepan muchas
	if card_node is Control:
		card_node.custom_minimum_size = Vector2(60, 80) # Más pequeñas para rivales
		# card_node.scale = Vector2(0.5, 0.5) # Opcional
		
	stable_container.add_child(card_node)
