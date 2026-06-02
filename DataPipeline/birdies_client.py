"""
18Birdies scorecard scraper — NO auth required.

The scorecard is fully public. After clicking the Scorecard tab,
the page renders hole-by-hole yardage for all tee sets.

Flow:
  1. POST /usercentral/api/course/searchPlaces  {"key": "Course Name"}
     → returns club ID
  2. Load course page with Playwright
  3. Click "Scorecard" tab, wait for render
  4. Parse the text: tee headers + hole rows

Handles facility variants (Blue/White vs Gold/Red):
  - Strip "~ Blue/White" from name before searching
  - After finding club, select correct variant from dropdown if present

Speed: ~3-5s per course (Playwright render). Run 8 workers per droplet.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import time
from pathlib import Path
from typing import Optional

import requests
from rapidfuzz import fuzz

from .normalizer import normalize_tee_key

SEARCH_URL = "https://18birdies.com/usercentral/api/course/searchPlaces"

_HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
    "Origin":     "https://18birdies.com",
    "Referer":    "https://18birdies.com/golf-courses/",
    "Accept":     "application/json, text/plain, */*",
    "Content-Type": "application/json",
}


class BirdiesClient:
    def __init__(self, cache_dir: Optional[Path] = None, sleep: float = 0.3):
        self.cache_dir = Path(cache_dir) if cache_dir else None
        self.sleep     = sleep
        self.session   = requests.Session()
        self.session.headers.update(_HEADERS)

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def fetch_scorecard(
        self,
        course_name: str,
        state: str = "",
        country: str = "",
        city: str = "",
        hole_count: int = 18,
    ) -> Optional[dict]:
        """
        Returns standard scorecard dict or None.
        Uses Playwright for the page render (scorecard tab).
        """
        # Strip variant suffix for search
        facility_name = re.sub(r"\s*~.*$", "", course_name).strip()
        variant_hint  = ""
        m = re.search(r"~\s*(.+)$", course_name)
        if m:
            variant_hint = m.group(1).strip()

        # Step 1: Search for club ID
        club = self._search_club(facility_name, state, country, hole_count)
        if not club:
            return None

        club_id   = club.get("id", {}).get("id", "")
        club_name = club.get("name", facility_name)
        club_slug = re.sub(r"[^a-z0-9]+", "-", club_name.lower()).strip("-")

        if not club_id:
            return None

        # Step 2: Scrape scorecard with Playwright
        return self._scrape_scorecard(club_id, club_slug, variant_hint, hole_count)

    # ------------------------------------------------------------------
    # Search (no auth)
    # ------------------------------------------------------------------

    def _search_club(
        self, name: str, state: str, country: str, hole_count: int
    ) -> Optional[dict]:
        cache_key = f"b_search_{_hash(f'{name}_{state}_{country}')}"
        cached = self._cache_read(cache_key)
        if cached is not None:
            return cached if cached else None

        for variant in _name_variants(name):
            try:
                r = self.session.post(
                    SEARCH_URL, json={"key": variant}, timeout=10
                )
                time.sleep(self.sleep)
                if r.status_code != 200:
                    continue
                clubs = [c.get("clubBrief", {})
                         for c in r.json().get("clubCards", [])]
                if not clubs:
                    continue
                best = _best_match(name, state, country, hole_count, clubs)
                if best:
                    self._cache_write(cache_key, best)
                    return best
            except Exception:
                pass

        self._cache_write(cache_key, {})
        return None

    # ------------------------------------------------------------------
    # Playwright scorecard scrape
    # ------------------------------------------------------------------

    def _scrape_scorecard(
        self,
        club_id: str,
        club_slug: str,
        variant_hint: str,
        hole_count: int,
    ) -> Optional[dict]:
        cache_key = f"b_sc_{_hash(f'{club_id}_{variant_hint}')}"
        cached = self._cache_read(cache_key)
        if cached is not None:
            return cached if cached else None

        url = f"https://18birdies.com/golf-courses/club/{club_id}/{club_slug}"

        try:
            from playwright.sync_api import sync_playwright
        except ImportError:
            return None

        result = None
        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch(headless=True)
                ctx = browser.new_context(user_agent=_HEADERS["User-Agent"])
                page = ctx.new_page()
                page.set_default_timeout(20000)

                page.goto(url, wait_until="networkidle", timeout=25000)
                time.sleep(1)

                # Select course variant if needed (Blue/White vs Gold/Red etc.)
                if variant_hint:
                    self._select_variant(page, variant_hint)

                # Click Scorecard tab
                sc_btn = page.query_selector('button:has-text("Scorecard")')
                if sc_btn:
                    sc_btn.click()
                    time.sleep(3)
                else:
                    time.sleep(2)

                # Parse first (default) tee
                text = page.inner_text("body")
                result = _parse_scorecard_text(text, hole_count)

                # Now cycle through all other tees to get their yardages
                if result:
                    result = _scrape_all_tees(page, result, hole_count)

                browser.close()
        except Exception:
            pass

        if result:
            result["birdies_club_id"] = club_id
            self._cache_write(cache_key, result)
        else:
            self._cache_write(cache_key, {})
        return result

    def _select_variant(self, page, variant_hint: str) -> None:
        """Click the right course variant in the dropdown if multiple exist."""
        # Look for a select/dropdown with course variant names
        try:
            selects = page.query_selector_all("select")
            for sel in selects:
                options = sel.query_selector_all("option")
                for opt in options:
                    opt_text = opt.inner_text().strip()
                    if fuzz.token_set_ratio(
                        variant_hint.lower(), opt_text.lower()
                    ) >= 70:
                        sel.select_option(value=opt.get_attribute("value") or "")
                        time.sleep(1.5)
                        return

            # Try clicking a tab/button
            for btn in page.query_selector_all("button, [role='tab']"):
                btn_text = btn.inner_text().strip()
                if fuzz.token_set_ratio(
                    variant_hint.lower(), btn_text.lower()
                ) >= 70:
                    btn.click()
                    time.sleep(1)
                    return
        except Exception:
            pass

    # ------------------------------------------------------------------
    # Cache
    # ------------------------------------------------------------------

    def _cache_read(self, key: str):
        if not self.cache_dir:
            return None
        p = self.cache_dir / f"{key}.json"
        if p.exists():
            try:
                return json.loads(p.read_text())
            except Exception:
                pass
        return None

    def _cache_write(self, key: str, data) -> None:
        if not self.cache_dir:
            return
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        try:
            (self.cache_dir / f"{key}.json").write_text(
                json.dumps(data, ensure_ascii=False)
            )
        except Exception:
            pass


# ---------------------------------------------------------------------------
# Scorecard text parser
# ---------------------------------------------------------------------------

def _parse_scorecard_text(text: str, hole_count: int) -> Optional[dict]:
    """
    Parse 18Birdies scorecard text.

    Layout (one tee shown at a time):
      Scorecard
      [Course Name]
      Back 6000 yds (105/67) for Men     ← available tees listed
      Middle 5690 yds ...
      Forward 2450 yds ...
      Hole                                ← column headers
      Par
      Handicap
      Back                               ← selected tee name
      1  4  14  365                      ← hole, par, hcp, yardage (4 values)
      2  3   8  250
      ...
      OUT  36  3140  TOT
      [repeats for back 9]
    """
    lines = [l.strip() for l in text.split("\n") if l.strip()]

    sc_start = next((i for i, l in enumerate(lines) if l == "Scorecard"), None)
    if sc_start is None:
        return None

    sc_lines = lines[sc_start:]

    # --- Collect available tees from header lines ---
    # "Back 6000 yds (105/67) for Men"  OR  "Back 6000 yds for Men"
    tee_header_pat = re.compile(
        r"^(.+?)\s+[\d,]+\s+yds?\s*(?:\([^)]+\))?\s+for\s+(Men|Women)$", re.I
    )
    available_tees: dict[str, str] = {}  # raw_name → gender (prefer male, don't overwrite)
    for line in sc_lines[:25]:
        m = tee_header_pat.match(line)
        if m:
            raw = m.group(1).strip()
            gen = "male" if "women" not in m.group(2).lower() else "female"
            # Only set if not already present (prefer male over female for same tee name)
            if raw not in available_tees or gen == "male":
                available_tees[raw] = gen

    if not available_tees:
        return None

    # --- Find the column header block to identify active tee ---
    # Look for pattern: "Hole\nPar\nHandicap\n<tee_name>"
    active_tee_raw = None
    active_tee_gender = None
    for i, line in enumerate(sc_lines):
        if line == "Hole":
            # Next lines should be Par, Handicap, <tee_name>
            ahead = sc_lines[i+1:i+4]
            if len(ahead) >= 3 and ahead[0] == "Par" and ahead[1] == "Handicap":
                candidate = ahead[2]
                if candidate in available_tees:
                    active_tee_raw    = candidate
                    active_tee_gender = available_tees[candidate]
                    break
                # Might be just the tee color without "for Men/Women"
                for raw in available_tees:
                    if raw.lower() == candidate.lower():
                        active_tee_raw    = raw
                        active_tee_gender = available_tees[raw]
                        break
            if active_tee_raw:
                break

    if not active_tee_raw:
        # Fallback: use first available tee
        active_tee_raw    = next(iter(available_tees))
        active_tee_gender = available_tees[active_tee_raw]

    tee_key = normalize_tee_key(active_tee_raw, active_tee_gender)

    # --- Parse hole rows: groups of 4 numbers (hole, par, hcp, yardage) ---
    holes_map: dict[int, dict] = {}
    i = 0
    while i < len(sc_lines):
        line = sc_lines[i]
        if re.match(r"^(1[0-8]|[1-9])$", line):
            hole_num = int(line)
            if 1 <= hole_num <= 36:
                j = i + 1
                nums = []
                while len(nums) < 3 and j < len(sc_lines):
                    v = sc_lines[j]
                    if re.match(r"^\d+$", v):
                        nums.append(int(v))
                    elif v not in ("OUT", "IN", "TOT", "Hole", "Par", "Handicap"):
                        pass   # skip non-numeric non-keyword
                    else:
                        break
                    j += 1

                if len(nums) >= 3:
                    par  = nums[0] if 3 <= nums[0] <= 5 else None
                    hcp  = nums[1] if 1 <= nums[1] <= 36 else None
                    yds  = nums[2] if 50 <= nums[2] <= 900 else None
                    if yds:
                        holes_map[hole_num] = {
                            "hole_number": hole_num,
                            "par":         par,
                            "handicap":    hcp,
                            "yards_by_tee": {tee_key: yds},
                        }
                i = j
                continue
        i += 1

    if len(holes_map) < max(9, hole_count // 2):
        return None

    return {
        "source":     "18birdies",
        "confidence": "high",
        "active_tee": active_tee_raw,
        "all_tees":   list(available_tees.keys()),
        "holes":      sorted(holes_map.values(), key=lambda h: h["hole_number"]),
    }


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _scrape_all_tees(page, base_result: dict, hole_count: int) -> dict:
    """
    Use the tee <select> dropdown to cycle through all tee options.
    Merges yardages for each tee into base_result.
    """
    try:
        # Find the tee selector (second visible <select> — first is course variant)
        selects = [s for s in page.query_selector_all("select") if s.is_visible()]
        tee_select = None
        for sel in selects:
            opts = sel.query_selector_all("option")
            opt_texts = [o.inner_text() for o in opts]
            # The tee select has options like "Blue 4996 yds..."
            if any("yds" in t.lower() for t in opt_texts):
                tee_select = sel
                all_opts = [(o.get_attribute("value"), o.inner_text()) for o in opts]
                break

        if not tee_select:
            return base_result

        # Skip index 0 (already scraped as default)
        for val, label in all_opts[1:]:
            try:
                tee_select.select_option(value=val)
                time.sleep(1.5)

                text   = page.inner_text("body")
                parsed = _parse_scorecard_text(text, hole_count)
                if not parsed:
                    continue

                # Merge
                for p_hole in parsed["holes"]:
                    hn = p_hole["hole_number"]
                    matched = next(
                        (h for h in base_result["holes"] if h["hole_number"] == hn), None
                    )
                    if matched:
                        matched["yards_by_tee"].update(p_hole["yards_by_tee"])
                    else:
                        base_result["holes"].append(p_hole)

            except Exception:
                continue

    except Exception:
        pass

    base_result["holes"].sort(key=lambda h: h["hole_number"])
    return base_result


def _best_match(
    name: str, state: str, country: str, hole_count: int, clubs: list[dict]
) -> Optional[dict]:
    best, best_score = None, 60.0
    for club in clubs:
        parts = [club.get(k, "") for k in ("name", "address", "ciName") if club.get(k)]
        text  = " ".join(str(p) for p in parts)
        score = float(max(
            fuzz.token_set_ratio(name.lower(), text.lower()),
            fuzz.WRatio(name.lower(), text.lower()),
        ))
        api_holes = _int(club.get("holeCount"))
        if api_holes and api_holes == hole_count: score += 3
        elif api_holes and api_holes != hole_count: score -= 5
        if state and state.upper() in (club.get("address") or "").upper(): score += 3
        if score > best_score:
            best_score, best = score, club
    return best


def _name_variants(name: str) -> list[str]:
    variants = [name]
    short = re.sub(
        r"\b(golf course|golf club|country club|golf links|g\.c\.|g\.l\.)\b",
        "", name, flags=re.I
    ).strip()
    if short and short != name:
        variants.append(short)
    return variants


def _int(v) -> Optional[int]:
    try: return int(float(str(v).replace(",", "").strip()))
    except: return None


def _hash(text: str) -> str:
    return hashlib.sha1(text.encode()).hexdigest()[:16]
