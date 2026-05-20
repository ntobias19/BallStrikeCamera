import unittest

from Backend.geometry_pipeline.pipeline import (
    Coordinate,
    HoleGeometry,
    ScorecardHole,
    build_overpass_query,
    scorecard_tolerance_yards,
    validate_course_geometry,
    validate_hole_yardage,
)


class GeometryValidationTests(unittest.TestCase):
    def test_scorecard_tolerance_has_minimum_and_percent(self):
        self.assertEqual(scorecard_tolerance_yards(250), 25)
        self.assertEqual(scorecard_tolerance_yards(500), 40)

    def test_hole_yardage_accepts_close_geometry(self):
        tee = Coordinate(40.0, -80.0)
        # Roughly 110 yards north.
        green = Coordinate(40.000905, -80.0)
        hole = HoleGeometry(number=1, par=3, tee=tee, green_center=green)
        self.assertIsNone(validate_hole_yardage(hole, ScorecardHole(1, 3, 110)))

    def test_hole_yardage_rejects_bad_geometry(self):
        tee = Coordinate(40.0, -80.0)
        green = Coordinate(40.0036, -80.0)
        hole = HoleGeometry(number=1, par=3, tee=tee, green_center=green)
        error = validate_hole_yardage(hole, ScorecardHole(1, 3, 110))
        self.assertIsNotNone(error)
        self.assertIn("exceeds tolerance", error)

    def test_course_acceptance_requires_enough_matching_holes(self):
        holes = []
        scorecard = []
        for number in range(1, 10):
            tee = Coordinate(40.0 + number * 0.001, -80.0)
            green = Coordinate(tee.latitude + 0.002, -80.0)
            holes.append(HoleGeometry(number=number, par=4, tee=tee, green_center=green))
            scorecard.append(ScorecardHole(number, 4, 243))
        result = validate_course_geometry(holes, scorecard, minimum_holes=9)
        self.assertTrue(result.accepted)
        self.assertEqual(result.errors, [])

    def test_overpass_query_includes_relations_pins_and_boundary(self):
        query = build_overpass_query(40.0, -80.0)
        self.assertIn('node["golf"="pin"]', query)
        self.assertIn('relation["golf"="green"]', query)
        self.assertIn('relation["leisure"="golf_course"]', query)


if __name__ == "__main__":
    unittest.main()
