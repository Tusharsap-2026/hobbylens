import os
import tempfile
import unittest

import bakeoff as b


class Names(unittest.TestCase):
    def test_species_ignores_author_and_hybrid_signs(self):
        self.assertEqual(b.species_key("Epipremnum aureum (Linden & André) G.S.Bunting"), "epipremnum aureum")
        self.assertEqual(b.species_key("Rosa × hybrida"), "rosa hybrida")
        self.assertEqual(b.species_key("Aglaonema 'Red Siam'"), "aglaonema")
        self.assertEqual(b.genus_key("Phalaenopsis amabilis"), "phalaenopsis")

    def test_bangla_detection(self):
        self.assertTrue(b.has_bangla("তুলসী"))
        self.assertFalse(b.has_bangla("Holy basil"))


class Scoring(unittest.TestCase):
    def photo(self, group="g"):
        return b.Photo("x.jpg", "plant", ["Epipremnum aureum", "Scindapsus aureus"], group)

    def test_hits_at_each_level(self):
        r = b.Row("e", self.photo(), ["Philodendron hederaceum", "Scindapsus aureus", "x"], 1.0, False, None)
        self.assertFalse(r.hit(1, "species"))
        self.assertTrue(r.hit(3, "species"), "a synonym in the top 3 counts")
        genus_only = b.Row("e", self.photo(), ["Epipremnum pinnatum"], 1.0, False, None)
        self.assertFalse(genus_only.hit(3, "species"))
        self.assertTrue(genus_only.hit(1, "genus"))

    def test_wilson_interval_width_at_50_and_300_photos(self):
        lo50, hi50 = b.wilson(43, 50)
        lo300, hi300 = b.wilson(255, 300)
        self.assertGreater(hi50 - lo50, 0.17, "50 photos give roughly +/-10 points")
        self.assertLess(hi300 - lo300, 0.09, "300 photos give roughly +/-4 points")

    def test_decision_picks_cheapest_passing_engine(self):
        summary = [
            {"engine": "a", "passes": True, "usd_per_call": 0.05, "top3_species": 0.95},
            {"engine": "b", "passes": True, "usd_per_call": 0.005, "top3_species": 0.86},
            {"engine": "c", "passes": False, "usd_per_call": 0.0, "top3_species": 0.70},
        ]
        self.assertEqual(b.decide(summary)["engine"], "b")
        self.assertIsNone(b.decide([summary[2]]))

    def test_slow_engine_fails_even_if_accurate(self):
        photos = [self.photo() for _ in range(10)]
        rows = [b.Row("slow", p, ["Epipremnum aureum"], 5.0, False, None) for p in photos]
        s = b.summarise(rows, {"slow": 0.0})[0]
        self.assertEqual(s["top3_species"], 1.0)
        self.assertFalse(s["passes"])

    def test_errors_count_as_misses_and_are_recorded(self):
        def boom(jpeg, kind):
            raise RuntimeError("HTTP 500")
        rows = b.run([self.photo()], lambda p: b"x", {"bad": boom})
        self.assertEqual(rows[0].error, "RuntimeError: HTTP 500")
        self.assertFalse(rows[0].hit(3, "species"))

    def test_plant_engines_skip_animal_photos(self):
        cat = b.Photo("c.jpg", "cat", ["Persian"], "cats")
        rows = b.run([cat], lambda p: b"x", {"plantid": lambda j, k: b.EngineAnswer(["x"]), "gemini": lambda j, k: b.EngineAnswer(["Persian"])})
        self.assertEqual([r.engine for r in rows], ["gemini"])

    def test_outputs_are_written(self):
        rows = [b.Row("e", self.photo("orchid"), ["Epipremnum aureum"], 1.2, True, None)]
        summary = b.summarise(rows, {"e": 0.01})
        with tempfile.TemporaryDirectory() as d:
            b.write_outputs(rows, summary, b.decide(summary), d)
            self.assertTrue(os.path.exists(os.path.join(d, "report.md")))
            with open(os.path.join(d, "per_photo.csv"), encoding="utf-8") as f:
                self.assertIn("Epipremnum aureum", f.read())

    def test_demo_runs_offline(self):
        self.assertEqual(b.demo(), 0)


if __name__ == "__main__":
    unittest.main()
