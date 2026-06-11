extends PanelContainer

signal card_selected(card_id: int)

@onready var grid: GridContainer = $MarginContainer/VBoxContainer/ScrollContainer/GridContainer
@onready var title_label: Label = $MarginContainer/VBoxContainer/TitleLabel

# Usamos la misma escena de carta visual que ya tienes
const CARD_SCENE = preload("res://scenes/cards/CardUI.tscn")

func _ready():
	hide()

func open_selection(card_ids: Array, title: String):
	title_label.text = title
	
	# 1. Limpiar selección anterior
	for child in grid.get_children():
		child.queue_free()
	
	# 2. Crear cartas seleccionables
	for id in card_ids:
		var data = CardDatabase.get_card_data(id)
		if not data: continue # Seguridad por si acaso
		
		var card = CARD_SCENE.instantiate()
		grid.add_child(card)
		card.setup_card(data)

		# MODO SELECCIÓN: toda la carta es clicable (funciona con mouse Y toque,
		# sin necesidad de hover).
		var cap_id: int = id
		card.enable_pick_mode(func(): _on_card_chosen(cap_id))

	show()

func _on_card_chosen(id: int):
	# Emitimos la elección y cerramos
	card_selected.emit(id)
	hide()
