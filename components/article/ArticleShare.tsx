"use client";

import { useState } from "react";
import styles from "@/components/article/article.module.css";

export function ArticleShare({
  title,
  path,
}: {
  title: string;
  path: string;
}) {
  const [copied, setCopied] = useState(false);
  const canNative =
    typeof navigator !== "undefined" && typeof navigator.share === "function";

  function url() {
    if (typeof window === "undefined") return path;
    return `${window.location.origin}${path}`;
  }

  async function copyLink() {
    try {
      await navigator.clipboard.writeText(url());
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  async function nativeShare() {
    try {
      await navigator.share({ title, url: url() });
    } catch {
      // they cancelled, chill
    }
  }

  return (
    <div className={styles.share}>
      <p className={styles.kicker}>Share</p>
      <div className={styles.shareRow}>
        <button type="button" className={styles.shareBtn} onClick={() => void copyLink()}>
          {copied ? "Copied" : "Copy link"}
        </button>
        {canNative ? (
          <button type="button" className={styles.shareBtn} onClick={() => void nativeShare()}>
            Share
          </button>
        ) : null}
      </div>
    </div>
  );
}
