class_name PlayerData extends RefCounted

# Datos de Red e Identidad
var id: int = 1 # ID de red de Godot (1 = Servidor)
var name: String = "Jugador"

# Estado del Juego
var hand: Array[CardData] = []
var stable: Array[CardData] = []
var is_turn: bool = false

# Constructor
func _init(new_id: int, new_name: String):
	id = new_id
	name = new_name

# Serialización básica para enviar info resumen a otros clientes
# (No enviamos toda la data de las cartas, solo sus IDs para reconstruir)
func get_public_state() -> Dictionary:
	return {
		"id": id,
		"name": name,
		"hand_count": hand.size(), # Los rivales solo necesitan saber CUÁNTAS tienes
		"stable_ids": _get_ids_from_array(stable) # Los rivales SÍ necesitan ver tu establo
	}

func _get_ids_from_array(cards: Array[CardData]) -> Array:
	var ids = []
	for c in cards:
		ids.append(c.id)
	return ids
