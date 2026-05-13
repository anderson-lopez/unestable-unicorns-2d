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
var description_en: String = ""

# GAMEPLAY
var is_nursery: bool = false
var deck_location: String = "main_deck"
var effects: Array[CardEffect] = []

# --- Helpers de tipo ---

func is_unicorn() -> bool:
	return type == GameEnums.CardType.BABY_UNICORN \
		or type == GameEnums.CardType.BASIC_UNICORN \
		or type == GameEnums.CardType.MAGICAL_UNICORN

func is_baby_unicorn() -> bool:
	return type == GameEnums.CardType.BABY_UNICORN

func is_basic_unicorn() -> bool:
	return type == GameEnums.CardType.BASIC_UNICORN

func is_magical_unicorn() -> bool:
	return type == GameEnums.CardType.MAGICAL_UNICORN

func is_upgrade() -> bool:
	return type == GameEnums.CardType.UPGRADE

func is_downgrade() -> bool:
	return type == GameEnums.CardType.DOWNGRADE

func is_magic_spell() -> bool:
	return type == GameEnums.CardType.MAGIC_SPELL

func is_instant() -> bool:
	return type == GameEnums.CardType.INSTANT

# Las cartas "permanentes" se quedan en el establo al ser jugadas
func is_permanent() -> bool:
	return is_unicorn() or is_upgrade() or is_downgrade()

# Las cartas que comprueban el filtro UNICORN_CARD
func matches_filter(filter: GameEnums.Filter) -> bool:
	match filter:
		GameEnums.Filter.ANY:              return true
		GameEnums.Filter.UNICORN_CARD:     return is_unicorn()
		GameEnums.Filter.BABY_UNICORN:     return is_baby_unicorn()
		GameEnums.Filter.BASIC_UNICORN:    return is_basic_unicorn()
		GameEnums.Filter.MAGICAL_UNICORN:  return is_magical_unicorn()
		GameEnums.Filter.UPGRADE_CARD:     return is_upgrade()
		GameEnums.Filter.DOWNGRADE_CARD:   return is_downgrade()
		GameEnums.Filter.MAGIC_SPELL:      return is_magic_spell()
		GameEnums.Filter.INSTANT:          return is_instant()
		_: return false

func has_tag(tag: String) -> bool:
	var needle = tag.to_lower()
	for t in tags:
		if t.to_lower() == needle:
			return true
	return false

# Cuenta cuántos unicornios suma esta carta hacia la victoria
# (Ginormous Unicorn cuenta como 2)
func unicorn_count_value() -> int:
	if not is_unicorn():
		return 0
	for effect in effects:
		if effect.condition == GameEnums.Condition.COUNTS_AS_2_UNICORNS:
			return 2
	return 1

func _to_string() -> String:
	return "CardData[%d:%s]" % [id, name_es]
