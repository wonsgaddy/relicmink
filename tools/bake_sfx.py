"""Generate original, short retro SFX with no external assets or dependencies."""
from pathlib import Path
import math
import random
import struct
import wave

RATE = 22050
OUTPUT = Path(__file__).resolve().parents[1] / "audio" / "sfx"
OUTPUT.mkdir(parents=True, exist_ok=True)


def bake(name, duration, kind):
    rng = random.Random(name)
    samples = []
    phase = 0.0
    filtered = 0.0
    for index in range(round(duration * RATE)):
        t = index / RATE
        u = t / duration
        filtered += (rng.uniform(-1, 1) - filtered) * 0.32
        envelope = min(1, t / 0.006) * (1 - u) ** 1.7
        if kind == "charge":
            frequency = 80 + 330 * u * u
            phase += math.tau * frequency / RATE
            value = (math.sin(phase) * 0.45 + filtered * 0.35) * (0.3 + 0.7 * u)
            envelope = min(1, t / 0.03) * min(1, (duration - t) / 0.04)
        elif kind in ("launch", "dash"):
            phase += math.tau * (260 * (1 - u) + 55) / RATE
            value = filtered * 0.8 + math.sin(phase) * (0.3 if kind == "launch" else 0.12)
        elif kind in ("impact", "boss_hit"):
            phase += math.tau * (110 * math.exp(-t * 23) + 38) / RATE
            value = math.sin(phase) * 0.85 + filtered * 0.6 * math.exp(-t * 12)
        elif kind in ("spray", "burst", "splash", "mine"):
            phase += math.tau * (180 + 650 * (1 - u) ** 3) / RATE
            bubbles = 0.5 + 0.5 * math.sin(t * math.tau * (28 if kind == "splash" else 17))
            value = math.sin(phase + math.sin(t * 210) * 1.3) * bubbles * 0.6 + filtered * 0.5
        elif kind == "shot":
            phase += math.tau * (160 + 1450 * math.exp(-t * 95)) / RATE
            value = math.sin(phase) * 0.55 + filtered * 0.9
        elif kind == "hurt":
            phase += math.tau * (480 * (1 - u) + 90) / RATE
            value = (1 if math.sin(phase) > 0 else -1) * 0.35 + filtered * 0.25
        elif kind == "drink":
            local = (t % 0.16) / 0.16
            phase += math.tau * (150 + 310 * (1 - local) ** 2) / RATE
            value = math.sin(phase) * math.sin(math.pi * local) ** 4 * 0.8 + filtered * 0.08
        elif kind in ("win", "lose"):
            notes = [330, 440, 554, 660] if kind == "win" else [330, 277, 220, 165]
            frequency = notes[min(3, int(u * 4))]
            phase += math.tau * frequency / RATE
            value = math.sin(phase) * 0.65 + math.sin(phase * 2) * 0.12
        else:  # Periodic loop: integer cycles, no random discontinuity at the seam.
            value = (math.sin(math.tau * 80 * t) * 0.55 + math.sin(math.tau * 160 * t) * 0.18)
            value *= 0.7 + 0.3 * math.cos(math.tau * 10 * t)
            envelope = 1.0
        samples.append(value * envelope)
    peak = max(abs(value) for value in samples) or 1
    pcm = b"".join(struct.pack("<h", round(value / peak * 0.72 * 32767)) for value in samples)
    with wave.open(str(OUTPUT / (name + ".wav")), "wb") as output:
        output.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        output.writeframes(pcm)


if __name__ == "__main__":
    for spec in [
        ("charge", 0.48, "charge"), ("launch", 0.20, "launch"),
        ("impact", 0.23, "impact"), ("spray", 0.20, "spray"),
        ("burst", 0.24, "burst"), ("splash", 0.09, "splash"),
        ("mine", 0.34, "mine"), ("shot", 0.075, "shot"),
        ("boss_hit", 0.09, "boss_hit"), ("hurt", 0.20, "hurt"),
        ("dash", 0.13, "dash"), ("drink", 0.52, "drink"),
        ("win", 0.65, "win"), ("lose", 0.60, "lose"),
        ("roll", 0.40, "roll"),
    ]:
        bake(*spec)
    print("Baked 15 original SFX in audio/sfx")
