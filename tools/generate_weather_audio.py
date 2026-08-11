from __future__ import annotations

import math
import wave
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "assets" / "audio" / "weather"
SAMPLE_RATE = 44_100


def normalize(signal: np.ndarray, peak: float) -> np.ndarray:
    maximum = float(np.max(np.abs(signal)))
    if maximum > 0.0:
        signal = signal * (peak / maximum)
    return signal


def write_wav(path: Path, signal: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(signal, -1.0, 1.0)
    pcm = np.asarray(clipped * 32767.0, dtype="<i2")
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def periodic_colored_noise(rng: np.random.Generator, samples: int, color: float) -> np.ndarray:
    frequencies = np.fft.rfftfreq(samples, 1.0 / SAMPLE_RATE)
    spectrum = rng.normal(size=frequencies.size) + 1j * rng.normal(size=frequencies.size)
    spectrum[0] = 0.0
    weighting = np.power(np.maximum(frequencies, 0.35), -color)
    spectrum *= weighting
    return normalize(np.fft.irfft(spectrum, n=samples), 1.0)


def make_rain_loop() -> np.ndarray:
    rng = np.random.default_rng(20260810)
    seconds = 14.0
    samples = int(SAMPLE_RATE * seconds)
    air = periodic_colored_noise(rng, samples, 0.08)
    body = periodic_colored_noise(rng, samples, 0.62)
    rain = air * 0.45 + body * 0.22

    # Soft impacts provide the uneven, painted-window character of real rain.
    for _ in range(290):
        center = int(rng.integers(0, samples))
        duration = int(rng.uniform(0.008, 0.035) * SAMPLE_RATE)
        amplitude = float(rng.uniform(0.015, 0.075))
        decay = np.exp(-np.arange(duration) / max(1.0, duration * rng.uniform(0.17, 0.34)))
        tone = np.sin(
            2.0 * math.pi * rng.uniform(850.0, 2900.0) * np.arange(duration) / SAMPLE_RATE
        )
        drop = amplitude * decay * (0.35 * tone + 0.65 * rng.normal(size=duration))
        indices = (center + np.arange(duration)) % samples
        np.add.at(rain, indices, drop)

    # A slow periodic breathing layer avoids a static white-noise impression.
    phase = np.arange(samples) / samples
    rain *= 0.88 + 0.08 * np.sin(phase * math.tau * 3.0 + 0.4) + 0.04 * np.sin(
        phase * math.tau * 7.0 + 2.1
    )
    return normalize(rain, 0.72)


def smooth_noise(rng: np.random.Generator, samples: int, window: int) -> np.ndarray:
    raw = rng.normal(size=samples + window)
    kernel = np.ones(window, dtype=np.float64) / float(window)
    return np.convolve(raw, kernel, mode="valid")[:samples]


def make_thunder(seed: int, duration: float, close: bool, rolling: bool) -> np.ndarray:
    rng = np.random.default_rng(seed)
    samples = int(SAMPLE_RATE * duration)
    time = np.arange(samples) / SAMPLE_RATE
    attack = 1.0 - np.exp(-time * (90.0 if close else 18.0))
    decay = np.exp(-time / (2.4 if close else 3.5))
    envelope = attack * decay

    low = smooth_noise(rng, samples, 680 if close else 1050)
    mid = smooth_noise(rng, samples, 105 if close else 170)
    signal = low * 1.7 + mid * 0.42

    if close:
        crack_length = int(0.16 * SAMPLE_RATE)
        crack_time = np.arange(crack_length) / SAMPLE_RATE
        crack = rng.normal(size=crack_length) * np.exp(-crack_time * 28.0)
        signal[:crack_length] += crack * 1.2

    if rolling:
        for center, gain, width in ((1.25, 0.75, 0.44), (2.65, 0.52, 0.7), (4.1, 0.31, 0.85)):
            pulse = np.exp(-0.5 * np.square((time - center) / width))
            signal += smooth_noise(rng, samples, 760) * pulse * gain

    signal *= envelope
    signal += np.sin(2.0 * math.pi * (43.0 + 5.0 * np.sin(time * 1.8)) * time) * envelope * 0.14
    fade_samples = int(0.35 * SAMPLE_RATE)
    signal[-fade_samples:] *= np.linspace(1.0, 0.0, fade_samples)
    return normalize(signal, 0.88)


def main() -> None:
    write_wav(OUTPUT / "rain_window_loop.wav", make_rain_loop())
    write_wav(OUTPUT / "thunder_close.wav", make_thunder(71, 5.5, True, True))
    write_wav(OUTPUT / "thunder_distant.wav", make_thunder(83, 6.8, False, True))
    write_wav(OUTPUT / "thunder_rolling.wav", make_thunder(97, 7.5, False, True))
    print(f"Generated weather audio in {OUTPUT}")


if __name__ == "__main__":
    main()
