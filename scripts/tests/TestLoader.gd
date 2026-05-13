extends Node
# Adjunta este script a cualquier nodo en una escena vacía y dale Play para probar

func _ready():
	print("--- INICIANDO TEST DE INTEGRIDAD DE DATOS ---")

	# Esperamos un frame para asegurar que el Autoload cargó
	await get_tree().process_frame

	# TEST 1: Cantidad
	var total = CardDatabase.database.size()
	print("Total cartas: ", total)
	if total == 0:
		printerr("FALLO: La base de datos está vacía.")
		return
	if total != 85:
		printerr("ADVERTENCIA: Se esperaban 85 cartas, se cargaron ", total)

	# TEST 2: ID 4 - Extremely Destructive Unicorn (sacrifice all_players unicorn)
	var card_4 = CardDatabase.get_card_data(4)
	if card_4:
		print("\n[ID 4] ", card_4.name_es)
		_assert_eq(card_4.type, GameEnums.CardType.MAGICAL_UNICORN, "type")
		var eff = card_4.effects[0]
		_assert_eq(eff.trigger, GameEnums.Trigger.ON_ENTER_STABLE, "trigger")
		_assert_eq(eff.primary_action_type, GameEnums.Action.SACRIFICE, "primary_action")
		_assert_eq(eff.primary_scope, GameEnums.Scope.ALL_PLAYERS, "scope (debe ser all_players)")
		_assert_eq(eff.primary_filter, GameEnums.Filter.UNICORN_CARD, "filter (debe ser unicorn_card)")

	# TEST 3: ID 5 - Good Deal (draw 3 + discard 1)
	var card_5 = CardDatabase.get_card_data(5)
	if card_5:
		print("\n[ID 5] ", card_5.name_es)
		var eff = card_5.effects[0]
		_assert_eq(eff.primary_amount, 3, "draw amount (debe ser 3)")
		_assert_eq(eff.has_secondary, true, "tiene secundario")
		_assert_eq(eff.secondary_action_type, GameEnums.Action.DISCARD, "secondary discard")

	# TEST 4: ID 8 - Magical Kittencorn (passive immune_to_magic_destroy)
	var card_8 = CardDatabase.get_card_data(8)
	if card_8:
		print("\n[ID 8] ", card_8.name_es)
		var eff = card_8.effects[0]
		_assert_eq(eff.trigger, GameEnums.Trigger.PASSIVE, "trigger PASSIVE")
		_assert_eq(eff.condition, GameEnums.Condition.IMMUNE_TO_MAGIC_DESTROY, "condition")
		_assert_eq(eff.primary_action_type, GameEnums.Action.PROTECT, "action PROTECT")

	# TEST 5: ID 26 - Ginormous Unicorn (2 efectos pasivos)
	var card_26 = CardDatabase.get_card_data(26)
	if card_26:
		print("\n[ID 26] ", card_26.name_es)
		_assert_eq(card_26.effects.size(), 2, "tiene 2 efectos")
		_assert_eq(card_26.effects[0].condition, GameEnums.Condition.COUNTS_AS_2_UNICORNS, "efecto 1 = counts_as_2")
		_assert_eq(card_26.effects[1].condition, GameEnums.Condition.PREVENT_PLAY_NEIGH, "efecto 2 = prevent_neigh")
		_assert_eq(card_26.unicorn_count_value(), 2, "cuenta como 2 unicornios")

	# TEST 6: ID 34 - Neigh (on_card_played + cancel)
	var card_34 = CardDatabase.get_card_data(34)
	if card_34:
		print("\n[ID 34] ", card_34.name_es)
		_assert_eq(card_34.type, GameEnums.CardType.INSTANT, "type INSTANT")
		var eff = card_34.effects[0]
		_assert_eq(eff.trigger, GameEnums.Trigger.ON_CARD_PLAYED, "trigger ON_CARD_PLAYED")
		_assert_eq(eff.primary_action_type, GameEnums.Action.CANCEL, "action CANCEL")

	# TEST 7: ID 70 - Super Neigh (cannot_be_neighed)
	var card_70 = CardDatabase.get_card_data(70)
	if card_70:
		print("\n[ID 70] ", card_70.name_es)
		var eff = card_70.effects[0]
		_assert_eq(eff.condition, GameEnums.Condition.CANNOT_BE_NEIGHED, "condition")

	# TEST 8: ID 78 - Shake Up (shuffle + draw 5)
	var card_78 = CardDatabase.get_card_data(78)
	if card_78:
		print("\n[ID 78] ", card_78.name_es)
		var eff = card_78.effects[0]
		_assert_eq(eff.has_secondary, true, "tiene secundario")
		_assert_eq(eff.secondary_amount, 5, "draw 5")

	# TEST 9: ID 83 - Double Dutch (extra_action)
	var card_83 = CardDatabase.get_card_data(83)
	if card_83:
		print("\n[ID 83] ", card_83.name_es)
		var eff = card_83.effects[0]
		_assert_eq(eff.primary_action_type, GameEnums.Action.EXTRA_ACTION, "EXTRA_ACTION")
		_assert_eq(eff.primary_amount, 2, "amount 2")

	# TEST 10: Helpers de tipo en CardData
	print("\n[Helpers] CardData.is_unicorn / matches_filter")
	var baby = CardDatabase.get_card_data(2) # Baby Death
	_assert_eq(baby.is_unicorn(), true, "baby es unicornio")
	_assert_eq(baby.is_baby_unicorn(), true, "es baby unicorn")
	_assert_eq(baby.matches_filter(GameEnums.Filter.UNICORN_CARD), true, "matches UNICORN_CARD")
	_assert_eq(baby.matches_filter(GameEnums.Filter.MAGIC_SPELL), false, "no matches MAGIC_SPELL")

	# TEST 11: Búsqueda por tag
	var narwhals = CardDatabase.get_cards_by_tag("narwhal")
	print("\nCartas con tag 'narwhal': ", narwhals.size())
	if narwhals.size() < 5:
		printerr("ADVERTENCIA: se esperaban al menos 5 cartas narwhal")

	print("\n--- TEST FINALIZADO ---")

func _assert_eq(actual, expected, label: String):
	if actual == expected:
		print("  ✓ ", label)
	else:
		printerr("  ✗ FALLO en '", label, "': esperado=", expected, " obtenido=", actual)
