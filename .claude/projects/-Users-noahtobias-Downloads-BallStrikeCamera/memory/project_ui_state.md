---
name: Post-Shot UI State (May 2026)
description: Current ShotResultView flow and VLA feature parity status
type: project
---

Combined animation screen + frame replay auto-transition implemented.

**Why:** User wanted cinematic side-view + top-down mini map on ONE screen, with auto-transition to frame replay.

**How to apply:** ShotResultView now shows both animations in parallel, auto-opens ShotTrackingReviewView after completion. ShotTrackingReviewView has two-row topBar + actionBar (Save/Bad) footer.

VLA feature parity: All 61/61 model features now computed in Swift (ground calibration IDW + full feature set). GroundCalibration.autoLoad() in VLAModelPredictor.swift. ShotMetricsCalculator passes all post-impact obs (not just 6) to VLA feature extraction.
