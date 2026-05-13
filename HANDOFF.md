# Unstable Unicorns 2D — Handoff de Contexto

> Documento maestro para continuar el desarrollo en otra sesión de Claude Code.
> Última actualización: 2026-05-13 · Sesión previa: Fase 1 completada.

---

## 🎯 Comando para retomar en nueva sesión

Copia y pega esto al iniciar una nueva sesión de Claude Code en este proyecto:

```
Estoy continuando el desarrollo de Unstable Unicorns 2D en Godot 4.6. 
Lee el archivo HANDOFF.md en la raíz del proyecto que contiene TODO el 
contexto: arquitectura, lo que está hecho, lo que falta, decisiones de 
diseño y el roadmap. 

Después de leerlo, dime un resumen breve de en qué fase estamos y 
pregúntame por dónde quiero continuar. NO empieces a programar todavía 
hasta que confirmemos el siguiente paso.

Importante: cuando haya que tocar nodos/escenas en el editor visual, 
guíame paso a paso para que yo lo haga (estoy aprendiendo Godot). 
Para scripts puros podés editarlos directamente.
```

---

## 📋 Resumen ejecutivo

**¿Qué es?** Juego de cartas multijugador en red basado en *Unstable Unicorns* (2-4 jugadores).

**Stack:** Godot 4.6.2 · GDScript · ENet multiplayer · GL Compatibility renderer.

**Estado:** Fase 1 completada (bucle de turno funcional). Próximo: Fase 2 (EffectProcessor).

**Mecánica core:** Cada jugador acumula unicornios en su establo. Gana quien llegue primero a 7 (configurable). Las cartas permiten robar, destruir, sacrificar, hurtar, etc.

---

## 🏗️ Arquitectura del proyecto

```
unestable-unicorns-2d/
├── assets/
│   ├── data/
│   │   └── base_deck_data.json        ← 85 cartas con efectos modelados
│   └── textures/cards/                 ← PNGs de las cartas
├── scripts/
│   ├── core/
│   │   ├── CardDatabase.gd            ← Autoload: carga JSON, get_card_data()
│   │   ├── GameManager.gd             ← Autoload: red, turnos, fases, victoria
│   │   ├── GameEnums.gd               ← Todos los enums (Type, Action, Condition...)
│   │   ├── EffectProcessor.gd         ← STUB vacío (Fase 2)
│   │   ├── GameRules.gd               ← Resource serializable (Reglas configurables)
│   │   └── PlayerData.gd              ← RefCounted (hand, stable, name, id)
│   ├── data/
│   │   ├── CardData.gd                ← Datos de carta + helpers (is_unicorn, matches_filter...)
│   │   └── CardEffect.gd              ← Estructura de efecto (trigger, condition, cost, primary, secondary)
│   ├── utils/
│   │   └── DataParser.gd              ← Strings JSON → Enums
│   └── tests/
│       └── TestLoader.gd              ← 11 tests de integridad
├── scenes/
│   ├── cards/
│   │   ├── CardUI.tscn + card_ui.gd                ← Carta interactiva
│   │   └── CardInfoPanel.tscn + card_info_panel.gd ← Panel de detalle
│   ├── game/
│   │   ├── Lobby.tscn + lobby.gd                    ← Pantalla de lobby
│   │   ├── GameTable.tscn + game_table.gd           ← Mesa de juego (con HUD por código)
│   │   └── RivalZone.tscn + rival_zone.gd           ← Zona visual de cada rival
│   └── ui/
│       └── CardSelector.tscn + card_selector.gd     ← Modal para elegir 1 carta de N
├── project.godot                                     ← Autoloads: CardDatabase, GameManager
└── HANDOFF.md                                        ← Este archivo
```

### Autoloads (singletons globales)

Configurados en `project.godot`:
- `CardDatabase` — Carga `base_deck_data.json` al iniciar. Acceso por `CardDatabase.get_card_data(id)`.
- `GameManager` — Estado global: jugadores, mazos, turnos, fases, victoria. RPC backbone.

---

## 🗂️ Modelo de datos

### Estructura de una carta en JSON

```json
{
  "meta": {
    "id": 3,
    "version": "base_set_2nd_edition",
    "image_path": "res://assets/textures/cards/cartas_base/3_unicorn_poison.png"
  },
  "identity": {
    "name": {"es": "Veneno De Unicornio", "en": "Unicorn Poison"},
    "type": "magic_spell",
    "tags": ["unicorn", "poison"]
  },
  "visual": {
    "description": {"es": "DESTRUYE una carta de Unicornio.", "en": "..."}
  },
  "gameplay": {
    "is_nursery": false,
    "deck_location": "main_deck",
    "effects": [
      {
        "order": 1,
        "trigger": "on_play",
        "condition": "none",
        "cost": {"required": false, "action": "none", "amount": 0, "target_type": "none"},
        "primary_action": {
          "type": "destroy",
          "amount": 1,
          "target_scope": "chosen_opponent",
          "target_zone": "stable",
          "target_filter": "unicorn_card"
        },
        "secondary_action": null
      }
    ]
  }
}
```

### Enums clave (GameEnums.gd)

- **CardType:** BABY_UNICORN, BASIC_UNICORN, MAGICAL_UNICORN, MAGIC_SPELL, INSTANT, UPGRADE, DOWNGRADE, REFERENCE
- **Trigger:** ON_PLAY, ON_ENTER_STABLE, ON_TURN_START, ON_DESTROY, ON_SACRIFICE, PASSIVE, ON_CARD_PLAYED
- **Action:** DRAW, DISCARD, DESTROY, SACRIFICE, STEAL, PULL, SWAP_HANDS, RETURN_TO_HAND, RETURN_TO_NURSERY, REVIVE, SUMMON, SEARCH_DECK, SHUFFLE_DECK, PROTECT, CANCEL, SKIP_TURN, EXTRA_TURN, EXTRA_ACTION
- **Filter:** ANY, SELF, UNICORN_CARD, BABY_UNICORN, BASIC_UNICORN, MAGICAL_UNICORN, UPGRADE_CARD, DOWNGRADE_CARD, MAGIC_SPELL, INSTANT, HAND_AND_DISCARD
- **Zone:** DECK, HAND, STABLE, DISCARD_PILE, NURSERY, VOID
- **Scope:** SELF, CHOSEN_OPPONENT, ALL_OPPONENTS, ALL_PLAYERS, ANY_PLAYER
- **Condition:** 24 valores semánticos (ver `GameEnums.gd` para lista completa con comentarios)

### Condiciones especiales (Condition enum)

Las conditions modifican el comportamiento del effect. El EffectProcessor (Fase 2) las debe interpretar:

| Categoría | Conditions |
|---|---|
| **Trigger modifiers** | `ALWAYS`, `IN_STABLE`, `OR_ON_SACRIFICE`, `OR_ON_LEAVE_STABLE` |
| **Inmunidades** | `IMMUNE_TO_DESTROY`, `IMMUNE_TO_MAGIC_DESTROY` |
| **Bloqueos** | `PREVENT_BASIC_ENTRY`, `PREVENT_PLAY_NEIGH`, `PREVENT_PLAY_UPGRADE`, `PREVENT_NEIGH_ON_OWNER` |
| **Transformaciones** | `DISABLE_UNICORN_EFFECTS`, `CONVERT_UNICORNS_TO_PANDAS`, `HAND_VISIBLE`, `COUNTS_AS_2_UNICORNS` |
| **Numéricas** | `IF_UNICORN_COUNT_EXCEEDS_5` |
| **Acción** | `SCRY_3`, `TAG_NARWHAL`, `RANDOM`, `CHOICE_EITHER`, `MOVE_UNICORN_TO_OPPONENT`, `RETARGET_UPGRADE_DOWNGRADE`, `CANNOT_BE_NEIGHED`, `REPLACE_TARGET_UNICORN` |

---

## ✅ Lo que está COMPLETO

### Fase 0 — Base (preexistente)
- Red ENet (host/join, max 4 jugadores, puerto 7777)
- Handshake de jugadores, sincronización de reglas
- Carga de JSON (85 cartas) a objetos GDScript tipados
- Lobby UI con configuración de reglas
- Selección de bebé inicial (modal CardSelector)
- Reparto inicial de mano (5 cartas)
- Orden de turnos sincronizado por RPC
- Sistema de zonas visuales: mano propia, establo propio (con fila para unicornios y otra para upgrades/downgrades), zonas rivales

### Sesión actual — Trabajo realizado

#### 1. JSON corregido (42 cartas con errores arreglados)

Errores que existían y se corrigieron:
- **Scopes incorrectos:** "Each player" estaba como `self` → ahora `all_players` (IDs 4, 24, 42, 64, 67, 82)
- **Cantidades erróneas:** Good Deal robaba 1 en vez de 3 (ID 5), Unicorn on the Cob igual (ID 30)
- **Costes faltantes:** Glitter Bomb, Caffeine Overload, Rainbow Lasso, Necromancer, Phoenix, etc. (IDs 9, 12, 22, 25, 29, 41, 43, 58, 71, 75, 76)
- **Efectos pasivos mal modelados:** Magical Kittencorn tenía acción `destroy` en vez de `protect`; Rainbow Aura igual; Blinding Light/Nanny Cam/Yay/Pandamonium todos con condition apropiada (IDs 8, 26, 28, 35, 37, 39, 46, 52, 76, 80)
- **Triggers erróneos:** Neigh era `on_play` debería ser `on_card_played` (IDs 25, 34, 70, 72)
- **Efectos OR (choice_either):** Targeted Destruction, Chainsaw Unicorn, Re-Target (IDs 10, 49, 73)
- **Efectos completamente erróneos reemplazados:** Black Knight, Unicorn Oracle, Neigh, Kiss of Life, Back Kick, Super Neigh (IDs 16, 18, 34, 45, 62, 70)
- **Acciones secundarias añadidas:** Shabby/Classy Narwhal/Mystical Vortex/Reset Button (IDs 15, 17, 21, 27, 42, 50, 51, 66, 67, 81, 85)

Resultado: **85 cartas válidas, validadas contra todos los maps de DataParser**.

#### 2. Sistema de tipos consolidado

- **`GameEnums.gd`**: añadido enum `Condition` con 24 valores documentados.
- **`DataParser.gd`**: nuevo `CONDITION_MAP` + `parse_condition()`. Maps existentes ampliados con `extra_turn`, `skip_turn`, `on_card_played`, `all_opponents`, `void`.
- **`CardEffect.gd`**: `condition: String` → `condition: GameEnums.Condition` (type-safe). Helper `has_cost()`.
- **`CardData.gd`**: añadidos helpers: `is_unicorn()`, `is_baby_unicorn()`, `is_basic_unicorn()`, `is_magical_unicorn()`, `is_upgrade()`, `is_downgrade()`, `is_magic_spell()`, `is_instant()`, `is_permanent()`, `matches_filter(filter)`, `has_tag(tag)`, `unicorn_count_value()` (devuelve 2 para Ginormous).
- **`CardDatabase.gd`**: parseo defensivo con `.get()`. Helpers `get_cards_by_type(type)`, `get_cards_by_tag(tag)`.
- **`TestLoader.gd`**: 11 tests con assert_eq cubriendo correcciones específicas.

#### 3. Fase 1 — Bucle de turno completo

**`GameManager.gd`** ahora maneja flujo authorative:

```
_server_start_turn(player_id)
  ↓ phase = START (placeholder para on_turn_start effects)
  ↓ wait 0.4s
_server_advance_to_draw_phase()
  ↓ phase = DRAW
  ↓ auto-draw 1 carta, RPC al dueño + tamaño a rivales
  ↓ wait 0.3s
_server_advance_to_action_phase()
  ↓ phase = ACTION, actions_remaining = 1
  ↓ (esperar a que el jugador juegue carta o haga End Turn)
[evento: consume_action o request_end_turn]
_server_advance_to_end_phase()
  ↓ phase = END
  ↓ enforce hand_limit (descarte forzado por ahora desde el front)
  ↓ wait 0.4s
_server_next_turn() → loop
```

Nuevas señales en GameManager:
- `actions_changed(remaining: int)`
- `game_won(winner_id, winner_name)`
- `hand_size_changed(player_id, new_size)`
- `stable_changed(player_id)`

Nuevos métodos:
- `consume_action()` — el jugador gastó 1 acción
- `grant_extra_action(amount)` — Double Dutch dará +1 en Fase 2
- `check_win_condition()` — usa `unicorn_count_value()` (Ginormous cuenta 2)
- `request_end_turn` RPC — validado contra turno y fase
- `get_opponents_of(player_id)` — helper

**`game_table.gd`** ahora tiene:
- **HUD por código** (CanvasLayer dinámico en `_build_hud()`): Turno, Fase, Acciones, contador Mazo/Descarte, botón "Finalizar Turno"
- **Panel de victoria** modal (`_show_winner_panel`)
- **Validación server-side** completa en `server_play_card`: turno activo, fase ACTION, acciones > 0, posesión de la carta
- **Downgrades** van al establo del oponente (auto-target al primero — picker pendiente Fase 3)
- **Cartas en mano se deshabilitan** automáticamente fuera de tu turno/fase (`_refresh_hand_interactivity()`)
- **Predicción optimista** al jugar carta (tween local)

---

## ❌ Lo que FALTA — Roadmap

### Fase 2 — EffectProcessor (siguiente prioridad)
**Archivo:** `scripts/core/EffectProcessor.gd` (actualmente vacío).

Necesita implementar:

```
EffectProcessor.resolve_card_play(card_data, playing_player_id)
  → para cada effect en card.effects:
    → if trigger matches ON_PLAY or ON_ENTER_STABLE:
      → check condition (puede prevenir o modificar)
      → if cost.required: pedir al jugador pagar (Fase 3 con UI)
      → execute_action(primary_action, context)
      → if has_secondary: execute_action(secondary_action, context)
```

Acciones a implementar (orden recomendado de complejidad):
1. **Fácil sin UI:** DRAW (self), DISCARD (self), SHUFFLE_DECK, RETURN_TO_NURSERY
2. **Necesita target picker (depende Fase 3):** DESTROY, SACRIFICE, STEAL, PULL, RETURN_TO_HAND, REVIVE
3. **Complejas:** SUMMON (de hand/nursery a stable), SEARCH_DECK (con scry_3), SWAP_HANDS
4. **Meta-acciones:** SKIP_TURN, EXTRA_TURN, EXTRA_ACTION (este ya tiene gancho con `grant_extra_action`)
5. **Pasivos:** PROTECT con todas sus condiciones (prevent_basic_entry, immune_to_destroy, etc.)

Sistema de **PassiveRegistry** sugerido: mantener un diccionario de pasivos activos `{player_id: {condition: [card_ids]}}` que se consulta antes de cada acción que pudiera ser bloqueada.

### Fase 3 — Sistema de Targeting (UI)
**Aquí entra el aprendizaje de nodos del usuario.**

Nuevo archivo `scenes/ui/TargetSelector.tscn` + `target_selector.gd`:
- Resaltar cartas válidas en el establo del scope correcto
- Esperar click del jugador activo
- Cancelar con ESC

RPCs coordinados:
- Server: `rpc_id(active_player, "open_target_selection", filter, scope, zone)`
- Client: muestra UI, espera elección
- Client: `rpc_id(1, "server_target_chosen", card_id, owner_id)`

### Fase 4 — Ventana Neigh
Mecánica crítica de Unstable Unicorns. Cuando alguien juega una carta, se abre una **ventana de respuesta** de N segundos donde cualquier jugador puede jugar un Relincho.

```
[Server] Recibe play_card
  → ¿hay alguien con Neigh + cards permite jugar Neigh?
  → rpc("open_neigh_window", card_id, original_player)
  → timer 5s
  → ¿alguien jugó Neigh? → cancela carta original, abre OTRA ventana (super-neigh)
  → ¿nadie? → resolver carta original
```

Cuidado con condition `PREVENT_NEIGH_ON_OWNER` (Yay) y `CANNOT_BE_NEIGHED` (Super Neigh).

### Fase 5 — Pulido
- Animaciones de movimiento de carta (mano → establo, etc.)
- Sonidos (shuffle, jugar, Neigh)
- Pantalla de game over con botón "Nueva partida"
- Log de jugadas en chat lateral
- Pila de descarte visible y clickeable
- Reemplazar HUD por código con HUD en escena (`scenes/ui/HUD.tscn`)

---

## 🧠 Decisiones de diseño importantes

### Server-authoritative
**Toda la lógica vive en el servidor.** Los clientes solo:
- Envían intenciones (`server_play_card`)
- Reciben estados sincronizados (`sync_turn_state`, `client_card_entered_stable`)

Esto previene cheating y desyncs. El "host" es también el servidor y un cliente más (peer ID 1).

### Cartas viajan como IDs por red
Solo se envían `int` IDs por RPC. Los objetos `CardData` se reconstruyen localmente desde el `CardDatabase` autoload. Esto:
- Ahorra ancho de banda
- Garantiza que todos vean los mismos datos
- Evita serialización compleja

### Condition como enum en vez de string
Decisión hecha en esta sesión: `CardEffect.condition` ahora es `GameEnums.Condition`. Ventaja: el switch en EffectProcessor estará type-safe y el IDE autocompleta.

### Helpers en CardData en vez de duplicar
`is_permanent()`, `matches_filter()`, etc. viven en CardData. Cualquier script que necesite saber "¿esta carta es un upgrade?" usa `card.is_upgrade()` en vez de comparar enums manualmente.

### HUD por código vs por escena
Fase 1 lo construyó por código (`_build_hud()` en game_table.gd) para no requerir tocar el .tscn. **Fase 3 lo vamos a refactorizar a una escena dedicada para enseñar nodos.**

---

## 📐 Reglas del juego (referencia)

### Estructura de turno
```
1. INICIO    → disparar efectos on_turn_start (de tus upgrades/downgrades)
2. ROBO      → robar 1 carta del mazo
3. ACCIÓN    → elegir 1 acción:
               a) Jugar 1 carta de tu mano
               b) No hacer nada (pasar)
4. FIN       → si tienes >7 cartas, descartar al límite
```

### Dónde van las cartas al jugarse
- **Unicornios** (Baby/Basic/Magical) → tu establo
- **Upgrades** → tu establo (fila separada)
- **Downgrades** → establo de un oponente (fila separada)
- **Magic Spells** → al descarte tras resolver efecto
- **Instants (Neighs)** → al descarte; se juegan fuera de turno como respuesta

### Acciones del juego
- **DRAW** — robar del mazo
- **DISCARD** — descartar de tu mano al descarte
- **DESTROY** — eliminar carta del establo de OTRO (al descarte)
- **SACRIFICE** — eliminar carta de TU establo (al descarte)
- **STEAL** — mover carta del establo rival → tu establo
- **PULL** — mover carta de mano rival → tu mano
- **SWAP HANDS** — intercambiar manos con un rival
- **RETURN TO HAND** — establo → mano del dueño
- **NEIGH (cancel)** — cancelar la carta que está jugando alguien

### Condición de victoria
Primer jugador en tener **7 unicornios en su establo** gana. Ginormous Unicorn cuenta como 2.

### Bebés (Baby Unicorns)
- Son **inmortales** en la práctica: si serían destruidos/sacrificados/devueltos, vuelven a la Guardería.
- Cada jugador empieza con 1 bebé elegido en setup.

### Neigh (Relincho)
- Se juega **fuera de turno** como respuesta a cualquier carta jugada.
- Cancela la carta y la envía al descarte.
- Después de un Neigh hay otra ventana para que alguien lo Super-Neigh.
- **Super Neigh** no puede ser Relinchado.

---

## 🚦 Estado de pruebas del usuario

Al cierre de esta sesión, el usuario iba a probar Fase 1 con esta checklist:

### A. Setup inicial
- [ ] HUD arriba muestra Turno/Fase/Acciones
- [ ] Contador Mazo/Descarte arriba a la derecha
- [ ] Botón "Finalizar Turno" abajo a la derecha (deshabilitado al inicio)
- [ ] Botón viejo "Robar carta" invisible

### B. Flujo de turno automático
- [ ] Fase: Inicio → Robo (recibe carta auto) → Acción
- [ ] Texto "Turno: [Nombre] (TÚ)" en amarillo cuando es tu turno

### C. Turno del rival
- [ ] Cartas grises (deshabilitadas)
- [ ] Botón Finalizar Turno deshabilitado

### D. Jugar cartas
- [ ] Unicornio → fila de unicornios, turno pasa
- [ ] Upgrade → fila de upgrades, turno pasa
- [ ] Downgrade → establo del RIVAL, turno pasa
- [ ] Magia → al descarte, turno pasa

### E. Botón Finalizar Turno
- [ ] Pasa al rival sin jugar nada

### F. Victoria
- [ ] Panel central "🏆 ¡VICTORIA!" cuando llegas a 7 unicornios
- [ ] Turnos se detienen

### G. Lo que NO funciona aún (correcto, Fase 2)
- ❌ Efectos de cartas
- ❌ Pasivos
- ❌ Neighs
- ❌ Costes

---

## 🎓 Aprendizaje de Godot — Plan pedagógico

El usuario está aprendiendo Godot. **A partir de la Fase 3 (cuando haya UI nueva)**, los pasos serán:

1. **Claude escribe** los `.gd` (scripts puros)
2. **Claude da instrucciones paso a paso** para tocar el editor:
   ```
   📂 Abre escena X
   🌳 Añade nodo Y como hijo de Z
   ⚙️ Configura propiedades en el Inspector
   🔌 Conecta señal A → B
   ```
3. **El usuario hace clic** en el editor siguiendo las instrucciones

### Conceptos Godot que se irán cubriendo
- Scene tree y composición de nodos
- Control vs Node2D vs Node
- Anchors, offsets, margins (layout responsivo)
- Signals (forma "Godot" de comunicar nodos)
- Instancing (escenas como prefabs)
- Autoloads (singletons globales)
- Scripts adjuntos a nodos

---

## 🐛 Issues conocidos / TODOs menores

- **Hand limit auto-descarte:** actualmente saca cartas del frente (FIFO) — debería ser elección del jugador (pendiente Fase 2 con UI)
- **Downgrade target auto:** elige al primer oponente — debería pickear con UI (Fase 3)
- **Predicción optimista al jugar carta:** si el servidor rechaza, la carta visual ya se destruyó (causaría desync) — no es problema en happy path pero requiere reconciliation futura
- **HUD por código:** funciona pero debería migrarse a escena (`scenes/ui/HUD.tscn`) en Fase 5
- **No hay reconexión:** si un jugador se desconecta, la partida queda colgada
- **Puerto y MAX_CLIENTS hardcoded** en GameManager (7777, 4)

---

## 📁 Archivos críticos para releer al retomar

Si quieres ponerte al día rápido, lee en este orden:

1. `HANDOFF.md` — este archivo
2. `scripts/core/GameEnums.gd` — todos los enums (especialmente Condition)
3. `scripts/core/GameManager.gd` — flujo de turno y red
4. `scripts/data/CardData.gd` y `scripts/data/CardEffect.gd` — modelo
5. `scripts/core/CardDatabase.gd` — cómo se carga el JSON
6. `assets/data/base_deck_data.json` — vistazo a 2-3 cartas (e.g. ID 1, ID 26, ID 34)
7. `scenes/game/game_table.gd` — UI principal + RPCs de juego
8. `scripts/core/EffectProcessor.gd` — está vacío, ahí va Fase 2

---

## ✍️ Convenciones del código

- **Naming:** clases en PascalCase (`CardData`), variables en snake_case (`active_player_id`), constantes en SCREAMING_SNAKE (`MAX_CLIENTS`).
- **RPCs server-side:** prefijo `server_*` (e.g., `server_play_card`)
- **RPCs client-side:** prefijo `client_*` (e.g., `client_card_entered_stable`)
- **Funciones server-only privadas:** prefijo `_server_*` (e.g., `_server_advance_to_draw_phase`)
- **Idioma:** comentarios y print en español, identificadores en inglés.
- **No emojis en código** salvo prints/labels de UI.

---

## 🔗 Referencias

- **Reglas oficiales Unstable Unicorns:** https://teeturtle.com/products/unstable-unicorns
- **Godot 4 docs:** https://docs.godotengine.org/en/stable/
- **GDScript RPC:** https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html

---

*Fin del handoff. Buena suerte con la siguiente sesión.* 🦄
