"""Where the beats are in a piece of music, so cuts can land on them."""
from dataclasses import dataclass

import numpy as np


@dataclass
class Cue:
    path: str
    duration: float
    tempo: float
    beats: list       # seconds
    downbeat: int     # index into beats of the first bar line


def analyze_cue(path: str) -> Cue:
    import librosa  # slow to import; only needed here

    y, sr = librosa.load(path, sr=22050, mono=True)
    onset = librosa.onset.onset_strength(y=y, sr=sr)
    tempo, frames = librosa.beat.beat_track(onset_envelope=onset, sr=sr)
    beats = librosa.frames_to_time(frames, sr=sr).tolist()
    # Bars are four beats; the phase whose beats hit hardest is where bars start.
    strength = onset[frames] if len(frames) else np.zeros(0)
    phases = [strength[p::4].sum() for p in range(min(4, len(strength)))]
    downbeat = int(np.argmax(phases)) if phases else 0
    return Cue(path, len(y) / sr, float(np.atleast_1d(tempo)[0]), beats, downbeat)
