#!/usr/bin/env python3
"""Deterministic generator for the ORIGINAL background track "Camel Groove".

Style homage only: mid-80s Italo-disco, 118 BPM, 4-on-the-floor kick, off-beat
open hi-hat, gated clap on 2 and 4, octave-jumping synth bass, lush pad and an
original lead motif in the Phrygian-dominant scale on E (E F G# A B C D).

No melody, riff, chord sequence or lyric from any existing song is used. Stdlib
only (wave, math, struct, random, os, shutil, subprocess); deterministic. Writes
32 bars (~65 s) 22050 Hz mono, peak <= -3 dBFS, seamless loop, as
game/assets/music/camel_groove.ogg (ffmpeg q4) or .wav when ffmpeg is absent.
"""
import math
import os
import random
import shutil
import struct
import subprocess
import wave

SR = 22050
BPM = 118.0
BEAT = 60.0 / BPM
BARS = 32
BEATS = BARS * 4
TOTAL = int(round(BEATS * BEAT * SR))

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "music")
random.seed(0xCA11E1)


def add(dst, buf, start, amp=1.0):
    n = len(dst)
    for i, v in enumerate(buf):
        j = start + i
        if 0 <= j < n:
            dst[j] += v * amp


def tone(freq, dur, amp, kind="sine", attack=0.004, release=0.03, detune=0.0):
    n = int(dur * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        phase += (freq * (1.0 + detune)) / SR
        if kind == "saw":
            v = 2.0 * (phase % 1.0) - 1.0
        elif kind == "triangle":
            p = phase % 1.0
            v = 4.0 * abs(p - 0.5) - 1.0
        elif kind == "pulse":
            v = 1.0 if (phase % 1.0) < 0.35 else -1.0
        else:
            v = math.sin(2.0 * math.pi * phase)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        rem = dur - t
        if rem < release:
            env *= max(0.0, rem / release)
        out[i] = v * amp * env
    return out


def kick(dur=0.30, amp=0.95):
    n = int(dur * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = 50.0 + 110.0 * math.exp(-t * 28.0)
        phase += f / SR
        env = math.exp(-t * 9.0) * min(1.0, t / 0.002)
        click = math.exp(-t * 120.0) * 0.25
        out[i] = (math.sin(2.0 * math.pi * phase) + click) * env * amp
    return out


def hat(dur=0.11, amp=0.22):
    n = int(dur * SR)
    out = [0.0] * n
    band = 0.0
    for i in range(n):
        t = i / SR
        x = random.uniform(-1.0, 1.0)
        # crude high-pass: keep the fast component
        band = 0.75 * band + 0.25 * x
        hp = x - band
        out[i] = hp * math.exp(-t * 42.0) * amp
    return out


def clap(dur=0.22, amp=0.42):
    n = int(dur * SR)
    out = [0.0] * n
    for i in range(n):
        t = i / SR
        gate = 0.0
        for off in (0.0, 0.028, 0.056):
            d = t - off
            if 0.0 <= d < 0.05:
                gate = max(gate, math.exp(-d * 95.0))
        tail = math.exp(-max(0.0, t - 0.056) * 20.0) if t >= 0.056 else 0.0
        out[i] = random.uniform(-1.0, 1.0) * (gate + tail * 0.5) * amp
    return out


def hz(semitones_from_e4):
    return 329.63 * (2.0 ** (semitones_from_e4 / 12.0))


# Phrygian dominant on E: E F G# A B C D  -> semitone offsets
SCALE = [0, 1, 4, 5, 7, 8, 10]
# original 8-note lead motif (scale degrees), soft and non-dominant
MOTIF = [0, 1, 4, 5, 7, 8, 7, 5]
# four-bar chord roots (scale degree index): E, F, A, B
ROOT_DEG = [0, 1, 3, 4]


def lead_note(deg, octave):
    s = SCALE[deg % len(SCALE)] + 12 * (deg // len(SCALE)) + 12 * octave
    return hz(s)


def main():
    master = [0.0] * TOTAL

    for beat in range(BEATS):
        start = int(round(beat * BEAT * SR))
        add(master, kick(), start)
        half = int(round((beat + 0.5) * BEAT * SR))
        add(master, hat(), half)
        if beat % 4 in (1, 3):  # beats 2 and 4
            add(master, clap(), start)

    # octave-jumping bass on eighth notes, 8ths alternate root / root+12
    for bar in range(BARS):
        root_deg = ROOT_DEG[(bar // 1) % len(ROOT_DEG)]
        for eighth in range(8):
            beat = bar * 4 + eighth * 0.5
            start = int(round(beat * BEAT * SR))
            octave = 1 if eighth % 2 == 1 else 0
            f = lead_note(root_deg, -2 + octave)
            add(master, tone(f, BEAT * 0.5 * 0.95, 0.22, kind="saw",
                             attack=0.003, release=0.02), start)

    # lush pad: sustained triad per bar (root, third, fifth in the scale)
    for bar in range(BARS):
        root_deg = ROOT_DEG[bar % len(ROOT_DEG)]
        start = int(round(bar * 4 * BEAT * SR))
        dur = 4 * BEAT
        for step in (0, 2, 4):
            f = lead_note(root_deg + step, 0)
            for det in (-0.004, 0.004):
                buf = tone(f, dur, 0.045, kind="sine", attack=0.25,
                           release=0.35, detune=det)
                add(master, buf, start)

    # original lead motif: one soft phrase every 4 bars
    for group in range(BARS // 4):
        base = group * 4 * 4  # beats
        for k, deg in enumerate(MOTIF):
            beat = base + 2 + k  # start at bar 2 of the group
            start = int(round(beat * BEAT * SR))
            f = lead_note(deg, 1)
            add(master, tone(f, BEAT * 0.85, 0.085, kind="triangle",
                             attack=0.02, release=0.08), start)

    _loopify(master, fade=0.02)
    _normalise(master, peak=0.70)
    _write(master)


def _loopify(buf, fade=0.02):
    n = len(buf)
    f = max(1, int(SR * fade))
    for i in range(f):
        a = i / f
        buf[i] = buf[i] * a + buf[n - f + i] * (1.0 - a)
    del buf[n - f:]


def _normalise(buf, peak):
    mx = max(1e-6, max(abs(v) for v in buf))
    if mx > peak:
        s = peak / mx
        for i in range(len(buf)):
            buf[i] *= s


def _write(buf):
    os.makedirs(OUT_DIR, exist_ok=True)
    wav_path = os.path.join(OUT_DIR, "camel_groove.wav")
    data = bytearray()
    for v in buf:
        data += struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32000))
    with wave.open(wav_path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(bytes(data))
    print("wrote camel_groove.wav (%0.2fs)" % (len(buf) / SR))

    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg:
        ogg_path = os.path.join(OUT_DIR, "camel_groove.ogg")
        cmd = [ffmpeg, "-y", "-loglevel", "error", "-i", wav_path,
               "-c:a", "libvorbis", "-q:a", "4", ogg_path]
        try:
            subprocess.run(cmd, check=True)
            os.remove(wav_path)
            print("wrote camel_groove.ogg (ffmpeg q4)")
        except (subprocess.CalledProcessError, OSError) as exc:
            print("ffmpeg conversion failed (%s); keeping wav" % exc)


if __name__ == "__main__":
    main()
