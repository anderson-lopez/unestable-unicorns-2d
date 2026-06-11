extends Node
# Autoload: ejecuta efectos de cartas con autoridad del servidor.
# Se llama desde game_table.gd cuando una carta es jugada / entra al establo / etc.

# Señales internas (server-side) usadas para esperar respuestas de UI
signal target_picked(card_id: int, owner_id: int)
signal cost_paid(success: bool, paid_card_ids: Array)

var passives: PassiveRegistry = PassiveRegistry.new()

# Carta que origina el efecto en curso (para saber si un DESTROY viene de una Magia)
var _current_source: CardData = null

func _ready():
	passives.clear()

# Wrappers para enrutar RPCs visuales a través de game_table
func _table_rpc(method, p1 = null, p2 = null, p3 = null, p4 = null, p5 = null):
	if not GameManager.game_table: return
	var args = [method]
	for p in [p1, p2, p3, p4, p5]:
		if p != null: args.append(p)
	GameManager.game_table.callv("rpc", args)

func _table_rpc_id(target_id: int, method, p1 = null, p2 = null, p3 = null, p4 = null, p5 = null):
	if not GameManager.game_table: return
	var args = [target_id, method]
	for p in [p1, p2, p3, p4, p5]:
		if p != null: args.append(p)
	GameManager.game_table.callv("rpc_id", args)

func reset():
	passives.clear()

# Aviso breve a un jugador (toast en su pantalla)
func _notify(player_id: int, msg: String) -> void:
	_table_rpc_id(player_id, "client_toast", msg)

# Difunde una línea al registro de jugadas de todos los jugadores.
func _log(msg: String, color: Color = Color.WHITE) -> void:
	_table_rpc("client_log_event", msg, color)

func _player_name(player_id: int) -> String:
	if GameManager.players.has(player_id):
		return GameManager.players[player_id].name
	return "?"

# ==============================================================================
# 🎯 ENTRADA PRINCIPAL
# ==============================================================================

# Llamado por server_play_card. Resuelve todos los efectos cuyo trigger sea ON_PLAY.
# Para unicornios/upgrades/downgrades, después el caller debe llamar resolve_on_enter_stable.
func resolve_on_play(card_data: CardData, acting_player_id: int) -> void:
	for effect in card_data.effects:
		if effect.trigger == GameEnums.Trigger.ON_PLAY:
			await _execute_effect(effect, card_data, acting_player_id)

func resolve_on_enter_stable(card_data: CardData, owner_id: int) -> void:
	# Registrar pasivos primero
	passives.on_card_entered_stable(owner_id, card_data)
	# Barbed Wire / Tiny Stable reaccionan a unicornios entrando
	if card_data.is_unicorn():
		await _on_unicorn_stable_changed(owner_id, true)
	# Luz Cegadora: los efectos de unicornios propios no se activan
	if card_data.is_unicorn() and passives.unicorn_effects_disabled(owner_id):
		return
	for effect in card_data.effects:
		if effect.trigger == GameEnums.Trigger.ON_ENTER_STABLE:
			await _execute_effect(effect, card_data, owner_id)

func resolve_on_turn_start(player_id: int) -> void:
	# Recorre el establo del jugador activo y dispara on_turn_start
	var player: PlayerData = GameManager.players.get(player_id)
	if not player: return
	# Copia local para evitar mutación durante iteración
	var stable_copy: Array[CardData] = []
	for c in player.stable:
		stable_copy.append(c)
	for card in stable_copy:
		# Luz Cegadora desactiva los efectos de los UNICORNIOS (no de upgrades/downgrades)
		if card.is_unicorn() and passives.unicorn_effects_disabled(player_id):
			continue
		for effect in card.effects:
			if effect.trigger == GameEnums.Trigger.ON_TURN_START:
				if effect.condition == GameEnums.Condition.IN_STABLE:
					# Verificar que la carta sigue en el establo
					if not (card in player.stable): continue
				await _execute_effect(effect, card, player_id)

func resolve_on_destroy(card_data: CardData, owner_id: int) -> void:
	# Luz Cegadora: unicornios sin efectos
	if card_data.is_unicorn() and passives.unicorn_effects_disabled(owner_id):
		return
	# Dispara on_destroy (también acepta or_on_sacrifice)
	for effect in card_data.effects:
		var t = effect.trigger
		if t == GameEnums.Trigger.ON_DESTROY or t == GameEnums.Trigger.ON_SACRIFICE:
			# El "vuelve a TU mano" (return_to_hand self) NO es una acción normal:
			# se gestiona como destino en _remove_from_stable. Lo saltamos aquí.
			if effect.primary_action_type == GameEnums.Action.RETURN_TO_HAND \
					and effect.primary_filter == GameEnums.Filter.SELF:
				continue
			await _execute_effect(effect, card_data, owner_id)

# ¿Esta carta vuelve a la mano de su dueño cuando es destruida/sacrificada?
# (Unicornios voladores). Devuelve true si tiene ese efecto de reemplazo.
func _returns_to_hand_on_destroy(card_data: CardData) -> bool:
	for effect in card_data.effects:
		var t = effect.trigger
		if t == GameEnums.Trigger.ON_DESTROY or t == GameEnums.Trigger.ON_SACRIFICE:
			if effect.primary_action_type == GameEnums.Action.RETURN_TO_HAND \
					and effect.primary_filter == GameEnums.Filter.SELF:
				return true
	return false

# ==============================================================================
# ⚙️ EJECUCIÓN DE UN EFFECT
# ==============================================================================

func _execute_effect(effect: CardEffect, source_card: CardData, acting_player_id: int) -> void:
	# Guardar el origen del efecto (para inmunidades tipo "no por Magia")
	_current_source = source_card

	# 0. Condiciones que son ACCIONES CUSTOM (no siguen el flujo normal)
	match effect.condition:
		GameEnums.Condition.MOVE_UNICORN_TO_OPPONENT:
			await _custom_unicorn_swap(acting_player_id)
			return
		GameEnums.Condition.RETARGET_UPGRADE_DOWNGRADE:
			await _custom_retarget(acting_player_id)
			return

	# 1. Coste (si lo hay)
	if effect.has_cost():
		var paid = await _request_pay_cost(effect, acting_player_id)
		if not paid:
			return # Jugador rechazó pagar -> efecto cancelado

	# 2. Condition CHOICE_EITHER: jugador elige primary o secondary
	if effect.condition == GameEnums.Condition.CHOICE_EITHER and effect.has_secondary:
		var choice = await _request_choice(effect, acting_player_id)
		if choice == 0:
			await _execute_action(effect.primary_action_type, effect.primary_amount,
				effect.primary_scope, effect.primary_zone, effect.primary_filter,
				source_card, acting_player_id, effect)
		elif choice == 1:
			await _execute_action(effect.secondary_action_type, effect.secondary_amount,
				effect.secondary_scope, effect.secondary_zone, effect.secondary_filter,
				source_card, acting_player_id, effect)
		return

	# 3. Acción principal
	var primary_ok = await _execute_action(effect.primary_action_type, effect.primary_amount,
		effect.primary_scope, effect.primary_zone, effect.primary_filter,
		source_card, acting_player_id, effect)

	# 4. Acción secundaria — SOLO si la primaria se completó.
	# Esto modela cartas tipo "DESTRUYE X. Si lo haces, termina tu turno" (Uniceronte):
	# si cancelas el destroy, el skip_turn NO se ejecuta.
	if effect.has_secondary and primary_ok:
		await _execute_action(effect.secondary_action_type, effect.secondary_amount,
			effect.secondary_scope, effect.secondary_zone, effect.secondary_filter,
			source_card, acting_player_id, effect)

# ==============================================================================
# 🔧 ACCIONES — Dispatch
# ==============================================================================

# Devuelve true si la acción se completó, false si el jugador la canceló.
func _execute_action(
	action: GameEnums.Action, amount: int,
	scope: GameEnums.Scope, zone: GameEnums.Zone, filter: GameEnums.Filter,
	source_card: CardData, acting_player_id: int, effect: CardEffect
) -> bool:
	match action:
		GameEnums.Action.DRAW:
			await _act_draw(amount, acting_player_id)
			return true
		GameEnums.Action.DISCARD:
			await _act_discard(amount, scope, filter, acting_player_id)
			return true
		GameEnums.Action.DESTROY:
			return await _act_destroy(amount, scope, filter, acting_player_id)
		GameEnums.Action.SACRIFICE:
			return await _act_sacrifice(amount, scope, filter, acting_player_id, source_card)
		GameEnums.Action.STEAL:
			return await _act_steal(amount, scope, filter, acting_player_id)
		GameEnums.Action.PULL:
			await _act_pull(amount, scope, acting_player_id, effect)
			return true
		GameEnums.Action.SWAP_HANDS:
			await _act_swap_hands(acting_player_id)
			return true
		GameEnums.Action.RETURN_TO_HAND:
			return await _act_return_to_hand(amount, scope, filter, acting_player_id)
		GameEnums.Action.RETURN_TO_NURSERY:
			return true # Se maneja en destroy/sacrifice cuando el baby vuelve solo
		GameEnums.Action.REVIVE:
			return await _act_revive(amount, zone, filter, acting_player_id)
		GameEnums.Action.SUMMON:
			return await _act_summon(amount, zone, filter, acting_player_id)
		GameEnums.Action.SEARCH_DECK:
			await _act_search_deck(filter, acting_player_id, effect)
			return true
		GameEnums.Action.SHUFFLE_DECK:
			_act_shuffle_deck(filter, acting_player_id)
			return true
		GameEnums.Action.PROTECT:
			return true # Es pasivo, no hace nada al ejecutarse
		GameEnums.Action.CANCEL:
			return true # Se gestiona en NeighManager, no aquí
		GameEnums.Action.SKIP_TURN:
			GameManager._server_advance_to_end_phase()
			return true
		GameEnums.Action.EXTRA_TURN:
			GameManager.queue_extra_turn(acting_player_id)
			return true
		GameEnums.Action.EXTRA_ACTION:
			GameManager.grant_extra_action(max(1, amount - 1))
			return true
		_:
			print("EffectProcessor: acción no implementada: ", action)
			return true

# ==============================================================================
# 📥 ROBAR / DESCARTAR
# ==============================================================================

func _act_draw(amount: int, player_id: int) -> void:
	var drawn = GameManager.draw_cards(amount)
	var player = GameManager.players.get(player_id)
	if not player: return
	for cid in drawn:
		var data = CardDatabase.get_card_data(cid)
		if data: player.hand.append(data)
	if not drawn.is_empty():
		_table_rpc_id(player_id, "client_receive_drawn_batch", drawn)
		var new_size = player.hand.size()
		for p in GameManager.players:
			if p != player_id:
				_table_rpc_id(p, "client_sync_hand_size", player_id, new_size)

func _act_discard(amount: int, scope: GameEnums.Scope, filter: GameEnums.Filter, acting_player_id: int) -> void:
	var targets := _resolve_player_targets(scope, acting_player_id)
	for target_id in targets:
		var actual_amount = amount if amount > 0 else 1
		for i in actual_amount:
			# Pedir al jugador que elija qué descartar
			var picked = await _request_discard_pick(target_id, filter)
			if picked == -1:
				continue
			var p = GameManager.players.get(target_id)
			if not p: continue
			# Remover de mano
			for j in range(p.hand.size()):
				if p.hand[j].id == picked:
					p.hand.remove_at(j)
					break
			GameManager.discard_pile.append(picked)
			_table_rpc(&"client_card_left_hand", target_id, picked)
			_table_rpc(&"client_sync_hand_size", target_id, p.hand.size())

# ==============================================================================
# 💥 DESTRUIR / SACRIFICAR
# ==============================================================================

func _act_destroy(amount: int, scope: GameEnums.Scope, filter: GameEnums.Filter, acting_player_id: int) -> bool:
	var did_any = false
	for i in max(1, amount):
		var pick = await _request_stable_target(acting_player_id, scope, filter, true)
		if pick.is_empty(): return did_any
		var target_owner = pick["owner_id"]
		var target_card_id = pick["card_id"]
		_remove_from_stable(target_owner, target_card_id, true)
		var dcard = CardDatabase.get_card_data(target_card_id)
		if dcard:
			_log("💥 %s destruyó %s (de %s)" % [_player_name(acting_player_id), dcard.name_es, _player_name(target_owner)], Color(1, 0.5, 0.4))
		did_any = true
	return did_any

func _act_sacrifice(amount: int, scope: GameEnums.Scope, filter: GameEnums.Filter, acting_player_id: int, source: CardData) -> bool:
	# Caso especial: -1 = TODAS las que cumplan filtro
	if amount == GameEnums.AMOUNT_ALL:
		var owners = _resolve_player_targets(scope, acting_player_id)
		for owner_id in owners:
			var player = GameManager.players.get(owner_id)
			if not player: continue
			var to_remove: Array[int] = []
			for card in player.stable:
				if card.matches_filter(filter):
					to_remove.append(card.id)
			for cid in to_remove:
				_remove_from_stable(owner_id, cid, false)
		return true

	# Sacrifice específico (con elección si scope=self)
	var did_any = false
	for i in max(1, amount):
		# Scope=self pero filter=self → es la propia source
		if scope == GameEnums.Scope.SELF and filter == GameEnums.Filter.SELF and source:
			_remove_from_stable(acting_player_id, source.id, false)
			did_any = true
			continue
		var owners = _resolve_player_targets(scope, acting_player_id)
		for owner_id in owners:
			var pick = await _request_stable_target(owner_id, GameEnums.Scope.SELF, filter, false)
			if pick.is_empty(): continue
			_remove_from_stable(pick["owner_id"], pick["card_id"], false)
			did_any = true
	return did_any

# ==============================================================================
# 🤝 STEAL / PULL / SWAP / RETURN
# ==============================================================================

func _act_steal(amount: int, scope: GameEnums.Scope, filter: GameEnums.Filter, acting_player_id: int) -> bool:
	var did_any = false
	for i in max(1, amount):
		var pick = await _request_stable_target(acting_player_id, scope, filter, false)
		if pick.is_empty(): return did_any
		var source_owner = pick["owner_id"]
		var card_id = pick["card_id"]
		# Extraer del establo origen (sin destruir ni descartar)
		var card_data = await _extract_from_stable(source_owner, card_id)
		if not card_data: continue
		# Añadir al establo del acting
		var dest = GameManager.players.get(acting_player_id)
		if dest:
			dest.stable.append(card_data)
			_table_rpc(&"client_card_entered_stable_visual", acting_player_id, card_id)
			passives.on_card_entered_stable(acting_player_id, card_data)
			if card_data.is_unicorn():
				await _on_unicorn_stable_changed(acting_player_id, true)
			_log("🤝 %s robó %s a %s" % [_player_name(acting_player_id), card_data.name_es, _player_name(source_owner)], Color(0.9, 0.8, 1.0))
			did_any = true
	GameManager.check_win_condition()
	return did_any

func _act_pull(amount: int, scope: GameEnums.Scope, acting_player_id: int, effect: CardEffect) -> void:
	var is_random = effect != null and effect.condition == GameEnums.Condition.RANDOM
	for i in max(1, amount):
		var targets := _resolve_player_targets(scope, acting_player_id)
		if targets.is_empty(): return
		var target_id = targets[0]
		# Si hay más de un oponente y scope es chosen, pedir picker de jugador
		if scope == GameEnums.Scope.CHOSEN_OPPONENT and targets.size() > 1:
			target_id = await _request_player_pick(acting_player_id, targets)
			if target_id == -1: return
		var p = GameManager.players.get(target_id)
		if not p or p.hand.is_empty(): return

		var taken_id: int
		if is_random:
			# Americornio: carta al azar
			taken_id = p.hand[randi() % p.hand.size()].id
		else:
			# Robo Descarado: ves la mano rival y ELIGES
			var ids: Array = []
			for c in p.hand: ids.append(c.id)
			taken_id = await _request_card_pick(acting_player_id, ids, "Elige una carta de la mano rival")
			if taken_id == -1: return

		# Quitar de la mano rival por ID
		var taken: CardData = null
		for j in range(p.hand.size()):
			if p.hand[j].id == taken_id:
				taken = p.hand[j]
				p.hand.remove_at(j)
				break
		if not taken: return
		# Mover a la mano del acting
		var acting = GameManager.players.get(acting_player_id)
		if acting:
			acting.hand.append(taken)
			_table_rpc_id(acting_player_id, "client_receive_drawn_batch", [taken.id])
		for pid in GameManager.players:
			_table_rpc_id(pid, "client_sync_hand_size", target_id, p.hand.size())
			_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, acting.hand.size())

func _act_swap_hands(acting_player_id: int) -> void:
	var opponents = GameManager.get_opponents_of(acting_player_id)
	if opponents.is_empty(): return
	var target_id = opponents[0]
	if opponents.size() > 1:
		target_id = await _request_player_pick(acting_player_id, opponents)
		if target_id == -1: return
	var a = GameManager.players.get(acting_player_id)
	var b = GameManager.players.get(target_id)
	if not a or not b: return
	var tmp = a.hand
	a.hand = b.hand
	b.hand = tmp
	# Enviar las cartas nuevas a cada uno
	var a_ids: Array = []; var b_ids: Array = []
	for c in a.hand: a_ids.append(c.id)
	for c in b.hand: b_ids.append(c.id)
	_table_rpc_id(acting_player_id, "client_replace_hand", a_ids)
	_table_rpc_id(target_id, "client_replace_hand", b_ids)
	for pid in GameManager.players:
		_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, a.hand.size())
		_table_rpc_id(pid, "client_sync_hand_size", target_id, b.hand.size())

func _act_return_to_hand(amount: int, scope: GameEnums.Scope, filter: GameEnums.Filter, acting_player_id: int) -> bool:
	var did_any = false
	for i in max(1, amount):
		var pick = await _request_stable_target(acting_player_id, scope, filter, false)
		if pick.is_empty(): return did_any
		var owner_id = pick["owner_id"]
		var card_id = pick["card_id"]
		# Extraer del establo (sin descartar)
		var card_data = await _extract_from_stable(owner_id, card_id)
		if not card_data: continue
		# Bebé con guardería segura → vuelve a la Guardería (no a la mano)
		if card_data.is_baby_unicorn() and GameManager.current_rules.nursery_is_safe_zone:
			GameManager.nursery_deck.append(card_id)
			did_any = true
			continue
		# Va a la mano del DUEÑO (no del acting)
		var p = GameManager.players.get(owner_id)
		if p:
			p.hand.append(card_data)
			_table_rpc_id(owner_id, "client_receive_drawn_batch", [card_id])
			for pid in GameManager.players:
				_table_rpc_id(pid, "client_sync_hand_size", owner_id, p.hand.size())
		did_any = true
	return did_any

# ==============================================================================
# 🪄 SUMMON / REVIVE / SEARCH / SHUFFLE
# ==============================================================================

func _act_revive(amount: int, zone: GameEnums.Zone, filter: GameEnums.Filter, acting_player_id: int) -> bool:
	# Trae carta de descarte a STABLE o HAND según target_zone del effect
	var did_any = false
	for i in max(1, amount):
		# Buscar candidatos en el descarte que matcheen el filtro
		var candidates: Array = []
		for cid in GameManager.discard_pile:
			var c = CardDatabase.get_card_data(cid)
			if c and c.matches_filter(filter):
				candidates.append(cid)
		if candidates.is_empty():
			_notify(acting_player_id, "No hay cartas válidas en el descarte")
			return did_any
		var picked_id = await _request_card_pick(acting_player_id, candidates, "Elige carta del descarte")
		if picked_id == -1: return did_any
		did_any = true
		GameManager.discard_pile.erase(picked_id)
		var card_data = CardDatabase.get_card_data(picked_id)
		var p = GameManager.players.get(acting_player_id)
		if not p: return did_any
		if zone == GameEnums.Zone.STABLE:
			p.stable.append(card_data)
			_table_rpc(&"client_card_entered_stable_visual", acting_player_id, picked_id)
			# Dispara su efecto de ENTRADA (+ registra pasivos + Alambre/Establo Diminuto).
			# Antes solo registraba pasivos → los efectos al entrar no se activaban.
			await resolve_on_enter_stable(card_data, acting_player_id)
			GameManager.check_win_condition()
		else: # HAND
			p.hand.append(card_data)
			_table_rpc_id(acting_player_id, "client_receive_drawn_batch", [picked_id])
			for pid in GameManager.players:
				_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, p.hand.size())
	return did_any

func _act_summon(amount: int, zone: GameEnums.Zone, filter: GameEnums.Filter, acting_player_id: int) -> bool:
	# Pone una carta directo al establo desde HAND o NURSERY
	var did_any = false
	# Queen Bee: si otro jugador tiene la Reina, no puedo invocar básicos a mi establo
	var basics_blocked = passives.basic_unicorns_blocked_against(acting_player_id, GameManager.players.keys())
	for i in max(1, amount):
		var candidates: Array = []
		var p = GameManager.players.get(acting_player_id)
		if not p: return did_any
		if zone == GameEnums.Zone.HAND:
			for c in p.hand:
				if c.matches_filter(filter):
					if c.is_basic_unicorn() and basics_blocked: continue
					candidates.append(c.id)
		elif zone == GameEnums.Zone.NURSERY:
			for cid in GameManager.nursery_deck:
				var c = CardDatabase.get_card_data(cid)
				if c and c.matches_filter(filter):
					candidates.append(cid)
		if candidates.is_empty():
			_notify(acting_player_id, "No hay cartas válidas para invocar")
			return did_any
		var picked_id = await _request_card_pick(acting_player_id, candidates, "Elige carta para invocar")
		if picked_id == -1: return did_any
		did_any = true
		var card_data = CardDatabase.get_card_data(picked_id)
		if zone == GameEnums.Zone.HAND:
			for j in range(p.hand.size()):
				if p.hand[j].id == picked_id:
					p.hand.remove_at(j); break
			for pid in GameManager.players:
				_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, p.hand.size())
		else:
			GameManager.nursery_deck.erase(picked_id)
		p.stable.append(card_data)
		_table_rpc(&"client_card_entered_stable_visual", acting_player_id, picked_id)
		passives.on_card_entered_stable(acting_player_id, card_data)
		# Disparar on_enter_stable de la carta invocada (chain)
		await resolve_on_enter_stable(card_data, acting_player_id)
		GameManager.check_win_condition()
	return did_any

func _act_search_deck(filter: GameEnums.Filter, acting_player_id: int, effect: CardEffect) -> void:
	# Si la condition es SCRY_3: mira top 3, elige 1, devuelve 2 al tope
	if effect.condition == GameEnums.Condition.SCRY_3:
		var top3: Array = []
		for i in 3:
			if GameManager.deck.is_empty(): break
			top3.append(GameManager.deck.pop_back())
		if top3.is_empty(): return
		var picked_id = await _request_card_pick(acting_player_id, top3, "Elige carta a añadir a tu mano")
		if picked_id != -1:
			top3.erase(picked_id)
			var data = CardDatabase.get_card_data(picked_id)
			var p = GameManager.players.get(acting_player_id)
			if p and data:
				p.hand.append(data)
				_table_rpc_id(acting_player_id, "client_receive_drawn_batch", [picked_id])
				for pid in GameManager.players:
					_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, p.hand.size())
		# Devolver el resto al tope (en orden)
		for cid in top3:
			GameManager.deck.append(cid)
		return

	# Si la condition es TAG_NARWHAL: buscar cartas con tag "narwhal"
	var candidates: Array = []
	for cid in GameManager.deck:
		var c = CardDatabase.get_card_data(cid)
		if not c: continue
		var matches = c.matches_filter(filter)
		if effect.condition == GameEnums.Condition.TAG_NARWHAL:
			matches = c.has_tag("narwhal")
		if matches:
			candidates.append(cid)
	if candidates.is_empty(): return
	var picked = await _request_card_pick(acting_player_id, candidates, "Busca una carta en el mazo")
	if picked == -1: return
	GameManager.deck.erase(picked)
	var card_data = CardDatabase.get_card_data(picked)
	var p2 = GameManager.players.get(acting_player_id)
	if p2 and card_data:
		p2.hand.append(card_data)
		_table_rpc_id(acting_player_id, "client_receive_drawn_batch", [picked])
		for pid in GameManager.players:
			_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, p2.hand.size())
	GameManager.deck.shuffle()

func _act_shuffle_deck(filter: GameEnums.Filter, acting_player_id: int) -> void:
	# Si filter es hand_and_discard, también barajar la mano y el descarte
	if filter == GameEnums.Filter.HAND_AND_DISCARD:
		var p = GameManager.players.get(acting_player_id)
		if p:
			for c in p.hand:
				GameManager.deck.append(c.id)
			p.hand.clear()
			_table_rpc_id(acting_player_id, "client_replace_hand", [])
			for pid in GameManager.players:
				_table_rpc_id(pid, "client_sync_hand_size", acting_player_id, 0)
		for cid in GameManager.discard_pile:
			GameManager.deck.append(cid)
		GameManager.discard_pile.clear()
	else:
		# Solo barajar descarte en deck
		for cid in GameManager.discard_pile:
			GameManager.deck.append(cid)
		GameManager.discard_pile.clear()
	GameManager.deck.shuffle()
	_table_rpc(&"client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())

# ==============================================================================
# 🗑️ REMOCIÓN DE CARTAS DEL ESTABLO (destroy / sacrifice / move)
# ==============================================================================

func _remove_from_stable(owner_id: int, card_id: int, is_destroy: bool) -> void:
	var player = GameManager.players.get(owner_id)
	if not player: return

	# --- CABALLERO NEGRO (replace_target_unicorn) ---
	# Si un unicornio del dueño sería DESTRUIDO y tiene un Caballero Negro distinto,
	# puede sacrificar el Caballero en lugar del unicornio.
	if is_destroy:
		var victim: CardData = null
		for c in player.stable:
			if c.id == card_id: victim = c; break
		if victim and victim.is_unicorn() and passives.has_black_knight(owner_id):
			var knight_id = passives.source_card_of(owner_id, GameEnums.Condition.REPLACE_TARGET_UNICORN)
			if knight_id != -1 and knight_id != card_id:
				var accept = await _request_confirm(owner_id,
					"¿Sacrificar el Caballero Negro en lugar de perder tu Unicornio?")
				if accept:
					await _remove_from_stable(owner_id, knight_id, false)
					return # el unicornio original SOBREVIVE

	var card_data: CardData = null
	for i in range(player.stable.size()):
		if player.stable[i].id == card_id:
			card_data = player.stable[i]
			player.stable.remove_at(i)
			break
	if not card_data: return
	# Determinar destino especial ANTES de disparar otros efectos
	var goes_to_hand = _returns_to_hand_on_destroy(card_data)
	# Desregistrar pasivos
	passives.on_card_left_stable(owner_id, card_data)
	# Disparar on_destroy (salta el self-return, que es enrutamiento, no acción)
	await resolve_on_destroy(card_data, owner_id)
	# DESTINO de la carta:
	if card_data.is_baby_unicorn() and GameManager.current_rules.nursery_is_safe_zone:
		# Bebé protegido → Guardería
		GameManager.nursery_deck.append(card_id)
		_table_rpc(&"client_card_left_stable", owner_id, card_id)
	elif goes_to_hand:
		# Unicornio Volador → vuelve a la mano de su dueño en vez del descarte
		var op = GameManager.players.get(owner_id)
		if op:
			op.hand.append(card_data)
			_table_rpc(&"client_card_left_stable", owner_id, card_id)
			_table_rpc_id(owner_id, "client_receive_drawn_batch", [card_id])
			for pid in GameManager.players:
				_table_rpc_id(pid, "client_sync_hand_size", owner_id, op.hand.size())
	else:
		# Caso normal → descarte
		GameManager.discard_pile.append(card_id)
		_table_rpc(&"client_card_left_stable", owner_id, card_id)
	_table_rpc(&"client_sync_deck_counters", GameManager.deck.size(), GameManager.discard_pile.size(), GameManager.nursery_deck.size())
	# ALAMBRE DE PÚAS: un unicornio salió del establo
	if card_data.is_unicorn():
		await _on_unicorn_stable_changed(owner_id, false)

# Saca una carta del establo SIN destruirla ni descartarla (para mover/robar/devolver).
# Desregistra pasivos y dispara Alambre de Púas (salida), pero NO dispara on_destroy.
# Devuelve el CardData extraído, o null.
func _extract_from_stable(owner_id: int, card_id: int) -> CardData:
	var player = GameManager.players.get(owner_id)
	if not player: return null
	var card_data: CardData = null
	for i in range(player.stable.size()):
		if player.stable[i].id == card_id:
			card_data = player.stable[i]
			player.stable.remove_at(i)
			break
	if not card_data: return null
	passives.on_card_left_stable(owner_id, card_data)
	_table_rpc(&"client_card_left_stable", owner_id, card_id)
	if card_data.is_unicorn():
		await _on_unicorn_stable_changed(owner_id, false)
	return card_data

# ==============================================================================
# 🔁 REACCIONES DE ESTADO (Barbed Wire / Tiny Stable)
# ==============================================================================

func _on_unicorn_stable_changed(owner_id: int, entered: bool) -> void:
	# Alambre de Púas: descarta 1 carta cada vez que un unicornio entra o sale
	if passives.has_barbed_wire(owner_id):
		await _force_discard_one(owner_id)
	# Establo Diminuto: solo al ENTRAR puede superar el límite de 5
	if entered and passives.has_tiny_stable(owner_id):
		await _enforce_tiny_stable(owner_id)

func _count_unicorns(owner_id: int) -> int:
	var player = GameManager.players.get(owner_id)
	if not player: return 0
	var total = 0
	for c in player.stable:
		total += c.unicorn_count_value()
	return total

func _enforce_tiny_stable(owner_id: int) -> void:
	# Sacrifica unicornios hasta tener 5 o menos
	while _count_unicorns(owner_id) > 5:
		var pick = await _request_stable_target(owner_id, GameEnums.Scope.SELF, GameEnums.Filter.UNICORN_CARD, false)
		if pick.is_empty(): break
		await _remove_from_stable(pick["owner_id"], pick["card_id"], false)

func _force_discard_one(owner_id: int) -> void:
	var picked = await _request_discard_pick(owner_id, GameEnums.Filter.ANY)
	if picked == -1: return
	var p = GameManager.players.get(owner_id)
	if not p: return
	for j in range(p.hand.size()):
		if p.hand[j].id == picked:
			p.hand.remove_at(j); break
	GameManager.discard_pile.append(picked)
	_table_rpc(&"client_card_left_hand", owner_id, picked)
	for pid in GameManager.players:
		_table_rpc_id(pid, "client_sync_hand_size", owner_id, p.hand.size())

# Mueve una carta de un establo a otro (sin destruir). Actualiza pasivos y visual.
func _move_stable_card(from_id: int, to_id: int, card_id: int) -> void:
	var to_p = GameManager.players.get(to_id)
	if not to_p: return
	var card_data = await _extract_from_stable(from_id, card_id)
	if not card_data: return
	to_p.stable.append(card_data)
	passives.on_card_entered_stable(to_id, card_data)
	_table_rpc(&"client_card_entered_stable_visual", to_id, card_id)
	if card_data.is_unicorn():
		await _on_unicorn_stable_changed(to_id, true)

# ==============================================================================
# 🎴 ACCIONES CUSTOM (cartas con mecánica especial)
# ==============================================================================

# Intercambio de Unicornios (ID 72): mueve un unicornio tuyo al establo de un
# oponente, luego HURTA un unicornio de ese oponente.
func _custom_unicorn_swap(acting_player_id: int) -> void:
	# 1. Elige un unicornio propio
	var mine = await _request_stable_target(acting_player_id, GameEnums.Scope.SELF, GameEnums.Filter.UNICORN_CARD, false)
	if mine.is_empty(): return
	# 2. Elige oponente
	var opps = GameManager.get_opponents_of(acting_player_id)
	if opps.is_empty(): return
	var target_id = opps[0]
	if opps.size() > 1:
		target_id = await _request_player_pick(acting_player_id, opps)
		if target_id == -1: return
	# 3. Mueve mi unicornio al establo del oponente
	await _move_stable_card(acting_player_id, target_id, mine["card_id"])
	# 4. Hurta un unicornio del oponente
	var stolen = await _request_owner_stable_pick(acting_player_id, target_id, GameEnums.Filter.UNICORN_CARD)
	if stolen == -1: return
	await _move_stable_card(target_id, acting_player_id, stolen)
	GameManager.check_win_condition()

# Cambio de Objetivo (ID 73): mueve una carta de Ventaja/Desventaja de cualquier
# establo a cualquier otro.
func _custom_retarget(acting_player_id: int) -> void:
	# 1. Reunir todas las mejoras/degradaciones de TODOS los establos
	var candidates: Array = []
	for pid in GameManager.players:
		var pl = GameManager.players[pid]
		for c in pl.stable:
			if c.is_upgrade() or c.is_downgrade():
				candidates.append({"owner_id": pid, "card_id": c.id})
	if candidates.is_empty(): return
	var chosen = await _request_candidate_pick(acting_player_id, candidates, "Elige Ventaja/Desventaja a mover")
	if chosen.is_empty(): return
	# 2. Elegir destino (cualquier jugador distinto del dueño actual)
	var dests: Array[int] = []
	for pid in GameManager.players:
		if pid != chosen["owner_id"]:
			dests.append(pid)
	if dests.is_empty(): return
	var dest_id = dests[0]
	if dests.size() > 1:
		dest_id = await _request_player_pick(acting_player_id, dests)
		if dest_id == -1: return
	await _move_stable_card(chosen["owner_id"], dest_id, chosen["card_id"])

# ==============================================================================
# 👥 REQUESTS DE UI (esperan input del jugador activo)
# ==============================================================================

# Pide al jugador que pague el costo (descarte/sacrifice obligatorio).
# Retorna true si pagó, false si rechazó.
func _request_pay_cost(effect: CardEffect, player_id: int) -> bool:
	var msg = ""
	match effect.cost_action:
		GameEnums.Action.DISCARD:
			msg = "Descarta %d carta(s) para activar" % effect.cost_amount
		GameEnums.Action.SACRIFICE:
			msg = "Sacrifica %d carta(s) para activar" % effect.cost_amount
		_:
			return true
	# Si es opcional (no cost_required), permitir cancelar
	var optional = not effect.cost_required
	_table_rpc_id(player_id, "client_open_cost_pay",
		int(effect.cost_action), effect.cost_amount,
		int(effect.cost_target_type), msg, optional)
	var result = await cost_paid
	if not result[0]: return false
	# Aplicar el coste
	var p = GameManager.players.get(player_id)
	if not p: return false
	for cid in result[1]:
		if effect.cost_action == GameEnums.Action.DISCARD:
			# Quitar de mano → descarte
			for j in range(p.hand.size()):
				if p.hand[j].id == cid:
					p.hand.remove_at(j); break
			GameManager.discard_pile.append(cid)
			_table_rpc(&"client_card_left_hand", player_id, cid)
		elif effect.cost_action == GameEnums.Action.SACRIFICE:
			await _remove_from_stable(player_id, cid, false)
	for pid in GameManager.players:
		_table_rpc_id(pid, "client_sync_hand_size", player_id, p.hand.size())
	return true

func _request_discard_pick(player_id: int, filter: GameEnums.Filter) -> int:
	var p = GameManager.players.get(player_id)
	if not p or p.hand.is_empty(): return -1
	# Si el filter no aplica (any), elige automáticamente la primera
	var candidates: Array = []
	for c in p.hand:
		if c.matches_filter(filter):
			candidates.append(c.id)
	if candidates.is_empty(): return -1
	_table_rpc_id(player_id, "client_open_card_pick", candidates, "Elige carta a descartar", false)
	var result = await target_picked
	return result[0]

func _request_stable_target(acting_player_id: int, scope: GameEnums.Scope, filter: GameEnums.Filter, exclude_self_immunity: bool) -> Dictionary:
	var candidates := TargetResolver.find_candidates(acting_player_id, scope, GameEnums.Zone.STABLE, filter, passives)
	var source_is_magic = _current_source != null and _current_source.is_magic_spell()
	var wants_unicorn = filter in [GameEnums.Filter.UNICORN_CARD, GameEnums.Filter.BASIC_UNICORN,
		GameEnums.Filter.MAGICAL_UNICORN, GameEnums.Filter.BABY_UNICORN]

	var clean: Array = []
	for cand in candidates:
		var data = CardDatabase.get_card_data(cand["card_id"])
		var owner = cand["owner_id"]
		# Pandamonio: los unicornios cuentan como pandas → no los afectan efectos que apuntan a Unicornios
		if data.is_unicorn() and wants_unicorn and passives.unicorns_are_pandas(owner):
			continue
		# Inmunidad a DESTROY (Rainbow Aura) y a DESTROY por Magia (Gaticornio Mágico)
		if exclude_self_immunity and data.is_unicorn():
			if passives.unicorn_immune_to_destroy(owner):
				continue
			if source_is_magic and passives.unicorn_immune_to_magic(owner):
				continue
		clean.append(cand)
	candidates = clean
	if candidates.is_empty():
		_notify(acting_player_id, "No hay cartas válidas para el efecto")
		return {}
	# SIEMPRE mostramos el picker (aunque haya 1 candidato) para que el jugador
	# pueda elegir o CANCELAR. Antes auto-seleccionaba y forzaba la jugada.
	_table_rpc_id(acting_player_id, "client_open_stable_target_pick", candidates, "Elige una carta objetivo")
	var result = await target_picked
	return {"card_id": result[0], "owner_id": result[1]}

func _request_card_pick(player_id: int, card_ids: Array, prompt: String) -> int:
	if card_ids.is_empty(): return -1
	# SIEMPRE mostramos el picker (con cancelar), aunque haya 1 candidato.
	_table_rpc_id(player_id, "client_open_card_pick", card_ids, prompt, true)
	var result = await target_picked
	return result[0]

func _request_player_pick(acting_player_id: int, candidates: Array[int]) -> int:
	if candidates.is_empty(): return -1
	if candidates.size() == 1: return candidates[0]
	_table_rpc_id(acting_player_id, "client_open_player_pick", candidates, "Elige un jugador")
	var result = await target_picked
	return result[0]

func _request_choice(_effect: CardEffect, player_id: int) -> int:
	# Pide al jugador elegir 0 (primary) o 1 (secondary)
	var labels = ["Opción A (primaria)", "Opción B (secundaria)"]
	_table_rpc_id(player_id, "client_open_binary_choice", labels)
	var result = await target_picked
	return result[0]

# Confirmación Sí/No. Devuelve true si el jugador elige la primera opción.
func _request_confirm(player_id: int, msg: String) -> bool:
	var labels = ["Sí: " + msg, "No"]
	_table_rpc_id(player_id, "client_open_binary_choice", labels)
	var result = await target_picked
	return result[0] == 0

# Pick de una carta del establo de UN jugador concreto (devuelve card_id o -1)
func _request_owner_stable_pick(viewer_id: int, owner_id: int, filter: GameEnums.Filter) -> int:
	var owner = GameManager.players.get(owner_id)
	if not owner: return -1
	var candidates: Array = []
	for c in owner.stable:
		if c.matches_filter(filter):
			# Respetar Pandamonio si se busca unicornio
			if c.is_unicorn() and filter == GameEnums.Filter.UNICORN_CARD and passives.unicorns_are_pandas(owner_id):
				continue
			candidates.append({"owner_id": owner_id, "card_id": c.id})
	if candidates.is_empty(): return -1
	_table_rpc_id(viewer_id, "client_open_stable_target_pick", candidates, "Elige una carta")
	var result = await target_picked
	return result[0]

# Pick de una lista explícita de candidatos {owner_id, card_id}
func _request_candidate_pick(viewer_id: int, candidates: Array, prompt: String) -> Dictionary:
	if candidates.is_empty(): return {}
	_table_rpc_id(viewer_id, "client_open_stable_target_pick", candidates, prompt)
	var result = await target_picked
	return {"card_id": result[0], "owner_id": result[1]}

# ==============================================================================
# 🌐 RPCs (cliente → servidor): respuestas de pickers
# ==============================================================================

@rpc("any_peer", "call_local", "reliable")
func server_pick_response(value_a: int, value_b: int):
	if not multiplayer.is_server(): return
	target_picked.emit(value_a, value_b)

@rpc("any_peer", "call_local", "reliable")
func server_cost_response(success: bool, paid_ids: Array):
	if not multiplayer.is_server(): return
	cost_paid.emit(success, paid_ids)

func _resolve_player_targets(scope: GameEnums.Scope, acting_player_id: int) -> Array[int]:
	var out: Array[int] = []
	for p in GameManager.players:
		match scope:
			GameEnums.Scope.SELF:
				if p == acting_player_id: out.append(p)
			GameEnums.Scope.CHOSEN_OPPONENT:
				if p != acting_player_id: out.append(p)
			GameEnums.Scope.ALL_OPPONENTS:
				if p != acting_player_id: out.append(p)
			GameEnums.Scope.ALL_PLAYERS:
				out.append(p)
			GameEnums.Scope.ANY_PLAYER:
				out.append(p)
	return out
