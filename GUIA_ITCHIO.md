# Guía para publicar en itch.io — Unstable Unicorns 2D

## ⚠️ Importante sobre el multijugador
El juego usa red **ENet (UDP, puerto 7777)**. Esto:
- ✅ Funciona perfecto en el **build descargable de Windows** (por LAN o VPN tipo Tailscale).
- ❌ NO funciona en una versión **HTML5/navegador** (los navegadores no permiten UDP).
  Una versión web jugable requeriría reescribir la red a WebSocket/WebRTC + un servidor
  relay alojado. Es un proyecto aparte.

👉 **Para itch.io, sube el build DESCARGABLE de Windows.**

---

## 1) Requisito: plantillas de exportación 4.6.3
- Godot → **Editor → Administrar plantillas de exportación → Descargar e Instalar**.
  (Tienes 4.4.1; el editor es 4.6.3, así que hacen falta las 4.6.3 para exportar.)

## 2) Exportar el .exe
**Opción editor:** Proyecto → Exportar → "Windows Desktop" → **Exportar Proyecto…**
→ guardar en `builds/UnstableUnicorns2D.exe`.

**Opción línea de comandos** (tras instalar plantillas 4.6.3):
```
"C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
  --headless --path . --export-release "Windows Desktop" "builds/UnstableUnicorns2D.exe"
```

## 3) Empaquetar para itch.io
itch.io quiere un `.zip`. Mete en una carpeta y comprime:
- `UnstableUnicorns2D.exe`
- (si aparece) `UnstableUnicorns2D.pck`  ← debe ir junto al .exe
- Un `LEEME.txt` con instrucciones (abajo te dejo el texto)

Comprime esa carpeta → `UnstableUnicorns2D_Windows.zip`.

## 4) Subir a itch.io
1. Crea cuenta en itch.io → **Upload new project**.
2. **Kind of project**: "Downloadable".
3. Sube el `.zip`. Marca la casilla **"This file will be played in the browser"** = **NO**
   (es descargable) y marca **Windows** como plataforma.
4. Pon precio "$0 or donate" (gratis) si quieres.
5. Sube capturas de pantalla y un cover (630×500 px recomendado).
6. Publica (Public) o déjalo en Draft/Restricted para pruebas.

---

## 📝 Texto sugerido para la página de itch.io

**Título:** Unstable Unicorns 2D (fan-made)

**Descripción corta:**
Versión digital fan-made del juego de cartas Unstable Unicorns. Multijugador local (LAN) o por VPN. ¡Reúne 7 unicornios y gana!

**Descripción larga:**
```
🦄 Unstable Unicorns 2D — versión fan-made en Godot

Juego de cartas por turnos para 2-4 jugadores. Acumula unicornios en tu
establo, sabotea a tus rivales con magias y desventajas, y defiéndete con
Relinchos. ¡El primero en reunir 7 unicornios gana!

▶ MULTIJUGADOR
- Local (misma red WiFi): el host comparte su IP y los demás se unen.
- Online: usa una VPN gratuita (Tailscale / Radmin VPN). El host comparte
  su IP de la VPN y todos se conectan.

▶ CÓMO JUGAR EN RED
1. Un jugador pulsa CREAR PARTIDA (es el host) y comparte su IP.
2. Los demás escriben esa IP y pulsan UNIRSE.
3. El host elige las reglas y pulsa Iniciar.

▶ NOTAS
- 85 cartas del set base, en español.
- Hecho con Godot 4.6. Proyecto fan, sin fines comerciales.
- No afiliado a Unstable Games / TeeTurtle.

Controles: ratón (o pantalla táctil). Pasa el cursor / toca una carta para verla.
```

**Tags sugeridos:** `cards`, `multiplayer`, `turn-based`, `unicorns`, `lan`, `godot`

---

## 📄 Texto para LEEME.txt (dentro del .zip)
```
UNSTABLE UNICORNS 2D (fan-made)

CÓMO JUGAR:
1. Abre UnstableUnicorns2D.exe
2. Escribe tu nombre.
3. HOST: pulsa "CREAR PARTIDA" y comparte tu IP (aparece en pantalla).
   - Misma red WiFi: comparte tu IP local.
   - Online: instala Tailscale (gratis) y comparte tu IP de Tailscale (100.x.x.x).
4. OTROS: escriben la IP del host y pulsan "UNIRSE".
5. El host configura las reglas y empieza.

REQUISITOS DE RED:
- Puerto 7777 (UDP) debe estar permitido en el firewall del host.
  (En Windows, la primera vez puede salir un aviso del firewall: acepta "Redes privadas".)

Proyecto fan-made. No afiliado a Unstable Games / TeeTurtle.
```

---

## 🌐 ¿Y si en el futuro quieres versión navegador?
Para que funcione en itch.io HTML5 con multijugador habría que:
1. Cambiar `ENetMultiplayerPeer` → `WebSocketMultiplayerPeer` (o WebRTC).
2. Alojar un **servidor dedicado** (un navegador no puede ser servidor).
3. Exportar a HTML5.
Es un trabajo grande pero factible. Avísame si algún día lo quieres y lo planificamos.
```
