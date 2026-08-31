"use client";

import { useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import Link from "next/link";
import styles from "./cms.module.css";

export function StandardsGate({
  action,
  busy,
  agreed,
  onAgreed,
  onCancel,
  onConfirm,
}: {
  action: "submit" | "publish";
  busy: boolean;
  agreed: boolean;
  onAgreed: (value: boolean) => void;
  onCancel: () => void;
  onConfirm: () => void;
}) {
  const titleId = useId();
  const boxRef = useRef<HTMLInputElement>(null);
  const confirmLabel = action === "publish" ? "Publish" : "Submit";

  useEffect(() => {
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    boxRef.current?.focus();

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape" && !busy) onCancel();
    }

    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      document.removeEventListener("keydown", onKey);
    };
  }, [busy, onCancel]);

  if (typeof document === "undefined") return null;

  return createPortal(
    <div
      className={styles.gateRoot}
      role="presentation"
      onMouseDown={(e) => {
        if (e.target === e.currentTarget && !busy) onCancel();
      }}
    >
      <div className={styles.gateCard} role="dialog" aria-modal="true" aria-labelledby={titleId}>
        <p className={styles.gateKicker}>Before it goes out</p>
        <h2 id={titleId}>This piece has to abide.</h2>
        <p className={styles.gateCopy}>
          Submit and publish only if it follows Niche&apos;s{" "}
          <Link href="/standards" target="_blank" rel="noopener noreferrer">
            Editorial Standards
          </Link>{" "}
          and{" "}
          <Link href="/guidelines" target="_blank" rel="noopener noreferrer">
            Community Guidelines
          </Link>
          .
        </p>
        <label className={styles.gateCheck}>
          <input
            ref={boxRef}
            type="checkbox"
            checked={agreed}
            onChange={(e) => onAgreed(e.target.checked)}
          />
          <span>I confirm this piece follows both.</span>
        </label>
        <div className={styles.gateActions}>
          <button type="button" className={styles.secondary} disabled={busy} onClick={onCancel}>
            Cancel
          </button>
          <button
            type="button"
            className={styles.primary}
            disabled={busy || !agreed}
            onClick={onConfirm}
          >
            {busy ? "Working…" : confirmLabel}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
