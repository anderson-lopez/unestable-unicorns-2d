class_name CardData extends RefCounted

# META
var id: int
var version: String
var image_path: String

# IDENTITY
var name_es: String
var name_en: String
var type: GameEnums.CardType
var tags: Array[String] = []

# VISUAL
var description_es: String

# GAMEPLAY
var is_nursery: bool = false
var deck_location: String = "main_deck"
var effects: Array[CardEffect] = []

# Función de ayuda para saber si es un unicornio
func is_unicorn() -> bool:
	return type == GameEnums.CardType.BABY_UNICORN or \
		   type == GameEnums.CardType.BASIC_UNICORN or \
		   type == GameEnums.CardType.MAGICAL_UNICORN
