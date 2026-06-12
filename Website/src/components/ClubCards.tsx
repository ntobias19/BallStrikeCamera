"use client";

import { useRef } from "react";

type Card = { club: string; loft: string; carry: string; id: string };

const CARDS: Card[] = [
  { club: "Driver", loft: "10.5°", carry: "251", id: "TC·01" },
  { club: "7 Iron", loft: "30.5°", carry: "169", id: "TC·07" },
  { club: "56° Wedge", loft: "56°", carry: "101", id: "TC·12" },
];

function NfcWave() {
  return (
    <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" aria-hidden>
      <circle cx="7.5" cy="12" r="1.3" fill="currentColor" stroke="none" />
      <path d="M11.5 8.5a6 6 0 0 1 0 7" />
      <path d="M15 6a10 10 0 0 1 0 12" />
    </svg>
  );
}

/**
 * The NFC club-card fan. Cards live in a perspective stage and tilt in 3D
 * toward the pointer; a holographic sheen tracks the same coordinates.
 * Idle, they float on offset phases so the stack never sits still.
 */
export default function ClubCards() {
  const stageRef = useRef<HTMLDivElement | null>(null);

  function onMove(e: React.PointerEvent<HTMLDivElement>) {
    const el = stageRef.current;
    if (!el) return;
    const r = el.getBoundingClientRect();
    el.style.setProperty("--tx", `${(e.clientX - r.left) / r.width - 0.5}`);
    el.style.setProperty("--ty", `${(e.clientY - r.top) / r.height - 0.5}`);
  }

  function onLeave() {
    const el = stageRef.current;
    if (!el) return;
    el.style.setProperty("--tx", "0");
    el.style.setProperty("--ty", "0");
  }

  return (
    <div className="club-cards" ref={stageRef} onPointerMove={onMove} onPointerLeave={onLeave}>
      {CARDS.map((c, i) => (
        <div className={`club-card cc-${i}`} key={c.id}>
          <div className="cc-sheen" aria-hidden />
          <div className="cc-top">
            <span className="cc-brand">True <span className="it">Carry.</span></span>
            <span className="cc-nfc"><NfcWave /></span>
          </div>
          <div className="cc-club">{c.club}</div>
          <div className="cc-meta">
            <span>Loft <b>{c.loft}</b></span>
            <span>Avg carry <b>{c.carry}y</b></span>
          </div>
          <div className="cc-foot">
            <span>{c.id}</span>
            <span>Tap to tag</span>
          </div>
        </div>
      ))}
    </div>
  );
}
