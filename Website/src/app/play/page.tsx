"use client";

import { Suspense } from "react";
import { useSearchParams } from "next/navigation";

function PlaySim() {
  const params = useSearchParams();
  const code = params.get("code");
  const src = code ? `/sim/index.html?code=${code}` : "/sim/index.html";

  return (
    <div className="sim-host">
      <div className="sim-bar">
        <a className="sim-back" href="/">
          ← True <span className="it">Carry.</span>
        </a>
        <span className="sim-title">The Sim · Pine Hollow National</span>
        <a className="sim-full" href={src} target="_blank" rel="noreferrer">
          Full screen ↗
        </a>
      </div>
      <iframe
        className="sim-frame"
        src={src}
        title="True Carry Sim — Pine Hollow National"
        allow="autoplay; fullscreen"
      />
    </div>
  );
}

export default function PlayPage() {
  return (
    <Suspense>
      <PlaySim />
    </Suspense>
  );
}
