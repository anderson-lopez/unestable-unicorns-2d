class_name DataParser extends RefCounted

# Mapeos estáticos para búsqueda rápida O(1)

const TYPE_MAP = {
	"baby_unicorn": GameEnums.CardType.BABY_UNICORN,
	"basic_unicorn": GameEnums.CardType.BASIC_UNICORN,
	"magical_unicorn": GameEnums.CardType.MAGICAL_UNICORN,
	"magic_spell": GameEnums.CardType.MAGIC_SPELL,
	"instant": GameEnums.CardType.INSTANT,
	"upgrade": GameEnums.CardType.UPGRADE,
	"downgrade": GameEnums.CardType.DOWNGRADE,
	"reference": GameEnums.CardType.REFERENCE
}

const ACTION_MAP = {
	"draw": GameEnums.Action.DRAW,
	"discard": GameEnums.Action.DISCARD,
	"destroy": GameEnums.Action.DESTROY,
	"sacrifice": GameEnums.Action.SACRIFICE,
	"steal": GameEnums.Action.STEAL,
	"pull": GameEnums.Action.PULL,
	"swap_hands": GameEnums.Action.SWAP_HANDS,
	"return_to_hand": GameEnums.Action.RETURN_TO_HAND,
	"return_to_nursery": GameEnums.Action.RETURN_TO_NURSERY,
	"revive": GameEnums.Action.REVIVE,
	"summon": GameEnums.Action.SUMMON,
	"search_deck": GameEnums.Action.SEARCH_DECK,
	"shuffle_deck": GameEnums.Action.SHUFFLE_DECK,
	"protect": GameEnums.Action.PROTECT,
	"cancel": GameEnums.Action.CANCEL,
	"extra_action": GameEnums.Action.EXTRA_ACTION,
	"none": GameEnums.Action.NONE
}

const TRIGGER_MAP = {
	"on_play": GameEnums.Trigger.ON_PLAY,
	"on_enter_stable": GameEnums.Trigger.ON_ENTER_STABLE,
	"on_turn_start": GameEnums.Trigger.ON_TURN_START,
	"on_destroy": GameEnums.Trigger.ON_DESTROY,
	"on_sacrifice": GameEnums.Trigger.ON_SACRIFICE,
	"passive": GameEnums.Trigger.PASSIVE,
	"none": GameEnums.Trigger.NONE
}

const FILTER_MAP = {
	"any": GameEnums.Filter.ANY,
	"self": GameEnums.Filter.SELF,
	"unicorn_card": GameEnums.Filter.UNICORN_CARD,
	"basic_unicorn": GameEnums.Filter.BASIC_UNICORN,
	"magical_unicorn": GameEnums.Filter.MAGICAL_UNICORN,
	"baby_unicorn": GameEnums.Filter.BABY_UNICORN,
	"upgrade_card": GameEnums.Filter.UPGRADE_CARD,
	"downgrade_card": GameEnums.Filter.DOWNGRADE_CARD,
	"magic_spell": GameEnums.Filter.MAGIC_SPELL,
	"instant": GameEnums.Filter.INSTANT,
	"hand_and_discard": GameEnums.Filter.HAND_AND_DISCARD,
	"none": GameEnums.Filter.NONE
}

const SCOPE_MAP = {
	"self": GameEnums.Scope.SELF,
	"chosen_opponent": GameEnums.Scope.CHOSEN_OPPONENT,
	"all_players": GameEnums.Scope.ALL_PLAYERS,
	"any_player": GameEnums.Scope.ANY_PLAYER,
	"none": GameEnums.Scope.NONE
}

const ZONE_MAP = {
	"deck": GameEnums.Zone.DECK,
	"hand": GameEnums.Zone.HAND,
	"stable": GameEnums.Zone.STABLE,
	"discard_pile": GameEnums.Zone.DISCARD_PILE,
	"nursery": GameEnums.Zone.NURSERY,
	"none": GameEnums.Zone.NONE
}

# Funciones estáticas seguras (si el string no existe, devuelve NONE/UNDEFINED)

static func parse_type(key: String) -> GameEnums.CardType:
	return TYPE_MAP.get(key, GameEnums.CardType.BASIC_UNICORN)

static func get_type_name(type: GameEnums.CardType) -> String:
	for key in TYPE_MAP.keys():
		if TYPE_MAP[key] == type:
			return key.capitalize()
	return "Desconocido"

static func parse_action(key: String) -> GameEnums.Action:
	return ACTION_MAP.get(key, GameEnums.Action.NONE)

static func parse_trigger(key: String) -> GameEnums.Trigger:
	return TRIGGER_MAP.get(key, GameEnums.Trigger.NONE)

static func parse_filter(key: String) -> GameEnums.Filter:
	return FILTER_MAP.get(key, GameEnums.Filter.NONE)
	
static func parse_scope(key: String) -> GameEnums.Scope:
	return SCOPE_MAP.get(key, GameEnums.Scope.NONE)

static func parse_zone(key: String) -> GameEnums.Zone:
	return ZONE_MAP.get(key, GameEnums.Zone.NONE)
