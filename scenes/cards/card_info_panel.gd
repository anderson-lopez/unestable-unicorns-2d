class_name CardInfoPanel extends PanelContainer

# Referencias a los nodos (Asegúrate de respetar la jerarquía que creamos)
@onready var big_image: TextureRect = $MarginContainer/HBoxContainer/BigCardImage
@onready var title_label: Label = $MarginContainer/HBoxContainer/InfoColumn/Header/TitleLabel
@onready var close_button: Button = $MarginContainer/HBoxContainer/InfoColumn/Header/CloseButton
@onready var type_label: Label = $MarginContainer/HBoxContainer/InfoColumn/TypeLabel
@onready var desc_label: RichTextLabel = $MarginContainer/HBoxContainer/InfoColumn/DescriptionLabel
@onready var tags_label: Label = $MarginContainer/HBoxContainer/InfoColumn/TagsLabel

func _ready():
	# Conectar cerrar
	close_button.pressed.connect(hide)
	hide() # Nace oculto

func show_card_info(data: CardData):
	# 1. Datos Básicos
	title_label.text = data.name_es
	type_label.text = _get_pretty_type(data.type)
	
	# 2. Descripción con formato
	desc_label.text = _format_description(data.description_es)
	
	# 3. Tags (unimos el array de strings con comas)
	if data.tags.is_empty():
		tags_label.text = ""
	else:
		tags_label.text = "Tags: " + ", ".join(data.tags)
	
	# 4. Imagen Grande
	if ResourceLoader.exists(data.image_path):
		big_image.texture = load(data.image_path)
	
	# 5. Animación de entrada (Pop)
	show()
	pivot_offset = size / 2
	scale = Vector2(0.9, 0.9)
	var tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

# Traducir Enum a Texto para el jugador
func _get_pretty_type(type: GameEnums.CardType) -> String:
	match type:
		GameEnums.CardType.BABY_UNICORN: return "🦄 Bebé Unicornio"
		GameEnums.CardType.BASIC_UNICORN: return "🐴 Unicornio Básico"
		GameEnums.CardType.MAGICAL_UNICORN: return "✨ Unicornio Mágico"
		GameEnums.CardType.MAGIC_SPELL: return "🪄 Magia"
		GameEnums.CardType.INSTANT: return "🚫 Relincho (Instantáneo)"
		GameEnums.CardType.UPGRADE: return "⬆️ Mejora"
		GameEnums.CardType.DOWNGRADE: return "⬇️ Degradación"
		_: return "Carta Desconocida"

func _format_description(text: String) -> String:
	# Colores para palabras clave
	var t = text.replace("DESTRUYE", "[b][color=#FF4500]DESTRUYE[/color][/b]")
	t = t.replace("SACRIFICAR", "[b][color=#8B0000]SACRIFICA[/color][/b]")
	t = t.replace("ROBAR", "[b][color=#008000]ROBA[/color][/b]")
	t = t.replace("DESCARTAR", "[b][color=#555555]DESCARTA[/color][/b]")
	t = t.replace("HURTAR", "[b][color=#800080]HURTAR[/color][/b]") # Steal
	return "[font_size=18]" + t + "[/font_size]"
