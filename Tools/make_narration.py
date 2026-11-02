#!/usr/bin/env python3
# Author: MUI group 3
"""
Generates the narration audio for every line in Story/Script.swift with a neural voice
(Kokoro, Apache-2.0, runs offline) and writes <line id>.m4a into the app's Narration folder.
Re-run after changing the script text. Recorded files with the same name can replace any line.

    pip install kokoro-onnx soundfile numpy      (+ ffmpeg on the PATH)
    python3 Tools/make_narration.py               # all lines, default voice
    python3 Tools/make_narration.py --voice bm_george --speed 0.92
    python3 Tools/make_narration.py --samples     # one line in several voices → Tools/voice_samples/

The model files (~350 MB) are downloaded once into Tools/.tts_model/.
"""
import argparse, os, re, subprocess, sys, tempfile, urllib.request
import numpy as np
import soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "..", "MUI_Lightning_Group_3")
SCRIPT = os.path.join(APP, "Story", "Script.swift")
OUT = os.path.join(APP, "Narration")
MODEL_DIR = os.path.join(HERE, ".tts_model")
BASE_URL = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/"
FILES = ["kokoro-v1.0.onnx", "voices-v1.0.bin"]
SAMPLE_VOICES = ["af_heart", "af_bella", "bf_emma", "bf_isabella", "am_michael", "bm_george", "bm_fable"]

ap = argparse.ArgumentParser()
ap.add_argument("--voice", default="af_heart")
ap.add_argument("--speed", type=float, default=0.95)
ap.add_argument("--samples", action="store_true")
args = ap.parse_args()

os.makedirs(MODEL_DIR, exist_ok=True)
for f in FILES:
    path = os.path.join(MODEL_DIR, f)
    if not os.path.exists(path):
        print("downloading", f, "…")
        urllib.request.urlretrieve(BASE_URL + f, path)

from kokoro_onnx import Kokoro
kokoro = Kokoro(os.path.join(MODEL_DIR, FILES[0]), os.path.join(MODEL_DIR, FILES[1]))

source = open(SCRIPT, encoding="utf-8").read()
pattern = re.compile(r'(?:\.init|NarrationLine)\(\s*"(\w+)",\s*"((?:[^"\\]|\\.)*)"\s*\)', re.S)
lines = [(m.group(1), m.group(2).replace('\\"', '"')) for m in pattern.finditer(source)]
if not lines:
    sys.exit("no narration lines found in Script.swift")

def speak(text, voice, path):
    samples, rate = kokoro.create(text, voice=voice, speed=args.speed, lang="en-gb" if voice.startswith("b") else "en-us")
    pad = lambda s: np.zeros(int(rate * s), dtype=np.float32)
    audio = np.concatenate([pad(0.15), samples.astype(np.float32), pad(0.25)])
    audio *= 0.89 / max(1e-6, float(np.abs(audio).max()))          # consistent level
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        sf.write(tmp.name, audio, rate)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "aac", "-b:a", "96k",
                    "-metadata", "artist=MUI group 3", path], check=True)
    os.remove(tmp.name)
    return len(audio) / rate

if args.samples:
    folder = os.path.join(HERE, "voice_samples")
    os.makedirs(folder, exist_ok=True)
    text = dict(lines).get("intro_01_welcome", lines[0][1])
    for v in SAMPLE_VOICES:
        speak(text, v, os.path.join(folder, f"{v}.m4a"))
        print("sample", v)
    sys.exit()

os.makedirs(OUT, exist_ok=True)
total = 0
for line_id, text in lines:
    seconds = speak(text, args.voice, os.path.join(OUT, f"{line_id}.m4a"))
    total += seconds
    print(f"{line_id:22s} {seconds:5.1f} s")
print(f"{len(lines)} lines, {total / 60:.1f} min, voice {args.voice} → {os.path.abspath(OUT)}")
