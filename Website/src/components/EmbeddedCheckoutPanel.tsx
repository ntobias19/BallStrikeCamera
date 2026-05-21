"use client";

import { EmbeddedCheckout, EmbeddedCheckoutProvider } from "@stripe/react-stripe-js";
import { loadStripe } from "@stripe/stripe-js";
import { useCallback, useEffect, useMemo, useState } from "react";

const publishableKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;
const stripePromise = publishableKey ? loadStripe(publishableKey) : null;

interface EmbeddedCheckoutPanelProps {
  accessToken: string;
  checkoutUrl: string;
  onClose: () => void;
}

export default function EmbeddedCheckoutPanel({ accessToken, checkoutUrl, onClose }: EmbeddedCheckoutPanelProps) {
  const [clientSecret, setClientSecret] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [complete, setComplete] = useState(false);
  const [requestId, setRequestId] = useState(0);

  const createCheckoutSession = useCallback(async () => {
    if (!publishableKey) {
      throw new Error("Stripe publishable key is not configured.");
    }
    if (!checkoutUrl) {
      throw new Error("Checkout function URL is not configured.");
    }

    const res = await fetch(checkoutUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({
        tier: "premium",
        billingInterval: "monthly",
        uiMode: "embedded",
      }),
    });

    const json = await res.json().catch(() => ({}));
    if (!res.ok) {
      const message = json.error ?? "Checkout failed. Please try again.";
      throw new Error(res.status === 401 ? "Please sign in again before starting checkout." : message);
    }
    if (!json.clientSecret) throw new Error("Checkout did not return a client secret.");
    return json.clientSecret as string;
  }, [accessToken, checkoutUrl]);

  useEffect(() => {
    let cancelled = false;

    async function loadCheckout() {
      setError(null);
      setClientSecret(null);
      setComplete(false);
      try {
        const secret = await createCheckoutSession();
        if (!cancelled) setClientSecret(secret);
      } catch (err) {
        if (!cancelled) {
          setError(err instanceof Error ? err.message : "Checkout failed. Please try again.");
        }
      }
    }

    void loadCheckout();
    return () => {
      cancelled = true;
    };
  }, [createCheckoutSession, requestId]);

  const options = useMemo(() => ({
    clientSecret,
    onComplete: () => setComplete(true),
  }), [clientSecret]);

  return (
    <div className="checkout-overlay" role="dialog" aria-modal="true" aria-label="True Carry checkout">
      <button className="checkout-scrim" type="button" onClick={onClose} aria-label="Close checkout" />
      <div className="checkout-shell">
        <div className="checkout-head">
          <div>
            <span className="badge">Secure checkout</span>
            <h2>Upgrade without leaving True Carry.</h2>
          </div>
          <button className="checkout-close" type="button" onClick={onClose} aria-label="Close checkout">
            Close
          </button>
        </div>

        {complete ? (
          <div className="checkout-config">
            <h3>You&apos;re all set.</h3>
            <p>
              Stripe confirmed checkout inside True Carry. Your premium access will appear after the webhook finishes
              syncing your subscription.
            </p>
            <button className="checkout-retry" type="button" onClick={onClose}>
              Close
            </button>
          </div>
        ) : error ? (
          <div className="checkout-config checkout-error">
            <h3>Checkout needs attention.</h3>
            <p>{error}</p>
            <button className="checkout-retry" type="button" onClick={() => setRequestId((current) => current + 1)}>
              Try again
            </button>
          </div>
        ) : !stripePromise ? (
          <div className="checkout-config">
            <h3>Stripe needs one public setting.</h3>
            <p>
              Add <code>NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY</code> in Vercel and locally to enable embedded checkout.
              Card details will still be handled by Stripe, not by True Carry servers.
            </p>
          </div>
        ) : clientSecret ? (
          <EmbeddedCheckoutProvider stripe={stripePromise} options={options}>
            <EmbeddedCheckout />
          </EmbeddedCheckoutProvider>
        ) : (
          <div className="checkout-config">
            <h3>Preparing secure checkout...</h3>
            <p>Creating your Stripe checkout session inside True Carry.</p>
          </div>
        )}
      </div>
    </div>
  );
}
