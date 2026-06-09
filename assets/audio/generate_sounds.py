#!/usr/bin/env python3
"""Genera efectos de sonido cortos y procedurales para Unstable Unicorns 2D.

No requiere dependencias externas (solo stdlib). Salida: .wav 44.1kHz 16-bit mono.
Volver a ejecutar:  python assets/audio/generate_sounds.py
Los sonidos son discretos a propósito; puedes reemplazarlos por otros .wav del
mismo nombre cuando quieras.
"""
import math
import os
import random
import struct
import wave

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))


def _envelope(n, attack=0.005, release=0.05):
    """Envolvente attack/decay simple para evitar clics al inicio/fin."""
    a = int(SR * attack)
    r = int(SR * release)
    env = []
    for i in range(n):
        e = 1.0
        if i < a:
            e = i / max(1, a)
        elif i > n - r:
            e = max(0.0, (n - i) / max(1, r))
        env.append(e)
    return env


def _write(name, samples, volume=0.35):
    """Normaliza, aplica volumen y escribe el .wav."""
    peak = max((abs(s) for s in samples), default=1.0) or 1.0
    scale = (volume / peak) * 32767.0
    path = os.path.join(HERE, name)
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        frames = bytearray()
        for s in samples:
            v = int(max(-32768, min(32767, s * scale)))
            frames += struct.pack("<h", v)
        w.writeframes(bytes(frames))
    print("  ->", name, "(%.2fs)" % (len(samples) / SR))


def tone(freq, dur, kind="sine", vibrato=0.0):
    n = int(SR * dur)
    env = _envelope(n)
    out = []
    for i in range(n):
        t = i / SR
        f = freq * (1.0 + vibrato * math.sin(2 * math.pi * 6 * t))
        ph = 2 * math.pi * f * t
        if kind == "sine":
            s = math.sin(ph)
        elif kind == "saw":
            s = 2.0 * ((f * t) % 1.0) - 1.0
        elif kind == "square":
            s = 1.0 if math.sin(ph) >= 0 else -1.0
        else:
            s = math.sin(ph)
        out.append(s * env[i])
    return out


def sweep(f0, f1, dur, kind="saw"):
    n = int(SR * dur)
    env = _envelope(n)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = f0 + (f1 - f0) * (i / n)
        phase += 2 * math.pi * f / SR
        if kind == "saw":
            s = 2.0 * ((phase / (2 * math.pi)) % 1.0) - 1.0
        else:
            s = math.sin(phase)
        out.append(s * env[i])
    return out


def noise(dur, decay=8.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        e = math.exp(-decay * (i / n))
        out.append((random.uniform(-1, 1)) * e)
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def concat(*tracks):
    out = []
    for t in tracks:
        out += t
    return out


def main():
    random.seed(42)
    print("Generando sonidos en", HERE)

    # Click de UI: blip corto y agudo.
    _write("click.wav", tone(880, 0.05), volume=0.25)

    # Robar carta: swish corto (ruido con decaimiento) + leve blip.
    _write("draw.wav", mix(noise(0.16, decay=14.0), tone(520, 0.10)), volume=0.30)

    # Jugar carta: whoosh suave (ruido + tono grave descendente).
    _write("play.wav", mix(noise(0.18, decay=10.0), sweep(420, 180, 0.18, "sine")), volume=0.32)

    # Relincho: alerta de dos tonos con vibrato (evoca un "neigh").
    _write("neigh.wav", concat(tone(660, 0.12, "square", vibrato=0.04),
                               tone(440, 0.18, "square", vibrato=0.06)), volume=0.30)

    # Destruir: zap descendente (sawtooth grave).
    _write("destroy.wav", sweep(500, 70, 0.28, "saw"), volume=0.34)

    # Inicio de turno: campanita suave (quinta justa).
    _write("turn.wav", mix(tone(523, 0.30), tone(784, 0.30)), volume=0.22)

    # Victoria: arpegio ascendente C-E-G-C.
    _write("win.wav", concat(tone(523, 0.13), tone(659, 0.13),
                             tone(784, 0.13), tone(1046, 0.30)), volume=0.30)

    # Barajar: ráfaga de clics cortos (riffle).
    riffle = []
    for _ in range(7):
        riffle += noise(0.04, decay=30.0)
        riffle += [0.0] * int(SR * 0.015)
    _write("shuffle.wav", riffle, volume=0.26)

    print("Listo.")


if __name__ == "__main__":
    main()
