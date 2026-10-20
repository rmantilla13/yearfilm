"""yearfilm: a year of family footage in, a film for the holidays out.

  python -m yearfilm make   INPUT -o film.mp4 --family "The Garcias" --cast "Ana,Leo"
  python -m yearfilm plan   INPUT -o timeline.json ...
  python -m yearfilm render timeline.json -o film.mp4

INPUT holds clips/ (video), notes/ (weekly voice notes) and music/ (score cues).
Dates come from the file's capture metadata, else a YYYY-MM-DD in its name.
"""
import argparse
import json
import sys
from pathlib import Path

from . import analyze, music, plan, probe, render


def make_plan(args) -> dict:
    root = Path(args.input)
    clip_paths = probe.files(root / "clips", probe.VIDEO_EXT)
    if not clip_paths:
        sys.exit(f"no video in {root / 'clips'}")
    print(f"analysing {len(clip_paths)} clips")
    clips = [probe.probe_clip(p) for p in clip_paths]
    series = [analyze.measure(c) for c in clips]
    found = analyze.moments(series)
    print(f"  {sum(m.kind == 'shot' for m in found)} shots, {sum(m.kind == 'scene' for m in found)} scenes")

    cue_paths = probe.files(root / "music", probe.AUDIO_EXT)
    print(f"analysing {len(cue_paths)} music cues")
    cues = [music.analyze_cue(str(p)) for p in cue_paths]
    for c in cues:
        print(f"  {Path(c.path).name}: {c.tempo:.0f} bpm, {len(c.beats)} beats")

    notes = [(str(p), probe.note_date(p), probe.duration(p)) for p in probe.files(root / "notes", probe.AUDIO_EXT)]
    year = args.year or max(c.date for c in clips).year
    cast = [n.strip() for n in args.cast.split(",") if n.strip()] if args.cast else []
    timeline = plan.build(found, cues, notes, args.family, year, cast)
    print(f"planned {len(timeline['segments'])} segments, {plan.runtime(timeline) / 60:.1f} min")
    return timeline


def main(argv=None) -> None:
    ap = argparse.ArgumentParser(prog="yearfilm", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("make", "plan"):
        p = sub.add_parser(name)
        p.add_argument("input")
        p.add_argument("-o", "--out", required=True)
        p.add_argument("--family", default="Our Family")
        p.add_argument("--year", type=int)
        p.add_argument("--cast", help="comma-separated names for the credits")
        p.add_argument("--keep", action="store_true", help="keep rendered segments")
    r = sub.add_parser("render")
    r.add_argument("timeline")
    r.add_argument("-o", "--out", required=True)
    r.add_argument("--keep", action="store_true")
    args = ap.parse_args(argv)

    if args.cmd == "render":
        timeline = json.loads(Path(args.timeline).read_text())
    else:
        timeline = make_plan(args)
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        if args.cmd == "plan":
            Path(args.out).write_text(json.dumps(timeline, indent=2, ensure_ascii=False))
            print(f"wrote {args.out}")
            return
        Path(args.out).with_suffix(".timeline.json").write_text(json.dumps(timeline, indent=2, ensure_ascii=False))
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    print("rendering")
    render.render(timeline, args.out, keep=args.keep)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
