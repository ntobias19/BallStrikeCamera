# Ball Tracking Tester Python Plots

Offline matplotlib tools for inspecting exported BallStrikeCamera shots and experimental metrics.

## Export a Shot

1. Capture a shot in the app.
2. Open the post-shot review screen.
3. Export the shot package.
4. Open the DEBUG BallTrackingTester.
5. Load that same shot export, run the tracker, then tap **Export Metrics**.

The shot folder should contain frames plus JSON files such as:

- `frame_000.png` ... `frame_040.png`
- `timestamps.json`
- `metadata.json`
- `tracking.json`
- `experimental_metrics.json`

## Install

```bash
cd BallStrikeCamera/Experimental/BallTrackingTester/Python
python3 -m pip install -r requirements.txt
```

## Usage

Folder input:

```bash
python3 plot_tracking.py --shot /path/to/ShotExport_YYYYMMDD_HHMMSS
```

Zip input:

```bash
python3 plot_tracking.py --zip /path/to/ShotExport_YYYYMMDD_HHMMSS.zip
```

Optional selected frame:

```bash
python3 plot_tracking.py --shot /path/to/ShotExport --frame 23
```

## Outputs

The script writes PNGs next to the shot folder by default:

- `tracking_overlay_frame_XX.png`: selected frame with ball, club, ROI, and impact marker
- `ball_tracking_timeline.png`: ball x/y, diameter, and confidence by frame
- `trajectory_2d.png`: top-down X/Z and side Y/Z ball trajectory
- `club_tracking.png`: club center/leading edge and speed frames
- `metrics_summary.png`: metric values and warnings

These plots are for tuning/debugging. Ball speed, club speed, carry, and total depend on estimated FOV and approximate club depth.

---

## shot_tester.py (Interactive GUI Tuner)

`/tmp/shot_tester.py` is the full interactive tuner. It replaces `plot_tracking.py` with a live
matplotlib GUI that lets you scrub frames, adjust all tracking parameters with sliders, and
re-run the tracker without restarting.

### Basic usage

```bash
python3 /tmp/shot_tester.py "/path/to/ShotExport"
```

Three tabs: **Ball Tracking**, **Club Tracking**, **Metrics**. Press **Run** to execute the
tracker with current slider values. Results appear immediately.

### Metrics computed

After running, the Metrics tab shows:

| Metric | Notes |
|--------|-------|
| Ball Speed | 3D velocity fit from post-impact frames |
| HLA (img-ref) | Image-space horizontal launch angle relative to 0° reference |
| VLA | Vertical launch angle from 3D velocity fit |
| Club Speed | Estimated from clubhead position near impact |
| Smash Factor | ball\_speed / club\_speed |
| Ideal Carry | Ballistic carry: v²·sin(2θ)/g (no drag) |
| Est. Carry | idealCarry × correctionFactor (default 0.75) |
| Rollout / Total | VLA-bucket rollout model |
| Backspin (Est) | Model-based: (800+90·spd+120·vla)×vlaMultiplier. ESTIMATED. |
| Sidespin (Est) | (HLA−clubPath)×200×(speed/100). ESTIMATED. |
| Club Path (Est) | Centroid 2D regression → projected onto 0° ref. ESTIMATED. |
| Face Angle (Est) | Bbox longest-axis heuristic. Very low confidence. |

All directional values use **L/R convention**: positive = R, negative = L.

### Saved files

After each Run, two files are written to the shot folder:

- `python_experimental_metrics.json` — all metrics in schema `ballstrike.python_shot_tester_metrics.v2`

### Carry correction slider

The **Carry Correction** slider (0.40–1.20, default 0.75) scales the ballistic ideal carry.
A value of 0.75 compensates for aerodynamic drag on a golf ball. Tune this per club/swing speed.

---

## Clubface Debug Figure

Add `--save-face-debug` to generate a dedicated clubface analysis figure after each Run:

```bash
python3 /tmp/shot_tester.py "/path/to/ShotExport" --save-face-debug
```

Three output files are written to the shot folder:

- `clubface_debug.png` — full-frame + zoomed crop with all overlays
- `face_debug.json` — all detection inputs/outputs in schema `ballstrike.face_debug.v1`
- `clubface_mask_debug.png` — edge/mask internals (requires `--face-save-mask-debug`)

### What each line/color means

| Element | Color | Meaning |
|---------|-------|---------|
| Solid circle | Green | Ball detection (from tracking) |
| + crosshair | Green | Ball center |
| Dashed circle | Orange | Ball exclusion zone (club detection ignores this area) |
| Dashed rectangle | Cyan | Clubface search ROI |
| Solid rectangle | Orange | Club bounding box (nearest to frame, if detected) |
| Dashed line | White | 0° reference direction (set by "0° Ref Angle" slider) |
| Solid line | Magenta | Detected clubface line |
| Arrow | Yellow | Projection ray from face center in face direction |
| Top-left text | Magenta | Face angle, method, coherence, edge point count |

### Detection methods

`--face-method auto` (default) tries Hough first (requires `cv2`), falls back to PCA.

**PCA** (always available, no cv2 required):
- Computes Sobel edge magnitude across the ROI
- Removes ball exclusion zone
- Uses circular statistics (double-angle accumulation) to find the dominant edge direction
- Coherence (0–1) measures how consistent the edge directions are; values below ~0.15 indicate
  a noisy or ambiguous result

**Hough** (requires `pip install opencv-python`):
- Canny edge detection → HoughLinesP
- Picks the longest detected line segment
- More reliable on clean, straight club faces; less reliable when there is motion blur

### Angle convention

Face angle is measured relative to the 0° reference direction (set by the "0° Ref Angle" slider):
- **Positive** = face open (pointing Right of reference)
- **Negative** = face closed (pointing Left of reference)

`--face-angle-normal-mode line` (default): the angle reported is the angle of the detected face
*line* itself relative to the 0° reference.

`--face-angle-normal-mode normal`: the angle is rotated 90° so it represents the *normal*
(perpendicular) to the face, i.e., the direction the ball will be launched.

### Frame selection

By default the impact frame is used. Override with:

```bash
--face-frame 23          # exact frame index
--face-frame-offset -1   # offset from detected impact (e.g. one frame before)
```

### Search ROI tuning

The ROI is centered on the ball and scaled by ball diameter:

```bash
--face-roi-scale-x 4.0   # ROI width  = ball_dia × scale_x  (default 4.0)
--face-roi-scale-y 3.0   # ROI height = ball_dia × scale_y  (default 3.0)
--face-roi-offset-x 0.0  # shift ROI center left/right (normalized, default 0)
--face-roi-offset-y 0.0  # shift ROI center up/down   (normalized, default 0)
--face-ball-exclusion-scale 1.4  # exclusion radius = ball_dia × scale / 2
--face-use-club-box       # expand ROI to include nearest club bounding box
--face-club-box-padding 1.5      # padding multiplier around club box
```

### Detection threshold tuning

```bash
# PCA / edge detection
--face-edge-threshold 20     # Sobel magnitude cutoff (default 20)
--face-min-edge-pixels 30    # minimum edge pixels needed to attempt PCA (default 30)
--face-pca-outlier-trim 0.05 # trim top/bottom 5% of edge magnitudes before PCA (default 0.05)

# Hough (cv2 only)
--face-canny-low 50          # Canny lower threshold (default 50)
--face-canny-high 150        # Canny upper threshold (default 150)
--face-hough-threshold 30    # Hough accumulator threshold (default 30)
--face-hough-min-length 15   # minimum line segment length in pixels (default 15)
--face-hough-max-gap 10      # maximum gap between line segments (default 10)
```

### Other flags

```bash
--face-angle-flip 1       # flip sign of computed angle (default 0)
--face-save-mask-debug    # also save clubface_mask_debug.png
```

### Limitations

- Face angle from image edges is inherently ambiguous: the detected line could be the shaft,
  hosel, or a background edge rather than the face. Motion blur at impact further degrades
  reliability. Treat results as indicative, not measured.
- PCA coherence below ~0.15 usually means no dominant edge was found.
- Hough requires `pip install opencv-python` and may fail on blurry frames.
- All estimates assume the clubhead is visible and within the ROI. Adjust
  `--face-roi-offset-x` / `--face-roi-offset-y` if the club is consistently off-center.
