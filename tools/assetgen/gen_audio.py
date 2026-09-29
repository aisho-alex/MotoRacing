#!/usr/bin/env python3
"""Procedural audio set: engine loop, tires, UI, impacts.

All loops are synthesized with periodic LFOs and periodic noise (FFT-domain),
so they loop seamlessly by construction. WAVs are converted to mono OGG via
ffmpeg. Every file gets a .license sidecar.

Output:
  assets/audio/engine/sport/engine.ogg     (4.0 s loop)
  assets/audio/tires/{screech,skid}.ogg    (1.5 s loops)
  assets/audio/ui/{countdown_1,2,3,go,lap,finish,click,unlock}.ogg
  assets/audio/impacts/{hit_light,landing}.ogg
"""

import os
import subprocess
import tempfile
import wave

import numpy as np

from pbr_common import DATE, asset_path, write_license

SR = 44100
TOOL = "procedural synthesis (tools/assetgen/gen_audio.py)"


def pnoise(n: int, mask, seed: int) -> np.ndarray:
    """Periodic (seamless) filtered noise of length n."""
    rng = np.random.default_rng(seed)
    spec = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1.0 / SR)
    return np.fft.irfft(spec * mask(freqs), n)


def bandpass(lo: float, hi: float):
    return lambda f: 1.0 / (1.0 + np.exp(-(f - lo) / 60.0)) * 1.0 / (1.0 + np.exp((f - hi) / 60.0))


def lowpass(fc: float, order: float = 90.0):
    return lambda f: 1.0 / (1.0 + (f / fc) ** order)


def fade(x: np.ndarray, ms: float = 8.0) -> np.ndarray:
    k = max(int(SR * ms / 1000.0), 1)
    ramp = np.linspace(0.0, 1.0, k)
    x = x.copy()
    x[:k] *= ramp
    x[-k:] *= ramp[::-1]
    return x


def write_ogg(rel: str, sig: np.ndarray, peak: float, note: str, tool: str = TOOL) -> None:
    sig = sig / max(np.abs(sig).max(), 1e-9) * peak
    pcm = (np.clip(sig, -1.0, 1.0) * 32767.0).astype(np.int16)
    out = asset_path(rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        wav = tmp.name
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-ac", "1", "-ar", "44100",
         "-c:a", "libvorbis", "-qscale:a", "4", out],
        check=True,
    )
    os.remove(wav)
    write_license(out + ".license", os.path.basename(out), tool, note)
    print(f"  {rel} ({len(sig) / SR:.2f}s)")


def engine_loop() -> np.ndarray:
    dur = 4.0
    n = int(SR * dur)
    t = np.arange(n) / SR
    f0 = 78.0  # Hz; integer number of cycles over the loop
    sig = np.zeros(n)
    for k, a in [(1, 1.0), (2, 0.55), (3, 0.38), (4, 0.28), (5, 0.20), (6, 0.14), (7, 0.10), (8, 0.08)]:
        fk = f0 * k
        sig += a * np.sin(2 * np.pi * fk * t + 1.2 * np.sin(2 * np.pi * fk * 0.5 * t))
    am = 1.0 + 0.22 * np.sin(2 * np.pi * 31.0 * t)           # firing pulses
    rough = 0.15 * np.sin(2 * np.pi * 13.0 * t + 2.0 * np.sin(2 * np.pi * 7.0 * t))
    exhaust = pnoise(n, lowpass(700), seed=7) * 0.35
    # no fade: every component is periodic, so the loop joint is continuous
    return sig * am * 0.5 + rough * 0.5 + exhaust * 0.4


def screech_loop() -> np.ndarray:
    dur = 1.5
    n = int(SR * dur)
    t = np.arange(n) / SR
    body = pnoise(n, bandpass(1200, 2400), seed=17)
    layer2 = pnoise(n, bandpass(2000, 3200), seed=18) * 0.4
    am = 0.65 + 0.35 * np.sin(2 * np.pi * 8.0 * t)           # 12 cycles: periodic
    return (body + layer2) * am


def skid_loop() -> np.ndarray:
    dur = 1.5
    n = int(SR * dur)
    t = np.arange(n) / SR
    body = pnoise(n, lowpass(500), seed=19)
    am = 0.7 + 0.3 * np.sin(2 * np.pi * 6.0 * t)             # 9 cycles: periodic
    return body * am


def beep(freq: float, dur: float, harm: float = 0.3) -> np.ndarray:
    n = int(SR * dur)
    t = np.arange(n) / SR
    env = np.exp(-t * 6.0)
    return (np.sin(2 * np.pi * freq * t) + harm * np.sin(2 * np.pi * freq * 2 * t)) * env


def sequence(notes: list[tuple[float, float]], gap: float = 0.0) -> np.ndarray:
    parts = []
    for freq, dur in notes:
        parts.append(beep(freq, dur))
        if gap > 0:
            parts.append(np.zeros(int(SR * gap)))
    return np.concatenate(parts)


def main() -> None:
    print("gen_audio:")
    write_ogg("audio/engine/sport/engine.ogg", engine_loop(), 0.5, "4s seamless loop, f0=78Hz + harmonics")
    write_ogg("audio/tires/screech.ogg", screech_loop(), 0.45, "1.5s seamless loop, bandpass noise")
    write_ogg("audio/tires/skid.ogg", skid_loop(), 0.40, "1.5s seamless loop, lowpass rumble")

    for i in (1, 2, 3):
        write_ogg(f"audio/ui/countdown_{i}.ogg", beep(660.0, 0.16), 0.6, "countdown beep")
    write_ogg("audio/ui/countdown_go.ogg", sequence([(990.0, 0.42), (1485.0, 0.0)]), 0.6, "go chord")
    write_ogg("audio/ui/lap.ogg", sequence([(880.0, 0.12), (1174.7, 0.2)], gap=0.02), 0.55, "lap chime")
    write_ogg(
        "audio/ui/finish.ogg",
        np.concatenate([
            sequence([(523.25, 0.14), (659.25, 0.14), (784.0, 0.14)], gap=0.01),
            beep(1046.5, 0.5) + beep(1318.5, 0.5) * 0.5,
        ]),
        0.6,
        "finish fanfare",
    )
    click = pnoise(int(SR * 0.03), highpass_like(), seed=21)
    write_ogg("audio/ui/click.ogg", fade(click, 1.0), 0.5, "ui click burst")
    write_ogg("audio/ui/unlock.ogg", sequence([(660.0, 0.12), (880.0, 0.22)], gap=0.02), 0.55, "unlock jingle")

    n_hit = int(SR * 0.25)
    t_hit = np.arange(n_hit) / SR
    hit = pnoise(n_hit, lowpass(2500), seed=23) * np.exp(-t_hit * 30.0) + 0.8 * np.sin(2 * np.pi * 110 * t_hit) * np.exp(-t_hit * 25.0)
    write_ogg("audio/impacts/hit_light.ogg", hit, 0.7, "wall impact: noise burst + 110Hz thud")

    n_land = int(SR * 0.4)
    t_land = np.arange(n_land) / SR
    land = pnoise(n_land, lowpass(900), seed=24) * np.exp(-t_land * 18.0) + np.sin(2 * np.pi * 70 * t_land) * np.exp(-t_land * 14.0)
    write_ogg("audio/impacts/landing.ogg", land, 0.7, "ramp landing: 70Hz thud + dirt noise")


def highpass_like():
    return lambda f: 1.0 / (1.0 + (300.0 / np.maximum(f, 1.0)) ** 4)


if __name__ == "__main__":
    main()
