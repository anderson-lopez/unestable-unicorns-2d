class_name GameRules extends Resource

# --- CONFIGURACIÓN DE VICTORIA ---
@export var unicorns_to_win: int = 7 # Por defecto 7
@export var double_dutch_enabled: bool = false # Si se permite jugar 2 cartas por defecto

# --- CONFIGURACIÓN DE BEBÉS ---
# Si "matar" bebés es enviarlos a la guardería (true) o eliminarlos del juego (false)
@export var nursery_is_safe_zone: bool = true 
@export var starting_baby_count: int = 1

# --- LIMITES ---
@export var hand_limit: int = 7
@export var deck_count: int = 1 # Cuantos mazos se usan (para muchas personas)

# Copias de CADA carta del mazo (1 = normal; 2-5 = duplicar..quintuplicar).
# Multiplica TODO por igual (unicornios incluidos) para conservar las proporciones
# del juego y dar cartas de sobra con muchos jugadores. Los bebés (guardería) y la
# carta de referencia NO se multiplican.
@export var deck_multiplier: int = 1

# Función para convertir esto a un Diccionario y pasarlo por red
func to_dictionary() -> Dictionary:
	return {
		"unicorns_to_win": unicorns_to_win,
		"double_dutch_enabled": double_dutch_enabled,
		"nursery_is_safe_zone": nursery_is_safe_zone,
		"starting_baby_count": starting_baby_count,
		"hand_limit": hand_limit,
		"deck_multiplier": deck_multiplier
	}

# Función para cargar desde diccionario (cuando el Cliente recibe las reglas)
func from_dictionary(dict: Dictionary):
	unicorns_to_win = dict.get("unicorns_to_win", 7)
	double_dutch_enabled = dict.get("double_dutch_enabled", false)
	nursery_is_safe_zone = dict.get("nursery_is_safe_zone", true)
	starting_baby_count = dict.get("starting_baby_count", 1)
	hand_limit = dict.get("hand_limit", 7)
	deck_multiplier = dict.get("deck_multiplier", 1)
