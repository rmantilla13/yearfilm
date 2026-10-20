# Data model

> **Superseded for storage (2026-10-20):** footage and voice notes now stay on the phone and
> sync through the user's own iCloud — see [storage-plan.md](storage-plan.md). The server
> tables and storage layout below describe the earlier design and aren't deployed.

```
family ─┬─ family_members   (logins: producer / contributor / viewer)
        ├─ cast_members     (people on screen; credits; face consent)
        ├─ footage ── moments ── appearances ── cast_members
        ├─ voice_notes
        ├─ music_tracks
        └─ films (one per year) ── film_cuts (versioned timelines)
```

Schema: [`schema/schema.sql`](../schema/schema.sql).

## The ideas that shape it

**The year is the product.** `films` is unique on `(family_id, year)`. Status moves
`filming → post_production → locked → premiered`; premiere night plays the cut
with `locked_at` set.

**Acts and weeks are derived, never stored.** A season is a function of
`captured_on` (`plan.act_of`). Storing it means a second fact that can disagree
with the date the day someone corrects a date.

**`captured_on` is a calendar date, not a timestamp.** A clip filmed at 11pm on
Dec 31 in Los Angeles is a 2026 clip, even though in UTC it's 2027. Read the
phone's local creation date (`com.apple.quicktime.creationdate`) and keep only the day.

**Moments are derived and disposable.** They're analysis output. Improving the
analyser means deleting and recomputing them. The two human decisions about a
moment, `pinned` and `hidden`, are the only parts that matter if it's
regenerated, so a real version should key them by `(footage_id, start_s)`
rather than by moment id.

**The edit is a versioned timeline.** `film_cuts.timeline` is exactly the JSON
the renderer follows (see `yearfilm/plan.py`). The planner writes version 1; a
producer swapping a clip or a song writes version 2. Rendering is a pure function
of a timeline, so any version can be re-rendered and nothing needs re-analysing.
Trailers and weekly "dailies" are the same table with a different `kind`.

**Logins are not cast.** `family_members` is who can sign in. `cast_members` is
who appears in the film and in the credits. A newborn is cast but has no login;
an uncle who uploads may never appear.

**Face matching is opt-in per person.** `cast_members.face_consent_at` is null
until someone consents. Without it, appearances are tagged by hand or not at all.
This matters legally: grouping faces creates biometric data, and Illinois' BIPA
requires explicit consent for it.

**Licence travels with the track.** The film is watched privately; the trailer
is shared in group chats. A track can be cleared for one and not the other, so
the renderer for the trailer must check `music_tracks.licence`.

## Storage layout

```
{family}/{year}/original/{footage_id}.{ext}   originals, cold storage after proxying
{family}/{year}/proxy/{footage_id}.mp4         1080p SDR CFR — what everything reads
{family}/{year}/notes/{voice_note_id}.m4a
{family}/{year}/renders/{cut_id}.mp4           + HLS ladder for TV playback
```
