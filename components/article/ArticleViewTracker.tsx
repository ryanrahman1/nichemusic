"use client";

import { useEffect, useRef } from "react";
import { useSession } from "@/components/providers/SessionProvider";
import { trackArticleEngagement } from "@/lib/editorial/api";

const VIEW_MS = 15_000;
const MIN_SCROLL_PX = 80;
const SID_KEY = "nm.editorial.sid";

function todayKey() {
  return new Date().toISOString().slice(0, 10);
}

function alreadyPinged(articleId: string) {
  try {
    return window.localStorage.getItem(`nm.editorial.view.${articleId}.${todayKey()}`) === "1";
  } catch {
    return false;
  }
}

function markPinged(articleId: string) {
  try {
    window.localStorage.setItem(`nm.editorial.view.${articleId}.${todayKey()}`, "1");
  } catch {
    // private mode whatever
  }
}

function readerSessionId() {
  try {
    const existing = window.localStorage.getItem(SID_KEY);
    if (existing) return existing;
    const next =
      typeof crypto !== "undefined" && "randomUUID" in crypto
        ? crypto.randomUUID()
        : `s_${Date.now()}_${Math.random().toString(36).slice(2)}`;
    window.localStorage.setItem(SID_KEY, next);
    return next;
  } catch {
    return `s_${Date.now()}`;
  }
}

function scrollPct() {
  const max = document.documentElement.scrollHeight - window.innerHeight;
  if (max <= 0) return 0;
  return Math.min(100, Math.max(0, Math.round((window.scrollY / max) * 100)));
}

export function ArticleViewTracker({
  articleId,
  authorProfileIds,
}: {
  articleId: string;
  authorProfileIds: string[];
}) {
  const { status, user } = useSession();
  const sent = useRef(false);

  useEffect(() => {
    if (status === "loading") return;
    // you wrote it, it aint a view. editors still count if theyre not the writer
    if (user && authorProfileIds.includes(user.id)) return;
    if (alreadyPinged(articleId)) return;

    let visibleMs = 0;
    let traveled = 0;
    let maxDepth = 0;
    let lastY = window.scrollY;
    let last = performance.now();
    let timer = 0;

    function maybePing() {
      if (sent.current) return;
      if (visibleMs < VIEW_MS) return;
      // parked on the page with no scroll aint a read
      if (traveled < MIN_SCROLL_PX && maxDepth < 8) return;
      sent.current = true;
      markPinged(articleId);
      const seconds = Math.max(15, Math.round(visibleMs / 1000));
      const depth = Math.max(1, maxDepth);
      void trackArticleEngagement(articleId, {
        sessionId: readerSessionId(),
        referrer: document.referrer ? document.referrer.slice(0, 500) : null,
        engagedSeconds: seconds,
        scrollDepth: depth,
      }).catch(() => {
        sent.current = false;
        try {
          window.localStorage.removeItem(`nm.editorial.view.${articleId}.${todayKey()}`);
        } catch {
          // nah
        }
      });
    }

    function tick() {
      const now = performance.now();
      if (document.visibilityState === "visible") {
        visibleMs += now - last;
      }
      last = now;
      maybePing();
    }

    function onScroll() {
      const y = window.scrollY;
      traveled += Math.abs(y - lastY);
      lastY = y;
      maxDepth = Math.max(maxDepth, scrollPct());
      maybePing();
    }

    function onVis() {
      last = performance.now();
    }

    timer = window.setInterval(tick, 400);
    window.addEventListener("scroll", onScroll, { passive: true });
    document.addEventListener("visibilitychange", onVis);

    return () => {
      window.clearInterval(timer);
      window.removeEventListener("scroll", onScroll);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, [articleId, authorProfileIds, status, user]);

  return null;
}
