"use client";

import { useEffect, useState, type ReactNode } from "react";
import styles from "@/components/editor/write-home.module.css";

const PREFIX = "nm.desk.fold.";

function readOpen(id: string, fallback: boolean) {
  try {
    const raw = window.localStorage.getItem(PREFIX + id);
    if (raw === "0") return false;
    if (raw === "1") return true;
  } catch {
    // private mode chill
  }
  return fallback;
}

export function DeskFold({
  id,
  title,
  meta,
  children,
  defaultOpen = true,
}: {
  id: string;
  title: string;
  meta?: ReactNode;
  children: ReactNode;
  defaultOpen?: boolean;
}) {
  const [open, setOpen] = useState(defaultOpen);

  useEffect(() => {
    setOpen(readOpen(id, defaultOpen));
  }, [id, defaultOpen]);

  function toggle() {
    setOpen((on) => {
      const next = !on;
      try {
        window.localStorage.setItem(PREFIX + id, next ? "1" : "0");
      } catch {
        // whatever
      }
      return next;
    });
  }

  return (
    <section className={open ? styles.section : `${styles.section} ${styles.sectionFolded}`}>
      <button
        type="button"
        className={open ? styles.foldHead : `${styles.foldHead} ${styles.foldHeadClosed}`}
        aria-expanded={open}
        onClick={toggle}
      >
        <span className={styles.foldTitle}>
          <h2>{title}</h2>
          <span className={styles.foldMark} aria-hidden>
            {open ? "–" : "+"}
          </span>
        </span>
        {meta ? <span className={styles.foldMeta}>{meta}</span> : null}
      </button>
      {open ? children : null}
    </section>
  );
}
