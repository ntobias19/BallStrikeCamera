#!/usr/bin/env python3
"""Ball/Club Tracking Tuner — matplotlib GUI.
Pages: Ball Tracking | Club Tracking | Metrics
Features: mask refinement, B&W preview, dynamic impact detection,
          4 club modes (hybrid/frameDiff/darkBlob/edgeBlob), ball path,
          0° reference line, metrics formulas."""
import json, os, sys, glob, math, argparse as _ap
from collections import deque
import numpy as np
import matplotlib
matplotlib.use("MacOSX")
import matplotlib.pyplot as plt
import matplotlib.patches as patches
from matplotlib.widgets import Slider, Button, RadioButtons
from PIL import Image
import matplotlib.widgets as _mplw

# Patch matplotlib 3.9 crashes: RadioButtons hover on hidden axes + Slider grab_mouse conflict
def _patch_mpl_widgets():
    _orig_rb = _mplw.RadioButtons._clear
    def _safe_rb(self, event):
        try: _orig_rb(self, event)
        except (AttributeError, TypeError): pass
    _mplw.RadioButtons._clear = _safe_rb
    _orig_sl = _mplw.Slider._update
    def _safe_sl(self, event):
        try: _orig_sl(self, event)
        except (AttributeError, RuntimeError): pass
    _mplw.Slider._update = _safe_sl
_patch_mpl_widgets()

_aparser = _ap.ArgumentParser(add_help=False)
_aparser.add_argument("folder",                   nargs="?", default=".")
_aparser.add_argument("--batch",                  default=None, metavar="DIR",
                      help="Run headless over all ShotExport_* in DIR and print summary table")
_aparser.add_argument("--save-face-debug",        action="store_true")
_aparser.add_argument("--face-frame",             type=int,   default=None)
_aparser.add_argument("--face-frame-offset",      type=int,   default=1)
_aparser.add_argument("--face-method",            default="auto", choices=["auto","hough","pca"])
_aparser.add_argument("--face-roi-scale-x",       type=float, default=4.0)
_aparser.add_argument("--face-roi-scale-y",       type=float, default=3.0)
_aparser.add_argument("--face-roi-offset-x",      type=float, default=0.0)
_aparser.add_argument("--face-roi-offset-y",      type=float, default=0.0)
_aparser.add_argument("--face-ball-exclusion-scale", type=float, default=2.1)
_aparser.add_argument("--face-use-club-box",      action="store_true")
_aparser.add_argument("--face-club-box-padding",  type=float, default=1.5)
_aparser.add_argument("--face-edge-threshold",    type=float, default=20.0)
_aparser.add_argument("--face-min-edge-pixels",   type=int,   default=30)
_aparser.add_argument("--face-pca-outlier-trim",  type=float, default=0.05)
_aparser.add_argument("--face-canny-low",         type=int,   default=50)
_aparser.add_argument("--face-canny-high",        type=int,   default=150)
_aparser.add_argument("--face-hough-threshold",   type=int,   default=30)
_aparser.add_argument("--face-hough-min-length",  type=int,   default=15)
_aparser.add_argument("--face-hough-max-gap",     type=int,   default=10)
_aparser.add_argument("--face-angle-normal-mode", default="line", choices=["line","normal"])
_aparser.add_argument("--face-angle-flip",        type=int,   default=0, choices=[0,1])
_aparser.add_argument("--face-save-mask-debug",   action="store_true")
_aparser.add_argument("--vla-model", default="pinhole2dsize",
                      choices=["legacy","pinhole2dsize","blended"],
                      help="VLA estimation model")
_aparser.add_argument("--vla-image-y-weight",    type=float, default=0.45)
_aparser.add_argument("--vla-diameter-depth-weight", type=float, default=0.55)
_aparser.add_argument("--vla-depth-sign",        type=float, default=1.0)
_aparser.add_argument("--vla-depth-scale",       type=float, default=1.0)
_aparser.add_argument("--rightward-size-correction-strength", type=float, default=0.35)
_aparser.add_argument("--disable-rightward-size-correction",  action="store_true")
_face_args, _ = _aparser.parse_known_args()
FOLDER = _face_args.folder
VLA_MODEL = _face_args.vla_model

png_paths = sorted(glob.glob(os.path.join(FOLDER, "frame_*.png")))
assert png_paths, f"No frame_*.png in {FOLDER}"
raw_frames = [np.array(Image.open(p).convert("RGB")) for p in png_paths]
H, W = raw_frames[0].shape[:2]
N = len(raw_frames)
print(f"Loaded {N} frames ({W}x{H})")

meta_path = os.path.join(FOLDER, "metadata.json")
metadata = {}
impact_idx = 20
locked_rect = (0.45, 0.45, 0.10, 0.10)
fps_estimate = 240.0
if os.path.exists(meta_path):
    metadata = json.load(open(meta_path))
    impact_idx = metadata.get("impact_frame_index", impact_idx)
    fps_estimate = float(metadata.get("fps_estimate", fps_estimate) or fps_estimate)
    if "locked_ball_rect" in metadata:
        r = metadata["locked_ball_rect"]
        locked_rect = (r["x"], r["y"], r["width"], r["height"])

timestamps = [dict(frame_index=i, timestamp=i/fps_estimate,
                   relative_time=(i-impact_idx)/fps_estimate) for i in range(N)]
ts_path = os.path.join(FOLDER, "timestamps.json")
if os.path.exists(ts_path):
    ts_data = json.load(open(ts_path))
    ts_items = ts_data.get("timestamps", ts_data if isinstance(ts_data, list) else [])
    ts_by = {int(t.get("frame_index", t.get("frameIndex", i))): t for i, t in enumerate(ts_items)}
    for i in range(N):
        t = ts_by.get(i)
        if t:
            timestamps[i] = dict(frame_index=i,
                timestamp=float(t.get("timestamp", i/fps_estimate)),
                relative_time=float(t.get("relative_time", t.get("relativeTime",
                                           (i-impact_idx)/fps_estimate))))

rel_times = np.array([t["relative_time"] for t in timestamps], dtype=float)

# ── Normalization ─────────────────────────────────────────────────────────────
def normalize(img, mode):
    if mode == "original":
        return img.astype(np.float32) / 255.0
    f = img.astype(np.float32) / 255.0
    if mode == "darkened":
        f = np.clip(f * (2**-0.6), 0, 1)
        f = np.clip((f - 0.5) * 1.35 + 0.5, 0, 1)
        f = np.power(np.clip(f, 1e-6, 1), 1.0/1.10)
    else:
        f = np.clip(f * (2**1.0), 0, 1)
        f = np.clip((f - 0.5) * 1.20 + 0.5, 0, 1)
        f = np.power(np.clip(f, 1e-6, 1), 1.0/0.90)
    return np.clip(f, 0, 1)

# ── Mask-based diameter refinement ───────────────────────────────────────────
def mask_refine_diameter(img_norm, cx_norm, cy_norm, cand_dia_norm, p=None, window_scale=None):
    """Part A: adaptive percentile-based brightness threshold for ball mask."""
    if p is None: p = {}
    if window_scale is None: window_scale = float(p.get("mask_scale", 1.8))
    abs_brightness = int(p.get("mask_brightness", 30))
    use_percentile = float(p.get("use_percentile_mask", 1.0)) > 0.5
    pct_value = float(p.get("mask_percentile", 92.0))
    pct_min_bright = int(p.get("mask_pct_min_bright", 80))
    pct_max_bright = int(p.get("mask_pct_max_bright", 245))
    bg_delta = int(p.get("mask_bg_delta", 15))

    cx_px = int(round(cx_norm * W)); cy_px = int(round(cy_norm * H))
    radius_px = max(4, int(round(window_scale * cand_dia_norm * W / 2)))
    crop_size = radius_px * 2 + 1
    crop_origin_x = cx_px - radius_px; crop_origin_y = cy_px - radius_px
    x0 = max(0, crop_origin_x); x1 = min(W, cx_px + radius_px + 1)
    y0 = max(0, crop_origin_y); y1 = min(H, cy_px + radius_px + 1)
    img_i = (img_norm * 255).astype(np.int32)
    patch = img_i[y0:y1, x0:x1]
    r, g, b = patch[...,0], patch[...,1], patch[...,2]
    br = (r + g + b) // 3

    # Part A: percentile-based adaptive threshold
    if use_percentile and br.size > 0:
        flat = br.flatten()
        local_median = int(np.median(flat))
        pct_thresh = int(np.percentile(flat, pct_value))
        delta_thresh = local_median + bg_delta
        raw_thresh = max(abs_brightness, max(pct_thresh, delta_thresh))
        effective_thresh = max(pct_min_bright, min(pct_max_bright, raw_thresh))
    else:
        effective_thresh = abs_brightness

    ball_mask = br >= effective_thresh
    preview = np.zeros((crop_size, crop_size, 3), dtype=np.uint8)
    py0 = y0 - crop_origin_y; px0 = x0 - crop_origin_x
    cand_diam_in_crop = cand_dia_norm * W / crop_size
    if not ball_mask.any():
        return None, preview, cand_diam_in_crop, None, "no_white_pixels", None, None, 0, 0.0, 0.0, 1.0
    visited = np.zeros_like(ball_mask, dtype=bool)
    components = []
    target_x = cx_px - x0; target_y = cy_px - y0
    rows2, cols2 = ball_mask.shape
    for sr in range(rows2):
        for sc in range(cols2):
            if not ball_mask[sr, sc] or visited[sr, sc]:
                continue
            q = deque([(sr, sc)]); visited[sr, sc] = True; pixels = []
            while q:
                cr, cc = q.popleft(); pixels.append((cr, cc))
                for dr, dc in [(-1,0),(1,0),(0,-1),(0,1)]:
                    nr, nc = cr+dr, cc+dc
                    if 0<=nr<rows2 and 0<=nc<cols2 and ball_mask[nr,nc] and not visited[nr,nc]:
                        visited[nr,nc] = True; q.append((nr,nc))
            ys_ = [p[0] for p in pixels]; xs_ = [p[1] for p in pixels]
            cx_ = (min(xs_)+max(xs_))/2; cy_ = (min(ys_)+max(ys_))/2
            dist = (cx_-target_x)**2 + (cy_-target_y)**2
            components.append(dict(pixels=pixels, count=len(pixels),
                min_x=min(xs_), max_x=max(xs_), min_y=min(ys_), max_y=max(ys_), dist=dist))
    if not components:
        return None, preview, cand_diam_in_crop, None, "no_connected_component", None, None, 0, 0.0, 0.0, 1.0
    sub = [c for c in components if c["count"] >= 4]
    if not sub:
        sub = [c for c in components if c["count"] >= 2] or components
    best = min(sub, key=lambda c: (c["dist"], -c["count"]))
    max_drift = max(2.0, cand_dia_norm * W * 0.55)
    if best["dist"]**0.5 > max_drift:
        return None, preview, cand_diam_in_crop, None, "component_drift_fallback_candidate", None, None, 0, 0.0, 0.0, 1.0
    for row, col in best["pixels"]:
        preview[py0+row, px0+col] = 255
    min_x = x0 + best["min_x"]; max_x = x0 + best["max_x"]
    min_y = y0 + best["min_y"]; max_y = y0 + best["max_y"]
    diam_px = max(max_x-min_x+1, max_y-min_y+1)
    raw_dia = diam_px / W
    ref_diam_in_crop = diam_px / crop_size
    mc_px = ((min_x+max_x)/2, (min_y+max_y)/2)
    mc_norm = (mc_px[0]/W, mc_px[1]/H)
    mc_crop = ((mc_px[0]-crop_origin_x)/crop_size, (mc_px[1]-crop_origin_y)/crop_size)
    bright_vals = [int(br[row, col]) for row, col in best["pixels"]]
    brightness_mean = float(sum(bright_vals) / len(bright_vals)) if bright_vals else 0.0
    fill_ratio = float(best["count"]) / max(1.0, math.pi * (diam_px / 2) ** 2)
    # Part D: Compute mask component aspect ratio for roundness check
    comp_width_px  = max(best["max_x"] - best["min_x"] + 1, 1)
    comp_height_px = max(best["max_y"] - best["min_y"] + 1, 1)
    mask_aspect = comp_width_px / max(comp_height_px, 1)
    return raw_dia, preview, cand_diam_in_crop, ref_diam_in_crop, "mask_refined", mc_norm, mc_crop, best["count"], fill_ratio, brightness_mean, mask_aspect

# ── Dynamic impact detection ──────────────────────────────────────────────────
def detect_impact_frame(pass1_results, fallback_impact, move_thresh=0.006, confirm_frames=2, stable_window=10, p=None):
    if p is None: p = {}
    use_diam_change = p.get("impact_detect_use_diam_change", 1.0) > 0.5
    diam_change_ratio = float(p.get("impact_diam_change_ratio", 1.35))
    diam_shrink_ratio = float(p.get("impact_diam_shrink_ratio", 0.80))
    return_minus_one = p.get("impact_return_minus_one", 1.0) > 0.5
    min_stable = max(3, int(p.get("impact_min_stable_frames", 6)))

    cutoff = min(stable_window, fallback_impact)
    stable = [(r['idx'], r['chosen']['cx'], r['chosen']['cy'])
              for r in pass1_results if r['idx'] < cutoff and r['chosen']]
    if len(stable) < min_stable:
        return fallback_impact, None, move_thresh, "fallback_insufficient_stable"
    cxs = sorted(s[1] for s in stable); cys = sorted(s[2] for s in stable)
    med_cx = cxs[len(cxs)//2]; med_cy = cys[len(cys)//2]
    dias = sorted(r['chosen']['dia'] for r in pass1_results if r['idx'] < cutoff and r['chosen'])
    med_dia = dias[len(dias)//2] if dias else 0.030
    threshold = max(move_thresh, med_dia * 0.20)
    scan_start = stable[-1][0] + 1

    # Check both position and diameter change
    event_frame = None; event_reason = None
    consec = 0; first_frame = None; last_idx = scan_start - 2

    scan_results = [r for r in pass1_results if r['idx'] >= scan_start]
    for r in sorted(scan_results, key=lambda x: x['idx']):
        idx = r['idx']
        chosen = r.get('chosen')
        if not chosen:
            # bad detection — treat as event
            if event_frame is None:
                event_frame = idx; event_reason = "bad_detection_minus_one"
            break
        cx, cy = chosen['cx'], chosen['cy']
        dia = chosen.get('dia', med_dia)
        dist = ((cx-med_cx)**2 + (cy-med_cy)**2)**0.5
        pos_moved = dist > threshold
        diam_spiked = use_diam_change and (dia / max(med_dia, 1e-6) > diam_change_ratio)
        diam_shrunk = use_diam_change and (dia / max(med_dia, 1e-6) < diam_shrink_ratio)

        if pos_moved:
            if consec == 0: first_frame = idx; consec = 1
            elif idx == last_idx + 1: consec += 1
            else: first_frame = idx; consec = 1
            if consec >= confirm_frames:
                event_frame = first_frame; event_reason = "first_movement_minus_one"
                break
        else:
            consec = 0; first_frame = None

        if (diam_spiked or diam_shrunk) and event_frame is None:
            event_frame = idx
            event_reason = "first_size_change_minus_one" if diam_spiked else "first_size_shrink_minus_one"
            break

        last_idx = idx

    if event_frame is not None:
        result_frame = max(0, event_frame - 1) if return_minus_one else event_frame
        return result_frame, (med_cx, med_cy), threshold, event_reason
    return fallback_impact, (med_cx, med_cy), threshold, "fallback_no_movement"

# ── Candidate scoring (Parts A-M equivalent) ─────────────────────────────────
def compute_predicted(recent_post_points, lookback=3, init_center=None, frame_dt=None):
    pts = list(recent_post_points)[-max(2, lookback):]
    if len(pts) >= 2:
        dt = pts[-1][2] - pts[-2][2]
        if abs(dt) < 1e-9:
            # Use index-based step
            vx = pts[-1][0] - pts[-2][0]
            vy = pts[-1][1] - pts[-2][1]
            return (pts[-1][0] + vx, pts[-1][1] + vy), "velocity"
        vx = (pts[-1][0] - pts[-2][0]) / dt
        vy = (pts[-1][1] - pts[-2][1]) / dt
        step_dt = frame_dt if frame_dt else dt
        return (pts[-1][0] + vx * step_dt, pts[-1][1] + vy * step_dt), "velocity"
    elif len(pts) == 1 and init_center is not None:
        # Single-point prediction: project from init_center through first post point
        dx = pts[0][0] - init_center[0]
        dy = pts[0][1] - init_center[1]
        dist = math.sqrt(dx*dx + dy*dy)
        if dist < 1e-6:
            return None, None
        # Step size = same as distance from init to first point
        step = min(max(dist, 0.006), 0.12)
        norm = dist
        return (pts[0][0] + dx/norm * step, pts[0][1] + dy/norm * step), "single_point"
    return None, None

def score_candidate(c, context, p):
    bright_score = c["conf"]

    dia = c["dia"]
    exp_dia = context.get("expected_diameter")
    target_dia = exp_dia if exp_dia else 0.025
    size_score = max(0.0, 1.0 - abs(dia - target_dia) / max(target_dia, 1e-6))

    bx, by, bw, bh = c["rect"]
    shape_score = min(bw, bh) / max(bw, bh, 1e-6)

    preferred = context.get("preferred_center")
    dist_score = 0.0
    if preferred:
        dx = c["cx"] - preferred[0]; dy = c["cy"] - preferred[1]
        dist_score = max(0.0, 1.0 - math.sqrt(dx*dx+dy*dy) / max(p.get("sc_max_jump",0.10),1e-6))

    predicted = context.get("predicted_pos")
    motion_score = 0.0; jump_dist = None; penalty = 0.0
    if predicted:
        dx = c["cx"] - predicted[0]; dy = c["cy"] - predicted[1]
        jd = math.sqrt(dx*dx + dy*dy); jump_dist = jd
        max_jump = max(p.get("sc_max_jump",0.10), dia * p.get("sc_jump_by_dia",4.0))
        motion_score = max(0.0, 1.0 - jd / max(max_jump, 1e-6))
        if jd > max_jump:
            penalty += p.get("sc_jump_penalty", 3.0)

    exp_dir = context.get("expected_direction")
    dir_score = 0.0
    if exp_dir and context.get("is_post_impact"):
        ref_pt = predicted or preferred
        if ref_pt:
            dx = c["cx"] - ref_pt[0]; dy = c["cy"] - ref_pt[1]
            edx, edy = exp_dir
            elen = math.sqrt(edx*edx + edy*edy)
            if elen > 1e-6: edx, edy = edx/elen, edy/elen
            forward = dx * edx + dy * edy
            if forward < p.get("sc_min_fwd", -0.005):
                penalty += p.get("sc_dir_penalty", 1.5)
            dir_score = max(0.0, min(1.0, 0.5 + forward * 20))

    dia_score = 0.0
    if exp_dia and exp_dia > 0:
        ratio = dia / exp_dia
        dia_score = max(0.0, 1.0 - abs(ratio - 1.0))
        if ratio < p.get("sc_min_dia_ratio",0.35) or ratio > p.get("sc_max_dia_ratio",2.25):
            penalty += p.get("sc_diam_w",2.0) * 0.5
        if p.get("sc_hard_reject_diam",1.0) > 0.5:
            ext = p.get("sc_extreme_dia_ratio",3.0)
            if ratio > ext or ratio < 1.0 / ext:
                c["accepted"] = False; c["reason"] = f"extreme_dia({ratio:.2f})"

    asp = bw / max(bh, 1e-6)
    if p.get("sc_reject_club",1.0) > 0.5 and asp > p.get("sc_club_asp",4.0):
        c["accepted"] = False; c["reason"] = f"club_asp({asp:.2f})"

    # Hard no-backward / no-behind-ball rule (Part A) — before launch direction locked
    # Use zero-degree reference direction to reject candidates clearly behind start point
    launch_dir = context.get("launch_dir")
    prev_prog  = context.get("prev_progress")
    ball_launched = context.get("ball_launched", False)
    init_c = context.get("init_center")
    progress = None; backward_rejected = False

    if (p.get("hard_reject_behind_start", 1.0) > 0.5 and
            p.get("use_ref_progress_before_launch", 1.0) > 0.5 and
            not ball_launched and init_c and context.get("is_post_impact")):
        theta_ref = math.radians(context.get("zero_deg", 0))
        ref_dx = math.cos(theta_ref); ref_dy = -math.sin(theta_ref)
        dx = c["cx"] - init_c[0]; dy = c["cy"] - init_c[1]
        progress_ref = dx * ref_dx + dy * ref_dy
        min_prog_pre = float(p.get("min_progress_before_launch", -0.003))
        if progress_ref < min_prog_pre:
            c["accepted"] = False
            c["reason"] = f"rejected_behind_start({progress_ref:.4f})"
            c.update(dict(total_score=-999, jump_dist=jump_dist,
                          progress=progress_ref, backward_rejected=True))
            return c

    if (p.get("sc_monotonic",1.0) > 0.5 and ball_launched and
            launch_dir and init_c and context.get("is_post_impact")):
        ldx, ldy = launch_dir
        ddx = c["cx"] - init_c[0]; ddy = c["cy"] - init_c[1]
        pval = ddx * ldx + ddy * ldy
        progress = pval
        allow_back = p.get("sc_allow_backward", 0.005)
        behind_initial   = pval < -allow_back
        backward_fr_prev = (prev_prog is not None and pval < prev_prog - allow_back)
        if behind_initial or backward_fr_prev:
            backward_rejected = True
            tag = "behind_initial" if behind_initial else "backward_after_launch"
            c["reason"] = f"{tag}({pval:.4f})"
            if p.get("sc_hard_reject_backward", 1.0) > 0.5:
                c["accepted"] = False
                c.update(dict(progress=progress, backward_rejected=True,
                              total_score=-999, jump_dist=jump_dist))
                return c
            else:
                penalty += p.get("sc_backward_penalty", 3.0)

    # Straight-line path constraint (Part C) — only after launch direction locked
    if (p.get("sc_straight_line", 1.0) > 0.5 and ball_launched and
            launch_dir and init_c and context.get("is_post_impact")):
        ldx, ldy = launch_dir
        dx = c["cx"] - init_c[0]; dy = c["cy"] - init_c[1]
        perp_dist = abs(dx * ldy - dy * ldx)
        resid_thresh = p.get("sc_straight_resid", 0.018)
        if perp_dist > resid_thresh:
            if p.get("sc_hard_reject_straight", 1.0) > 0.5:
                c["accepted"] = False
                c["reason"] = f"off_line({perp_dist:.4f})"
                c.update(dict(total_score=-999, jump_dist=jump_dist,
                              progress=progress, backward_rejected=backward_rejected))
                return c
            penalty += p.get("sc_straight_penalty", 4.0)

    # Per-candidate HLA gating (Part D) — only after launch direction locked
    cand_hla = None
    if (context.get("is_post_impact") and ball_launched and init_c):
        dx_norm = c["cx"] - init_c[0]; dy_norm = c["cy"] - init_c[1]
        dx_px = dx_norm * W; dy_px = dy_norm * H
        mov_len = math.sqrt(dx_px**2 + dy_px**2)
        if mov_len > 1e-6:
            theta = math.radians(context.get("zero_deg", 0))
            ref_x = math.cos(theta); ref_y = -math.sin(theta)
            perp_x = math.sin(theta); perp_y = math.cos(theta)
            fwd = dx_px*ref_x + dy_px*ref_y
            lat = dx_px*perp_x + dy_px*perp_y
            cand_hla = math.degrees(math.atan2(lat, fwd))
            max_hla = p.get("sc_max_cand_hla", 35.0)
            if p.get("sc_hard_reject_hla", 1.0) > 0.5 and abs(cand_hla) > max_hla:
                c["accepted"] = False
                c["reason"] = f"hla({cand_hla:.1f}deg)"
                c.update(dict(total_score=-999, cand_hla=cand_hla, jump_dist=jump_dist,
                              progress=progress, backward_rejected=backward_rejected))
                return c
            elif abs(cand_hla) > p.get("sc_hla_soft_warn", 20.0):
                penalty += p.get("sc_hla_penalty", 2.0)

    # Part E — HLA closeness scoring: prefer candidates with HLA closer to 0°
    hla_closeness_score = 0.0
    if cand_hla is not None:
        max_hla_ref = max(float(p.get("sc_max_cand_hla", 35.0)), 1e-6)
        hla_closeness_score = max(0.0, 1.0 - abs(cand_hla) / max_hla_ref)

    # Part E line-fit boost: reward candidates close to fitted ball path line
    line_fit_boost_score = 0.0
    if (p.get("line_fit_boost_enabled", 1.0) > 0.5 and ball_launched and
            launch_dir and init_c and context.get("is_post_impact")):
        ldx, ldy = launch_dir
        dx = c["cx"] - init_c[0]; dy = c["cy"] - init_c[1]
        perp_dist = abs(dx * ldy - dy * ldx)
        strong_thresh = float(p.get("line_fit_strong_resid_thresh", 0.008))
        prog_ok = (progress is not None and progress > 0) if p.get("line_fit_progress_required", 1.0) > 0.5 else True
        if perp_dist <= strong_thresh and prog_ok:
            line_fit_boost_score = 1.0

    # New session Part C: prediction cross boost — candidates near prediction get bonus
    pred_boost_score = 0.0
    if (p.get("enable_prediction_boost", 1.0) > 0.5 and predicted and
            context.get("is_post_impact") and not context.get("ball_terminated")):
        px_, py_ = predicted
        bx_r, by_r, bw_r, bh_r = c["rect"]
        inside = (bx_r <= px_ <= bx_r + bw_r and by_r <= py_ <= by_r + bh_r)
        if inside:
            pred_boost_score = float(p.get("prediction_inside_bonus", 4.0))
        else:
            _boost_r = float(p.get("prediction_boost_radius_norm", 0.045))
            _dx_p = c["cx"] - px_; _dy_p = c["cy"] - py_
            _pd = math.sqrt(_dx_p*_dx_p + _dy_p*_dy_p)
            if _pd <= _boost_r:
                pred_boost_score = float(p.get("prediction_near_bonus", 2.0)) * (1.0 - _pd / max(_boost_r, 1e-6))
            elif _pd > _boost_r * 2:
                penalty += float(p.get("prediction_dist_penalty_weight", 3.0)) * min(1.0, (_pd - _boost_r * 2) / max(_boost_r, 1e-6))

    # Part F: downward jump rejection (post-launch only)
    _vert_penalty = 0.0
    if (context.get("ball_launched") and context.get("prev_pos") is not None and
            p.get("hard_reject_large_downward_jump", 1.0) > 0.5):
        _prev_cy = context["prev_pos"][1]
        _down_jump = c["cy"] - _prev_cy   # positive = down in image
        _max_down = float(p.get("max_downward_jump_per_frame", 0.040))
        if _down_jump > _max_down:
            c["accepted"] = False
            c["reason"] = f"rejected_large_downward_jump({_down_jump:.4f})"
            c.update(dict(total_score=-999, jump_dist=jump_dist, progress=progress,
                          backward_rejected=backward_rejected))
            return c
        elif _down_jump > _max_down * 0.5:
            _vert_penalty = float(p.get("vertical_jump_penalty_weight", 4.0)) * (_down_jump / max(_max_down, 1e-6))
    penalty += _vert_penalty

    # Part C: offscreen/edge rejection
    if p.get("reject_edge_partial_ball", 1.0) > 0.5 and context.get("is_post_impact"):
        _margin = float(p.get("min_ball_margin_norm", 0.012))
        _radius = dia / 2.0
        _edge_fail = (c["cx"] - _radius < _margin or c["cx"] + _radius > 1.0 - _margin or
                      c["cy"] - _radius < _margin or c["cy"] + _radius > 1.0 - _margin)
        if _edge_fail:
            c["accepted"] = False
            c["reason"] = f"rejected_partial_offscreen_ball"
            c.update(dict(total_score=-999, jump_dist=jump_dist, progress=progress, backward_rejected=backward_rejected))
            return c

    total = (p.get("sc_bright_w",0.5)*bright_score + p.get("sc_size_w",2.0)*size_score +
             p.get("sc_dist_w",2.5)*dist_score     + p.get("sc_motion_w",1.5)*motion_score +
             p.get("sc_dir_w",1.0)*dir_score       + p.get("sc_shape_w",0.5)*shape_score +
             p.get("sc_diam_w",2.0)*dia_score +
             p.get("sc_hla_closeness_w",3.0)*hla_closeness_score +
             p.get("line_fit_boost_weight",3.0)*line_fit_boost_score +
             pred_boost_score) - penalty
    c.update(dict(total_score=total, bright_score=bright_score, size_score=size_score,
                  dist_score=dist_score, motion_score=motion_score, dir_score=dir_score,
                  shape_score=shape_score, dia_score=dia_score, penalty=penalty,
                  jump_dist=jump_dist, progress=progress, backward_rejected=backward_rejected,
                  cand_hla=cand_hla, hla_closeness_score=hla_closeness_score,
                  line_fit_boost_score=line_fit_boost_score, pred_boost_score=pred_boost_score))
    return c

# ── Candidate finder ──────────────────────────────────────────────────────────
def find_candidates(img_norm, roi, bright_thresh, spread_thresh, min_samples,
                    min_nw, max_nw, min_nh, max_nh, min_asp, max_asp, stride,
                    context=None, p=None):
    x0n, y0n, wn, hn = roi
    x0 = max(0, int(x0n*W)); x1 = min(W, int((x0n+wn)*W))
    y0 = max(0, int(y0n*H)); y1 = min(H, int((y0n+hn)*H))
    if x1 <= x0 or y1 <= y0: return [], None, None
    patch = (img_norm[y0:y1:stride, x0:x1:stride]*255).astype(np.int32)
    r_, g_, b_ = patch[...,0], patch[...,1], patch[...,2]
    brightness = (r_+g_+b_)//3
    spread = np.maximum(np.maximum(r_,g_),b_) - np.minimum(np.minimum(r_,g_),b_)
    bright_mask = (brightness >= bright_thresh) & (spread <= spread_thresh)
    rows, cols = bright_mask.shape
    visited = np.zeros_like(bright_mask, dtype=bool)
    candidates = []
    for sr in range(rows):
        for sc in range(cols):
            if not bright_mask[sr,sc] or visited[sr,sc]: continue
            q = deque([(sr,sc)]); visited[sr,sc] = True; pxs, pys = [], []
            while q:
                cr, cc = q.popleft()
                py = y0+cr*stride; px = x0+cc*stride
                pxs.append(px); pys.append(py)
                for dr, dc in [(-1,0),(1,0),(0,-1),(0,1)]:
                    nr, nc = cr+dr, cc+dc
                    if 0<=nr<rows and 0<=nc<cols and bright_mask[nr,nc] and not visited[nr,nc]:
                        visited[nr,nc] = True; q.append((nr,nc))
            count = len(pxs)
            bw = (max(pxs)-min(pxs)+stride)/W; bh = (max(pys)-min(pys)+stride)/H
            asp = bw/max(bh, 1e-6)
            cx_ = np.mean(pxs)/W; cy_ = np.mean(pys)/H
            dia = (bw+bh)/2; conf = min(1.0, count/(min_samples*4))
            reason = None
            if   count < min_samples: reason = f"few_px({count})"
            elif bw < min_nw:         reason = f"w_small({bw:.4f})"
            elif bw > max_nw:         reason = f"w_large({bw:.4f})"
            elif bh < min_nh:         reason = f"h_small({bh:.4f})"
            elif bh > max_nh:         reason = f"h_large({bh:.4f})"
            elif asp < min_asp:       reason = f"asp_low({asp:.2f})"
            elif asp > max_asp:       reason = f"asp_high({asp:.2f})"
            candidates.append(dict(cx=cx_, cy=cy_, dia=dia, conf=conf, count=count,
                rect=(min(pxs)/W, min(pys)/H, bw, bh),
                accepted=(reason is None), reason=reason))
    eligible = [c for c in candidates if c["accepted"]]
    if eligible and context is not None and p is not None:
        for c in eligible:
            score_candidate(c, context, p)
        eligible = [c for c in eligible if c.get("accepted", True)]
        eligible_sorted = sorted(eligible, key=lambda c: c.get("total_score", 0.0), reverse=True)
        jd = eligible_sorted[0].get("jump_dist") if eligible_sorted else None
        return candidates, eligible_sorted, jd
    return candidates, ([eligible[0]] if eligible else []), None

# ── Cone/wedge geometry helper (Part C) ──────────────────────────────────────
def is_inside_cone(cx, cy, cone_origin, cone_dir_rad, cone_half_rad, cone_length, cone_backward):
    """Return True if (cx,cy) is inside the forward cone."""
    ox, oy = cone_origin
    dx = cx - ox; dy = cy - oy
    # Project onto cone forward direction and perpendicular
    fwd = dx * math.cos(cone_dir_rad) - dy * math.sin(cone_dir_rad)
    # Must not be too far backward
    if fwd < -cone_backward:
        return False
    dist = math.sqrt(dx*dx + dy*dy)
    if dist > cone_length + 0.01:
        return False
    if dist < 1e-6:
        return True
    angle = math.acos(max(-1.0, min(1.0, fwd / dist)))
    return angle <= cone_half_rad

# ── Preliminary mask scoring (Part D) ────────────────────────────────────────
def prelim_mask_score_candidate(c, img_norm, p):
    """Quick BW mask quality check for candidate scoring. Returns dict of prelim metrics."""
    scale = float(p.get("prelim_mask_window_scale", 1.6))
    # Call mask_refine_diameter with smaller window
    mdia, _, _, _, reason, _, _, px_count, fill, bright, aspect = \
        mask_refine_diameter(img_norm, c["cx"], c["cy"], c["dia"], p=p, window_scale=scale)
    if px_count == 0:
        return dict(prelim_pixels=0, prelim_fill=0.0, prelim_aspect=1.0,
                    prelim_ok=False, prelim_reason="no_pixels", prelim_score=-5.0,
                    prelim_is_line_like=False)
    _line_asp = float(p.get("prelim_line_like_aspect", 3.0))
    _line_fill = float(p.get("prelim_line_like_fill_max", 0.18))
    _min_px = int(p.get("prelim_min_mask_pixels", 8))
    _min_fill = float(p.get("prelim_min_fill_ratio", 0.06))
    _max_asp = float(p.get("prelim_max_aspect", 2.2))
    _min_asp = float(p.get("prelim_min_aspect", 0.45))

    is_line_like = (aspect > _line_asp or aspect < 1.0/_line_asp) and fill < _line_fill
    is_too_small = px_count < _min_px
    is_bad_aspect = aspect > _max_asp or aspect < _min_asp

    score = 0.0
    reason_out = "ok"
    if is_line_like:
        score = -8.0; reason_out = "rejected_prelim_line_like_mask"
    elif is_too_small:
        score = -4.0; reason_out = "rejected_prelim_tiny_mask"
    elif is_bad_aspect:
        score = -2.0; reason_out = "rejected_prelim_not_round"
    else:
        # Good round mask — bonus
        roundness = 1.0 - abs(aspect - 1.0) / max(1.0, abs(_max_asp - 1.0))
        fill_score = min(1.0, fill / 0.5)
        score = float(p.get("prelim_roundness_weight", 5.0)) * roundness * fill_score

    return dict(prelim_pixels=px_count, prelim_fill=fill, prelim_aspect=aspect,
                prelim_ok=not (is_line_like or is_too_small),
                prelim_reason=reason_out, prelim_score=score,
                prelim_is_line_like=is_line_like)

# ── Ball tracking pass ────────────────────────────────────────────────────────
def run_tracking_pass(frames_norm, p, impact, locked):
    lx, ly, lw, lh = locked
    init_center = (lx+lw/2, ly+lh/2)
    last_pre = init_center; last_post = None
    results = []; recent_dias = deque(maxlen=max(2, int(p['smooth_window'])))
    # Scoring state
    recent_post_points = deque(maxlen=max(2, int(p.get('sc_lookback', 3)) + 1))
    expected_diameter = None; expected_direction = None; post_miss_count = 0
    pre_final_dias = []; sc_dir_alpha = float(p.get('sc_dir_alpha', 0.35))
    # Part B: diameter gate state
    previous_valid_diameter = None; pre_impact_median_diameter = None
    max_growth_ratio = float(p.get("max_diam_growth_ratio", 1.35))
    max_preimpact_ratio = float(p.get("max_diam_ratio_to_pre_impact", 1.75))
    hard_clamp_diam = float(p.get("hard_clamp_diameter", 1.0)) > 0.5
    # Launch direction / termination state (Parts A–C)
    launch_dir = None; ball_launched = False; launch_frame = None
    max_progress = 0.0; prev_progress = None
    consec_misses_after_launch = 0; ball_terminated = False; term_frame = None
    # Part C: suspicious fallback state
    last_chosen_pos = None; stationary_count = 0
    # Part D: static false-object memory
    static_positions = {}; static_reject_set = set()
    _static_gs = float(p.get("static_pos_tolerance", 0.008))
    # New session Part D: rescue pass counter
    rescued_count = 0
    # New session Part F: prediction disable state
    prediction_miss_count = 0; prediction_disabled = False; prediction_disabled_frame = None
    # New session Part K: rejection counters for JSON export
    _mask_quality_rejected = 0; _tiny_weak_rejected = 0
    _merged_clubball_rejected = 0; _pred_boost_applied = 0
    _off_path_rejected = 0
    # Part C: cone filter counter; Part F: vertical jump rejection counter
    _cone_rejected_total = 0; _vert_jump_rejected = 0
    # Prediction cross rescue state
    _pred_rescue_consec_misses = 0
    _pred_rescue_attempted = 0
    _pred_rescue_success = 0
    _pred_rescue_rejected_weak = 0
    _edge_rejected_count = 0
    _edge_rejected_frames = []
    # Part D: line-like mask rejection counter; Part E: single-point prediction counter
    _line_like_rejected = 0
    _single_point_pred_count = 0
    # Part C (new): near-impact diameter jump guard
    _near_impact_diam_guard_rejected = 0
    # Part E (new): first post-impact clean point flag
    _first_post_clean = None

    for i, img in enumerate(frames_norm):
        idx = i
        if idx < impact:   scale = p["pre_scale"];    cfg = "pre"
        elif idx == impact: scale = p["impact_scale"]; cfg = "pre"
        else:
            offset = idx-impact
            scale = min(p["post_max_scale"], p["post_base_scale"]+offset*p["post_growth"])
            cfg = "post"

        # Part C: all frames after termination output as miss
        if ball_terminated and p.get("sc_termination", 1.0) > 0.5 and idx > impact:
            center = last_post if last_post else last_pre
            cx_r, cy_r = center
            rw = lw*scale; rh = lh*scale
            roi = (max(0,cx_r-rw/2), max(0,cy_r-rh/2),
                   min(1,cx_r+rw/2)-max(0,cx_r-rw/2),
                   min(1,cy_r+rh/2)-max(0,cy_r-rh/2))
            results.append(dict(idx=idx, roi=roi, candidates=[], chosen=None,
                mask_dia=None, preview=None, cand_in_crop=None, ref_in_crop=None,
                mask_center=None, mask_center_in_crop=None, mask_count=0,
                mask_fill_ratio=0.0, mask_brightness_mean=0.0,
                mask_reason="terminated", final_dia=None, predicted_pos=None,
                jump_dist=None, expected_diameter=expected_diameter,
                launch_dir=launch_dir, ball_launched=ball_launched,
                launch_frame=launch_frame, max_progress=max_progress,
                prev_progress=prev_progress, ball_terminated=True,
                prediction_disabled=prediction_disabled,
                prediction_disabled_frame=prediction_disabled_frame,
                rescued=False))
            continue

        if cfg == "post" and expected_diameter is None and pre_final_dias:
            sorted_pd = sorted(pre_final_dias)
            expected_diameter = sorted_pd[len(sorted_pd) // 2]
        center = last_post if (cfg=="post" and last_post) else last_pre
        cx_r, cy_r = center
        # Part F: asymmetric pre-impact ROI — expand forward, backward, and vertically
        if p.get("use_asymmetric_roi", 1.0) > 0.5 and cfg == "pre":
            near = abs(idx - impact) <= int(p.get("near_impact_window", 4))
            fwd_mul  = p.get("near_fwd_scale",  10.0) if near else p.get("pre_fwd_scale",  5.5)
            bwd_mul  = p.get("near_bwd_scale",   2.5) if near else p.get("pre_bwd_scale",  1.8)
            vert_mul = p.get("near_vert_scale",  4.0) if near else p.get("pre_vert_scale", 2.5)
            theta_roi = math.radians(p.get("zero_deg", 0))
            fx_ = math.cos(theta_roi); fy_ = -math.sin(theta_roi)  # forward unit
            px_ = -fy_; py_ = fx_                                   # perp unit
            base = lw  # base unit = locked ball half-width
            # Axis-aligned bounding box of oriented ROI with separate vertical expansion
            corners_x = [cx_r - bwd_mul*base*fx_ - vert_mul*base*px_,
                          cx_r + fwd_mul*base*fx_ - vert_mul*base*px_,
                          cx_r + fwd_mul*base*fx_ + vert_mul*base*px_,
                          cx_r - bwd_mul*base*fx_ + vert_mul*base*px_]
            corners_y = [cy_r - bwd_mul*base*fy_ - vert_mul*base*py_,
                          cy_r + fwd_mul*base*fy_ - vert_mul*base*py_,
                          cy_r + fwd_mul*base*fy_ + vert_mul*base*py_,
                          cy_r - bwd_mul*base*fy_ + vert_mul*base*py_]
            x0 = max(0.0, min(corners_x)); x1 = min(1.0, max(corners_x))
            y0 = max(0.0, min(corners_y)); y1 = min(1.0, max(corners_y))
            roi = (x0, y0, x1-x0, y1-y0)
        elif cfg == "post":
            # Part A: asymmetric post-impact search — wide forward, narrow vertical
            _n_clean = len([r for r in results if r.get("idx", -1) >= impact and r.get("chosen") and not r.get("likely_merged_club_ball") and not r.get("excluded_from_metrics_merged")])
            _reliable_track = _n_clean >= int(p.get("reliable_track_min_points", 2))
            fwd_mul  = float(p.get("post_fwd_scale", 10.0))
            bwd_mul  = float(p.get("post_bwd_scale", 1.2))
            if _reliable_track:
                vert_mul = float(p.get("post_vert_scale_tracked", 2.5))
            else:
                vert_mul = float(p.get("post_vert_scale_untracked", 1.5))
            # Use launch direction if available, else zero_deg
            if launch_dir is not None:
                _ldx, _ldy = launch_dir
                theta_post = math.atan2(-_ldy, _ldx)
            else:
                theta_post = math.radians(p.get("zero_deg", 0))
            fx_ = math.cos(theta_post); fy_ = -math.sin(theta_post)
            px_ = -fy_; py_ = fx_
            base = lw
            corners_x = [cx_r - bwd_mul*base*fx_ - vert_mul*base*px_,
                          cx_r + fwd_mul*base*fx_ - vert_mul*base*px_,
                          cx_r + fwd_mul*base*fx_ + vert_mul*base*px_,
                          cx_r - bwd_mul*base*fx_ + vert_mul*base*px_]
            corners_y = [cy_r - bwd_mul*base*fy_ - vert_mul*base*py_,
                          cy_r + fwd_mul*base*fy_ - vert_mul*base*py_,
                          cy_r + fwd_mul*base*fy_ + vert_mul*base*py_,
                          cy_r - bwd_mul*base*fy_ + vert_mul*base*py_]
            x0 = max(0.0, min(corners_x)); x1 = min(1.0, max(corners_x))
            y0 = max(0.0, min(corners_y)); y1 = min(1.0, max(corners_y))
            roi = (x0, y0, x1-x0, y1-y0)
        else:
            rw = lw*scale; rh = lh*scale
            roi = (max(0,cx_r-rw/2), max(0,cy_r-rh/2),
                   min(1,cx_r+rw/2)-max(0,cx_r-rw/2),
                   min(1,cy_r+rh/2)-max(0,cy_r-rh/2))
        bt = p["pre_bright"] if cfg=="pre" else p["post_bright"]
        sp = p["pre_spread"] if cfg=="pre" else p["post_spread"]
        ms = int(p["pre_min_samples"]) if cfg=="pre" else int(p["post_min_samples"])
        predicted_pos = None; _pred_mode = None
        _enable_single_pt = p.get("enable_single_point_prediction", 1.0) > 0.5
        if cfg == "post" and len(recent_post_points) >= 2:
            predicted_pos, _pred_mode = compute_predicted(recent_post_points, int(p.get('sc_lookback', 3)),
                                                          init_center=init_center)
        elif cfg == "post" and len(recent_post_points) == 1 and _enable_single_pt and init_center is not None:
            # Part E (new): gate single-point prediction on clean first point
            _allow_single_pt = (p.get("require_clean_first_point_for_prediction", 1.0) < 0.5 or
                                 _first_post_clean)
            if _allow_single_pt:
                predicted_pos, _pred_mode = compute_predicted(recent_post_points, int(p.get('sc_lookback', 3)),
                                                              init_center=init_center)
            else:
                predicted_pos = None; _pred_mode = "disabled_dirty_first_point"
        # New session Part F: disable prediction cross after N consecutive post-launch misses
        if (prediction_disabled and p.get("disable_prediction_after_miss", 1.0) > 0.5
                and cfg == "post"):
            predicted_pos = None; _pred_mode = None
        ctx = dict(preferred_center=center, predicted_pos=predicted_pos,
                   expected_diameter=expected_diameter if cfg=="post" else None,
                   expected_direction=expected_direction if cfg=="post" else None,
                   is_post_impact=(cfg=="post"), miss_count=post_miss_count,
                   launch_dir=launch_dir if cfg=="post" else None,
                   prev_progress=prev_progress if cfg=="post" else None,
                   ball_launched=ball_launched if cfg=="post" else False,
                   init_center=init_center,
                   zero_deg=p.get("zero_deg", 0),
                   prev_pos=(last_post[0], last_post[1]) if (last_post and cfg=="post") else None)
        all_raw_candidates, eligible_sorted, jump_dist = find_candidates(img, roi, int(bt), int(sp), ms,
            p["pre_min_nw"] if cfg=="pre" else p["post_min_nw"],
            p["pre_max_nw"] if cfg=="pre" else p["post_max_nw"],
            p["pre_min_nh"] if cfg=="pre" else p["post_min_nh"],
            p["pre_max_nh"] if cfg=="pre" else p["post_max_nh"],
            p["pre_min_asp"] if cfg=="pre" else p["post_min_asp"],
            p["pre_max_asp"] if cfg=="pre" else p["post_max_asp"],
            int(p["stride"]), context=ctx, p=p)

        # Part D: filter static false objects from candidate pool
        if p.get("enable_static_false_object_memory", 1.0) > 0.5 and static_reject_set and cfg == "post":
            non_static = [c for c in eligible_sorted if
                (round(c["cx"]/_static_gs), round(c["cy"]/_static_gs)) not in static_reject_set]
            if non_static:
                eligible_sorted = non_static

        # Part C: cone/wedge candidate filter for post-impact
        _cone_rejected_count = 0; _cone_miss = False
        if (cfg == "post" and p.get("use_cone_search", 1.0) > 0.5 and eligible_sorted):
            _cone_org = last_post if last_post else init_center
            _zero_rad = math.radians(p.get("zero_deg", 0))
            if p.get("cone_use_launch_dir", 1.0) > 0.5 and launch_dir is not None:
                _cdx, _cdy = launch_dir
                _cone_dir_rad = math.atan2(-_cdy, _cdx)
            else:
                _cone_dir_rad = _zero_rad
            _cone_half_rad = math.radians(float(p.get("cone_half_angle_deg", 18.0)))
            _cone_frame = max(0, idx - impact)
            _cone_len = min(
                float(p.get("cone_max_length_norm", 0.75)),
                float(p.get("cone_initial_length_norm", 0.12)) + _cone_frame * float(p.get("cone_length_growth_per_frame", 0.035))
            )
            _cone_bwd = float(p.get("cone_backward_allowance", 0.015))
            _cone_filtered = []
            for _cc in eligible_sorted:
                if is_inside_cone(_cc["cx"], _cc["cy"], _cone_org, _cone_dir_rad,
                                  _cone_half_rad, _cone_len, _cone_bwd):
                    _cone_filtered.append(_cc)
                else:
                    _cc["reason"] = "rejected_outside_cone"
                    _cc["accepted"] = False
                    _cone_rejected_count += 1
            if _cone_filtered:
                eligible_sorted = _cone_filtered
            else:
                _cone_miss = (len(eligible_sorted) > 0)
        _cone_rejected_total += _cone_rejected_count

        # Part F: fitted path vertical gate (post-launch, after cone filter)
        if (cfg == "post" and ball_launched and launch_dir and init_center and
                p.get("use_fitted_path_for_vertical_gate", 1.0) > 0.5 and eligible_sorted):
            _ldx, _ldy = launch_dir
            _max_vj = float(p.get("max_vertical_jump_from_path", 0.050))
            _vj_rejected_this = []
            _vj_kept = []
            for _vc in eligible_sorted:
                _dx2 = _vc["cx"] - init_center[0]
                _dy2 = _vc["cy"] - init_center[1]
                _perp = _dx2 * _ldy - _dy2 * _ldx
                if _perp > _max_vj:
                    _vc["reason"] = f"rejected_below_launch_path({_perp:.4f})"
                    _vc["accepted"] = False
                    _vj_rejected_this.append(_vc)
                    _vert_jump_rejected += 1
                else:
                    _vj_kept.append(_vc)
            if _vj_kept:
                eligible_sorted = _vj_kept

        # Part D: full-frame recovery if cone found no valid candidates
        if (_cone_miss and p.get("enable_full_frame_recovery", 1.0) > 0.5 and cfg == "post"):
            _full_roi = (0.0, 0.0, 1.0, 1.0)
            _full_cands, _full_eligible, _ = find_candidates(
                img, _full_roi,
                int(p.get("post_bright", 92)), int(p["post_spread"]), int(p["post_min_samples"]),
                p["post_min_nw"], p["post_max_nw"], p["post_min_nh"], p["post_max_nh"],
                p["post_min_asp"], p["post_max_asp"], int(p["stride"]),
                context=ctx, p=p
            )
            _recovery_eligible = []
            for _rc in (_full_eligible or []):
                _in_cone = is_inside_cone(_rc["cx"], _rc["cy"], _cone_org, _cone_dir_rad,
                                          _cone_half_rad, _cone_len * 2.0, _cone_bwd * 3.0)
                _near_pred = False
                if predicted_pos:
                    _pd2 = math.sqrt((_rc["cx"]-predicted_pos[0])**2 + (_rc["cy"]-predicted_pos[1])**2)
                    _near_pred = _pd2 < 0.08
                if not (_in_cone or _near_pred):
                    continue
                if ball_launched and launch_dir and init_center:
                    _ldx2, _ldy2 = launch_dir
                    _dp2 = (_rc["cx"]-init_center[0])*_ldx2 + (_rc["cy"]-init_center[1])*(-_ldy2)
                    if _dp2 < -float(p.get("cone_backward_allowance", 0.015)):
                        continue
                _rc["reason"] = "recovery_candidate_accepted"
                _recovery_eligible.append(_rc)
            if _recovery_eligible:
                eligible_sorted = _recovery_eligible

        # Part D (new): preliminary mask scoring pass — run before fallback loop
        if p.get("enable_prelim_mask_scoring", 1.0) > 0.5 and eligible_sorted and cfg == "post":
            for _pc in eligible_sorted:
                _pm = prelim_mask_score_candidate(_pc, img, p)
                _pc["prelim_mask"] = _pm
                # Apply to total_score
                _prev_score = _pc.get("total_score", 0.0)
                _pc["total_score"] = _prev_score + _pm["prelim_score"]
                if _pm["prelim_is_line_like"] and p.get("prelim_reject_line_like", 1.0) > 0.5:
                    _pc["accepted"] = False
                    _pc["reason"] = _pm["prelim_reason"]
            # Re-sort after score adjustment
            eligible_sorted = sorted(eligible_sorted, key=lambda x: x.get("total_score", 0), reverse=True)
            eligible_sorted_accepted = [c for c in eligible_sorted if c.get("accepted", True)]
            if eligible_sorted_accepted:
                eligible_sorted = eligible_sorted_accepted + [c for c in eligible_sorted if not c.get("accepted", True)]

        mask_dia=None; preview=None; cand_in_crop=None; ref_in_crop=None
        mask_reason="disabled"; mask_center=None; mask_center_in_crop=None; mask_count=0
        mask_fill_ratio=0.0; mask_brightness_mean=0.0; mask_aspect_ratio=1.0
        chosen = None
        max_fallback = int(p.get("max_fallback_candidates", 8)) if cfg == "post" else 1

        for _attempt, _cand in enumerate(eligible_sorted[:max_fallback]):
            # Part C: suspicious-selection fallback — try second-best if first is suspicious
            if (_attempt == 0 and p.get("enable_suspicious_fallback", 1.0) > 0.5 and
                    cfg == "post" and len(eligible_sorted) > 1):
                _suspicious = False
                # Stationarity check
                if last_chosen_pos is not None:
                    _ddx = _cand["cx"] - last_chosen_pos[0]
                    _ddy = _cand["cy"] - last_chosen_pos[1]
                    _dist = math.sqrt(_ddx*_ddx + _ddy*_ddy)
                    if _dist < float(p.get("stationary_motion_thresh", 0.004)):
                        if stationary_count >= int(p.get("stationary_frame_limit", 2)):
                            _suspicious = True
                # Predicted distance check
                if not _suspicious and predicted_pos:
                    _pd = math.sqrt((_cand["cx"]-predicted_pos[0])**2 +
                                    (_cand["cy"]-predicted_pos[1])**2)
                    if _pd > float(p.get("max_pred_dist_before_fallback", 0.080)):
                        _suspicious = True
                # Forward progress check
                if not _suspicious:
                    _prog = _cand.get("progress")
                    if _prog is not None and _prog < float(p.get("min_fwd_prog_before_fallback", -0.002)):
                        _suspicious = True
                # Off-line check (after ball launched)
                if not _suspicious and ball_launched and launch_dir and init_center:
                    _ldx, _ldy = launch_dir
                    _dx = _cand["cx"] - init_center[0]; _dy = _cand["cy"] - init_center[1]
                    _perp = abs(_dx * _ldy - _dy * _ldx)
                    if _perp > float(p.get("max_line_resid_before_fallback", 0.030)):
                        _suspicious = True
                if _suspicious:
                    continue

            # New session Part B: merged club-ball rejection — first N post-impact frames
            post_offset = idx - impact if cfg == "post" else 0
            if (p.get("enable_merged_reject", 1.0) > 0.5 and cfg == "post" and
                    post_offset <= int(p.get("merged_candidate_frame_window", 3)) and
                    expected_diameter is not None and expected_diameter > 0):
                _max_merged_r = float(p.get("max_first_postimpact_diam_ratio", 1.85))
                if _cand["dia"] > expected_diameter * _max_merged_r:
                    _cand["reason"] = f"rejected_merged_club_ball({_cand['dia']/expected_diameter:.2f}x)"
                    _cand["accepted"] = False
                    _merged_clubball_rejected += 1
                    if _attempt < len(eligible_sorted) - 1:
                        mask_dia = None; chosen = None; continue
                    else:
                        break

            # New session Part E: off-path hard rejection after launch (very large deviations)
            if (p.get("hard_reject_far_off_path", 1.0) > 0.5 and ball_launched and
                    launch_dir and init_center and cfg == "post"):
                _ldx, _ldy = launch_dir
                _dx = _cand["cx"] - init_center[0]; _dy = _cand["cy"] - init_center[1]
                _perp = abs(_dx * _ldy - _dy * _ldx)
                _max_off = float(p.get("max_off_path_dist_norm", 0.060))
                if _perp > _max_off:
                    _cand["reason"] = f"rejected_far_right_off_path({_perp:.4f})"
                    _cand["accepted"] = False
                    _off_path_rejected += 1
                    if _attempt < len(eligible_sorted) - 1:
                        mask_dia = None; chosen = None; continue
                    else:
                        break

            # Run mask refinement
            mask_dia, preview, cand_in_crop, ref_in_crop, mask_reason, \
                mask_center, mask_center_in_crop, mask_count, \
                mask_fill_ratio, mask_brightness_mean, mask_aspect_ratio = \
                mask_refine_diameter(img, _cand['cx'], _cand['cy'], _cand['dia'], p=p)

            # Part B / new session Part A: mask quality gate — reject weak/tiny detections
            if (p.get("require_min_mask_quality", 1.0) > 0.5 and cfg == "post"):
                _only_after_launch = p.get("hard_reject_tiny_weak", 1.0) > 0.5
                _do_quality = (not _only_after_launch) or ball_launched
                if _do_quality:
                    _min_px = int(p.get("min_mask_white_pixels", 18))
                    _min_fill = float(p.get("min_mask_white_fill_ratio", 0.10))
                    _min_bright = float(p.get("min_mask_brightness_mean", 120))
                    _quality_fail = (mask_count > 0 and (
                        mask_count < _min_px or
                        mask_fill_ratio < _min_fill or
                        mask_brightness_mean < _min_bright))
                    # Also check refined diameter ratio vs expected
                    if not _quality_fail and mask_dia is not None and expected_diameter and expected_diameter > 0:
                        _ref_r = mask_dia / expected_diameter
                        _min_ref = float(p.get("min_post_impact_refined_diam_ratio", 0.45))
                        if _ref_r < _min_ref:
                            _quality_fail = True
                            _cand["reason"] = f"rejected_tiny_refined_diameter({_ref_r:.2f})"
                    if _quality_fail:
                        _mask_quality_rejected += 1
                        if mask_count < int(p.get("min_mask_white_pixels", 18)):
                            _tiny_weak_rejected += 1
                        if _attempt < len(eligible_sorted) - 1:
                            mask_dia = None; chosen = None; continue

            # Part D: line-like mask rejection
            if p.get("reject_line_like_mask", 1.0) > 0.5 and mask_count > 0:
                _max_asp = float(p.get("max_mask_aspect_for_ball", 2.2))
                _min_asp = float(p.get("min_mask_aspect_for_ball", 0.45))
                _line_asp = float(p.get("line_like_aspect_threshold", 3.0))
                _line_fill = float(p.get("line_like_fill_max", 0.18))
                _is_line_like = (mask_aspect_ratio > _line_asp or mask_aspect_ratio < 1.0/_line_asp) and mask_fill_ratio < _line_fill
                _is_bad_aspect = mask_aspect_ratio > _max_asp or mask_aspect_ratio < _min_asp
                if _is_line_like:
                    _cand["reason"] = f"rejected_line_like_mask(asp={mask_aspect_ratio:.2f},fill={mask_fill_ratio:.3f})"
                    _cand["accepted"] = False
                    _mask_quality_rejected += 1
                    _line_like_rejected += 1
                    if _attempt < len(eligible_sorted) - 1:
                        mask_dia = None; chosen = None; continue

            # Part C (new): near-impact diameter jump guard
            if p.get("enable_near_impact_diam_guard", 1.0) > 0.5:
                _guard_window = int(p.get("near_impact_diam_guard_window", 2))
                _is_near_impact = (cfg == "post" and idx <= impact + _guard_window)
                if _is_near_impact:
                    _ref_diam = pre_impact_median_diameter or previous_valid_diameter
                    if _ref_diam is not None and _ref_diam > 0:
                        _cand_d = mask_dia if mask_dia is not None else _cand["dia"]
                        _growth = _cand_d / _ref_diam
                        _shrink = _cand_d / _ref_diam
                        _max_growth = float(p.get("near_impact_max_diam_growth", 1.50))
                        _min_shrink = float(p.get("near_impact_min_diam_shrink", 0.80))
                        if _growth > _max_growth:
                            _cand["reason"] = f"rejected_near_impact_growth_spike({_growth:.2f}x)"
                            _cand["accepted"] = False
                            _near_impact_diam_guard_rejected += 1
                            if _attempt < len(eligible_sorted) - 1:
                                mask_dia = None; chosen = None; continue
                            else:
                                break
                        elif _shrink < _min_shrink and previous_valid_diameter is not None:
                            _cand["reason"] = f"rejected_near_impact_shrink_spike({_shrink:.2f}x)"
                            _cand["accepted"] = False
                            _near_impact_diam_guard_rejected += 1
                            if _attempt < len(eligible_sorted) - 1:
                                mask_dia = None; chosen = None; continue
                            else:
                                break

            chosen = _cand
            if chosen.get("pred_boost_score", 0.0) > 0:
                _pred_boost_applied += 1
            jump_dist = _cand.get("jump_dist")
            break

        # New session Part D: rescue pass — if no candidate found, try all with rescue scoring
        _rescued_this_frame = False
        if (chosen is None and p.get("enable_rescue_pass", 1.0) > 0.5 and
                cfg == "post" and ball_launched):
            _rescue_r_line = float(p.get("rescue_line_resid_thresh", 0.014))
            _rescue_r_pred = float(p.get("rescue_pred_dist_thresh", 0.050))
            _rescue_min_px = int(p.get("rescue_min_mask_pixels", 18))
            _rescue_min_dr = float(p.get("rescue_min_diam_ratio", 0.45))
            _rescue_max = int(p.get("rescue_max_candidates", 6))
            _rescue_pool = [c for c in eligible_sorted[:_rescue_max]
                            if not c.get("reason", "").startswith("rejected_far_right") and
                            not c.get("reason", "").startswith("rejected_merged")]
            _best_rescue = None; _best_rescue_score = -999
            for _rc in _rescue_pool:
                _rs = 0.0
                if predicted_pos:
                    _rdx = _rc["cx"] - predicted_pos[0]; _rdy = _rc["cy"] - predicted_pos[1]
                    _rpd = math.sqrt(_rdx*_rdx + _rdy*_rdy)
                    if _rpd > _rescue_r_pred:
                        continue
                    _rs += max(0.0, 1.0 - _rpd / max(_rescue_r_pred, 1e-6)) * 3.0
                if launch_dir and init_center:
                    _rldx, _rldy = launch_dir
                    _rdx2 = _rc["cx"] - init_center[0]; _rdy2 = _rc["cy"] - init_center[1]
                    _rperp = abs(_rdx2 * _rldy - _rdy2 * _rldx)
                    if _rperp > _rescue_r_line:
                        continue
                    _rs += max(0.0, 1.0 - _rperp / max(_rescue_r_line, 1e-6)) * 2.0
                _r_mask_dia, _r_prev, _r_cic, _r_ric, _r_mr, _r_mc, _r_mcic, \
                    _r_cnt, _r_fill, _r_bright, _r_asp = \
                    mask_refine_diameter(img, _rc["cx"], _rc["cy"], _rc["dia"], p=p)
                if _r_cnt < _rescue_min_px:
                    continue
                if _r_mask_dia is not None and expected_diameter and expected_diameter > 0:
                    if _r_mask_dia / expected_diameter < _rescue_min_dr:
                        continue
                _rs += _r_fill * 1.0 + min(1.0, _r_cnt / 30.0)
                if _rs > _best_rescue_score:
                    _best_rescue_score = _rs
                    _best_rescue = (_rc, _r_mask_dia, _r_prev, _r_cic, _r_ric,
                                    _r_mr, _r_mc, _r_mcic, _r_cnt, _r_fill, _r_bright, _r_asp)
            if _best_rescue is not None:
                (chosen, mask_dia, preview, cand_in_crop, ref_in_crop,
                 mask_reason, mask_center, mask_center_in_crop,
                 mask_count, mask_fill_ratio, mask_brightness_mean, mask_aspect_ratio) = _best_rescue
                mask_reason = f"rescued({mask_reason})"
                jump_dist = chosen.get("jump_dist")
                _rescued_this_frame = True
                rescued_count += 1

        # Prediction cross rescue: if still no chosen, search all raw candidates
        _pred_rescue_this_frame = False
        if (chosen is None
                and p.get("enable_prediction_cross_rescue", 1.0) > 0.5
                and cfg == "post"
                and predicted_pos is not None
                and not ball_terminated
                and not (p.get("prediction_rescue_disable_after_termination", 1.0) > 0.5 and ball_terminated)):

            # Check rescue window and consecutive miss limit
            _rescue_window = int(p.get("prediction_rescue_window_frames", 12))
            _rescue_max_misses = int(p.get("prediction_rescue_max_consec_misses", 2))
            _frames_since_launch = (idx - launch_frame) if launch_frame is not None else 0
            _rescue_active = (
                (len(recent_post_points) >= 2 or ball_launched) and
                _frames_since_launch <= _rescue_window and
                _pred_rescue_consec_misses <= _rescue_max_misses and
                not ball_terminated
            )

            if _rescue_active:
                _pred_rescue_attempted += 1
                _ppx, _ppy = predicted_pos
                _rescue_radius = float(p.get("prediction_rescue_radius_norm", 0.055))
                _rescue_max_resid = float(p.get("prediction_rescue_max_line_residual", 0.025))
                _circle_scale = float(p.get("prediction_rescue_inside_circle_scale", 1.25))
                _rescue_min_px = int(p.get("prediction_rescue_min_mask_pixels", 8))
                _rescue_min_fill = float(p.get("prediction_rescue_min_fill_ratio", 0.045))
                _rescue_min_dr = float(p.get("prediction_rescue_min_diam_ratio", 0.35))
                _allow_borderline = p.get("prediction_rescue_allow_borderline_mask", 1.0) > 0.5
                _require_fwd = p.get("prediction_rescue_require_forward_progress", 1.0) > 0.5

                # Build rescue pool from ALL raw candidates (including scoring-rejected ones)
                # but exclude genuinely bad ones: merged club+ball, behind start, off-path
                _rescue_pool_all = []
                for _rc in all_raw_candidates:
                    # Skip merged club+ball
                    if "merged" in _rc.get("reason", ""):
                        continue
                    # Skip extremely tiny blobs (1-3 pixels)
                    if _rc.get("count", 0) < 4:
                        continue
                    # Skip if diameter is wildly wrong
                    if expected_diameter and expected_diameter > 0:
                        _dr = _rc["dia"] / expected_diameter
                        if _dr < 0.20 or _dr > 5.0:
                            continue
                    _rescue_pool_all.append(_rc)

                _best_pred_rescue = None
                _best_pred_rescue_score = -999.0

                for _prc in _rescue_pool_all:
                    # Compute prediction inside checks
                    _prx, _pry, _prw, _prh = _prc["rect"]
                    _inside_rect = (_prx <= _ppx <= _prx + _prw and _pry <= _ppy <= _pry + _prh)
                    _cand_radius = _prc["dia"] / 2.0
                    _pred_dist = math.sqrt((_prc["cx"] - _ppx)**2 + (_prc["cy"] - _ppy)**2)
                    _inside_circle = (_pred_dist <= _cand_radius * _circle_scale)
                    _near_pred = (_pred_dist <= _rescue_radius)

                    if not (_inside_rect or _inside_circle or _near_pred):
                        continue

                    # Check forward progress if required
                    if _require_fwd and launch_dir is not None and init_center is not None:
                        _ldx, _ldy = launch_dir
                        _fwd = (_prc["cx"] - init_center[0]) * _ldx + (_prc["cy"] - init_center[1]) * (-_ldy)
                        if _fwd < -float(p.get("cone_backward_allowance", 0.015)):
                            continue

                    # Check line residual (not wildly off path)
                    if ball_launched and launch_dir is not None and init_center is not None:
                        _ldx, _ldy = launch_dir
                        _dx = _prc["cx"] - init_center[0]; _dy = _prc["cy"] - init_center[1]
                        _perp = abs(_dx * _ldy - _dy * _ldx)
                        if _perp > _rescue_max_resid * 3.0:  # generous — 3x the normal threshold
                            continue

                    # Run mask refinement
                    _pr_mdia, _pr_prev, _pr_cic, _pr_ric, _pr_mr, _pr_mc, _pr_mcic, \
                        _pr_cnt, _pr_fill, _pr_bright, _pr_asp = \
                        mask_refine_diameter(img, _prc["cx"], _prc["cy"], _prc["dia"], p=p)

                    # Part D: Reject line-like masks even in rescue
                    if p.get("reject_line_like_mask", 1.0) > 0.5:
                        _line_asp = float(p.get("line_like_aspect_threshold", 3.0))
                        _line_fill = float(p.get("line_like_fill_max", 0.18))
                        if (_pr_asp > _line_asp or _pr_asp < 1.0/_line_asp) and _pr_fill < _line_fill:
                            _prc["reason"] = "rejected_prediction_rescue_line_like_mask"
                            _line_like_rejected += 1
                            continue

                    # Quality gate: allow borderline mask if prediction is inside
                    _pred_strong = _inside_rect or _inside_circle
                    if _allow_borderline and _pred_strong:
                        _min_px_use = _rescue_min_px   # relaxed
                        _min_fill_use = _rescue_min_fill  # relaxed
                    else:
                        _min_px_use = int(p.get("min_mask_white_pixels", 18)) // 2
                        _min_fill_use = float(p.get("min_mask_white_fill_ratio", 0.10)) / 2

                    # Hard minimums: absolutely reject if way too tiny
                    if _pr_cnt < 4:
                        _pred_rescue_rejected_weak += 1
                        _prc["reason"] = "rejected_prediction_rescue_weak_mask"
                        continue
                    if _pr_cnt < _min_px_use or _pr_fill < _min_fill_use:
                        if not (_pred_strong and _pr_cnt >= 4):
                            _pred_rescue_rejected_weak += 1
                            _prc["reason"] = "rejected_prediction_rescue_borderline_mask"
                            continue

                    # Diameter ratio check
                    if expected_diameter and expected_diameter > 0:
                        _ref_dr = (_pr_mdia / expected_diameter) if _pr_mdia else (_prc["dia"] / expected_diameter)
                        if _ref_dr < _rescue_min_dr:
                            _prc["reason"] = "rejected_prediction_rescue_tiny_diameter"
                            continue

                    # Compute rescue score
                    _pr_score = 0.0
                    if _inside_rect:
                        _pr_score += float(p.get("prediction_rescue_inside_bonus", 12.0))
                    if _inside_circle:
                        _pr_score += float(p.get("prediction_rescue_inside_bonus", 12.0)) * 0.7
                    if _near_pred:
                        _pr_score += float(p.get("prediction_rescue_near_bonus", 7.0)) * (1.0 - _pred_dist / max(_rescue_radius, 1e-6))
                    _pr_score += min(1.0, _pr_cnt / 20.0) + _pr_fill * 0.5

                    if _pr_score > _best_pred_rescue_score:
                        _best_pred_rescue_score = _pr_score
                        _best_pred_rescue = (_prc, _pr_mdia, _pr_prev, _pr_cic, _pr_ric,
                                             _pr_mr, _pr_mc, _pr_mcic, _pr_cnt, _pr_fill, _pr_bright,
                                             _inside_rect, _inside_circle, _pred_dist, _pr_asp)

                if _best_pred_rescue is not None:
                    (chosen, mask_dia, preview, cand_in_crop, ref_in_crop,
                     mask_reason, mask_center, mask_center_in_crop,
                     mask_count, mask_fill_ratio, mask_brightness_mean,
                     _pr_inside_rect, _pr_inside_circle, _pr_dist, mask_aspect_ratio) = _best_pred_rescue
                    _reason_str = "rescued_prediction_inside_candidate" if (_pr_inside_rect or _pr_inside_circle) else "rescued_prediction_near_candidate"
                    mask_reason = f"pred_cross_rescue({mask_reason})"
                    chosen["reason"] = _reason_str
                    chosen["prediction_rescued"] = True
                    chosen["pred_rescue_inside_rect"] = _pr_inside_rect
                    chosen["pred_rescue_inside_circle"] = _pr_inside_circle
                    chosen["pred_rescue_dist"] = _pr_dist
                    jump_dist = chosen.get("jump_dist")
                    _pred_rescue_this_frame = True
                    _pred_rescue_success += 1
                    rescued_count += 1
                    _pred_rescue_consec_misses = 0   # reset on success

        # Track consecutive prediction rescue misses
        if cfg == "post" and chosen is None and ball_launched:
            _pred_rescue_consec_misses += 1
        elif chosen is not None:
            _pred_rescue_consec_misses = 0

        base_dia = mask_dia if mask_dia is not None else (chosen['dia'] if chosen else None)
        # Part B: clamp base diameter before smoothing (only for post-impact frames)
        if base_dia is not None and hard_clamp_diam and chosen and cfg == "post":
            if previous_valid_diameter is not None:
                max_from_prev = previous_valid_diameter * max_growth_ratio
                if base_dia > max_from_prev:
                    base_dia = max_from_prev
                    mask_reason = "diameter_clamped_growth"
            ref_median = pre_impact_median_diameter if pre_impact_median_diameter else expected_diameter
            if ref_median is not None:
                max_from_median = ref_median * max_preimpact_ratio
                if base_dia > max_from_median:
                    base_dia = max_from_median
                    mask_reason = mask_reason if mask_reason == "diameter_clamped_growth" else "diameter_clamped_median"
        # Part C: shrink clamp — prevent sudden diameter drop (all phases)
        min_shrink_ratio = float(p.get("min_diam_shrink_ratio", 0.70))
        hard_clamp_shrink = float(p.get("hard_clamp_diameter_shrink", 1.0)) > 0.5
        if (base_dia is not None and hard_clamp_shrink and chosen and
                previous_valid_diameter is not None):
            min_from_prev = previous_valid_diameter * min_shrink_ratio
            if base_dia < min_from_prev:
                base_dia = min_from_prev
                mask_reason = "diameter_clamped_shrink"
        if base_dia is not None: recent_dias.append(base_dia)
        smoothed = float(np.median(list(recent_dias))) if len(recent_dias) >= 2 else None
        final_dia = smoothed if smoothed is not None else base_dia
        results.append(dict(idx=idx, roi=roi, candidates=all_raw_candidates, chosen=chosen,
            mask_dia=mask_dia, preview=preview, cand_in_crop=cand_in_crop,
            ref_in_crop=ref_in_crop, mask_center=mask_center,
            mask_center_in_crop=mask_center_in_crop, mask_count=mask_count,
            mask_fill_ratio=mask_fill_ratio, mask_brightness_mean=mask_brightness_mean,
            mask_reason=mask_reason, final_dia=final_dia,
            predicted_pos=predicted_pos, jump_dist=jump_dist,
            expected_diameter=expected_diameter,
            launch_dir=launch_dir, ball_launched=ball_launched,
            launch_frame=launch_frame, max_progress=max_progress,
            prev_progress=prev_progress, ball_terminated=False,
            prediction_disabled=prediction_disabled,
            prediction_disabled_frame=prediction_disabled_frame,
            rescued=_rescued_this_frame,
            prediction_rescued=chosen.get("prediction_rescued", False) if chosen else False,
            pred_rescue_inside_rect=chosen.get("pred_rescue_inside_rect", False) if chosen else False,
            pred_rescue_inside_circle=chosen.get("pred_rescue_inside_circle", False) if chosen else False,
            pred_rescue_dist=chosen.get("pred_rescue_dist") if chosen else None,
            mask_aspect_ratio=mask_aspect_ratio,
            predictionMode=_pred_mode,
            merged_club_hints=[]))
        # Final edge safety gate — runs after all candidate selection and rescue
        if chosen is not None and p.get("enable_final_edge_ball_filter", 1.0) > 0.5:
            _efm = float(p.get("final_edge_margin_norm", 0.012))
            _efrs = float(p.get("final_edge_radius_margin_scale", 1.00))
            _ecx = mask_center[0] if mask_center else chosen["cx"]
            _ecy = mask_center[1] if mask_center else chosen["cy"]
            _edia = final_dia if final_dia is not None else chosen["dia"]
            _eradius = (_edia / 2.0) * _efrs
            _eleft   = _ecx - _eradius
            _eright  = _ecx + _eradius
            _etop    = _ecy - _eradius
            _ebottom = _ecy + _eradius
            _edge_fail = (
                _eleft   < _efm or
                _eright  > 1.0 - _efm or
                _etop    < _efm or
                _ebottom > 1.0 - _efm
            )
            if _edge_fail:
                _ereason = ("rejected_prediction_rescue_edge_ball"
                            if results[-1].get("prediction_rescued")
                            else "rejected_edge_partial_ball")
                results[-1]["edge_rejected"]           = True
                results[-1]["excluded_from_metrics_edge"] = True
                results[-1]["edge_reject_reason"]      = _ereason
                results[-1]["edge_bounds"]             = {
                    "left": _eleft, "right": _eright,
                    "top": _etop, "bottom": _ebottom
                }
                _edge_rejected_count += 1
                _edge_rejected_frames.append(idx)
                chosen = None  # prevent ALL state updates from this frame
        if chosen:
            # Part B: update diameter gate state
            if final_dia is not None:
                _is_clean_for_diam = (
                    not chosen.get("excluded_merged") and
                    "rejected_line_like_mask" not in (mask_reason or "") and
                    "rejected_partial_offscreen" not in (chosen.get("reason") or "")
                )
                if _is_clean_for_diam:
                    previous_valid_diameter = final_dia
                if idx == impact and pre_final_dias:
                    sorted_pd = sorted(pre_final_dias)
                    pre_impact_median_diameter = sorted_pd[len(sorted_pd) // 2]
            if cfg == "post":
                last_post = (chosen["cx"], chosen["cy"])
                t = rel_times[idx]
                # Part H: only update prediction from clean frames
                _is_clean_for_prediction = (
                    not chosen.get("excluded_merged") and
                    "rejected_line_like_mask" not in (mask_reason or "") and
                    "rejected_partial_offscreen" not in (chosen.get("reason") or "") and
                    "rejected_near_impact" not in (chosen.get("reason") or "") and
                    mask_count >= int(p.get("prelim_min_mask_pixels", 8))
                )
                if _is_clean_for_prediction:
                    recent_post_points.append((
                        mask_center[0] if mask_center else chosen["cx"],
                        mask_center[1] if mask_center else chosen["cy"],
                        t))
                    # Part E (new): track first post-impact clean point
                    if _first_post_clean is None:
                        _first_post_clean = True
                elif _first_post_clean is None:
                    # Has a chosen but it's not clean
                    _first_post_clean = False
                if _pred_mode == "single_point":
                    _single_point_pred_count += 1
                post_miss_count = 0
                consec_misses_after_launch = 0
                if len(recent_post_points) >= 2:
                    pts = list(recent_post_points)
                    dx = pts[-1][0] - pts[-2][0]; dy = pts[-1][1] - pts[-2][1]
                    dlen = math.sqrt(dx*dx + dy*dy)
                    if dlen > 1e-6:
                        ndx, ndy = dx/dlen, dy/dlen
                        if expected_direction is None:
                            expected_direction = (ndx, ndy)
                        else:
                            edx, edy = expected_direction
                            edx = sc_dir_alpha*ndx + (1-sc_dir_alpha)*edx
                            edy = sc_dir_alpha*ndy + (1-sc_dir_alpha)*edy
                            elen = math.sqrt(edx*edx + edy*edy)
                            expected_direction = (edx/elen, edy/elen) if elen > 1e-6 else expected_direction
                # Update progress tracking (Part A)
                prog = chosen.get("progress")
                if prog is not None:
                    if prog > max_progress: max_progress = prog
                    prev_progress = prog
                # Lock launch direction once ball has traveled far enough
                if not ball_launched:
                    ddx = chosen["cx"] - init_center[0]
                    ddy = chosen["cy"] - init_center[1]
                    dist_init = math.sqrt(ddx*ddx + ddy*ddy)
                    if dist_init >= p.get("sc_lock_dist", 0.02):
                        launch_dir = (ddx/dist_init, ddy/dist_init)
                        ball_launched = True; launch_frame = idx
                        print(f"Ball launched at frame {idx} dir=({ddx/dist_init:.3f},{ddy/dist_init:.3f})")
                # Part C: update stationary counter
                if last_chosen_pos is not None:
                    _mv = math.sqrt((chosen["cx"]-last_chosen_pos[0])**2 +
                                    (chosen["cy"]-last_chosen_pos[1])**2)
                    if _mv < float(p.get("stationary_motion_thresh", 0.004)):
                        stationary_count += 1
                    else:
                        stationary_count = 0
                last_chosen_pos = (chosen["cx"], chosen["cy"])
                # Part D: update static false-object memory (pre-launch only)
                if (p.get("enable_static_false_object_memory", 1.0) > 0.5 and
                        not ball_launched):
                    _prog = chosen.get("progress", 0) or 0
                    if _prog < float(p.get("sc_lock_dist", 0.02)):
                        _key = (round(chosen["cx"]/_static_gs), round(chosen["cy"]/_static_gs))
                        static_positions[_key] = static_positions.get(_key, 0) + 1
                        if (p.get("static_reject_after_limit", 1.0) > 0.5 and
                                static_positions[_key] > int(p.get("static_frame_limit", 2))):
                            static_reject_set.add(_key)
            else:
                last_pre = (chosen["cx"], chosen["cy"])
                if idx < impact and final_dia is not None:
                    pre_final_dias.append(final_dia)
            # New session Part F: reset prediction miss counter on successful detection
            if cfg == "post":
                prediction_miss_count = 0
        else:
            if cfg == "post":
                post_miss_count += 1
                # New session Part F: track prediction misses to disable prediction cross
                if ball_launched:
                    prediction_miss_count += 1
                    if (p.get("disable_prediction_after_miss", 1.0) > 0.5 and
                            prediction_miss_count >= int(p.get("prediction_miss_limit", 3)) and
                            not prediction_disabled):
                        prediction_disabled = True; prediction_disabled_frame = idx
                        print(f"Prediction disabled at frame {idx} after {prediction_miss_count} misses")
                # Part C: check for lost-ball termination
                if ball_launched:
                    consec_misses_after_launch += 1
                    if (p.get("sc_termination", 1.0) > 0.5 and
                            consec_misses_after_launch >= int(p.get("sc_term_miss_limit", 3)) and
                            max_progress >= p.get("sc_term_min_progress", 0.05) and
                            not ball_terminated):
                        ball_terminated = True; term_frame = idx
                        print(f"Ball track terminated at frame {idx} after {consec_misses_after_launch} misses maxP={max_progress:.4f}")
        # Update launch state in last result entry
        results[-1].update(dict(launch_dir=launch_dir, ball_launched=ball_launched,
            launch_frame=launch_frame, max_progress=max_progress,
            prev_progress=prev_progress, ball_terminated=results[-1].get("ball_terminated", ball_terminated),
            prediction_disabled=prediction_disabled,
            prediction_disabled_frame=prediction_disabled_frame))
    # Part B: Enhanced merged shape stopper (post-processing pass on selected results)
    # Part A: uses separate spike ratios for impact frame vs post-impact frames
    _early_merged_stopper_count = 0
    if p.get("enable_early_merged_stopper", 1.0) > 0.5:
        pre_impact_diams = [r.get("final_dia") for r in results
                            if r["idx"] < impact and r.get("final_dia")]
        if pre_impact_diams:
            expected_diam = float(np.median(pre_impact_diams))
            stopper_window = int(p.get("merged_shape_frame_window", 3))
            lookahead = int(p.get("spike_drop_lookahead_frames", 2))
            drop_thresh = float(p.get("spike_drop_ratio_threshold", 0.75))
            for i, r in enumerate(results):
                if r["idx"] < impact or r["idx"] > impact + stopper_window:
                    continue
                chosen = r.get("chosen")
                if not chosen:
                    continue
                cand_diam = chosen.get("norm_w", 0) or chosen.get("dia", 0)
                if expected_diam <= 0 or cand_diam <= 0:
                    continue
                # Part A: separate spike ratio for impact frame vs post-impact frames
                if r["idx"] == impact:
                    max_spike_here = float(p.get("max_impact_diam_spike_ratio", 1.75))
                    reason_prefix = "impact_diameter_spike"
                else:
                    max_spike_here = float(p.get("max_early_diam_spike_ratio", 1.60))
                    reason_prefix = "early_diameter_spike"
                spike_ratio = cand_diam / expected_diam
                is_spike = spike_ratio > max_spike_here
                # Spike-then-drop check
                spike_then_drop = False
                if is_spike and p.get("require_spike_then_drop", 1.0) > 0.5:
                    for j in range(i+1, min(i+1+lookahead, len(results))):
                        fut = results[j]
                        if fut.get("final_dia") and fut["final_dia"] > 0:
                            if fut["final_dia"] / cand_diam < drop_thresh:
                                spike_then_drop = True
                                break
                if is_spike or spike_then_drop:
                    r["likely_merged_club_ball"] = True
                    r["merged_spike_ratio"] = spike_ratio
                    r["merged_reason"] = reason_prefix + ("_then_drop" if spike_then_drop else "")
                    r["excluded_from_metrics_merged"] = True
                    if "chosen" in r:
                        r["chosen"]["excluded_merged"] = True
                    # Part B: store as club hint
                    if p.get("use_merged_ball_club_hints", 1.0) > 0.5 and chosen:
                        hint = {"cx": chosen.get("cx"), "cy": chosen.get("cy"),
                                "dia": chosen.get("dia"), "spikeRatio": spike_ratio,
                                "reason": r["merged_reason"]}
                        r.setdefault("merged_club_hints", []).append(hint)
                    _early_merged_stopper_count += 1
    _last_tracking_stats.update(dict(
        maskQualityRejectedCount=_mask_quality_rejected,
        tinyWeakRejectedCount=_tiny_weak_rejected,
        mergedClubBallRejectedCount=_merged_clubball_rejected,
        predictionBoostAppliedCount=_pred_boost_applied,
        rescuedCandidateCount=rescued_count,
        offPathRejectedCount=_off_path_rejected,
        predictionDisabledFrame=prediction_disabled_frame,
        ballTrackTerminatedFrame=term_frame,
        earlyMergedStopperCount=_early_merged_stopper_count,
        coneRejectedCount=_cone_rejected_total,
        verticalJumpRejectedCount=_vert_jump_rejected,
        predictionRescueAttemptedCount=_pred_rescue_attempted,
        predictionRescueSuccessCount=_pred_rescue_success,
        predictionRescueRejectedWeakCount=_pred_rescue_rejected_weak,
        lineLikeMaskRejectedCount=_line_like_rejected,
        singlePointPredictionUsedCount=_single_point_pred_count,
        nearImpactDiamGuardRejectedCount=_near_impact_diam_guard_rejected,
        edgeRejectedCount=_edge_rejected_count,
        edgeRejectedFrames=_edge_rejected_frames,
    ))
    return results

def run_tracker(frames_norm, p, fallback_impact, locked):
    pass1 = run_tracking_pass(frames_norm, p, fallback_impact, locked)
    det_impact, init_center, move_thresh, det_reason = detect_impact_frame(
        pass1, fallback_impact, p['move_thresh'], int(p['confirm_frames']), int(p['stable_window']), p=p)
    if det_impact != fallback_impact:
        final = run_tracking_pass(frames_norm, p, det_impact, locked)
    else:
        final = pass1
    tracked = sum(1 for r in final if r['chosen'])
    print(f"Tracked {tracked}/{N}  impact={det_impact}  fallback={fallback_impact}  reason={det_reason}")
    return final, det_impact, fallback_impact, det_reason

# ── 3D helpers ────────────────────────────────────────────────────────────────
def focal_lengths(p):
    fx = W / (2*math.tan(math.radians(p["fov_x"])/2))
    fy = H / (2*math.tan(math.radians(p["fov_y"])/2))
    return fx, fy

def image_point_to_3d(cx, cy, depth, fx, fy):
    x = ((cx*W) - W/2) * depth/fx
    y = -((cy*H) - H/2) * depth/fy
    return np.array([x, y, depth], dtype=float)

def ball_3d_observations(results, p):
    fx, fy = focal_lengths(p)
    f_avg = (fx+fy)/2; obs = []
    _merged_excluded_count = 0
    _edge_excluded_count = 0
    for r in results:
        if not r.get("chosen") or not r.get("final_dia"): continue
        # Part B: skip frames flagged by early merged shape stopper
        if r.get("excluded_from_metrics_merged"):
            _merged_excluded_count += 1
            continue
        # Final edge filter exclusion
        if r.get("excluded_from_metrics_edge") and p.get("exclude_edge_ball_from_metrics", 1.0) > 0.5:
            _edge_excluded_count += 1
            continue
        c = r["chosen"]
        cx, cy = r.get("mask_center") or (c["cx"], c["cy"])
        dia_px = r["final_dia"] * W
        if dia_px <= 0: continue
        z = p["ball_diam_m"] * f_avg / dia_px
        obs.append(dict(idx=r["idx"], t=rel_times[r["idx"]], cx=cx, cy=cy,
                        dia=r["final_dia"], dia_px=dia_px,
                        pos=image_point_to_3d(cx, cy, z, fx, fy), conf=c.get("conf", 1.0)))
    if _merged_excluded_count > 0:
        print(f"  [Part B stopper] Excluded {_merged_excluded_count} merged-shape frame(s) from metrics.")
    if _edge_excluded_count > 0:
        print(f"  [Edge filter] Excluded {_edge_excluded_count} edge/partial-frame ball point(s) from metrics.")
    return obs

def fit_velocity(points):
    if len(points) < 2: return None, "not_enough_data"
    t = np.array([p["t"] for p in points], dtype=float)
    xyz = np.array([p["pos"] for p in points], dtype=float)
    if len(points) == 2:
        dt = t[1]-t[0]
        return ((xyz[1]-xyz[0])/dt if dt > 0 else None), "two_point_delta"
    t0 = t.mean(); denom = np.sum((t-t0)**2)
    if denom <= 0: return None, "bad_time_span"
    vel = np.array([np.sum((t-t0)*xyz[:,k])/denom for k in range(3)])
    return vel, f"linear_fit_{len(points)}_points"

# ── Ball metrics ──────────────────────────────────────────────────────────────
def _estimate_vla_from_diameter(post_obs, p):
    """Estimate VLA from apparent ball diameter growth.
    Increasing diameter → ball moving toward camera → upward/forward launch."""
    valid = [o for o in post_obs if o.get("dia") and o["dia"] > 0]
    if len(valid) < 2:
        return None, 0.0, "not_enough_diameter_data"
    valid.sort(key=lambda o: o["t"])
    dia_first = valid[0]["dia"]; dia_last = valid[-1]["dia"]
    if dia_first <= 0:
        return None, 0.0, "zero_initial_diameter"
    growth = (dia_last - dia_first) / dia_first
    scale = float(p.get("diam_growth_vla_scale", 140.0))
    max_vla = float(p.get("max_vla_clamp", 75.0))
    vla_est = max(0.0, min(max_vla, growth * scale))
    boost_tag = ""
    # Part A: slow-horizontal boost — low horizontal movement → more upward → boost VLA
    if p.get("slow_horizontal_progress_boost", 1.0) > 0.5 and len(valid) >= 2 and growth > 0:
        cx0, cy0 = valid[0].get("cx", 0.5), valid[0].get("cy", 0.5)
        cx1, cy1 = valid[-1].get("cx", 0.5), valid[-1].get("cy", 0.5)
        dx_px = (cx1 - cx0) * W; dy_px = (cy1 - cy0) * H
        horiz_prog = math.sqrt(dx_px**2 + dy_px**2) / max(W, H)
        slow_thresh = float(p.get("slow_horiz_thresh", 0.035))
        if horiz_prog < slow_thresh:
            mult = float(p.get("slow_horiz_vla_boost_mult", 1.4))
            vla_est = min(max_vla, vla_est * mult)
            boost_tag = f"+slowH({horiz_prog:.3f})"
    # Part A: VLA floor for significant diameter growth (high launch indicator)
    sig_thresh = float(p.get("significant_diam_growth_thresh", 0.10))
    very_high_thresh = float(p.get("very_high_launch_diam_growth_thresh", 0.25))
    if growth > very_high_thresh:
        vla_floor = min(max_vla, very_high_thresh * scale * 0.8)
        vla_est = max(vla_est, vla_floor)
        boost_tag += "+vhFloor"
    elif growth > sig_thresh:
        vla_floor = min(max_vla, sig_thresh * scale * 0.8)
        vla_est = max(vla_est, vla_floor)
    n = len(valid)
    return vla_est, growth, f"diam_growth({growth:+.3f}_over_{n}_pts{boost_tag})"

def _filter_metric_points(post, p):
    """Part F: filter metric points by confidence, diameter outlier, path residual."""
    min_conf = float(p.get("metric_min_conf", 0.35))
    max_diam_ratio = float(p.get("metric_max_diam_ratio", 1.75))
    max_resid = float(p.get("metric_max_resid", 0.025))
    min_pts = 2
    warns = []
    filtered = list(post)

    # Step 1: confidence
    step1 = [o for o in filtered if o.get("conf", 1.0) >= min_conf]
    if len(step1) >= min_pts:
        if len(step1) < len(filtered):
            warns.append(f"Filtered {len(filtered)-len(step1)} low-conf metric pts.")
        filtered = step1

    # Step 2: diameter outlier
    dias = sorted(o.get("dia") or 0 for o in filtered)
    if dias:
        med_d = dias[len(dias) // 2]
        step2 = [o for o in filtered if (o.get("dia") or 0) <= med_d * max_diam_ratio]
        if len(step2) >= min_pts:
            if len(step2) < len(filtered):
                warns.append(f"Filtered {len(filtered)-len(step2)} outlier-dia metric pts.")
            filtered = step2

    # Step 3: path residual (needs ≥3)
    if len(filtered) >= 3:
        times = [o["t"] for o in filtered]
        xs = [o["cx"] for o in filtered]
        ys = [o["cy"] for o in filtered]
        mean_t = sum(times) / len(times)
        cx0 = sum(xs) / len(xs); cy0 = sum(ys) / len(ys)
        denom = sum((t - mean_t)**2 for t in times)
        if denom > 0:
            dx = sum((times[i]-mean_t)*xs[i] for i in range(len(times))) / denom
            dy = sum((times[i]-mean_t)*ys[i] for i in range(len(times))) / denom
            dl = math.sqrt(dx*dx + dy*dy)
            if dl > 1e-6:
                ndx, ndy = dx/dl, dy/dl
                step3 = [o for o in filtered
                         if abs((o["cx"]-cx0)*ndy - (o["cy"]-cy0)*ndx) <= max_resid]
                if len(step3) >= min_pts:
                    if len(step3) < len(filtered):
                        warns.append(f"Filtered {len(filtered)-len(step3)} path-outlier metric pts.")
                    filtered = step3
    return filtered, warns

def _vla_pinhole2dsize(post_obs, p, fx, fy):
    """New VLA model: use image coords + apparent size (pinhole depth) to estimate VLA.

    Parts B-F: pinhole depth from diameter, perspective correction, diameter-growth boost,
    outlier filtering, 0-70° clamp.
    """
    f_avg = (fx + fy) / 2.0
    ball_diam_m = float(p.get("ball_diam_m", 0.04267))
    max_vla = float(p.get("max_vla_pinhole", 70.0))

    # Sort by time, use first 2-6 valid points
    valid = [o for o in sorted(post_obs, key=lambda x: x["t"])
             if o.get("dia") and o["dia"] > 0 and o.get("cx") and o.get("cy")]

    debug = dict(pointsUsed=0, pointsRejected=0, rejectReasons=[],
                 perspectiveCorrectionApplied=False, vlaModel="pinhole2DSize",
                 vlaRawDegrees=None, vlaFinalDegrees=None, vlaClampedDegrees=None,
                 vlaImageYComponent=None, vlaDepthComponent=None,
                 vlaHorizontalComponent=None, correctedDiameterGrowth=None,
                 observedDiameterGrowth=None, dXpixels=None, dYpixels=None,
                 dZestimated=None, vlaWarnings=[])

    if len(valid) < 2:
        debug["rejectReasons"].append("fewer_than_2_valid_points")
        debug["pointsRejected"] = len(post_obs) - len(valid)
        return None, debug, ["Not enough valid pinhole2DSize VLA points."]

    # Use at most 6 earliest points
    pts = valid[:6]

    # Initial ball X for perspective correction
    init_cx = float(p.get("init_ball_cx", pts[0]["cx"]))  # fallback to first point

    # Part E: perspective size correction — ball appears smaller moving right
    use_persp = p.get("use_rightward_perspective_correction", 1.0) > 0.5
    strength = float(p.get("rightward_size_correction_strength", 0.35))
    max_corr = float(p.get("max_size_correction_ratio", 1.35))

    def corrected_dia(obs):
        dia = obs["dia"]
        if not use_persp:
            return dia
        dx_norm = obs["cx"] - init_cx
        scale = 1.0 / max(1e-6, 1.0 + strength * max(0.0, dx_norm))
        corrected = dia / scale
        return min(corrected, dia * max_corr)

    # Compute corrected diameters and depth Z for each point
    enriched = []
    for o in pts:
        c_dia = corrected_dia(o)
        dia_px = c_dia * W
        if dia_px <= 0:
            continue
        Z = ball_diam_m * f_avg / dia_px
        enriched.append(dict(**o, c_dia=c_dia, Z=Z))

    if len(enriched) < 2:
        debug["rejectReasons"].append("too_few_after_perspective_correction")
        return None, debug, ["Not enough points after perspective correction."]

    first, last = enriched[0], enriched[-1]
    debug["perspectiveCorrectionApplied"] = use_persp
    debug["pointsUsed"] = len(enriched)
    debug["pointsRejected"] = len(valid) - len(enriched)

    # Part D: image-space displacement in pixels
    dx_px = (last["cx"] - first["cx"]) * W
    dy_px = (last["cy"] - first["cy"]) * H
    dz = last["Z"] - first["Z"]
    avg_Z = (first["Z"] + last["Z"]) / 2.0

    # Part D: convert to approximate metric displacement at average depth
    d_x_m = dx_px * avg_Z / max(fx, 1e-6)
    d_y_m = -dy_px * avg_Z / max(fy, 1e-6)   # image y is downward, ball going up → negative dy
    d_z_m = dz

    debug["dXpixels"] = dx_px
    debug["dYpixels"] = dy_px
    debug["dZestimated"] = d_z_m

    # Part D: VLA components
    img_y_w  = float(p.get("vla_image_y_weight",       0.45))
    dia_dw   = float(p.get("vla_diameter_depth_weight", 0.55))
    depth_sgn = float(p.get("vla_depth_sign",  1.0))
    depth_scl = float(p.get("vla_depth_scale", 1.0))

    # Vertical: upward = positive image-y displacement OR depth increasing (ball coming toward camera)
    # dz negative → ball closer → upward launch → vertical contribution positive
    vert_from_image_y = d_y_m
    vert_from_depth   = -d_z_m * depth_sgn * depth_scl  # negative dz means forward/toward camera = upward

    vert_combined = img_y_w * vert_from_image_y + dia_dw * vert_from_depth
    horiz_component = max(abs(d_x_m), 1e-6)

    debug["vlaImageYComponent"] = vert_from_image_y
    debug["vlaDepthComponent"]  = vert_from_depth
    debug["vlaHorizontalComponent"] = horiz_component

    raw_vla = math.degrees(math.atan2(max(0.0, vert_combined), horiz_component))
    debug["vlaRawDegrees"] = raw_vla

    # Part F: diameter growth boost
    obs_growth = (last["dia"] - first["dia"]) / max(first["dia"], 1e-6)
    corr_growth = (last["c_dia"] - first["c_dia"]) / max(first["c_dia"], 1e-6)
    debug["observedDiameterGrowth"] = obs_growth
    debug["correctedDiameterGrowth"] = corr_growth

    sig_thresh = float(p.get("vla_significant_growth_thresh",  0.10))
    vh_thresh  = float(p.get("vla_very_high_growth_thresh",    0.25))
    min_vla_vh = float(p.get("vla_min_from_very_high_growth",  30.0))
    growth_scale = float(p.get("vla_growth_boost_dia_scale",   140.0))

    boosted_vla = raw_vla
    if corr_growth > sig_thresh:
        growth_vla = corr_growth * growth_scale
        boosted_vla = max(raw_vla, growth_vla)
    if corr_growth > vh_thresh:
        boosted_vla = max(boosted_vla, min_vla_vh)

    final_vla = max(0.0, min(max_vla, boosted_vla))
    debug["vlaFinalDegrees"]   = final_vla
    debug["vlaClampedDegrees"] = final_vla

    warns = []
    if raw_vla < 0:
        warns.append(f"Pinhole2DSize VLA raw={raw_vla:.1f}° (negative component clamped to 0)")
    if corr_growth < obs_growth - 0.01:
        warns.append(f"Perspective correction applied: obs_growth={obs_growth:+.3f} corrected_growth={corr_growth:+.3f}")
    debug["vlaWarnings"] = warns

    return final_vla, debug, warns


def calc_ball_metrics(ball3d, impact, p=None):
    if p is None: p = params
    raw_post = [o for o in sorted(ball3d, key=lambda x: x["idx"]) if o["idx"] > impact][:6]
    # Part F: filter metric points
    post, filter_warns = _filter_metric_points(raw_post, p)
    if len(post) < 2:
        return dict(ball_speed=None, hla=None, vla=None, vla_raw=None, points=len(post),
                    quality=0, method="not_enough_data", warnings=["Not enough post-impact ball points."] + filter_warns)
    vel, method = fit_velocity(post)
    if vel is None:
        return dict(ball_speed=None, hla=None, vla=None, vla_raw=None, points=len(post),
                    quality=0, method=method, warnings=["Ball velocity failed."] + filter_warns)
    speed = float(np.linalg.norm(vel)) * 2.23694
    # 3D raw HLA (for debug/reference only)
    hla_3d = math.degrees(math.atan2(vel[0], vel[2]))
    horiz = math.sqrt(vel[0]**2 + vel[2]**2)
    # Part E: VLA clamped to ≥ 0
    vla_raw = math.degrees(math.atan2(vel[1], horiz))
    vla_3d = max(0.0, vla_raw)
    avg_conf = sum(o["conf"] for o in post)/len(post)
    warns = list(filter_warns)
    if len(raw_post) == 2: warns.append("Ball velocity used 2-point fallback.")
    if vla_raw < 0: warns.append(f"VLA was negative ({vla_raw:.1f}°); clamped to 0.")
    # Part D: diameter-growth VLA estimator
    vla_diam_est = None; diam_growth = 0.0; diam_vla_reason = "disabled"
    if p.get("use_diam_growth_vla", 1.0) > 0.5:
        vla_diam_est, diam_growth, diam_vla_reason = _estimate_vla_from_diameter(post, p)
    # VLA model selection
    vla_model = p.get("vla_model", "pinhole2dsize")
    pinhole_debug = {}
    if vla_model == "pinhole2dsize":
        fx2, fy2 = focal_lengths(p)
        vla_pinhole, pinhole_debug, pinhole_warns = _vla_pinhole2dsize(post, p, fx2, fy2)
        warns.extend(pinhole_warns)
        if vla_pinhole is not None:
            vla = max(0.0, min(70.0, vla_pinhole))
        else:
            vla = vla_3d  # fallback
    elif vla_model == "blended":
        fx2, fy2 = focal_lengths(p)
        vla_pinhole, pinhole_debug, pinhole_warns = _vla_pinhole2dsize(post, p, fx2, fy2)
        warns.extend(pinhole_warns)
        if vla_diam_est is not None and vla_pinhole is not None:
            vla = max(0.0, min(70.0, (vla_diam_est + vla_pinhole) / 2.0))
        elif vla_pinhole is not None:
            vla = max(0.0, min(70.0, vla_pinhole))
        elif vla_diam_est is not None:
            # Combine 3D VLA with diameter-growth estimate (legacy path)
            w_diam = float(p.get("diam_growth_vla_weight", 0.65))
            w_3d   = float(p.get("image_y_vla_weight", 0.35))
            if vla_3d < 5.0 and vla_diam_est > 10.0:
                combined = vla_diam_est * w_diam + vla_3d * w_3d
                warns.append(f"VLA: 3D={vla_3d:.1f}° near zero; diameter growth={diam_growth:+.3f} → est={vla_diam_est:.1f}°; combined={combined:.1f}°.")
            else:
                combined = max(vla_3d, vla_diam_est * w_diam)
            vla = max(0.0, min(float(p.get("max_vla_clamp", 75.0)), combined))
        else:
            vla = vla_3d
    else:  # legacy
        pinhole_debug = {}
        # Combine 3D VLA with diameter-growth estimate (original logic)
        if vla_diam_est is not None:
            w_diam = float(p.get("diam_growth_vla_weight", 0.65))
            w_3d   = float(p.get("image_y_vla_weight", 0.35))
            if vla_3d < 5.0 and vla_diam_est > 10.0:
                combined = vla_diam_est * w_diam + vla_3d * w_3d
                warns.append(f"VLA: 3D={vla_3d:.1f}° near zero; diameter growth={diam_growth:+.3f} → est={vla_diam_est:.1f}°; combined={combined:.1f}°.")
            else:
                combined = max(vla_3d, vla_diam_est * w_diam)
            vla = max(0.0, min(float(p.get("max_vla_clamp", 75.0)), combined))
        else:
            vla = vla_3d

    # Image-space HLA relative to 0° reference line (preferred)
    hla_img, dx2d, dy2d, fwd, lat, hla_warns = _image_space_hla(post, params["zero_deg"])
    warns.extend(hla_warns)
    hla = hla_img if hla_img is not None else hla_3d

    # Part G — suppress HLA if it exceeds the plausibility gate
    max_metric_hla = float(p.get("metric_max_hla", 35.0))
    if hla is not None and abs(hla) > max_metric_hla:
        warns.append(f"HLA ({hla:.1f}°) exceeds ±{max_metric_hla:.0f}° gate — suppressed (false detection likely).")
        hla = None
        dx2d = dy2d = fwd = lat = None

    return dict(ball_speed=speed, hla=hla, hla_3d_raw=hla_3d,
                hla_dx=dx2d, hla_dy=dy2d, hla_forward=fwd, hla_lateral=lat,
                vla=vla, vla_raw=vla_raw, vla_3d=vla_3d,
                vla_diam_est=vla_diam_est, diam_growth=diam_growth,
                vla_model=vla_model,
                pinhole_debug=pinhole_debug,
                points=len(post),
                quality=min(1.0,len(post)/6)*avg_conf, method=method, warnings=warns)


def _image_space_hla(post_obs, zero_deg):
    """Compute HLA in image space relative to zero_deg reference angle.

    Image space: x right, y down (normalized 0-1).
    ref = (cos θ, -sin θ),  perp = (sin θ, cos θ)
    HLA = atan2(lateral, forward) — 0° when ball moves along reference.
    """
    warns = []
    if len(post_obs) < 2:
        return None, None, None, None, None, ["Not enough points for image-space HLA."]

    times = [o["t"] for o in post_obs]
    xs    = [o["cx"] for o in post_obs]
    ys    = [o["cy"] for o in post_obs]
    n = len(times)
    mean_t = sum(times) / n
    denom  = sum((t - mean_t)**2 for t in times)
    if denom <= 0:
        return None, None, None, None, None, ["Invalid time span for image-space HLA."]

    dxdt = sum((times[i]-mean_t)*xs[i] for i in range(n)) / denom
    dydt = sum((times[i]-mean_t)*ys[i] for i in range(n)) / denom

    # Scale to pixel space so the computed angle matches the visual angle between
    # the drawn 0° ref line and the drawn ball path (the ref line is drawn in pixels).
    dxdt_px = dxdt * W
    dydt_px = dydt * H
    mov_len = math.sqrt(dxdt_px**2 + dydt_px**2)
    if mov_len < 1e-6:
        warns.append("Ball 2D movement vector near zero; HLA unreliable.")
        return None, dxdt, dydt, None, None, warns

    theta = math.radians(zero_deg)
    ref_x =  math.cos(theta)
    ref_y = -math.sin(theta)   # y-down image convention
    perp_x = math.sin(theta)
    perp_y = math.cos(theta)

    forward = dxdt_px * ref_x + dydt_px * ref_y
    lateral = dxdt_px * perp_x + dydt_px * perp_y
    if abs(forward) < 0.001 * mov_len:
        warns.append("Ball moving nearly perpendicular to 0° reference; HLA near ±90°.")
    hla = math.degrees(math.atan2(lateral, forward))
    return hla, dxdt, dydt, forward, lateral, warns

# ── Directional formatting ────────────────────────────────────────────────────
def format_lr(degrees, pos="R", neg="L"):
    """Format signed angle as 'X.X° R' or 'X.X° L'."""
    if degrees is None: return "—"
    label = pos if degrees >= 0 else neg
    return f"{abs(degrees):.1f}° {label}"

def format_spin_lr(rpm):
    """Format signed spin as '850 rpm R' or '450 rpm L'."""
    if rpm is None: return "—"
    label = "R" if rpm >= 0 else "L"
    return f"{abs(rpm):.0f} rpm {label}"

# ── Physics-based carry model ─────────────────────────────────────────────────
# idealCarry = v²·sin(2θ)/g  (ballistic, no drag)
# carry = idealCarry × correctionFactor × 1.09361  (yards)
# Correction factor default 0.75 accounts for aerodynamic drag.

def _ideal_carry_yards(ball_speed_mph, vla_deg):
    speed_mps = ball_speed_mph / 2.23694
    vla_rad   = math.radians(max(0.5, min(45, vla_deg)))
    ideal_m   = (speed_mps**2 * math.sin(2 * vla_rad)) / 9.80665
    return ideal_m * 1.09361  # yards

def estimate_distance(ball_speed, vla, hla, carry_correction_factor=0.75):
    warns = []
    if ball_speed is None or vla is None:
        return dict(ideal_carry=None, carry_correction_factor=carry_correction_factor,
                    carry=None, rollout_yards=None, total=None,
                    rollout_fraction=None, vla_bucket="unknown",
                    warnings=["Missing ball speed or VLA."])
    vla_c = min(max(vla, 0.5), 45)
    if vla_c != vla:
        warns.append(f"VLA {vla:.1f}° clamped to {vla_c:.1f}°.")

    ccf = max(0.40, min(1.20, carry_correction_factor))
    ideal_carry = _ideal_carry_yards(ball_speed, vla_c)
    carry = max(0, min(450, ideal_carry * ccf))

    # Finer VLA-bucket rollout table
    if vla_c < 1:
        base_rollout, vla_bucket = 0.85, "vla<1°"
    elif vla_c < 3:
        base_rollout, vla_bucket = 0.65, "1°≤vla<3°"
    elif vla_c < 6:
        base_rollout, vla_bucket = 0.45, "3°≤vla<6°"
    elif vla_c < 10:
        base_rollout, vla_bucket = 0.30, "6°≤vla<10°"
    elif vla_c < 15:
        base_rollout, vla_bucket = 0.20, "10°≤vla<15°"
    elif vla_c < 22:
        base_rollout, vla_bucket = 0.12, "15°≤vla<22°"
    elif vla_c < 30:
        base_rollout, vla_bucket = 0.07, "22°≤vla<30°"
    else:
        base_rollout, vla_bucket = 0.03, "vla≥30°"

    speed_adj = (0.45 if ball_speed < 40 else 0.75 if ball_speed < 80
                 else 1.10 if ball_speed >= 130 else 1.00)
    rollout_fraction = max(0.02, min(0.90, base_rollout * speed_adj))
    rollout_yards = carry * rollout_fraction
    total = min(carry + rollout_yards, 400)
    if total > 350:
        warns.append("Total >350 yd — verify calibration/FOV.")
    warns.append("Total = carry + VLA-based rollout. Spin/ground unknown.")
    warns.append(f"Carry: idealCarry={ideal_carry:.0f} yd × cf={ccf:.2f} = {carry:.0f} yd")
    warns.append(f"Rollout: {rollout_fraction*100:.0f}% of carry (VLA bucket: {vla_bucket})")
    return dict(ideal_carry=ideal_carry, carry_correction_factor=ccf,
                carry=carry, rollout_yards=rollout_yards, total=total,
                rollout_fraction=rollout_fraction, vla_bucket=vla_bucket, warnings=warns)

# ── Estimated spin ────────────────────────────────────────────────────────────
def estimate_spin(ball_speed, vla, hla, club_path):
    """Estimate backspin, sidespin and spin axis from launch parameters."""
    warns = ["Backspin ESTIMATED from speed+VLA model.",
             "Sidespin ESTIMATED from HLA/path difference."]
    if ball_speed is None or ball_speed <= 0:
        warns.append("Spin estimate unavailable: missing ball speed.")
        return dict(backspin=None, sidespin=None, sidespin_display="—",
                    spin_axis=None, spin_axis_display="—", method="unavailable",
                    warnings=warns)
    vla_eff = vla if vla is not None else 15.0
    if vla is None: warns.append("VLA unavailable — backspin uses default VLA=15°.")

    vla_mult = (0.60 if vla_eff < 5 else 0.80 if vla_eff < 10 else
                1.00 if vla_eff < 20 else 1.20 if vla_eff < 30 else 1.35)
    raw_bs = (800 + 90 * ball_speed + 120 * vla_eff) * vla_mult
    backspin = max(300, min(9000, raw_bs))

    method = "unavailable_sidespin"
    if hla is not None and club_path is not None:
        ftp = hla - club_path
        sidespin = max(-4000, min(4000, ftp * 200 * (ball_speed / 100)))
        method = "hla_minus_path"
    elif hla is not None:
        sidespin = max(-4000, min(4000, hla * 150 * (ball_speed / 100)))
        warns.append("Club path unavailable — sidespin from HLA only.")
        method = "hla_only"
    else:
        sidespin = None
        warns.append("HLA unavailable — sidespin unavailable.")

    spin_axis = (math.degrees(math.atan2(sidespin, backspin))
                 if sidespin is not None else None)
    return dict(backspin=backspin, sidespin=sidespin,
                sidespin_display=format_spin_lr(sidespin),
                spin_axis=spin_axis, spin_axis_display=format_lr(spin_axis),
                method=method, warnings=warns)

# ── Club path (image-space) ───────────────────────────────────────────────────
def estimate_club_path(club_obs, zero_deg, impact):
    """Compute club path angle from pre-impact centroid movement."""
    pre = [o for o in club_obs
           if o.get("found") and o.get("cx") is not None and o.get("idx", 9999) <= impact]
    if len(pre) < 2:
        return dict(angle=None, display="—", confidence=0,
                    method="not_enough_data", warnings=["Not enough pre-impact club obs."])
    pre = sorted(pre, key=lambda o: o["idx"])
    times = [rel_times[o["idx"]] for o in pre]
    xs = [o["cx"] for o in pre]; ys = [o["cy"] for o in pre]
    n = len(times); mean_t = sum(times)/n
    denom = sum((t-mean_t)**2 for t in times)
    if denom < 1e-12:
        return dict(angle=None, display="—", confidence=0,
                    method="zero_time_span", warnings=["Zero time span."])
    dxdt = sum((times[i]-mean_t)*xs[i] for i in range(n))/denom
    dydt = sum((times[i]-mean_t)*ys[i] for i in range(n))/denom
    dxpx = dxdt * W; dypx = dydt * H
    mov_len = math.sqrt(dxpx**2 + dypx**2)
    if mov_len < 1e-6:
        return dict(angle=None, display="—", confidence=0,
                    method="near_zero", warnings=["Club movement near zero."])
    theta = math.radians(zero_deg)
    ref_x = math.cos(theta);  ref_y = -math.sin(theta)
    perp_x = math.sin(theta); perp_y =  math.cos(theta)
    fwd = dxpx*ref_x + dypx*ref_y
    lat = dxpx*perp_x + dypx*perp_y
    angle = math.degrees(math.atan2(lat, fwd))
    conf  = min(1.0, len(pre)/5.0)
    return dict(angle=angle, display=format_lr(angle), confidence=conf,
                method=f"image_space_linear_fit_{len(pre)}pts",
                warnings=["Club path is image-space estimate only."])

# ── Face angle (bbox heuristic — pixel data not available in Python) ──────────
def estimate_face_angle(club_obs, zero_deg, impact, club_path_angle):
    """Face angle via bounding-box longest-axis heuristic."""
    near = [o for o in club_obs
            if o.get("found") and o.get("bbox") and o.get("idx", 9999) <= impact]
    if not near:
        return dict(angle=None, display="—", ftp=None, ftp_display="—",
                    confidence="unavailable", method="no_bbox",
                    warnings=["Face angle unavailable: no bbox near impact."])
    co = min(near, key=lambda o: abs(o["idx"] - impact))
    bbx, bby, bbw, bbh = co["bbox"]
    bbox_w_px = bbw * W; bbox_h_px = bbh * H
    shaft_rad = 0.0 if bbox_w_px >= bbox_h_px else math.pi / 2
    face_rad  = shaft_rad + math.pi / 2
    theta  = math.radians(zero_deg)
    ref_x  =  math.cos(theta); ref_y  = -math.sin(theta)
    perp_x =  math.sin(theta); perp_y =  math.cos(theta)
    fd_x = math.cos(face_rad); fd_y = math.sin(face_rad)
    fwd = fd_x*ref_x + fd_y*ref_y
    lat = fd_x*perp_x + fd_y*perp_y
    face_angle = math.degrees(math.atan2(lat, fwd))
    ftp = (face_angle - club_path_angle) if club_path_angle is not None else None
    return dict(angle=face_angle, display=format_lr(face_angle),
                ftp=ftp, ftp_display=format_lr(ftp),
                confidence="low_bbox_heuristic", method="bbox_aspect_ratio",
                warnings=["Face angle is a rough bbox-aspect heuristic. Very low confidence."])

# ── Clubface debug figure ─────────────────────────────────────────────────────
def _clubface_roi_norm(ball_cx, ball_cy, ball_dia, co_best, fa):
    """Return search ROI as normalized {x0,y0,x1,y1}."""
    dia_px = ball_dia * W
    hw = dia_px * fa.face_roi_scale_x / 2
    hh = dia_px * fa.face_roi_scale_y / 2
    cx_px = ball_cx * W + fa.face_roi_offset_x * W
    cy_px = ball_cy * H + fa.face_roi_offset_y * H
    x0 = max(0.0, (cx_px - hw) / W)
    y0 = max(0.0, (cy_px - hh) / H)
    x1 = min(1.0, (cx_px + hw) / W)
    y1 = min(1.0, (cy_px + hh) / H)
    if fa.face_use_club_box and co_best and co_best.get("bbox"):
        bbx, bby, bbw, bbh = co_best["bbox"]
        pad = fa.face_club_box_padding
        x0 = min(x0, max(0.0, bbx - bbw * (pad - 1) / 2))
        y0 = min(y0, max(0.0, bby - bbh * (pad - 1) / 2))
        x1 = max(x1, min(1.0, bbx + bbw * (1 + (pad - 1) / 2)))
        y1 = max(y1, min(1.0, bby + bbh * (1 + (pad - 1) / 2)))
    return dict(x0=x0, y0=y0, x1=x1, y1=y1)

def _excl_mask_crop(crop_h, crop_w, ball_cx, ball_cy, ball_dia, x0r, y0r, fa):
    """Boolean mask (True=exclude) for ball exclusion zone in crop pixel coords."""
    excl_r = ball_dia * W * fa.face_ball_exclusion_scale / 2
    bpx = ball_cx * W - x0r
    bpy = ball_cy * H - y0r
    ys, xs = np.mgrid[0:crop_h, 0:crop_w]
    return (xs - bpx) ** 2 + (ys - bpy) ** 2 <= excl_r ** 2

def _sobel_mag(gray_f):
    gx = np.zeros_like(gray_f); gy = np.zeros_like(gray_f)
    if gray_f.shape[0] > 2: gy[1:-1] = (gray_f[2:] - gray_f[:-2]) / 2.0
    if gray_f.shape[1] > 2: gx[:, 1:-1] = (gray_f[:, 2:] - gray_f[:, :-2]) / 2.0
    return gx, gy, np.sqrt(gx ** 2 + gy ** 2)

def _detect_face_pca(gray, excl_mask, x0r, y0r, fa, face_prior_rad=None):
    """Dominant edge direction via Sobel + circular-statistics PCA. No cv2 needed.
    face_prior_rad: if given, resolve 180° ambiguity toward the prior angle."""
    gx, gy, mag = _sobel_mag(gray.astype(float))
    edge_mask = (mag >= fa.face_edge_threshold) & ~excl_mask
    rows, cols = np.where(edge_mask)
    mags = mag[rows, cols]
    if len(rows) < fa.face_min_edge_pixels:
        return None
    trim = fa.face_pca_outlier_trim
    if trim > 0 and len(mags) > 20:
        lo = np.percentile(mags, trim * 100); hi = np.percentile(mags, (1 - trim) * 100)
        keep = (mags >= lo) & (mags <= hi)
        rows, cols, mags = rows[keep], cols[keep], mags[keep]
    if len(rows) < fa.face_min_edge_pixels:
        return None
    gx_pts = gx[rows, cols]; gy_pts = gy[rows, cols]
    edge_angles = np.arctan2(gx_pts, gy_pts)  # perpendicular to gradient = edge direction
    cos2 = float(np.sum(np.cos(2 * edge_angles) * mags))
    sin2 = float(np.sum(np.sin(2 * edge_angles) * mags))
    weight_sum = float(np.sum(mags))
    if weight_sum < 1e-6:
        return None
    dom_angle = math.atan2(sin2, cos2) / 2.0
    # Resolve 180° ambiguity: pick the interpretation closest to face_prior_rad
    if face_prior_rad is not None:
        alt_angle = dom_angle + math.pi
        def _angular_dist(a, b):
            d = (a - b + math.pi) % (2 * math.pi) - math.pi
            return abs(d)
        if _angular_dist(alt_angle, face_prior_rad) < _angular_dist(dom_angle, face_prior_rad):
            dom_angle = alt_angle
    coherence = math.sqrt(cos2 ** 2 + sin2 ** 2) / weight_sum
    cx_crop = float(np.sum(cols * mags) / weight_sum)
    cy_crop = float(np.sum(rows * mags) / weight_sum)
    return dict(method="pca", cx=(x0r + cx_crop) / W, cy=(y0r + cy_crop) / H,
                angle_rad=dom_angle, coherence=coherence, edge_count=int(len(rows)))

def _detect_face_hough(gray, excl_mask, x0r, y0r, fa, face_prior_rad=None,
                       face_prior_score_weight=3.0, max_prior_dev_rad=None):
    """Hough line detection via cv2.
    face_prior_rad: if given, score candidates by length × prior-closeness."""
    try:
        import cv2
    except ImportError:
        return None
    gray_u8 = np.clip(gray, 0, 255).astype(np.uint8)
    edges = cv2.Canny(gray_u8, fa.face_canny_low, fa.face_canny_high)
    edges[excl_mask] = 0
    lines = cv2.HoughLinesP(edges, 1, math.pi / 180, fa.face_hough_threshold,
                            minLineLength=fa.face_hough_min_length,
                            maxLineGap=fa.face_hough_max_gap)
    if lines is None or len(lines) == 0:
        return None

    def _score_line(l):
        x1c, y1c, x2c, y2c = l[0]
        length = math.hypot(x2c - x1c, y2c - y1c)
        if face_prior_rad is None:
            return length
        line_rad = math.atan2(float(y2c - y1c), float(x2c - x1c))
        # Try both orientations (180° ambiguity)
        d1 = abs((line_rad - face_prior_rad + math.pi) % (2*math.pi) - math.pi)
        d2 = abs((line_rad + math.pi - face_prior_rad + math.pi) % (2*math.pi) - math.pi)
        dev = min(d1, d2)
        if max_prior_dev_rad is not None and dev > max_prior_dev_rad:
            return length * 0.1  # heavily penalize out-of-prior lines
        prior_score = max(0.0, 1.0 - dev / max(max_prior_dev_rad or math.pi, 1e-6))
        return length * (1.0 + face_prior_score_weight * prior_score)

    best = max(lines, key=_score_line)
    x1c, y1c, x2c, y2c = best[0]
    cx_crop = (x1c + x2c) / 2.0; cy_crop = (y1c + y2c) / 2.0
    angle_rad = math.atan2(float(y2c - y1c), float(x2c - x1c))
    # Resolve 180° ambiguity toward prior
    if face_prior_rad is not None:
        alt = angle_rad + math.pi
        d1 = abs((angle_rad - face_prior_rad + math.pi) % (2*math.pi) - math.pi)
        d2 = abs((alt - face_prior_rad + math.pi) % (2*math.pi) - math.pi)
        if d2 < d1:
            angle_rad = alt
    length = math.hypot(x2c - x1c, y2c - y1c)
    return dict(method="hough_cv2", cx=(x0r + cx_crop) / W, cy=(y0r + cy_crop) / H,
                angle_rad=angle_rad,
                coherence=min(1.0, length / max(1, fa.face_hough_min_length * 4)),
                edge_count=len(lines),
                endpoints=((x0r + x1c) / W, (y0r + y1c) / H,
                            (x0r + x2c) / W, (y0r + y2c) / H))

def _face_angle_info(face_result, zero_deg, fa):
    angle_rad = face_result["angle_rad"]
    if fa.face_angle_normal_mode == "normal":
        angle_rad += math.pi / 2
    if fa.face_angle_flip:
        angle_rad = -angle_rad
    theta = math.radians(zero_deg)
    ref_x = math.cos(theta);  ref_y  = -math.sin(theta)
    perp_x = math.sin(theta); perp_y =  math.cos(theta)
    fdx = math.cos(angle_rad); fdy = math.sin(angle_rad)
    fwd = fdx * ref_x + fdy * ref_y
    lat = fdx * perp_x + fdy * perp_y
    deg = math.degrees(math.atan2(lat, fwd))
    return dict(angle_deg=deg, display=format_lr(deg), angle_rad_used=angle_rad)

def generate_clubface_debug(track_results, club_obs, metrics, impact, fa, p):
    """Save clubface_debug.png + face_debug.json. Graceful no-crash on any missing data."""
    if not metrics:
        print("Clubface debug: no metrics — run tracker first."); return

    frame_i = fa.face_frame if fa.face_frame is not None else (impact + fa.face_frame_offset)
    frame_i = max(0, min(N - 1, frame_i))

    ball_cx = ball_cy = ball_dia = None
    if track_results:
        res = track_results[frame_i]
        if res.get("chosen"):
            c = res["chosen"]
            mc = res.get("mask_center") or (c["cx"], c["cy"])
            ball_cx, ball_cy = float(mc[0]), float(mc[1])
            ball_dia = float(res.get("final_dia") or c["dia"])
        if ball_cx is None:
            det = [r for r in track_results if r.get("chosen")]
            if det:
                nr = min(det, key=lambda r: abs(r["idx"] - frame_i))
                c = nr["chosen"]
                mc = nr.get("mask_center") or (c["cx"], c["cy"])
                ball_cx, ball_cy = float(mc[0]), float(mc[1])
                ball_dia = float(nr.get("final_dia") or c["dia"])
    if ball_cx is None and metrics.get("ball3d"):
        ob = min(metrics["ball3d"], key=lambda o: abs(o["idx"] - frame_i))
        ball_cx, ball_cy = float(ob["cx"]), float(ob["cy"])
        ball_dia = float(ob["dia"])
    if ball_cx is None:
        print(f"Clubface debug: no ball position for frame {frame_i}.")
        _clubface_failure_fig(frame_i, "no_ball_position"); return

    co_near = sorted([o for o in club_obs if o.get("found") and o.get("bbox")],
                     key=lambda o: abs(o.get("idx", 9999) - frame_i))
    co_best = co_near[0] if co_near else None

    zero_deg = p.get("zero_deg", 0.0)
    roi = _clubface_roi_norm(ball_cx, ball_cy, ball_dia, co_best, fa)
    x0r = max(0, int(roi["x0"] * W)); y0r = max(0, int(roi["y0"] * H))
    x1r = min(W, int(roi["x1"] * W)); y1r = min(H, int(roi["y1"] * H))
    crop_w = x1r - x0r; crop_h = y1r - y0r

    face_result = None; excl = None; gray_crop = None
    if crop_w >= 10 and crop_h >= 10:
        crop = raw_frames[frame_i][y0r:y1r, x0r:x1r].astype(np.float32)
        gray_crop = np.mean(crop, axis=2)
        excl = _excl_mask_crop(crop_h, crop_w, ball_cx, ball_cy, ball_dia, x0r, y0r, fa)
        if fa.face_method in ("auto", "hough"):
            face_result = _detect_face_hough(gray_crop, excl, x0r, y0r, fa)
        if face_result is None and fa.face_method in ("auto", "pca"):
            face_result = _detect_face_pca(gray_crop, excl, x0r, y0r, fa)

    ainfo = _face_angle_info(face_result, zero_deg, fa) if face_result else None

    # Draw figure
    fig2, (ax_f, ax_z) = plt.subplots(1, 2, figsize=(16, 9), facecolor="#111",
                                       gridspec_kw={"width_ratios": [2, 1]})
    for ax in (ax_f, ax_z):
        ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values(): sp.set_color("#444")

    ax_f.imshow(raw_frames[frame_i], origin="upper", aspect="equal")

    bx = ball_cx * W; by = ball_cy * H; br = ball_dia * W / 2
    ax_f.add_patch(plt.Circle((bx, by), br, color="#44ff44", fill=False, lw=2.0, zorder=5))
    ax_f.plot(bx, by, "g+", markersize=10, mew=2, zorder=6)

    excl_r = ball_dia * W * fa.face_ball_exclusion_scale / 2
    ax_f.add_patch(plt.Circle((bx, by), excl_r, color="#ff9900",
                               fill=False, lw=1.5, ls="--", alpha=0.7, zorder=4))

    roi_xpx = roi["x0"] * W; roi_ypx = roi["y0"] * H
    roi_wpx = (roi["x1"] - roi["x0"]) * W; roi_hpx = (roi["y1"] - roi["y0"]) * H
    ax_f.add_patch(patches.Rectangle((roi_xpx, roi_ypx), roi_wpx, roi_hpx,
                                      lw=1.5, edgecolor="cyan", facecolor="none",
                                      ls="--", alpha=0.8, zorder=4))

    if co_best and co_best.get("bbox"):
        bbx, bby, bbw, bbh = co_best["bbox"]
        ax_f.add_patch(patches.Rectangle((bbx * W, bby * H), bbw * W, bbh * H,
                                          lw=2, edgecolor="#ff9900", facecolor="none", zorder=4))

    zero_rad = math.radians(zero_deg)
    ref_len = min(W, H) * 0.22
    ax_f.plot([bx, bx + ref_len * math.cos(zero_rad)],
              [by, by - ref_len * math.sin(zero_rad)],
              color="white", lw=2, ls="--", alpha=0.9, zorder=5)
    ax_f.text(bx + ref_len * math.cos(zero_rad) + 6,
              by - ref_len * math.sin(zero_rad),
              f"0 deg ref ({zero_deg:+.1f})", color="white", fontsize=8, va="center")

    if face_result and ainfo:
        cx_f = face_result["cx"] * W; cy_f = face_result["cy"] * H
        arad = ainfo["angle_rad_used"]
        adx = math.cos(arad); ady = math.sin(arad)
        half = min(W, H) * 0.15
        if "endpoints" in face_result:
            x1e = face_result["endpoints"][0] * W; y1e = face_result["endpoints"][1] * H
            x2e = face_result["endpoints"][2] * W; y2e = face_result["endpoints"][3] * H
            ax_f.plot([x1e, x2e], [y1e, y2e], color="magenta", lw=3, alpha=0.95, zorder=8)
        else:
            ax_f.plot([cx_f - adx * half, cx_f + adx * half],
                      [cy_f - ady * half, cy_f + ady * half],
                      color="magenta", lw=3, alpha=0.95, zorder=8)
        ax_f.plot(cx_f, cy_f, "m+", markersize=12, mew=2.5, zorder=9)
        ray_len = min(W, H) * 0.25
        ax_f.annotate("", xy=(cx_f + adx * ray_len, cy_f + ady * ray_len),
                      xytext=(cx_f, cy_f),
                      arrowprops=dict(arrowstyle="->", color="#ffff00", lw=2.5), zorder=10)
        ann = (f"Face: {ainfo['display']}\n"
               f"method: {face_result['method']}\n"
               f"coherence: {face_result['coherence']:.2f}\n"
               f"edge pts: {face_result['edge_count']}")
        ax_f.text(0.02, 0.97, ann, color="magenta", fontsize=9,
                  transform=ax_f.transAxes, va="top", family="monospace",
                  bbox=dict(facecolor="#111", alpha=0.75, boxstyle="round,pad=0.3"))
    else:
        ax_f.text(0.02, 0.97, "Face: not detected",
                  color="#ff6644", fontsize=9, transform=ax_f.transAxes, va="top",
                  family="monospace",
                  bbox=dict(facecolor="#111", alpha=0.75, boxstyle="round,pad=0.3"))

    ax_f.text(0.99, 0.01,
              "green = ball  orange dashed = excl zone\n"
              "cyan dashed = search ROI  orange box = club\n"
              "white dashed = 0 deg ref  magenta = face line\n"
              "yellow arrow = projection ray",
              color="white", fontsize=7.5, transform=ax_f.transAxes,
              va="bottom", ha="right", family="monospace",
              bbox=dict(facecolor="#111", alpha=0.72, boxstyle="round,pad=0.3"))

    rel = frame_i - impact
    phase = "IMPACT" if rel == 0 else (f"pre {rel}" if rel < 0 else f"post +{rel}")
    ax_f.set_title(f"Clubface Debug  Frame {frame_i} [{phase}]  "
                   f"method={fa.face_method}  0deg={zero_deg:+.1f}",
                   color="white", fontsize=11, pad=6)

    if gray_crop is not None:
        crop_rgb = raw_frames[frame_i][y0r:y1r, x0r:x1r]
        ax_z.imshow(crop_rgb, origin="upper", aspect="equal", extent=[x0r, x1r, y1r, y0r])
        ax_z.add_patch(plt.Circle((bx, by), excl_r, color="#ff9900",
                                   fill=False, lw=1.5, ls="--", alpha=0.7))
        if face_result and ainfo:
            cx_f = face_result["cx"] * W; cy_f = face_result["cy"] * H
            arad = ainfo["angle_rad_used"]
            adx = math.cos(arad); ady = math.sin(arad)
            half_z = min(crop_w, crop_h) * 0.45
            ax_z.plot([cx_f - adx * half_z, cx_f + adx * half_z],
                      [cy_f - ady * half_z, cy_f + ady * half_z],
                      color="magenta", lw=2.5, alpha=0.95)
            ax_z.plot(cx_f, cy_f, "m+", markersize=10, mew=2)
        ax_z.set_xlim(x0r, x1r); ax_z.set_ylim(y1r, y0r)
        ax_z.set_title("ROI Crop (full res)", color="white", fontsize=9, pad=4)
    else:
        ax_z.text(0.5, 0.5, "ROI too small", color="#777",
                  fontsize=10, ha="center", va="center", transform=ax_z.transAxes)
        ax_z.set_title("ROI Crop", color="white", fontsize=9, pad=4)

    plt.tight_layout(pad=0.5)
    out_png = os.path.join(FOLDER, "clubface_debug.png")
    fig2.savefig(out_png, dpi=150, facecolor="#111", bbox_inches="tight")
    plt.close(fig2)
    print(f"Saved: {out_png}")

    if fa.face_save_mask_debug and gray_crop is not None:
        _save_clubface_mask_debug(frame_i, gray_crop, excl, face_result, x0r, y0r, fa)

    _save_face_debug_json(frame_i, impact, ball_cx, ball_cy, ball_dia,
                          roi, face_result, ainfo, metrics, p, fa)

def _clubface_failure_fig(frame_i, reason):
    fig2, ax = plt.subplots(figsize=(10, 6), facecolor="#111")
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    ax.imshow(raw_frames[min(frame_i, N - 1)], origin="upper", aspect="equal")
    ax.text(0.5, 0.5, f"No clubface detected\n({reason})",
            color="#ff6644", fontsize=16, ha="center", va="center",
            transform=ax.transAxes, weight="bold",
            bbox=dict(facecolor="#111", alpha=0.8, boxstyle="round,pad=0.5"))
    ax.set_title(f"Clubface Debug  Frame {frame_i}  FAILED", color="#ff6644", fontsize=11)
    plt.tight_layout()
    out_png = os.path.join(FOLDER, "clubface_debug.png")
    fig2.savefig(out_png, dpi=150, facecolor="#111", bbox_inches="tight")
    plt.close(fig2)
    print(f"Saved (failure): {out_png}")

def _save_clubface_mask_debug(frame_i, gray_crop, excl, face_result, x0r, y0r, fa):
    _, _, mag = _sobel_mag(gray_crop.astype(float))
    fig2, axes = plt.subplots(1, 3, figsize=(15, 5), facecolor="#111")
    for ax, img, title, cmap in zip(
            axes,
            [gray_crop, mag, excl.astype(float) * 255],
            ["Grayscale Crop", "Sobel Edge Magnitude", "Exclusion Mask"],
            ["gray", "hot", "gray"]):
        ax.imshow(img, cmap=cmap, origin="upper")
        ax.set_title(title, color="white", fontsize=9)
        ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values(): sp.set_color("#444")
    axes[1].contour(mag, levels=[fa.face_edge_threshold], colors=["cyan"], linewidths=0.8)
    plt.suptitle(f"Clubface Mask Debug  Frame {frame_i}", color="white", fontsize=10)
    plt.tight_layout()
    out_png = os.path.join(FOLDER, "clubface_mask_debug.png")
    fig2.savefig(out_png, dpi=120, facecolor="#111", bbox_inches="tight")
    plt.close(fig2)
    print(f"Saved: {out_png}")

def _save_face_debug_json(frame_i, impact, ball_cx, ball_cy, ball_dia,
                           roi, face_result, ainfo, metrics, p, fa):
    cp_ = (metrics or {}).get("club_path", {})
    payload = dict(
        schema="ballstrike.face_debug.v1",
        frameIndex=frame_i, impactFrameIndex=impact,
        zeroDegreeAngleDegrees=p.get("zero_deg", 0.0),
        faceDetectionMethod=fa.face_method,
        faceAngleNormalMode=fa.face_angle_normal_mode,
        ballCenter=dict(x=ball_cx, y=ball_cy),
        ballDiameter=ball_dia,
        searchROI=dict(x0=roi["x0"], y0=roi["y0"], x1=roi["x1"], y1=roi["y1"]),
        detectedFace=(dict(method=face_result["method"],
                           cx=face_result["cx"], cy=face_result["cy"],
                           angleRad=face_result["angle_rad"],
                           coherence=face_result["coherence"],
                           edgeCount=face_result["edge_count"],
                           endpoints=face_result.get("endpoints"))
                      if face_result else None),
        faceAngle=(dict(angleDegrees=ainfo["angle_deg"], display=ainfo["display"])
                   if ainfo else None),
        clubPathForReference=dict(angleDegrees=cp_.get("angle"),
                                  display=cp_.get("display", "--")),
        settings=dict(
            faceRoiScaleX=fa.face_roi_scale_x, faceRoiScaleY=fa.face_roi_scale_y,
            faceRoiOffsetX=fa.face_roi_offset_x, faceRoiOffsetY=fa.face_roi_offset_y,
            faceBallExclusionScale=fa.face_ball_exclusion_scale,
            faceEdgeThreshold=fa.face_edge_threshold,
            faceMinEdgePixels=fa.face_min_edge_pixels,
            facePcaOutlierTrim=fa.face_pca_outlier_trim,
            faceCannyLow=fa.face_canny_low, faceCannyHigh=fa.face_canny_high,
            faceHoughThreshold=fa.face_hough_threshold,
            faceHoughMinLength=fa.face_hough_min_length,
            faceHoughMaxGap=fa.face_hough_max_gap,
            faceAngleFlip=fa.face_angle_flip))
    out_json = os.path.join(FOLDER, "face_debug.json")
    with open(out_json, "w") as f:
        json.dump(payload, f, indent=2, sort_keys=True, default=lambda _: None)
    print(f"Saved: {out_json}")

# ── Club tracking — 4 modes ───────────────────────────────────────────────────
def _club_roi(ball_center, ball_dia, p):
    cx, cy = ball_center
    rw = ball_dia*p["club_roi_x"]; rh = ball_dia*p["club_roi_y"]
    if p.get("club_behind",1.0) >= 0.5: cx -= rw*0.30  # expanded: was 0.22
    x0=max(0,cx-rw/2); y0=max(0,cy-rh/2)
    x1=min(1,cx+rw/2); y1=min(1,cy+rh/2)
    return (x0, y0, max(0,x1-x0), max(0,y1-y0))

def find_club_blob(curr, prev, roi, ball_center, ball_dia, p):
    mode = p.get("club_mode","hybrid")
    x0n, y0n, wn, hn = roi
    stride = max(1, int(p.get("club_stride",2)))
    x0=max(0,int(x0n*W)); x1=min(W,int((x0n+wn)*W))
    y0=max(0,int(y0n*H)); y1=min(H,int((y0n+hn)*H))
    if x1<=x0 or y1<=y0: return None

    curr_patch = curr[y0:y1:stride, x0:x1:stride]
    rows, cols = curr_patch.shape[:2]
    if rows == 0 or cols == 0: return None

    py_coords = np.arange(y0, y1, stride)[:rows]
    px_coords = np.arange(x0, x1, stride)[:cols]

    cp_i = (curr_patch * 255).astype(np.int32)
    r_ch, g_ch, b_ch = cp_i[...,0], cp_i[...,1], cp_i[...,2]
    brightness = (r_ch + g_ch + b_ch) // 3

    canUseDiff = (prev is not None and p.get("club_use_diff",1.0) >= 0.5)
    diff_arr = np.zeros((rows,cols), dtype=np.int32)
    if canUseDiff:
        prev_patch = (prev[y0:y1:stride, x0:x1:stride]*255).astype(np.int32)
        diff_arr = np.abs(cp_i - prev_patch).mean(axis=2).astype(np.int32)

    edge_arr = np.zeros((rows,cols), dtype=float)
    if mode in ("edgeBlob","hybrid"):
        gray = brightness.astype(float)
        dy = np.zeros_like(gray); dx = np.zeros_like(gray)
        if rows > 2: dy[1:-1] = (gray[2:] - gray[:-2]) / 2.0
        if cols > 2: dx[:,1:-1] = (gray[:,2:] - gray[:,:-2]) / 2.0
        edge_arr = np.sqrt(dx**2 + dy**2)

    dark_thr = int(p["club_dark"]); diff_thr = int(p["club_diff"])
    edge_thr = float(p.get("club_edge_thresh",20))

    if mode == "frameDiff":
        active = (diff_arr >= diff_thr) if canUseDiff else np.zeros((rows,cols),dtype=bool)
    elif mode == "darkBlob":
        active = brightness <= dark_thr
    elif mode == "edgeBlob":
        active = edge_arr >= edge_thr
    else:  # hybrid
        active = (brightness <= dark_thr)
        if canUseDiff: active = active | (diff_arr >= diff_thr)
        active = active | (edge_arr >= edge_thr)

    # Exclusion zone
    bx, by = ball_center[0]*W, ball_center[1]*H
    excl_r = ball_dia * W * p["club_exclusion"] / 2
    px_grid = px_coords[None,:]  # (1,cols)
    py_grid = py_coords[:,None]  # (rows,1)
    dist_sq = (px_grid - bx)**2 + (py_grid - by)**2
    active = active & (dist_sq > excl_r**2)

    if not active.any(): return None

    visited = np.zeros_like(active, dtype=bool)
    blobs = []
    for start_r, start_c in zip(*np.where(active)):
        if visited[start_r, start_c]: continue
        q = deque([(int(start_r), int(start_c))]); visited[start_r,start_c] = True
        pxs, pys = [], []
        while q:
            rr, cc = q.popleft()
            pxs.append(int(px_coords[cc])); pys.append(int(py_coords[rr]))
            for dr, dc in [(-1,0),(1,0),(0,-1),(0,1)]:
                nr, nc = rr+dr, cc+dc
                if 0<=nr<rows and 0<=nc<cols and active[nr,nc] and not visited[nr,nc]:
                    visited[nr,nc]=True; q.append((nr,nc))
        count = len(pxs)
        if count < int(p["club_min_area"]) or count > int(p["club_max_area"]): continue
        min_x,max_x = min(pxs),max(pxs); min_y,max_y = min(pys),max(pys)
        cx_ = float(np.mean(pxs)); cy_ = float(np.mean(pys))
        width = max(1, max_x-min_x+stride); height = max(1, max_y-min_y+stride)
        elong = max(width/height, height/width)
        conf = min(1.0, 0.65*min(1,count/max(1,int(p["club_min_area"])*10)) + 0.35*min(1,elong/4))
        closest_i = int(np.argmin([(pxs[k]-bx)**2+(pys[k]-by)**2 for k in range(count)]))
        dist = math.hypot(cx_-bx, cy_-by) / max(W,H)
        score = dist - min(0.04, elong*0.004) - conf*0.02
        blobs.append(dict(score=score, count=count, conf=conf,
                          cx=cx_/W, cy=cy_/H,
                          lead_x=pxs[closest_i]/W, lead_y=pys[closest_i]/H,
                          bbox=(min_x/W, min_y/H, (max_x-min_x+stride)/W, (max_y-min_y+stride)/H),
                          reason=f"club_{mode}"))
    if not blobs: return None
    best = min(blobs, key=lambda b: b["score"])
    return best if best["conf"] >= p["club_min_conf"] else None

def nearest_ball_result(results, idx):
    with_ball = [r for r in results if r.get("chosen")]
    if not with_ball: return None
    return min(with_ball, key=lambda r: abs(r["idx"]-idx))

def run_club_tracker(frames_norm, results, impact, p):
    if p.get("club_enabled",1.0) < 0.5: return []
    start, end = max(0,impact-10), min(N-1,impact+1)
    out = []
    for idx in range(start, end+1):
        br = nearest_ball_result(results, idx)
        if not br or not br.get("chosen"):
            out.append(dict(idx=idx, found=False, reason="no_ball_reference")); continue
        c = br["chosen"]
        ball_center = br.get("mask_center") or (c["cx"], c["cy"])
        ball_dia = br.get("final_dia") or c["dia"]
        roi = _club_roi(ball_center, ball_dia, p)
        prev = frames_norm[idx-1] if idx > 0 else None
        blob = find_club_blob(frames_norm[idx], prev, roi, ball_center, ball_dia, p)
        obs = dict(idx=idx, roi=roi, ball_center=ball_center,
                   exclusion_dia=ball_dia*p["club_exclusion"], found=blob is not None,
                   reason="no_club_blob")
        if blob: obs.update(blob); obs["reason"] = blob["reason"]
        out.append(obs)
    found = sum(1 for o in out if o.get("found"))
    print(f"Club tracking complete: {found}/{len(out)} detected")
    return out

def calc_club_metrics(club_obs, ball3d, impact, p):
    warns = ["Club speed approximate: depth assumed from ball depth near impact."]
    nearby = [o for o in ball3d if o["idx"] >= impact-1]
    if not nearby:
        return dict(club_speed=None,points=0,quality=0,method="not_enough_data",
                    warnings=warns+["No ball depth near impact."],speed_frames=[])
    depth = min(nearby, key=lambda o: abs(o["idx"]-impact))["pos"][2]
    fx, fy = focal_lengths(p)
    points = []
    for o in club_obs:
        if o.get("found") and o["idx"] <= impact:
            x = o.get("lead_x", o.get("cx")); y = o.get("lead_y", o.get("cy"))
            if x is None or y is None: continue
            points.append(dict(idx=o["idx"], t=rel_times[o["idx"]],
                               pos=image_point_to_3d(x,y,depth,fx,fy), conf=o.get("conf",0)))
    if len(points) < 2:
        return dict(club_speed=None,points=len(points),quality=0,method="not_enough_data",
                    warnings=warns+["Not enough club points."],speed_frames=[p["idx"] for p in points])
    vel, method = fit_velocity(points)
    if vel is None:
        return dict(club_speed=None,points=len(points),quality=0,method=method,
                    warnings=warns,speed_frames=[p["idx"] for p in points])
    speed = float(np.linalg.norm(vel)) * 2.23694
    avg_conf = sum(p_["conf"] for p_ in points)/len(points)
    print(f"Club speed: {speed:.1f} mph ({len(points)} pts)")
    return dict(club_speed=speed, points=len(points),
                quality=min(1.0,len(points)/6)*avg_conf*0.65,
                method=method, warnings=warns, speed_frames=[p_["idx"] for p_ in points])

def compute_metrics_and_club(frames_norm, results, impact, p):
    ball3d = ball_3d_observations(results, p)
    ball = calc_ball_metrics(ball3d, impact, p=p)
    club_obs = run_club_tracker(frames_norm, results, impact, p)
    club = calc_club_metrics(club_obs, ball3d, impact, p)
    smash = None
    if ball["ball_speed"] and club["club_speed"] and club["club_speed"] > 0:
        smash = ball["ball_speed"] / club["club_speed"]

    ccf = p.get("carry_correction_factor", 0.75)
    dist = estimate_distance(ball["ball_speed"], ball["vla"], ball["hla"],
                             carry_correction_factor=ccf)
    club_path = estimate_club_path(club_obs, p.get("zero_deg", 0), impact)
    face      = estimate_face_angle(club_obs, p.get("zero_deg", 0), impact,
                                    club_path["angle"])
    spin      = estimate_spin(ball["ball_speed"], ball["vla"], ball["hla"],
                              club_path["angle"])

    warnings = sorted(set(ball["warnings"] + club["warnings"] + dist["warnings"] +
                          spin["warnings"] + club_path["warnings"] + face["warnings"] +
                          ["Experimental FOV calibration is estimated."]))
    fmt = lambda v,s="",d=1: "—" if v is None else f"{v:.{d}f}{s}"
    print(f"Ball: {fmt(ball['ball_speed'],' mph')} HLA={format_lr(ball['hla'])} VLA={fmt(ball['vla'],'°')}")
    print(f"Club: {fmt(club['club_speed'],' mph')}  Smash: {fmt(smash,'',2)}")
    print(f"Carry: {fmt(dist['carry'],' yd',0)} (ideal={fmt(dist['ideal_carry'],' yd',0)} × cf={ccf:.2f})"
          f"  Total: {fmt(dist['total'],' yd',0)}")
    print(f"Backspin(est): {fmt(spin['backspin'],' rpm',0)}  "
          f"Sidespin: {spin['sidespin_display']}  SpinAxis: {spin['spin_axis_display']}")
    print(f"ClubPath(est): {club_path['display']}  Face(est): [PCA pending...]")
    return dict(ball3d=ball3d, ball=ball, club_obs=club_obs, club=club,
                smash=smash, distance=dist, spin=spin, club_path=club_path,
                face_angle=face, warnings=warnings)

def write_python_metrics_json(results, metrics, impact, fallback, reason):
    if not metrics: return
    def clean(v):
        if isinstance(v, np.ndarray): return [clean(x) for x in v.tolist()]
        if isinstance(v, (np.floating, np.integer)): return v.item()
        if isinstance(v, np.bool_): return bool(v)
        if isinstance(v, dict): return {k: clean(val) for k,val in v.items()}
        if isinstance(v, (list,tuple)): return [clean(x) for x in v]
        return v
    ball_obs = []
    for r in results:
        c = r.get("chosen")
        _rank = None
        if c and r.get("candidates"):
            _elig = [x for x in r["candidates"] if x.get("accepted", True)]
            _elig_s = sorted(_elig, key=lambda x: x.get("total_score", 0), reverse=True)
            for _ri, _rc in enumerate(_elig_s):
                if _rc is c or (_rc["cx"] == c["cx"] and _rc["cy"] == c["cy"]):
                    _rank = _ri; break
        ball_obs.append(dict(frameIndex=r["idx"], detected=c is not None,
            centerX=(r.get("mask_center") or (c["cx"],c["cy"]))[0] if c else None,
            centerY=(r.get("mask_center") or (c["cx"],c["cy"]))[1] if c else None,
            diameter=r.get("final_dia"), candidateDiameter=c["dia"] if c else None,
            maskRefinedDiameter=r.get("mask_dia"), confidence=c.get("conf",0) if c else 0,
            diameterDebugReason=r.get("mask_reason"), maskWhitePixelCount=r.get("mask_count",0),
            maskFillRatio=r.get("mask_fill_ratio"), maskBrightnessMean=r.get("mask_brightness_mean"),
            lineFitBoostScore=c.get("line_fit_boost_score") if c else None,
            predBoostScore=c.get("pred_boost_score") if c else None,
            hlaClonenessScore=c.get("hla_closeness_score") if c else None,
            candHLADegrees=c.get("cand_hla") if c else None,
            totalScore=c.get("total_score") if c else None,
            selectedCandidateRank=_rank,
            rescued=r.get("rescued", False),
            predictionDisabled=r.get("prediction_disabled", False),
            rejectionReason=c.get("reason") if c else None,
            predictionRescued=r.get("prediction_rescued", False),
            predRescueInsideRect=r.get("pred_rescue_inside_rect", False),
            predRescueInsideCircle=r.get("pred_rescue_inside_circle", False),
            predRescueDist=r.get("pred_rescue_dist"),
            maskAspectRatio=r.get("mask_aspect_ratio"),
            predictionMode=r.get("predictionMode"),
            mergedClubHints=r.get("merged_club_hints", []),
            edgeRejected=r.get("edge_rejected", False),
            excludedFromMetricsEdge=r.get("excluded_from_metrics_edge", False),
            edgeRejectReason=r.get("edge_reject_reason"),
            edgeBounds=r.get("edge_bounds")))
    b_ = metrics["ball"]; dist_ = metrics["distance"]
    spin_ = metrics.get("spin", {}); cp_ = metrics.get("club_path", {})
    fa_ = metrics.get("face_angle", {})
    bm_dx = b_.get("hla_dx"); bm_dy = b_.get("hla_dy")
    payload = dict(
        schema="ballstrike.python_shot_tester_metrics.v2",
        sourceName=os.path.basename(os.path.abspath(FOLDER)),
        detectedImpactFrameIndex=impact, fallbackImpactFrameIndex=fallback,
        impactDetectionReason=reason,
        zeroDegreeReferenceAngleDegrees=params["zero_deg"],
        calibration=dict(horizontalFOVDegrees=params["fov_x"], verticalFOVDegrees=params["fov_y"],
                         imageWidthPixels=W, imageHeightPixels=H,
                         realBallDiameterMeters=params["ball_diam_m"],
                         focalLengthPixelsX=focal_lengths(params)[0],
                         focalLengthPixelsY=focal_lengths(params)[1]),
        metrics=dict(ballSpeedMph=b_["ball_speed"],
                     hlaDegrees=b_["hla"],
                     hlaDisplay=format_lr(b_["hla"]),
                     hla3DRawDegrees=b_.get("hla_3d_raw"),
                     hlaReferenceAngle=params["zero_deg"],
                     hlaForwardComponent=b_.get("hla_forward"),
                     hlaLateralComponent=b_.get("hla_lateral"),
                     ballMovementVector2D=({"dx": bm_dx, "dy": bm_dy}
                                          if bm_dx is not None and bm_dy is not None else None),
                     vlaDegrees=b_["vla"],
                     vlaRaw3DDegrees=b_.get("vla_3d"),
                     vlaDiameterEstDegrees=b_.get("vla_diam_est"),
                     diameterGrowthFraction=b_.get("diam_growth"),
                     vlaModel=b_.get("vla_model","legacy"),
                     vlaPinholeDebug=b_.get("pinhole_debug"),
                     clubSpeedMph=metrics["club"]["club_speed"], smashFactor=metrics["smash"],
                     idealCarryYards=dist_.get("ideal_carry"),
                     carryCorrectionFactor=dist_.get("carry_correction_factor", 0.75),
                     carryYards=dist_["carry"],
                     rolloutYards=dist_.get("rollout_yards"),
                     rolloutFraction=dist_.get("rollout_fraction"),
                     vlaBucket=dist_.get("vla_bucket"),
                     totalYards=dist_["total"],
                     estimatedBackspinRpm=spin_.get("backspin"),
                     estimatedSidespinRpmSigned=spin_.get("sidespin"),
                     estimatedSidespinDisplay=spin_.get("sidespin_display","—"),
                     estimatedSpinAxisDegreesSigned=spin_.get("spin_axis"),
                     estimatedSpinAxisDisplay=spin_.get("spin_axis_display","—"),
                     spinEstimateMethod=spin_.get("method","unavailable"),
                     clubPathDegreesSigned=cp_.get("angle"),
                     clubPathDisplay=cp_.get("display","—"),
                     estimatedFaceAngleDegreesSigned=fa_.get("angle"),
                     estimatedFaceAngleDisplay=fa_.get("display","—"),
                     faceAngleConfidence=fa_.get("confidence","unavailable"),
                     faceSuppressedReason=fa_.get("suppressed_reason"),
                     faceToPathDegreesSigned=fa_.get("ftp"),
                     faceToPathDisplay=fa_.get("ftp_display","—"),
                     ballPointsUsed=b_["points"], clubPointsUsed=metrics["club"]["points"],
                     ballQuality=b_["quality"], clubQuality=metrics["club"]["quality"],
                     ballMethod=b_["method"], clubMethod=metrics["club"]["method"],
                     clubTrackingMode=club_mode_val,
                     clubSpeedFrameIndices=metrics["club"]["speed_frames"]),
        trackingQuality=dict(
            maskQualityRejectedCount=_last_tracking_stats.get("maskQualityRejectedCount", 0),
            tinyWeakRejectedCount=_last_tracking_stats.get("tinyWeakRejectedCount", 0),
            mergedClubBallRejectedCount=_last_tracking_stats.get("mergedClubBallRejectedCount", 0),
            predictionBoostAppliedCount=_last_tracking_stats.get("predictionBoostAppliedCount", 0),
            rescuedCandidateCount=_last_tracking_stats.get("rescuedCandidateCount", 0),
            offPathRejectedCount=_last_tracking_stats.get("offPathRejectedCount", 0),
            predictionDisabledFrame=_last_tracking_stats.get("predictionDisabledFrame"),
            ballTrackTerminatedFrame=_last_tracking_stats.get("ballTrackTerminatedFrame"),
            mergedShapeRejectedCount=_last_tracking_stats.get("earlyMergedStopperCount", 0),
            likelyMergedClubBallFrames=[r["idx"] for r in results if r.get("likely_merged_club_ball")],
            mergedShapeReasons={str(r["idx"]): r.get("merged_reason","") for r in results if r.get("likely_merged_club_ball")},
            coneRejectedCount=_last_tracking_stats.get("coneRejectedCount", 0),
            fullFrameRecoveryCount=_last_tracking_stats.get("fullFrameRecoveryCount", 0),
            verticalJumpRejectedCount=_last_tracking_stats.get("verticalJumpRejectedCount", 0),
            extremeDiameterMaxRatio=params.get("sc_extreme_dia_ratio", 4.0),
            impactMergedShapeRejectedCount=_last_tracking_stats.get("earlyMergedStopperCount", 0),
            predictionRescueAttemptedCount=_last_tracking_stats.get("predictionRescueAttemptedCount", 0),
            predictionRescueSuccessCount=_last_tracking_stats.get("predictionRescueSuccessCount", 0),
            predictionRescueRejectedWeakCount=_last_tracking_stats.get("predictionRescueRejectedWeakCount", 0),
            lineLikeMaskRejectedCount=_last_tracking_stats.get("lineLikeMaskRejectedCount", 0),
            singlePointPredictionUsedCount=_last_tracking_stats.get("singlePointPredictionUsedCount", 0),
            nearImpactDiamGuardRejectedCount=_last_tracking_stats.get("nearImpactDiamGuardRejectedCount", 0),
            edgeRejectedCount=_last_tracking_stats.get("edgeRejectedCount", 0),
            edgeRejectedFrames=_last_tracking_stats.get("edgeRejectedFrames", []),
            faceFrameOffset=int(_face_args.face_frame_offset),
            detectedImpactReason=reason,
        ),
        warnings=metrics["warnings"], ballTrackingObservations=ball_obs,
        ball3DObservations=[dict(frameIndex=o["idx"], relativeTime=o["t"],
            imageX=o["cx"], imageY=o["cy"], diameterNorm=o["dia"], diameterPixels=o["dia_px"],
            positionMeters=dict(x=o["pos"][0],y=o["pos"][1],z=o["pos"][2]),
            confidence=o["conf"]) for o in metrics["ball3d"]],
        clubObservations=[dict(frameIndex=o["idx"], detected=o.get("found",False),
            centerX=o.get("cx"), centerY=o.get("cy"),
            leadingEdgeX=o.get("lead_x"), leadingEdgeY=o.get("lead_y"),
            clubBoundingBox=dict(x=o["bbox"][0],y=o["bbox"][1],
                                 width=o["bbox"][2],height=o["bbox"][3]) if o.get("bbox") else None,
            detectionMode=o.get("reason","none"), confidence=o.get("conf",0),
            searchROI=o.get("roi"),
            ballExclusionCenterX=(o.get("ball_center") or (None,None))[0],
            ballExclusionCenterY=(o.get("ball_center") or (None,None))[1],
            ballExclusionDiameter=o.get("exclusion_dia"),
            debugReason=o.get("reason","")) for o in metrics["club_obs"]])
    out_path = os.path.join(FOLDER, "python_experimental_metrics.json")
    with open(out_path,"w") as f: json.dump(clean(payload),f,indent=2,sort_keys=True)
    print(f"Wrote: {out_path}")

# ── Default params ────────────────────────────────────────────────────────────
params = dict(
    stride=2,
    pre_bright=90, pre_spread=90, pre_min_samples=6,
    pre_min_nw=0.008, pre_max_nw=0.090, pre_min_nh=0.012, pre_max_nh=0.130,
    pre_min_asp=0.30, pre_max_asp=2.00,
    post_bright=92, post_spread=110, post_min_samples=4,
    post_min_nw=0.018, post_max_nw=0.120, post_min_nh=0.005, post_max_nh=0.150,
    post_min_asp=0.12, post_max_asp=5.00,
    pre_scale=5.67, impact_scale=8.66,
    post_base_scale=5.03, post_growth=5.00, post_max_scale=30.0,
    mask_scale=1.8, smooth_window=5,
    move_thresh=0.006, confirm_frames=2, stable_window=10,
    fov_x=70.0, fov_y=45.0, ball_diam_m=0.04267,
    club_enabled=1.0, club_behind=1.0, club_exclusion=1.8,
    club_roi_x=8.0, club_roi_y=6.0, club_use_diff=1.0,
    club_diff=34, club_dark=85, club_edge_thresh=20,
    club_min_area=5, club_max_area=6000, club_min_conf=0.20, club_stride=2,
    club_mode="frameDiff",
    zero_deg=0.0,
    carry_correction_factor=0.75,
    # Candidate scoring weights
    sc_bright_w=0.5, sc_size_w=4.0, sc_dist_w=2.5, sc_motion_w=1.5,
    sc_dir_w=1.0, sc_shape_w=0.5, sc_diam_w=2.0,
    # Motion prediction
    sc_lookback=3, sc_max_jump=0.10, sc_jump_by_dia=4.0, sc_jump_penalty=3.0,
    # Direction constraint
    sc_dir_penalty=1.5, sc_min_fwd=-0.005, sc_dir_alpha=0.35,
    # Diameter constraint
    sc_min_dia_ratio=0.35, sc_max_dia_ratio=2.25,
    sc_hard_reject_diam=1.0, sc_extreme_dia_ratio=4.0,
    # Club-like rejection
    sc_reject_club=1.0, sc_club_asp=4.0,
    # Launch direction / backward rejection / termination (Parts A–C)
    sc_monotonic=1.0, sc_lock_dist=0.02, sc_allow_backward=0.005,
    sc_backward_penalty=3.0, sc_hard_reject_backward=1.0,
    sc_termination=1.0, sc_term_miss_limit=3, sc_term_min_progress=0.05,
    sc_reacquire_term=0.0,
    # Part A — percentile mask threshold
    use_percentile_mask=1.0, mask_percentile=85.0,
    mask_pct_min_bright=80, mask_pct_max_bright=245, mask_bg_delta=15,
    mask_brightness=30,
    # Part B — diameter gates
    max_diam_growth_ratio=1.35, max_diam_ratio_to_pre_impact=4.0, hard_clamp_diameter=1.0,
    # Part E/F — metrics filtering
    metric_min_conf=0.35, metric_max_diam_ratio=1.75, metric_max_resid=0.025,
    # Part C — straight-line path constraint
    sc_straight_line=1.0, sc_straight_resid=0.018,
    sc_hard_reject_straight=1.0, sc_straight_penalty=4.0,
    # Part D — per-candidate HLA gating
    sc_max_cand_hla=35.0, sc_hard_reject_hla=1.0, sc_hla_soft_warn=20.0, sc_hla_penalty=2.0,
    # Part G — metric HLA suppression
    metric_max_hla=35.0,
    # New Part A — hard no-backward before launch
    hard_reject_behind_start=1.0, min_progress_before_launch=-0.003,
    use_ref_progress_before_launch=1.0,
    # Asymmetric pre-impact ROI (Part F updated)
    use_asymmetric_roi=1.0, pre_fwd_scale=5.5, pre_bwd_scale=1.8,
    near_fwd_scale=10.0, near_bwd_scale=2.5, near_impact_window=4,
    pre_vert_scale=1.4, near_vert_scale=2.0,
    # Diameter shrink clamp (Part G)
    min_diam_shrink_ratio=0.70, hard_clamp_diameter_shrink=1.0,
    diam_shrink_outlier_reject=1.0,
    # VLA from diameter growth (Part A/D updated)
    use_diam_growth_vla=1.0, diam_growth_vla_scale=140.0,
    diam_growth_vla_weight=0.75, image_y_vla_weight=0.25, max_vla_clamp=75.0,
    # Part A enhanced VLA
    slow_horizontal_progress_boost=1.0, slow_horiz_thresh=0.035,
    slow_horiz_vla_boost_mult=1.4, significant_diam_growth_thresh=0.10,
    very_high_launch_diam_growth_thresh=0.25,
    # New VLA model (pinhole2DSize)
    vla_model="pinhole2dsize",
    vla_image_y_weight=0.45,
    vla_diameter_depth_weight=0.55,
    vla_depth_sign=1.0,
    vla_depth_scale=1.0,
    use_rightward_perspective_correction=1.0,
    rightward_size_correction_strength=0.35,
    max_size_correction_ratio=1.35,
    vla_growth_boost_weight=0.30,
    vla_growth_boost_dia_scale=140.0,
    vla_significant_growth_thresh=0.10,
    vla_very_high_growth_thresh=0.25,
    vla_min_from_very_high_growth=30.0,
    max_vla_pinhole=70.0,
    # HLA closeness scoring (Part H raised to 3.0)
    sc_hla_closeness_w=3.0,
    # Part B mask quality gate (new session Part A: raised thresholds)
    require_min_mask_quality=1.0, min_mask_white_pixels=18,
    min_mask_white_fill_ratio=0.10, min_mask_brightness_mean=120,
    hard_reject_tiny_weak=1.0, min_post_impact_refined_diam_ratio=0.45,
    # Part C suspicious-selection fallback
    enable_suspicious_fallback=1.0, max_fallback_candidates=8,
    stationary_frame_limit=2, stationary_motion_thresh=0.004,
    max_pred_dist_before_fallback=0.080, max_line_resid_before_fallback=0.030,
    min_fwd_prog_before_fallback=-0.002,
    # Part D static false-object memory
    enable_static_false_object_memory=1.0, static_pos_tolerance=0.008,
    static_frame_limit=2, static_reject_after_limit=1.0,
    # Part E line-fit boost
    line_fit_boost_enabled=1.0, line_fit_strong_resid_thresh=0.008,
    line_fit_boost_weight=3.0, line_fit_progress_required=1.0,
    # New session Part B: merged club-ball rejection (first post-impact frames)
    enable_merged_reject=1.0, max_first_postimpact_diam_ratio=1.85,
    max_candidate_area_ratio_to_pre=3.00, merged_candidate_frame_window=3,
    # New session Part C: prediction cross boost
    enable_prediction_boost=1.0, prediction_inside_bonus=4.0,
    prediction_near_bonus=2.0, prediction_boost_radius_norm=0.045,
    prediction_dist_penalty_weight=3.0,
    # New session Part D: rescue pass
    enable_rescue_pass=1.0, rescue_max_candidates=6,
    rescue_line_resid_thresh=0.014, rescue_pred_dist_thresh=0.050,
    rescue_min_mask_pixels=18, rescue_min_diam_ratio=0.45,
    # Prediction cross rescue (new)
    enable_prediction_cross_rescue=1.0,
    prediction_rescue_window_frames=16,
    prediction_rescue_max_consec_misses=2,
    prediction_rescue_radius_norm=0.065,
    prediction_rescue_inside_bonus=12.0,
    prediction_rescue_near_bonus=7.0,
    prediction_rescue_max_line_residual=0.025,
    prediction_rescue_inside_circle_scale=1.25,
    prediction_rescue_allow_borderline_mask=1.0,
    prediction_rescue_min_mask_pixels=8,
    prediction_rescue_min_fill_ratio=0.045,
    prediction_rescue_min_diam_ratio=0.35,
    prediction_rescue_require_forward_progress=1.0,
    prediction_rescue_disable_after_termination=1.0,
    # Part A: improved impact detection
    impact_detect_use_diam_change=1.0,
    impact_diam_change_ratio=1.35,
    impact_diam_shrink_ratio=0.80,
    impact_return_minus_one=1.0,
    impact_min_stable_frames=6,
    # Part C: offscreen/edge ball rejection
    reject_edge_partial_ball=1.0,
    min_ball_margin_norm=0.012,
    # Part D: mask roundness / line-like rejection
    reject_line_like_mask=1.0,
    max_mask_aspect_for_ball=2.2,
    min_mask_aspect_for_ball=0.45,
    min_mask_component_pixels_for_ball=10,
    line_like_aspect_threshold=3.0,
    line_like_fill_max=0.18,
    # Part E: single-point prediction
    enable_single_point_prediction=1.0,
    single_point_prediction_max_step=0.12,
    single_point_prediction_min_step=0.006,
    # New session Part E: off-path hard rejection after launch
    hard_reject_far_off_path=1.0, max_off_path_dist_norm=0.060,
    # New session Part F: prediction termination (disable cross after N misses)
    disable_prediction_after_miss=1.0, prediction_miss_limit=3,
    # Face estimation guided by prior
    use_face_prior=1.0, face_prior_hla_weight=0.85, face_prior_club_weight=0.15,
    max_face_prior_dev=35.0, face_prior_score_weight=3.0,
    suppress_face_if_far_from_hla=1.0, max_face_ball_hla_difference=30.0,
    # Part B — enhanced merged shape stopper
    enable_early_merged_stopper=1.0,
    merged_shape_frame_window=3,
    max_early_diam_spike_ratio=1.60,
    max_early_area_spike_ratio=2.50,
    max_early_mask_bounds_spike_ratio=2.00,
    require_spike_then_drop=1.0,
    spike_drop_lookahead_frames=2,
    spike_drop_ratio_threshold=0.75,
    allow_gradual_diam_growth=1.0,
    max_gradual_growth_ratio_per_frame=1.35,
    # Part A: impact-frame spike ratio (separate from post-impact)
    max_impact_diam_spike_ratio=1.75,
    # Part C: cone/wedge candidate filter for post-impact
    use_cone_search=1.0,
    cone_half_angle_deg=18.0,
    cone_initial_length_norm=0.12,
    cone_length_growth_per_frame=0.035,
    cone_max_length_norm=0.75,
    cone_backward_allowance=0.015,
    cone_max_vert_expansion=0.22,
    cone_use_launch_dir=1.0,
    # Part D: full-frame recovery after cone miss
    enable_full_frame_recovery=1.0,
    recovery_min_mask_pixels=25,
    recovery_min_mask_fill_ratio=0.12,
    recovery_max_line_residual=0.035,
    recovery_max_hla_degrees=35.0,
    recovery_reject_tiny_weak=1.0,
    # Part E: tiny component mask_refine fix
    min_component_pixels=4,
    ignore_tiny_components=1.0,
    # Part F: vertical jump rejection
    max_downward_jump_per_frame=0.040,
    max_vertical_jump_from_path=0.050,
    vertical_jump_penalty_weight=4.0,
    hard_reject_large_downward_jump=1.0,
    use_fitted_path_for_vertical_gate=1.0,
    # Part A: asymmetric post-impact ROI
    post_fwd_scale=10.0,
    post_bwd_scale=1.2,
    post_vert_scale_untracked=1.5,
    post_vert_scale_tracked=2.5,
    reliable_track_min_points=2,
    # Part B: merged club hints
    use_merged_ball_club_hints=1.0,
    # Part C: near-impact diameter jump guard
    enable_near_impact_diam_guard=1.0,
    near_impact_diam_guard_window=2,
    near_impact_max_diam_growth=1.50,
    near_impact_min_diam_shrink=0.80,
    # Part D: preliminary mask scoring
    enable_prelim_mask_scoring=1.0,
    prelim_mask_window_scale=1.6,
    prelim_min_mask_pixels=8,
    prelim_min_fill_ratio=0.06,
    prelim_max_aspect=2.2,
    prelim_min_aspect=0.45,
    prelim_line_like_aspect=3.0,
    prelim_line_like_fill_max=0.18,
    prelim_roundness_weight=5.0,
    prelim_reject_line_like=1.0,
    # Part E: clean first point for prediction
    require_clean_first_point_for_prediction=1.0,
    # Final edge ball filter (post-rescue gate)
    enable_final_edge_ball_filter=1.0,
    final_edge_margin_norm=0.012,
    final_edge_radius_margin_scale=1.00,
    exclude_edge_ball_from_metrics=1.0,
)

# Override vla_model from CLI arg
params["vla_model"] = _face_args.vla_model

# ── State ─────────────────────────────────────────────────────────────────────
display_mode  = "darkened"
tracking_mode = "darkened"
club_mode_val = "frameDiff"
track_results = None
_last_tracking_stats = {}
club_results  = []
metrics_data  = None
detected_impact      = impact_idx
fallback_impact_disp = impact_idx
det_reason_disp      = "not_run"
current_frame = impact_idx
club_frame_idx = 0
current_page  = "ball"
norm_cache = {}
face_debug_data = None

def get_norm(mode):
    if mode not in norm_cache:
        norm_cache[mode] = [normalize(f, mode) for f in raw_frames]
    return norm_cache[mode]

def club_window():
    start = max(0, detected_impact-10)
    end   = min(N-1, detected_impact+1)
    return list(range(start, end+1))

# ── Figure ────────────────────────────────────────────────────────────────────
fig = plt.figure(figsize=(18, 10), facecolor="#111")
fig.canvas.manager.set_window_title("Ball/Club Tracking Tuner")

# Page tab buttons (top of content area)
ax_tb  = fig.add_axes([0.01, 0.955, 0.13, 0.038])
ax_tc  = fig.add_axes([0.15, 0.955, 0.13, 0.038])
ax_tm  = fig.add_axes([0.29, 0.955, 0.13, 0.038])
ax_tf  = fig.add_axes([0.43, 0.955, 0.13, 0.038])
btn_tb = Button(ax_tb, "● Ball Tracking", color="#553399", hovercolor="#7744bb")
btn_tc = Button(ax_tc, "○ Club Tracking", color="#2a2a2a", hovercolor="#3a3a3a")
btn_tm = Button(ax_tm, "○ Metrics",       color="#2a2a2a", hovercolor="#3a3a3a")
btn_tf = Button(ax_tf, "○ Clubface",      color="#2a2a2a", hovercolor="#3a3a3a")
for b in [btn_tb, btn_tc, btn_tm, btn_tf]:
    b.label.set_color("white"); b.label.set_fontsize(9)

# ── Ball page axes ────────────────────────────────────────────────────────────
ax_img   = fig.add_axes([0.00, 0.215, 0.62, 0.730])
ax_strip = fig.add_axes([0.00, 0.135, 0.62, 0.070])
ax_fsl   = fig.add_axes([0.00, 0.068, 0.62, 0.060])
ax_info  = fig.add_axes([0.00, 0.000, 0.62, 0.068])
ax_mask  = fig.add_axes([0.44, 0.760, 0.17, 0.180])

# ── Club page axes ────────────────────────────────────────────────────────────
ax_cimg   = fig.add_axes([0.00, 0.215, 0.62, 0.730])
ax_cstrip = fig.add_axes([0.00, 0.135, 0.62, 0.070])
ax_csl    = fig.add_axes([0.00, 0.068, 0.62, 0.060])
ax_cinfo  = fig.add_axes([0.00, 0.000, 0.62, 0.068])

# ── Metrics page axes ─────────────────────────────────────────────────────────
ax_ml = fig.add_axes([0.00, 0.000, 0.41, 0.950])
ax_mr = fig.add_axes([0.42, 0.000, 0.21, 0.950])

# ── Clubface page axes ────────────────────────────────────────────────────────
# Image fills same footprint as ball/club page. Zoom crop is an inset like ax_mask.
ax_fdimg  = fig.add_axes([0.00, 0.215, 0.62, 0.730])
ax_fdzoom = fig.add_axes([0.43, 0.620, 0.18, 0.290])  # inset crop, like ax_mask
ax_fdinfo = fig.add_axes([0.00, 0.000, 0.62, 0.210])

# Face-page radio buttons live in the far-right sidebar (same slots as ax_track / ax_cmode).
# They're shown only on face page; ax_track/ax_cmode are shown only on non-face pages.
ax_fd_method = fig.add_axes([0.935, 0.720, 0.065, 0.110], facecolor="#1a1a2a")
ax_fd_nmode  = fig.add_axes([0.935, 0.555, 0.065, 0.140], facecolor="#1a1a2a")

for ax in [ax_img, ax_strip, ax_fsl, ax_info, ax_mask,
           ax_cimg, ax_cstrip, ax_csl, ax_cinfo, ax_ml, ax_mr,
           ax_fdimg, ax_fdzoom, ax_fdinfo]:
    ax.set_facecolor("#111")
    ax.tick_params(colors="white")
    for sp in ax.spines.values(): sp.set_color("#333")

for ax in [ax_img, ax_cimg, ax_fdimg, ax_fdzoom]: ax.set_xticks([]); ax.set_yticks([])
for ax in [ax_strip, ax_cstrip]: ax.set_xticks([]); ax.set_yticks([])
for ax in [ax_info, ax_cinfo, ax_fdinfo]: ax.set_xticks([]); ax.set_yticks([])
for ax in [ax_ml, ax_mr]: ax.set_xticks([]); ax.set_yticks([])
ax_mask.set_xticks([]); ax_mask.set_yticks([])
for sp in ax_mask.spines.values(): sp.set_color("#888"); sp.set_linewidth(1.5)
for ax in [ax_fd_method, ax_fd_nmode]:
    for sp in ax.spines.values(): sp.set_color("#444")

radio_fd_method = RadioButtons(ax_fd_method, ["auto","hough","pca"], active=0)
radio_fd_nmode  = RadioButtons(ax_fd_nmode,  ["line","normal"],      active=0)
for rb in [radio_fd_method, radio_fd_nmode]:
    for lbl in rb.labels: lbl.set_color("white"); lbl.set_fontsize(8)
ax_fd_method.set_title("Face Method", color="#aaa", fontsize=7, pad=2)
ax_fd_nmode.set_title("Angle Mode",   color="#aaa", fontsize=7, pad=2)

# Sync radio to whatever _face_args was set to from CLI
for lbl in radio_fd_method.labels:
    if lbl.get_text() == _face_args.face_method: lbl.set_weight("bold")
for lbl in radio_fd_nmode.labels:
    if lbl.get_text() == _face_args.face_angle_normal_mode: lbl.set_weight("bold")

# Hide all non-ball pages initially
BALL_AX  = [ax_img, ax_strip, ax_fsl, ax_info, ax_mask]
CLUB_AX  = [ax_cimg, ax_cstrip, ax_csl, ax_cinfo]
MET_AX   = [ax_ml, ax_mr]
FACE_AX  = [ax_fdimg, ax_fdzoom, ax_fdinfo, ax_fd_method, ax_fd_nmode]
for ax in CLUB_AX + MET_AX + FACE_AX: ax.set_visible(False)

# ── Frame sliders ─────────────────────────────────────────────────────────────
sl_frame = Slider(ax_fsl, "Frame", 0, N-1, valinit=current_frame, valstep=1, color="#444")
sl_frame.label.set_color("white"); sl_frame.valtext.set_color("white")

sl_cframe = Slider(ax_csl, "Club frame (0=impact-10)", 0, 20, valinit=10, valstep=1, color="#774400")
sl_cframe.label.set_color("white"); sl_cframe.valtext.set_color("white")

# ── Sidebar ───────────────────────────────────────────────────────────────────
ax_disp  = fig.add_axes([0.935, 0.855, 0.065, 0.110], facecolor="#222")
ax_track = fig.add_axes([0.935, 0.720, 0.065, 0.110], facecolor="#222")
ax_cmode = fig.add_axes([0.935, 0.555, 0.065, 0.140], facecolor="#222")
ax_run   = fig.add_axes([0.935, 0.490, 0.065, 0.050])
ax_metsm = fig.add_axes([0.640, 0.010, 0.285, 0.215])

for ax in [ax_metsm]:
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    for sp in ax.spines.values(): sp.set_color("#333")

radio_disp  = RadioButtons(ax_disp,  ["original","darkened","brightened"], active=1)
radio_track = RadioButtons(ax_track, ["original","darkened","brightened"], active=1)
radio_cmode = RadioButtons(ax_cmode, ["hybrid","frameDiff","darkBlob","edgeBlob"], active=1)
for rb in [radio_disp, radio_track, radio_cmode]:
    for lbl in rb.labels: lbl.set_color("white"); lbl.set_fontsize(8)
ax_disp.set_title("Display",  color="white", fontsize=8, pad=2)
ax_track.set_title("Tracker", color="white", fontsize=8, pad=2)
ax_cmode.set_title("Club Mode",color="white",fontsize=8, pad=2)

btn_run = Button(ax_run, "Run", color="#553399", hovercolor="#7744bb")
btn_run.label.set_color("white")

# ── Sliders ───────────────────────────────────────────────────────────────────
slider_defs = [
    ("stride",           1,    8,     params["stride"],            "Stride"),
    ("pre_bright",       40,   240,   params["pre_bright"],         "Pre Bright ≥"),
    ("pre_spread",       10,   180,   params["pre_spread"],         "Pre Spread ≤"),
    ("pre_min_samples",  1,    100,   params["pre_min_samples"],    "Pre MinSamples"),
    ("pre_min_nw",       0.001,0.25,  params["pre_min_nw"],         "Pre MinW"),
    ("pre_max_nw",       0.001,0.25,  params["pre_max_nw"],         "Pre MaxW"),
    ("pre_min_nh",       0.001,0.25,  params["pre_min_nh"],         "Pre MinH"),
    ("pre_max_nh",       0.001,0.25,  params["pre_max_nh"],         "Pre MaxH"),
    ("pre_min_asp",      0.05, 8.0,   params["pre_min_asp"],        "Pre MinAsp"),
    ("pre_max_asp",      0.05, 8.0,   params["pre_max_asp"],        "Pre MaxAsp"),
    ("post_bright",      40,   240,   params["post_bright"],        "Post Bright ≥"),
    ("post_spread",      10,   180,   params["post_spread"],        "Post Spread ≤"),
    ("post_min_samples", 1,    100,   params["post_min_samples"],   "Post MinSamples"),
    ("post_min_nw",      0.001,0.25,  params["post_min_nw"],        "Post MinW"),
    ("post_max_nw",      0.001,0.25,  params["post_max_nw"],        "Post MaxW"),
    ("post_min_nh",      0.001,0.25,  params["post_min_nh"],        "Post MinH"),
    ("post_max_nh",      0.001,0.25,  params["post_max_nh"],        "Post MaxH"),
    ("post_min_asp",     0.05, 8.0,   params["post_min_asp"],       "Post MinAsp"),
    ("post_max_asp",     0.05, 8.0,   params["post_max_asp"],       "Post MaxAsp"),
    ("pre_scale",        1,    40,    params["pre_scale"],          "Pre ROI Scale"),
    ("impact_scale",     1,    40,    params["impact_scale"],       "Impact Scale"),
    ("post_base_scale",  1,    40,    params["post_base_scale"],    "Post Base Scale"),
    ("post_growth",      0,    5,     params["post_growth"],        "Post Growth"),
    ("post_max_scale",   1,    40,    params["post_max_scale"],     "Post Max Scale"),
    ("mask_scale",           0.5,  4.0,   params["mask_scale"],          "Mask WindowScale"),
    ("mask_brightness",      5,    200,   params["mask_brightness"],     "Mask AbsBright"),
    ("use_percentile_mask",  0,    1,     params["use_percentile_mask"], "Mask UsePctile"),
    ("mask_percentile",      50,   99,    params["mask_percentile"],     "Mask Percentile"),
    ("mask_pct_min_bright",  20,   150,   params["mask_pct_min_bright"], "Mask PctMin"),
    ("mask_pct_max_bright",  150,  255,   params["mask_pct_max_bright"], "Mask PctMax"),
    ("mask_bg_delta",        0,    50,    params["mask_bg_delta"],       "Mask BgDelta"),
    ("max_diam_growth_ratio",1.0,  3.0,   params["max_diam_growth_ratio"],"DiamGrowthRatio"),
    ("max_diam_ratio_to_pre_impact",1.0,6.0,params["max_diam_ratio_to_pre_impact"],"DiamPreImpactRatio"),
    ("hard_clamp_diameter",  0,    1,     params["hard_clamp_diameter"], "DiamHardClamp"),
    ("metric_min_conf",      0,    1,     params["metric_min_conf"],     "MetricMinConf"),
    ("metric_max_diam_ratio",1.0,  5.0,   params["metric_max_diam_ratio"],"MetricMaxDiamR"),
    ("metric_max_resid",     0,    0.10,  params["metric_max_resid"],    "MetricMaxResid"),
    ("smooth_window",        2,    15,    params["smooth_window"],       "Smooth Window"),
    ("move_thresh",      0.001,0.030, params["move_thresh"],        "Impact MoveThresh"),
    ("confirm_frames",   1,    5,     params["confirm_frames"],     "Impact Confirm"),
    ("stable_window",    3,    20,    params["stable_window"],      "Impact StableWin"),
    ("fov_x",            35,   110,   params["fov_x"],              "FOV X°"),
    ("fov_y",            25,   90,    params["fov_y"],              "FOV Y°"),
    ("ball_diam_m",      0.035,0.050, params["ball_diam_m"],        "Ball Diam m"),
    ("zero_deg",        -45,   45,    params["zero_deg"],           "0° Ref Angle"),
    ("club_enabled",     0,    1,     params["club_enabled"],       "Club Enabled"),
    ("club_exclusion",   0.5,  5.0,   params["club_exclusion"],     "Club Excl x"),
    ("club_roi_x",       1,    16,    params["club_roi_x"],         "Club ROI X"),
    ("club_roi_y",       1,    12,    params["club_roi_y"],         "Club ROI Y"),
    ("club_diff",        1,    120,   params["club_diff"],          "Club FDiff ≥"),
    ("club_dark",        10,   180,   params["club_dark"],          "Club Dark ≤"),
    ("club_edge_thresh", 1,    100,   params["club_edge_thresh"],   "Club Edge ≥"),
    ("club_min_area",    1,    300,   params["club_min_area"],      "Club MinArea"),
    ("club_max_area",    100,  20000, params["club_max_area"],      "Club MaxArea"),
    ("club_min_conf",    0,    1,     params["club_min_conf"],      "Club MinConf"),
    ("club_stride",      1,    4,     params["club_stride"],        "Club Stride"),
    ("carry_correction_factor", 0.40, 1.20, params["carry_correction_factor"], "Carry Correction"),
    # Candidate scoring
    ("sc_bright_w",          0,    5,    params["sc_bright_w"],           "Sc: Bright W"),
    ("sc_size_w",            0,    5,    params["sc_size_w"],             "Sc: Size W"),
    ("sc_dist_w",            0,    5,    params["sc_dist_w"],             "Sc: Dist W"),
    ("sc_motion_w",          0,    5,    params["sc_motion_w"],           "Sc: Motion W"),
    ("sc_dir_w",             0,    5,    params["sc_dir_w"],              "Sc: Dir W"),
    ("sc_shape_w",           0,    5,    params["sc_shape_w"],            "Sc: Shape W"),
    ("sc_diam_w",            0,    5,    params["sc_diam_w"],             "Sc: Diam W"),
    ("sc_max_jump",          0.01, 0.30, params["sc_max_jump"],           "Sc: MaxJump"),
    ("sc_jump_by_dia",       1,    10,   params["sc_jump_by_dia"],        "Sc: JumpByDia"),
    ("sc_jump_penalty",      0,    10,   params["sc_jump_penalty"],       "Sc: JumpPenalty"),
    ("sc_dir_penalty",       0,    5,    params["sc_dir_penalty"],        "Sc: DirPenalty"),
    ("sc_min_dia_ratio",     0.1,  1.0,  params["sc_min_dia_ratio"],      "Sc: MinDiaRatio"),
    ("sc_max_dia_ratio",     1.0,  5.0,  params["sc_max_dia_ratio"],      "Sc: MaxDiaRatio"),
    ("sc_extreme_dia_ratio", 1.5,  8.0,  params["sc_extreme_dia_ratio"],  "Sc: ExtDiaRatio"),
    ("sc_club_asp",          2,    10,   params["sc_club_asp"],           "Sc: ClubAspMax"),
    ("sc_dir_alpha",         0.1,  1.0,  params["sc_dir_alpha"],          "Sc: DirAlpha"),
    ("sc_lookback",          1,    8,    params["sc_lookback"],           "Sc: Lookback"),
    ("sc_hard_reject_diam",    0,    1,    params["sc_hard_reject_diam"],     "Sc: HardRejDiam"),
    ("sc_reject_club",         0,    1,    params["sc_reject_club"],          "Sc: RejectClub"),
    # Launch direction / backward rejection / termination
    ("sc_monotonic",           0,    1,    params["sc_monotonic"],             "Sc: MonotonicProg"),
    ("sc_lock_dist",           0.005,0.10, params["sc_lock_dist"],             "Sc: LockDist"),
    ("sc_allow_backward",      0,    0.05, params["sc_allow_backward"],        "Sc: AllowBackward"),
    ("sc_backward_penalty",    0,    10,   params["sc_backward_penalty"],      "Sc: BackPenalty"),
    ("sc_hard_reject_backward",0,    1,    params["sc_hard_reject_backward"],  "Sc: HardRejBack"),
    ("sc_termination",         0,    1,    params["sc_termination"],           "Sc: Termination"),
    ("sc_term_miss_limit",     1,    10,   params["sc_term_miss_limit"],       "Sc: TermMissLim"),
    ("sc_term_min_progress",   0,    0.30, params["sc_term_min_progress"],     "Sc: TermMinProg"),
    ("sc_reacquire_term",      0,    1,    params["sc_reacquire_term"],        "Sc: ReacquireTerm"),
    # Part C — straight-line path constraint
    ("sc_straight_line",       0,    1,    params["sc_straight_line"],         "Sc: StraightLine"),
    ("sc_straight_resid",      0, 0.10,   params["sc_straight_resid"],        "Sc: StraightResid"),
    ("sc_hard_reject_straight",0,    1,    params["sc_hard_reject_straight"],  "Sc: HardRejStraight"),
    ("sc_straight_penalty",    0,   10,   params["sc_straight_penalty"],      "Sc: StraightPenalty"),
    # Part D — per-candidate HLA gating
    ("sc_max_cand_hla",       10,   90,   params["sc_max_cand_hla"],          "Sc: MaxCandHLA°"),
    ("sc_hard_reject_hla",     0,    1,   params["sc_hard_reject_hla"],       "Sc: HardRejHLA"),
    ("sc_hla_soft_warn",       5,   60,   params["sc_hla_soft_warn"],         "Sc: HLASoftWarn°"),
    ("sc_hla_penalty",         0,   10,   params["sc_hla_penalty"],           "Sc: HLAPenalty"),
    # Part G — metric HLA gate
    ("metric_max_hla",        10,   90,   params["metric_max_hla"],           "Metric MaxHLA°"),
    # New Part A — hard no-backward before launch
    ("hard_reject_behind_start",    0,    1,    params["hard_reject_behind_start"],     "A: HardRejBehind"),
    ("min_progress_before_launch", -0.02, 0.01, params["min_progress_before_launch"],   "A: MinProgPreLaunch"),
    ("use_ref_progress_before_launch",0,  1,    params["use_ref_progress_before_launch"],"A: UseRefProg"),
    # Part F: asymmetric pre-impact ROI (updated)
    ("use_asymmetric_roi",    0,    1,    params["use_asymmetric_roi"],        "F: AsymROI"),
    ("pre_fwd_scale",         1,   20,   params["pre_fwd_scale"],             "F: PreFwdScale"),
    ("pre_bwd_scale",         0.5,  5,   params["pre_bwd_scale"],             "F: PreBwdScale"),
    ("pre_vert_scale",        0.5,  8,   params["pre_vert_scale"],            "F: PreVertScale"),
    ("near_fwd_scale",        1,   25,   params["near_fwd_scale"],            "F: NearFwdScale"),
    ("near_bwd_scale",        0.5,  5,   params["near_bwd_scale"],            "F: NearBwdScale"),
    ("near_vert_scale",       0.5,  8,   params["near_vert_scale"],           "F: NearVertScale"),
    ("near_impact_window",    1,   10,   params["near_impact_window"],        "F: NearImpWin"),
    # Part A: asymmetric post-impact ROI
    ("post_fwd_scale",                  1.0, 20.0, params["post_fwd_scale"],              "Post: FwdScale"),
    ("post_bwd_scale",                  0.5, 5.0,  params["post_bwd_scale"],              "Post: BwdScale"),
    ("post_vert_scale_untracked",       0.5, 5.0,  params["post_vert_scale_untracked"],   "Post: VertUntracked"),
    ("post_vert_scale_tracked",         0.5, 8.0,  params["post_vert_scale_tracked"],     "Post: VertTracked"),
    # Part C (new): near-impact diameter guard
    ("enable_near_impact_diam_guard",   0,   1,    params["enable_near_impact_diam_guard"], "C: NearImpactGuard"),
    ("near_impact_max_diam_growth",     1.0, 3.0,  params["near_impact_max_diam_growth"], "C: MaxDiamGrowth"),
    ("near_impact_min_diam_shrink",     0.3, 1.0,  params["near_impact_min_diam_shrink"], "C: MinDiamShrink"),
    # Part D (new): preliminary mask scoring
    ("enable_prelim_mask_scoring",      0,   1,    params["enable_prelim_mask_scoring"],  "D: PrelimMask"),
    ("prelim_roundness_weight",         0,   10,   params["prelim_roundness_weight"],     "D: PrelimRoundW"),
    ("prelim_reject_line_like",         0,   1,    params["prelim_reject_line_like"],     "D: PrelimRejectLine"),
    # Part E (new): clean first point for prediction
    ("require_clean_first_point_for_prediction", 0, 1, params["require_clean_first_point_for_prediction"], "E: CleanFirstPt"),
    # Part G: diameter shrink clamp
    ("min_diam_shrink_ratio", 0.3,  1.0, params["min_diam_shrink_ratio"],     "G: MinShrinkRatio"),
    ("hard_clamp_diameter_shrink",0, 1,  params["hard_clamp_diameter_shrink"],"G: HardClampShrink"),
    ("diam_shrink_outlier_reject",0, 1,  params["diam_shrink_outlier_reject"],"G: ShrinkOutlierRej"),
    # Part A/D: VLA from diameter growth (updated)
    ("use_diam_growth_vla",   0,    1,   params["use_diam_growth_vla"],       "A: DiamGrowthVLA"),
    ("diam_growth_vla_scale", 0,  300,   params["diam_growth_vla_scale"],     "A: DiamGrowthScale"),
    ("diam_growth_vla_weight",0,    1,   params["diam_growth_vla_weight"],    "A: DiamVLAWeight"),
    ("max_vla_clamp",        30,   90,   params["max_vla_clamp"],             "A: MaxVLAClamp"),
    ("slow_horizontal_progress_boost",0,1,params["slow_horizontal_progress_boost"],"A: SlowHorizBoost"),
    ("slow_horiz_thresh",     0.005,0.1, params["slow_horiz_thresh"],         "A: SlowHorizThresh"),
    ("slow_horiz_vla_boost_mult",1.0,3.0,params["slow_horiz_vla_boost_mult"],"A: SlowHorizMult"),
    ("significant_diam_growth_thresh",0,0.5,params["significant_diam_growth_thresh"],"A: SigGrowthThr"),
    ("very_high_launch_diam_growth_thresh",0,0.5,params["very_high_launch_diam_growth_thresh"],"A: VHGrowthThr"),
    # Part H: HLA closeness (raised to 3.0)
    ("sc_hla_closeness_w",    0,    6,   params["sc_hla_closeness_w"],        "H: HLAClosenessW"),
    # Part B: mask quality gate
    ("require_min_mask_quality",0,  1,   params["require_min_mask_quality"],  "B: ReqMaskQuality"),
    ("min_mask_white_pixels", 1,   30,   params["min_mask_white_pixels"],     "B: MinMaskPx"),
    ("min_mask_white_fill_ratio",0,0.5,  params["min_mask_white_fill_ratio"], "B: MinFillRatio"),
    ("min_mask_brightness_mean",30,220,  params["min_mask_brightness_mean"],  "B: MinBrightMean"),
    # Part C: suspicious fallback
    ("enable_suspicious_fallback",0, 1,  params["enable_suspicious_fallback"],"C: SuspFallback"),
    ("max_fallback_candidates",1,   8,   params["max_fallback_candidates"],   "C: MaxFallback"),
    ("stationary_frame_limit",1,    6,   params["stationary_frame_limit"],    "C: StatFrameLim"),
    ("stationary_motion_thresh",0,0.02,  params["stationary_motion_thresh"],  "C: StatMotThr"),
    ("max_pred_dist_before_fallback",0,0.2,params["max_pred_dist_before_fallback"],"C: MaxPredDist"),
    ("max_line_resid_before_fallback",0,0.1,params["max_line_resid_before_fallback"],"C: MaxLineResid"),
    # Part D: static false-object memory
    ("enable_static_false_object_memory",0,1,params["enable_static_false_object_memory"],"D: StaticMemory"),
    ("static_pos_tolerance",  0.002,0.03,params["static_pos_tolerance"],      "D: StaticPosTol"),
    ("static_frame_limit",    1,    6,   params["static_frame_limit"],        "D: StaticFrameLim"),
    ("static_reject_after_limit",0, 1,   params["static_reject_after_limit"], "D: StaticRejAfter"),
    # Part E: line-fit boost
    ("line_fit_boost_enabled",0,    1,   params["line_fit_boost_enabled"],    "E: LineFitBoost"),
    ("line_fit_strong_resid_thresh",0,0.03,params["line_fit_strong_resid_thresh"],"E: LineFitResid"),
    ("line_fit_boost_weight", 0,    8,   params["line_fit_boost_weight"],     "E: LineFitW"),
    # Part I: club ROI expansion
    ("club_roi_x",            1,   20,   params["club_roi_x"],                "I: Club ROI X"),
    ("club_roi_y",            1,   15,   params["club_roi_y"],                "I: Club ROI Y"),
    # New session Part A: tiny mask / weak glare rejection
    ("hard_reject_tiny_weak",         0,  1,    params["hard_reject_tiny_weak"],         "nA: HardRejTiny"),
    ("min_post_impact_refined_diam_ratio",0,1,  params["min_post_impact_refined_diam_ratio"],"nA: MinRefDiamR"),
    # New session Part B: merged club-ball rejection
    ("enable_merged_reject",          0,  1,    params["enable_merged_reject"],          "nB: MergedReject"),
    ("max_first_postimpact_diam_ratio",1.0,4.0, params["max_first_postimpact_diam_ratio"],"nB: MaxMergedDiam"),
    ("merged_candidate_frame_window", 1,  8,    params["merged_candidate_frame_window"], "nB: MergedWinFr"),
    # New session Part C: prediction cross boost
    ("enable_prediction_boost",       0,  1,    params["enable_prediction_boost"],       "nC: PredBoost"),
    ("prediction_inside_bonus",       0,  8,    params["prediction_inside_bonus"],       "nC: PredInsideBonus"),
    ("prediction_near_bonus",         0,  6,    params["prediction_near_bonus"],         "nC: PredNearBonus"),
    ("prediction_boost_radius_norm",  0.005,0.15,params["prediction_boost_radius_norm"], "nC: PredBoostRadius"),
    ("prediction_dist_penalty_weight",0,  8,    params["prediction_dist_penalty_weight"],"nC: PredDistPenW"),
    # New session Part D: rescue pass
    ("enable_rescue_pass",            0,  1,    params["enable_rescue_pass"],            "nD: RescuePass"),
    ("rescue_max_candidates",         1,  12,   params["rescue_max_candidates"],         "nD: RescueMaxCands"),
    ("rescue_line_resid_thresh",      0,  0.05, params["rescue_line_resid_thresh"],      "nD: RescueLineResid"),
    ("rescue_pred_dist_thresh",       0,  0.15, params["rescue_pred_dist_thresh"],       "nD: RescuePredDist"),
    ("rescue_min_mask_pixels",        1,  40,   params["rescue_min_mask_pixels"],        "nD: RescueMinPx"),
    ("rescue_min_diam_ratio",         0,  1,    params["rescue_min_diam_ratio"],         "nD: RescueMinDiamR"),
    # Prediction cross rescue sliders
    ("enable_prediction_cross_rescue",    0, 1,    params["enable_prediction_cross_rescue"],    "PR: Enable"),
    ("prediction_rescue_radius_norm",     0.01, 0.15, params["prediction_rescue_radius_norm"],  "PR: RadiusNorm"),
    ("prediction_rescue_window_frames",   1, 20,   params["prediction_rescue_window_frames"],   "PR: WindowFrames"),
    ("prediction_rescue_max_consec_misses", 1, 5,  params["prediction_rescue_max_consec_misses"], "PR: MaxMisses"),
    ("prediction_rescue_inside_bonus",    0, 15,   params["prediction_rescue_inside_bonus"],    "PR: InsideBonus"),
    ("prediction_rescue_near_bonus",      0, 10,   params["prediction_rescue_near_bonus"],      "PR: NearBonus"),
    ("prediction_rescue_allow_borderline_mask", 0, 1, params["prediction_rescue_allow_borderline_mask"], "PR: BorderlineMask"),
    ("prediction_rescue_min_mask_pixels", 2, 30,   params["prediction_rescue_min_mask_pixels"], "PR: MinMaskPx"),
    ("prediction_rescue_min_fill_ratio",  0.01, 0.2, params["prediction_rescue_min_fill_ratio"], "PR: MinFillRatio"),
    # New session Part E: off-path hard rejection
    ("hard_reject_far_off_path",      0,  1,    params["hard_reject_far_off_path"],      "nE: HardRejOffPath"),
    ("max_off_path_dist_norm",        0,  0.2,  params["max_off_path_dist_norm"],        "nE: MaxOffPathDist"),
    # New session Part F: prediction termination
    ("disable_prediction_after_miss", 0,  1,    params["disable_prediction_after_miss"], "nF: DisablePred"),
    ("prediction_miss_limit",         1,  8,    params["prediction_miss_limit"],         "nF: PredMissLim"),
    # Face prior
    ("use_face_prior",        0,    1,   params["use_face_prior"],            "J: UseFacePrior"),
    ("face_prior_hla_weight", 0,    1,   params["face_prior_hla_weight"],     "J: FacePriorHLAW"),
    ("face_prior_club_weight",0,    1,   params["face_prior_club_weight"],    "J: FacePriorClubW"),
    ("max_face_prior_dev",    5,   90,   params["max_face_prior_dev"],        "J: MaxFacePriorDev"),
    ("face_prior_score_weight",0,  10,  params["face_prior_score_weight"],   "J: FacePriorScoreW"),
    # Part A: Face suppression from ball HLA
    ("suppress_face_if_far_from_hla", 0, 1,  params["suppress_face_if_far_from_hla"], "A: SuppressFarFromHLA"),
    ("max_face_ball_hla_difference",  5, 60, params["max_face_ball_hla_difference"],  "A: MaxFaceHLADiff"),
    # Part B: Enhanced early merged shape stopper
    ("enable_early_merged_stopper",      0, 1,    params["enable_early_merged_stopper"],      "B: EarlyMergedStopper"),
    ("merged_shape_frame_window",        1, 8,    params["merged_shape_frame_window"],         "B: MergedFrameWindow"),
    ("max_early_diam_spike_ratio",       1.0, 3.0, params["max_early_diam_spike_ratio"],       "B: MaxDiamSpikeRatio"),
    ("max_impact_diam_spike_ratio",      1.0, 3.0, params["max_impact_diam_spike_ratio"],      "B: MaxImpactDiamSpike"),
    ("max_early_area_spike_ratio",       1.0, 5.0, params["max_early_area_spike_ratio"],       "B: MaxAreaSpikeRatio"),
    ("require_spike_then_drop",          0, 1,    params["require_spike_then_drop"],           "B: RequireSpikeDropChk"),
    ("max_gradual_growth_ratio_per_frame", 1.0, 2.0, params["max_gradual_growth_ratio_per_frame"], "B: MaxGradualGrowth"),
    # Part C: cone search
    ("use_cone_search",               0, 1,    params["use_cone_search"],              "C: UseConeSearch"),
    ("cone_half_angle_deg",           5, 60,   params["cone_half_angle_deg"],          "C: ConeHalfAngleDeg"),
    ("cone_initial_length_norm",      0.01, 0.5, params["cone_initial_length_norm"],   "C: ConeInitLength"),
    ("cone_length_growth_per_frame",  0.005, 0.1, params["cone_length_growth_per_frame"], "C: ConeLengthGrowth"),
    ("cone_max_length_norm",          0.2, 1.0, params["cone_max_length_norm"],         "C: ConeMaxLength"),
    ("cone_backward_allowance",       0, 0.05,  params["cone_backward_allowance"],      "C: ConeBackwardAllow"),
    # Part D: full-frame recovery
    ("enable_full_frame_recovery",    0, 1,    params["enable_full_frame_recovery"],   "D: FullFrameRecovery"),
    ("recovery_min_mask_pixels",      5, 50,   params["recovery_min_mask_pixels"],     "D: RecovMinMaskPx"),
    # Part F: vertical jump rejection
    ("hard_reject_large_downward_jump", 0, 1, params["hard_reject_large_downward_jump"], "F: HardRejectDownJump"),
    ("max_downward_jump_per_frame",   0.01, 0.15, params["max_downward_jump_per_frame"], "F: MaxDownJumpPerFrame"),
    ("max_vertical_jump_from_path",   0.01, 0.15, params["max_vertical_jump_from_path"], "F: MaxVertFromPath"),
    ("vertical_jump_penalty_weight",  0, 10,  params["vertical_jump_penalty_weight"],  "F: VertJumpPenalty"),
    ("use_fitted_path_for_vertical_gate", 0, 1, params["use_fitted_path_for_vertical_gate"], "F: UseFittedPathGate"),
    # New VLA model (pinhole2DSize) sliders
    ("vla_image_y_weight",         0, 1,    params["vla_image_y_weight"],         "VLA: ImgYWeight"),
    ("vla_diameter_depth_weight",  0, 1,    params["vla_diameter_depth_weight"],  "VLA: DepthWeight"),
    ("vla_depth_sign",            -1, 1,    params["vla_depth_sign"],             "VLA: DepthSign"),
    ("vla_depth_scale",            0, 3,    params["vla_depth_scale"],            "VLA: DepthScale"),
    ("rightward_size_correction_strength", 0, 1, params["rightward_size_correction_strength"], "VLA: PerspStr"),
    ("use_rightward_perspective_correction", 0, 1, params["use_rightward_perspective_correction"], "VLA: UsePerspCorr"),
    ("vla_significant_growth_thresh", 0, 0.5, params["vla_significant_growth_thresh"], "VLA: SigGrowthThr"),
    ("vla_very_high_growth_thresh",   0, 0.5, params["vla_very_high_growth_thresh"],   "VLA: VHGrowthThr"),
    ("vla_min_from_very_high_growth", 0, 70,  params["vla_min_from_very_high_growth"], "VLA: MinVHGrowth"),
    ("max_vla_pinhole",              0, 70,   params["max_vla_pinhole"],               "VLA: MaxPinhole"),
    # Part A: improved impact detection
    ("impact_detect_use_diam_change",0, 1,   params["impact_detect_use_diam_change"], "IA: UseDiamChange"),
    ("impact_diam_change_ratio",  1.0, 3.0,  params["impact_diam_change_ratio"],      "IA: DiamChangeRatio"),
    ("impact_diam_shrink_ratio",  0.3, 1.0,  params["impact_diam_shrink_ratio"],      "IA: DiamShrinkRatio"),
    ("impact_return_minus_one",    0,  1,    params["impact_return_minus_one"],       "IA: ReturnMinusOne"),
    ("impact_min_stable_frames",   2,  12,   params["impact_min_stable_frames"],      "IA: MinStableFrames"),
    # Part C: offscreen/edge rejection
    ("reject_edge_partial_ball",   0,  1,    params["reject_edge_partial_ball"],      "EC: RejectEdgeBall"),
    ("min_ball_margin_norm",    0.002, 0.05, params["min_ball_margin_norm"],          "EC: MinBallMargin"),
    # Part D: line-like mask rejection
    ("reject_line_like_mask",      0,  1,    params["reject_line_like_mask"],         "LD: RejectLineLike"),
    ("max_mask_aspect_for_ball",  1.0, 5.0,  params["max_mask_aspect_for_ball"],      "LD: MaxMaskAspect"),
    ("min_mask_aspect_for_ball",  0.1, 1.0,  params["min_mask_aspect_for_ball"],      "LD: MinMaskAspect"),
    ("line_like_aspect_threshold",1.5, 8.0,  params["line_like_aspect_threshold"],    "LD: LineAspectThr"),
    ("line_like_fill_max",       0.01, 0.5,  params["line_like_fill_max"],            "LD: LineFillMax"),
    # Part E: single-point prediction
    ("enable_single_point_prediction",0, 1,  params["enable_single_point_prediction"],"SP: EnableSinglePt"),
    ("single_point_prediction_max_step",0.005,0.3,params["single_point_prediction_max_step"],"SP: MaxStep"),
    ("single_point_prediction_min_step",0.001,0.05,params["single_point_prediction_min_step"],"SP: MinStep"),
]

slider_h = 0.0105; slider_gap = 0.0007; sidebar_top = 0.985
sliders = {}
sidebar_sl_axes = []   # all regular slider axes — hidden on face page
for i, (key, lo, hi, val, lbl) in enumerate(slider_defs):
    y = sidebar_top - (i+1)*(slider_h+slider_gap)
    ax_s = fig.add_axes([0.640, y, 0.285, slider_h], facecolor="#222")
    sl = Slider(ax_s, lbl, lo, hi, valinit=val, color="#8844cc")
    sl.label.set_color("white");  sl.label.set_fontsize(7)
    sl.valtext.set_color("#aaa"); sl.valtext.set_fontsize(7)
    sliders[key] = sl
    sidebar_sl_axes.append(ax_s)

# ── Face-page tuning sliders (in the same sidebar area as regular sliders) ────
face_slider_defs = [
    ("face_edge_threshold",        5,   100, _face_args.face_edge_threshold,         "Edge Threshold"),
    ("face_frame_offset",         -5,     5, float(_face_args.face_frame_offset),    "Frame Offset"),
    ("face_roi_scale_x",         1.0,  10.0, _face_args.face_roi_scale_x,            "ROI Scale X"),
    ("face_roi_scale_y",         1.0,  10.0, _face_args.face_roi_scale_y,            "ROI Scale Y"),
    ("face_roi_offset_x",       -0.4,   0.4, _face_args.face_roi_offset_x,           "ROI Offset X"),
    ("face_roi_offset_y",       -0.4,   0.4, _face_args.face_roi_offset_y,           "ROI Offset Y"),
    ("face_ball_exclusion_scale", 0.5,   4.0, _face_args.face_ball_exclusion_scale,  "Ball Excl Scale"),
    ("face_min_edge_pixels",       5,   200, float(_face_args.face_min_edge_pixels), "Min Edge Pixels"),
    ("face_pca_outlier_trim",    0.0,   0.3, _face_args.face_pca_outlier_trim,       "PCA Outlier Trim"),
    ("face_angle_flip",          0.0,   1.0, float(_face_args.face_angle_flip),      "Angle Flip (0/1)"),
]
face_sliders = {}
face_sl_axes = []
# Face sliders intentionally start at y=0.220 going DOWN — the 44 regular sliders
# end at y≈0.259, so these positions never overlap with any regular slider axis.
# This makes it physically impossible for face slider events to bleed into ball tracking.
_face_sl_top = 0.220
_face_sl_step = 0.021
for _i, (_key, _lo, _hi, _val, _lbl) in enumerate(face_slider_defs):
    _y   = _face_sl_top - _i * _face_sl_step
    _axs = fig.add_axes([0.640, _y, 0.285, slider_h], facecolor="#1a1a2a")
    _sl  = Slider(_axs, _lbl, _lo, _hi, valinit=_val, color="#336699")
    _sl.label.set_color("white");   _sl.label.set_fontsize(8)
    _sl.valtext.set_color("#aaddff"); _sl.valtext.set_fontsize(8)
    face_sliders[_key] = _sl
    face_sl_axes.append(_axs)
FACE_AX.extend(face_sl_axes)
for _axs in face_sl_axes: _axs.set_visible(False)

# Face-page "Re-analyse" button — replaces the main Run button on this page.
# Clicking it ONLY re-runs face edge detection on already-computed results.
ax_fd_run = fig.add_axes([0.935, 0.490, 0.065, 0.050])
btn_fd_run = Button(ax_fd_run, "Re-analyse\nFace", color="#1a3355", hovercolor="#2a4466")
btn_fd_run.label.set_color("white"); btn_fd_run.label.set_fontsize(7)
FACE_AX.append(ax_fd_run)
ax_fd_run.set_visible(False)

# Sidebar axes hidden on face page: regular sliders + display/tracker/cmode radios + Run.
# This makes it impossible to accidentally re-run ball tracking from the face tab.
SIDEBAR_AX = sidebar_sl_axes + [ax_disp, ax_track, ax_cmode, ax_run]
# ax_metsm handled separately in set_page (hidden on both met and face)

# ── Draw functions ────────────────────────────────────────────────────────────
def draw_mask_preview():
    ax_mask.cla(); ax_mask.set_xticks([]); ax_mask.set_yticks([])
    ax_mask.set_facecolor("#111")
    for sp in ax_mask.spines.values(): sp.set_color("#888"); sp.set_linewidth(1.5)
    res = track_results[current_frame] if track_results else None
    preview = res.get("preview") if res else None
    if preview is not None:
        sz = preview.shape[1]
        ax_mask.imshow(preview, origin="upper", aspect="equal", interpolation="nearest")
        cx_c, cy_c = sz/2, sz/2
        if res.get("cand_in_crop") is not None:
            ax_mask.add_patch(plt.Circle((cx_c,cy_c), res["cand_in_crop"]*sz/2,
                color="red", fill=False, linewidth=1.5, alpha=0.9))
        if res.get("ref_in_crop") is not None:
            mc = res.get("mask_center_in_crop") or (0.5,0.5)
            ax_mask.add_patch(plt.Circle((mc[0]*sz,mc[1]*sz), res["ref_in_crop"]*sz/2,
                color="#44ff44", fill=False, linewidth=1.5, alpha=0.9))
            ax_mask.plot(mc[0]*sz, mc[1]*sz, "y.", markersize=5, zorder=5)
        ax_mask.set_title("Mask  ●red=cand  ●grn=refined", color="white", fontsize=7, pad=2)
    else:
        msg = ("run first" if not track_results
               else "no ball" if (res and not res.get("chosen")) else "no mask")
        ax_mask.text(0.5,0.5,msg,color="#555",fontsize=10,ha="center",va="center",
                     transform=ax_mask.transAxes)
        ax_mask.set_title("Mask Preview", color="#555", fontsize=7, pad=2)

def draw_ball_strip():
    ax_strip.cla(); ax_strip.set_facecolor("#111"); ax_strip.set_xticks([]); ax_strip.set_yticks([])
    for i in range(N):
        is_det  = (i == detected_impact)
        is_fall = (track_results is not None and i == fallback_impact_disp and i != detected_impact)
        is_cur  = (i == current_frame)
        if track_results:
            chosen = track_results[i]["chosen"]
            terminated = track_results[i].get("ball_terminated", False)
            pred_disabled = track_results[i].get("prediction_disabled", False)
            rescued = track_results[i].get("rescued", False)
            prediction_rescued = track_results[i].get("prediction_rescued", False)
            has_candidates = bool(track_results[i].get("candidates"))
            likely_merged = track_results[i].get("likely_merged_club_ball", False)
            excluded_merged = track_results[i].get("excluded_from_metrics_merged", False)
            edge_rejected   = track_results[i].get("edge_rejected", False)
            # Color hierarchy: impact > fallback > merged_stopper > chosen(pred_rescued) > chosen(rescued) > chosen > pred_disabled_miss > terminated > candidate_rejected > miss
            if is_det:
                color = "#ffdd00"
            elif is_fall:
                color = "#997700"
            elif likely_merged:
                color = "#9900cc"   # purple: early merged club-ball (Part B stopper)
            elif excluded_merged:
                color = "#cc00cc"   # magenta: excluded from metrics merged
            elif chosen and edge_rejected:
                color = "#8b0000"   # dark red: final edge filter rejected
            elif chosen and prediction_rescued:
                color = "#33ccff"   # light blue: prediction cross rescue detection
            elif chosen and rescued:
                color = "#00bbff"   # cyan: rescued detection
            elif chosen:
                color = "#44cc44"   # green: normal detection
            elif terminated:
                color = "#500000"   # very dark red: terminated
            elif pred_disabled and not terminated:
                color = "#666666"   # gray: prediction disabled, still trying
            elif has_candidates and not chosen:
                color = "#ff6600"   # orange: had candidates but all rejected
            else:
                color = "#cc4444"   # red: no candidates at all
        else:
            color = "#ffdd00" if is_det else "#444"
        ax_strip.add_patch(patches.Rectangle((i/N,0.1),1/N-0.005,0.8,
            linewidth=2 if is_cur else 0, edgecolor="white", facecolor=color))
        if club_results and any(o.get("idx")==i and o.get("found") for o in club_results):
            ax_strip.add_patch(patches.Circle((i/N+(1/N)/2,0.18),0.0075,color="#ff9900",zorder=5))
    ax_strip.set_xlim(0,1); ax_strip.set_ylim(0,1)

def draw_ball_image():
    ax_img.cla(); ax_img.set_xticks([]); ax_img.set_yticks([])
    norm = get_norm(display_mode)
    ax_img.imshow(norm[current_frame], origin="upper", aspect="equal")
    if track_results:
        res = track_results[current_frame]
        rx,ry,rw,rh = res["roi"][0]*W,res["roi"][1]*H,res["roi"][2]*W,res["roi"][3]*H
        ax_img.add_patch(patches.Rectangle((rx,ry),rw,rh,
            linewidth=1.5,edgecolor="cyan",facecolor="none",linestyle="--"))
        for cand in res["candidates"]:
            bx_,by_,bw2,bh2 = cand["rect"]
            if cand.get("backward_rejected"):
                color = "#660000"; lw_ = 1.5
                cx_c, cy_c = cand["cx"]*W, cand["cy"]*H
                ax_img.plot(cx_c, cy_c, "o", color="#660000", markersize=4, zorder=5)
            elif not cand["accepted"]:
                color = "#ff4444"; lw_ = 1
            else:
                color = "#ffee00"; lw_ = 1
            ax_img.add_patch(patches.Rectangle((bx_*W,by_*H),bw2*W,bh2*H,
                linewidth=lw_,edgecolor=color,facecolor="none",
                linestyle="--" if not cand["accepted"] else "-"))
        if res.get("predicted_pos"):
            ppx, ppy = res["predicted_pos"]
            ax_img.plot(ppx*W, ppy*H, "+", color="magenta", markersize=16, mew=2.5, zorder=6,
                        alpha=0.85)
        if res["chosen"]:
            c = res["chosen"]
            mc = res.get("mask_center") or (c["cx"],c["cy"])
            cx2,cy2 = mc[0]*W,mc[1]*H
            circle_d = res.get("mask_dia") or res.get("final_dia") or c["dia"]
            ax_img.add_patch(patches.Circle((cx2,cy2),circle_d*W/2,
                linewidth=2,edgecolor="#44ff44",facecolor="none"))
            ax_img.plot(cx2,cy2,"g.",markersize=5)

    # Ball path (post-impact cyan trail) — starts from lastPreImpactBallPoint (Part B)
    last_pre_impact_pt = None
    if track_results:
        for _r in reversed(track_results):
            if _r["idx"] < detected_impact and _r.get("chosen"):
                _c = _r["chosen"]
                _mc = _r.get("mask_center") or (_c["cx"], _c["cy"])
                last_pre_impact_pt = (_mc[0]*W, _mc[1]*H)
                break
    if metrics_data:
        post_pts = [(o["cx"]*W, o["cy"]*H) for o in metrics_data["ball3d"]
                    if o["idx"] > detected_impact]
        # Draw path from lastPreImpactBallPoint through post-impact points
        path_origin = last_pre_impact_pt or (post_pts[0] if post_pts else None)
        if path_origin and post_pts:
            all_path = [path_origin] + post_pts
            xs_,ys_ = zip(*all_path)
            ax_img.plot(xs_,ys_,color="#00ccff",lw=2,ls="--",alpha=0.85,zorder=4)
        if post_pts:
            ax_img.scatter(*zip(*post_pts),c="#00ccff",s=14,zorder=5,alpha=0.7)
        if path_origin:
            # Mark lastPreImpactBallPoint with a distinct dot
            if last_pre_impact_pt:
                ax_img.plot(last_pre_impact_pt[0],last_pre_impact_pt[1],"o",
                            color="#ffcc00",markersize=8,zorder=6,
                            markeredgecolor="white",markeredgewidth=1.5)
            # 0° reference line originates from path_origin
            x0_,y0_ = path_origin
            zero_rad = math.radians(params["zero_deg"])
            ll = min(W,H)*0.20
            x1_ = x0_ + ll*math.cos(zero_rad)
            y1_ = y0_ - ll*math.sin(zero_rad)
            ax_img.plot([x0_,x1_],[y0_,y1_],color="white",lw=1.5,ls="--",alpha=0.85,zorder=3)
            ax_img.text(x1_+6,y1_,"0° ref",color="white",fontsize=7,alpha=0.75,zorder=3)

    # Club path — orange solid through clubhead centers
    if club_results:
        path_pts = [(o["cx"]*W, o["cy"]*H)
                    for o in club_results if o.get("found") and o.get("cx") is not None]
        if len(path_pts) >= 2:
            xs_,ys_ = zip(*path_pts)
            ax_img.plot(xs_,ys_,color="#ff9900",lw=2,ls="-",alpha=0.85)
            ax_img.scatter(xs_,ys_,c="#ff9900",s=12,zorder=5,alpha=0.6)
        co = next((o for o in club_results if o.get("idx")==current_frame), None)
        if co:
            if co.get("roi"):
                rx_,ry_,rw_,rh_ = co["roi"]
                ax_img.add_patch(patches.Rectangle((rx_*W,ry_*H),rw_*W,rh_*H,
                    lw=1.5,edgecolor="#ff9900",facecolor="none",linestyle="--"))
            if co.get("ball_center") and co.get("exclusion_dia"):
                bxc,byc = co["ball_center"]
                ax_img.add_patch(patches.Circle((bxc*W,byc*H),co["exclusion_dia"]*W/2,
                    lw=1,edgecolor="#ff9900",facecolor="none",alpha=0.35))
            if co.get("found"):
                if co.get("bbox"):
                    bbx,bby,bbw,bbh = co["bbox"]
                    ax_img.add_patch(patches.Rectangle((bbx*W,bby*H),bbw*W,bbh*H,
                        lw=2,edgecolor="#ff9900",facecolor="none"))
                ax_img.plot(co["cx"]*W,co["cy"]*H,"o",color="#ff9900",markersize=5)
                ax_img.plot(co["lead_x"]*W,co["lead_y"]*H,"x",color="#aa44ff",markersize=8,mew=2)

    # Launch direction arrow (Part D)
    if track_results:
        res = track_results[current_frame]
        if res.get("ball_launched") and res.get("launch_dir"):
            ldx, ldy = res["launch_dir"]
            _lr = locked_rect
            ix, iy = (_lr[0]+_lr[2]/2)*W, (_lr[1]+_lr[3]/2)*H
            arrow_len = min(W, H) * 0.20
            tip_x = ix + ldx * arrow_len; tip_y = iy + ldy * arrow_len
            ax_img.annotate("", xy=(tip_x, tip_y), xytext=(ix, iy),
                arrowprops=dict(arrowstyle="->", color="#00ffcc", lw=2.0), zorder=7)
        if res.get("ball_terminated"):
            ax_img.text(0.98, 0.02, "TERM", transform=ax_img.transAxes,
                color="#cc2222", fontsize=9, fontweight="bold", ha="right", va="bottom",
                bbox=dict(boxstyle="round,pad=0.2", facecolor="#330000", alpha=0.8))

    idx = current_frame
    phase = "IMPACT" if idx==detected_impact else ("post" if idx>detected_impact else "pre")
    launch_info = ""
    if track_results:
        res = track_results[current_frame]
        if res.get("ball_launched"):
            lf = res.get("launch_frame")
            launch_info = f"  launched@{lf}"
        if res.get("ball_terminated"):
            launch_info += "  TERMINATED"
    ax_img.set_title(f"Frame {idx}  [{phase}]  impact={detected_impact}  "
                     f"fallback={fallback_impact_disp}  ({det_reason_disp}){launch_info}",
                     color="white",fontsize=9,pad=4)

def draw_ball_info():
    ax_info.cla(); ax_info.set_facecolor("#111"); ax_info.set_xticks([]); ax_info.set_yticks([])
    if not track_results: return
    res = track_results[current_frame]; c = res["chosen"]
    if c:
        cD = f"{c['dia']:.4f}"; rD = f"{res['mask_dia']:.4f}" if res["mask_dia"] else "—"
        fD = f"{res['final_dia']:.4f}" if res["final_dia"] else "—"
        txt = (f"x={c['cx']:.4f}  y={c['cy']:.4f}  "
               f"candD={cD}  maskD={rD}  finalD={fD}  "
               f"maskPx={res.get('mask_count',0)}  reason={res['mask_reason']}")
        ax_info.text(0.01,0.68,txt,color="#44ff44",fontsize=8,va="center",
                     transform=ax_info.transAxes,family="monospace")
        if res.get("edge_rejected"):
            eb = res.get("edge_bounds", {})
            edge_txt = (f"⚠ EDGE REJECTED  reason={res.get('edge_reject_reason','')}  "
                        f"L={eb.get('left',0):.3f} R={eb.get('right',0):.3f} "
                        f"T={eb.get('top',0):.3f} B={eb.get('bottom',0):.3f}")
            ax_info.text(0.01, 0.85, edge_txt, color="#ff4444", fontsize=7.5, va="center",
                         transform=ax_info.transAxes, family="monospace")
        if c.get("total_score") is not None:
            jd = res.get("jump_dist"); exp_d = res.get("expected_diameter")
            score_txt = (
                f"score={c['total_score']:.2f}  "
                f"br={c.get('bright_score',0):.2f}  sz={c.get('size_score',0):.2f}  "
                f"dist={c.get('dist_score',0):.2f}  mot={c.get('motion_score',0):.2f}  "
                f"dir={c.get('dir_score',0):.2f}  shp={c.get('shape_score',0):.2f}  "
                f"dia={c.get('dia_score',0):.2f}  pen={c.get('penalty',0):.2f}"
            )
            if jd is not None: score_txt += f"  jump={jd:.4f}"
            if exp_d is not None: score_txt += f"  expD={exp_d:.4f}"
            ax_info.text(0.01,0.50,score_txt,color="#aaaaff",fontsize=7,va="center",
                         transform=ax_info.transAxes,family="monospace")
    else:
        top_cands = sorted([c for c in res["candidates"]], key=lambda x: x.get("total_score",0), reverse=True)
        reason = top_cands[0]["reason"] if top_cands else "no_blobs"
        miss_label = "TERMINATED" if res.get("ball_terminated") else "MISS"
        miss_color = "#cc3333" if res.get("ball_terminated") else "#ff6644"
        ax_info.text(0.01,0.68,f"{miss_label}  reason: {reason}  blobs: {len(res['candidates'])}",
                     color=miss_color,fontsize=8,va="center",
                     transform=ax_info.transAxes,family="monospace")
    # Launch direction / termination state (Part D)
    if res.get("ball_launched") and res.get("launch_dir"):
        ld = res["launch_dir"]
        prog = (res["chosen"] or {}).get("progress")
        prog_txt = f"  prog={prog:.4f}" if prog is not None else ""
        maxp_txt = f"  maxP={res.get('max_progress',0):.4f}"
        lf = res.get("launch_frame")
        ax_info.text(0.01,0.34,
            f"launched@{lf} dir=({ld[0]:.3f},{ld[1]:.3f}){prog_txt}{maxp_txt}",
            color="#00ffcc",fontsize=7,va="center",transform=ax_info.transAxes,family="monospace")
    if res.get("ball_terminated"):
        ax_info.text(0.01,0.20,"⛔ BALL TRACK TERMINATED",
                     color="#cc3333",fontsize=8,va="center",
                     transform=ax_info.transAxes,family="monospace")
    tracked = sum(1 for r in track_results if r["chosen"])
    fmt = lambda v,s="",d=1: "—" if v is None else f"{v:.{d}f}{s}"
    met_txt = ""
    if metrics_data:
        b=metrics_data["ball"]; cl=metrics_data["club"]; dist=metrics_data["distance"]
        rf = dist.get("rollout_fraction")
        rf_txt = f"{rf*100:.0f}%" if rf is not None else "—"
        met_txt = (f"  ball={fmt(b['ball_speed'],' mph')} hla={format_lr(b['hla'])} "
                   f"vla={fmt(b['vla'],'°')} club={fmt(cl['club_speed'],' mph')} "
                   f"smash={fmt(metrics_data['smash'],'',2)} "
                   f"carry={fmt(dist['carry'],' yd',0)} rollout={rf_txt} total={fmt(dist['total'],' yd',0)}")
    ax_info.text(0.01,0.15,f"Tracked {tracked}/{N}{met_txt}",
                 color="white",fontsize=8,va="center",transform=ax_info.transAxes,family="monospace")

def draw_metrics_sm():
    ax_metsm.cla(); ax_metsm.set_facecolor("#111"); ax_metsm.set_xticks([]); ax_metsm.set_yticks([])
    for sp in ax_metsm.spines.values(): sp.set_color("#333")
    ax_metsm.set_title("Metrics", color="white", fontsize=9, pad=4)
    if not metrics_data:
        ax_metsm.text(0.04,0.82,"Press Run",color="#777",fontsize=9,transform=ax_metsm.transAxes); return
    b=metrics_data["ball"]; cl=metrics_data["club"]; dist=metrics_data["distance"]
    spin=metrics_data.get("spin",{}); cp=metrics_data.get("club_path",{})
    fmt = lambda v,s="",d=1: "—" if v is None else f"{v:.{d}f}{s}"
    rf = dist.get("rollout_fraction")
    rollout_sm = (f"{rf*100:.0f}%  {fmt(dist.get('rollout_yards'),' yd',0)}" if rf is not None
                  else "—")
    rows_ = [("Ball Speed",  fmt(b["ball_speed"]," mph")),
             ("HLA (img-ref)",format_lr(b["hla"])),
             ("VLA",         fmt(b["vla"],"°") + (f" (raw {b.get('vla_raw',b['vla']):.1f}° 3D={b.get('vla_3d',b['vla']):.1f}° diam={b.get('vla_diam_est',0) or 0:.1f}°)" if b.get("vla_diam_est") is not None else
                              (f" (raw {b.get('vla_raw',b['vla']):.1f}°)" if b.get("vla_raw") is not None and b.get("vla_raw",0) < 0 else ""))),
             ("VLA Model",   b.get("vla_model", "legacy")),
             ("Club Speed",  fmt(cl["club_speed"]," mph")),
             ("Smash",       fmt(metrics_data["smash"],"",2)),
             ("Est. Carry",  fmt(dist["carry"]," yd",0)),
             ("Rollout",     rollout_sm),
             ("Est. Total",  fmt(dist["total"]," yd",0)),
             ("Backspin(E)", fmt(spin.get("backspin")," rpm",0)),
             ("ClubPath(E)", cp.get("display","—")),
             ("Ball/Club Pts",f"{b['points']}/{cl['points']}")]
    y = 0.93
    for label,value in rows_:
        ax_metsm.text(0.04,y,label,color="#aaa",fontsize=7.5,transform=ax_metsm.transAxes)
        ax_metsm.text(0.56,y,value,color="white",fontsize=7.5,transform=ax_metsm.transAxes,family="monospace")
        y -= 0.083
    if metrics_data["warnings"]:
        ax_metsm.text(0.04,0.03,metrics_data["warnings"][0],color="#ffcc44",fontsize=6,
                      transform=ax_metsm.transAxes)

# ── Club page draw ────────────────────────────────────────────────────────────
def draw_club_image():
    ax_cimg.cla(); ax_cimg.set_xticks([]); ax_cimg.set_yticks([])
    wf = club_window()
    if not wf: ax_cimg.set_title("Run tracker first",color="white"); return
    safe_idx = min(int(club_frame_idx), len(wf)-1)
    frame_i = wf[safe_idx]
    norm = get_norm(display_mode)
    ax_cimg.imshow(norm[frame_i], origin="upper", aspect="equal")

    # Club path — orange solid through clubhead centers, up to current frame
    if club_results:
        path_pts = [(o["cx"]*W, o["cy"]*H)
                    for o in club_results
                    if o.get("found") and o.get("cx") is not None and o.get("idx") <= frame_i]
        if len(path_pts) >= 2:
            xs_,ys_ = zip(*path_pts)
            ax_cimg.plot(xs_,ys_,color="#ff9900",lw=2,ls="-",alpha=0.9,label="Club center path")
        # Dots at each detected center; emphasize current frame
        for o in club_results:
            if not o.get("found") or o.get("cx") is None: continue
            is_cur = (o.get("idx") == frame_i)
            ms = 70 if is_cur else 25
            ax_cimg.scatter([o["cx"]*W],[o["cy"]*H],c="#ff9900",s=ms,zorder=6,
                            alpha=1.0 if is_cur else 0.6)

        co = next((o for o in club_results if o.get("idx")==frame_i), None)
        if co:
            if co.get("roi"):
                rx_,ry_,rw_,rh_ = co["roi"]
                ax_cimg.add_patch(patches.Rectangle((rx_*W,ry_*H),rw_*W,rh_*H,
                    lw=1.5,edgecolor="#ff9900",facecolor="none",linestyle="--"))
            if co.get("ball_center") and co.get("exclusion_dia"):
                bxc,byc = co["ball_center"]
                ax_cimg.add_patch(patches.Circle((bxc*W,byc*H),co["exclusion_dia"]*W/2,
                    lw=1,edgecolor="#ff9900",facecolor="none",alpha=0.35))
            if co.get("found"):
                if co.get("bbox"):
                    bbx,bby,bbw,bbh = co["bbox"]
                    ax_cimg.add_patch(patches.Rectangle((bbx*W,bby*H),bbw*W,bbh*H,
                        lw=2,edgecolor="#ff9900",facecolor="none"))
                ax_cimg.plot(co["cx"]*W,co["cy"]*H,"o",color="#ff9900",markersize=6)
                ax_cimg.plot(co["lead_x"]*W,co["lead_y"]*H,"x",color="#aa44ff",markersize=10,mew=2.5)

    # 0° reference line from ball center at impact
    if metrics_data:
        ball_origin = None
        for o in (club_results or []):
            if o.get("idx") == detected_impact and o.get("ball_center"):
                bc = o["ball_center"]
                ball_origin = (bc[0]*W, bc[1]*H)
                break
        if ball_origin is None and metrics_data.get("ball3d"):
            imp_obs = min(metrics_data["ball3d"],
                         key=lambda o: abs(o["idx"]-detected_impact), default=None)
            if imp_obs:
                ball_origin = (imp_obs["cx"]*W, imp_obs["cy"]*H)
        if ball_origin:
            x0r,y0r = ball_origin
            zero_rad = math.radians(params["zero_deg"])
            ll = min(W,H)*0.22
            x1r = x0r + ll*math.cos(zero_rad)
            y1r = y0r - ll*math.sin(zero_rad)
            ax_cimg.plot([x0r,x1r],[y0r,y1r],color="white",lw=1.5,ls="--",alpha=0.85,zorder=3)
            ax_cimg.text(x1r+6,y1r,"0° ref",color="white",fontsize=7,alpha=0.75,zorder=3)

    # Club page legend
    ax_cimg.text(0.99,0.99,
                 "— orange = club center path\n"
                 "--- orange = search ROI\n"
                 "○ orange = ball exclusion zone\n"
                 "--- white = 0° HLA reference",
                 color="white",fontsize=6.5,transform=ax_cimg.transAxes,
                 va="top",ha="right",alpha=0.85,family="monospace",
                 bbox=dict(facecolor="#111",alpha=0.72,boxstyle="round,pad=0.3"))

    rel = frame_i - detected_impact
    phase = "IMPACT" if rel==0 else (f"pre {rel}" if rel<0 else f"post +{rel}")
    ax_cimg.set_title(f"Frame {frame_i}  [{phase}]  mode={club_mode_val}",
                      color="white",fontsize=10,pad=4)

def draw_club_strip():
    ax_cstrip.cla(); ax_cstrip.set_facecolor("#111"); ax_cstrip.set_xticks([]); ax_cstrip.set_yticks([])
    wf = club_window()
    if not wf: return
    safe_idx = min(int(club_frame_idx), len(wf)-1)
    for i, fi in enumerate(wf):
        is_imp = fi == detected_impact; is_cur = i == safe_idx
        det = club_results and any(o.get("idx")==fi and o.get("found") for o in club_results)
        color = "#ffdd00" if is_imp else ("#ff9900" if det else ("#cc4444" if club_results else "#444"))
        ax_cstrip.add_patch(patches.Rectangle((i/len(wf),0.05),1/len(wf)-0.01,0.90,
            linewidth=2.5 if is_cur else 0, edgecolor="white", facecolor=color))
        ax_cstrip.text(i/len(wf)+0.5/len(wf), 0.5, str(fi), ha="center", va="center",
                       fontsize=7, color="black" if (is_imp or det) else "white")
    ax_cstrip.set_xlim(0,1); ax_cstrip.set_ylim(0,1)

def draw_club_info():
    ax_cinfo.cla(); ax_cinfo.set_facecolor("#111"); ax_cinfo.set_xticks([]); ax_cinfo.set_yticks([])
    wf = club_window()
    if not wf: return
    safe_idx = min(int(club_frame_idx), len(wf)-1)
    frame_i = wf[safe_idx]
    co = next((o for o in club_results if o.get("idx")==frame_i), None) if club_results else None
    if co and co.get("found"):
        bbox_txt = ""
        if co.get("bbox"):
            bbx,bby,bbw,bbh = co["bbox"]
            bbox_txt = f"  bbox=({bbx:.3f},{bby:.3f},{bbw:.3f},{bbh:.3f})"
        txt = (f"DETECTED  lead=({co['lead_x']:.4f},{co['lead_y']:.4f})"
               f"  conf={co['conf']:.2f}  mode={co.get('reason','')} {bbox_txt}")
        ax_cinfo.text(0.01,0.65,txt,color="#ff9900",fontsize=9,va="center",
                      transform=ax_cinfo.transAxes,family="monospace")
    elif co:
        ax_cinfo.text(0.01,0.65,f"MISS  {co.get('reason','')}",color="#ff6644",fontsize=9,
                      va="center",transform=ax_cinfo.transAxes,family="monospace")
    else:
        ax_cinfo.text(0.01,0.65,"Run tracker first",color="#777",fontsize=9,
                      va="center",transform=ax_cinfo.transAxes)
    if metrics_data:
        cl=metrics_data["club"]
        fmt = lambda v,s="",d=1: "—" if v is None else f"{v:.{d}f}{s}"
        ax_cinfo.text(0.01,0.20,
            f"Club speed={fmt(cl['club_speed'],' mph')}  pts={cl['points']}  "
            f"quality={cl['quality']:.2f}  method={cl['method']}",
            color="white",fontsize=8,va="center",transform=ax_cinfo.transAxes,family="monospace")

# ── Metrics page draw ─────────────────────────────────────────────────────────
def draw_metrics_page():
    for ax in [ax_ml, ax_mr]:
        ax.cla(); ax.set_facecolor("#0d0d1a"); ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values(): sp.set_color("#333")

    # Left: results
    ax_ml.set_title("METRICS RESULTS", color="white", fontsize=11, pad=8)
    if not metrics_data:
        ax_ml.text(0.05,0.85,"Press Run to calculate metrics.",color="#777",
                   fontsize=12,transform=ax_ml.transAxes); return
    b=metrics_data["ball"]; cl=metrics_data["club"]; dist=metrics_data["distance"]
    spin=metrics_data.get("spin",{}); cp=metrics_data.get("club_path",{})
    fa=metrics_data.get("face_angle",{})
    fmt = lambda v,s="",d=1: "—" if v is None else f"{v:.{d}f}{s}"
    fx_,fy_ = focal_lengths(params)

    def result_row(label, value, formula, y):
        ax_ml.text(0.04,y,label,color="#aaaaaa",fontsize=9,weight="bold",transform=ax_ml.transAxes)
        ax_ml.text(0.46,y,value,color="#44ff88",fontsize=10,transform=ax_ml.transAxes,family="monospace")
        if formula:
            ax_ml.text(0.04,y-0.032,formula,color="#4499cc",fontsize=7.5,
                       transform=ax_ml.transAxes,family="monospace",alpha=0.85)

    rf = dist.get("rollout_fraction")
    rollout_txt = (f"{rf*100:.0f}%  ({fmt(dist.get('rollout_yards'), ' yd', 0)})"
                   if rf is not None else "—")
    fwd = b.get("hla_forward"); lat = b.get("hla_lateral")
    fwd_lat_txt = (f"fwd={fwd:.3f}  lat={lat:.3f}" if fwd is not None and lat is not None else "—")
    ccf = dist.get("carry_correction_factor", 0.75)
    ideal_carry_txt = (f"{dist['ideal_carry']:.0f} yd" if dist.get("ideal_carry") is not None else "—")
    rows_ = [
        ("Ball Speed",       fmt(b["ball_speed"]," mph"),   "= |v_ball| × 2.23694"),
        ("HLA (img-ref)",    format_lr(b["hla"]),           fwd_lat_txt),
        ("HLA 3D raw",       fmt(b.get("hla_3d_raw"),"°"), "= atan2(vx,vz)  [debug]"),
        ("VLA",              fmt(b["vla"],"°"),              "= atan2(vy, √(vx²+vz²))"),
        ("Club Speed",       fmt(cl["club_speed"]," mph"),  "= |v_club| × 2.23694"),
        ("Smash Factor",     fmt(metrics_data["smash"],"",2), "= ball_speed / club_speed"),
        ("Ideal Carry",      ideal_carry_txt,               "= v²·sin(2θ)/g (no drag)"),
        ("Est. Carry",       fmt(dist["carry"]," yd",0),    f"= idealCarry × cf={ccf:.2f}"),
        ("Rollout",          rollout_txt,                   f"VLA bucket: {dist.get('vla_bucket','?')}"),
        ("Est. Total",       fmt(dist["total"]," yd",0),    "= carry + rollout yards"),
        ("Backspin (Est)",   fmt(spin.get("backspin")," rpm",0), "= (800+90s+120v)×mult  ESTIMATED"),
        ("Sidespin (Est)",   spin.get("sidespin_display","—"), f"method: {spin.get('method','')}"),
        ("Spin Axis (Est)",  spin.get("spin_axis_display","—"), "= atan2(sidespin,backspin)  ESTIMATED"),
        ("Club Path (Est)",  cp.get("display","—"),         f"img-space 2D fit  conf={cp.get('confidence',0):.2f}"),
        ("Face Angle (Est)", fa.get("display","—"),         f"bbox heuristic  {fa.get('confidence','')}"),
        ("Face-to-Path (E)", fa.get("ftp_display","—"),     "= face − club path"),
        ("Ball pts",         str(b["points"]),               f"method: {b['method']}"),
        ("Club pts",         str(cl["points"]),              f"method: {cl['method']}"),
    ]
    y = 0.96
    for label, value, formula in rows_:
        result_row(label, value, formula, y)
        y -= 0.062

    # Calibration
    ax_ml.plot([0.0, 1.0], [y+0.01, y+0.01], color="#333", lw=0.8,
               transform=ax_ml.transAxes, clip_on=False)
    y -= 0.02
    ax_ml.text(0.04,y,"CALIBRATION",color="#aaaaaa",fontsize=9,weight="bold",transform=ax_ml.transAxes)
    y -= 0.05
    cal_rows = [
        (f"Image: {W}×{H} px", f"  H-FOV: {params['fov_x']:.1f}°  V-FOV: {params['fov_y']:.1f}°"),
        (f"fx={fx_:.1f} px  fy={fy_:.1f} px", f"  ball Ø={params['ball_diam_m']*1000:.1f} mm"),
    ]
    for a,b_ in cal_rows:
        ax_ml.text(0.04,y,a+b_,color="#6699aa",fontsize=8,transform=ax_ml.transAxes,family="monospace")
        y -= 0.04

    # Warnings
    if metrics_data["warnings"]:
        y -= 0.01
        ax_ml.text(0.04,y,"WARNINGS",color="#ffcc44",fontsize=9,weight="bold",transform=ax_ml.transAxes)
        y -= 0.04
        for w in metrics_data["warnings"][:5]:
            ax_ml.text(0.04,y,f"• {w}",color="#ffcc44",fontsize=7,transform=ax_ml.transAxes,
                       wrap=True,alpha=0.85)
            y -= 0.038

    # Right: formulas
    ax_mr.set_title("HOW IT WORKS", color="white", fontsize=11, pad=8)
    def formula_block(title, body, y):
        ax_mr.text(0.04,y,title,color="white",fontsize=9,weight="bold",transform=ax_mr.transAxes)
        y -= 0.03
        ax_mr.text(0.04,y,body,color="#4499cc",fontsize=7.5,transform=ax_mr.transAxes,
                   family="monospace",va="top",linespacing=1.5,
                   bbox=dict(facecolor="#1a1a2e",alpha=0.5,boxstyle="round,pad=0.3"))
        lines = body.count("\n")+1
        return y - 0.042*lines - 0.025

    y = 0.92
    y = formula_block("3D Position",
        "Z = ballDiam × focalLen / diamPx\n"
        "X = (px − W/2) × Z / fx\n"
        "Y = −(py − H/2) × Z / fy", y)
    y = formula_block("Ball Velocity",
        "Linear regression over ≥3\n"
        "post-impact 3D pts vs time.\n"
        "2-point Δ if only 2 pts.", y)
    y = formula_block("HLA (image-space)",
        "ref = (cos θ, −sin θ)  [y-down]\n"
        "perp = (sin θ, cos θ)\n"
        "fwd = dx·refX + dy·refY\n"
        "lat = dx·perpX + dy·perpY\n"
        "HLA = atan2(lat, fwd)\n"
        "θ = '0° Ref Angle' slider", y)
    y = formula_block("VLA",
        "VLA = atan2(vy, √(vx²+vz²))\n"
        "(3D fit, +ve = upward)", y)
    y = formula_block("Club Speed",
        "Club depth = ball depth\n"
        "near impact. Same fit method.", y)
    y = formula_block("Distance",
        "idealCarry = v²·sin(2θ)/g (ballistic, m)\n"
        "carry = idealCarry × corrFactor × 1.09361 yd\n"
        "corrFactor default 0.75 (tune with slider)\n"
        "Rollout VLA buckets:\n"
        "  <1°:85%  1-3°:65%  3-6°:45%  6-10°:30%\n"
        "  10-15°:20%  15-22°:12%  22-30°:7%  ≥30°:3%\n"
        "speedAdj: <40×0.45  40-80×0.75  ≥130×1.1", y)
    y = formula_block("Est. Spin (Model-Based)",
        "backspin=(800+90×spd+120×vla)×vlaMultiplier\n"
        "  <5°:×0.60  5-10°:×0.80  10-20°:×1.00\n"
        "  20-30°:×1.20  ≥30°:×1.35  clamp 300-9000\n"
        "sidespin=(HLA-path)×200×(spd/100)\n"
        "spinAxis=atan2(sidespin,backspin)\n"
        "ESTIMATED — not measured", y)
    y = formula_block("Club Path & Face (Estimated)",
        "clubPath: centroid 2D regression → projected\n"
        "  onto 0° ref → atan2  (image-space)\n"
        "faceAngle: bbox longest-axis heuristic\n"
        "face-to-path = face − clubPath\n"
        "ESTIMATED — low confidence", y)
    y = formula_block("Club Modes",
        "frameDiff: |curr−prev| ≥ thr\n"
        "hybrid: dark|frameDiff|edge\n"
        "darkBlob:  brightness ≤ thr\n"
        "edgeBlob:  ∇gray ≥ thr", y)

# ── Clubface page analysis + draw ─────────────────────────────────────────────
def _run_face_analysis():
    """Compute face detection result from current metrics and return a data dict."""
    if not metrics_data:
        return None
    # Always anchor to the tracker's detected_impact — never the pre-run default of 20.
    # Frame Offset slider shifts relative to that; _face_args.face_frame overrides entirely.
    if _face_args.face_frame is not None:
        frame_i = _face_args.face_frame
    else:
        frame_i = detected_impact + int(round(_face_args.face_frame_offset))
    frame_i = max(0, min(N - 1, frame_i))
    zero_deg = params.get("zero_deg", 0.0)

    ball_cx = ball_cy = ball_dia = None
    if track_results:
        res = track_results[frame_i]
        if res.get("chosen"):
            c = res["chosen"]
            mc = res.get("mask_center") or (c["cx"], c["cy"])
            ball_cx, ball_cy = float(mc[0]), float(mc[1])
            ball_dia = float(res.get("final_dia") or c["dia"])
        if ball_cx is None:
            det = [r for r in track_results if r.get("chosen")]
            if det:
                nr = min(det, key=lambda r: abs(r["idx"] - frame_i))
                c = nr["chosen"]
                mc = nr.get("mask_center") or (c["cx"], c["cy"])
                ball_cx, ball_cy = float(mc[0]), float(mc[1])
                ball_dia = float(nr.get("final_dia") or c["dia"])
    if ball_cx is None and metrics_data.get("ball3d"):
        ob = min(metrics_data["ball3d"], key=lambda o: abs(o["idx"] - frame_i))
        ball_cx, ball_cy = float(ob["cx"]), float(ob["cy"])
        ball_dia = float(ob["dia"])
    if ball_cx is None:
        return dict(frame_i=frame_i, zero_deg=zero_deg, error="no_ball_position",
                    ball_cx=None, ball_cy=None, ball_dia=None,
                    roi=None, face_result=None, ainfo=None,
                    gray_crop=None, excl=None, x0r=0, y0r=0, x1r=0, y1r=0)

    co_near = sorted([o for o in club_results if o.get("found") and o.get("bbox")],
                     key=lambda o: abs(o.get("idx", 9999) - frame_i))
    co_best = co_near[0] if co_near else None
    roi = _clubface_roi_norm(ball_cx, ball_cy, ball_dia, co_best, _face_args)
    x0r = max(0, int(roi["x0"] * W)); y0r = max(0, int(roi["y0"] * H))
    x1r = min(W, int(roi["x1"] * W)); y1r = min(H, int(roi["y1"] * H))
    crop_w = x1r - x0r; crop_h = y1r - y0r

    # Part F: compute face angle prior from ball HLA and club path
    face_prior_deg = None; face_prior_rad = None
    max_prior_dev_rad = None
    if params.get("use_face_prior", 1.0) > 0.5 and metrics_data:
        ball_hla = metrics_data["ball"].get("hla")
        club_path_angle = metrics_data.get("club_path", {}).get("angle")
        w_hla  = float(params.get("face_prior_hla_weight",  0.75))
        w_club = float(params.get("face_prior_club_weight", 0.25))
        if ball_hla is not None and club_path_angle is not None:
            face_prior_deg = w_hla * ball_hla + w_club * club_path_angle
        elif ball_hla is not None:
            face_prior_deg = ball_hla
        elif club_path_angle is not None:
            face_prior_deg = club_path_angle
        if face_prior_deg is not None:
            # Convert to image-space angle (same convention as _face_angle_info)
            theta_zero = math.radians(zero_deg)
            face_prior_rad = theta_zero + math.radians(face_prior_deg)
            max_dev = float(params.get("max_face_prior_dev", 35.0))
            max_prior_dev_rad = math.radians(max_dev)
    fp_sw = float(params.get("face_prior_score_weight", 3.0))

    face_result = None; excl = None; gray_crop = None
    if crop_w >= 10 and crop_h >= 10:
        crop = raw_frames[frame_i][y0r:y1r, x0r:x1r].astype(np.float32)
        gray_crop = np.mean(crop, axis=2)
        excl = _excl_mask_crop(crop_h, crop_w, ball_cx, ball_cy, ball_dia, x0r, y0r, _face_args)
        if _face_args.face_method in ("auto", "hough"):
            face_result = _detect_face_hough(gray_crop, excl, x0r, y0r, _face_args,
                                             face_prior_rad=face_prior_rad,
                                             face_prior_score_weight=fp_sw,
                                             max_prior_dev_rad=max_prior_dev_rad)
        if face_result is None and _face_args.face_method in ("auto", "pca"):
            face_result = _detect_face_pca(gray_crop, excl, x0r, y0r, _face_args,
                                           face_prior_rad=face_prior_rad)

    ainfo = _face_angle_info(face_result, zero_deg, _face_args) if face_result else None
    return dict(frame_i=frame_i, zero_deg=zero_deg, error=None,
                ball_cx=ball_cx, ball_cy=ball_cy, ball_dia=ball_dia,
                co_best=co_best, roi=roi,
                x0r=x0r, y0r=y0r, x1r=x1r, y1r=y1r,
                crop_w=crop_w, crop_h=crop_h,
                face_result=face_result, ainfo=ainfo,
                gray_crop=gray_crop, excl=excl,
                face_prior_deg=face_prior_deg)

def draw_clubface_page():
    # Only clear image/info axes — never cla slider or radio axes (wipes widgets)
    for ax in [ax_fdimg, ax_fdzoom, ax_fdinfo]:
        ax.cla(); ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values(): sp.set_color("#333")

    fd = face_debug_data
    if fd is None:
        ax_fdimg.text(0.5, 0.5, "Press Run to analyse clubface",
                      color="#777", fontsize=13, ha="center", va="center",
                      transform=ax_fdimg.transAxes)
        ax_fdimg.set_title("Clubface Debug", color="white", fontsize=11, pad=6)
        ax_fdzoom.text(0.5, 0.5, "—", color="#555", fontsize=10,
                       ha="center", va="center", transform=ax_fdzoom.transAxes)
        ax_fdinfo.text(0.02, 0.5, "No data. Run tracker first.",
                       color="#555", fontsize=9, va="center", transform=ax_fdinfo.transAxes)
        return

    if fd.get("error"):
        ax_fdimg.imshow(raw_frames[fd["frame_i"]], origin="upper", aspect="equal")
        ax_fdimg.text(0.5, 0.5, f"Error: {fd['error']}",
                      color="#ff6644", fontsize=13, ha="center", va="center",
                      transform=ax_fdimg.transAxes, weight="bold",
                      bbox=dict(facecolor="#111", alpha=0.75, boxstyle="round,pad=0.4"))
        ax_fdimg.set_title(f"Clubface Debug  Frame {fd['frame_i']}  FAILED",
                           color="#ff6644", fontsize=11, pad=6)
        return

    frame_i = fd["frame_i"]; zero_deg = fd["zero_deg"]
    ball_cx = fd["ball_cx"]; ball_cy = fd["ball_cy"]; ball_dia = fd["ball_dia"]
    roi = fd["roi"]; face_result = fd["face_result"]; ainfo = fd["ainfo"]
    x0r = fd["x0r"]; y0r = fd["y0r"]; x1r = fd["x1r"]; y1r = fd["y1r"]
    crop_w = fd["crop_w"]; crop_h = fd["crop_h"]

    # Full frame
    ax_fdimg.imshow(raw_frames[frame_i], origin="upper", aspect="equal")
    bx = ball_cx * W; by = ball_cy * H; br = ball_dia * W / 2
    ax_fdimg.add_patch(plt.Circle((bx, by), br, color="#44ff44", fill=False, lw=2.0, zorder=5))
    ax_fdimg.plot(bx, by, "g+", markersize=10, mew=2, zorder=6)

    excl_r = ball_dia * W * _face_args.face_ball_exclusion_scale / 2
    ax_fdimg.add_patch(plt.Circle((bx, by), excl_r, color="#ff9900",
                                   fill=False, lw=1.5, ls="--", alpha=0.7, zorder=4))

    roi_xpx = roi["x0"] * W; roi_ypx = roi["y0"] * H
    roi_wpx = (roi["x1"] - roi["x0"]) * W; roi_hpx = (roi["y1"] - roi["y0"]) * H
    ax_fdimg.add_patch(patches.Rectangle((roi_xpx, roi_ypx), roi_wpx, roi_hpx,
                                          lw=1.5, edgecolor="cyan", facecolor="none",
                                          ls="--", alpha=0.8, zorder=4))

    co_best = fd.get("co_best")
    if co_best and co_best.get("bbox"):
        bbx, bby, bbw, bbh = co_best["bbox"]
        ax_fdimg.add_patch(patches.Rectangle((bbx * W, bby * H), bbw * W, bbh * H,
                                              lw=2, edgecolor="#ff9900", facecolor="none", zorder=4))

    zero_rad = math.radians(zero_deg)
    ref_len = min(W, H) * 0.22
    ax_fdimg.plot([bx, bx + ref_len * math.cos(zero_rad)],
                  [by, by - ref_len * math.sin(zero_rad)],
                  color="white", lw=2, ls="--", alpha=0.9, zorder=5)
    ax_fdimg.text(bx + ref_len * math.cos(zero_rad) + 4,
                  by - ref_len * math.sin(zero_rad),
                  f"0 deg ({zero_deg:+.1f})", color="white", fontsize=7, va="center")

    if face_result and ainfo:
        cx_f = face_result["cx"] * W; cy_f = face_result["cy"] * H
        arad = ainfo["angle_rad_used"]
        adx = math.cos(arad); ady = math.sin(arad)
        half = min(W, H) * 0.15
        if "endpoints" in face_result:
            x1e = face_result["endpoints"][0] * W; y1e = face_result["endpoints"][1] * H
            x2e = face_result["endpoints"][2] * W; y2e = face_result["endpoints"][3] * H
            ax_fdimg.plot([x1e, x2e], [y1e, y2e], color="magenta", lw=3, alpha=0.95, zorder=8)
        else:
            ax_fdimg.plot([cx_f - adx * half, cx_f + adx * half],
                          [cy_f - ady * half, cy_f + ady * half],
                          color="magenta", lw=3, alpha=0.95, zorder=8)
        ax_fdimg.plot(cx_f, cy_f, "m+", markersize=12, mew=2.5, zorder=9)
        ray_len = min(W, H) * 0.20
        ax_fdimg.annotate("", xy=(cx_f + adx * ray_len, cy_f + ady * ray_len),
                          xytext=(cx_f, cy_f),
                          arrowprops=dict(arrowstyle="->", color="#ffff00", lw=2.5), zorder=10)
        ann = (f"Face: {ainfo['display']}\n"
               f"method: {face_result['method']}\n"
               f"coherence: {face_result['coherence']:.2f}\n"
               f"edge pts: {face_result['edge_count']}")
        ax_fdimg.text(0.02, 0.97, ann, color="magenta", fontsize=8,
                      transform=ax_fdimg.transAxes, va="top", family="monospace",
                      bbox=dict(facecolor="#111", alpha=0.75, boxstyle="round,pad=0.3"))
    else:
        ax_fdimg.text(0.02, 0.97, "Face: not detected",
                      color="#ff6644", fontsize=9, transform=ax_fdimg.transAxes, va="top",
                      family="monospace",
                      bbox=dict(facecolor="#111", alpha=0.75, boxstyle="round,pad=0.3"))

    # Draw face prior line (Part F)
    face_prior_deg_ = fd.get("face_prior_deg")
    if face_prior_deg_ is not None:
        prior_rad_ = math.radians(zero_deg) + math.radians(face_prior_deg_)
        prior_len = min(W, H) * 0.18
        ax_fdimg.plot([bx, bx + prior_len * math.cos(prior_rad_)],
                      [by, by - prior_len * math.sin(prior_rad_)],
                      color="#00ffaa", lw=1.5, ls=":", alpha=0.8, zorder=6,
                      label=f"FacePrior {face_prior_deg_:.1f}°")
        ax_fdimg.text(bx + prior_len * math.cos(prior_rad_) + 4,
                      by - prior_len * math.sin(prior_rad_),
                      f"prior {face_prior_deg_:+.1f}°", color="#00ffaa",
                      fontsize=7, alpha=0.85, zorder=6)

    rel = frame_i - detected_impact
    phase = "IMPACT" if rel == 0 else (f"pre {abs(rel)}" if rel < 0 else f"post +{rel}")
    offset_str = f"  [offset {rel:+d}]" if rel != 0 else ""
    ax_fdimg.set_title(
        f"Frame {frame_i}{offset_str}  |  Tracker impact = {detected_impact}  "
        f"|  method={_face_args.face_method}  0°={zero_deg:+.1f}",
        color="white", fontsize=9, pad=5)

    ax_fdimg.text(0.99, 0.01,
                  "green=ball  orange dashed=excl\n"
                  "cyan dashed=ROI  orange box=club\n"
                  "white dashed=0 ref  magenta=face\n"
                  "yellow arrow=projection",
                  color="white", fontsize=6.5, transform=ax_fdimg.transAxes,
                  va="bottom", ha="right", family="monospace",
                  bbox=dict(facecolor="#111", alpha=0.7, boxstyle="round,pad=0.3"))

    # Zoom crop panel
    gray_crop = fd.get("gray_crop")
    if gray_crop is not None and crop_w > 0 and crop_h > 0:
        ax_fdzoom.imshow(raw_frames[frame_i][y0r:y1r, x0r:x1r],
                         origin="upper", aspect="equal", extent=[x0r, x1r, y1r, y0r])
        ax_fdzoom.add_patch(plt.Circle((bx, by), excl_r, color="#ff9900",
                                       fill=False, lw=1.5, ls="--", alpha=0.7))
        if face_result and ainfo:
            cx_f = face_result["cx"] * W; cy_f = face_result["cy"] * H
            arad = ainfo["angle_rad_used"]
            adx = math.cos(arad); ady = math.sin(arad)
            half_z = min(crop_w, crop_h) * 0.45
            ax_fdzoom.plot([cx_f - adx * half_z, cx_f + adx * half_z],
                           [cy_f - ady * half_z, cy_f + ady * half_z],
                           color="magenta", lw=2.5, alpha=0.95)
            ax_fdzoom.plot(cx_f, cy_f, "m+", markersize=10, mew=2)
        ax_fdzoom.set_xlim(x0r, x1r); ax_fdzoom.set_ylim(y1r, y0r)
        ax_fdzoom.set_title("ROI crop", color="white", fontsize=8, pad=3)
    else:
        ax_fdzoom.text(0.5, 0.5, "ROI\ntoo small", color="#555",
                       fontsize=9, ha="center", va="center", transform=ax_fdzoom.transAxes)
        ax_fdzoom.set_title("ROI crop", color="white", fontsize=8, pad=3)

    # Info bar
    fmt = lambda v, s="", d=1: "—" if v is None else f"{v:.{d}f}{s}"
    cp = metrics_data.get("club_path", {}) if metrics_data else {}
    face_deg_txt = (f"Face={ainfo['display']}" if ainfo
                    else "Face=not detected")
    ax_fdinfo.text(0.01, 0.72,
                   f"Frame {frame_i}  [{phase}]  "
                   f"0 deg={zero_deg:+.1f}  "
                   f"method={_face_args.face_method}  "
                   f"normal_mode={_face_args.face_angle_normal_mode}",
                   color="white", fontsize=8.5, va="center",
                   transform=ax_fdinfo.transAxes, family="monospace")
    ax_fdinfo.text(0.01, 0.42, face_deg_txt, color="magenta", fontsize=9, va="center",
                   transform=ax_fdinfo.transAxes, family="monospace")
    ax_fdinfo.text(0.01, 0.18,
                   f"ClubPath(ref)={cp.get('display','—')}  "
                   f"ROI scale=({_face_args.face_roi_scale_x:.1f}x"
                   f"{_face_args.face_roi_scale_y:.1f})  "
                   f"excl_scale={_face_args.face_ball_exclusion_scale:.1f}  "
                   f"edge_thr={_face_args.face_edge_threshold:.0f}  "
                   f"min_pts={_face_args.face_min_edge_pixels}",
                   color="#aaaaaa", fontsize=7.5, va="center",
                   transform=ax_fdinfo.transAxes, family="monospace")

# ── Face-page callbacks ───────────────────────────────────────────────────────
# _face_refresh ONLY touches face detection state. It never calls the ball/club
# tracker, never writes to params, and never modifies metrics_data.
def _face_refresh(_=None):
    global face_debug_data
    # Hard guard: bail immediately if not on face page or no tracker data yet.
    # This ensures sliders on other pages can never accidentally trigger this.
    if current_page != "face" or not metrics_data:
        return
    for key, sl in face_sliders.items():
        val = sl.val
        if key in ("face_frame_offset", "face_min_edge_pixels", "face_angle_flip"):
            val = int(round(val))
        setattr(_face_args, key, val)
    # Only re-runs face edge detection on already-computed track/club results.
    face_debug_data = _run_face_analysis()
    draw_clubface_page()
    fig.canvas.draw_idle()

def _on_fd_nmode(label):
    if current_page != "face": return
    _face_args.face_angle_normal_mode = label
    _face_refresh()

def _on_fd_method(label):
    if current_page != "face": return
    _face_args.face_method = label
    _face_refresh()

# ── Master refresh ────────────────────────────────────────────────────────────
_is_refreshing = False

def refresh():
    global _is_refreshing
    if _is_refreshing:
        return
    _is_refreshing = True
    try:
        if current_page == "ball":
            draw_ball_image(); draw_ball_strip(); draw_ball_info()
            draw_mask_preview(); draw_metrics_sm()
        elif current_page == "club":
            draw_club_image(); draw_club_strip(); draw_club_info()
            draw_metrics_sm()
        elif current_page == "face":
            draw_clubface_page()
        else:
            draw_metrics_page()
        fig.canvas.draw_idle()
    finally:
        _is_refreshing = False

def set_page(page):
    global current_page
    current_page = page
    is_face = page == "face"
    for ax in BALL_AX:    ax.set_visible(page == "ball")
    for ax in CLUB_AX:    ax.set_visible(page == "club")
    for ax in MET_AX:     ax.set_visible(page == "met")
    for ax in FACE_AX:    ax.set_visible(is_face)
    for ax in SIDEBAR_AX: ax.set_visible(not is_face)
    ax_metsm.set_visible(page not in ("met", "face"))
    btn_tb.ax.set_facecolor("#553399" if page == "ball" else "#2a2a2a")
    btn_tc.ax.set_facecolor("#774400" if page == "club" else "#2a2a2a")
    btn_tm.ax.set_facecolor("#225522" if page == "met"  else "#2a2a2a")
    btn_tf.ax.set_facecolor("#1a3355" if page == "face" else "#2a2a2a")
    btn_tb.label.set_text("● Ball Tracking" if page == "ball" else "○ Ball Tracking")
    btn_tc.label.set_text("● Club Tracking" if page == "club" else "○ Club Tracking")
    btn_tm.label.set_text("● Metrics"       if page == "met"  else "○ Metrics")
    btn_tf.label.set_text("● Clubface"      if page == "face" else "○ Clubface")
    refresh()

# ── Event handlers ────────────────────────────────────────────────────────────
def on_run(_):
    global track_results, club_results, metrics_data, face_debug_data
    global detected_impact, fallback_impact_disp, det_reason_disp
    for key, sl in sliders.items():
        params[key] = sl.val
    params["club_mode"] = club_mode_val
    norm = get_norm(tracking_mode)
    print(f"Running tracker (mode={tracking_mode}, club_mode={club_mode_val})...")
    print(f"  Settings: Sc: Size W = {params.get('sc_size_w',4.0):.2f}  |  Mask Percentile = {params.get('mask_percentile',85.0):.0f}  |  Post Bright >= {params.get('post_bright',92):.0f}  |  Post MinW = {params.get('post_min_nw',0.018):.4f}")
    print(f"Experimental club tracking mode: {club_mode_val}")
    track_results, detected_impact, fallback_impact_disp, det_reason_disp = \
        run_tracker(norm, params, impact_idx, locked_rect)
    metrics_data = compute_metrics_and_club(norm, track_results, detected_impact, params)
    club_results = metrics_data["club_obs"] if metrics_data else []
    face_debug_data = _run_face_analysis()
    # Upgrade bbox heuristic face angle with PCA/Hough result when available
    if face_debug_data and face_debug_data.get("ainfo") and metrics_data:
        ainfo = face_debug_data["ainfo"]
        ang = ainfo.get("angle_deg")
        if ang is not None:
            cp_ang = metrics_data["club_path"].get("angle")
            ftp = (ang - cp_ang) if cp_ang is not None else None
            fr = face_debug_data.get("face_result") or {}
            metrics_data["face_angle"].update(
                angle=ang, display=format_lr(ang),
                ftp=ftp, ftp_display=format_lr(ftp),
                confidence=fr.get("method", "pca_edge"),
                method="pca_edge_detection"
            )
            cp_disp = metrics_data["club_path"].get("display", "—")
            print(f"ClubPath(est): {cp_disp}  Face(PCA): {format_lr(ang)}  F-to-P: {format_lr(ftp)}")
    # Suppress face if it's far from ball HLA
    if (params.get("suppress_face_if_far_from_hla", 1.0) > 0.5
            and metrics_data and face_debug_data and face_debug_data.get("ainfo")):
        ang = face_debug_data["ainfo"].get("angle_deg")
        ball_hla_val = metrics_data.get("ball", {}).get("hla")
        max_diff = float(params.get("max_face_ball_hla_difference", 30.0))
        if ang is not None and ball_hla_val is not None:
            diff = abs(ang - ball_hla_val)
            if diff > 180: diff = 360 - diff
            if diff > max_diff:
                metrics_data["face_angle"].update(
                    angle=None, display="—",
                    ftp=None, ftp_display="—",
                    confidence="suppressed",
                    method="suppressed_far_from_ball_hla",
                    suppressed_reason=f"face {ang:.1f}° differs from ballHLA {ball_hla_val:.1f}° by {diff:.1f}° > {max_diff:.1f}°"
                )
                print(f"Face suppressed: diff={diff:.1f}° > {max_diff:.1f}°")
    write_python_metrics_json(track_results, metrics_data,
                              detected_impact, fallback_impact_disp, det_reason_disp)
    if _face_args.save_face_debug:
        generate_clubface_debug(track_results, club_results, metrics_data,
                                detected_impact, _face_args, params)
    refresh()

def on_frame_slide(val):
    global current_frame
    current_frame = int(round(val)); refresh()

def on_cframe_slide(val):
    global club_frame_idx
    club_frame_idx = int(round(val)); refresh()

def on_display(label):
    global display_mode
    display_mode = label; refresh()

def on_track(label):
    global tracking_mode
    tracking_mode = label

def on_cmode(label):
    global club_mode_val
    club_mode_val = label
    params["club_mode"] = label

def on_key(event):
    global current_frame, club_frame_idx
    if current_page == "ball":
        if event.key == "right" and current_frame < N-1:
            current_frame += 1; sl_frame.set_val(current_frame); refresh()
        elif event.key == "left" and current_frame > 0:
            current_frame -= 1; sl_frame.set_val(current_frame); refresh()
    elif current_page == "club":
        wf = club_window()
        if event.key == "right" and club_frame_idx < len(wf)-1:
            club_frame_idx += 1; sl_cframe.set_val(club_frame_idx); refresh()
        elif event.key == "left" and club_frame_idx > 0:
            club_frame_idx -= 1; sl_cframe.set_val(club_frame_idx); refresh()

def on_strip_click(event):
    global current_frame, club_frame_idx
    if event.inaxes == ax_strip and event.xdata is not None:
        current_frame = max(0, min(N-1, int(event.xdata*N)))
        sl_frame.set_val(current_frame); refresh()
    elif event.inaxes == ax_cstrip and event.xdata is not None:
        wf = club_window()
        if wf:
            club_frame_idx = max(0, min(len(wf)-1, int(event.xdata*len(wf))))
            sl_cframe.set_val(club_frame_idx); refresh()

btn_run.on_clicked(on_run)
sl_frame.on_changed(on_frame_slide)
sl_cframe.on_changed(on_cframe_slide)
radio_disp.on_clicked(on_display)
radio_track.on_clicked(on_track)
radio_cmode.on_clicked(on_cmode)
btn_tb.on_clicked(lambda _: set_page("ball"))
btn_tc.on_clicked(lambda _: set_page("club"))
btn_tm.on_clicked(lambda _: set_page("met"))
btn_tf.on_clicked(lambda _: set_page("face"))
for _sl in face_sliders.values(): _sl.on_changed(_face_refresh)
radio_fd_method.on_clicked(_on_fd_method)
radio_fd_nmode.on_clicked(_on_fd_nmode)
btn_fd_run.on_clicked(_face_refresh)   # face-only Re-analyse; never runs ball tracker
fig.canvas.mpl_connect("key_press_event", on_key)
fig.canvas.mpl_connect("button_press_event", on_strip_click)

def run_batch_folder(folder, p):
    """Run headless tracking on a single ShotExport folder. Returns summary dict."""
    global W, H, N, rel_times
    _png = sorted(glob.glob(os.path.join(folder, "frame_*.png")))
    if not _png:
        return None
    _frames = [np.array(Image.open(pp).convert("RGB")) for pp in _png]
    H_, W_ = _frames[0].shape[:2]
    _n = len(_frames)
    _meta_path = os.path.join(folder, "metadata.json")
    _meta = {}; _imp = 20; _fps = 240.0; _locked = (0.45, 0.45, 0.10, 0.10)
    if os.path.exists(_meta_path):
        _meta = json.load(open(_meta_path))
        _imp = _meta.get("impact_frame_index", _imp)
        _fps = float(_meta.get("fps_estimate", _fps) or _fps)
        if "locked_ball_rect" in _meta:
            _r = _meta["locked_ball_rect"]
            _locked = (_r["x"], _r["y"], _r["width"], _r["height"])
    _ts = [dict(frame_index=i, timestamp=i/_fps, relative_time=(i-_imp)/_fps) for i in range(_n)]
    _ts_path = os.path.join(folder, "timestamps.json")
    if os.path.exists(_ts_path):
        _tsd = json.load(open(_ts_path))
        _tsi = _tsd.get("timestamps", _tsd if isinstance(_tsd, list) else [])
        _tsb = {int(t.get("frame_index", t.get("frameIndex", ii))): t for ii, t in enumerate(_tsi)}
        for ii in range(_n):
            tt = _tsb.get(ii)
            if tt:
                _ts[ii] = dict(frame_index=ii,
                    timestamp=float(tt.get("timestamp", ii/_fps)),
                    relative_time=float(tt.get("relative_time", tt.get("relativeTime", (ii-_imp)/_fps))))
    # Update globals for tracking functions
    W = W_; H = H_; N = _n
    rel_times = np.array([t["relative_time"] for t in _ts], dtype=float)
    _norm = [normalize(f, "darkened") for f in _frames]
    _results, _det_imp, _fall, _det_reason = run_tracker(_norm, p, _imp, _locked)
    _tracked = sum(1 for r in _results if r.get("chosen"))
    _post_tracked = sum(1 for r in _results if r.get("chosen") and r["idx"] > _det_imp)
    _stats = dict(_last_tracking_stats)
    _metrics = None
    try:
        _metrics = compute_metrics_and_club(_norm, _results, _det_imp, p)
    except Exception as _e:
        print(f"  metrics error: {_e}")
    _hla = _metrics["ball"]["hla"] if _metrics else None
    _vla = _metrics["ball"]["vla"] if _metrics else None
    _spd = _metrics["ball"]["ball_speed"] if _metrics else None
    _warns = len(_metrics["warnings"]) if _metrics else -1
    return dict(
        folder=os.path.basename(folder),
        tracked=_tracked, n=_n, post_tracked=_post_tracked,
        impact=_det_imp, reason=_det_reason,
        hla=_hla, vla=_vla, speed=_spd, warnings=_warns,
        mask_rej=_stats.get("maskQualityRejectedCount", 0),
        tiny_rej=_stats.get("tinyWeakRejectedCount", 0),
        merged_rej=_stats.get("mergedClubBallRejectedCount", 0),
        early_merged_stopper=_stats.get("earlyMergedStopperCount", 0),
        rescued=_stats.get("rescuedCandidateCount", 0),
        off_path_rej=_stats.get("offPathRejectedCount", 0),
        pred_dis_fr=_stats.get("predictionDisabledFrame"),
        term_fr=_stats.get("ballTrackTerminatedFrame"),
        post_min_nw=p.get("post_min_nw", 0.018),
        mask_pct=p.get("mask_percentile", 85.0),
    )

if _face_args.batch:
    import sys as _sys
    _batch_dir = _face_args.batch
    _shot_folders = sorted(glob.glob(os.path.join(_batch_dir, "ShotExport_*")))
    if not _shot_folders:
        print(f"No ShotExport_* found in {_batch_dir}"); _sys.exit(1)
    print(f"\n{'='*120}")
    print(f"BATCH MODE: {len(_shot_folders)} shots in {_batch_dir}")
    print(f"{'='*120}")
    _batch_results = []
    for _sf in _shot_folders:
        print(f"\n--- {os.path.basename(_sf)} ---")
        _br = run_batch_folder(_sf, params)
        if _br:
            _batch_results.append(_br)
    # Print summary table
    print(f"\n{'='*140}")
    _hdr = (f"{'Shot':<40} {'Trk':>4} {'N':>4} {'Post':>4} {'Imp':>4} "
            f"{'HLA':>7} {'VLA':>6} {'Spd':>6} "
            f"{'MskRj':>5} {'TnyRj':>5} {'MrgRj':>5} {'EMrgS':>5} {'Rscue':>5} {'OPRj':>5} "
            f"{'PDisFr':>6} {'TrmFr':>6} {'PMinW':>6} {'MskPct':>6} {'Wrn':>4}")
    print(_hdr)
    print("-"*140)
    for _br in _batch_results:
        def _fmt(v, fmt=".1f"): return "—" if v is None else format(v, fmt)
        _row = (f"{_br['folder']:<40} {_br['tracked']:>4}/{_br['n']:<4} {_br['post_tracked']:>4} "
                f"{_br['impact']:>4} "
                f"{_fmt(_br['hla']):>7} {_fmt(_br['vla']):>6} {_fmt(_br['speed']):>6} "
                f"{_br['mask_rej']:>5} {_br['tiny_rej']:>5} {_br['merged_rej']:>5} "
                f"{_br['early_merged_stopper']:>5} "
                f"{_br['rescued']:>5} {_br['off_path_rej']:>5} "
                f"{str(_br['pred_dis_fr'] or '—'):>6} {str(_br['term_fr'] or '—'):>6} "
                f"{_fmt(_br['post_min_nw'],'.4f'):>6} {_fmt(_br['mask_pct'],'.0f'):>6} "
                f"{_br['warnings']:>4}")
        print(_row)
    print("="*140)
    _sys.exit(0)

norm_cache["darkened"] = [normalize(f,"darkened") for f in raw_frames]
refresh()
plt.show()
