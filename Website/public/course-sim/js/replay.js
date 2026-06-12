// Button-triggered cinematic shot replay.
// Records trajectory during physics, replays via Catmull-Rom camera spline.

import * as THREE from 'three';

let _trajectory = [];   // recorded positions during flight
let _replayActive = false;
let _replayT = 0;       // normalized time 0-1
let _replayDuration = 3.5; // seconds
let _clock = null;
let _camTarget = null;  // { camera, controls }
let _savedCamPos = null, _savedCamLookAt = null;
let _onDone = null;

// Call once per substep during flight to record ball position
export function recordPosition(pos) {
  _trajectory.push({ x: pos.x, y: pos.y, z: pos.z });
}

export function clearTrajectory() {
  _trajectory = [];
}

export function hasTrajectory() {
  return _trajectory.length > 5;
}

// Build a smoothed camera path above and behind the trajectory
function buildCameraPath(traj) {
  const N = 12;
  const pts = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N;
    const idx = Math.min(Math.floor(t * (traj.length - 1)), traj.length - 2);
    const frac = t * (traj.length - 1) - idx;
    const p = traj[idx];
    const q = traj[idx + 1] || p;
    const bx = p.x + (q.x - p.x) * frac;
    const by = p.y + (q.y - p.y) * frac;
    const bz = p.z + (q.z - p.z) * frac;

    // Camera sits above and slightly behind
    const offsetY = 6 + Math.sin(t * Math.PI) * 12;
    const dx = t < 0.02 ? 0 : (bx - (traj[Math.max(0, idx-1)].x)) * 2;
    const dz = t < 0.02 ? 0 : (bz - (traj[Math.max(0, idx-1)].z)) * 2;
    pts.push(new THREE.Vector3(bx - dx * 0.4, by + offsetY, bz - dz * 0.4));
  }
  return new THREE.CatmullRomCurve3(pts);
}

function buildLookAtPath(traj) {
  const N = 12;
  const pts = [];
  for (let i = 0; i <= N; i++) {
    const t = i / N;
    const idx = Math.min(Math.floor(t * (traj.length - 1)), traj.length - 1);
    const p = traj[idx];
    pts.push(new THREE.Vector3(p.x, p.y + 0.5, p.z));
  }
  return new THREE.CatmullRomCurve3(pts);
}

// Show the replay button in the HUD
export function showReplayButton() {
  const btn = document.getElementById('replay-btn');
  if (btn) btn.classList.remove('hidden');
}

export function hideReplayButton() {
  const btn = document.getElementById('replay-btn');
  if (btn) btn.classList.add('hidden');
}

// Called when user clicks the replay button
export function startReplay(camera, onDone) {
  if (!hasTrajectory()) { if (onDone) onDone(); return; }
  _replayActive = true;
  _replayT = 0;
  _clock = Date.now();
  _onDone = onDone;
  _camTarget = camera;

  // Save current camera state to restore after replay
  _savedCamPos = camera.position.clone();
  _savedCamLookAt = new THREE.Vector3(0, 0, 0);

  hideReplayButton();

  // Show skip button
  const skip = document.getElementById('replay-skip');
  if (skip) skip.classList.remove('hidden');
}

export function skipReplay() {
  if (!_replayActive) return;
  _replayActive = false;
  hideReplayButton();
  const skip = document.getElementById('replay-skip');
  if (skip) skip.classList.add('hidden');
  if (_onDone) _onDone();
}

// Call this every animation frame — returns true while replay is active
export function updateReplay(camera) {
  if (!_replayActive) return false;

  const elapsed = (Date.now() - _clock) / 1000;
  _replayT = Math.min(elapsed / _replayDuration, 1);

  if (_trajectory.length < 2) { skipReplay(); return false; }

  const camPath = buildCameraPath(_trajectory);
  const lookPath = buildLookAtPath(_trajectory);

  // Ease in/out
  const ease = _replayT < 0.5
    ? 2 * _replayT * _replayT
    : 1 - 2 * (1 - _replayT) * (1 - _replayT);

  const camPt  = camPath.getPoint(ease);
  const lookPt = lookPath.getPoint(Math.min(ease + 0.05, 1));

  camera.position.copy(camPt);
  camera.lookAt(lookPt);

  if (_replayT >= 1) {
    // Brief pause at landing, then finish
    setTimeout(() => {
      _replayActive = false;
      const skip = document.getElementById('replay-skip');
      if (skip) skip.classList.add('hidden');
      if (_onDone) _onDone();
    }, 800);
    _replayActive = false; // prevent double-call
    return false;
  }
  return true;
}

export function isReplaying() { return _replayActive; }
