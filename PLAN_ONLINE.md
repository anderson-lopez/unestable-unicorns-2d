# Plan técnico — Online con Render + WebSocket + salas con código

Estado: **Fase 1 COMPLETA** (red migrada de ENet → WebSocket; local funciona).
Este documento define cómo seguimos para jugar online con salas y código.

---

## El reto central (por qué hay que decidir bien)

El juego HOY es **server-authoritative pero el "host" es un jugador**: quien crea
la partida abre el servidor WebSocket en SU máquina y además juega. Los `GameManager`
y `game_table` mezclan "lógica de servidor" con "soy un jugador con pantalla".

Para online con Render, **el servidor debe vivir en Render** (los jugadores no tienen
IP pública). Eso obliga a separar la lógica del servidor de la parte visual del jugador.

Hay dos niveles de ambición:

### Opción 3A — Una sala global (rápido, v1)
- Render corre **una sola partida** a la vez.
- Todos los que entren caen en la misma mesa.
- El "código" sería simbólico (o sin código).
- ✅ Mucho más rápido de construir y desplegar.
- ❌ Si dos grupos quieren jugar a la vez, chocan.

### Opción 3B — Multi-sala con código (lo que pediste)
- Render maneja **muchas salas** a la vez, cada una con su código único (ej. `ABCD`).
- Crear sala → genera código → otros entran con ese código.
- Mínimo 4 jugadores por sala.
- ✅ Es lo ideal y lo que quieres.
- ❌ Requiere refactor: el estado del juego (mazos, turnos, jugadores, efectos) debe
  pasar de ser **global** a ser **por sala** (`rooms = { "ABCD": EstadoDePartida }`).
  Es trabajo de varias sesiones y hay que tocar `GameManager`, `EffectProcessor`,
  `NeighManager` y `game_table` con cuidado.

---

## Arquitectura objetivo (3B)

```
            (Render, gratis)
        ┌─────────────────────────┐
        │  SERVIDOR DEDICADO       │
        │  (Godot headless)        │
        │                          │
        │  rooms = {               │
        │    "ABCD": { jugadores,  │
        │              mazo, turno,│
        │              efectos },  │
        │    "WXYZ": { ... },      │
        │  }                       │
        └───────────▲──────────────┘
                    │ WebSocket (wss://)
        ┌───────────┼───────────┐
     Jugador1   Jugador2   Jugador3 ...
   (cada uno solo CLIENTE; nadie es host)
```

Cambios principales:
1. **Modo "dedicado"**: el mismo proyecto puede arrancar como servidor puro
   (sin jugador local, sin escena de mesa) con un flag (`--dedicated` o variable de entorno).
2. **Estado por sala**: encapsular `deck/discard/nursery/turn_order/players/...` en una
   clase `RoomState`, y que el servidor tenga un diccionario de salas.
3. **Enrutado por sala**: cada RPC del juego sabe a qué sala pertenece (por el peer_id
   del emisor → su sala). Los broadcast van solo a los peers de esa sala.
4. **Matchmaking**: RPCs nuevos `crear_sala()` → devuelve código; `unirse_sala(codigo)`.
5. **Lobby**: pestañas **Local** (como ahora) y **Online** (servidor Render + código).

---

## Despliegue en Render (cuando el servidor esté listo)

1. El servidor headless se empaqueta (export Linux/Server o un Dockerfile con Godot).
2. En Render → **New → Web Service** → conectar tu repo de GitHub.
3. Build: instalar Godot headless; Start: `godot --headless --dedicated --port $PORT`.
   (Render asigna el puerto en la variable `$PORT`; el servidor debe leerla.)
4. Render da una URL `wss://tuapp.onrender.com` → esa va en el cliente (Online).
5. Plan free: el servicio **se duerme tras 15 min** sin uso (primer jugador espera ~50s).

---

## Fases restantes

| Fase | Qué | Quién |
|---|---|---|
| 2 | Lobby con pestañas Local/Online + campo de código | Claude |
| 3 | Refactor a estado-por-sala + modo dedicado + matchmaking | Claude (varias sesiones) |
| 4 | Desplegar en Render + conectar cliente a la URL | Claude escribe, Anderson despliega |
| 5 | Export web (HTML5) a itch.io | Claude + Anderson |

---

## ❓ Decisión que necesito de Anderson

**¿Empezamos por 3A (una sala global, online funcionando rápido) y luego evolucionamos a
3B (multi-sala con código)? ¿O vamos directo a 3B aunque tarde más?**

- **3A primero** = juegas online con amigos pronto (una mesa a la vez), y mejoramos después.
- **3B directo** = lo ideal desde el inicio, pero más sesiones antes de poder probar online.

Mi recomendación: **3A primero** para tener online real cuanto antes, y luego 3B.

---

# ESTADO REAL (actualizado)

- ✅ **Fase 1**: red ENet → WebSocket. Local funciona.
- ✅ **Fase 3.1**: `OnlineServer.gd` — servidor dedicado multi-sala (matchmaking).
- ✅ **Fase 3.2**: UI online en el lobby (crear/unirse con código). **PROBADO**: código
  generado + lista de jugadores en vivo. (overlay por código en `lobby.gd`)
- ✅ **Base de 3.3**: `RoomState.gd` — contenedor del estado por-sala (creado; reservado para 3B futuro).
- ✅ **Fase 3.3 (Opción 🅰️ — HECHA)**: el **servidor dedicado aloja la partida** reusando
  la lógica existente. **Una partida a la vez**: mientras hay partida activa no se crean
  salas nuevas (broadcast de RPCs seguro). El servidor NO es jugador (solo árbitro).
  - `OnlineServer._start_game_for_room()`: registra a los jugadores en `GameManager`
    (peer 1 = servidor, NO jugador), pone `is_dedicated_referee=true`, avisa a los
    clientes (`_recv_room_started`) y carga `GameTable` en el servidor para arbitrar.
  - `GameManager.online_mode`: en online el registro lo hace la sala, no el flujo local.
  - Guardas de árbitro en `game_table` (`setup_table`, `client_start_baby_selection`,
    `client_go_to_lobby`) para que el servidor no abra UI ni cierre su propio peer.
- ⏭️ **Fase 3.4**: desplegar servidor en Render. **Archivos listos**: `Dockerfile`,
  `render.yaml`, `GUIA_RENDER.md`. Falta: Anderson despliega y pone la URL `wss://` en
  `scenes/game/lobby.gd` (`ONLINE_SERVER_URL`).

## Decisión tomada: Opción 🅰️ (una partida a la vez, rápido y seguro). 3B queda para el futuro.

---

# 📋 FASE 3.3 — Pasos concretos para el refactor por-sala

Objetivo: cuando el host de una sala pulsa Iniciar, ESA sala juega su partida,
con varias salas a la vez sin chocar. Todo corre en el SERVIDOR DEDICADO.

**Idea clave:** mover el estado global de `GameManager` a `RoomState` (ya creado), y
que el servidor tenga `rooms: { codigo: RoomState }`. Cada RPC del juego se enruta a la
sala del emisor (`OnlineServer.peer_room[sender]`).

### Pasos sugeridos (incrementales, con tests entre cada uno):
1. **Helper de enrutado**: en el servidor, dado un `peer_id`, obtener su `RoomState`
   (`OnlineServer.peer_room[id]` → `OnlineServer.rooms[code]` → su RoomState).
   Guardar el RoomState dentro de cada entrada de `OnlineServer.rooms`.
2. **Mover la lógica de turnos** de GameManager a funciones que reciban un `RoomState`
   (start_turn, draw_phase, action_phase, end_phase, next_turn, consume_action...).
   En vez de `deck`, usar `room.deck`, etc.
3. **EffectProcessor por-sala**: las funciones reciben/usan el `RoomState` (su `passives`,
   su `deck`, sus `players`). Hoy usan `GameManager.deck`, `EffectProcessor.passives`...
4. **NeighManager por-sala**: igual, opera sobre el RoomState de la jugada.
5. **RPCs visuales dirigidos a la sala**: los `rpc(...)` que hoy hacen broadcast a TODOS
   deben ir solo a los peers de la sala (`rpc_id` a cada `room.players`).
6. **game_table en cliente**: al recibir `_recv_room_started`, cargar la mesa y pedir su
   estado. El cliente NO tiene estado autoritativo (ya es así); solo recibe RPCs visuales.
7. **Arranque de partida**: `OnlineServer.req_start_room` crea el RoomState, baraja mazo,
   reparte, y empieza el primer turno de ESA sala.

### Riesgos / cuidados:
- GameManager/EffectProcessor/NeighManager son autoloads (singletons). El estado debe
  vivir en RoomState, NO en el autoload. Los autoloads pasan a ser "operadores" que
  reciben el RoomState como parámetro.
- `game_table` (cliente) NO debe cambiar mucho: ya es server-authoritative y solo pinta
  lo que llega por RPC. Lo que cambia es el SERVIDOR.
- Mantener el modo LOCAL funcionando: el host local crea una sala "implícita" con un solo
  RoomState (reutiliza el mismo camino).
- Probar con 216 tests + manualmente (servidor dedicado + 2 clientes) en cada paso.

### Cómo probar el servidor dedicado en local (PowerShell):
```
cd "C:/Users/Anderson/Documents/game desing/unestable-unicorns-2d"
& "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --dedicated
```
Luego abrir 2 instancias del juego → 🌐 JUGAR ONLINE → crear/unirse con código.
