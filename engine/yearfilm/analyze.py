"""Find the moments worth keeping in a clip.

Two kinds, because the film alternates two kinds of sequence:
  shot  - a few seconds that look good: sharp, moving, well exposed. Cut to music.
  scene - a stretch where someone is talking or laughing. Played with its own sound.
"""
import subprocess
from dataclasses import dataclass

import numpy as np

from .probe import Clip

RATE = 4  # analysis samples per second
SHOT_LEN = 3.0
SCENE_MIN = 6.0
SCENE_MAX = 30.0
VOICE_DB = -38.0  # speech-band level that counts as "someone is talking"


@dataclass
class Moment:
    clip: Clip
    start: float
    dur: float
    kind: str  # 'shot' | 'scene'
    score: float


@dataclass
class Series:
    clip: Clip
    sharp: np.ndarray
    motion: np.ndarray
    bright: np.ndarray
    voice_db: np.ndarray


def _frames(path: str) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vf", f"fps={RATE},scale=64:36,format=gray", "-f", "rawvideo", "-"],
        capture_output=True, check=True,
    ).stdout
    return np.frombuffer(raw, np.uint8).reshape(-1, 36, 64).astype(np.float32)


def _voice_db(path: str, n: int) -> np.ndarray:
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar", "16000", "-f", "s16le", "-"],
        capture_output=True, check=True,
    ).stdout
    y = np.frombuffer(raw, np.int16).astype(np.float32) / 32768
    hop = 16000 // RATE
    freqs = np.fft.rfftfreq(hop, 1 / 16000)
    band = (freqs >= 300) & (freqs <= 3400)
    out = np.full(n, -90.0)
    for i in range(min(n, len(y) // hop)):
        spec = np.abs(np.fft.rfft(y[i * hop:(i + 1) * hop])) / hop
        out[i] = 20 * np.log10(np.sqrt((spec[band] ** 2).sum()) + 1e-9)
    return out


def measure(clip: Clip) -> Series:
    f = _frames(clip.path)
    lap = 4 * f[:, 1:-1, 1:-1] - f[:, :-2, 1:-1] - f[:, 2:, 1:-1] - f[:, 1:-1, :-2] - f[:, 1:-1, 2:]
    sharp = np.log1p(lap.var(axis=(1, 2)))
    motion = np.concatenate([[0.0], np.abs(np.diff(f, axis=0)).mean(axis=(1, 2))])
    bright = f.mean(axis=(1, 2)) / 255
    voice = _voice_db(clip.path, len(f)) if clip.has_audio else np.full(len(f), -90.0)
    return Series(clip, sharp, motion, bright, voice)


def _pct(values: np.ndarray, pool: np.ndarray) -> np.ndarray:
    """Rank against every clip of the year, so 'sharp' means sharp for this family's phone."""
    return np.searchsorted(np.sort(pool), values) / max(len(pool), 1)


def _runs(mask: np.ndarray):
    start = None
    for i, on in enumerate(np.append(mask, False)):
        if on and start is None:
            start = i
        elif not on and start is not None:
            yield start, i
            start = None


def _close_gaps(mask: np.ndarray, gap: int) -> np.ndarray:
    """Pauses between sentences are still the same conversation."""
    out = mask.copy()
    last = None
    for i, on in enumerate(mask):
        if on:
            if last is not None and 0 < i - last - 1 <= gap:
                out[last:i] = True
            last = i
    return out


def moments(all_series: list) -> list:
    sharp_pool = np.concatenate([s.sharp for s in all_series])
    motion_pool = np.concatenate([s.motion for s in all_series])
    found = []
    for s in all_series:
        clip, n = s.clip, len(s.sharp)
        sharp = _pct(s.sharp, sharp_pool)
        motion = _pct(s.motion, motion_pool)
        exposure = np.clip(0.12 - s.bright, 0, None) + np.clip(s.bright - 0.9, 0, None)
        shake = np.clip(motion - 0.97, 0, None)
        frame_score = sharp + 0.5 * motion - 4 * exposure - 6 * shake

        # Shots: best non-overlapping windows, two per clip at most.
        w = int(SHOT_LEN * RATE)
        edge = RATE // 2
        if n >= w + 2 * edge:
            windows = [(frame_score[i:i + w].mean(), i) for i in range(edge, n - w - edge + 1, RATE)]
            taken = []
            for score, i in sorted(windows, reverse=True):
                if all(abs(i - j) >= w for j in taken):
                    taken.append(i)
                    found.append(Moment(clip, i / RATE, SHOT_LEN, "shot", float(score)))
                if len(taken) == 2:
                    break
        elif n:
            found.append(Moment(clip, 0.0, clip.duration, "shot", float(frame_score.mean()) - 0.5))

        # Scenes: the longest well-lit stretch of talking.
        talking = _close_gaps(s.voice_db > VOICE_DB, int(1.5 * RATE))
        best = None
        for a, b in _runs(talking):
            start = max(0.0, a / RATE - 1.0)
            end = min(clip.duration, b / RATE + 1.0, start + SCENE_MAX)
            if end - start < SCENE_MIN:
                continue
            seg = slice(a, b)
            score = talking[seg].mean() * min(end - start, 20) / 20 + 0.3 * sharp[seg].mean() - 4 * exposure[seg].mean()
            if best is None or score > best.score:
                best = Moment(clip, start, end - start, "scene", float(score))
        if best:
            found.append(best)
    return found
