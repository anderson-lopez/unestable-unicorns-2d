# 🌐 Guía: desplegar el servidor online en Render (gratis)

Esto pone tu **servidor dedicado** en internet para jugar online con salas por código
(Opción 🅰️: **una partida a la vez** — seguro y sencillo). Tú haces los pasos de Render;
el código ya está listo (`Dockerfile`, `render.yaml`, `OnlineServer.gd`).

---

## 1) Subir el repo a GitHub
Ya lo tienes. Asegúrate de hacer commit de `Dockerfile` y `render.yaml`.

## 2) Crear el servicio en Render
1. Entra a https://render.com y crea cuenta (gratis, puedes usar tu GitHub).
2. **New → Blueprint** → conecta tu repo → Render detecta `render.yaml`.
   - (Alternativa: **New → Web Service → Docker** y apuntar al repo; Render usa el `Dockerfile`.)
3. Plan: **Free**. Crea el servicio. La primera construcción tarda varios minutos
   (descarga Godot + importa recursos).

## 3) Copiar la URL
Cuando termine, Render te da una URL como:
```
https://unstable-unicorns-server.onrender.com
```
Para WebSocket seguro, en el juego se usa con `wss://` (sin `https`):
```
wss://unstable-unicorns-server.onrender.com
```

## 4) Poner la URL en el juego
Edita `scenes/game/lobby.gd` y reemplaza `ws://127.0.0.1:7777` por tu URL `wss://...`:
- `const ONLINE_SERVER_URL := "wss://unstable-unicorns-server.onrender.com"`

> Para PROBAR EN LOCAL deja `ws://127.0.0.1:7777`. Para la build pública usa `wss://...`.

## 5) Volver a exportar el juego
Exporta Windows/Web/Android otra vez (ya con la URL de Render) y comparte.

---

## Cómo jugar online
1. Cada jugador abre el juego → **🌐 JUGAR ONLINE (código de sala)**.
2. Uno pulsa **Crear sala** → aparece un código (ej. `9HSZ`).
3. Los demás escriben ese código → **Unirse**.
4. Mínimo 2 jugadores (ideal 4). El host pulsa **¡INICIAR PARTIDA!**.
5. El servidor de Render arbitra la partida y todos juegan.

## Notas del plan gratis
- El servicio **se duerme tras 15 min** sin uso. El primer jugador en conectarse
  espera ~50 s mientras Render lo despierta. Después va fluido.
- **Una partida a la vez**: mientras un grupo juega, el servidor no crea salas nuevas
  (así es estable y seguro). Al terminar, queda libre para el siguiente grupo.

## Probar el servidor en tu PC (sin Render)
```powershell
cd "C:/Users/Anderson/Documents/game desing/unestable-unicorns-2d"
& "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" --headless --path . --dedicated
```
Luego abre 2 instancias del juego → 🌐 JUGAR ONLINE → crea/únete con el código.
