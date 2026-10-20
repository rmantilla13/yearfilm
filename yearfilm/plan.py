"""Turn a year of moments into a timeline: the film as data, before any pixel is rendered.

The timeline is the edit. Rendering only follows it, so swapping a clip or a song
is an edit to this JSON and a re-render, never a re-analysis.

Shape of the film:
  cold open   - the year's best shots cut to music, ending on the main title
  per act     - a chapter card and a montage (with that season's voice notes over it),
                then the season's scenes with their own sound
  credits     - starring, filmed by, music
"""
import datetime as dt
from pathlib import Path

from .analyze import Moment
from .music import Cue

ACTS = [
    ("Winter", (1, 2)),
    ("Spring", (3, 4, 5)),
    ("Summer", (6, 7, 8)),
    ("Fall", (9, 10, 11)),
    ("The Holidays", (12,)),
]
MONTH = ["", "January", "February", "March", "April", "May", "June", "July",
         "August", "September", "October", "November", "December"]


def act_of(date: dt.date) -> int:
    return next(i for i, (_, months) in enumerate(ACTS) if date.month in months)


def act_span(i: int) -> str:
    months = ACTS[i][1]
    return MONTH[months[0]] if len(months) == 1 else f"{MONTH[months[0]]} – {MONTH[months[-1]]}"


def beats_per(seconds: float, tempo: float, choices=(1, 2, 4, 8)) -> int:
    """How many beats make a span close to `seconds` - always a musical count."""
    beat = 60.0 / max(tempo, 1.0)
    return min(choices, key=lambda k: abs(k * beat - seconds))


def place_on_beats(beats: list, first: int, lengths: list) -> list:
    """Lay spans of `lengths` beats end to end from beat `first`.

    Returns (start, duration) per span, in cue time, for as many spans as the
    music has beats for. Durations come from the detected beats, not from the
    tempo, so a drifting live recording still cuts on its own beat.
    """
    out, i = [], first
    for k in lengths:
        if i + k >= len(beats):
            break
        out.append((beats[i], beats[i + k] - beats[i]))
        i += k
    return out


def in_point(m: Moment, dur: float) -> float:
    """Centre the cut on the moment, without running off either end of the clip."""
    start = m.start + (m.dur - dur) / 2
    return round(max(0.0, min(start, m.clip.duration - dur)), 3)


def montage(label: str, cue: Cue, specs: list, narration=()) -> dict:
    """specs: ('card', title, subtitle, seconds) or ('shot', Moment)."""
    shot_beats = beats_per(2.4, cue.tempo)
    lengths = [beats_per(s[3], cue.tempo, (4, 8, 16)) if s[0] == "card" else shot_beats for s in specs]
    slots = place_on_beats(cue.beats, cue.downbeat, lengths)
    items = []
    for spec, (_, dur) in zip(specs, slots):
        dur = round(dur, 3)
        if spec[0] == "card":
            items.append({"card": {"title": spec[1], "subtitle": spec[2]}, "dur": dur})
        else:
            m = spec[1]
            items.append({"src": m.clip.path, "in": in_point(m, dur), "dur": dur})
    total = round(sum(it["dur"] for it in items), 3)
    return {
        "kind": "montage",
        "label": label,
        "music": {"path": cue.path, "start": round(slots[0][0], 3) if slots else 0.0, "duration": total},
        "narration": list(narration),
        "items": items,
    }


def scene(label: str, m: Moment) -> dict:
    return {"kind": "scene", "label": label, "src": m.clip.path, "in": round(m.start, 3),
            "dur": round(m.dur, 3), "has_audio": m.clip.has_audio}


def narration_for(notes: list, act: int, gap: float = 0.6) -> list:
    """Voice notes recorded in this act, read one after another from the chapter card."""
    out, at = [], 0.5
    for path, date, dur in sorted(notes, key=lambda n: n[1]):
        if act_of(date) == act:
            out.append({"path": path, "at": round(at, 3)})
            at += dur + gap
    return out


def build(found: list, cues: list, notes: list, family: str, year: int, cast: list,
          shots_per_act: int = 8, scenes_per_act: int = 2, cold_open_shots: int = 6) -> dict:
    if not cues:
        raise SystemExit("no music: put at least one track in music/")
    shots = [m for m in found if m.kind == "shot"]
    scenes = [m for m in found if m.kind == "scene"]
    chrono = lambda ms: sorted(ms, key=lambda m: (m.clip.date, m.clip.path, m.start))
    cue = iter(cues * 8).__next__
    segments, used = [], set()

    # Cold open: the year's best, one per clip so it reads as the whole year.
    best, seen = [], set()
    for m in sorted(shots, key=lambda m: -m.score):
        if m.clip.path not in seen:
            best.append(m)
            seen.add(m.clip.path)
        if len(best) == cold_open_shots:
            break
    used.update(id(m) for m in best)
    segments.append(montage("Cold open", cue(),
                            [("shot", m) for m in chrono(best)] + [("card", family, str(year), 4.0)]))

    for a, (name, _) in enumerate(ACTS):
        act_shots = [m for m in shots if act_of(m.clip.date) == a and id(m) not in used]
        act_scenes = [m for m in scenes if act_of(m.clip.date) == a]
        if not act_shots and not act_scenes:
            continue
        picked = chrono(sorted(act_shots, key=lambda m: -m.score)[:shots_per_act])
        segments.append(montage(name, cue(),
                                [("card", name, act_span(a), 3.2)] + [("shot", m) for m in picked],
                                narration_for(notes, a)))
        for m in chrono(sorted(act_scenes, key=lambda m: -m.score)[:scenes_per_act]):
            segments.append(scene(f"{name}: {m.clip.date:%b %-d}", m))

    credits = []
    if cast:
        credits.append(("card", "Starring", "\n".join(cast), 6.0))
    credits.append(("card", "Filmed by", family, 4.0))
    credits.append(("card", "Music", "\n".join(sorted({Path(c.path).stem for c in cues})), 4.0))
    segments.append(montage("Credits", cue(), credits))

    return {"title": f"{family} — {year}", "fps": 30, "size": [1920, 1080], "segments": segments}


def runtime(timeline: dict) -> float:
    return sum(s["music"]["duration"] if s["kind"] == "montage" else s["dur"] for s in timeline["segments"])
