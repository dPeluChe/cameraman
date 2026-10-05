#!/usr/bin/env python3
"""Builds a reference recording for checking transcription: known sentences read by the macOS
`say` voice, separated by silences of known length. Writes reference.wav (16 kHz mono) and
truth.json (where each sentence starts and ends), so word error rate and timing error can be
measured against ground truth. See docs/RESEARCH/TRANSCRIPT_VALIDATION.md.

Limit: a synthetic voice reads "um" and "uh" as clean words, not as natural hesitations, so this
cannot validate filler-word detection. Use real speech for that.
"""
import json, subprocess, wave

PHRASES = [
    "So this is the um new onboarding flow we shipped last week.",
    "Wait, let me start that part again.",
    "Up top you can see revenue, and uh here's where you invite your team.",
    "Every project, er, shows its status right in the table.",
    "Click export and choose the folder where the file should be saved.",
    "That is basically all you need to know, thanks for watching.",
]
GAPS = [0.8, 2.5, 0.6, 3.0, 1.2]  # silence after each phrase except the last, in seconds
RATE = 16000

out = wave.open("reference.wav", "wb")
out.setnchannels(1); out.setsampwidth(2); out.setframerate(RATE)
truth, t = [], 0.0
for i, phrase in enumerate(PHRASES):
    subprocess.run(["say", "-v", "Samantha", "-r", "170", "-o", f"p{i}.aiff", phrase], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@16000", "-c", "1", f"p{i}.aiff", f"p{i}.wav"], check=True)
    w = wave.open(f"p{i}.wav", "rb")
    frames, duration = w.readframes(w.getnframes()), w.getnframes() / w.getframerate()
    w.close()
    out.writeframes(frames)
    truth.append({"text": phrase, "start": round(t, 3), "end": round(t + duration, 3)})
    t += duration
    if i < len(GAPS):
        out.writeframes(b"\x00\x00" * int(GAPS[i] * RATE))
        t += GAPS[i]
out.close()
json.dump({"phrases": truth, "total": round(t, 3), "gaps": GAPS}, open("truth.json", "w"), indent=1)
print(f"reference.wav {t:.1f}s, truth.json written")
