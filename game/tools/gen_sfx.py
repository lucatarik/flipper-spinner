#!/usr/bin/env python3
"""Deterministic synthesiser for the pinball / slot sound effects.

Stdlib only (wave, math, struct, random, os). Writes 22050 Hz mono 16-bit WAVs
into game/assets/sfx/.  Every sound in spec Part B is produced here; the two
"loop" sounds (reel_spin, plunger_charge) are rendered seamlessly.

The runtime autoload `Sfx` prefers a CC0 drop-in in assets/sfx/override/ and uses
the CC0 OGG tracks in assets/music/ for music (see the sound amendment), so
`temple_theme.wav` is only produced so the named list is complete.
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sfx")

random.seed(0x7E1D)  # deterministic noise


def clamp(v):
    return max(-1.0, min(1.0, v))


def silence(dur):
    return [0.0] * int(SR * dur)


def env_ad(n, attack=0.01, decay=1.0, curve=2.0):
    """Attack/decay envelope of n samples (seconds)."""
    a = max(1, int(SR * attack))
    out = []
    for i in range(n):
        if i < a:
            e = i / a
        else:
            e = max(0.0, 1.0 - (i - a) / max(1.0, n - a))
        out.append(e ** curve)
    return out


def sine(freq, dur, amp=0.5, decay=3.0, attack=0.005, phase=0.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        if isinstance(freq, (tuple, list)):
            f = freq[0] + (freq[1] - freq[0]) * (i / max(1, n - 1))
        else:
            f = freq
        a = amp
        if i < int(SR * attack):
            a *= i / max(1, int(SR * attack))
        else:
            a *= math.exp(-decay * t)
        out.append(math.sin(2 * math.pi * f * t + phase) * a)
    return out


def square(freq, dur, amp=0.3, decay=3.0):
    n = int(SR * dur)
    out = []
    for i in range(n):
        t = i / SR
        a = amp * math.exp(-decay * t)
        out.append((1.0 if math.sin(2 * math.pi * freq * t) >= 0 else -1.0) * a)
    return out


def noise(dur, amp=0.4, decay=6.0, lp=0.0, attack=0.002):
    n = int(SR * dur)
    out = []
    prev = 0.0
    a_coef = lp if 0.0 < lp <= 1.0 else 1.0
    for i in range(n):
        t = i / SR
        a = amp
        if i < int(SR * attack):
            a *= i / max(1, int(SR * attack))
        else:
            a *= math.exp(-decay * t)
        x = random.uniform(-1.0, 1.0)
        prev = prev + a_coef * (x - prev)
        out.append(prev * a)
    return out


def mix(*buffers):
    length = max(len(b) for b in buffers)
    out = [0.0] * length
    for b in buffers:
        for i, v in enumerate(b):
            out[i] += v
    return out


def concat(*buffers):
    out = []
    for b in buffers:
        out.extend(b)
    return out


def hz_note(semitones_from_a4):
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


# Middle-Eastern flavoured scale (A harmonic minor-ish) as semitone offsets.
MAQAM = [0, 2, 3, 5, 7, 8, 11]


def arpeggio(notes, note_dur, amp=0.4, decay=4.0):
    out = []
    for s in notes:
        out.extend(sine(hz_note(s), note_dur, amp=amp, decay=decay, attack=0.005))
    return out


def write_wav(name, samples, loop=False):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name + ".wav")
    n = len(samples)
    data = bytearray()
    # tiny DC-block to avoid clicks on loop points
    prev_in = 0.0
    prev_out = 0.0
    for v in samples:
        prev_out = v - prev_in + 0.995 * prev_out
        prev_in = v
        data += struct.pack("<h", int(clamp(prev_out) * 32000))
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    return path


def loopify(buf, fade=0.02):
    """Crossfade the tail into the head so the buffer loops without a click."""
    n = len(buf)
    f = max(1, int(SR * fade))
    if n <= 2 * f:
        return buf
    out = list(buf)
    for i in range(f):
        a = i / f
        out[i] = buf[i] * a + buf[n - f + i] * (1.0 - a)
    return out[: n - f]


def main():
    sounds = {}

    # --- pinball -----------------------------------------------------------
    sounds["flipper"] = mix(
        noise(0.07, amp=0.5, decay=45.0, lp=0.5),
        sine((240, 90), 0.09, amp=0.5, decay=30.0),
    )
    sounds["bumper"] = mix(
        sine((880, 1320), 0.14, amp=0.45, decay=16.0),
        noise(0.05, amp=0.25, decay=50.0, lp=0.6),
    )
    sounds["sling"] = mix(
        sine((520, 760), 0.11, amp=0.4, decay=20.0),
        noise(0.04, amp=0.2, decay=60.0, lp=0.7),
    )
    sounds["launch"] = mix(
        sine((180, 760), 0.38, amp=0.4, decay=3.0),
        noise(0.38, amp=0.28, decay=4.0, lp=0.15),
    )
    # seamless loop while the plunger is held
    charge = mix(
        sine(150, 0.40, amp=0.22, decay=0.0, attack=0.05),
        sine(225, 0.40, amp=0.18, decay=0.0, attack=0.05),
        sine(300, 0.40, amp=0.10, decay=0.0, attack=0.05),
    )
    sounds["plunger_charge"] = loopify(charge)
    sounds["drain"] = mix(
        sine((600, 90), 0.65, amp=0.4, decay=5.0),
        noise(0.5, amp=0.15, decay=4.0, lp=0.1),
    )
    sounds["target"] = mix(
        sine((700, 980), 0.13, amp=0.4, decay=18.0),
        noise(0.03, amp=0.2, decay=70.0),
    )
    sounds["target_bank"] = concat(
        sine(hz_note(7), 0.10, amp=0.35, decay=10.0),
        sine(hz_note(12), 0.10, amp=0.35, decay=10.0),
        sine(hz_note(16), 0.22, amp=0.4, decay=6.0),
    )
    sounds["lane"] = mix(
        sine(hz_note(16), 0.16, amp=0.35, decay=14.0),
        sine(hz_note(23), 0.16, amp=0.2, decay=14.0),
    )
    sounds["orbit"] = concat(
        sine(hz_note(12), 0.09, amp=0.35, decay=10.0),
        sine(hz_note(16), 0.09, amp=0.35, decay=10.0),
        sine(hz_note(19), 0.09, amp=0.35, decay=10.0),
        sine(hz_note(24), 0.16, amp=0.4, decay=7.0),
    )
    sounds["scoop"] = mix(
        sine((320, 720), 0.5, amp=0.35, decay=5.0),
        sine((480, 960), 0.5, amp=0.2, decay=5.0),
    )
    sounds["lock"] = mix(
        sine((160, 120), 0.28, amp=0.45, decay=12.0),
        noise(0.06, amp=0.3, decay=40.0, lp=0.4),
    )
    sounds["jackpot"] = concat(
        arpeggio([12, 16, 19, 24], 0.10, amp=0.35, decay=9.0),
        arpeggio([19, 24, 28], 0.16, amp=0.4, decay=4.0),
    )
    sounds["multiball"] = concat(
        arpeggio([12, 15, 19, 22, 24], 0.09, amp=0.32, decay=10.0),
        arpeggio([24, 19, 24, 27, 31], 0.13, amp=0.4, decay=5.0),
    )
    sounds["ball_save"] = concat(
        sine(hz_note(19), 0.11, amp=0.35, decay=9.0),
        sine(hz_note(26), 0.22, amp=0.4, decay=6.0),
    )
    sounds["game_start"] = concat(
        arpeggio([7, 12, 16, 19], 0.14, amp=0.35, decay=6.0),
        arpeggio([24, 19, 24, 28], 0.16, amp=0.4, decay=4.0),
    )
    sounds["game_over"] = concat(
        sine(hz_note(16), 0.30, amp=0.4, decay=4.0),
        sine(hz_note(12), 0.30, amp=0.4, decay=4.0),
        sine((hz_note(8), hz_note(2)), 0.9, amp=0.45, decay=2.0),
    )
    sounds["mode_start"] = concat(
        sine(hz_note(12), 0.12, amp=0.35, decay=8.0),
        sine(hz_note(19), 0.12, amp=0.35, decay=8.0),
        sine(hz_note(24), 0.26, amp=0.4, decay=5.0),
    )
    sounds["mode_complete"] = concat(
        arpeggio([24, 26, 28, 31], 0.11, amp=0.35, decay=8.0),
        arpeggio([31, 36], 0.22, amp=0.4, decay=4.0),
    )

    # --- slot --------------------------------------------------------------
    # Seamless reel spin: harmonic stack with integer cycle counts over 0.5 s.
    spin = []
    base = 0.5
    for i in range(int(SR * base)):
        t = i / SR
        v = 0.0
        for k, a in ((80, 0.25), (120, 0.18), (161, 0.10), (203, 0.07)):
            v += math.sin(2 * math.pi * k * t) * a
        spin.append(v)
    sounds["reel_spin"] = loopify(spin)
    sounds["reel_stop"] = mix(
        noise(0.05, amp=0.4, decay=60.0, lp=0.6),
        sine((900, 500), 0.10, amp=0.3, decay=22.0),
    )
    sounds["anticipation"] = sine((200, 900), 2.0, amp=0.32, decay=0.0, attack=0.5)
    sounds["win_small"] = concat(
        sine(hz_note(19), 0.10, amp=0.35, decay=10.0),
        sine(hz_note(24), 0.10, amp=0.35, decay=10.0),
        sine(hz_note(28), 0.18, amp=0.4, decay=7.0),
    )
    sounds["win_big"] = concat(
        arpeggio([12, 16, 19, 24, 28, 31], 0.09, amp=0.32, decay=9.0),
        arpeggio([31, 36], 0.25, amp=0.4, decay=4.0),
    )
    sounds["big_win"] = concat(
        arpeggio([7, 12, 16, 19, 24, 28, 31, 36], 0.09, amp=0.32, decay=8.0),
        arpeggio([36, 31, 36], 0.24, amp=0.4, decay=3.5),
    )
    sounds["coin"] = mix(
        sine((1180, 1560), 0.14, amp=0.4, decay=18.0),
        noise(0.03, amp=0.15, decay=70.0),
    )
    sounds["free_spins"] = concat(
        arpeggio([12, 19, 24, 28, 31, 36], 0.10, amp=0.32, decay=8.0),
        arpeggio([36, 40], 0.22, amp=0.4, decay=4.0),
    )
    sounds["book_reveal"] = mix(
        noise(0.5, amp=0.2, decay=3.0, lp=0.05),
        sine((300, 1200), 0.5, amp=0.3, decay=3.0),
    )
    sounds["bet_up"] = sine((500, 1000), 0.22, amp=0.35, decay=10.0)

    # --- table nudge / tilt (synthesised at the end so the RNG draws used by
    # the existing effects are unchanged) ----------------------------------
    sounds["nudge"] = mix(
        sine((150, 70), 0.16, amp=0.5, decay=22.0),
        noise(0.08, amp=0.35, decay=40.0, lp=0.12),
    )
    sounds["tilt"] = mix(
        square(110, 0.55, amp=0.28, decay=3.5),
        square(73, 0.55, amp=0.22, decay=3.5),
        noise(0.12, amp=0.2, decay=25.0, lp=0.3),
    )

    # --- D2 ramps / combo (synth'd at the end so earlier RNG draws hold) ---
    sounds["ramp_enter"] = mix(
        sine((220, 900), 0.32, amp=0.30, decay=4.0),
        noise(0.32, amp=0.20, decay=5.0, lp=0.12),
    )
    sounds["ramp_made"] = concat(
        arpeggio([12, 19, 24], 0.09, amp=0.32, decay=9.0),
        arpeggio([28, 31], 0.20, amp=0.38, decay=5.0),
    )
    sounds["combo"] = concat(
        arpeggio([24, 28, 31, 36], 0.07, amp=0.30, decay=11.0),
        sine(hz_note(36), 0.22, amp=0.36, decay=6.0),
    )

    # --- fallback theme (runtime music uses the CC0 OGG tracks) -----------
    theme = []
    bass = [0, 0, -5, -5, 3, 3, 2, 2]
    for bar in range(4):
        for step, s in enumerate(bass):
            theme.extend(sine(hz_note(s - 12), 0.5, amp=0.12, decay=0.6, attack=0.02))
    # overlay a slow arpeggio
    arp = []
    for bar in range(4):
        for s in (0, 3, 7, 10):
            arp.extend(sine(hz_note(s), 0.5, amp=0.10, decay=1.2, attack=0.03))
    theme = loopify(mix(theme, arp), fade=0.05)
    sounds["temple_theme"] = theme

    # --- write -------------------------------------------------------------
    for name, buf in sounds.items():
        # gentle normalisation headroom
        peak = max(1e-6, max(abs(v) for v in buf))
        scale = 0.85 / peak if peak > 0.85 else 1.0
        write_wav(name, [v * scale for v in buf])
        print("wrote %s.wav (%0.3fs)" % (name, len(buf) / SR))
    print("gen_sfx: %d files" % len(sounds))


if __name__ == "__main__":
    main()
