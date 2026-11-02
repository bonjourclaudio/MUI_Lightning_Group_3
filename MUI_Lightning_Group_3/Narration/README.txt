Author: MUI group 3

Narration audio, one file per line, named after the line id in Story/Script.swift.

The current files are generated with a neural voice (Kokoro "af_heart") by
Tools/make_narration.py. After changing a line's text in Script.swift, run it again:

    python3 Tools/make_narration.py                    # default voice
    python3 Tools/make_narration.py --voice bm_george  # another voice (samples in Tools/voice_samples)

You can also replace any single file with a recording of your own (.m4a, .mp3, .wav or .caf,
same name). Missing files are fine: that step then uses its fallback duration.
