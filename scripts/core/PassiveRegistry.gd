class_name PassiveRegistry extends RefCounted

# Mantiene una lista de pasivos activos: { player_id: { condition: [card_ids] } }
# Se actualiza cuando una carta entra o sale del establo.
# Server-side. Replicado a clientes solo si necesitan saber (hand visible, etc.)

var by_player: Dictionary = {} # player_id -> { Condition -> Array[int] (card ids) }

func clear() -> void:
	by_player.clear()

# Registra todos los pasivos de una carta que entra al establo
func on_card_entered_stable(player_id: int, card_data: CardData) -> void:
	for effect in card_data.effects:
		if effect.trigger == GameEnums.Trigger.PASSIVE:
			_add(player_id, effect.condition, card_data.id)

# Desregistra los pasivos de una carta que sale
func on_card_left_stable(player_id: int, card_data: CardData) -> void:
	for effect in card_data.effects:
		if effect.trigger == GameEnums.Trigger.PASSIVE:
			_remove(player_id, effect.condition, card_data.id)

func _add(player_id: int, cond: GameEnums.Condition, card_id: int) -> void:
	if not by_player.has(player_id):
		by_player[player_id] = {}
	if not by_player[player_id].has(cond):
		by_player[player_id][cond] = []
	if not card_id in by_player[player_id][cond]:
		by_player[player_id][cond].append(card_id)

func _remove(player_id: int, cond: GameEnums.Condition, card_id: int) -> void:
	if not by_player.has(player_id): return
	if not by_player[player_id].has(cond): return
	by_player[player_id][cond].erase(card_id)
	if by_player[player_id][cond].is_empty():
		by_player[player_id].erase(cond)

# Consultas

func player_has(player_id: int, cond: GameEnums.Condition) -> bool:
	if not by_player.has(player_id): return false
	if not by_player[player_id].has(cond): return false
	var ids: Array = by_player[player_id][cond]
	if ids.is_empty(): return false

	# LUZ CEGADORA: si el dueño tiene DISABLE_UNICORN_EFFECTS, los pasivos que
	# provienen de sus propios UNICORNIOS quedan anulados (Reina del Baile,
	# Gordicornio, etc.). Los pasivos de mejoras/desventajas siguen activos.
	if cond != GameEnums.Condition.DISABLE_UNICORN_EFFECTS and _has_blinding_light(player_id):
		for cid in ids:
			var card = CardDatabase.get_card_data(cid)
			if card and not card.is_unicorn():
				return true # hay una fuente NO-unicornio → sigue activo
		return false # todas las fuentes son unicornios → anulado por Luz Cegadora
	return true

# Lectura directa del registro (sin pasar por player_has, para evitar recursión)
func _has_blinding_light(player_id: int) -> bool:
	if not by_player.has(player_id): return false
	var d: Array = by_player[player_id].get(GameEnums.Condition.DISABLE_UNICORN_EFFECTS, [])
	return not d.is_empty()

func anyone_has(cond: GameEnums.Condition) -> bool:
	for pid in by_player:
		if player_has(pid, cond):
			return true
	return false

func players_with(cond: GameEnums.Condition) -> Array[int]:
	var result: Array[int] = []
	for pid in by_player:
		if player_has(pid, cond):
			result.append(pid)
	return result

# Devuelve los IDs de las cartas que están dando el pasivo (útil para "elige una para destruir")
func sources_of(player_id: int, cond: GameEnums.Condition) -> Array:
	if not by_player.has(player_id): return []
	return by_player[player_id].get(cond, [])

# Helpers semánticos comunes

func can_play_instant(player_id: int) -> bool:
	# Ginormous Unicorn y Slowdown bloquean los Relinchos del dueño
	return not player_has(player_id, GameEnums.Condition.PREVENT_PLAY_NEIGH)

func can_play_upgrade(player_id: int) -> bool:
	return not player_has(player_id, GameEnums.Condition.PREVENT_PLAY_UPGRADE)

func owner_immune_to_neigh(player_id: int) -> bool:
	# Yay: tus cartas no pueden ser Relinchadas
	return player_has(player_id, GameEnums.Condition.PREVENT_NEIGH_ON_OWNER)

func unicorn_immune_to_destroy(player_id: int) -> bool:
	# Rainbow Aura
	return player_has(player_id, GameEnums.Condition.IMMUNE_TO_DESTROY)

func basic_unicorns_blocked_against(player_id: int, all_players: Array) -> bool:
	# Queen Bee: si OTRO jugador tiene la Reina, los básicos no pueden entrar
	# al establo de player_id. (La Reina no bloquea su propio establo.)
	for pid in all_players:
		if pid == player_id: continue
		if player_has(pid, GameEnums.Condition.PREVENT_BASIC_ENTRY):
			return true
	return false

func unicorn_immune_to_magic(player_id: int) -> bool:
	# Gaticornio Mágico: no puede ser destruida por cartas de Magia
	return player_has(player_id, GameEnums.Condition.IMMUNE_TO_MAGIC_DESTROY)

func unicorn_effects_disabled(player_id: int) -> bool:
	# Luz Cegadora: los efectos de tus unicornios no se activan
	return player_has(player_id, GameEnums.Condition.DISABLE_UNICORN_EFFECTS)

func unicorns_are_pandas(player_id: int) -> bool:
	# Pandamonio: tus unicornios cuentan como pandas (no unicornios)
	return player_has(player_id, GameEnums.Condition.CONVERT_UNICORNS_TO_PANDAS)

func has_tiny_stable(player_id: int) -> bool:
	# Establo Diminuto: máx 5 unicornios
	return player_has(player_id, GameEnums.Condition.IF_UNICORN_COUNT_EXCEEDS_5)

func has_barbed_wire(player_id: int) -> bool:
	# Alambre de Púas: descarta al entrar/salir un unicornio
	return player_has(player_id, GameEnums.Condition.OR_ON_LEAVE_STABLE)

func has_black_knight(player_id: int) -> bool:
	# Caballero Negro: puede sacrificarse en lugar de destruir otro unicornio
	return player_has(player_id, GameEnums.Condition.REPLACE_TARGET_UNICORN)

# Devuelve el card_id de una carta que da cierto pasivo en el establo del jugador (o -1)
func source_card_of(player_id: int, cond: GameEnums.Condition) -> int:
	var srcs = sources_of(player_id, cond)
	return srcs[0] if not srcs.is_empty() else -1
