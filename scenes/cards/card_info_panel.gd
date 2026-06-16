class_name CardInfoPanel extends PanelContainer

# Referencias a los nodos (Asegúrate de respetar la jerarquía que creamos)
@onready var big_image: TextureRect = $MarginContainer/HBoxContainer/BigCardImage
@onready var title_label: Label = $MarginContainer/HBoxContainer/InfoColumn/Header/TitleLabel
@onready var close_button: Button = $MarginContainer/HBoxContainer/InfoColumn/Header/CloseButton
@onready var type_label: Label = $MarginContainer/HBoxContainer/InfoColumn/TypeLabel
@onready var desc_label: RichTextLabel = $MarginContainer/HBoxContainer/InfoColumn/DescriptionLabel
@onready var tags_label: Label = $MarginContainer/HBoxContainer/InfoColumn/TagsLabel

# Contenedor de "chips" de etiquetas (creado por código, debajo del rótulo).
var _tags_box: HFlowContainer

# Conectores/ruido que NO mostramos como chip.
const TAG_SKIP := {"a": true, "of": true, "on": true, "the": true, "with": true, "up": true, "back": true}

# Etiquetas de COLOR (vienen como "(red)", "(blue)"...): se pintan con su color real.
const TAG_COLORS := {
	"red": Color(0.85, 0.30, 0.30), "blue": Color(0.35, 0.55, 0.90), "green": Color(0.45, 0.75, 0.40),
	"yellow": Color(0.85, 0.72, 0.25), "orange": Color(0.90, 0.55, 0.25), "purple": Color(0.62, 0.42, 0.82),
	"pink": Color(0.90, 0.50, 0.72), "black": Color(0.40, 0.40, 0.48), "white": Color(0.80, 0.80, 0.88),
	"brown": Color(0.60, 0.42, 0.30), "indigo": Color(0.45, 0.38, 0.74), "rainbow": Color(0.80, 0.50, 0.90),
}

# Traducción de etiquetas al español. Las que no estén aquí se "embellecen" solas.
const TAG_ES := {
	"queen": "Reina", "bee": "Abeja", "unicorn": "Unicornio", "basic": "Básico", "magical": "Mágico",
	"baby": "Bebé", "extremely": "Extremo", "destructive": "Destructivo", "destruction": "Destrucción",
	"narwhal": "Narval", "poison": "Veneno", "flying": "Volador", "ginormous": "Gigantesco",
	"glitter": "Purpurina", "bomb": "Bomba", "blinding": "Cegadora", "light": "Luz", "dark": "Oscuro",
	"kittencorn": "Gaticornio", "llamacorn": "Llamacornio", "rhinocorn": "Rinocornio", "mermaid": "Sirena",
	"shark": "Tiburón", "phoenix": "Fénix", "angel": "Ángel", "necromancer": "Nigromante", "oracle": "Oráculo",
	"mother": "Madre", "majestic": "Majestuoso", "mystical": "Místico", "classy": "Elegante", "shabby": "Andrajoso",
	"swift": "Veloz", "greedy": "Codicioso", "seductive": "Seductor", "alluring": "Atrayente", "annoying": "Molesto",
	"stabby": "Apuñalador", "knight": "Caballero", "goose": "Ganso", "caffeine": "Cafeína", "americorn": "Americornio",
	"neigh": "Relincho", "super": "Súper", "yay": "Yay", "slowdown": "Ralentización", "pandamonium": "Pandemónium",
	"aura": "Aura", "barbed": "Púas", "wire": "Alambre", "tiny": "Diminuto", "stable": "Establo",
	"nanny": "Niñera", "cam": "Cámara", "good": "Buen", "deal": "Trato", "bargain": "Ganga", "shake": "Agitar",
	"double": "Doble", "dutch": "Holandesa", "swap": "Intercambio", "change": "Cambio", "luck": "Suerte",
	"kiss": "Beso", "life": "Vida", "ritual": "Ritual", "sadistic": "Sádico", "unfair": "Injusto", "targeted": "Dirigido",
	"blatant": "Descarado", "thievery": "Robo", "reset": "Reinicio", "button": "Botón", "re-target": "Recalibrar",
	"two-for-one": "Dos por uno", "tornado": "Tornado", "vortex": "Vórtice", "torpedo": "Torpedo", "overload": "Sobrecarga",
	"chainsaw": "Motosierra", "machine": "Máquina", "artillery": "Artillería", "claw": "Garra", "horn": "Cuerno",
	"lasso": "Lazo", "kick": "Patada", "cob": "Mazorca", "broken": "Roto", "great": "Gran", "majesty": "Majestad",
	"rule_card": "Carta de regla", "rainbow": "Arcoíris",
}

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
	
	# 3. Etiquetas como "chips" de color, en español.
	_ensure_tags_box()
	for c in _tags_box.get_children():
		c.queue_free()
	if data.tags.is_empty():
		tags_label.visible = false
		_tags_box.visible = false
	else:
		tags_label.visible = true
		tags_label.text = "Etiquetas:"
		_tags_box.visible = true
		for raw in data.tags:
			var clean := str(raw).strip_edges().to_lower().trim_prefix("(").trim_suffix(")")
			if clean.is_empty() or TAG_SKIP.has(clean):
				continue
			_tags_box.add_child(_make_chip(clean, data.type))
	
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

# Crea (una vez) el contenedor de chips, justo debajo del rótulo "Etiquetas:".
func _ensure_tags_box():
	if _tags_box and is_instance_valid(_tags_box):
		return
	_tags_box = HFlowContainer.new()
	_tags_box.add_theme_constant_override("h_separation", 6)
	_tags_box.add_theme_constant_override("v_separation", 6)
	var parent := tags_label.get_parent()
	parent.add_child(_tags_box)
	parent.move_child(_tags_box, tags_label.get_index() + 1)

# Un "chip" redondeado con borde de color y texto en español.
func _make_chip(tag_clean: String, card_type: GameEnums.CardType) -> Control:
	var es: String = TAG_ES.get(tag_clean, _prettify(tag_clean))
	var base: Color = TAG_COLORS.get(tag_clean, _type_color(card_type))
	var chip := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(base.r, base.g, base.b, 0.25)
	sb.border_color = base
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.content_margin_left = 9
	sb.content_margin_right = 9
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = es
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", base.lightened(0.55))
	chip.add_child(lbl)
	return chip

# Embellece una etiqueta sin traducción: guiones/underscores → espacios, Capitalizado.
func _prettify(s: String) -> String:
	return s.replace("-", " ").replace("_", " ").capitalize()

# Color de respaldo para chips no-color: el color del tipo de carta.
func _type_color(card_type: GameEnums.CardType) -> Color:
	match card_type:
		GameEnums.CardType.INSTANT: return Color("#ff4034")
		GameEnums.CardType.MAGIC_SPELL: return Color("#8ed247")
		GameEnums.CardType.MAGICAL_UNICORN: return Color("#54b0e5")
		GameEnums.CardType.UPGRADE: return Color("#f8752e")
		GameEnums.CardType.DOWNGRADE: return Color("#fbcb44")
		GameEnums.CardType.BABY_UNICORN: return Color("#c05e97")
		GameEnums.CardType.BASIC_UNICORN: return Color("#8a82c0")
		_: return Color("#9aa0b5")
