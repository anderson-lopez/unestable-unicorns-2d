extends Control

# --- REFERENCIAS UI (CONECTAR DESDE EL EDITOR) ---
@onready var login_panel: CenterContainer = %LoginPanel
@onready var lobby_panel: HBoxContainer = %LobbyPanel

# Inputs Login
@onready var name_input: LineEdit = %NameInput
@onready var ip_input: LineEdit = %IpInput
@onready var host_btn: Button = %HostBtn
@onready var join_btn: Button = %JoinBtn
@onready var status_label: Label = %StatusLabel

# Lobby UI
@onready var player_list_container: VBoxContainer = %PlayerListContainer
@onready var start_game_btn: Button = %StartGameBtn
@onready var waiting_label: Label = %WaitingLabel

# Rules UI (Solo visibles para el Host)
@onready var rules_container: VBoxContainer = %RulesContainer
@onready var spin_unicorns: SpinBox = %SpinUnicorns
@onready var check_nursery: CheckBox = %CheckNursery
@onready var check_double: CheckBox = %CheckDouble

# Control creado por código: multiplicador de copias de cartas de acción.
var spin_multiplier: SpinBox
# Selector de tiempo por turno (0 = infinito). Valores en segundos.
var opt_turn_time: OptionButton
const TURN_TIME_LABELS := ["∞ Infinito", "30 seg", "45 seg", "1 min", "1.5 min", "2 min", "3 min", "5 min"]
const TURN_TIME_VALUES := [0, 30, 45, 60, 90, 120, 180, 300]
# Botón para copiar la IP del host al portapapeles (útil en móvil).
var _copy_ip_btn: Button

# Plantilla para la fila de jugador (lo crearemos por código para no ensuciar)
var player_item_style = StyleBoxFlat.new()

func _ready():
	# Configurar estilo básico de items de lista
	player_item_style.bg_color = Color("2b2b2b")
	player_item_style.set_corner_radius_all(5)
	player_item_style.content_margin_left = 10
	player_item_style.content_margin_right = 10
	player_item_style.content_margin_top = 5
	player_item_style.content_margin_bottom = 5

	# Estado inicial
	login_panel.show()
	lobby_panel.hide()
	status_label.text = ""

	# Pista de IP: por defecto la misma máquina (cómodo para probar en una sola PC).
	if ip_input.text.strip_edges().is_empty():
		ip_input.text = "127.0.0.1"
	ip_input.placeholder_text = "IP del host (vacío = misma PC)"
	# Teclado virtual adecuado en móvil (con números y puntos).
	ip_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	
	# Conexiones de botones locales
	host_btn.pressed.connect(_on_host_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_game_btn.pressed.connect(_on_start_pressed)
	
	# Conexiones con GameManager (Señales globales)
	GameManager.player_connected.connect(_refresh_player_list)
	GameManager.player_disconnected.connect(_refresh_player_list)
	GameManager.game_error.connect(_on_error)
	GameManager.game_started.connect(_on_game_started)
	# Cuando llegan reglas nuevas del host, actualizar la UI del cliente
	GameManager.rules_updated.connect(_update_ui_from_manager)

	# El host emite cambios de reglas en vivo
	spin_unicorns.value_changed.connect(func(_v): _on_rules_ui_changed())
	check_nursery.toggled.connect(func(_b): _on_rules_ui_changed())
	check_double.toggled.connect(func(_b): _on_rules_ui_changed())

	# Control extra (por código): multiplicador de copias de cartas de acción.
	_build_multiplier_control()

	# Botón + pantalla de juego ONLINE (salas con código). Todo por código.
	_build_online_button()
	_build_online_overlay()
	# Señales del servidor de salas
	OnlineServer.room_joined.connect(_on_room_joined)
	OnlineServer.room_players_updated.connect(_on_room_players_updated)
	OnlineServer.room_error.connect(_on_online_error)
	OnlineServer.room_game_started.connect(_on_room_game_started)

# URL del servidor online.
#  - PRODUCCIÓN (Render): wss:// y SIN puerto (Render expone el 443 por fuera).
#  - LOCAL (pruebas): comenta la de Render y descomenta la local con tu servidor --dedicated.
const ONLINE_SERVER_URL := "wss://unstable-unicorns-server.onrender.com"
#const ONLINE_SERVER_URL := "ws://127.0.0.1:7777" # ← para probar en tu PC

var _online_layer: CanvasLayer
var _online_panel: PanelContainer
var _online_status: Label
var _online_code_input: LineEdit
var _online_room_box: VBoxContainer
var _online_code_label: Label
var _online_players_box: VBoxContainer
var _online_start_btn: Button
var _online_connected := false

func _build_online_button():
	# Lo añadimos junto a los botones de login (mismo contenedor que HostBtn).
	var btn := Button.new()
	btn.text = "🌐 JUGAR ONLINE (código de sala)"
	btn.pressed.connect(_open_online)
	host_btn.get_parent().add_child(btn)

func _open_online():
	if name_input.text.strip_edges().is_empty():
		status_label.text = "¡Necesitas un nombre!"
		return
	_online_layer.visible = true
	_online_room_box.visible = false
	_online_status.text = "Conectando al servidor..."
	# Modo online: el registro de jugadores lo gestiona la sala, no el flujo local.
	GameManager.online_mode = true
	OnlineServer.connect_to_server(ONLINE_SERVER_URL)
	# Damos un momento y mostramos los controles de crear/unirse.
	await get_tree().create_timer(0.4).timeout
	_online_connected = true
	_online_status.text = "Conectado. Crea una sala o únete con un código."

func _build_online_overlay():
	_online_layer = CanvasLayer.new()
	_online_layer.layer = 30
	_online_layer.visible = false
	add_child(_online_layer)

	# Fondo oscuro semitransparente
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_online_layer.add_child(bg)

	_online_panel = PanelContainer.new()
	_online_panel.anchor_left = 0.5; _online_panel.anchor_right = 0.5
	_online_panel.anchor_top = 0.5; _online_panel.anchor_bottom = 0.5
	_online_panel.offset_left = -260; _online_panel.offset_right = 260
	_online_panel.offset_top = -230; _online_panel.offset_bottom = 230
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.10, 0.14, 1.0)
	sb.set_corner_radius_all(12); sb.set_border_width_all(3)
	sb.border_color = Color(0.5, 0.5, 0.6); sb.set_content_margin_all(18)
	_online_panel.add_theme_stylebox_override("panel", sb)
	_online_layer.add_child(_online_panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_online_panel.add_child(v)

	var title := Label.new()
	title.text = "🌐 Jugar Online"
	title.add_theme_font_size_override("font_size", 24)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	_online_status = Label.new()
	_online_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_online_status)

	# Crear sala
	var create_btn := Button.new()
	create_btn.text = "➕ Crear sala"
	create_btn.custom_minimum_size = Vector2(0, 44)
	create_btn.pressed.connect(_on_create_room)
	v.add_child(create_btn)

	v.add_child(_hsep())

	# Unirse con código
	_online_code_input = LineEdit.new()
	_online_code_input.placeholder_text = "Código de sala (ej. ABCD)"
	_online_code_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_code_input.max_length = 6
	v.add_child(_online_code_input)
	var join_btn := Button.new()
	join_btn.text = "🚪 Unirse con código"
	join_btn.custom_minimum_size = Vector2(0, 44)
	join_btn.pressed.connect(_on_join_room)
	v.add_child(join_btn)

	# Vista de SALA (oculta hasta crear/unirse)
	_online_room_box = VBoxContainer.new()
	_online_room_box.add_theme_constant_override("separation", 8)
	_online_room_box.visible = false
	v.add_child(_online_room_box)

	_online_code_label = Label.new()
	_online_code_label.add_theme_font_size_override("font_size", 26)
	_online_code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_online_room_box.add_child(_online_code_label)

	_online_players_box = VBoxContainer.new()
	_online_room_box.add_child(_online_players_box)

	_online_start_btn = Button.new()
	_online_start_btn.text = "¡INICIAR PARTIDA!"
	_online_start_btn.custom_minimum_size = Vector2(0, 44)
	_online_start_btn.pressed.connect(func(): OnlineServer.start_room())
	_online_room_box.add_child(_online_start_btn)

	var close_btn := Button.new()
	close_btn.text = "Volver"
	close_btn.pressed.connect(func(): _online_layer.visible = false)
	v.add_child(close_btn)

func _hsep() -> HSeparator:
	return HSeparator.new()

func _on_create_room():
	if not _online_connected:
		_online_status.text = "Aún no conectado al servidor."
		return
	OnlineServer.create_room(name_input.text)

func _on_join_room():
	if not _online_connected:
		_online_status.text = "Aún no conectado al servidor."
		return
	var code := _online_code_input.text.strip_edges().to_upper()
	if code.is_empty():
		_online_status.text = "Escribe un código de sala."
		return
	OnlineServer.join_room(code, name_input.text)

func _on_room_joined(code: String, players: Array):
	_online_status.text = "¡En la sala!"
	_online_room_box.visible = true
	_online_code_label.text = "Código: %s" % code
	_render_online_players(players)

func _on_room_players_updated(players: Array):
	_render_online_players(players)

func _render_online_players(players: Array):
	for c in _online_players_box.get_children(): c.queue_free()
	var is_host := false
	var my_id := multiplayer.get_unique_id()
	for p in players:
		var lbl := Label.new()
		lbl.text = p["name"] + ("  (HOST)" if p.get("host", false) else "") + ("  (TÚ)" if p["id"] == my_id else "")
		_online_players_box.add_child(lbl)
		if p["id"] == my_id and p.get("host", false):
			is_host = true
	_online_start_btn.visible = is_host

func _on_online_error(message: String):
	_online_status.text = "⚠ " + message

func _on_room_game_started(_code: String):
	# El servidor ya nos registró en la partida; cargamos la mesa.
	# (Cliente: NO somos autoridad; solo recibimos los RPCs visuales del servidor.)
	_online_status.text = "¡La partida va a comenzar!"
	GameManager.is_game_active = true
	get_tree().change_scene_to_file("res://scenes/game/GameTable.tscn")

# Crea el selector de multiplicador (x1..x5) dentro del panel de reglas.
func _build_multiplier_control():
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Copias del mazo (x):"
	hb.add_child(lbl)
	spin_multiplier = SpinBox.new()
	spin_multiplier.min_value = 1
	spin_multiplier.max_value = 5
	spin_multiplier.step = 1
	spin_multiplier.value = 1
	spin_multiplier.tooltip_text = "Multiplica TODO el mazo por igual (unicornios, magias, relinchos, ventajas...)\npara que no falten cartas con muchos jugadores. x1 = mazo normal."
	spin_multiplier.value_changed.connect(func(_v): _on_rules_ui_changed())
	hb.add_child(spin_multiplier)
	rules_container.add_child(hb)
	_build_turn_time_control()

# Selector del tiempo por turno (de Infinito a varios minutos).
func _build_turn_time_control():
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = "Tiempo por turno:"
	hb.add_child(lbl)
	opt_turn_time = OptionButton.new()
	for i in range(TURN_TIME_LABELS.size()):
		opt_turn_time.add_item(TURN_TIME_LABELS[i], i)
	opt_turn_time.selected = 0 # Infinito por defecto
	opt_turn_time.tooltip_text = "Si se acaba el tiempo, el turno pasa automáticamente.\nInfinito = sin límite."
	opt_turn_time.item_selected.connect(func(_i): _on_rules_ui_changed())
	hb.add_child(opt_turn_time)
	rules_container.add_child(hb)

func _turn_time_value() -> int:
	if is_instance_valid(opt_turn_time):
		var idx: int = clampi(opt_turn_time.selected, 0, TURN_TIME_VALUES.size() - 1)
		return TURN_TIME_VALUES[idx]
	return 0

# --- BOTONES DE LOGIN ---

func _on_host_pressed():
	if name_input.text.strip_edges().is_empty():
		status_label.text = "¡Necesitas un nombre!"
		return
	
	status_label.text = "Creando sala..."
	_lock_buttons()
	
	# Crear reglas basadas en los inputs (aunque el host las puede cambiar luego)
	var rules = GameRules.new()
	# Aquí podríamos leer los valores iniciales de la UI si quisieras
	
	GameManager.host_game(name_input.text, rules)
	_go_to_lobby(true) # Es Host

func _on_join_pressed():
	if name_input.text.strip_edges().is_empty():
		status_label.text = "¡Necesitas un nombre!"
		return
		
	status_label.text = "Conectando..."
	_lock_buttons()
	GameManager.join_game(name_input.text, ip_input.text)
	_go_to_lobby(false) # Es Cliente

# --- TRANSICIONES ---

func _lock_buttons():
	host_btn.disabled = true
	join_btn.disabled = true

func _go_to_lobby(is_host: bool):
	login_panel.hide()
	lobby_panel.show()

	start_game_btn.visible = is_host

	# El host ve su IP local para compartirla; el cliente ve "esperando...".
	waiting_label.visible = true
	if is_host:
		var ip := GameManager.get_local_ip()
		waiting_label.text = "🌐 Tu IP: %s  (puerto %d)\nCompártela con los jugadores de tu MISMA red WiFi." % [ip, GameManager.PORT]
		_add_copy_ip_button(ip)
	else:
		waiting_label.text = "Esperando a que el host inicie la partida..."

	# CAMBIO CLAVE: Siempre mostramos las reglas, pero desactivamos edición
	rules_container.visible = true
	
	spin_unicorns.editable = is_host
	check_nursery.disabled = not is_host
	check_double.disabled = not is_host
	if is_instance_valid(spin_multiplier):
		spin_multiplier.editable = is_host
	if is_instance_valid(opt_turn_time):
		opt_turn_time.disabled = not is_host

	if is_host:
		_on_rules_ui_changed() # Enviar estado inicial


# Crea (una sola vez) un botón que copia la IP del host al portapapeles.
func _add_copy_ip_button(ip: String):
	if is_instance_valid(_copy_ip_btn):
		_copy_ip_btn.queue_free()
	_copy_ip_btn = Button.new()
	_copy_ip_btn.text = "📋 Copiar IP (%s)" % ip
	_copy_ip_btn.pressed.connect(func():
		DisplayServer.clipboard_set(ip)
		_copy_ip_btn.text = "✓ IP copiada: %s" % ip
	)
	var parent = waiting_label.get_parent()
	parent.add_child(_copy_ip_btn)
	parent.move_child(_copy_ip_btn, waiting_label.get_index() + 1)

func _on_rules_ui_changed():
	if not multiplayer.is_server(): return
	
	GameManager.current_rules.unicorns_to_win = int(spin_unicorns.value)
	GameManager.current_rules.nursery_is_safe_zone = check_nursery.button_pressed
	GameManager.current_rules.double_dutch_enabled = check_double.button_pressed
	if is_instance_valid(spin_multiplier):
		GameManager.current_rules.deck_multiplier = int(spin_multiplier.value)
	GameManager.current_rules.turn_time_seconds = _turn_time_value()

	# Si agregaste la función update_rules_broadcast en GameManager, úsala:
	if GameManager.has_method("update_rules_broadcast"):
		GameManager.update_rules_broadcast()

func _update_ui_from_manager():
	# Evitamos bucles: Si soy host, mi UI ya tiene la verdad
	if multiplayer.is_server(): return 
	
	var r = GameManager.current_rules
	spin_unicorns.value = r.unicorns_to_win
	check_nursery.button_pressed = r.nursery_is_safe_zone
	check_double.button_pressed = r.double_dutch_enabled
	if is_instance_valid(spin_multiplier):
		spin_multiplier.value = r.deck_multiplier
	if is_instance_valid(opt_turn_time):
		opt_turn_time.selected = max(0, TURN_TIME_VALUES.find(r.turn_time_seconds))

# --- ACTUALIZACIÓN DE LISTA DE JUGADORES ---

func _refresh_player_list(_data = null): # El argumento _data es opcional por la señal
	# Limpiar lista
	for child in player_list_container.get_children():
		child.queue_free()
	
	# Reconstruir lista desde GameManager.players
	for p_id in GameManager.players:
		var p_data = GameManager.players[p_id]
		var label = Label.new()
		label.text = p_data.name
		if p_id == 1: label.text += " (HOST)"
		if p_id == multiplayer.get_unique_id(): label.text += " (TÚ)"
		
		# Estilo bonito
		var panel = PanelContainer.new()
		panel.add_theme_stylebox_override("panel", player_item_style)
		panel.add_child(label)
		
		player_list_container.add_child(panel)

# --- MANEJO DE REGLAS (SOLO HOST) ---

func _on_rules_changed():
	if not multiplayer.is_server(): return
	_update_rules_from_ui()
	# Aquí podrías enviar un RPC para actualizar la UI de los clientes en tiempo real

func _update_rules_from_ui():
	GameManager.current_rules.unicorns_to_win = int(spin_unicorns.value)
	GameManager.current_rules.nursery_is_safe_zone = check_nursery.button_pressed
	GameManager.current_rules.double_dutch_enabled = check_double.button_pressed
	if is_instance_valid(spin_multiplier):
		GameManager.current_rules.deck_multiplier = int(spin_multiplier.value)
	# Nota: Falta implementar la sincronización en tiempo real de reglas hacia clientes
	# Por ahora se envían al conectar.

# --- INICIO ---

func _on_start_pressed():
	if GameManager.players.size() < 2:
		waiting_label.visible = true
		waiting_label.text = "⚠ Necesitas al menos 2 jugadores conectados para empezar."
		return

	_update_rules_from_ui()
	
	# 2. Ahora sí, avisar al GameManager para que envíe las reglas actualizadas a todos
	if GameManager.has_method("update_rules_broadcast"):
		GameManager.update_rules_broadcast()
	
	# 3. Arrancar la partida
	GameManager.start_game()

func _on_game_started():
	# AQUÍ CAMBIARÍAS A LA ESCENA DE LA MESA DE JUEGO
	print("Lobby: El juego ha iniciado. Cambiando escena...")
	# get_tree().change_scene_to_file("res://scenes/game/GameTable.tscn")
	# Nota: Por ahora solo imprime para no romper nada si no tienes la escena lista

func _on_error(msg):
	status_label.text = "Error: " + msg
	host_btn.disabled = false
	join_btn.disabled = false
	login_panel.show()
	lobby_panel.hide()
