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

	# TEST 2: Validar una carta compleja (ej: ID 4 - Extremely Destructive Unicorn)
	# JSON Original: Action: sacrifice, Scope: self, Zone: stable, Filter: any
	var card_4 = CardDatabase.get_card_data(4)
	if card_4:
		print("\nVerificando ID 4: ", card_4.name_es)
		print("Tipo Enum: ", card_4.type, " (Esperado: MAGICAL_UNICORN = ", GameEnums.CardType.MAGICAL_UNICORN, ")")
		
		if not card_4.effects.is_empty():
			var eff = card_4.effects[0]
			print("Efecto 1 Trigger Enum: ", eff.trigger, " (Esperado: ON_ENTER_STABLE = ", GameEnums.Trigger.ON_ENTER_STABLE, ")")
			print("Acción Primaria Enum: ", eff.primary_action_type, " (Esperado: SACRIFICE = ", GameEnums.Action.SACRIFICE, ")")
		else:
			printerr("FALLO: ID 4 no tiene efectos cargados.")

	# TEST 3: Validar carta con efecto secundario (ej: ID 78 - Shake Up)
	var card_78 = CardDatabase.get_card_data(78)
	if card_78:
		print("\nVerificando ID 78 (Efecto compuesto): ", card_78.name_es)
		var eff = card_78.effects[0]
		print("Tiene secundario: ", eff.has_secondary)
		print("Acción Primaria: ", eff.primary_action_type, " (Shuffle)")
		print("Acción Secundaria: ", eff.secondary_action_type, " (Draw)")
		print("Cantidad Secundaria: ", eff.secondary_amount, " (Esperado: 5)")

	print("\n--- TEST FINALIZADO ---")
