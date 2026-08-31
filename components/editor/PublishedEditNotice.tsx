"use client";

import { useEffect, useId, useRef } from "react";
import { createPortal } from "react-dom";
import styles from "./cms.module.css";

export type PublishedEditNoticeMode = "warning" | "unpublished";

// keep the published edit warning in the same modal lane as standards
export function PublishedEditNotice({
  mode,
  onDismiss,
}: {
  mode: PublishedEditNoticeMode;
  onDismiss: () => void;
}) {
  const titleId = useId();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const warning = mode === "warning";

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    buttonRef.current?.focus();

    function onKey(event: KeyboardEvent) {
      if (event.key === "Escape") onDismiss();
    }

    document.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = previousOverflow;
      document.removeEventListener("keydown", onKey);
    };
  }, [onDismiss]);

  if (typeof document === "undefined") return null;

  return createPortal(
    <div
      className={styles.gateRoot}
      role="presentation"
      onMouseDown={(event) => {
        if (event.target === event.currentTarget) onDismiss();
      }}
    >
      <div className={styles.gateCard} role="alertdialog" aria-modal="true" aria-labelledby={titleId}>
        <p className={styles.gateKicker}>
          {warning ? "Published piece" : "Changes saved"}
        </p>
        <h2 id={titleId}>
          {warning ? "Editing this takes it back through review." : "This piece is unpublished."}
        </h2>
        <p className={styles.gateCopy}>
          {warning
            ? "Any edit will take the published version offline when you save. It will need review and approval again before it can be published."
            : "Your changes are saved, but the published version is now offline. The author needs to submit it for review and approval, then republish it before it can go live again."}
        </p>
        <div className={styles.gateActions}>
          <button
            ref={buttonRef}
            type="button"
            className={styles.primary}
            onClick={onDismiss}
          >
            {warning ? "I understand" : "Got it"}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  );
}
