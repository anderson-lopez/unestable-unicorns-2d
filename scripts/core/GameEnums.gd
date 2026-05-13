class_name GameEnums extends RefCounted

# --- A. TIPOS DE CARTA (Identity) ---
enum CardType {
	UNDEFINED,
	BABY_UNICORN,
	BASIC_UNICORN,
	MAGICAL_UNICORN,
	MAGIC_SPELL,     # Magias Verdes
	INSTANT,         # Relinchos (Neighs)
	UPGRADE,         # Mejoras Naranjas
	DOWNGRADE,       # Degradaciones Amarillas
	REFERENCE        # Cartas de reglas/referencia
}

# --- B. DISPARADORES (Triggers) ---
# ¿Cuándo se activa el efecto?
enum Trigger {
	NONE,
	ON_PLAY,         # Al jugar la carta (Magias/Neighs)
	ON_ENTER_STABLE, # Cuando un unicornio toca la mesa
	ON_TURN_START,   # Efectos recurrentes al inicio del turno
	ON_DESTROY,      # Cuando es destruida o sacrificada
	ON_SACRIFICE,    # Específicamente cuando es sacrificada
	PASSIVE,         # Efecto continuo (ej: "No puedes jugar Neighs")
	ON_CARD_PLAYED   # Reacción inmediata (para los Neighs / Super Neighs)
}

# --- C. ACCIONES (Actions) ---
# ¿Qué hace el efecto?
enum Action {
	NONE,
	DRAW,              # Robar del mazo
	DISCARD,           # Descartar de la mano
	DESTROY,           # Romper carta en establo ajeno
	SACRIFICE,         # Romper carta en establo propio
	STEAL,             # Robar de Establo -> Establo
	PULL,              # Robar de Mano -> Mano
	SWAP_HANDS,        # Intercambiar manos completas (Carta 11)
	RETURN_TO_HAND,    # Devolver del Establo a la Mano
	RETURN_TO_NURSERY, # Bebés volviendo a casa
	REVIVE,            # Cementerio -> Establo/Mano
	SUMMON,            # Jugar carta gratis (ej: Unicornio Arcoíris)
	SEARCH_DECK,       # Buscar carta específica
	SHUFFLE_DECK,      # Barajar
	PROTECT,           # Inmunidad
	CANCEL,            # Neigh (Cancelar jugada)
	SKIP_TURN,         # Saltarse turno (Rhinocorn)
	EXTRA_TURN,        # Jugar otro turno (Change of Luck)
	EXTRA_ACTION       # Jugar 2 cartas en vez de 1 (Double Dutch)
}

# --- D. FILTROS (Target Filter) ---
# ¿A qué cartas afecta?
enum Filter {
	NONE,
	ANY,             # Cualquier carta válida en el contexto
	SELF,            # La carta misma (para efectos de retorno)
	UNICORN_CARD,    # Cualquier unicornio (Bebé, Básico, Mágico)
	BASIC_UNICORN,
	MAGICAL_UNICORN,
	BABY_UNICORN,
	UPGRADE_CARD,
	DOWNGRADE_CARD,
	MAGIC_SPELL,
	INSTANT,
	HAND_AND_DISCARD # Especial para efectos de barajar todo
}

# --- E. ZONAS (Target Zone) ---
# ¿Dónde buscamos o enviamos la carta?
enum Zone {
	NONE,
	DECK,
	HAND,
	STABLE,
	DISCARD_PILE,
	NURSERY,
	VOID # Fuera del juego
}

# --- F. ALCANCE (Target Scope) ---
# ¿A quién afecta?
enum Scope {
	NONE,
	SELF,            # Yo (mi establo/mi mano)
	CHOSEN_OPPONENT, # Un rival específico
	ALL_OPPONENTS,   # Todos los rivales (excluyéndome)
	ALL_PLAYERS,     # Todos (incluyéndome)
	ANY_PLAYER       # Cualquiera (yo o un rival, elección)
}

# --- G. CONDICIONES (Effect Conditions) ---
# Modificadores semánticos del efecto. El EffectProcessor los interpreta.
enum Condition {
	NONE,                          # Sin condición / por defecto
	ALWAYS,                        # Siempre se dispara (bebés cuando son destruidos)
	IN_STABLE,                     # Solo si la carta está en tu establo (upgrades on_turn_start)

	# --- Modificadores que extienden el trigger ---
	OR_ON_SACRIFICE,               # on_destroy + on_sacrifice (Flying Unicorns, Stabby)
	OR_ON_LEAVE_STABLE,            # on_enter_stable + on_leave (Barbed Wire)

	# --- Pasivas: Inmunidades ---
	IMMUNE_TO_DESTROY,             # Rainbow Aura: los unicornios del dueño no pueden ser destruidos
	IMMUNE_TO_MAGIC_DESTROY,       # Magical Kittencorn: no puede ser destruida por Magias

	# --- Pasivas: Bloqueos de juego ---
	PREVENT_BASIC_ENTRY,           # Queen Bee: los básicos no entran a otros establos
	PREVENT_PLAY_NEIGH,            # Slowdown, Ginormous: el dueño no puede jugar Relinchos
	PREVENT_PLAY_UPGRADE,          # Broken Stable: el dueño no puede jugar Mejoras
	PREVENT_NEIGH_ON_OWNER,        # Yay: las cartas del dueño no pueden ser Relinchadas

	# --- Pasivas: Transformaciones de estado ---
	DISABLE_UNICORN_EFFECTS,       # Blinding Light: los efectos de tus unicornios no aplican
	CONVERT_UNICORNS_TO_PANDAS,    # Pandamonium: tus unicornios cuentan como pandas
	HAND_VISIBLE,                  # Nanny Cam: tu mano visible para todos
	COUNTS_AS_2_UNICORNS,          # Ginormous Unicorn: cuenta como 2

	# --- Pasivas: Condicional numérica ---
	IF_UNICORN_COUNT_EXCEEDS_5,    # Tiny Stable: si >5 unicornios, sacrifica uno

	# --- Modificadores de acción ---
	SCRY_3,                        # Unicorn Oracle: mira top 3, elige 1
	TAG_NARWHAL,                   # The Great Narwhal: filter por tag "narwhal"
	RANDOM,                        # Americorn: target aleatorio
	CHOICE_EITHER,                 # Targeted Destruction: primary OR secondary (elección)
	MOVE_UNICORN_TO_OPPONENT,      # Unicorn Swap: das uno, te llevas uno
	RETARGET_UPGRADE_DOWNGRADE,    # Re-Target: mueve upgrade/downgrade entre establos
	CANNOT_BE_NEIGHED,             # Super Neigh: este efecto no puede ser Relinchado
	REPLACE_TARGET_UNICORN         # Black Knight: sacrifícame en lugar de destruir otro unicornio
}

# Constantes útiles para el código
const AMOUNT_ALL: int = -1  # Para acciones como "Destruye TODAS las mejoras"
const AMOUNT_NONE: int = 0
