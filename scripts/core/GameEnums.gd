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
	ON_CARD_PLAYED   # Reacción inmediata (para los Neighs)
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
	SKIP_TURN,         # Saltarse turno
	EXTRA_TURN,        # Jugar otro turno
	EXTRA_ACTION       # Jugar 2 cartas en vez de 1
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
	ALL_OPPONENTS,   # Todos los rivales
	ALL_PLAYERS,     # Todos (incluyéndome)
	ANY_PLAYER       # Cualquiera
}

# Constantes útiles para el código
const AMOUNT_ALL: int = -1  # Para acciones como "Destruye TODAS las mejoras"
const AMOUNT_NONE: int = 0
