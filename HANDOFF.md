# Unstable Unicorns 2D — Handoff de Contexto

> Documento maestro (detalle técnico) para continuar en otra sesión de Claude Code.
> 👉 Para la CRÓNICA completa de lo trabajado, lee primero **HISTORIAL.md**.
> Estado: jugable de punta a punta. 85 cartas, 84 efectos, 0 gaps. 216 tests OK. 0 errores de compilación.
> Pulido hecho: animaciones de movimiento real, sonidos, registro de jugadas, descarte
> elegible al límite de mano, red más robusta (timeout, IP local, desconexión) y exportación a .exe.
> Multijugador: hasta 8 jugadores, mesa dinámica (zonas rivales escalan según cantidad),
> establo rival con ventajas/desventajas arriba, multiplicador de cartas de acción (x1-x5)
> configurable en el lobby, HUD en esquina superior izquierda, registro desplegable.
> Pendiente: migrar HUD/pickers a escenas .tscn, reconexión de jugadores caídos, PLAYTEST en vivo.

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

**Estado actual:**
- ✅ Fase 0: Red, lobby, carga JSON, selección de bebé
- ✅ Fase 1: Bucle de turno (START→DRAW→ACTION→END), HUD, victoria, Downgrades hacia oponente
- ✅ Fase 2: EffectProcessor con todas las acciones (DRAW, DISCARD, DESTROY, SACRIFICE, STEAL, PULL, SWAP, RETURN, REVIVE, SUMMON, SEARCH, SHUFFLE, EXTRA_TURN, EXTRA_ACTION, SKIP_TURN)
- ✅ Fase 3: Sistema de pickers/targeting (card, stable, player, binary choice, cost pay) — UI construida por código
- ✅ Fase 4: Ventana Neigh con stacking (Neigh → Super-Neigh) + CANNOT_BE_NEIGHED + PREVENT_NEIGH_ON_OWNER (Yay) + PREVENT_PLAY_NEIGH (Slowdown/Ginormous)
- ⚠️ Fase 5: Pulido pendiente (animaciones, sonidos, log de jugadas, escenas .tscn para pickers)

**Mecánica core:** Cada jugador acumula unicornios en su establo. Gana quien llegue primero a 7 (configurable). Las cartas permiten robar, destruir, sacrificar, hurtar, etc., con ventana Neigh para cancelar jugadas.

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
│   │   ├── GameManager.gd             ← Autoload: red, turnos, fases, victoria, ref a game_table
│   │   ├── EffectProcessor.gd         ← Autoload: ejecuta efectos, manejadores de acción, pickers
│   │   ├── NeighManager.gd            ← Autoload: ventana Neigh con stacking
│   │   ├── PassiveRegistry.gd         ← RefCounted: tracker de pasivos activos
│   │   ├── TargetResolver.gd          ← RefCounted: utilidad scope/zone/filter → candidatos
│   │   ├── GameEnums.gd               ← Todos los enums (Type, Action, Condition...)
│   │   ├── GameRules.gd               ← Resource serializable
│   │   └── PlayerData.gd              ← RefCounted (hand, stable, name, id)
│   ├── data/
│   │   ├── CardData.gd                ← Datos + helpers (is_unicorn, matches_filter...)
│   │   └── CardEffect.gd              ← Estructura de efecto
│   ├── utils/
│   │   └── DataParser.gd              ← Strings JSON → Enums
│   └── tests/
│       └── TestLoader.gd              ← 11 tests de integridad
├── scenes/
│   ├── cards/
│   │   ├── CardUI.tscn + card_ui.gd
│   │   └── CardInfoPanel.tscn + card_info_panel.gd
│   ├── game/
│   │   ├── Lobby.tscn + lobby.gd
│   │   ├── GameTable.tscn + game_table.gd ← HUD y pickers construidos por código
│   │   └── RivalZone.tscn + rival_zone.gd
│   └── ui/
│       └── CardSelector.tscn + card_selector.gd ← Modal de bebé inicial
├── project.godot                       ← Autoloads: CardDatabase, GameManager, EffectProcessor, NeighManager
└── HANDOFF.md                          ← Este archivo
```

### Autoloads (singletons globales)

Configurados en `project.godot`:
- `CardDatabase` — Carga `base_deck_data.json` al iniciar.
- `GameManager` — Red, jugadores, mazos, turnos, fases. Mantiene `game_table` reference.
- `EffectProcessor` — Ejecuta efectos. Tiene su propio `PassiveRegistry`.
- `NeighManager` — Ventana de Relinchos.
- `TestLoader` — Suite de tests (puede desactivarse en producción).

---

## 🌐 Arquitectura de RPCs

### Patrón general
**Servidor authoritative.** Todos los efectos se resuelven server-side. Los clientes solo:
1. Envían intenciones (`server_play_card`, `server_pick_response`)
2. Reciben actualizaciones visuales (`client_card_entered_stable_visual`, `client_sync_hand_size`)

### Tabla de RPCs principales

| RPC | Definida en | Dirección | Propósito |
|---|---|---|---|
| `server_play_card(card_id, target_id)` | game_table | Cliente → Server | Jugar carta de mano |
| `server_discard_card(card_id)` | game_table | Cliente → Server | Descartar voluntariamente |
| `request_end_turn` | GameManager | Cliente → Server | Pasar turno |
| `server_pick_response(a, b)` | EffectProcessor | Cliente → Server | Respuesta de picker (genérico) |
| `server_cost_response(success, ids)` | EffectProcessor | Cliente → Server | Pagar coste de efecto |
| `server_receive_neigh_rpc(card_id)` | NeighManager | Cliente → Server | Jugar un Neigh durante ventana |
| `sync_turn_state(player, phase, actions)` | GameManager | Server → All | Sincronizar estado de turno |
| `client_card_entered_stable_visual` | game_table | Server → All | Visual de carta entrando al establo |
| `client_card_left_stable` | game_table | Server → All | Visual de carta saliendo |
| `client_card_left_hand` | game_table | Server → All | Visual de descarte |
| `client_receive_drawn_batch(ids)` | game_table | Server → Owner | Recibir cartas robadas |
| `client_sync_hand_size(pid, n)` | game_table | Server → All | Actualizar tamaño visual de mano rival |
| `client_sync_deck_counters(d, dp)` | game_table | Server → All | Actualizar contador HUD |
| `client_replace_hand(ids)` | game_table | Server → Target | Reemplazar mano (swap_hands) |
| `client_open_card_pick(ids, prompt, cancel)` | game_table | Server → Target | Abrir modal genérico de cartas |
| `client_open_stable_target_pick(cands, prompt)` | game_table | Server → Target | Abrir picker de carta en establo |
| `client_open_player_pick(ids, prompt)` | game_table | Server → Target | Abrir picker de jugador |
| `client_open_binary_choice(labels)` | game_table | Server → Target | Abrir choice A/B (CHOICE_EITHER) |
| `client_open_cost_pay(action, amt, fil, msg, opt)` | game_table | Server → Target | Abrir picker de pago de coste |
| `client_open_neigh_window(card, player, secs)` | game_table | Server → Eligible | Abrir ventana Neigh |
| `client_close_neigh_window` | game_table | Server → All | Cerrar ventana |
| `client_announce_neigh(...)` | game_table | Server → All | Toast "X Neigh'd Y" |
| `announce_winner(id, name)` | GameManager | Server → All | Mostrar panel de victoria |

### Wrappers `_table_rpc` / `_table_rpc_id`

EffectProcessor y NeighManager tienen métodos `_table_rpc()` y `_table_rpc_id()` que enrutan las llamadas RPC a través de `GameManager.game_table` (la referencia se registra en `game_table._ready()`). Esto evita que EffectProcessor tenga que conocer cómo encontrar la escena.

---

## 🗂️ Modelo de datos

### Estructura de una carta en JSON

```json
{
  "meta": {"id": 3, "version": "...", "image_path": "..."},
  "identity": {
    "name": {"es": "...", "en": "..."},
    "type": "magic_spell",
    "tags": ["unicorn", "poison"]
  },
  "visual": {"description": {"es": "...", "en": "..."}},
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
- **Filter:** ANY, SELF, UNICORN_CARD, BABY/BASIC/MAGICAL_UNICORN, UPGRADE/DOWNGRADE_CARD, MAGIC_SPELL, INSTANT, HAND_AND_DISCARD
- **Zone:** DECK, HAND, STABLE, DISCARD_PILE, NURSERY, VOID
- **Scope:** SELF, CHOSEN_OPPONENT, ALL_OPPONENTS, ALL_PLAYERS, ANY_PLAYER
- **Condition:** 24 valores semánticos — ver `GameEnums.gd` para lista completa

### Conditions especiales — manejo actual (TODAS implementadas ✅)

| Condition | Maneja | Estado |
|---|---|---|
| `ALWAYS` | EffectProcessor (siempre dispara) | ✅ |
| `IN_STABLE` | EffectProcessor.resolve_on_turn_start | ✅ |
| `OR_ON_SACRIFICE` | EffectProcessor.resolve_on_destroy | ✅ |
| `OR_ON_LEAVE_STABLE` (Barbed Wire) | `_remove_from_stable` → `_on_unicorn_stable_changed` | ✅ |
| `IMMUNE_TO_DESTROY` (Rainbow Aura) | `_request_stable_target` filtra | ✅ |
| `IMMUNE_TO_MAGIC_DESTROY` (Kittencorn) | `_current_source.is_magic_spell()` en `_request_stable_target` | ✅ |
| `PREVENT_BASIC_ENTRY` (Queen Bee) | `server_play_card` rechaza + `_act_summon` filtra | ✅ |
| `PREVENT_PLAY_NEIGH` | PassiveRegistry → bloquea en `server_play_card` | ✅ |
| `PREVENT_PLAY_UPGRADE` | PassiveRegistry → bloquea en `server_play_card` | ✅ |
| `PREVENT_NEIGH_ON_OWNER` (Yay) | NeighManager skip window | ✅ |
| `DISABLE_UNICORN_EFFECTS` (Blinding Light) | resolve_* saltan efectos de unicornios | ✅ |
| `CONVERT_UNICORNS_TO_PANDAS` (Pandamonium) | filtro de targeting + win condition | ✅ |
| `HAND_VISIBLE` (Nanny Cam) | `server_refresh_visible_hands` + `reveal_hand` | ✅ |
| `COUNTS_AS_2_UNICORNS` | CardData.unicorn_count_value | ✅ |
| `IF_UNICORN_COUNT_EXCEEDS_5` (Tiny Stable) | `_enforce_tiny_stable` tras entrar unicornio | ✅ |
| `SCRY_3` | EffectProcessor.\_act_search_deck | ✅ |
| `TAG_NARWHAL` | EffectProcessor.\_act_search_deck | ✅ |
| `RANDOM` | `_act_pull` (randi) | ✅ |
| `CHOICE_EITHER` | EffectProcessor.\_execute_effect | ✅ |
| `MOVE_UNICORN_TO_OPPONENT` (Unicorn Swap) | `_custom_unicorn_swap` | ✅ |
| `RETARGET_UPGRADE_DOWNGRADE` (Re-Target) | `_custom_retarget` | ✅ |
| `CANNOT_BE_NEIGHED` | NeighManager.\_handle_neigh_chain | ✅ |
| `REPLACE_TARGET_UNICORN` (Black Knight) | `_remove_from_stable` confirm + sacrifica el Caballero | ✅ |

**Costes opcionales vs obligatorios:** `cost_required: false` = el jugador puede declinar
(botón "No pagar"); `true` = obligatorio. `has_cost()` detecta el coste por `cost_action != NONE`.
Solo Ritual Sádico (9) y Dos por Uno (58) son obligatorios.

**Acción secundaria dependiente:** si la acción primaria de targeting se cancela,
la secundaria NO corre (modela "haz X. Si lo haces, haz Y").

---

## ✅ Lo que está COMPLETO

### Fase 0 — Base preexistente
Red ENet, handshake, lobby, JSON loader (85 cartas), selección de bebé, reparto inicial, orden de turnos.

### Sesión previa: Correcciones JSON + Fase 1
42 cartas con errores corregidas. Sistema de tipos consolidado con enum `Condition`. Bucle de turno completo con HUD, validación, victoria, Downgrades hacia oponente.

### Sesión actual: Fases 2-4 — Motor de juego

#### Fase 2 — EffectProcessor
Implementadas TODAS las acciones del enum:
- DRAW (self con sync), DISCARD (con picker), DESTROY (con picker + inmunidad Rainbow Aura), SACRIFICE (con AMOUNT_ALL para "todas")
- STEAL (carta → mi establo), PULL (carta random rival → mi mano), SWAP_HANDS (intercambio)
- RETURN_TO_HAND (con regreso a nursery si es bebé), REVIVE (descarte → mano o establo), SUMMON (mano/nursery → establo con chain de on_enter), SEARCH_DECK (incluye SCRY_3 y TAG_NARWHAL)
- SHUFFLE_DECK (con HAND_AND_DISCARD para Shake Up)
- SKIP_TURN, EXTRA_TURN (con cola), EXTRA_ACTION (suma al contador)
- PROTECT/CANCEL son no-ops (manejados como pasivos / en NeighManager)

Triggers integrados:
- ON_PLAY: dispara para magias/instants antes del descarte
- ON_ENTER_STABLE: dispara cuando un permanente toca el establo (registra pasivos)
- ON_TURN_START: recorre el establo del activo en fase START
- ON_DESTROY: dispara cuando se quita una carta del establo (incluye OR_ON_SACRIFICE)

Costes:
- Si `cost_required=true`, abre picker de cost pay con cartas válidas según filter
- Si `cost_required=false` pero `cost_action!=none`, el coste es opcional (Skip button)

Bebés inmortales: cuando un baby unicorn sería destruido/sacrificado/devuelto, vuelve a `nursery_deck` si `nursery_is_safe_zone` (default true).

#### Fase 3 — Sistema de Pickers (UI por código)
Todos los modales se construyen dinámicamente en `game_table.gd`:
- `_show_card_picker(ids, prompt, allow_cancel, callback)` — elegir 1 de N cartas
- `_show_stable_picker(candidates, prompt)` — elegir carta de establo (muestra dueño)
- `_show_player_picker(player_ids, prompt)` — elegir jugador
- `_show_binary_choice(labels)` — choice A/B para CHOICE_EITHER
- `_show_cost_picker(action, amount, filter, msg, optional)` — pagar coste con multi-select

Layer: `modal_layer` (CanvasLayer.layer=10), encima del HUD (layer=5).

Comunicación: server envía RPC `client_open_*`, cliente muestra modal, click envía `server_pick_response(value_a, value_b)` que el `EffectProcessor` espera con `await target_picked`.

#### Fase 4 — NeighManager
Ventana de Relincho con stacking real:
1. `NeighManager.open_window(card_id, playing_player_id)` se llama en `server_play_card` después de quitar la carta de la mano y antes de resolver efectos
2. Se chequean los eligibles: tienen un instant en mano AND `can_play_instant(pid)` (no tienen Slowdown)
3. Si el dueño tiene `PREVENT_NEIGH_ON_OWNER` (Yay), la ventana se salta
4. Se envía RPC `client_open_neigh_window` a los eligibles con timer N segundos
5. Si alguien responde con `server_receive_neigh_rpc`, se descarta su Neigh y se abre OTRA ventana (super-neigh)
6. Si la carta jugada tiene `CANNOT_BE_NEIGHED` (Super Neigh), la cadena se corta
7. La función retorna `true` si la carta original fue cancelada

Constante `WINDOW_SECONDS = 5.0` (modificable).

---

### Sesión de pulido — Animaciones, red, registro, descarte, sonido y export

Toda esta tanda es código puro (sin tocar escenas en el editor). 216 tests siguen OK.

**🎬 Animaciones de movimiento real** (`game_table.gd`)
- Nueva `anim_layer` (CanvasLayer, layer=15) con helper `_fly_card(tex, from_center, to_center, from_size, to_size, dur, on_finish)`: lanza una carta "fantasma" temporal que viaja entre dos puntos globales y se autodestruye. Vive fuera de los contenedores → no pelea con el layout de los HBox/VBox.
- Robar → la carta vuela del mazo a la mano y se revela al aterrizar (`_animate_card_into_hand`, usa `await process_frame` para leer la posición real tras el layout).
- Jugar → vuela de la mano al destino: establo (unicornio/mejora), establo rival (downgrade) o descarte (magia/instantánea) (`_animate_card_play`).
- Salir del establo / descartar → vuela al descarte (`_animate_card_to_discard`).

**🌐 Red más robusta** (`GameManager.gd`, `lobby.gd`, `game_table.gd`)
- `GameManager.get_local_ip()`: devuelve la IPv4 LAN (192.168/10/172.16-31). El lobby la muestra al host para compartir.
- IP por defecto `127.0.0.1` + placeholder en el lobby (cómodo para misma PC).
- Timeout de conexión: `_watch_join_timeout` aborta con aviso si tras 8 s sigue en CONNECTING.
- Desconexión a mitad de partida: avisa a todos (toast + registro), quita la zona del rival (`client_remove_player_zone`), desbloquea esperas de UI pendientes (emite `target_picked(-1,-1)` y `cost_paid(false,[])`), saca al jugador del orden de turnos y, si era su turno, avanza. Si queda 1 → victoria por abandono (`_end_match_last_player_standing`).

**📜 Registro de jugadas** (`game_table.gd`, `EffectProcessor.gd`)
- Panel lateral derecho (`_build_log_panel`) con scroll y poda a 60 líneas.
- RPC `client_log_event(text, color)` + helper server `_server_log()` (en game_table) y `_log()` (en EffectProcessor, vía `_table_rpc`).
- Eventos: inicio de partida, turno de X, juega carta, relinchada, destruyó/robó (desde EffectProcessor), victoria, desconexión.

**🗑️ Descarte elegible al límite de mano** (`GameManager.gd`, `game_table.gd`)
- Reemplaza el FIFO automático. `_resolve_hand_limit_discard` abre en el cliente activo `client_open_discard_to_limit(excess)` (picker multi-selección obligatorio), espera la elección (`server_discard_chosen` → `_on_discard_choice`) con timeout de 30 s y **fallback FIFO** si no responde o no hay UI (tests headless).

**🔊 Sonidos** (`assets/audio/`, `game_table.gd`)
- 8 .wav procedurales generados por `assets/audio/generate_sounds.py` (sin dependencias): click, draw, play, neigh, destroy, turn, win, shuffle.
- `_build_sfx()` crea un `AudioStreamPlayer` por sonido; `_play_sfx(name)` los dispara. Enganchados a robar, jugar, entrar al establo (rivales), destruir, relincho, inicio de TU turno, victoria, barajar (inicio) y click de fin de turno.

**📦 Exportación (Windows + macOS)** (`export_presets.cfg`, `.gitignore`)
- **Windows** [preset.0]: `embed_pck=true` (un solo archivo), salida `builds/UnstableUnicorns2D.exe` (~128 MB).
  CLI: `godot --headless --path . --export-release "Windows Desktop" "builds/UnstableUnicorns2D.exe"`.
- **macOS** [preset.1]: arquitectura `universal` (Intel + Apple Silicon), salida `builds/UnstableUnicorns2D_mac.zip` (~85 MB, contiene el `.app`). SIN firmar/notarizar.
  CLI: `godot --headless --path . --export-release "macOS" "builds/UnstableUnicorns2D_mac.zip"`.
- ⚠️ macOS universal/arm64 EXIGE `rendering/textures/vram_compression/import_etc2_astc=true` en project.godot (ya activado). Tras activarlo hay que reimportar (`--import`).
- ⚠️ El `.app` de macOS NO está firmado: Gatekeeper lo bloquea. En el Mac: descomprimir el .zip y o bien click derecho → Abrir → Abrir, o en Terminal `xattr -cr UnstableUnicorns2D.app` y luego abrirlo. Si no abre, `chmod +x UnstableUnicorns2D.app/Contents/MacOS/*`.
- Plantillas: las trae el Godot de Steam en `editor_data/export_templates/<version>/` (incluye `macos.zip`). Si faltan: Editor → Proyecto → Exportar → "Administrar plantillas de exportación".
- ⚠️ Al hostear, el firewall (Windows/macOS) pedirá permiso para el puerto 7777 (aceptar redes privadas/locales).

### Sesión — Multijugador 8p, mesa dinámica, HUD y multiplicador de cartas

Todo código puro (sin tocar escenas). 216 tests siguen OK, 0 errores de parseo.

**👥 Hasta 8 jugadores** (`GameManager.gd`)
- `MAX_CLIENTS = 7` (7 clientes + host = 8). `start_game` exige ≥2 jugadores (aviso en lobby).

**🃏 Multiplicador del mazo** (`GameRules.gd`, `GameManager.gd`, `lobby.gd`)
- `GameRules.deck_multiplier` (1-5), serializado en to/from_dictionary.
- Control SpinBox "Copias del mazo (x)" creado por código en el lobby (`_build_multiplier_control`), solo editable por el host, sincronizado en vivo.
- `initialize_deck` pone `mult` copias de CADA carta del mazo (unicornios incluidos) para conservar las proporciones. Los bebés (guardería) quedan en 1 copia. ⚠️ Intento previo (multiplicar SOLO cartas de acción) inundaba el mazo de magias y dejaba sin unicornios → corregido multiplicando todo por igual.
- ⚠️ Cartas duplicadas: los nodos del establo ahora se localizan por `set_meta("card_id", id)` y se quita el PRIMER match (antes era por nombre de nodo, que colisionaba con duplicados).
- ⚠️ Limitación conocida (duplicados): todo el protocolo identifica cartas por `card_id`, no por instancia. Si tienes DOS copias del MISMO id en mano y debes descartar ambas, el picker de límite de mano solo marca una por id; el resto se completa por FIFO (el CONTEO siempre es correcto, nunca se traba, pero la carta exacta puede diferir). Arreglo real = IDs de instancia en toda la red (refactor grande, pendiente).

**🪑 Mesa dinámica** (`game_table.gd`, `rival_zone.gd`)
- `setup_table` cuenta rivales y pasa una escala (`_rival_card_scale`: x1 ≤3 rivales, x0.8 4-5, x0.62 6-7) a cada `RivalZone.set_card_scale()`. Las zonas rivales (HBox `RivalsContainer`) se achican para caber 2-8.
- **Establo rival**: `rival_zone._build_upgrades_row()` crea por código una fila de ventajas/desventajas ARRIBA de la de unicornios (`add_card_to_stable(node, is_top_row)`).

**🖥️ HUD reorganizado** (`game_table.gd`)
- Turno/Fase/Acciones/Meta ahora en un panel en la **esquina superior izquierda** (antes centrado arriba).
- **Registro desplegable**: botón ▾/▸ en el título pliega/despliega el panel del registro.

**💬 Mensajes/modales** (`game_table.gd`)
- Toasts con fondo oscuro, borde y click-through (no estorban), en la franja superior; se desvanecen solos. `client_announce_neigh` usa el toast con estilo.
- Modal de Relincho con fondo oscuro, borde rojo y márgenes (más legible).

## ❌ Lo que FALTA — Pendiente

### Bugs/incompletos importantes
- **`OR_ON_LEAVE_STABLE`** (Barbed Wire): no se llama el efecto cuando una carta sale del establo. Hay que añadir un hook en `EffectProcessor._remove_from_stable`.
- **`IMMUNE_TO_MAGIC_DESTROY`** (Magical Kittencorn): el filtro de inmunidad necesita saber si la fuente es una magia. Habría que pasar `source_card` a `_request_stable_target`.
- **`PREVENT_BASIC_ENTRY`** (Queen Bee): el check está parcial — no se aplica realmente al jugar el básico.
- **`DISABLE_UNICORN_EFFECTS`** (Blinding Light): no se respeta. El EffectProcessor debería filtrar los effects de unicornios cuando este pasivo está activo.
- **`IF_UNICORN_COUNT_EXCEEDS_5`** (Tiny Stable): debería disparar tras cada `stable_changed` para sacrificar.
- **`MOVE_UNICORN_TO_OPPONENT`** (Unicorn Swap): la mecánica de "das un unicornio y te llevas otro" no está modelada propiamente.
- **`RETARGET_UPGRADE_DOWNGRADE`** (Re-Target): similar.
- **`REPLACE_TARGET_UNICORN`** (Black Knight): debería interceptar destroys sobre unicornios del dueño.

### UX/Polish (Fase 5)
- **HUD migrar a escena `.tscn`** — actualmente construido por código en `_build_hud()`. Migrar a `scenes/ui/HUD.tscn` para enseñar nodos al usuario. ⏳ Pendiente.
- **Pickers a escenas** — `_show_*` funciones podrían migrar a escenas reutilizables (`scenes/ui/CardPicker.tscn`, etc.) ⏳ Pendiente.
- ✅ **Animaciones de movimiento** — HECHO (cartas vuelan vía `_fly_card` en `anim_layer`).
- ✅ **Sonidos** — HECHO (8 .wav procedurales, ver `assets/audio/`).
- ✅ **Log de jugadas** — HECHO (panel lateral derecho + `client_log_event`).
- ✅ **Pila de descarte visible** — HECHO (sesión previa).
- ✅ **Discard picker en hand limit** — HECHO (`client_open_discard_to_limit` + fallback FIFO).
- ⏳ **Reconexión** — la desconexión ya se maneja (avisa, avanza turno, victoria por abandono) pero NO hay flujo para que un jugador caído vuelva a entrar. Pendiente.
- ✅ **Pantalla de game over** — HECHO (panel con votación revancha/lobby).
- ✅ **`RivalZone.remove_card_from_stable(card_id)`** — HECHO.

### Tests
- **No hay tests E2E** de un juego completo. Solo TestLoader de integridad de datos.
- **NeighManager** no tiene tests de stacking — verificar manualmente.

---

## 🧠 Decisiones de diseño importantes

### Server-authoritative
**Toda la lógica vive en el servidor.** Los clientes solo envían intenciones y reciben estados sincronizados. Esto previene cheating y desyncs.

### Cartas viajan como IDs por red
Solo `int` IDs cruzan la red. Los objetos `CardData` se reconstruyen localmente desde `CardDatabase`. Ahorra ancho de banda y garantiza consistencia.

### `EffectProcessor.passives` como única fuente de verdad
El `PassiveRegistry` server-side mantiene los pasivos activos. Se actualiza en cada `on_card_entered_stable` y `on_card_left_stable`. Cualquier check (puedo jugar Neigh? este unicornio es inmune?) consulta aquí.

### Pickers con await en server
El server llama `await _request_stable_target(...)` y se duerme hasta que el cliente responde con `server_pick_response`. Esto permite escribir el EffectProcessor como código secuencial sin callbacks.

### `_table_rpc` wrappers
EffectProcessor y NeighManager NO definen RPCs visuales. Los enrutan vía `GameManager.game_table.rpc(...)`. Esto desacopla la lógica del juego de la UI.

### Game table se registra a sí misma
En `game_table._ready()`: `GameManager.game_table = self`. Forma simple de tener un singleton de UI sin patrón Service Locator.

---

## 📐 Reglas del juego (referencia)

### Estructura de turno
```
1. INICIO    → disparar efectos on_turn_start de upgrades/downgrades en establo
2. ROBO      → robar 1 carta del mazo automáticamente
3. ACCIÓN    → elegir 1 acción:
               a) Jugar 1 carta de tu mano (con posible Neigh window)
               b) Finalizar Turno (botón)
4. FIN       → si tienes >7 cartas, descartar al límite
```

### Cartas al jugarse
- **Unicornios** → tu establo (con `on_enter_stable` triggers)
- **Upgrades** → tu establo, fila separada (con `on_enter_stable`)
- **Downgrades** → establo de un oponente, fila separada
- **Magic Spells** → resolver `on_play` → descarte
- **Instants (Neighs)** → respuesta fuera de turno → descarte

### Condición de victoria
**7 unicornios en establo** (configurable). Ginormous Unicorn cuenta como 2.

### Bebés (Baby Unicorns)
Inmortales: si serían destruidos/sacrificados/devueltos, vuelven a la Guardería. Cada jugador empieza con 1 elegido en setup.

### Neigh (Relincho)
Cancela una carta que se está jugando. Ventana de 5s. Después de un Neigh hay otra ventana para Super-Neigh. Super-Neigh no puede ser cancelado. Yay impide que tus cartas sean Relinchadas. Slowdown/Ginormous impiden que el dueño juegue Relinchos.

---

## 🧪 Suite de tests automatizada

**Archivo:** `scripts/tests/GameLogicTest.gd` + `scenes/GameLogicTest.tscn`

Ejecutar: abrir `GameLogicTest.tscn` y F6 (o `godot --headless res://scenes/GameLogicTest.tscn`).
Última corrida: **209 OK, 0 fallos.**

Cubre: integridad JSON, helpers de CardData (85 cartas), DataParser, PassiveRegistry,
supresión de Luz Cegadora, conteo de victoria (pandas/ginormous), TargetResolver, y
flujos de efectos con un **auto-respondedor** que simula los clicks del jugador en los
pickers (robar, destruir, devolver, sacrificar, mover) — sin necesidad de red ni UI.

Para correr headless rápido (Windows, Godot de Steam):
```
"C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
  --headless --path . res://scenes/GameLogicTest.tscn --quit-after 300
```

### Bugs encontrados y corregidos en el barrido de QA
- **STEAL duplicaba cartas:** robar usaba `_remove_from_stable` (que mandaba la carta al
  descarte) y además la añadía a tu establo → carta en descarte Y establo. Además disparaba
  `on_destroy` por error (robar a Stabby gatillaba su efecto de muerte). Fix: nuevo
  `_extract_from_stable` que saca sin destruir ni descartar.
- **RETURN_TO_HAND duplicaba:** misma causa — la carta acababa en la mano Y en el descarte.
- **Bebé devuelto a mano duplicaba en Guardería** (doble append). Fix con `_extract_from_stable`.
- **`await` faltantes** en sacrificio de coste y movimientos → secuenciación incorrecta.
- **Luz Cegadora** no anulaba pasivos de unicornios (Reina, Gordicornio). Fix en
  `PassiveRegistry.player_has` con supresión de fuentes-unicornio.
- **Unicornios Voladores (17,57,66,68,81) no volvían a la mano al morir:** el efecto
  `return_to_hand` con filter SELF no encontraba la carta (ya removida + SELF no matchea).
  Fix: se trata como ENRUTAMIENTO de destino en `_remove_from_stable` (como bebé→guardería).
- **Robo Descarado (47) robaba al azar en vez de dejar elegir:** `_act_pull` siempre tomaba
  carta aleatoria. Fix: si `condition == RANDOM` (Americornio) es al azar; si no, abre picker
  con la mano rival para elegir.

Tests: **216 OK, 0 fallos** (H7=volador a mano, H8=robo con elección, H9=robo al azar).

### Pilas visibles + visor (UI)
- 3 botones en el lado izquierdo: **Mazo** (no clicable, secreto), **Descarte** y **Guardería** (clicables).
- Click en Descarte/Guardería → pide al servidor (`server_request_pile`) y abre un visor
  (`client_open_pile_view`) con las cartas en scroll horizontal (solo lectura + info).
- Contadores unificados: `client_sync_deck_counters(deck, discard, nursery)`.
- **Beso de Amor / invocaciones sin candidatos** ahora avisan con toast (`client_toast` +
  `EffectProcessor._notify`) en vez de no hacer nada silenciosamente.
- **Animaciones:** cartas entran al establo con "pop" (TRANS_BACK); las pilas pulsan al cambiar.

### Fin de partida + votación + reglas
- **Botones debug eliminados** (DebugUI oculto).
- **Visor de pila era global → ahora local** del que lo pidió (el host hacía `rpc_id(0)`=broadcast;
  ahora abre directo local y los clientes piden por RPC dirigido).
- **Votación de fin de partida:** al ganar, panel con "🔄 Revancha" y "🚪 Ir al Lobby" + contador
  de votos. Si TODOS votan revancha → `reset_for_new_match` + recarga GameTable. Si alguien vota
  lobby → todos vuelven al Lobby (que detecta conexión activa y muestra la sala de espera, sin
  re-login). RPCs: `server_cast_vote`, `client_update_vote_tally`, `client_go_to_lobby`.
- **Reglas en vivo:** lobby conecta `value_changed`/`toggled` → broadcast; cliente escucha
  `rules_updated` → actualiza su UI. La meta de unicornios ahora se muestra en el HUD
  ("Meta: N 🦄") para ambos jugadores.

## 🔍 Análisis estático (Python)
Scripts de verificación usados (se pueden re-correr): aridad de llamadas RPC vs firmas,
métodos inexistentes sobre autoloads, cobertura JSON↔motor. Todos limpios.

## 🧪 Plan de pruebas manual

### Sanity check inmediato
1. Iniciar 2 instancias, host + join, Start
2. Cada jugador elige bebé → aparecen en establos
3. Verificar HUD arriba (Turno/Fase/Acciones)
4. En tu turno: la carta robada aparece automáticamente
5. Jugar un Unicornio → va a tu establo, turno pasa
6. Jugar Veneno de Unicornio (ID 3) → abre picker de establo del rival → seleccionas su unicornio → destruido
7. Jugar Ganga (ID 5) → debería robar 3 y abrir picker para descartar 1
8. Jugar Bomba de Purpurina como Upgrade y al inicio del siguiente turno → abre cost picker (sacrificar) → si pagas, abre picker para destruir
9. Si tienes un Neigh, ver ventana al jugar el rival una magia → click "¡Relincho!" → cancela

### Casos críticos
- **Magia destruye unicornio inmune (Rainbow Aura activo)** → no aparece en el picker
- **Super Neigh tras Neigh** → la carta original NO se cancela (Super cancela el Neigh)
- **7º unicornio** → panel victoria → turnos se detienen
- **Hand limit > 7 al fin de turno** → descarta automáticamente del front (sub-óptimo, pendiente)

---

## 🎓 Plan pedagógico — aprender Godot

El usuario está aprendiendo Godot. **A partir de Fase 5**, los pasos serán:
1. Claude escribe los `.gd` (scripts puros)
2. Claude da instrucciones paso a paso del editor:
   ```
   📂 Abre escena X
   🌳 Añade nodo Y como hijo de Z
   ⚙️ Configura propiedades en Inspector
   🔌 Conecta señal A → B
   ```
3. Usuario hace clic en el editor

Conceptos pendientes de cubrir cuando se migren HUD/pickers a escenas:
- Scene tree y composición
- Control vs Node2D
- Anchors, offsets, margins
- Signals y connections en el editor
- Instancing (escenas como prefabs)
- CanvasLayer y orden de render

---

## 🐛 Issues conocidos

1. **Pickers no migrados a escenas** — construidos por código (funcionan pero menos visual).
2. **Hand limit FIFO** — descarte forzado sin elección.
3. **Predicción optimista al jugar carta** — si el server rechaza, la carta visual ya se destruyó.
4. **Animaciones pop básicas** — no hay tween de movimiento.
5. **Re-Target / Unicorn Swap** — efectos especiales no completamente implementados.
6. **Sin chat ni log de jugadas** — los eventos solo aparecen en consola.
7. **Reconexión no manejada**.
8. **Puerto hardcoded** (7777). MAX_CLIENTS = 7 (8 jugadores máx).

---

## 📁 Archivos críticos para releer al retomar

Orden recomendado:
1. `HANDOFF.md` — este archivo
2. `scripts/core/GameEnums.gd` — todos los enums (especialmente Condition)
3. `scripts/core/EffectProcessor.gd` — el motor de efectos
4. `scripts/core/NeighManager.gd` — ventana Neigh
5. `scripts/core/PassiveRegistry.gd` + `TargetResolver.gd` — helpers del motor
6. `scripts/core/GameManager.gd` — flujo de turno y red
7. `scenes/game/game_table.gd` — UI principal, RPCs visuales, pickers
8. `scripts/data/CardData.gd` y `scripts/data/CardEffect.gd` — modelo
9. `assets/data/base_deck_data.json` — vistazo a 2-3 cartas (IDs 1, 26, 34)

---

## ✍️ Convenciones del código

- **Naming:** clases en PascalCase, variables/funciones en snake_case, constantes en SCREAMING_SNAKE
- **RPCs server-side:** prefijo `server_*`
- **RPCs client-side:** prefijo `client_*`
- **Funciones server-only privadas:** prefijo `_server_*`
- **Wrappers RPC visuales:** `_table_rpc()` / `_table_rpc_id()` en EffectProcessor/NeighManager
- **Idioma:** comentarios y print en español, identificadores en inglés
- **No emojis en código** salvo prints/labels de UI

---

## 🚀 Próximos pasos sugeridos (en orden)

1. **Probar el juego end-to-end** con dos clientes/instancias. Documentar bugs aquí.
2. **Migrar HUD a escena** `scenes/ui/HUD.tscn` (oportunidad pedagógica).
3. **Migrar Pickers a escena** reutilizable.
4. **Reconexión** de un jugador caído (la desconexión ya se maneja; falta volver a entrar).
5. **Control de volumen / mute** y reemplazar los .wav procedurales por sonidos definitivos.
6. **Persistencia de partida** (save/load) — opcional.

> Hecho en la sesión de pulido: animaciones de movimiento, sonidos, registro de jugadas,
> descarte elegible al límite, red más robusta y exportación a .exe.

---

## 🔗 Referencias

- **Reglas Unstable Unicorns:** https://teeturtle.com/products/unstable-unicorns
- **Godot 4 docs:** https://docs.godotengine.org/en/stable/
- **GDScript RPC:** https://docs.godotengine.org/en/stable/tutorials/networking/high_level_multiplayer.html

---

*Fin del handoff. Buena suerte con la siguiente sesión.* 🦄
