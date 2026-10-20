import datetime as dt
import unittest

from yearfilm.analyze import Moment
from yearfilm.music import Cue
from yearfilm.plan import ACTS, act_of, act_span, beats_per, build, in_point, narration_for, place_on_beats, runtime
from yearfilm.probe import Clip


def clip(date, dur=14.0, name=None):
    return Clip(name or f"{date}.mp4", dur, 1920, 1080, True, dt.date.fromisoformat(date))


def cue(tempo=120.0, n=200):
    beat = 60 / tempo
    return Cue("cue.mp3", n * beat, tempo, [i * beat for i in range(n)], 0)


class Acts(unittest.TestCase):
    def test_every_month_has_exactly_one_act(self):
        months = [m for _, ms in ACTS for m in ms]
        self.assertEqual(sorted(months), list(range(1, 13)))

    def test_act_of(self):
        self.assertEqual(ACTS[act_of(dt.date(2026, 1, 3))][0], "Winter")
        self.assertEqual(ACTS[act_of(dt.date(2026, 7, 4))][0], "Summer")
        self.assertEqual(ACTS[act_of(dt.date(2026, 12, 25))][0], "The Holidays")

    def test_span(self):
        self.assertEqual(act_span(1), "March – May")
        self.assertEqual(act_span(4), "December")


class Beats(unittest.TestCase):
    def test_beats_per_is_musical(self):
        self.assertEqual(beats_per(2.4, 120), 4)   # 4 x 0.5s = 2.0s
        self.assertEqual(beats_per(2.4, 60), 2)    # 2 x 1.0s = 2.0s
        self.assertEqual(beats_per(2.4, 180), 8)   # 8 x 0.33s = 2.67s

    def test_spans_follow_detected_beats_not_tempo(self):
        beats = [0.0, 0.5, 1.1, 1.5, 2.2, 2.5]
        self.assertEqual(place_on_beats(beats, 0, [2, 2]), [(0.0, 1.1), (1.1, 1.1)])

    def test_stops_when_music_runs_out(self):
        self.assertEqual(len(place_on_beats([0, 1, 2, 3], 0, [2, 2, 2])), 1)

    def test_starts_at_downbeat(self):
        self.assertEqual(place_on_beats([0, 1, 2, 3, 4], 2, [1])[0], (2, 1))


class Cuts(unittest.TestCase):
    def test_in_point_centres_and_clamps(self):
        c = clip("2026-01-01", dur=10)
        self.assertEqual(in_point(Moment(c, 4, 3, "shot", 1), 2), 4.5)
        self.assertEqual(in_point(Moment(c, 9, 3, "shot", 1), 2), 8.0)
        self.assertEqual(in_point(Moment(c, 0, 3, "shot", 1), 5), 0.0)

    def test_narration_is_sequential_within_act(self):
        notes = [("b.m4a", dt.date(2026, 4, 9), 5.0), ("a.m4a", dt.date(2026, 3, 2), 3.0),
                 ("x.m4a", dt.date(2026, 8, 1), 4.0)]
        out = narration_for(notes, act_of(dt.date(2026, 4, 1)))
        self.assertEqual([n["path"] for n in out], ["a.m4a", "b.m4a"])
        self.assertAlmostEqual(out[1]["at"], 0.5 + 3.0 + 0.6)


class Build(unittest.TestCase):
    def test_film_shape(self):
        found = []
        for d in ["2026-01-10", "2026-04-05", "2026-07-04", "2026-07-20", "2026-12-24"]:
            c = clip(d)
            found += [Moment(c, 1, 3, "shot", 0.5), Moment(c, 6, 3, "shot", 0.4)]
        found.append(Moment(clip("2026-07-04"), 2, 10, "scene", 0.9))
        t = build(found, [cue()], [], "The Testers", 2026, ["Ana"])
        labels = [s["label"] for s in t["segments"]]
        self.assertEqual(labels[0], "Cold open")
        self.assertEqual(labels[-1], "Credits")
        self.assertIn("Summer: Jul 4", labels)
        self.assertNotIn("Fall", labels)  # no footage, no chapter
        # The cold open ends on the title card.
        self.assertEqual(t["segments"][0]["items"][-1]["card"]["title"], "The Testers")
        # No shot appears twice.
        srcs = [(i["src"], i["in"]) for s in t["segments"] if s["kind"] == "montage" for i in s["items"] if "src" in i]
        self.assertEqual(len(srcs), len(set(srcs)))
        self.assertGreater(runtime(t), 0)

    def test_montage_durations_match_music(self):
        found = [Moment(clip(f"2026-0{m}-01"), 1, 3, "shot", 1) for m in range(1, 7)]
        t = build(found, [cue(tempo=97)], [], "F", 2026, [])
        for s in t["segments"]:
            if s["kind"] == "montage":
                self.assertAlmostEqual(sum(i["dur"] for i in s["items"]), s["music"]["duration"], places=2)


if __name__ == "__main__":
    unittest.main()
