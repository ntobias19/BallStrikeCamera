#!/usr/bin/env python3
import argparse
import json
import math
import tempfile
import zipfile
from pathlib import Path

import numpy as np
import matplotlib.image as mpimg
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Rectangle


def load_json(path):
    if not path.exists():
        return None
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def shot_root(args):
    if args.shot:
        return Path(args.shot), None
    tmp = tempfile.TemporaryDirectory()
    with zipfile.ZipFile(args.zip, "r") as zf:
        zf.extractall(tmp.name)
    root = Path(tmp.name)
    children = [p for p in root.iterdir() if p.is_dir()]
    return (children[0] if len(children) == 1 else root), tmp


def frames(root):
    return sorted(root.glob("frame_*.png"))


def frame_index(path):
    return int(path.stem.replace("frame_", ""))


def output_dir(root, args):
    out = Path(args.output) if args.output else root
    out.mkdir(parents=True, exist_ok=True)
    return out


def obs_by_frame(items):
    return {int(o.get("frameIndex", o.get("frame_index", 0))): o for o in items}


def ball_observations(metrics, tracking):
    if metrics and "ballTrackingObservations" in metrics:
        return metrics["ballTrackingObservations"]
    if tracking and "observations" in tracking:
        return [
            {
                "frameIndex": o.get("frame_index"),
                "centerX": o.get("center_x"),
                "centerY": o.get("center_y"),
                "diameter": o.get("diameter"),
                "confidence": o.get("confidence", 0),
            }
            for o in tracking["observations"]
        ]
    return []


def club_observations(metrics):
    return metrics.get("clubObservations", []) if metrics else []


def ball3d_observations(metrics):
    return metrics.get("ball3DObservations", []) if metrics else []


def norm_rect(rect, width, height):
    return rect["x"] * width, rect["y"] * height, rect["width"] * width, rect["height"] * height


def norm_point(x, y, width, height):
    return x * width, y * height


def value_text(value, suffix="", digits=1):
    if value is None:
        return "--"
    if isinstance(value, float) and not math.isfinite(value):
        return "--"
    return f"{value:.{digits}f}{suffix}"


def format_lr(degrees, pos="R", neg="L"):
    if degrees is None:
        return "--"
    label = pos if degrees >= 0 else neg
    return f"{abs(degrees):.1f} {label}"


def plot_overlay(root, out, selected_frame, metrics, tracking, show_ball_path, show_club):
    paths = frames(root)
    if not paths:
        return
    impact = metrics.get("detectedImpactFrameIndex", 20) if metrics else 20
    selected = selected_frame if selected_frame is not None else impact
    path = next((p for p in paths if frame_index(p) == selected), paths[min(selected, len(paths) - 1)])
    image = mpimg.imread(path)
    height, width = image.shape[0], image.shape[1]

    balls = obs_by_frame(ball_observations(metrics, tracking))
    clubs = obs_by_frame(club_observations(metrics))
    ball = balls.get(frame_index(path))
    club = clubs.get(frame_index(path))
    b3d = ball3d_observations(metrics)

    fig, ax = plt.subplots(figsize=(13, 7))
    ax.imshow(image)
    fi = frame_index(path)
    rel = fi - impact
    phase = "IMPACT" if rel == 0 else (f"pre {rel}" if rel < 0 else f"post +{rel}")
    ax.set_title(f"Frame {fi}  [{phase}]", color="white")
    ax.set_facecolor("black")
    ax.axis("off")

    if ball and ball.get("centerX") is not None and ball.get("centerY") is not None:
        cx, cy = norm_point(ball["centerX"], ball["centerY"], width, height)
        diameter = (ball.get("smoothedDiameter") or ball.get("maskRefinedDiameter")
                    or ball.get("diameter"))
        if diameter:
            ax.add_patch(Circle((cx, cy), diameter * width / 2,
                                fill=False, lw=2.0, color="lime", zorder=5))
        ax.scatter([cx], [cy], c="lime", s=18, zorder=6)

    if show_ball_path and b3d:
        post = [o for o in b3d if o["frameIndex"] > impact]
        if len(post) >= 2:
            pxs = [o["imageX"] * width for o in post]
            pys = [o["imageY"] * height for o in post]
            ax.plot(pxs, pys, color="cyan", lw=2, ls="--", alpha=0.85, label="ball path", zorder=4)
            ax.scatter(pxs, pys, c="cyan", s=14, zorder=5, alpha=0.7)

    if show_club and club:
        roi = club.get("searchROI")
        if isinstance(roi, dict):
            x, y, w, h = norm_rect(roi, width, height)
            ax.add_patch(Rectangle((x, y), w, h, fill=False, lw=1.5, ls="--",
                                   color="orange", alpha=0.8, zorder=4))

        ex = club.get("ballExclusionCenterX")
        ey = club.get("ballExclusionCenterY")
        ed = club.get("ballExclusionDiameter")
        if ex is not None and ey is not None and ed is not None:
            bx, by = norm_point(ex, ey, width, height)
            ax.add_patch(Circle((bx, by), ed * width / 2,
                                fill=False, lw=1.0, color="orange", alpha=0.35, zorder=3))

        bbox = club.get("clubBoundingBox")
        if isinstance(bbox, dict):
            bx, by, bw, bh = norm_rect(bbox, width, height)
            ax.add_patch(Rectangle((bx, by), bw, bh, fill=False, lw=2.0,
                                   color="orange", zorder=5))

        ccx, ccy = club.get("centerX"), club.get("centerY")
        if ccx is not None and ccy is not None:
            px, py = norm_point(ccx, ccy, width, height)
            ax.scatter([px], [py], c="orange", s=40, zorder=6, label="club center")

        lx, ly = club.get("leadingEdgeX"), club.get("leadingEdgeY")
        if lx is not None and ly is not None:
            px, py = norm_point(lx, ly, width, height)
            ax.scatter([px], [py], c="#ff9900", s=60, marker="x", zorder=7, label="leading edge")

    if show_club:
        club_pts = []
        for obs in club_observations(metrics):
            x = obs.get("leadingEdgeX", obs.get("centerX"))
            y = obs.get("leadingEdgeY", obs.get("centerY"))
            if x is not None and y is not None:
                club_pts.append(norm_point(x, y, width, height))
        if len(club_pts) >= 2:
            xs, ys = zip(*club_pts)
            ax.plot(xs, ys, color="#ff9900", lw=2.0, ls="-", alpha=0.85, label="club path (leading edge)")
            ax.scatter(xs, ys, c="#ff9900", s=14, zorder=5, alpha=0.65)

    # 0° HLA reference line
    zero_deg = metrics.get("zeroDegreeReferenceAngleDegrees", 0) if metrics else 0
    ref_origin = None
    if show_ball_path and b3d:
        post = [o for o in b3d if o["frameIndex"] > impact]
        if post:
            o0 = post[0]
            ref_origin = (o0["imageX"] * width, o0["imageY"] * height)
    if ref_origin is None and b3d:
        o0 = b3d[0]
        ref_origin = (o0["imageX"] * width, o0["imageY"] * height)
    if ref_origin is not None:
        x0r, y0r = ref_origin
        zero_rad = math.radians(zero_deg)
        ll = min(width, height) * 0.20
        x1r = x0r + ll * math.cos(zero_rad)
        y1r = y0r - ll * math.sin(zero_rad)
        ax.plot([x0r, x1r], [y0r, y1r], color="white", lw=1.5, ls="--", alpha=0.85,
                zorder=3, label=f"0 deg HLA ref ({zero_deg:.1f})")

    ax.text(0.01, 0.02, f"Impact frame: {impact}", transform=ax.transAxes,
            color="yellow", fontsize=10, bbox={"facecolor": "black", "alpha": 0.6})
    ax.legend(loc="upper right", fontsize=9, framealpha=0.6,
              facecolor="#222", labelcolor="white")
    fig.tight_layout()
    fig.savefig(out / f"tracking_overlay_frame_{fi:02d}.png", dpi=160)
    plt.close(fig)


def plot_ball_timeline(out, metrics, tracking):
    obs = ball_observations(metrics, tracking)
    if not obs:
        return
    idx = [o.get("frameIndex") for o in obs]
    xs = [o.get("centerX") for o in obs]
    ys = [o.get("centerY") for o in obs]
    ds = [o.get("smoothedDiameter") or o.get("maskRefinedDiameter") or o.get("diameter") for o in obs]
    cs = [o.get("confidence", 0) for o in obs]
    impact = metrics.get("detectedImpactFrameIndex", 20) if metrics else None

    fig, axes = plt.subplots(3, 1, figsize=(11, 8), sharex=True, facecolor="#111")
    for ax in axes:
        ax.set_facecolor("#111")
        ax.tick_params(colors="white")
        for sp in ax.spines.values():
            sp.set_color("#444")
        if impact:
            ax.axvline(impact, color="yellow", ls="--", lw=1, alpha=0.7, label="impact")

    axes[0].plot(idx, xs, label="x", color="lime", lw=1.5)
    axes[0].plot(idx, ys, label="y", color="cyan", lw=1.5)
    axes[0].set_ylabel("center (norm)", color="white")
    axes[0].legend(fontsize=8)
    axes[1].plot(idx, ds, color="lime", lw=1.5)
    axes[1].set_ylabel("diameter (norm)", color="white")
    axes[2].bar(idx, cs, color=["lime" if c and c > 0.5 else "gray" for c in cs])
    axes[2].set_ylabel("confidence", color="white")
    axes[2].set_xlabel("frame", color="white")

    fig.suptitle("Ball Tracking Timeline", color="white")
    fig.tight_layout()
    fig.savefig(out / "ball_tracking_timeline.png", dpi=160)
    plt.close(fig)


def plot_trajectory(out, metrics):
    obs = ball3d_observations(metrics)
    if not obs:
        return
    xs = [o["positionMeters"]["x"] for o in obs]
    ys = [o["positionMeters"]["y"] for o in obs]
    zs = [o["positionMeters"]["z"] for o in obs]
    fidx = [o["frameIndex"] for o in obs]

    fig, axes = plt.subplots(1, 2, figsize=(12, 5), facecolor="#111")
    for ax in axes:
        ax.set_facecolor("#111")
        ax.tick_params(colors="white")
        for sp in ax.spines.values():
            sp.set_color("#444")

    axes[0].plot(zs, xs, marker="o", color="cyan", lw=1.8)
    axes[0].set_title("Top-down (X / Z forward)", color="white")
    axes[0].set_xlabel("Z forward (m)", color="white")
    axes[0].set_ylabel("X horizontal (m)", color="white")
    axes[1].plot(zs, ys, marker="o", color="orange", lw=1.8)
    axes[1].set_title("Side (Y / Z forward)", color="white")
    axes[1].set_xlabel("Z forward (m)", color="white")
    axes[1].set_ylabel("Y vertical (m)", color="white")

    for ax, vals in ((axes[0], xs), (axes[1], ys)):
        for z, v, f in zip(zs, vals, fidx):
            ax.annotate(str(f), (z, v), textcoords="offset points", xytext=(3, 3),
                        fontsize=7, color="white")

    fig.suptitle("Ball 3D Trajectory", color="white")
    fig.tight_layout()
    fig.savefig(out / "trajectory_2d.png", dpi=160)
    plt.close(fig)


def plot_club(out, metrics):
    obs = club_observations(metrics)
    if not obs:
        return
    idx = [o["frameIndex"] for o in obs]
    cx = [o.get("centerX") for o in obs]
    cy = [o.get("centerY") for o in obs]
    lx = [o.get("leadingEdgeX") for o in obs]
    ly = [o.get("leadingEdgeY") for o in obs]
    conf = [o.get("confidence", 0) for o in obs]
    modes = [o.get("detectionMode", "") for o in obs]
    speed_frames = set(metrics.get("metrics", {}).get("clubSpeedFrameIndices", [])) if metrics else set()

    def _bar_color(m):
        if not m or m == "none" or m == "no_club_blob":
            return "gray"
        if "frameDiff" in m or "frameDifference" in m:
            return "#ff9900"
        if "dark" in m:
            return "yellow"
        if "edge" in m:
            return "cyan"
        if "hybrid" in m:
            return "#ff9900"
        return "#aaaaaa"
    bar_colors = [_bar_color(m) for m in modes]

    fig, axes = plt.subplots(3, 1, figsize=(11, 8), sharex=True, facecolor="#111")
    for ax in axes:
        ax.set_facecolor("#111")
        ax.tick_params(colors="white")
        for sp in ax.spines.values():
            sp.set_color("#444")

    axes[0].plot(idx, cx, marker="o", label="centerX", color="#ff9900", lw=1.5)
    axes[0].plot(idx, lx, marker="x", label="leadX (leading edge)", color="#ffcc44", lw=1.5)
    axes[0].set_ylabel("x (norm)", color="white")
    axes[0].legend(fontsize=8)
    axes[1].plot(idx, cy, marker="o", label="centerY", color="#ff9900", lw=1.5)
    axes[1].plot(idx, ly, marker="x", label="leadY (leading edge)", color="#ffcc44", lw=1.5)
    axes[1].set_ylabel("y (norm)", color="white")
    axes[1].legend(fontsize=8)
    axes[2].bar(idx, conf, color=bar_colors)
    axes[2].set_ylabel("confidence", color="white")
    axes[2].set_xlabel("frame", color="white")

    for fi in speed_frames:
        if fi in idx:
            axes[2].axvline(fi, color="cyan", ls=":", lw=1.5, alpha=0.8)

    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor="#ff9900", label="frameDiff / hybrid"),
        Patch(facecolor="yellow", label="dark only"),
        Patch(facecolor="cyan", label="edge only"),
        Patch(facecolor="gray", label="none / miss"),
    ]
    axes[2].legend(handles=legend_elements, fontsize=7, loc="upper left")

    fig.suptitle("Club Tracking", color="white")
    fig.tight_layout()
    fig.savefig(out / "club_tracking.png", dpi=160)
    plt.close(fig)


def plot_metrics_summary(out, metrics, show_details):
    fig = plt.figure(figsize=(14, 9), facecolor="#111")

    # Left: core ball/club/distance metrics
    left_w = 0.36 if show_details else 0.46
    ax = fig.add_axes([0.00, 0.00, left_w, 1.0])
    ax.set_facecolor("#111")
    ax.axis("off")

    # Center: estimated spin / path / face
    est_x0 = left_w + 0.01
    est_w = 0.24 if show_details else 0.22
    ax_e = fig.add_axes([est_x0, 0.00, est_w, 1.0])
    ax_e.set_facecolor("#111")
    ax_e.axis("off")

    if not metrics:
        ax.text(0.05, 0.9, "No experimental_metrics.json found", fontsize=14, color="white")
    else:
        m = metrics.get("metrics", {})
        cal = metrics.get("calibration", {})

        def row(axes_obj, label, value, formula, y, fs_lbl=11, fs_val=11):
            axes_obj.text(0.04, y, label, fontsize=fs_lbl, weight="bold", color="white")
            axes_obj.text(0.50, y, value, fontsize=fs_val, color="lime", fontfamily="monospace")
            if formula:
                axes_obj.text(0.04, y - 0.034, formula, fontsize=7.5,
                              color="cyan", fontfamily="monospace", alpha=0.8)

        title_y = 0.95
        ax.text(0.04, title_y, "METRICS", fontsize=13, weight="bold", color="white")

        rf = m.get("rolloutFraction")
        rollout_val = (f"{rf*100:.0f}%  ({value_text(m.get('rolloutYards'), ' yd', 0)})"
                       if rf is not None else "--")
        zero_deg_lbl = value_text(
            m.get("hlaReferenceAngle", metrics.get("zeroDegreeReferenceAngleDegrees", 0)), "")
        ccf = m.get("carryCorrectionFactor", 0.75)
        ideal_carry_txt = value_text(m.get("idealCarryYards"), " yd", 0)
        hla_display = m.get("hlaDisplay") or format_lr(m.get("hlaDegrees"))

        main_rows = [
            ("Ball Speed",    value_text(m.get("ballSpeedMph"), " mph"),  "= |v_ball| x 2.23694"),
            ("HLA (img-ref)", hla_display,                                f"ref angle = {zero_deg_lbl}"),
            ("VLA",           value_text(m.get("vlaDegrees"), ""),        "= atan2(vy, sqrt(vx2+vz2))"),
            ("Club Speed",    value_text(m.get("clubSpeedMph"), " mph"),  "= |v_club| x 2.23694"),
            ("Smash Factor",  value_text(m.get("smashFactor"), "", 2),    "= ball_speed / club_speed"),
            ("Ideal Carry",   ideal_carry_txt,                            "= v2*sin(2t)/g  (no drag)"),
            ("Est. Carry",    value_text(m.get("carryYards"), " yd", 0), f"= idealCarry x cf={ccf:.2f}"),
            ("Rollout",       rollout_val,                                f"VLA bucket: {m.get('vlaBucket','?')}"),
            ("Est. Total",    value_text(m.get("totalYards"), " yd", 0), "= carry + rollout"),
            ("Ball / Club pts",
             f"{m.get('ballPointsUsed','--')} / {m.get('clubPointsUsed','--')}", None),
        ]

        y = title_y - 0.07
        for label, value, formula in main_rows:
            row(ax, label, value, formula, y)
            y -= 0.085 if formula else 0.060

        ax.axhline(y + 0.01, color="#333", lw=0.7, transform=ax.transAxes)
        y -= 0.02
        ax.text(0.04, y, "Calibration", fontsize=10, weight="bold", color="white")
        y -= 0.048
        for key, val in [
            ("Image", f"{cal.get('imageWidthPixels','?')}x{cal.get('imageHeightPixels','?')} px"),
            ("H/V FOV", f"{value_text(cal.get('horizontalFOVDegrees'),'',0)} / "
                        f"{value_text(cal.get('verticalFOVDegrees'),'',0)}"),
            ("fx / fy", f"{value_text(cal.get('focalLengthPixelsX'),' px',0)} / "
                        f"{value_text(cal.get('focalLengthPixelsY'),' px',0)}"),
        ]:
            ax.text(0.04, y, key, fontsize=9, color="white")
            ax.text(0.40, y, val, fontsize=9, color="cyan", fontfamily="monospace")
            y -= 0.045

        # Warnings
        warnings = metrics.get("warnings", [])
        if warnings:
            y -= 0.01
            ax.text(0.04, y, "Warnings", fontsize=10, weight="bold", color="orange")
            y -= 0.042
            for w in warnings[:5]:
                ax.text(0.04, y, f"  {w}", fontsize=7.5, color="orange")
                y -= 0.038

        # Estimated / spin / path / face (center panel)
        ax_e.text(0.04, title_y, "ESTIMATED", fontsize=12, weight="bold", color="#aaaaaa")
        ax_e.text(0.04, title_y - 0.045, "(model-based, not measured)",
                  fontsize=7.5, color="#666666", style="italic")

        est_rows = [
            ("Backspin",    value_text(m.get("estimatedBackspinRpm"), " rpm", 0)),
            ("Sidespin",    m.get("estimatedSidespinDisplay") or
                            format_lr(m.get("estimatedSidespinRpmSigned")) + " rpm"),
            ("Spin Axis",   m.get("estimatedSpinAxisDisplay") or
                            format_lr(m.get("estimatedSpinAxisDegreesSigned"))),
            ("Spin Method", m.get("spinEstimateMethod") or "--"),
            ("Club Path",   m.get("clubPathDisplay") or
                            format_lr(m.get("clubPathDegreesSigned"))),
            ("Face Angle",  m.get("estimatedFaceAngleDisplay") or
                            format_lr(m.get("estimatedFaceAngleDegreesSigned"))),
            ("Face-to-Path", m.get("faceToPathDisplay") or
                             format_lr(m.get("faceToPathDegreesSigned"))),
            ("Face Conf",   str(m.get("faceAngleConfidence") or "--")),
        ]

        ey = title_y - 0.10
        for label, value in est_rows:
            ax_e.text(0.04, ey, label, fontsize=10, weight="bold", color="#aaaaaa")
            ax_e.text(0.04, ey - 0.032, value, fontsize=10, color="#ccff88",
                      fontfamily="monospace")
            ey -= 0.085

    # Right: formulas (optional)
    if show_details:
        ax2 = fig.add_axes([est_x0 + est_w + 0.01, 0.00,
                            1.0 - (est_x0 + est_w + 0.01), 1.0])
        ax2.set_facecolor("#0a0a1a")
        ax2.axis("off")
        ax2.text(0.04, 0.96, "HOW IT'S CALCULATED", fontsize=11, weight="bold", color="white")

        formulas = [
            ("3D Position (pinhole)",
             "Z = ballDiam x focalLen / apparentDiamPx\n"
             "X = (px - cx) x Z / fx\n"
             "Y = (py - cy) x Z / fy"),
            ("Ball Velocity",
             "Linear regression >=3 post-impact\n"
             "3D positions vs time.\n"
             "2-point delta fallback if only 2 pts."),
            ("HLA (image-space)",
             "ref = (cos t, -sin t)  [y-down]\n"
             "perp = (sin t, cos t)\n"
             "fwd = dx*refX + dy*refY\n"
             "lat = dx*perpX + dy*perpY\n"
             "HLA = atan2(lat, fwd)\n"
             "t = zeroDegreeReferenceAngle"),
            ("VLA",
             "VLA = atan2(vy, sqrt(vx2+vz2))  (3D)"),
            ("Club Speed",
             "Club 3D depth = ball depth near impact.\n"
             "Same linear fit method."),
            ("Distance",
             "idealCarry = v2*sin(2*vla)/g  (ballistic)\n"
             "carry = idealCarry x corrFactor x 1.094 yd\n"
             "corrFactor default 0.75 (drag approx)\n"
             "Rollout VLA buckets:\n"
             "  <1:85%  1-3:65%  3-6:45%  6-10:30%\n"
             "  10-15:20%  15-22:12%  22-30:7%  >=30:3%\n"
             "speedAdj: <40*0.45  40-80*0.75  >=130*1.1"),
            ("Est. Spin (Model-Based)",
             "backspin=(800+90*spd+120*vla)*vlaMultiplier\n"
             "  <5:x0.60  5-10:x0.80  10-20:x1.00\n"
             "  20-30:x1.20  >=30:x1.35  clamp 300-9000\n"
             "sidespin=(HLA-path)*200*(spd/100)\n"
             "spinAxis=atan2(sidespin,backspin)"),
            ("Club Path & Face",
             "clubPath: centroid 2D regression\n"
             "  onto 0-deg ref -> atan2  (image-space)\n"
             "faceAngle: bbox longest-axis heuristic\n"
             "face-to-path = face - clubPath"),
        ]

        y = 0.88
        for title, body in formulas:
            ax2.text(0.04, y, title, fontsize=9.5, weight="bold", color="white")
            y -= 0.03
            ax2.text(0.04, y, body, fontsize=8.0, color="cyan",
                     fontfamily="monospace", va="top",
                     bbox={"facecolor": "#1a1a2e", "alpha": 0.5, "boxstyle": "round,pad=0.3"})
            line_count = body.count("\n") + 1
            y -= 0.036 * line_count + 0.025

    fig.savefig(out / "metrics_summary.png", dpi=160, bbox_inches="tight")
    plt.close(fig)


# ── Clubface debug figure ─────────────────────────────────────────────────────

def _clubface_roi_norm(ball_cx, ball_cy, ball_dia, W, H, co_best, fa):
    dia_px = ball_dia * W
    hw = dia_px * fa.face_roi_scale_x / 2
    hh = dia_px * fa.face_roi_scale_y / 2
    cx_px = ball_cx * W + fa.face_roi_offset_x * W
    cy_px = ball_cy * H + fa.face_roi_offset_y * H
    x0 = max(0.0, (cx_px - hw) / W)
    y0 = max(0.0, (cy_px - hh) / H)
    x1 = min(1.0, (cx_px + hw) / W)
    y1 = min(1.0, (cy_px + hh) / H)
    if fa.face_use_club_box and co_best:
        bbox = co_best.get("clubBoundingBox")
        if isinstance(bbox, dict):
            bbx, bby, bbw, bbh = bbox["x"], bbox["y"], bbox["width"], bbox["height"]
            pad = fa.face_club_box_padding
            x0 = min(x0, max(0.0, bbx - bbw * (pad - 1) / 2))
            y0 = min(y0, max(0.0, bby - bbh * (pad - 1) / 2))
            x1 = max(x1, min(1.0, bbx + bbw * (1 + (pad - 1) / 2)))
            y1 = max(y1, min(1.0, bby + bbh * (1 + (pad - 1) / 2)))
    return dict(x0=x0, y0=y0, x1=x1, y1=y1)


def _excl_mask_crop(crop_h, crop_w, ball_cx, ball_cy, ball_dia, W, H, x0r, y0r, fa):
    excl_r = ball_dia * W * fa.face_ball_exclusion_scale / 2
    bpx = ball_cx * W - x0r
    bpy = ball_cy * H - y0r
    ys, xs = np.mgrid[0:crop_h, 0:crop_w]
    return (xs - bpx) ** 2 + (ys - bpy) ** 2 <= excl_r ** 2


def _sobel_mag(gray_f):
    gx = np.zeros_like(gray_f); gy = np.zeros_like(gray_f)
    if gray_f.shape[0] > 2:
        gy[1:-1] = (gray_f[2:] - gray_f[:-2]) / 2.0
    if gray_f.shape[1] > 2:
        gx[:, 1:-1] = (gray_f[:, 2:] - gray_f[:, :-2]) / 2.0
    return gx, gy, np.sqrt(gx ** 2 + gy ** 2)


def _detect_face_pca(gray, excl_mask, x0r, y0r, W, H, fa):
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
    edge_angles = np.arctan2(gx_pts, gy_pts)
    cos2 = float(np.sum(np.cos(2 * edge_angles) * mags))
    sin2 = float(np.sum(np.sin(2 * edge_angles) * mags))
    weight_sum = float(np.sum(mags))
    if weight_sum < 1e-6:
        return None
    dom_angle = math.atan2(sin2, cos2) / 2.0
    coherence = math.sqrt(cos2 ** 2 + sin2 ** 2) / weight_sum
    cx_crop = float(np.sum(cols * mags) / weight_sum)
    cy_crop = float(np.sum(rows * mags) / weight_sum)
    return dict(method="pca", cx=(x0r + cx_crop) / W, cy=(y0r + cy_crop) / H,
                angle_rad=dom_angle, coherence=coherence, edge_count=int(len(rows)))


def _detect_face_hough(gray, excl_mask, x0r, y0r, W, H, fa):
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
    best = max(lines, key=lambda l: math.hypot(l[0][2] - l[0][0], l[0][3] - l[0][1]))
    x1c, y1c, x2c, y2c = best[0]
    cx_crop = (x1c + x2c) / 2.0; cy_crop = (y1c + y2c) / 2.0
    angle_rad = math.atan2(float(y2c - y1c), float(x2c - x1c))
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


def plot_clubface_debug(root, out, metrics, fa):
    """Save clubface_debug.png and face_debug.json."""
    if not metrics:
        print("Clubface debug: no metrics — skipping.")
        return

    impact = metrics.get("detectedImpactFrameIndex", 0)
    frame_i = fa.face_frame if fa.face_frame is not None else (impact + fa.face_frame_offset)
    zero_deg = metrics.get("zeroDegreeReferenceAngleDegrees", 0)

    # Load frame image
    frame_paths = frames(root)
    if not frame_paths:
        print("Clubface debug: no frame images found.")
        return
    frame_path = next((p for p in frame_paths if frame_index(p) == frame_i), None)
    if frame_path is None:
        frame_path = frame_paths[min(frame_i, len(frame_paths) - 1)]
        frame_i = frame_index(frame_path)
    img_arr = np.array(__import__("PIL").Image.open(frame_path).convert("RGB"))
    H, W = img_arr.shape[:2]

    # Ball position — prefer ball3D obs, fallback to tracking obs
    ball_cx = ball_cy = ball_dia = None
    b3d = ball3d_observations(metrics)
    if b3d:
        ob = min(b3d, key=lambda o: abs(o["frameIndex"] - frame_i))
        ball_cx, ball_cy = float(ob["imageX"]), float(ob["imageY"])
        ball_dia = float(ob["diameterNorm"])
    if ball_cx is None:
        balls = obs_by_frame(ball_observations(metrics, None))
        for fi in [frame_i] + list(range(max(0, frame_i - 5), frame_i + 6)):
            bo = balls.get(fi)
            if bo and bo.get("centerX") is not None:
                ball_cx, ball_cy = float(bo["centerX"]), float(bo["centerY"])
                ball_dia = float(bo.get("smoothedDiameter") or bo.get("diameter") or 0.02)
                break

    if ball_cx is None:
        print(f"Clubface debug: no ball position found near frame {frame_i}.")
        _clubface_failure_fig_pt(img_arr, frame_i, "no_ball_position", out)
        return

    # Nearest club obs with bbox
    clubs_all = club_observations(metrics)
    co_near = sorted([o for o in clubs_all if isinstance(o.get("clubBoundingBox"), dict)],
                     key=lambda o: abs(o.get("frameIndex", 9999) - frame_i))
    co_best = co_near[0] if co_near else None

    roi = _clubface_roi_norm(ball_cx, ball_cy, ball_dia, W, H, co_best, fa)
    x0r = max(0, int(roi["x0"] * W)); y0r = max(0, int(roi["y0"] * H))
    x1r = min(W, int(roi["x1"] * W)); y1r = min(H, int(roi["y1"] * H))
    crop_w = x1r - x0r; crop_h = y1r - y0r

    face_result = None; excl = None; gray_crop = None
    if crop_w >= 10 and crop_h >= 10:
        crop = img_arr[y0r:y1r, x0r:x1r].astype(np.float32)
        gray_crop = np.mean(crop, axis=2)
        excl = _excl_mask_crop(crop_h, crop_w, ball_cx, ball_cy, ball_dia, W, H, x0r, y0r, fa)
        if fa.face_method in ("auto", "hough"):
            face_result = _detect_face_hough(gray_crop, excl, x0r, y0r, W, H, fa)
        if face_result is None and fa.face_method in ("auto", "pca"):
            face_result = _detect_face_pca(gray_crop, excl, x0r, y0r, W, H, fa)

    ainfo = _face_angle_info(face_result, zero_deg, fa) if face_result else None

    fig2, (ax_f, ax_z) = plt.subplots(1, 2, figsize=(16, 9), facecolor="#111",
                                       gridspec_kw={"width_ratios": [2, 1]})
    for ax in (ax_f, ax_z):
        ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
        for sp in ax.spines.values():
            sp.set_color("#444")

    ax_f.imshow(img_arr, origin="upper", aspect="equal")

    bx = ball_cx * W; by = ball_cy * H; br = ball_dia * W / 2
    ax_f.add_patch(Circle((bx, by), br, color="#44ff44", fill=False, lw=2.0, zorder=5))
    ax_f.plot(bx, by, "g+", markersize=10, mew=2, zorder=6)

    excl_r = ball_dia * W * fa.face_ball_exclusion_scale / 2
    ax_f.add_patch(Circle((bx, by), excl_r, color="#ff9900",
                           fill=False, lw=1.5, ls="--", alpha=0.7, zorder=4))

    roi_xpx = roi["x0"] * W; roi_ypx = roi["y0"] * H
    roi_wpx = (roi["x1"] - roi["x0"]) * W; roi_hpx = (roi["y1"] - roi["y0"]) * H
    ax_f.add_patch(Rectangle((roi_xpx, roi_ypx), roi_wpx, roi_hpx,
                               lw=1.5, edgecolor="cyan", facecolor="none",
                               ls="--", alpha=0.8, zorder=4))

    if co_best:
        bbox = co_best.get("clubBoundingBox")
        if isinstance(bbox, dict):
            ax_f.add_patch(Rectangle((bbox["x"] * W, bbox["y"] * H),
                                      bbox["width"] * W, bbox["height"] * H,
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
        ax_z.imshow(img_arr[y0r:y1r, x0r:x1r], origin="upper", aspect="equal",
                    extent=[x0r, x1r, y1r, y0r])
        ax_z.add_patch(Circle((bx, by), excl_r, color="#ff9900",
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
    out_png = out / "clubface_debug.png"
    fig2.savefig(out_png, dpi=150, facecolor="#111", bbox_inches="tight")
    plt.close(fig2)
    print(f"Saved: {out_png}")

    if fa.face_save_mask_debug and gray_crop is not None:
        _, _, mag = _sobel_mag(gray_crop.astype(float))
        fig3, axes3 = plt.subplots(1, 3, figsize=(15, 5), facecolor="#111")
        for ax, img, title, cmap in zip(
                axes3,
                [gray_crop, mag, excl.astype(float) * 255],
                ["Grayscale Crop", "Sobel Edge Magnitude", "Exclusion Mask"],
                ["gray", "hot", "gray"]):
            ax.imshow(img, cmap=cmap, origin="upper")
            ax.set_title(title, color="white", fontsize=9)
            ax.set_xticks([]); ax.set_yticks([])
            for sp in ax.spines.values():
                sp.set_color("#444")
        axes3[1].contour(mag, levels=[fa.face_edge_threshold], colors=["cyan"], linewidths=0.8)
        plt.suptitle(f"Clubface Mask Debug  Frame {frame_i}", color="white", fontsize=10)
        plt.tight_layout()
        out_mask = out / "clubface_mask_debug.png"
        fig3.savefig(out_mask, dpi=120, facecolor="#111", bbox_inches="tight")
        plt.close(fig3)
        print(f"Saved: {out_mask}")

    m_metrics = metrics.get("metrics", {}) if metrics else {}
    cp_angle = m_metrics.get("clubPathDegreesSigned")
    cp_display = m_metrics.get("clubPathDisplay", "--")
    payload = dict(
        schema="ballstrike.face_debug.v1",
        frameIndex=frame_i, impactFrameIndex=impact,
        zeroDegreeAngleDegrees=zero_deg,
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
        clubPathForReference=dict(angleDegrees=cp_angle, display=cp_display),
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
    out_json = out / "face_debug.json"
    with open(out_json, "w") as f:
        json.dump(payload, f, indent=2, sort_keys=True, default=lambda _: None)
    print(f"Saved: {out_json}")


def _clubface_failure_fig_pt(img_arr, frame_i, reason, out):
    fig2, ax = plt.subplots(figsize=(10, 6), facecolor="#111")
    ax.set_facecolor("#111"); ax.set_xticks([]); ax.set_yticks([])
    ax.imshow(img_arr, origin="upper", aspect="equal")
    ax.text(0.5, 0.5, f"No clubface detected\n({reason})",
            color="#ff6644", fontsize=16, ha="center", va="center",
            transform=ax.transAxes, weight="bold",
            bbox=dict(facecolor="#111", alpha=0.8, boxstyle="round,pad=0.5"))
    ax.set_title(f"Clubface Debug  Frame {frame_i}  FAILED", color="#ff6644", fontsize=11)
    plt.tight_layout()
    out_png = out / "clubface_debug.png"
    fig2.savefig(out_png, dpi=150, facecolor="#111", bbox_inches="tight")
    plt.close(fig2)
    print(f"Saved (failure): {out_png}")


def main():
    parser = argparse.ArgumentParser(description="Plot ball/club tracking from experimental_metrics.json")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--shot", help="Path to exported shot folder")
    group.add_argument("--zip", help="Path to exported shot zip")
    parser.add_argument("--frame", type=int, default=None,
                        help="Frame index for overlay plot (default: impact)")
    parser.add_argument("--metrics", default=None,
                        help="Path to experimental_metrics.json (default: auto)")
    parser.add_argument("--tracking", default=None,
                        help="Path to tracking.json (default: auto)")
    parser.add_argument("--output", default=None,
                        help="Output folder (default: shot folder)")
    parser.add_argument("--show-ball-path", action="store_true", default=True,
                        help="Draw ball path on overlay (default: on)")
    parser.add_argument("--no-ball-path", dest="show_ball_path", action="store_false")
    parser.add_argument("--show-club", action="store_true", default=True,
                        help="Draw club overlays (default: on)")
    parser.add_argument("--no-club", dest="show_club", action="store_false")
    parser.add_argument("--show-metrics-details", action="store_true", default=False,
                        help="Add formula explanation panel to metrics summary")

    # Clubface debug
    parser.add_argument("--save-face-debug",        action="store_true")
    parser.add_argument("--face-frame",             type=int,   default=None)
    parser.add_argument("--face-frame-offset",      type=int,   default=0)
    parser.add_argument("--face-method",            default="auto", choices=["auto","hough","pca"])
    parser.add_argument("--face-roi-scale-x",       type=float, default=4.0)
    parser.add_argument("--face-roi-scale-y",       type=float, default=3.0)
    parser.add_argument("--face-roi-offset-x",      type=float, default=0.0)
    parser.add_argument("--face-roi-offset-y",      type=float, default=0.0)
    parser.add_argument("--face-ball-exclusion-scale", type=float, default=1.4)
    parser.add_argument("--face-use-club-box",      action="store_true")
    parser.add_argument("--face-club-box-padding",  type=float, default=1.5)
    parser.add_argument("--face-edge-threshold",    type=float, default=20.0)
    parser.add_argument("--face-min-edge-pixels",   type=int,   default=30)
    parser.add_argument("--face-pca-outlier-trim",  type=float, default=0.05)
    parser.add_argument("--face-canny-low",         type=int,   default=50)
    parser.add_argument("--face-canny-high",        type=int,   default=150)
    parser.add_argument("--face-hough-threshold",   type=int,   default=30)
    parser.add_argument("--face-hough-min-length",  type=int,   default=15)
    parser.add_argument("--face-hough-max-gap",     type=int,   default=10)
    parser.add_argument("--face-angle-normal-mode", default="line", choices=["line","normal"])
    parser.add_argument("--face-angle-flip",        type=int,   default=0, choices=[0,1])
    parser.add_argument("--face-save-mask-debug",   action="store_true")

    args = parser.parse_args()

    root, temp = shot_root(args)
    out = output_dir(root, args)
    metrics = load_json(Path(args.metrics)) if args.metrics else load_json(root / "experimental_metrics.json")
    tracking = load_json(Path(args.tracking)) if args.tracking else load_json(root / "tracking.json")

    plot_overlay(root, out, args.frame, metrics, tracking, args.show_ball_path, args.show_club)
    plot_ball_timeline(out, metrics, tracking)
    plot_trajectory(out, metrics)
    plot_club(out, metrics)
    plot_metrics_summary(out, metrics, args.show_metrics_details)

    if args.save_face_debug:
        plot_clubface_debug(root, out, metrics, args)

    print(f"Wrote plots to {out}")
    if temp is not None:
        temp.cleanup()


if __name__ == "__main__":
    main()
