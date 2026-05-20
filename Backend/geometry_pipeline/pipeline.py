#!/usr/bin/env python3
"""Automatic golf-course geometry backfill worker.

This module intentionally uses only public/owned data sources. It does not read from
Apple/Google map display tiles. Optional OpenCV dependencies are used only when the
worker is configured to fetch legal imagery such as NAIP.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile
import urllib.parse
import urllib.request
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

EARTH_RADIUS_M = 6_371_000.0
YARDS_PER_METER = 1.0936132983
DEFAULT_OVERPASS_URL = "https://overpass-api.de/api/interpreter"
DEFAULT_NAIP_URL = (
    "https://gis.apfo.usda.gov/arcgis/rest/services/NAIP/"
    "USDA_CONUS_PRIME/ImageServer/exportImage"
)


@dataclass(frozen=True)
class Coordinate:
    latitude: float
    longitude: float

    def to_json(self) -> dict[str, float]:
        return {"latitude": self.latitude, "longitude": self.longitude}


@dataclass
class ScorecardHole:
    number: int
    par: int
    yardage: int
    handicap: int | None = None


@dataclass
class HoleGeometry:
    number: int
    par: int
    tee: Coordinate | None = None
    green_center: Coordinate | None = None
    green_front: Coordinate | None = None
    green_back: Coordinate | None = None
    green_polygon: list[Coordinate] = field(default_factory=list)
    fairway_polygon: list[Coordinate] = field(default_factory=list)
    bunker_polygons: list[list[Coordinate]] = field(default_factory=list)
    water_polygons: list[list[Coordinate]] = field(default_factory=list)
    path: list[Coordinate] = field(default_factory=list)

    def measured_yards(self) -> int | None:
        if not self.tee or not self.green_center:
            return None
        return round(yards_between(self.tee, self.green_center))


@dataclass
class CourseJob:
    course_id: str
    name: str
    city: str = ""
    state: str = ""
    country: str = "US"
    latitude: float | None = None
    longitude: float | None = None


@dataclass
class ValidationResult:
    accepted: bool
    confidence: float
    errors: list[str] = field(default_factory=list)


def yards_between(a: Coordinate, b: Coordinate) -> float:
    lat1 = math.radians(a.latitude)
    lat2 = math.radians(b.latitude)
    dlat = lat2 - lat1
    dlon = math.radians(b.longitude - a.longitude)
    h = (
        math.sin(dlat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    )
    return EARTH_RADIUS_M * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h)) * YARDS_PER_METER


def scorecard_tolerance_yards(scorecard_yards: int) -> float:
    return max(25.0, scorecard_yards * 0.08)


def validate_hole_yardage(hole: HoleGeometry, scorecard: ScorecardHole) -> str | None:
    measured = hole.measured_yards()
    if measured is None:
        return f"hole {scorecard.number}: missing tee or green center"
    tolerance = scorecard_tolerance_yards(scorecard.yardage)
    delta = abs(measured - scorecard.yardage)
    if delta > tolerance:
        return (
            f"hole {scorecard.number}: measured {measured} yd vs scorecard "
            f"{scorecard.yardage} yd exceeds tolerance {tolerance:.0f} yd"
        )
    return None


def validate_course_geometry(
    holes: list[HoleGeometry],
    scorecard: list[ScorecardHole],
    minimum_holes: int = 9,
) -> ValidationResult:
    by_number = {h.number: h for h in holes}
    errors: list[str] = []
    checked = 0
    passed = 0

    for sc in scorecard:
        hole = by_number.get(sc.number)
        if not hole:
            errors.append(f"hole {sc.number}: missing geometry")
            continue
        checked += 1
        error = validate_hole_yardage(hole, sc)
        if error:
            errors.append(error)
        else:
            passed += 1

    enough_holes = checked >= minimum_holes
    confidence = 0.0 if not scorecard else passed / len(scorecard)
    accepted = enough_holes and confidence >= 0.82 and not errors[: max(1, len(scorecard) // 5)]
    return ValidationResult(accepted=accepted, confidence=round(confidence, 3), errors=errors)


def build_overpass_query(lat: float, lon: float, radius_m: int = 1500) -> str:
    features = [
        'way["golf"="green"]',
        'way["golf"="fairway"]',
        'way["golf"="tee"]',
        'way["golf"="bunker"]',
        'way["natural"="sand"]',
        'way["golf"="water_hazard"]',
        'way["golf"="lateral_water_hazard"]',
        'way["natural"="water"]',
        'way["natural"="wetland"]',
        'way["golf"="hole"]',
        'way["leisure"="golf_course"]',
        'node["golf"="pin"]',
        'relation["golf"="green"]',
        'relation["golf"="fairway"]',
        'relation["golf"="tee"]',
        'relation["golf"="bunker"]',
        'relation["natural"="sand"]',
        'relation["golf"="water_hazard"]',
        'relation["golf"="lateral_water_hazard"]',
        'relation["natural"="water"]',
        'relation["natural"="wetland"]',
        'relation["golf"="hole"]',
        'relation["leisure"="golf_course"]',
    ]
    body = "\n".join(f"  {f}(around:{radius_m},{lat},{lon});" for f in features)
    return f"[out:json][timeout:25];\n(\n{body}\n);\nout body;\n>;\nout skel qt;"


def http_json(url: str, *, method: str = "GET", headers: dict[str, str] | None = None,
              body: bytes | None = None, timeout: int = 30) -> Any:
    req = urllib.request.Request(url, data=body, method=method, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        raw = response.read().decode("utf-8")
        return json.loads(raw) if raw.strip() else None


def fetch_overpass(lat: float, lon: float) -> dict[str, Any]:
    url = os.environ.get("OVERPASS_URL", DEFAULT_OVERPASS_URL)
    query = build_overpass_query(lat, lon)
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    return http_json(
        url,
        method="POST",
        headers={
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "User-Agent": "TrueCarry-GeometryPipeline",
        },
        body=body,
        timeout=45,
    )


def fetch_golfcourseapi_scorecard(query: str) -> list[ScorecardHole]:
    key = os.environ.get("GOLFCOURSEAPI_KEY")
    if not key:
        return []
    url = "https://api.golfcourseapi.com/v1/search?" + urllib.parse.urlencode(
        {"search_query": query}
    )
    data = http_json(url, headers={"Authorization": f"Key {key}"}, timeout=25)
    courses = data.get("courses", [])
    if not courses:
        return []
    tees = courses[0].get("tees", {})
    candidates = []
    for group in ("male", "female"):
        candidates.extend(tees.get(group) or [])
    if not candidates:
        return []
    tee = max(candidates, key=lambda t: t.get("total_yards") or 0)
    holes = tee.get("holes") or []
    scorecard = []
    for idx, hole in enumerate(holes, start=1):
        scorecard.append(
            ScorecardHole(
                number=idx,
                par=int(hole.get("par") or 4),
                yardage=int(hole.get("yardage") or 0),
                handicap=hole.get("handicap"),
            )
        )
    return [h for h in scorecard if h.yardage > 0]


def fetch_naip_image(job: CourseJob, output_path: Path, span_degrees: float = 0.018) -> Path:
    if job.latitude is None or job.longitude is None:
        raise ValueError("NAIP fetch requires course latitude/longitude")
    url = os.environ.get("NAIP_IMAGE_SERVER_URL", DEFAULT_NAIP_URL)
    bbox = [
        job.longitude - span_degrees,
        job.latitude - span_degrees,
        job.longitude + span_degrees,
        job.latitude + span_degrees,
    ]
    params = {
        "f": "image",
        "bbox": ",".join(str(x) for x in bbox),
        "bboxSR": "4326",
        "imageSR": "4326",
        "size": "1600,1600",
        "format": "jpgpng",
    }
    req_url = url + "?" + urllib.parse.urlencode(params)
    with urllib.request.urlopen(req_url, timeout=45) as response:
        output_path.write_bytes(response.read())
    return output_path


def detect_geometry_from_image(image_path: Path, job: CourseJob) -> dict[str, list[list[Coordinate]]]:
    """Very conservative CV draft extractor.

    It returns feature polygons, not accepted hole geometry. Hole numbering and tee placement
    still require scorecard validation before anything is promoted to accepted geometry.
    """
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
    except Exception:
        return {"greens": [], "fairways": [], "bunkers": [], "water": []}

    image = cv2.imread(str(image_path))
    if image is None or job.latitude is None or job.longitude is None:
        return {"greens": [], "fairways": [], "bunkers": [], "water": []}

    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    green_mask = cv2.inRange(hsv, np.array([32, 35, 45]), np.array([95, 255, 230]))
    sand_mask = cv2.inRange(hsv, np.array([12, 10, 120]), np.array([45, 95, 255]))
    water_mask = cv2.inRange(hsv, np.array([85, 25, 15]), np.array([135, 255, 130]))

    def contours(mask: Any, min_area: int, max_area: int | None = None) -> list[list[Coordinate]]:
        found, _ = cv2.findContours(mask, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        polygons: list[list[Coordinate]] = []
        height, width = mask.shape[:2]
        span = 0.018
        for contour in found:
            area = cv2.contourArea(contour)
            if area < min_area or (max_area is not None and area > max_area):
                continue
            approx = cv2.approxPolyDP(contour, epsilon=4.0, closed=True)
            pts: list[Coordinate] = []
            for p in approx.reshape(-1, 2):
                x, y = float(p[0]), float(p[1])
                lon = (job.longitude - span) + (x / width) * (2 * span)
                lat = (job.latitude + span) - (y / height) * (2 * span)
                pts.append(Coordinate(lat, lon))
            if len(pts) >= 3:
                pts.append(pts[0])
                polygons.append(pts)
        return polygons

    fairways = contours(green_mask, min_area=14_000)
    greens = contours(green_mask, min_area=1_200, max_area=20_000)
    bunkers = contours(sand_mask, min_area=250, max_area=18_000)
    water = contours(water_mask, min_area=500)
    return {"greens": greens, "fairways": fairways, "bunkers": bunkers, "water": water}


def ring_json(coords: list[Coordinate]) -> dict[str, Any] | None:
    if len(coords) < 3:
        return None
    return {"coordinates": [c.to_json() for c in coords]}


def course_payload(job: CourseJob, holes: list[HoleGeometry], source: str,
                   metadata: dict[str, Any]) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    return {
        "id": job.course_id,
        "name": job.name,
        "city": job.city,
        "state": job.state,
        "country": job.country,
        "latitude": job.latitude,
        "longitude": job.longitude,
        "holes": [hole_payload(job.course_id, h) for h in holes],
        "tee_boxes": [],
        "source": source,
        "cached_at": now,
        "course_polygon": None,
        "geometry_metadata": metadata,
    }


def hole_payload(course_id: str, h: HoleGeometry) -> dict[str, Any]:
    return {
        "id": f"{course_id}-hole-{h.number}",
        "course_id": course_id,
        "number": h.number,
        "par": h.par,
        "handicap": None,
        "tee_yards_by_tee_box": {},
        "green_front_coordinate": h.green_front.to_json() if h.green_front else None,
        "green_center_coordinate": h.green_center.to_json() if h.green_center else None,
        "green_back_coordinate": h.green_back.to_json() if h.green_back else None,
        "tee_coordinate_by_tee_box": None,
        "path_coordinates": [c.to_json() for c in h.path],
        "hazards": [],
        "tee_coordinate": h.tee.to_json() if h.tee else None,
        "green_polygon": ring_json(h.green_polygon),
        "fairway_polygon": ring_json(h.fairway_polygon),
        "bunker_polygons": [ring_json(p) for p in h.bunker_polygons if ring_json(p)],
        "water_polygons": [ring_json(p) for p in h.water_polygons if ring_json(p)],
    }


def write_supabase_geometry(job: CourseJob, holes: list[HoleGeometry],
                            validation: ValidationResult, source: str,
                            imagery_source: str | None = None) -> None:
    base_url = os.environ["SUPABASE_URL"].rstrip("/")
    service_key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    state = "accepted" if validation.accepted else "auto_draft"
    metadata = {
        "state": state,
        "confidence": validation.confidence,
        "source": source,
        "schema_version": 1,
        "generated_by": "geometry_pipeline",
        "validation_errors": validation.errors,
        "imagery_source": imagery_source,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    body = {
        "course_id": job.course_id,
        "course_name": job.name,
        "city": job.city,
        "state": job.state,
        "source": source,
        "geometry_state": state,
        "confidence": validation.confidence,
        "schema_version": 1,
        "generated_by": "geometry_pipeline",
        "validation_errors": validation.errors,
        "imagery_source": imagery_source,
        "payload": course_payload(job, holes, "autoBackfill", metadata),
        "updated_at": metadata["updated_at"],
    }
    url = f"{base_url}/rest/v1/course_geometries?on_conflict=course_id"
    data = json.dumps(body).encode("utf-8")
    http_json(
        url,
        method="POST",
        headers={
            "apikey": service_key,
            "Authorization": f"Bearer {service_key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal,resolution=merge-duplicates",
        },
        body=data,
        timeout=30,
    )


def run(job: CourseJob) -> int:
    scorecard = fetch_golfcourseapi_scorecard(job.name)
    holes: list[HoleGeometry] = []
    source = "osm_overpass"
    imagery_source = None

    if job.latitude is not None and job.longitude is not None:
        try:
            _ = fetch_overpass(job.latitude, job.longitude)
            # OSM parsing for production acceptance lives in the iOS path today. The worker
            # still fetches the full payload so this is ready to promote into accepted server
            # geometry once the same inference code is ported/shared.
        except Exception as exc:
            print(f"[geometry_pipeline] OSM fetch failed: {exc}", file=sys.stderr)

    if not holes and job.country.upper() == "US" and job.latitude and job.longitude:
        source = "naip_cv"
        imagery_source = "USDA NAIP"
        with tempfile.TemporaryDirectory() as tmp:
            image_path = Path(tmp) / "naip.png"
            try:
                fetch_naip_image(job, image_path)
                features = detect_geometry_from_image(image_path, job)
                print(
                    "[geometry_pipeline] draft features "
                    f"greens={len(features['greens'])} fairways={len(features['fairways'])} "
                    f"bunkers={len(features['bunkers'])} water={len(features['water'])}"
                )
            except Exception as exc:
                print(f"[geometry_pipeline] NAIP/CV failed: {exc}", file=sys.stderr)

    validation = validate_course_geometry(holes, scorecard)
    if os.environ.get("SUPABASE_URL") and os.environ.get("SUPABASE_SERVICE_ROLE_KEY"):
        write_supabase_geometry(job, holes, validation, source, imagery_source)
    print(json.dumps({
        "course_id": job.course_id,
        "accepted": validation.accepted,
        "confidence": validation.confidence,
        "errors": validation.errors,
        "source": source,
    }, indent=2))
    return 0 if validation.accepted else 2


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    run_parser = sub.add_parser("run")
    run_parser.add_argument("--course-id", required=True)
    run_parser.add_argument("--name", required=True)
    run_parser.add_argument("--city", default="")
    run_parser.add_argument("--state", default="")
    run_parser.add_argument("--country", default="US")
    run_parser.add_argument("--lat", type=float)
    run_parser.add_argument("--lon", type=float)
    args = parser.parse_args(argv)

    if args.command == "run":
        return run(CourseJob(
            course_id=args.course_id,
            name=args.name,
            city=args.city,
            state=args.state,
            country=args.country,
            latitude=args.lat,
            longitude=args.lon,
        ))
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
