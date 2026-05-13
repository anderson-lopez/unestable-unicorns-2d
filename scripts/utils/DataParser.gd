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
	"skip_turn": GameEnums.Action.SKIP_TURN,
	"extra_turn": GameEnums.Action.EXTRA_TURN,
	"extra_action": GameEnums.Action.EXTRA_ACTION,
	"none": GameEnums.Action.NONE
}

const TRIGGER_MAP = {
	"on_play": GameEnums.Trigger.ON_PLAY,
	"on_enter_stable": GameEnums.Trigger.ON_ENTER_STABLE,
	"on_turn_start": GameEnums.Trigger.ON_TURN_START,
	"on_destroy": GameEnums.Trigger.ON_DESTROY,
	"on_sacrifice": GameEnums.Trigger.ON_SACRIFICE,
	"on_card_played": GameEnums.Trigger.ON_CARD_PLAYED,
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
	"all_opponents": GameEnums.Scope.ALL_OPPONENTS,
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
	"void": GameEnums.Zone.VOID,
	"none": GameEnums.Zone.NONE
}

const CONDITION_MAP = {
	"none": GameEnums.Condition.NONE,
	"always": GameEnums.Condition.ALWAYS,
	"in_stable": GameEnums.Condition.IN_STABLE,

	# Modificadores de trigger
	"or_on_sacrifice": GameEnums.Condition.OR_ON_SACRIFICE,
	"or_on_leave_stable": GameEnums.Condition.OR_ON_LEAVE_STABLE,

	# Inmunidades
	"immune_to_destroy": GameEnums.Condition.IMMUNE_TO_DESTROY,
	"immune_to_magic_destroy": GameEnums.Condition.IMMUNE_TO_MAGIC_DESTROY,

	# Bloqueos
	"prevent_basic_entry": GameEnums.Condition.PREVENT_BASIC_ENTRY,
	"prevent_play_neigh": GameEnums.Condition.PREVENT_PLAY_NEIGH,
	"prevent_play_upgrade": GameEnums.Condition.PREVENT_PLAY_UPGRADE,
	"prevent_neigh_on_owner": GameEnums.Condition.PREVENT_NEIGH_ON_OWNER,

	# Transformaciones
	"disable_unicorn_effects": GameEnums.Condition.DISABLE_UNICORN_EFFECTS,
	"convert_unicorns_to_pandas": GameEnums.Condition.CONVERT_UNICORNS_TO_PANDAS,
	"hand_visible": GameEnums.Condition.HAND_VISIBLE,
	"counts_as_2_unicorns": GameEnums.Condition.COUNTS_AS_2_UNICORNS,

	# Condicionales numéricos
	"if_unicorn_count_exceeds_5": GameEnums.Condition.IF_UNICORN_COUNT_EXCEEDS_5,

	# Modificadores de acción
	"scry_3": GameEnums.Condition.SCRY_3,
	"tag_narwhal": GameEnums.Condition.TAG_NARWHAL,
	"random": GameEnums.Condition.RANDOM,
	"choice_either": GameEnums.Condition.CHOICE_EITHER,
	"move_unicorn_to_opponent": GameEnums.Condition.MOVE_UNICORN_TO_OPPONENT,
	"retarget_upgrade_downgrade": GameEnums.Condition.RETARGET_UPGRADE_DOWNGRADE,
	"cannot_be_neighed": GameEnums.Condition.CANNOT_BE_NEIGHED,
	"replace_target_unicorn": GameEnums.Condition.REPLACE_TARGET_UNICORN
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

static func parse_condition(key: String) -> GameEnums.Condition:
	if key == null or key == "":
		return GameEnums.Condition.NONE
	var result = CONDITION_MAP.get(key, -1)
	if result == -1:
		printerr("DataParser: condition desconocida -> '", key, "'. Usando NONE.")
		return GameEnums.Condition.NONE
	return result
