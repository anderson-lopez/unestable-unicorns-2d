extends Control
# Pantalla de apertura del juego.
# - Usa imágenes de res://assets/branding/ si existen (background.* y logo.*).
# - Si no hay imágenes, muestra un fondo y el título por defecto.
# - Dura ~2.5s con fade-in/out y luego entra al Lobby.
# - Se puede saltar tocando la pantalla o pulsando una tecla.
# - En el servidor dedicado (--dedicated) NO se muestra: va directo al Lobby.

const LOBBY_SCENE := "res://scenes/game/Lobby.tscn"
const HOLD_SECONDS := 1.4   # tiempo que se queda fija tras aparecer
const FADE_SECONDS := 0.6

var _done := false
var _fader: ColorRect

func _ready():
	# Servidor dedicado: sin apertura, directo al Lobby (es headless).
	if "--dedicated" in OS.get_cmdline_args() or OS.has_environment("UU_DEDICATED"):
		_go_to_lobby()
		return

	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_visuals()
	_play_intro()

func _build_visuals():
	# Fondo: imagen de branding si existe; si no, color sólido oscuro.
	var bg_path := _first_existing(["res://assets/branding/background.png", "res://assets/branding/background.jpg"])
	if bg_path != "":
		var bg := TextureRect.new()
		bg.texture = load(bg_path)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
	else:
		var solid := ColorRect.new()
		solid.color = Color(0.07, 0.06, 0.12, 1.0)
		solid.set_anchors_preset(Control.PRESET_FULL_RECT)
		solid.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(solid)

	# Centro: logo si existe; si no, título de texto.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var logo_path := _first_existing(["res://assets/branding/logo.png", "res://assets/branding/logo.jpg"])
	if logo_path != "":
		var logo := TextureRect.new()
		logo.texture = load(logo_path)
		logo.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.custom_minimum_size = Vector2(700, 0)
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		center.add_child(logo)
	else:
		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 10)
		var title := Label.new()
		title.text = ""
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title.add_theme_font_size_override("font_size", 52)
		title.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0))
		vb.add_child(title)
		var sub := Label.new()
		sub.text = ""
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 22)
		sub.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		vb.add_child(sub)
		center.add_child(vb)

	# Capa de fundido (negro), por encima de todo, para fade-in/out.
	_fader = ColorRect.new()
	_fader.color = Color(0, 0, 0, 1)
	_fader.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fader.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fader)

func _play_intro():
	var tw := create_tween()
	tw.tween_property(_fader, "color:a", 0.0, FADE_SECONDS)   # aparece
	tw.tween_interval(HOLD_SECONDS)                            # se queda
	tw.tween_property(_fader, "color:a", 1.0, FADE_SECONDS)   # se desvanece
	tw.tween_callback(_go_to_lobby)

# Saltar la apertura con un toque o tecla.
func _input(event):
	if _done:
		return
	if event is InputEventMouseButton and event.pressed:
		_go_to_lobby()
	elif event is InputEventScreenTouch and event.pressed:
		_go_to_lobby()
	elif event is InputEventKey and event.pressed:
		_go_to_lobby()

func _go_to_lobby():
	if _done:
		return
	_done = true
	get_tree().change_scene_to_file(LOBBY_SCENE)

# Devuelve la primera ruta que exista de una lista, o "" si ninguna.
func _first_existing(paths: Array) -> String:
	for p in paths:
		if ResourceLoader.exists(p):
			return p
	return ""
