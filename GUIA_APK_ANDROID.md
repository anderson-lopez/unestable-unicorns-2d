# Guía para exportar a APK (Android) — Unstable Unicorns 2D

El proyecto YA está preparado para móvil (toque, orientación horizontal, escalado).
Lo único que falta es instalar las herramientas de Android **una vez** y exportar.
Godot NO puede generar el APK sin estas herramientas (no vienen incluidas).

---

## ✅ Lo que ya dejé listo (no tienes que hacerlo)
- **Toque (táctil)**: las cartas ahora se abren con **TAP** (antes solo con hover de mouse).
  Todos los botones (Finalizar Turno, pilas, Ver Reglas, Relincho, modales) responden al toque.
- **Orientación horizontal** + **escalado** (`canvas_items`/`expand`) para que se vea bien en cualquier pantalla.
- **Renderer GL Compatibility** (el adecuado para móviles).
- `emulate_mouse_from_touch` y `emulate_touch_from_mouse` activados.

---

## 🛠️ Requisitos a instalar (UNA sola vez)

### 1. Java JDK 17
- Descarga **JDK 17** (Adoptium/Temurin es gratis): https://adoptium.net/temurin/releases/?version=17
- Instálalo y anota la ruta (ej: `C:\Program Files\Eclipse Adoptium\jdk-17...`).

### 2. Android SDK (vía Android Studio — lo más fácil)
- Instala **Android Studio**: https://developer.android.com/studio
- Ábrelo → **More Actions → SDK Manager** → pestaña **SDK Tools**, marca e instala:
  - Android SDK Platform-Tools
  - Android SDK Build-Tools
  - Android SDK Command-line Tools (latest)
- Anota la ruta del SDK (normalmente `C:\Users\Anderson\AppData\Local\Android\Sdk`).

### 3. Plantillas de exportación de Godot (versión 4.6.3)
- En Godot: **Editor → Administrar plantillas de exportación → Descargar y Instalar**.
  (Tienes 4.4.1 instaladas, pero el editor es 4.6.3 → necesitas las de 4.6.3.)

---

## ⚙️ Configurar Godot (UNA sola vez)

1. **Editor → Configuración del Editor → Export → Android**:
   - **Java SDK Path**: la carpeta del JDK 17.
   - **Android SDK Path**: la carpeta del SDK.
   - Godot creará/usará un **debug.keystore** automáticamente (deja "Debug Keystore" por defecto;
     si no existe, créalo con el botón o con: `keytool -keyalg RSA -genkeypair -alias androiddebugkey -keypass android -keystore debug.keystore -storepass android -dname "CN=Android Debug,O=Android,C=US" -validity 9999`).

2. **Proyecto → Exportar → Añadir… → Android**:
   - Se crea el preset de Android (con sus valores por defecto correctos).
   - Marca **"Use Gradle Build"** solo si instalaste el "Android Build Template"
     (Proyecto → Instalar plantilla de compilación de Android). Para un APK simple de prueba,
     puedes dejarlo **desmarcado** (usa la plantilla precompilada).
   - En **Architectures**, deja `arm64-v8a` (la mayoría de teléfonos actuales).
   - **Export Path**: `builds/UnstableUnicorns2D.apk`.

---

## 📦 Exportar el APK

- En el diálogo de Exportar, con el preset Android seleccionado:
  **Exportar Proyecto…** → guarda como `builds/UnstableUnicorns2D.apk`.
- O por línea de comandos (después de configurar lo anterior):
  ```
  "C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe" \
    --headless --path . --export-debug "Android" "builds/UnstableUnicorns2D.apk"
  ```

---

## 📲 Instalar en el teléfono

1. Pasa el `.apk` al teléfono (USB, WhatsApp, Drive, etc.).
2. En el teléfono: activa **"Instalar apps de fuentes desconocidas"** para el explorador de archivos.
3. Abre el `.apk` y acepta instalar.

---

## 🌐 Jugar en red (importante)

- El juego usa el **puerto 7777** por red local (LAN).
- El **host** debe estar en la **misma red WiFi** que los demás.
- Los que se unen escriben la **IP local del host** (la que aparece en el lobby) en el campo de IP.
- Si el teléfono y el PC están en la misma WiFi, funciona PC↔teléfono.
- ⚠️ Algunas redes (WiFi públicas / "aislamiento de cliente") bloquean la conexión entre dispositivos.
  Usa una red doméstica o un hotspot del móvil.

---

## ❓ Problemas comunes

| Síntoma | Causa / Solución |
|---|---|
| "No export template found" | Instala las plantillas 4.6.3 (Editor → Administrar plantillas). |
| "Java SDK path is invalid" | Apunta a la carpeta del **JDK 17** en Config. del Editor. |
| "Android SDK path is invalid" | Apunta a la carpeta del SDK (la que tiene `platform-tools`). |
| El APK instala pero no conecta | Mismo WiFi + IP local correcta + puerto 7777 no bloqueado. |
| Botones no responden al tocar | Ya está resuelto (toque habilitado). Si pasa, reporta. |

---

*Nota: yo (Claude) no puedo generar el APK directamente porque este entorno no tiene el
Android SDK ni el JDK instalados. Pero el proyecto ya está 100% listo para móvil; solo
sigue esta guía una vez y tendrás tu APK.* 🦄
