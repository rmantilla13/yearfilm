# yearfilm

A year of family footage in, a film for the holidays out. [yearfilm.com](https://yearfilm.com)

| Directory | What it is |
|---|---|
| `engine/` | The editing engine (Python + ffmpeg): footage, voice notes and music in, a film out |
| `app/`, `lib/` | yearfilm.com: landing page, waitlist, privacy policy and support pages (Next.js on Vercel) |
| `ios/` | The iPhone app (SwiftUI): weekly capture, voice notes, the year at a glance |
| `docs/` | Data model and [App Store compliance](docs/app-store-compliance.md) |

**Web:** `npm install && npm run dev` at the repo root. Vercel builds it with default
settings (Framework Preset: Next.js, Root Directory empty). The waitlist needs
`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`, plus the table in `supabase/waitlist.sql`.
Without them, the form says the waitlist isn't open yet instead of losing the signup.

**iOS:** `brew install xcodegen && cd ios && xcodegen generate && open Yearfilm.xcodeproj`.
Needs Xcode 26 (App Store Connect requires the iOS 26 SDK). Set `DEVELOPMENT_TEAM` in
`ios/project.yml` to sign. CI builds and tests it on every change under `ios/`.

## The engine

Everything below runs from `engine/`.

This is the prototype that tests the core question: can a folder of everyday
clips, voice notes and a few pieces of music become something that plays like
a film on the TV? It has no app, no accounts and no upload flow yet; it is the
editing engine those will feed.

## What it makes

```
Cold open      the year's best shots, cut on the beat, landing on the title card
Winter         chapter card + montage, that season's voice notes over it (music ducks)
  Feb 14       a scene: someone talking, played with its own sound
Spring ...
The Holidays
Credits        Starring · Filmed by · Music
```

- **Cuts land on beats.** Every shot is a whole number of beats long (about 2.4s,
  rounded to 1/2/4/8 beats). Durations come from the detected beat times, not the
  tempo, so a live recording that drifts is still cut on its own beat.
- **Montages and scenes alternate.** Shots are scored on sharpness, motion and
  exposure; scenes are found where someone is talking, and keep their sound.
- **Voice notes are the narration.** Each season's notes play over its chapter,
  and the music ducks under them (sidechain compression).
- **Built for a TV.** Output is 1920x1080, 30 fps. Portrait phone video sits over
  a blurred fill of itself instead of black bars. One loudness pass over the
  whole film keeps the volume steady.
- **The edit is data.** `plan` writes `timeline.json`; `render` follows it. To
  swap a clip or a song, edit the JSON and re-render.

## Run it

Needs `ffmpeg` (with libfreetype) and Python 3.10+.

```bash
python -m venv .venv && .venv/bin/pip install -r requirements.txt

# No footage yet? Synthesise a stand-in year (test patterns, noise "voices", click-track music).
./scripts/make_sample.sh sample

.venv/bin/python -m yearfilm make sample -o out/film.mp4 --family "The Garcias" --cast "Ana,Leo,Mia"
```

The input folder:

```
INPUT/
  clips/   video (.mp4 .mov ...). Date from capture metadata, else YYYY-MM-DD in the name
  notes/   weekly voice notes (.m4a .mp3 ...), dated the same way
  music/   score cues (.mp3 .wav ...); used in turn for cold open, each act, credits
```

Plan and render separately to edit in between:

```bash
.venv/bin/python -m yearfilm plan   sample -o timeline.json --family "The Garcias"
.venv/bin/python -m yearfilm render timeline.json -o out/film.mp4
```

Tests: `.venv/bin/python -m unittest discover -s tests -t .`

## Layout

```
yearfilm/probe.py    what a file is: length, shape, sound, the day it was filmed
yearfilm/analyze.py  moments worth keeping: shots (look good) and scenes (someone talking)
yearfilm/music.py    beats and the first bar line of each cue (librosa)
yearfilm/plan.py     moments + cues + notes → timeline. Pure; tested.
yearfilm/render.py   timeline → film, with ffmpeg
schema/schema.sql    the data model for the real app
docs/data-model.md   why it is shaped that way
```

## Known gaps (next steps, roughly in order)

1. **HDR iPhone footage** looks washed out. Proxy it to SDR first
   (`zscale=t=linear,tonemap=hable,zscale=p=bt709:t=bt709:m=bt709`).
2. **Better moment finding.** Replace the speech-band heuristic with real voice and
   laughter detection, add CLIP embeddings so montages don't repeat the same
   kind of shot, and use face clusters for the "Starring" credits.
3. **Transcribe voice notes** (Whisper) and let an LLM write chapter subtitles.
4. **Music from a licensed source.** Epidemic Sound's API or ElevenLabs Music,
   with per-act cues generated to length. Two consecutive acts currently reuse a
   cue when there are fewer cues than segments.
5. **Two-pass loudnorm** for an exact -16 LUFS (single pass lands within ~2 LU).
6. **Runtime budget.** Fit the plan to a target length (`--minutes 30`) instead
   of fixed shots and scenes per act.
7. **Crossfades** between scene and montage audio; today every join is a hard
   cut with short fades.
