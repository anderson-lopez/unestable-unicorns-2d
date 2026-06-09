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
		if ip == "127.0.0.1":
			waiting_label.text = "🌐 Sala creada en esta PC.\nOtro jugador en la MISMA red debe usar tu IP local (puerto %d)." % GameManager.PORT
		else:
			waiting_label.text = "🌐 Tu IP local: %s  (puerto %d)\nCompártela con los demás jugadores de tu red." % [ip, GameManager.PORT]
	else:
		waiting_label.text = "Esperando a que el host inicie la partida..."

	# CAMBIO CLAVE: Siempre mostramos las reglas, pero desactivamos edición
	rules_container.visible = true
	
	spin_unicorns.editable = is_host
	check_nursery.disabled = not is_host
	check_double.disabled = not is_host
	if is_instance_valid(spin_multiplier):
		spin_multiplier.editable = is_host

	if is_host:
		_on_rules_ui_changed() # Enviar estado inicial


func _on_rules_ui_changed():
	if not multiplayer.is_server(): return
	
	GameManager.current_rules.unicorns_to_win = int(spin_unicorns.value)
	GameManager.current_rules.nursery_is_safe_zone = check_nursery.button_pressed
	GameManager.current_rules.double_dutch_enabled = check_double.button_pressed
	if is_instance_valid(spin_multiplier):
		GameManager.current_rules.deck_multiplier = int(spin_multiplier.value)

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
