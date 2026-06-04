class_name TargetResolver extends RefCounted

# Utilidad server-side para encontrar cartas válidas según scope/zone/filter de un efecto.
# No tiene estado: solo lee de GameManager.players y del propio CardDatabase.

# Devuelve una lista de candidatos: cada uno es { "owner_id": int, "card_id": int }
static func find_candidates(
	acting_player_id: int,
	scope: GameEnums.Scope,
	zone: GameEnums.Zone,
	filter: GameEnums.Filter,
	passives: PassiveRegistry = null
) -> Array:
	var result: Array = []
	var owners := _resolve_owners(acting_player_id, scope)
	for owner_id in owners:
		var cards := _cards_in_zone(owner_id, zone)
		for card in cards:
			if not card.matches_filter(filter):
				continue
			# Filtrado por pasivos defensivos
			if zone == GameEnums.Zone.STABLE and passives != null:
				if card.is_unicorn() and passives.unicorn_immune_to_destroy(owner_id):
					# Solo afecta DESTROY, no SACRIFICE/STEAL — el caller decide si usar este filtro
					pass
			result.append({"owner_id": owner_id, "card_id": card.id})
	return result

static func _resolve_owners(acting_player_id: int, scope: GameEnums.Scope) -> Array[int]:
	var all: Array = GameManager.players.keys()
	var out: Array[int] = []
	match scope:
		GameEnums.Scope.SELF:
			out.append(acting_player_id)
		GameEnums.Scope.CHOSEN_OPPONENT:
			# El caller debe pickear con UI; aquí devolvemos todos los oponentes
			for p in all:
				if p != acting_player_id: out.append(p)
		GameEnums.Scope.ALL_OPPONENTS:
			for p in all:
				if p != acting_player_id: out.append(p)
		GameEnums.Scope.ALL_PLAYERS:
			for p in all:
				out.append(p)
		GameEnums.Scope.ANY_PLAYER:
			for p in all:
				out.append(p)
		_:
			pass
	return out

static func _cards_in_zone(owner_id: int, zone: GameEnums.Zone) -> Array[CardData]:
	var player = GameManager.players.get(owner_id)
	if not player: return []
	match zone:
		GameEnums.Zone.HAND:
			return player.hand
		GameEnums.Zone.STABLE:
			return player.stable
		GameEnums.Zone.DECK:
			var arr: Array[CardData] = []
			for id in GameManager.deck:
				var c = CardDatabase.get_card_data(id)
				if c: arr.append(c)
			return arr
		GameEnums.Zone.DISCARD_PILE:
			var arr2: Array[CardData] = []
			for id in GameManager.discard_pile:
				var c = CardDatabase.get_card_data(id)
				if c: arr2.append(c)
			return arr2
		GameEnums.Zone.NURSERY:
			var arr3: Array[CardData] = []
			for id in GameManager.nursery_deck:
				var c = CardDatabase.get_card_data(id)
				if c: arr3.append(c)
			return arr3
		_:
			return []
