class_name CardEffect extends RefCounted

# Metadatos del efecto
var order: int = 1
var trigger: GameEnums.Trigger = GameEnums.Trigger.NONE
var condition: GameEnums.Condition = GameEnums.Condition.NONE

# --- COSTO DEL EFECTO ---
var cost_required: bool = false
var cost_action: GameEnums.Action = GameEnums.Action.NONE
var cost_amount: int = 0
var cost_target_type: GameEnums.Filter = GameEnums.Filter.NONE

# --- ACCIÓN PRINCIPAL ---
var primary_action_type: GameEnums.Action = GameEnums.Action.NONE
var primary_amount: int = 0
var primary_scope: GameEnums.Scope = GameEnums.Scope.NONE
var primary_zone: GameEnums.Zone = GameEnums.Zone.NONE
var primary_filter: GameEnums.Filter = GameEnums.Filter.NONE

# --- ACCIÓN SECUNDARIA (Ej: "Sacrifica esto, LUEGO roba carta") ---
var has_secondary: bool = false
var secondary_action_type: GameEnums.Action = GameEnums.Action.NONE
var secondary_amount: int = 0
var secondary_scope: GameEnums.Scope = GameEnums.Scope.NONE
var secondary_zone: GameEnums.Zone = GameEnums.Zone.NONE
var secondary_filter: GameEnums.Filter = GameEnums.Filter.NONE

func has_cost() -> bool:
	return cost_required and cost_action != GameEnums.Action.NONE

func _to_string() -> String:
	return "Effect(Trigger: %s | Action: %s | Cond: %s)" % [
		GameEnums.Trigger.keys()[trigger],
		GameEnums.Action.keys()[primary_action_type],
		GameEnums.Condition.keys()[condition]
	]
