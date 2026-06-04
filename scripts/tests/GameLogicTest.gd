extends Node
# Test integral de lógica de juego (SIN red). Ejecutar con F6 sobre GameLogicTest.tscn.
# Valida: parseo, helpers de carta, pasivos (incl. Luz Cegadora), victoria, y
# flujos de efectos clave (robar/destruir/devolver/sacrificar/mover) usando un
# auto-respondedor que simula los clicks del jugador en los pickers.

var _passed := 0
var _failed := 0

func _ready():
	print("\n========== TEST INTEGRAL DE LÓGICA ==========")
	await get_tree().process_frame # esperar autoloads

	_test_json_integrity()
	_test_card_helpers()
	_test_dataparser_coverage()
	_test_passive_registry()
	_test_blinding_light_suppression()
	_test_win_counting()
	_test_target_resolver()
	await _test_effect_flows()

	print("\n========== RESULTADO: %d OK, %d FALLOS ==========" % [_passed, _failed])
	if _failed == 0:
		print("✅ TODO VERDE — listo para jugar")
	else:
		printerr("❌ HAY FALLOS — revisar arriba")

# ----------------- helpers de aserción -----------------
func _ok(cond: bool, label: String):
	if cond: _passed += 1
	else:
		_failed += 1
		printerr("  ✗ ", label)

func _eq(a, b, label: String):
	_ok(a == b, "%s (esperado=%s obtenido=%s)" % [label, b, a])

# ----------------- A. JSON -----------------
func _test_json_integrity():
	print("\n[A] Integridad de datos")
	_eq(CardDatabase.database.size(), 85, "85 cartas cargadas")
	# Toda carta no-referencia con type unicornio debe tener is_unicorn
	for id in CardDatabase.database:
		var c: CardData = CardDatabase.database[id]
		_ok(c.id == id, "id coherente %d" % id)
		for eff in c.effects:
			_ok(eff.primary_action_type != null, "efecto con accion ID %d" % id)

# ----------------- B. CardData helpers -----------------
func _test_card_helpers():
	print("\n[B] Helpers de CardData")
	var baby = CardDatabase.get_card_data(2)   # Baby Death
	var magic = CardDatabase.get_card_data(3)  # Veneno (magia)
	var ginormous = CardDatabase.get_card_data(26)
	var basic = CardDatabase.get_card_data(7)  # básico amarillo
	_ok(baby.is_unicorn() and baby.is_baby_unicorn(), "baby es unicornio")
	_ok(baby.is_permanent(), "baby es permanente")
	_ok(magic.is_magic_spell() and not magic.is_permanent(), "magia no permanente")
	_eq(ginormous.unicorn_count_value(), 2, "Gordicornio cuenta 2")
	_eq(baby.unicorn_count_value(), 1, "baby cuenta 1")
	_eq(magic.unicorn_count_value(), 0, "magia cuenta 0")
	_ok(baby.matches_filter(GameEnums.Filter.UNICORN_CARD), "baby matchea UNICORN")
	_ok(basic.matches_filter(GameEnums.Filter.BASIC_UNICORN), "basico matchea BASIC")
	_ok(not magic.matches_filter(GameEnums.Filter.UNICORN_CARD), "magia no matchea UNICORN")

# ----------------- C. DataParser -----------------
func _test_dataparser_coverage():
	print("\n[C] DataParser")
	_eq(DataParser.parse_action("extra_turn"), GameEnums.Action.EXTRA_TURN, "extra_turn")
	_eq(DataParser.parse_action("skip_turn"), GameEnums.Action.SKIP_TURN, "skip_turn")
	_eq(DataParser.parse_trigger("on_card_played"), GameEnums.Trigger.ON_CARD_PLAYED, "on_card_played")
	_eq(DataParser.parse_scope("all_opponents"), GameEnums.Scope.ALL_OPPONENTS, "all_opponents")
	_eq(DataParser.parse_condition("convert_unicorns_to_pandas"), GameEnums.Condition.CONVERT_UNICORNS_TO_PANDAS, "pandas")
	_eq(DataParser.parse_condition("desconocida_xyz"), GameEnums.Condition.NONE, "condicion desconocida -> NONE")

# ----------------- D. PassiveRegistry -----------------
func _test_passive_registry():
	print("\n[D] PassiveRegistry")
	var reg = PassiveRegistry.new()
	var queen = CardDatabase.get_card_data(1) # Reina (prevent_basic_entry)
	reg.on_card_entered_stable(2, queen)
	_ok(reg.player_has(2, GameEnums.Condition.PREVENT_BASIC_ENTRY), "Reina registra pasivo")
	_ok(reg.basic_unicorns_blocked_against(1, [1, 2]), "jugador 1 bloqueado por Reina de 2")
	_ok(not reg.basic_unicorns_blocked_against(2, [1, 2]), "dueño 2 NO se bloquea a sí mismo")
	reg.on_card_left_stable(2, queen)
	_ok(not reg.player_has(2, GameEnums.Condition.PREVENT_BASIC_ENTRY), "Reina desregistra al salir")

# ----------------- E. Luz Cegadora suprime pasivos de unicornio -----------------
func _test_blinding_light_suppression():
	print("\n[E] Luz Cegadora suprime pasivos de unicornio")
	var reg = PassiveRegistry.new()
	var queen = CardDatabase.get_card_data(1)   # unicornio mágico
	var blinding = CardDatabase.get_card_data(35) # desventaja
	reg.on_card_entered_stable(2, queen)
	reg.on_card_entered_stable(2, blinding)
	# La Reina (unicornio) queda anulada por Luz Cegadora del mismo dueño
	_ok(not reg.player_has(2, GameEnums.Condition.PREVENT_BASIC_ENTRY), "Reina anulada por Luz Cegadora")
	# Pero Luz Cegadora (desventaja) sigue activa
	_ok(reg.player_has(2, GameEnums.Condition.DISABLE_UNICORN_EFFECTS), "Luz Cegadora sigue activa")
	# Al quitar Luz Cegadora, la Reina vuelve a funcionar
	reg.on_card_left_stable(2, blinding)
	_ok(reg.player_has(2, GameEnums.Condition.PREVENT_BASIC_ENTRY), "Reina reactivada sin Luz Cegadora")

# ----------------- F. Conteo de victoria -----------------
func _test_win_counting():
	print("\n[F] Conteo de victoria (pandas/ginormous)")
	_setup_players()
	var p1 = GameManager.players[1]
	# 6 básicos + 1 ginormous = 6 + 2 = 8 (gana)
	for i in 6: p1.stable.append(CardDatabase.get_card_data(7))
	p1.stable.append(CardDatabase.get_card_data(26)) # ginormous = 2
	_ok(GameManager.check_win_condition(), "8 puntos -> victoria")
	# Con Pandamonio activo, no cuenta
	GameManager.is_game_active = true
	EffectProcessor.passives.on_card_entered_stable(1, CardDatabase.get_card_data(80))
	_ok(not GameManager.check_win_condition(), "Pandamonio anula la victoria")
	_teardown()

# ----------------- G. TargetResolver -----------------
func _test_target_resolver():
	print("\n[G] TargetResolver")
	_setup_players()
	GameManager.players[2].stable.append(CardDatabase.get_card_data(7))  # básico
	GameManager.players[2].stable.append(CardDatabase.get_card_data(3))  # magia (no debería estar en establo, pero test de filtro)
	var cands = TargetResolver.find_candidates(1, GameEnums.Scope.CHOSEN_OPPONENT, GameEnums.Zone.STABLE, GameEnums.Filter.UNICORN_CARD, EffectProcessor.passives)
	_eq(cands.size(), 1, "solo el básico matchea UNICORN_CARD")
	_teardown()

# ----------------- H. Flujos de efectos (con auto-respondedor) -----------------
func _test_effect_flows():
	print("\n[H] Flujos de efectos")

	# H1: _extract_from_stable NO descarta ni dispara on_destroy
	_setup_players()
	var p1 = GameManager.players[1]
	p1.stable.append(CardDatabase.get_card_data(54)) # Narval (unicornio sin efecto)
	var extracted = await EffectProcessor._extract_from_stable(1, 54)
	_ok(extracted != null, "extract devuelve la carta")
	_ok(not (54 in GameManager.discard_pile), "extract NO manda al descarte")
	_eq(p1.stable.size(), 0, "extract quita del establo")
	_teardown()

	# H2: _remove_from_stable (destroy) SÍ descarta
	_setup_players()
	GameManager.players[1].stable.append(CardDatabase.get_card_data(54))
	await EffectProcessor._remove_from_stable(1, 54, true)
	_ok(54 in GameManager.discard_pile, "destroy SÍ manda al descarte")
	_teardown()

	# H3: bebé destruido -> Guardería (no descarte)
	_setup_players()
	GameManager.players[1].stable.append(CardDatabase.get_card_data(2)) # baby death
	await EffectProcessor._remove_from_stable(1, 2, true)
	_ok(2 in GameManager.nursery_deck, "bebé destruido vuelve a Guardería")
	_ok(not (2 in GameManager.discard_pile), "bebé NO va al descarte")
	_teardown()

	# H4: STEAL no duplica (regresión del bug)
	_setup_players()
	GameManager.players[2].stable.append(CardDatabase.get_card_data(54))
	_auto_respond([{"a": 54, "b": 2}]) # elegir el Narval del jugador 2
	await EffectProcessor._act_steal(1, GameEnums.Scope.CHOSEN_OPPONENT, GameEnums.Filter.UNICORN_CARD, 1)
	_ok(_stable_has(1, 54), "robado entra a mi establo")
	_ok(not _stable_has(2, 54), "robado sale del establo rival")
	_ok(not (54 in GameManager.discard_pile), "robado NO va al descarte (no duplica)")
	_teardown()

	# H5: RETURN_TO_HAND no duplica
	_setup_players()
	GameManager.players[2].stable.append(CardDatabase.get_card_data(54))
	_auto_respond([{"a": 54, "b": 2}])
	await EffectProcessor._act_return_to_hand(1, GameEnums.Scope.CHOSEN_OPPONENT, GameEnums.Filter.ANY, 1)
	_ok(_hand_has(2, 54), "devuelta entra a la mano del dueño")
	_ok(not _stable_has(2, 54), "devuelta sale del establo")
	_ok(not (54 in GameManager.discard_pile), "devuelta NO va al descarte")
	_teardown()

	# H6: DRAW funciona y baja el mazo
	_setup_players()
	GameManager.deck = [10, 11, 12]
	await EffectProcessor._act_draw(2, 1)
	_eq(GameManager.players[1].hand.size(), 2, "robó 2 cartas")
	_eq(GameManager.deck.size(), 1, "mazo bajó a 1")
	_teardown()

	# H7: Unicornio Volador (17) destruido → vuelve a la MANO del dueño, no al descarte
	_setup_players()
	GameManager.players[1].stable.append(CardDatabase.get_card_data(17)) # Volador Codicioso
	await EffectProcessor._remove_from_stable(1, 17, true)
	_ok(_hand_has(1, 17), "volador destruido vuelve a la mano del dueño")
	_ok(not (17 in GameManager.discard_pile), "volador NO va al descarte")
	_ok(not _stable_has(1, 17), "volador sale del establo")
	_teardown()

	# H8: PULL con elección (Robo Descarado, condition=none) deja elegir
	_setup_players()
	GameManager.players[2].hand.append(CardDatabase.get_card_data(7))   # básico
	GameManager.players[2].hand.append(CardDatabase.get_card_data(54))  # narval
	var pull_eff = CardDatabase.get_card_data(47).effects[0] # Robo Descarado (none)
	_auto_respond([{"a": 54}]) # elijo el narval
	await EffectProcessor._act_pull(1, GameEnums.Scope.CHOSEN_OPPONENT, 1, pull_eff)
	_ok(_hand_has(1, 54), "Robo Descarado: la carta ELEGIDA pasa a mi mano")
	_ok(not _hand_has(2, 54), "carta sale de la mano rival")
	_teardown()

	# H9: PULL al azar (Americornio, condition=random) NO abre picker
	_setup_players()
	GameManager.players[2].hand.append(CardDatabase.get_card_data(7))
	var rnd_eff = CardDatabase.get_card_data(56).effects[0] # Americornio (random)
	await EffectProcessor._act_pull(1, GameEnums.Scope.CHOSEN_OPPONENT, 1, rnd_eff)
	_eq(GameManager.players[1].hand.size(), 1, "Americornio robó 1 al azar sin picker")
	_eq(GameManager.players[2].hand.size(), 0, "mano rival quedó vacía")
	_teardown()

# ----------------- utilidades de setup -----------------
func _setup_players():
	GameManager.game_table = null # los RPC visuales se vuelven no-op
	GameManager.players = {
		1: PlayerData.new(1, "TestA"),
		2: PlayerData.new(2, "TestB"),
	}
	GameManager.deck = []
	GameManager.discard_pile = []
	GameManager.nursery_deck = []
	GameManager.is_game_active = true
	GameManager.current_rules = GameRules.new()
	EffectProcessor.passives.clear()
	EffectProcessor._current_source = null

func _teardown():
	GameManager.players = {}
	GameManager.deck = []
	GameManager.discard_pile = []
	GameManager.nursery_deck = []
	EffectProcessor.passives.clear()

func _stable_has(pid: int, card_id: int) -> bool:
	for c in GameManager.players[pid].stable:
		if c.id == card_id: return true
	return false

func _hand_has(pid: int, card_id: int) -> bool:
	for c in GameManager.players[pid].hand:
		if c.id == card_id: return true
	return false

# Auto-respondedor: emite target_picked en frames sucesivos para simular clicks.
func _auto_respond(responses: Array):
	_run_responder(responses)

func _run_responder(responses: Array):
	for r in responses:
		await get_tree().process_frame
		await get_tree().process_frame
		EffectProcessor.target_picked.emit(r["a"], r.get("b", -1))
