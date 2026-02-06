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
		
		# Configuramos la carta
		card.setup_card(data)
		
		# --- MODO SELECCIÓN ---
		# Cambiamos el texto del botón
		card.play_button.text = "ELEGIR"
		# Ocultamos el botón descartar (no tiene sentido aquí)
		card.discard_button.hide()
		
		# CONEXIÓN INTELIGENTE:
		# No tocamos las señales internas del botón.
		# Simplemente escuchamos cuando la carta dice "Hey, quieren jugarme"
		card.play_requested.connect(func(_card_ui): _on_card_chosen(id))

	show()

func _on_card_chosen(id: int):
	# Emitimos la elección y cerramos
	card_selected.emit(id)
	hide()
