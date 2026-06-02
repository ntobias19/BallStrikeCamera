"""
Self-contained 18Birdies tee-enrichment worker.
Usage: python3 worker.py --courses courses_N.json --supabase-url URL --service-key KEY
"""
import argparse, gzip, hashlib, json, os, re, sys, time, urllib.request, urllib.error
from collections import defaultdict
from typing import Optional

SUPABASE_URL = os.environ.get("SUPABASE_URL", "")
SERVICE_KEY  = os.environ.get("SERVICE_KEY", "")
LOG_FILE     = "/tmp/worker.log"

# ── Inline normalizer ─────────────────────────────────────────────────────────

def normalize_tee_key(tee_name: str, gender: str = "male") -> str:
    name = tee_name.strip().title()
    for suffix in [" Men", " Women", " Male", " Female"]:
        if name.endswith(suffix):
            name = name[:-len(suffix)].strip()
    return name

# ── 18Birdies scraper (self-contained, retry-aware) ──────────────────────────

SEARCH_URL = "https://18birdies.com/usercentral/api/course/searchPlaces"
_HEADERS   = {
    "User-Agent":   "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36",
    "Origin":       "https://18birdies.com",
    "Referer":      "https://18birdies.com/golf-courses/",
    "Accept":       "application/json, text/plain, */*",
    "Content-Type": "application/json",
}

import requests
from rapidfuzz import fuzz

def _name_variants(name):
    variants = [name]
    short = re.sub(r"\b(golf course|golf club|country club|golf links|g\.c\.|g\.l\.)\b",
                   "", name, flags=re.I).strip()
    if short and short != name:
        variants.append(short)
    return variants

def _best_match(name, state, country, hole_count, clubs):
    best, best_score = None, 60.0
    for club in clubs:
        parts = [club.get(k,"") for k in ("name","address","ciName") if club.get(k)]
        text  = " ".join(str(p) for p in parts)
        score = float(max(fuzz.token_set_ratio(name.lower(), text.lower()),
                          fuzz.WRatio(name.lower(), text.lower())))
        try: ah = int(float(str(club.get("holeCount","0")).replace(",","")))
        except: ah = 0
        if ah and ah == hole_count: score += 3
        elif ah and ah != hole_count: score -= 5
        if state and state.upper() in (club.get("address") or "").upper(): score += 3
        if score > best_score:
            best_score, best = score, club
    return best

def _search_club(name, state, country, hole_count, session):
    for variant in _name_variants(name):
        try:
            r = session.post(SEARCH_URL, json={"key": variant}, timeout=10)
            time.sleep(0.4)
            if r.status_code != 200: continue
            clubs = [c.get("clubBrief",{}) for c in r.json().get("clubCards",[])]
            if not clubs: continue
            best = _best_match(name, state, country, hole_count, clubs)
            if best: return best
        except Exception:
            pass
    return None

def _parse_scorecard_text(text, hole_count):
    lines = [l.strip() for l in text.split("\n") if l.strip()]
    sc_start = next((i for i,l in enumerate(lines) if l == "Scorecard"), None)
    if sc_start is None: return None
    sc_lines = lines[sc_start:]

    tee_header_pat = re.compile(
        r"^(.+?)\s+[\d,]+\s+yds?\s*(?:\([^)]+\))?\s+for\s+(Men|Women)$", re.I)
    available_tees = {}
    for line in sc_lines[:25]:
        m = tee_header_pat.match(line)
        if m:
            raw = m.group(1).strip()
            gen = "male" if "women" not in m.group(2).lower() else "female"
            if raw not in available_tees or gen == "male":
                available_tees[raw] = gen
    if not available_tees: return None

    active_tee_raw = None
    active_tee_gender = None
    for i, line in enumerate(sc_lines):
        if line == "Hole":
            ahead = sc_lines[i+1:i+4]
            if len(ahead) >= 3 and ahead[0] == "Par" and ahead[1] == "Handicap":
                candidate = ahead[2]
                if candidate in available_tees:
                    active_tee_raw    = candidate
                    active_tee_gender = available_tees[candidate]
                    break
                for raw in available_tees:
                    if raw.lower() == candidate.lower():
                        active_tee_raw    = raw
                        active_tee_gender = available_tees[raw]
                        break
            if active_tee_raw: break

    if not active_tee_raw:
        active_tee_raw    = next(iter(available_tees))
        active_tee_gender = available_tees[active_tee_raw]

    tee_key = normalize_tee_key(active_tee_raw, active_tee_gender)
    holes_map = {}
    i = 0
    while i < len(sc_lines):
        line = sc_lines[i]
        if re.match(r"^(1[0-8]|[1-9])$", line):
            hole_num = int(line)
            if 1 <= hole_num <= 36:
                j, nums = i+1, []
                while len(nums) < 3 and j < len(sc_lines):
                    v = sc_lines[j]
                    if re.match(r"^\d+$", v): nums.append(int(v))
                    elif v not in ("OUT","IN","TOT","Hole","Par","Handicap"): pass
                    else: break
                    j += 1
                if len(nums) >= 3:
                    par = nums[0] if 3 <= nums[0] <= 5 else None
                    hcp = nums[1] if 1 <= nums[1] <= 36 else None
                    yds = nums[2] if 50 <= nums[2] <= 900 else None
                    if yds:
                        holes_map[hole_num] = {"hole_number": hole_num, "par": par,
                                               "handicap": hcp, "yards_by_tee": {tee_key: yds}}
                i = j; continue
        i += 1

    if len(holes_map) < max(9, hole_count // 2): return None
    return {"active_tee": active_tee_raw, "all_tees": list(available_tees.keys()),
            "holes": sorted(holes_map.values(), key=lambda h: h["hole_number"])}

def _scrape_all_tees(page, base_result, hole_count):
    try:
        selects = [s for s in page.query_selector_all("select") if s.is_visible()]
        tee_select, all_opts = None, []
        for sel in selects:
            opts = sel.query_selector_all("option")
            opt_texts = [o.inner_text() for o in opts]
            if any("yds" in t.lower() for t in opt_texts):
                tee_select = sel
                all_opts = [(o.get_attribute("value"), o.inner_text()) for o in opts]
                break
        if not tee_select: return base_result
        for val, label in all_opts[1:]:
            try:
                tee_select.select_option(value=val)
                time.sleep(0.8)
                parsed = _parse_scorecard_text(page.inner_text("body"), hole_count)
                if not parsed: continue
                for p_hole in parsed["holes"]:
                    hn = p_hole["hole_number"]
                    matched = next((h for h in base_result["holes"] if h["hole_number"]==hn), None)
                    if matched: matched["yards_by_tee"].update(p_hole["yards_by_tee"])
                    else: base_result["holes"].append(p_hole)
            except Exception: continue
    except Exception: pass
    base_result["holes"].sort(key=lambda h: h["hole_number"])
    return base_result

def fetch_scorecard(course_name, state="", country="", hole_count=18, session=None):
    """Fetch scorecard with up to 3 retry attempts, increasing timeout each time."""
    if session is None:
        session = requests.Session()
        session.headers.update(_HEADERS)

    facility_name = re.sub(r"\s*~.*$", "", course_name).strip()
    variant_hint  = ""
    m = re.search(r"~\s*(.+)$", course_name)
    if m: variant_hint = m.group(1).strip()

    club = _search_club(facility_name, state, country, hole_count, session)
    if not club: return None

    club_id   = club.get("id",{}).get("id","")
    club_name = club.get("name", facility_name)
    club_slug = re.sub(r"[^a-z0-9]+", "-", club_name.lower()).strip("-")
    if not club_id: return None

    url = f"https://18birdies.com/golf-courses/club/{club_id}/{club_slug}"

    try:
        from playwright.sync_api import sync_playwright, TimeoutError as PWTimeout
    except ImportError:
        return None

    base_timeout = 25000
    for attempt in range(3):
        timeout = base_timeout + attempt * 15000  # 25s → 40s → 55s
        try:
            with sync_playwright() as pw:
                browser = pw.chromium.launch(headless=True)
                ctx  = browser.new_context(user_agent=_HEADERS["User-Agent"])
                page = ctx.new_page()
                page.set_default_timeout(timeout)

                # domcontentloaded is much faster than networkidle — scorecard
                # data is in the initial HTML, no need to wait for all XHR.
                page.goto(url, wait_until="domcontentloaded", timeout=timeout)
                time.sleep(0.5)

                if variant_hint:
                    try:
                        for sel in page.query_selector_all("select"):
                            for opt in sel.query_selector_all("option"):
                                if fuzz.token_set_ratio(variant_hint.lower(),
                                                        opt.inner_text().strip().lower()) >= 70:
                                    sel.select_option(value=opt.get_attribute("value") or "")
                                    time.sleep(0.8)
                                    break
                    except Exception: pass

                sc_btn = page.query_selector('button:has-text("Scorecard")')
                if sc_btn:
                    sc_btn.click()
                    time.sleep(1.5)
                else:
                    time.sleep(1.0)

                text   = page.inner_text("body")
                result = _parse_scorecard_text(text, hole_count)
                if result:
                    result = _scrape_all_tees(page, result, hole_count)
                browser.close()

            if result:
                return result
            # Empty result — don't retry
            return None

        except Exception as e:
            err = str(e).lower()
            browser_closed = False
            try: browser.close()
            except: pass
            if "timeout" in err or "timed out" in err:
                if attempt < 2:
                    log(f"  timeout attempt {attempt+1}/3, retrying with {timeout+15000}ms...")
                    time.sleep(5)
                    continue
            return None

    return None

# ── Supabase helpers ──────────────────────────────────────────────────────────

def fetch_geometry(course_id):
    url = f"{SUPABASE_URL}/storage/v1/object/public/course-geometry/{course_id}.json.gz"
    try:
        return json.loads(gzip.decompress(urllib.request.urlopen(url, timeout=15).read()))
    except:
        return None

def push_geometry(course_id, geo):
    payload = gzip.compress(json.dumps(geo, separators=(",",":")).encode(), compresslevel=6)
    req = urllib.request.Request(
        f"{SUPABASE_URL}/storage/v1/object/course-geometry/{course_id}.json.gz",
        data=payload, method="POST",
        headers={"Authorization": f"Bearer {SERVICE_KEY}",
                 "Content-Type": "application/gzip", "x-upsert": "true"})
    try:
        urllib.request.urlopen(req, timeout=20)
        return True
    except:
        return False

def merge_and_push(course_id, scorecard_holes):
    """Merge 18Birdies tee data into existing geometry file and re-upload."""
    geo = fetch_geometry(course_id)
    if not geo: return False

    # Build lookup: hole_number → yards_by_tee
    sc_map = {h["hole_number"]: h["yards_by_tee"] for h in scorecard_holes}

    changed = False
    for h in geo.get("holes", []):
        num  = h.get("number")
        new  = sc_map.get(num, {})
        if not new: continue
        existing = h.get("tee_yards_by_tee_box") or {}
        merged   = dict(existing)
        for k, v in new.items():
            if k not in merged or v > merged[k]:
                merged[k] = v
        if merged != existing:
            h["tee_yards_by_tee_box"] = merged
            changed = True

    if not changed: return False
    return push_geometry(course_id, geo)

# ── Logging ───────────────────────────────────────────────────────────────────

def log(msg):
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except:
        pass

# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    global SUPABASE_URL, SERVICE_KEY

    ap = argparse.ArgumentParser()
    ap.add_argument("--courses",      required=True)
    ap.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL",""))
    ap.add_argument("--service-key",  default=os.environ.get("SERVICE_KEY",""))
    ap.add_argument("--results-file", default="/tmp/results.jsonl")
    args = ap.parse_args()

    SUPABASE_URL = args.supabase_url
    SERVICE_KEY  = args.service_key

    courses = json.load(open(args.courses))
    total   = len(courses)
    log(f"Starting: {total} courses")

    session = requests.Session()
    session.headers.update(_HEADERS)

    ok = not_found = errors = already_done = 0

    for i, c in enumerate(courses, 1):
        cid        = c["id"]
        name       = c["name"]
        state      = c.get("state") or ""
        country    = c.get("country") or ""
        hole_count = int(c.get("hole_count") or 18)

        try:
            result = fetch_scorecard(name, state=state, country=country,
                                     hole_count=hole_count, session=session)
        except Exception as e:
            log(f"[{i}/{total}] ERROR {name}: {e}")
            errors += 1
            with open(args.results_file, "a") as f:
                f.write(json.dumps({"id": cid, "status": "error"}) + "\n")
            continue

        if not result:
            not_found += 1
            with open(args.results_file, "a") as f:
                f.write(json.dumps({"id": cid, "status": "not_found"}) + "\n")
            if i % 50 == 0:
                log(f"[{i}/{total}] ok:{ok} not_found:{not_found} errors:{errors}")
            continue

        pushed = merge_and_push(cid, result["holes"])
        if pushed:
            ok += 1
            tees = list({t for h in result["holes"] for t in h["yards_by_tee"]})
            log(f"[{i}/{total}] ✓ {name} — tees: {sorted(tees)}")
        else:
            already_done += 1

        with open(args.results_file, "a") as f:
            f.write(json.dumps({
                "id":     cid,
                "status": "ok" if pushed else "no_change",
                "holes":  result["holes"]
            }) + "\n")

    log(f"DONE — ok:{ok} not_found:{not_found} no_change:{already_done} errors:{errors}")

if __name__ == "__main__":
    main()
