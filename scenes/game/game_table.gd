extends Control

# --- CONFIGURACIÓN ---
# Precargamos la "plantilla" visual de la carta
const CARD_SCENE = preload("res://scenes/cards/CardUI.tscn")

# --- REFERENCIAS ---
@onready var cards_container: HBoxContainer = $HandZone/CardsContainer
# Buscamos el panel dentro del CanvasLayer para asegurar que esté encima
@onready var info_panel: CardInfoPanel = $UILayer/CardInfoPanel

# Botones de Debug (Conéctalos desde el editor o por código)
@onready var btn_add_random: Button = $DebugUI/BtnAddRandom
@onready var btn_add_magic: Button = $DebugUI/BtnAddMagic

func _ready():
	# Conectamos botones de prueba
	btn_add_random.pressed.connect(_spawn_random_card)
	btn_add_magic.pressed.connect(_spawn_magic_card)
	
	# Test inicial: Crear 5 cartas aleatorias al iniciar
	print("--- INICIANDO MESA DE JUEGO ---")
	for i in range(5):
		_spawn_random_card()

# --- LÓGICA DE SPAWN (Core del Sistema) ---
func add_card_to_hand(card_id: int):
	# 1. Obtener Data Lógica
	var data = CardDatabase.get_card_data(card_id)
	if not data:
		printerr("Error: Intentando crear carta con ID inexistente: ", card_id)
		return

	# 2. Instanciar Visual
	var new_card = CARD_SCENE.instantiate()
	
	# 3. Agregar al Árbol de Nodos (Primero agregamos, luego configuramos)
	cards_container.add_child(new_card)
	
	# 4. Inyectar Datos
	new_card.setup_card(data)
	new_card.name = "Card_%d" % card_id # Nombre único en el inspector para debug
	
	# 5. CONEXIÓN DE SEÑALES (El cableado vital)
	# Cuando la carta pida info, abrimos el panel
	new_card.info_requested.connect(_on_card_info_requested)
	# Cuando la carta pida jugar/descartar, ejecutamos lógica de juego
	new_card.play_requested.connect(_on_card_play_requested)
	new_card.discard_requested.connect(_on_card_discard_requested)
	
	print("Carta creada: ", data.name_es)

# --- MANEJADORES DE SEÑALES (Signal Handlers) ---

func _on_card_info_requested(data: CardData):
	# ¡Aquí conectamos la Carta con el Modal!
	print("Abriendo info para: ", data.name_es)
	info_panel.show_card_info(data)

func _on_card_play_requested(card_ui: CardUI):
	print("JUGAR carta: ", card_ui.card_data.name_es)
	# AQUÍ IRÍA LA LÓGICA REAL DEL JUEGO:
	# 1. Verificar si tengo maná/acciones
	# 2. Mover carta de HandZone a StableZone
	# 3. Ejecutar efectos del JSON
	
	# Por ahora, simulamos que se juega eliminándola de la mano visualmente
	var tween = create_tween()
	tween.tween_property(card_ui, "scale", Vector2(0,0), 0.2) # Efecto "puff"
	tween.tween_callback(card_ui.queue_free)

func _on_card_discard_requested(card_ui: CardUI):
	print("DESCARTAR carta: ", card_ui.card_data.name_es)
	# Lógica: Mover al DiscardPile
	card_ui.queue_free()

# --- FUNCIONES DE DEBUG ---
func _spawn_random_card():
	# Elegimos un ID al azar de los que existen en tu JSON (IDs del 1 al 85)
	# Nota: CardDatabase.database.keys() nos da todos los IDs válidos
	var all_ids = CardDatabase.database.keys()
	if all_ids.is_empty(): return
	var random_id = all_ids.pick_random()
	add_card_to_hand(random_id)

func _spawn_magic_card():
	# Busca una carta específica (ej: ID 3 Veneno) para probar tipos
	add_card_to_hand(3)
