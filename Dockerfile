# ==============================================================================
# Servidor dedicado de "Unstable Unicorns 2D" para Render (Godot headless).
# Opción 🅰️: una partida a la vez, con salas por código.
#
# Render: New → Web Service → este repo. Render detecta el Dockerfile y lo
# construye. El servidor escucha en el puerto de la variable $PORT (Render la fija).
# ==============================================================================
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
# Versión de Godot (DEBE coincidir con la de desarrollo, 4.6.x; con 4.3 los
# autoloads del proyecto 4.6 no compilan y quedan nulos).
ENV GODOT_VERSION=4.6.3-stable

# Dependencias mínimas para Godot headless.
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip ca-certificates \
    libfontconfig1 libfreetype6 libx11-6 libxcursor1 libxinerama1 \
    libxrandr2 libxi6 libgl1 libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*

# Descargar Godot (binario Linux headless/editor; sirve para correr el proyecto).
RUN wget -q "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" -O /tmp/godot.zip \
    && unzip -q /tmp/godot.zip -d /usr/local/bin \
    && mv /usr/local/bin/Godot_v${GODOT_VERSION}_linux.x86_64 /usr/local/bin/godot \
    && chmod +x /usr/local/bin/godot \
    && rm /tmp/godot.zip

WORKDIR /app
COPY . /app

# Importar recursos una vez (genera la carpeta .godot/ con el caché de imports).
RUN godot --headless --import --path . || true

# Render asigna el puerto en $PORT; el servidor (OnlineServer.gd) lo lee.
EXPOSE 7777

# Arranca como servidor dedicado (sin jugador local). OnlineServer detecta --dedicated.
CMD ["godot", "--headless", "--path", ".", "--dedicated"]
