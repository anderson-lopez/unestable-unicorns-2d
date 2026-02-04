extends Node

# Almacenamiento principal: ID -> Objeto CardData
# Ejemplo: { 1: <CardData#123>, 2: <CardData#456> }
var database: Dictionary = {}

# Ruta al archivo JSON (ajusta si cambiaste la carpeta)
const JSON_PATH = "res://assets/data/base_deck_data.json"

func _ready():
	# Cargamos los datos apenas arranca el juego
	load_database()

func load_database():
	if not FileAccess.file_exists(JSON_PATH):
		printerr("ERROR CRÍTICO: No se encontró base_deck_data.json en ", JSON_PATH)
		return

	var file = FileAccess.open(JSON_PATH, FileAccess.READ)
	var content = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(content)

	if error != OK:
		printerr("ERROR JSON: Falló el parseo en línea ", json.get_error_line(), ": ", json.get_error_message())
		return

	var data_array = json.data
	
	# Iteramos sobre cada diccionario crudo del JSON
	for card_dict in data_array:
		var new_card = _parse_card_object(card_dict)
		database[new_card.id] = new_card
	
	print("✅ BASE DE DATOS CARGADA: %d cartas procesadas exitosamente." % database.size())

# Función auxiliar para convertir un diccionario JSON en un objeto CardData
func _parse_card_object(data: Dictionary) -> CardData:
	var c = CardData.new()
	
	# 1. META
	c.id = int(data["meta"]["id"])
	c.version = data["meta"]["version"]
	c.image_path = data["meta"]["image_path"]
	
	# 2. IDENTITY
	c.name_es = data["identity"]["name"]["es"]
	c.name_en = data["identity"]["name"]["en"]
	c.type = DataParser.parse_type(data["identity"]["type"])
	
	# Tags es un array de strings, lo copiamos directo
	if "tags" in data["identity"]:
		c.tags.assign(data["identity"]["tags"])
	
	# 3. VISUAL
	c.description_es = data["visual"]["description"]["es"]
	# (Puedes agregar description_en si lo necesitas)
	
	# 4. GAMEPLAY
	c.is_nursery = data["gameplay"]["is_nursery"]
	c.deck_location = data["gameplay"]["deck_location"]
	
	# 5. EFECTOS (Lo más complejo)
	if "effects" in data["gameplay"]:
		for eff_dict in data["gameplay"]["effects"]:
			var effect_obj = _parse_effect_object(eff_dict)
			c.effects.append(effect_obj)
			
	return c

# Función auxiliar para convertir un bloque de efecto JSON en CardEffect
func _parse_effect_object(eff_data: Dictionary) -> CardEffect:
	var e = CardEffect.new()
	
	e.order = int(eff_data["order"])
	e.trigger = DataParser.parse_trigger(eff_data["trigger"])
	
	# Condición (String raw)
	if "condition" in eff_data:
		e.condition = eff_data["condition"]
	
	# --- COSTO ---
	if "cost" in eff_data:
		var cost_data = eff_data["cost"]
		e.cost_required = cost_data["required"]
		e.cost_action = DataParser.parse_action(cost_data["action"])
		e.cost_amount = int(cost_data["amount"])
		e.cost_target_type = DataParser.parse_filter(cost_data["target_type"])
	
	# --- ACCIÓN PRINCIPAL ---
	if "primary_action" in eff_data and eff_data["primary_action"] != null:
		var p_act = eff_data["primary_action"]
		e.primary_action_type = DataParser.parse_action(p_act["type"])
		e.primary_amount = int(p_act.get("amount", 0)) # .get() es seguro si no existe el campo
		e.primary_scope = DataParser.parse_scope(p_act.get("target_scope", "none"))
		e.primary_zone = DataParser.parse_zone(p_act.get("target_zone", "none"))
		e.primary_filter = DataParser.parse_filter(p_act.get("target_filter", "none"))
	
	# --- ACCIÓN SECUNDARIA ---
	if "secondary_action" in eff_data and eff_data["secondary_action"] != null:
		var s_act = eff_data["secondary_action"]
		e.has_secondary = true
		e.secondary_action_type = DataParser.parse_action(s_act["type"])
		e.secondary_amount = int(s_act.get("amount", 0))
		e.secondary_scope = DataParser.parse_scope(s_act.get("target_scope", "none"))
		e.secondary_zone = DataParser.parse_zone(s_act.get("target_zone", "none"))
		e.secondary_filter = DataParser.parse_filter(s_act.get("target_filter", "none"))
		
	return e

# Función pública para obtener datos
func get_card_data(id: int) -> CardData:
	if id in database:
		return database[id]
	printerr("CardDatabase: ID no encontrado -> ", id)
	return null
