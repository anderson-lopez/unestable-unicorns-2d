# Unstable Unicorns 2D — Historial completo de desarrollo

> Crónica de TODO lo trabajado entre Anderson y Claude, en orden.
> Documento complementario a **HANDOFF.md** (que tiene el detalle técnico/arquitectura).
> Para continuar: lee primero este HISTORIAL para el contexto narrativo, luego HANDOFF.md
> para el detalle técnico, y arranca con el comando de retomar que está en HANDOFF.md.

---

## 🎯 Comando para que la próxima instancia retome

```
Estoy continuando el desarrollo de Unstable Unicorns 2D en Godot 4.6.
Lee HISTORIAL.md (crónica completa de lo trabajado) y HANDOFF.md (detalle
técnico) en la raíz del proyecto. Después dime en qué punto estamos y
pregúntame por dónde sigo. NO programes hasta confirmar el siguiente paso.

Reglas de trabajo del usuario (Anderson):
- Está aprendiendo Godot: cuando haya que tocar el editor visual (nodos/escenas),
  guíalo PASO A PASO. Para scripts .gd puros, edítalos directo.
- Hay un Godot de Steam instalado; SE PUEDE correr headless para testear:
  "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe"
- Existe una suite de tests: scenes/GameLogicTest.tscn (216 OK). Correrla antes/después de cambios:
  godot --headless --path . res://scenes/GameLogicTest.tscn --quit-after 300
- Verificar compilación: godot --headless --editor --quit  (grep "Parse Error"/"SCRIPT ERROR")
```

---

## 📖 Qué es el proyecto

Videojuego del juego de cartas **Unstable Unicorns** hecho en **Godot 4.6**, multijugador
en red (ENet, 2-4 jugadores, server-authoritative). El usuario ya tenía:
- Cartas en español (imágenes PNG en `assets/textures/cards/`)
- Un JSON extenso (`assets/data/base_deck_data.json`) con el estado y efecto de cada carta (85 cartas)
- Una base inicial: red, lobby, carga de JSON, selección de bebé, turnos básicos

Meta del juego: ser el primero en tener 7 unicornios en tu establo (configurable).

---

## 🕐 Línea de tiempo (qué se hizo, en orden)

### Sesión 1 — Análisis inicial
- Claude exploró todo el proyecto y entregó un mapa completo de arquitectura, estado y roadmap.
- Se definieron 5 fases: (1) bucle de turno, (2) EffectProcessor, (3) targeting/pickers,
  (4) ventana Neigh, (5) pulido.

### Corrección masiva del JSON (42 cartas)
- El JSON tenía 42 cartas con efectos mal modelados (scopes, cantidades, costes, triggers,
  pasivos, etc.). Se corrigieron TODAS. Quedó en 85 cartas válidas.
- Errores típicos: "Each player" estaba como `self` (debía ser `all_players`); Good Deal robaba
  1 en vez de 3; pasivos modelados como `destroy` en vez de `protect`; Neigh con trigger
  `on_play` en vez de `on_card_played`; etc.

### Sistema de tipos consolidado
- `GameEnums.gd`: se añadió el enum `Condition` con 24 valores documentados (uno por carta especial).
- `DataParser.gd`: nuevo `CONDITION_MAP` + `parse_condition()`. Maps ampliados (`extra_turn`,
  `skip_turn`, `on_card_played`, `all_opponents`, `void`).
- `CardEffect.gd`: `condition` pasó de String a enum (type-safe).
- `CardData.gd`: helpers (`is_unicorn`, `is_permanent`, `matches_filter`, `unicorn_count_value`, etc.).
- `CardDatabase.gd`: parseo defensivo + helpers de búsqueda.
- `TestLoader.gd`: 11 tests de integridad.

### Fase 1 — Bucle de turno completo
- `GameManager.gd`: flujo START→DRAW→ACTION→END, auto-draw, `consume_action`, `request_end_turn`,
  hand limit, `check_win_condition`, señales nuevas.
- `game_table.gd`: HUD por código (turno/fase/acciones/contadores), botón Finalizar Turno,
  validaciones server-side, panel de victoria, Downgrades hacia el oponente.
- **El usuario probó y confirmó que funcionaba** (logs de 2 instancias jugando).

### Fases 2-4 (en una gran tanda) — Motor de juego completo
- **EffectProcessor.gd** (de stub vacío a motor completo): todas las acciones (DRAW, DISCARD,
  DESTROY, SACRIFICE, STEAL, PULL, SWAP_HANDS, RETURN_TO_HAND, REVIVE, SUMMON, SEARCH_DECK,
  SHUFFLE_DECK, SKIP_TURN, EXTRA_TURN, EXTRA_ACTION). Triggers on_play/on_enter_stable/
  on_turn_start/on_destroy. Costes (obligatorios y opcionales).
- **PassiveRegistry.gd**: tracker de pasivos activos (Queen Bee, Rainbow Aura, Yay, Slowdown, etc.).
- **TargetResolver.gd**: resuelve scope/zone/filter → candidatos.
- **NeighManager.gd**: ventana de Relincho con stacking real (Neigh → Super-Neigh).
- **Pickers (UI por código)** en game_table: card/stable/player/binary/cost picker, ventana Neigh.
- Autoloads nuevos en project.godot: EffectProcessor, NeighManager.

### Ronda de bugfixes (reportados por el usuario jugando)
1. Error de tipo (`dest_player_id` sin tipo) → explícito `: int`.
2. `Out of bounds players dict` → guard cuando un jugador se desconecta.
3. `VBox not found` en pickers → `_make_modal_panel` guarda ref del vbox en meta.
4. Ternarios "standalone" → if/else.
5. `setup_card` con textura null → añadir el panel al árbol ANTES de poblarlo (los `@onready`).
6. **Ver info de cualquier carta**: `set_disabled` ya no bloquea el hover; cartas de establo
   (propias y rivales) y de pickers conectan `info_requested`.
7. **z-index**: cartas de la mano siempre por encima del campo. Cartas disabled solo muestran botón Info.
8. **Scroll horizontal** en pickers (ScrollContainer).
9. **Neigh desde la mano**: durante la ventana, los Relinchos en mano se iluminan y son clicables;
   bloqueo de jugar Neigh fuera de contexto (toast).
10. **Costes opcionales**: `cost_required` ahora significa "obligatorio" (no "hay coste").
    Los "puedes pagar X" muestran botón "No pagar". Botón Pagar deshabilitado hasta completar selección.
11. **Cancelar acción primaria → no corre la secundaria** (modela "haz X. Si lo haces, haz Y").
    Ej: Uniceronte (destruir → si lo haces, termina turno).
12. Cartas destruidas en establo rival no desaparecían → `RivalZone.remove_card_from_stable`.

### Barrido de QA completo (a pedido del usuario: "que todo funcione sin excepción")
- Auditoría: 74/84 efectos OK; se implementaron las 10 conditions faltantes:
  immune_to_magic_destroy, disable_unicorn_effects (Luz Cegadora), convert_unicorns_to_pandas,
  hand_visible (Cámara Espía), if_unicorn_count_exceeds_5 (Establo Diminuto), move_unicorn_to_opponent
  (Intercambio), retarget_upgrade_downgrade (Re-Target), replace_target_unicorn (Caballero Negro),
  prevent_basic_entry completo (Reina del Baile), or_on_leave_stable (Alambre de Púas).
- **Tests automatizados**: se creó `scripts/tests/GameLogicTest.gd` + escena, con auto-respondedor
  de pickers. Se corrió headless de verdad: **216 OK, 0 fallos**.
- Bugs graves encontrados por análisis: STEAL y RETURN_TO_HAND DUPLICABAN cartas (iban a la mano/
  establo Y al descarte) → se creó `_extract_from_stable` (saca sin destruir). `await` faltantes.

### Más bugs reportados jugando
- **Unicornios Voladores no volvían a la mano al morir** → se trata como enrutamiento de destino.
- **Robo Descarado robaba al azar** (debía dejar elegir) → distingue condition `random` (Americornio)
  de elección (Robo Descarado).

### Pilas visibles + visor + animaciones
- 3 pilas a la izquierda: Mazo (secreto), Descarte y Guardería (clicables → visor de cartas).
- Contadores unificados `client_sync_deck_counters(deck, discard, nursery)`.
- Beso de Amor / invocaciones sin candidatos → avisan con toast.
- Animación de entrada de carta (primero "pop" con scale → causó bug "a medias" →
  **cambiado a fade-in**, que es robusto en contenedores).

### Fin de partida + votación + reglas + lobby
- **Votación al ganar**: panel con "🔄 Revancha" / "🚪 Ir al Lobby" + contador de votos.
  Todos revancha → reinicia limpio. Alguien lobby → desconecta y vuelve al **login normal**.
- **Sincronización de reglas en vivo**: el host cambia spinbox/checkboxes → broadcast; el cliente
  escucha `rules_updated` y actualiza su UI. La meta se muestra en el HUD ("Meta: N 🦄").
- **Botones debug eliminados** (DebugUI oculto).
- **Visor de pila era global → ahora local** del que lo pidió.
- IMPORTANTE: hubo un intento de auto-saltar al waiting room al volver al lobby que ROMPÍA el
  login; se revirtió. El login (nombre → IP → unirse/crear) es SIEMPRE la entrada del lobby.

---

## ✅ Estado actual (todo verde)

- **85 cartas**, **84 efectos**, **0 gaps** en el motor.
- **216 tests automatizados OK, 0 fallos.**
- **0 errores de compilación.**
- Jugable de principio a fin: lobby → selección de bebé → turnos con efectos completos →
  Relinchos → victoria → votación (revancha o lobby).

---

## ⚠️ Cosas a vigilar / posibles mejoras futuras

- **Animaciones**: por ahora fade-in simple. Si se quiere "movimiento" de carta (mano→establo)
  hay que hacerlo con nodos fuera de contenedor (overlay) para no pelear con el layout del HBox.
- **Hand limit**: descarte forzado por FIFO (saca las primeras). Idealmente debería dejar elegir.
- **Reconexión**: si un jugador se cae a mitad de partida, no hay flujo de reconexión.
- **Sonido**: no hay audio.
- **HUD/pickers por código**: funcionan pero podrían migrarse a escenas .tscn (oportunidad
  pedagógica para enseñar nodos al usuario).
- **Puerto/MAX_CLIENTS hardcoded** (7777, 4).
- Edge case menor: Gordicornio (cuenta 2) bajo Luz Cegadora propia sigue contando 2 para
  victoria (unicorn_count_value lee los efectos de la carta, no el registry). Muy raro en práctica.

---

## 🗂️ Mapa rápido de archivos

| Archivo | Rol |
|---|---|
| `scripts/core/GameManager.gd` | Autoload: red, turnos, fases, victoria, reset_for_new_match |
| `scripts/core/EffectProcessor.gd` | Autoload: ejecuta TODOS los efectos + pickers + extract/remove |
| `scripts/core/NeighManager.gd` | Autoload: ventana Neigh con stacking |
| `scripts/core/PassiveRegistry.gd` | Pasivos activos (incl. supresión por Luz Cegadora) |
| `scripts/core/TargetResolver.gd` | scope/zone/filter → candidatos |
| `scripts/core/CardDatabase.gd` | Autoload: carga JSON |
| `scripts/core/GameEnums.gd` | Enums (Type, Trigger, Action, Filter, Zone, Scope, Condition) |
| `scripts/data/CardData.gd`, `CardEffect.gd` | Modelos |
| `scripts/utils/DataParser.gd` | Strings JSON → enums |
| `scripts/tests/GameLogicTest.gd` | Suite de tests (216 OK) |
| `scenes/game/game_table.gd` | Mesa: HUD, RPCs visuales, pickers, pilas, votación |
| `scenes/game/lobby.gd` | Lobby: login, reglas en vivo, lista de jugadores |
| `scenes/game/rival_zone.gd` | Zona visual de cada rival (mano/establo/revelar) |
| `scenes/cards/card_ui.gd` | Carta interactiva (hover, botones, disabled) |
| `assets/data/base_deck_data.json` | 85 cartas con efectos |
| `HANDOFF.md` | Detalle técnico (RPCs, conditions, decisiones de diseño) |
| `HISTORIAL.md` | Este archivo (crónica) |

---

## 🧠 Decisiones de diseño clave (resumen; detalle en HANDOFF.md)

1. **Server-authoritative**: toda la lógica en el servidor; clientes envían intención y reciben estado.
2. **Cartas viajan como IDs** por red; `CardData` se reconstruye desde `CardDatabase`.
3. **`EffectProcessor.passives`** es la única fuente de verdad de pasivos.
4. **Pickers con `await`**: el servidor se duerme hasta que el cliente responde (`server_pick_response`).
5. **`_table_rpc`/`_table_rpc_id`**: EffectProcessor/NeighManager enrutan RPCs visuales vía `GameManager.game_table`.
6. **`is_resolving`**: lock que evita jugar otra carta a mitad de una resolución (anti-desync).
7. **Acción secundaria dependiente**: si cancelas la primaria de targeting, no corre la secundaria.
8. **`_extract_from_stable` vs `_remove_from_stable`**: mover/robar (sin descartar) vs destruir (al descarte).

---

*Fin del historial. La próxima instancia: lee también HANDOFF.md y corre los tests antes de tocar nada.* 🦄
