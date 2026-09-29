#!/usr/bin/env python3
"""Procedural music: menu theme and two race loops (synth arcade style).

All events are quantized to a whole number of bars, note tails end inside the
loop, so every track loops seamlessly.

Output:
  assets/audio/music/menu.ogg          (soft pads, 90 BPM)
  assets/audio/music/race_city.ogg     (energetic, 128 BPM, Am F C G)
  assets/audio/music/race_desert.ogg   (energetic, 128 BPM, Dm Bb F C)
"""

import numpy as np

from gen_audio import SR, lowpass, pnoise, write_ogg

TOOL = "procedural synthesis (tools/assetgen/gen_music.py)"

# (bass root Hz, third ratio, name) — minor: 2^(3/12), major: 2^(4/12)
MIN3 = 2 ** (3.0 / 12.0)
MAJ3 = 2 ** (4.0 / 12.0)
PROG_CITY = [(55.00, MIN3, "Am"), (43.65, MAJ3, "F"), (65.41, MAJ3, "C"), (49.00, MAJ3, "G")]
PROG_DESERT = [(73.42, MIN3, "Dm"), (58.27, MAJ3, "Bb"), (43.65, MAJ3, "F"), (65.41, MAJ3, "C")]


def saw(freq: float, dur: float, vol: float = 1.0, harm: int = 12) -> np.ndarray:
    n = int(SR * dur)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for k in range(1, harm + 1):
        sig += np.sin(2 * np.pi * freq * k * t) / k
    return sig * vol


def env_ad(n: int, attack: float, release: float) -> np.ndarray:
    a = max(int(SR * attack), 1)
    r = max(int(SR * release), 1)
    env = np.ones(n)
    env[:a] = np.linspace(0.0, 1.0, a)
    env[-r:] *= np.linspace(1.0, 0.0, r)
    return env


def filtered(sig: np.ndarray, fc: float) -> np.ndarray:
    spec = np.fft.rfft(sig)
    freqs = np.fft.rfftfreq(len(sig), 1.0 / SR)
    return np.fft.irfft(spec * lowpass(fc)(freqs), len(sig))


def kick(dur: float = 0.24) -> np.ndarray:
    n = int(SR * dur)
    t = np.arange(n) / SR
    freq = 120.0 * np.exp(-t * 22.0) + 42.0
    phase = 2 * np.pi * np.cumsum(freq) / SR
    return np.sin(phase) * np.exp(-t * 14.0)


def hat(dur: float = 0.045, seed: int = 0) -> np.ndarray:
    n = int(SR * dur)
    noise = pnoise(n, lambda f: (f > 5500).astype(float), seed=seed)
    return noise * np.exp(-np.arange(n) / SR * 60.0)


class Composer:
    def __init__(self, total: float):
        self.n = int(SR * total)
        self.buf = np.zeros(self.n)

    def add(self, sig: np.ndarray, at: float, vol: float = 1.0) -> None:
        start = int(at * SR) % self.n
        end = min(start + len(sig), self.n)
        if end > start:
            self.buf[start:end] += sig[: end - start] * vol

    def finish(self) -> np.ndarray:
        return self.buf


def race_loop(prog: list, bpm: float, hats16: bool, seed: int) -> np.ndarray:
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 8
    total = bars * bar
    c = Composer(total)
    k = kick()
    h = hat(seed=seed)
    for b in range(bars):
        root, third, _ = prog[b % len(prog)]
        t0 = b * bar
        for beat_i in range(4):  # kicks + hats
            c.add(k, t0 + beat_i * beat, 0.9)
            if hats16:
                for s in range(4):
                    c.add(h, t0 + beat_i * beat + s * beat / 4.0, 0.35 if s % 2 == 0 else 0.22)
            else:
                c.add(h, t0 + beat_i * beat + beat / 2.0, 0.4)
        # bass: driving eighth notes with an octave lift at "and" of 4
        bass_fc = 620.0
        for e in range(8):
            f = root * (2.0 if e == 6 else 1.0)
            note = filtered(saw(f, beat / 2.0 * 0.95), bass_fc) * env_ad(int(SR * beat / 2.0 * 0.95), 0.004, 0.05)
            c.add(note, t0 + e * beat / 2.0, 0.5)
        # chord stabs on beats 2 and 4
        chord = [root * 2.0, root * 2.0 * third, root * 3.0]
        for st in (1.0, 3.0):
            for f in chord:
                det = 1.003
                stab = saw(f, 0.3) + saw(f * det, 0.3)
                c.add(stab * env_ad(len(stab), 0.004, 0.22), t0 + st * beat, 0.16)
    return c.finish()


def menu_loop(prog: list, bpm: float) -> np.ndarray:
    beat = 60.0 / bpm
    bar = 4 * beat
    bars = 8
    total = bars * bar
    c = Composer(total)
    for b in range(bars):
        root, third, _ = prog[b % len(prog)]
        t0 = b * bar
        # pad chord: soft detuned saws, one bar long
        chord = [root * 2.0, root * 2.0 * third, root * 3.0, root * 4.0]
        pad = np.zeros(int(SR * bar))
        for f in chord:
            pad += saw(f, bar, 0.6, harm=8)
        pad = filtered(pad, 900.0) * env_ad(len(pad), 0.4, 0.6)
        c.add(pad, t0, 0.16)
        # slow bass half notes
        for half in range(2):
            f = root * (1.0 if half == 0 else 2.0)
            note = filtered(saw(f, beat * 2.0 * 0.92), 420.0)
            note *= env_ad(len(note), 0.02, 0.2)
            c.add(note, t0 + half * beat * 2.0, 0.4)
        # sparkle arpeggio, quiet
        arp = [root * 4.0, root * 6.0, root * 5.0, root * 6.0]
        for i, f in enumerate(arp):
            pluck = saw(f, 0.22, 1.0, harm=6) * env_ad(int(SR * 0.22), 0.002, 0.16)
            c.add(pluck, t0 + beat * 3.0 + i * beat / 4.0, 0.10)
    return c.finish()


def main() -> None:
    print("gen_music:")
    write_ogg("audio/music/race_city.ogg", race_loop(PROG_CITY, 128.0, hats16=False, seed=41),
              0.5, "128 BPM arcade synth loop, Am F C G", tool=TOOL)
    write_ogg("audio/music/race_desert.ogg", race_loop(PROG_DESERT, 128.0, hats16=True, seed=42),
              0.5, "128 BPM arcade synth loop, Dm Bb F C", tool=TOOL)
    write_ogg("audio/music/menu.ogg", menu_loop(PROG_CITY, 90.0),
              0.5, "90 BPM soft menu theme", tool=TOOL)


if __name__ == "__main__":
    main()
