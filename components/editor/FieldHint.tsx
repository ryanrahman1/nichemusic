"use client";

import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { createPortal } from "react-dom";
import { FIELD_HELP, type HelpId } from "@/components/editor/fieldHelp";
import styles from "./cms.module.css";

const HELP_OPEN = "niche-help-open";

export function FieldHint({
  id,
  children,
}: {
  id: HelpId;
  children?: ReactNode;
}) {
  const help = FIELD_HELP[id];
  return (
    <span className={styles.fieldHead}>
      <span>{children ?? help.label}</span>
      <HelpButton id={id} />
    </span>
  );
}

export function HelpButton({ id }: { id: HelpId }) {
  const help = FIELD_HELP[id];
  const titleId = useId();
  const btnRef = useRef<HTMLButtonElement>(null);
  const panelRef = useRef<HTMLDivElement>(null);
  const [open, setOpen] = useState(false);
  const [mounted, setMounted] = useState(false);
  const [sheet, setSheet] = useState(false);
  const [coords, setCoords] = useState({ top: 0, left: 0 });

  useEffect(() => {
    setMounted(true);
  }, []);

  // only one hint at a time so they dont stack
  useEffect(() => {
    function onOther(e: Event) {
      if ((e as CustomEvent<string>).detail !== id) setOpen(false);
    }
    window.addEventListener(HELP_OPEN, onOther);
    return () => window.removeEventListener(HELP_OPEN, onOther);
  }, [id]);

  useEffect(() => {
    if (!open) return;
    window.dispatchEvent(new CustomEvent(HELP_OPEN, { detail: id }));
  }, [open, id]);

  useEffect(() => {
    if (!open) return;

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    function onPointer(e: PointerEvent) {
      const t = e.target as Node;
      if (btnRef.current?.contains(t) || panelRef.current?.contains(t)) return;
      setOpen(false);
    }

    document.addEventListener("keydown", onKey);
    document.addEventListener("pointerdown", onPointer);
    return () => {
      document.removeEventListener("keydown", onKey);
      document.removeEventListener("pointerdown", onPointer);
    };
  }, [open]);

  useLayoutEffect(() => {
    if (!open) return;

    function place() {
      const btn = btnRef.current;
      const panel = panelRef.current;
      if (!btn || !panel) return;

      const a = btn.getBoundingClientRect();
      const vw = window.innerWidth;
      const vh = window.innerHeight;
      const width = Math.min(320, vw - 16);
      const height = panel.offsetHeight || 140;
      const gap = 8;
      const pad = 8;

      const roomRight = vw - a.right - gap - pad;
      const roomLeft = a.left - gap - pad;
      const roomBelow = vh - a.bottom - gap - pad;
      const roomAbove = a.top - gap - pad;
      const needsSheet =
        vw < 560 ||
        (roomRight < width && roomLeft < width && roomBelow < height && roomAbove < height);

      if (needsSheet) {
        setSheet(true);
        return;
      }

      setSheet(false);
      let left = a.right + gap;
      if (roomRight < width && roomLeft >= width) left = a.left - width - gap;
      if (left + width > vw - pad) left = vw - width - pad;
      if (left < pad) left = pad;

      let top = a.top;
      if (top + height > vh - pad) top = Math.max(pad, vh - height - pad);
      setCoords({ top, left });
    }

    place();
    window.addEventListener("resize", place);
    window.addEventListener("scroll", place, true);
    return () => {
      window.removeEventListener("resize", place);
      window.removeEventListener("scroll", place, true);
    };
  }, [open]);

  function toggle() {
    setOpen((was) => !was);
  }

  const layer =
    mounted && open
      ? createPortal(
          sheet ? (
            <div className={styles.helpSheetRoot} role="presentation">
              <div
                ref={panelRef}
                className={styles.helpSheet}
                role="dialog"
                aria-modal="true"
                aria-labelledby={titleId}
              >
                <h2 id={titleId}>{help.label}</h2>
                <p>{help.body}</p>
              </div>
            </div>
          ) : (
            <div
              ref={panelRef}
              className={styles.helpPop}
              style={{ top: coords.top, left: coords.left }}
              role="dialog"
              aria-modal="false"
              aria-labelledby={titleId}
            >
              <h2 id={titleId}>{help.label}</h2>
              <p>{help.body}</p>
            </div>
          ),
          document.body,
        )
      : null;

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        className={styles.infoBtn}
        aria-label={`About ${help.label}`}
        aria-expanded={open}
        onClick={(e) => {
          e.preventDefault();
          e.stopPropagation();
          toggle();
        }}
      >
        i
      </button>
      {layer}
    </>
  );
}
