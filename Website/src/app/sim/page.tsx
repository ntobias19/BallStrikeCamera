"use client";

import { useEffect, useRef, useState, Suspense } from "react";
import { useSearchParams } from "next/navigation";
import SiteNav from "@/components/SiteNav";
import Link from "next/link";

function SimContent() {
  const searchParams = useSearchParams();
  const urlCode = searchParams.get("code") ?? "";

  const [inputCode, setInputCode] = useState(urlCode);
  const [activeCode, setActiveCode] = useState(urlCode);
  const [launched, setLaunched] = useState(!!urlCode);
  const inputRef = useRef<HTMLInputElement>(null);

  // If the URL already has a code, auto-launch.
  useEffect(() => {
    if (urlCode && urlCode.length === 6) {
      setActiveCode(urlCode);
      setLaunched(true);
    }
  }, [urlCode]);

  function launch(code: string) {
    const trimmed = code.trim();
    if (trimmed.length !== 6 || !/^\d{6}$/.test(trimmed)) return;
    setActiveCode(trimmed);
    setLaunched(true);
    // Push ?code= into the URL so the user can share / bookmark.
    const url = new URL(window.location.href);
    url.searchParams.set("code", trimmed);
    window.history.replaceState({}, "", url.toString());
  }

  if (launched && activeCode) {
    return (
      <div className="sim-fullscreen">
        <iframe
          key={activeCode}
          src={`/sim-app/index.html?code=${activeCode}`}
          className="sim-iframe"
          allow="autoplay; fullscreen"
          title="True Carry Live Sim"
        />
        <button
          className="sim-change-code"
          onClick={() => {
            setLaunched(false);
            setInputCode("");
            setActiveCode("");
            setTimeout(() => inputRef.current?.focus(), 100);
          }}
        >
          ✕ Change Code
        </button>
      </div>
    );
  }

  return (
    <>
      <SiteNav />
      <main className="sim-landing">
        <div className="sim-landing-card">
          <div className="sim-landing-eyebrow">True Carry Live Sim</div>
          <h1 className="sim-landing-title">Stream shots to your browser</h1>
          <p className="sim-landing-desc">
            Open <strong>Sim → Live Sim</strong> in the True Carry iOS app and enter
            the 6-digit code below to see your shots in real-time — no PC, no cables.
          </p>

          <form
            className="sim-code-form"
            onSubmit={(e) => {
              e.preventDefault();
              launch(inputCode);
            }}
          >
            <input
              ref={inputRef}
              className="sim-code-input"
              type="text"
              inputMode="numeric"
              maxLength={6}
              placeholder="000000"
              value={inputCode}
              onChange={(e) => setInputCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
              autoFocus
              autoComplete="off"
            />
            <button
              className="sim-code-btn"
              type="submit"
              disabled={inputCode.length !== 6}
            >
              Open Simulator
            </button>
          </form>

          <p className="sim-landing-hint">
            Don&apos;t have the app? <Link href="/#pricing" className="sim-link">Download True Carry →</Link>
          </p>
        </div>
      </main>

      <style>{`
        .sim-landing {
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 80px 24px 40px;
          background: var(--bg);
        }
        .sim-landing-card {
          max-width: 520px;
          width: 100%;
          text-align: center;
        }
        .sim-landing-eyebrow {
          display: inline-flex;
          align-items: center;
          gap: 12px;
          font-family: var(--r-mono);
          font-size: 11px;
          font-weight: 500;
          letter-spacing: 0.28em;
          text-transform: uppercase;
          color: var(--carry-gold);
          margin-bottom: 20px;
        }
        .sim-landing-eyebrow::before,
        .sim-landing-eyebrow::after {
          content: "";
          width: 26px;
          height: 1px;
          background: var(--carry-gold);
        }
        .sim-landing-title {
          font-family: var(--display);
          font-weight: 400;
          font-size: clamp(2.4rem, 6vw, 3.6rem);
          letter-spacing: -0.03em;
          color: var(--cream);
          margin-bottom: 18px;
          line-height: 1.02;
        }
        .sim-landing-desc {
          font-size: 15.5px;
          color: var(--muted);
          line-height: 1.7;
          margin-bottom: 36px;
        }
        .sim-landing-desc strong { color: var(--cream); }
        .sim-code-form {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 14px;
          margin-bottom: 24px;
        }
        .sim-code-input {
          width: 240px;
          text-align: center;
          font-size: 2.4rem;
          font-weight: 500;
          letter-spacing: 0.22em;
          padding: 16px 8px 16px 16px;
          border-radius: var(--radius);
          border: 1px solid var(--border-strong);
          background: var(--surface);
          color: var(--cream);
          outline: none;
          font-family: var(--r-mono);
          transition: border-color 0.2s;
        }
        .sim-code-input:focus { border-color: var(--text); }
        .sim-code-input::placeholder { color: var(--faint); }
        .sim-code-btn {
          width: 240px;
          padding: 15px 32px;
          border-radius: 999px;
          border: 1px solid var(--bone);
          background: var(--bone);
          color: var(--ink);
          font-family: var(--r-mono);
          font-size: 12px;
          font-weight: 700;
          letter-spacing: 0.2em;
          text-transform: uppercase;
          cursor: pointer;
          transition: background 0.2s, border-color 0.2s, opacity 0.2s;
        }
        .sim-code-btn:hover:not(:disabled) { background: var(--carry-gold); border-color: var(--carry-gold); }
        .sim-code-btn:disabled { opacity: 0.35; cursor: default; }
        .sim-landing-hint { font-size: 13px; color: var(--faint); }
        .sim-link { color: var(--carry-gold); text-decoration: none; }
        .sim-link:hover { color: var(--bone); }

        /* Fullscreen iframe mode */
        .sim-fullscreen {
          position: fixed;
          inset: 0;
          background: var(--forest-darker);
          z-index: 1000;
        }
        .sim-iframe {
          width: 100%;
          height: 100%;
          border: none;
          display: block;
        }
        .sim-change-code {
          position: fixed;
          bottom: 16px;
          left: 50%;
          transform: translateX(-50%);
          z-index: 1001;
          padding: 9px 18px;
          border-radius: 999px;
          border: 1px solid rgba(236, 228, 210, 0.22);
          background: rgba(14, 20, 15, 0.65);
          color: rgba(236, 228, 210, 0.66);
          font-family: var(--r-mono);
          font-size: 11px;
          font-weight: 500;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          cursor: pointer;
          backdrop-filter: blur(8px);
          transition: color 0.15s, border-color 0.15s;
        }
        .sim-change-code:hover { color: var(--bone); border-color: rgba(236, 228, 210, 0.45); }
      `}</style>
    </>
  );
}

export default function SimPage() {
  return (
    <Suspense>
      <SimContent />
    </Suspense>
  );
}
