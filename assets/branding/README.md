# 🎨 Carpeta de branding (imágenes del juego)

Pon aquí tus imágenes y la **pantalla de apertura** las usará automáticamente.
Si un archivo no existe, la apertura muestra un fondo y título por defecto (no falla).

## Archivos que reconoce la apertura
Coloca los que tengas (PNG o JPG). Nombres EXACTOS:

| Archivo | Para qué | Tamaño sugerido |
|---|---|---|
| `background.png` | Fondo a pantalla completa de la apertura | 1280×720 o mayor (16:9) |
| `logo.png`       | Logo/banner centrado (con transparencia) | ~700 px de ancho |

> También acepta `.jpg` con el mismo nombre (ej. `background.jpg`).

## Cómo añadirlas
1. Copia tus imágenes a esta carpeta (`assets/branding/`).
2. Abre el proyecto en Godot una vez (importa las imágenes solo).
3. Ejecuta el juego: verás tu apertura. ¡Listo!

La apertura dura ~2.5s y se puede saltar tocando la pantalla o pulsando una tecla.
