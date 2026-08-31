"use client";

import {
  useCallback,
  useEffect,
  useState,
  useSyncExternalStore,
  type CSSProperties,
  type PointerEvent as ReactPointerEvent,
  type RefObject,
} from "react";

const LS_KEY = "niche-editor-layout";
const SIDE_MIN = 220;
const SIDE_MAX = 480;
const SIDE_DEFAULT = 300;
const WIDGET_MIN = 220;
const WIDGET_MAX = 440;
const WIDGET_DEFAULT = 280;
const MAIN_MIN = 380;
const DEFAULT_LAYOUT = { side: SIDE_DEFAULT, widget: WIDGET_DEFAULT };

function clamp(n: number, min: number, max: number) {
  return Math.min(max, Math.max(min, n));
}

function readLayout() {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return DEFAULT_LAYOUT;
    const parsed = JSON.parse(raw) as { side?: unknown; widget?: unknown };
    return {
      side: clamp(Number(parsed.side) || SIDE_DEFAULT, SIDE_MIN, SIDE_MAX),
      widget: clamp(Number(parsed.widget) || WIDGET_DEFAULT, WIDGET_MIN, WIDGET_MAX),
    };
  } catch {
    return DEFAULT_LAYOUT;
  }
}

let layoutSnap = DEFAULT_LAYOUT;

function getLayoutSnapshot() {
  // reuse the obj if widths didnt move so useSyncExternalStore chills
  const next = readLayout();
  if (next.side === layoutSnap.side && next.widget === layoutSnap.widget) {
    return layoutSnap;
  }
  layoutSnap = next;
  return layoutSnap;
}

function getServerLayoutSnapshot() {
  return DEFAULT_LAYOUT;
}

function subscribeLayout() {
  // we only need the first client read, drag state lives in react
  return () => {};
}

// remember the desk widths so writers dont reset every session
export function useEditorLayout(
  hasWidget: boolean,
  shellRef: RefObject<HTMLDivElement | null>,
) {
  const persisted = useSyncExternalStore(
    subscribeLayout,
    getLayoutSnapshot,
    getServerLayoutSnapshot,
  );
  const [override, setOverride] = useState<{ side: number; widget: number } | null>(null);
  const [dragging, setDragging] = useState<"side" | "widget" | null>(null);
  const side = override?.side ?? persisted.side;
  const widget = override?.widget ?? persisted.widget;

  useEffect(() => {
    if (!override) return;
    localStorage.setItem(LS_KEY, JSON.stringify(override));
  }, [override]);

  const drag = useCallback(
    (which: "side" | "widget", e: ReactPointerEvent<HTMLButtonElement>) => {
      e.preventDefault();
      const startX = e.clientX;
      const startSide = side;
      const startWidget = widget;
      const total = shellRef.current?.clientWidth ?? 1200;
      const widgetW = hasWidget ? startWidget : 0;

      setDragging(which);
      document.body.style.cursor = "col-resize";
      document.body.style.userSelect = "none";

      function onMove(ev: PointerEvent) {
        const dx = ev.clientX - startX;
        if (which === "side") {
          const max = Math.min(SIDE_MAX, total - widgetW - MAIN_MIN);
          setOverride({
            side: clamp(startSide + dx, SIDE_MIN, Math.max(SIDE_MIN, max)),
            widget: startWidget,
          });
          return;
        }
        const max = Math.min(WIDGET_MAX, total - startSide - MAIN_MIN);
        setOverride({
          side: startSide,
          widget: clamp(startWidget - dx, WIDGET_MIN, Math.max(WIDGET_MIN, max)),
        });
      }

      function onUp() {
        setDragging(null);
        document.body.style.cursor = "";
        document.body.style.userSelect = "";
        window.removeEventListener("pointermove", onMove);
        window.removeEventListener("pointerup", onUp);
      }

      window.addEventListener("pointermove", onMove);
      window.addEventListener("pointerup", onUp);
    },
    [hasWidget, shellRef, side, widget],
  );

  return {
    side,
    widget,
    dragging,
    vars: {
      "--editor-side": `${side}px`,
      "--editor-widget": `${widget}px`,
    } as CSSProperties,
    dragSide: (e: ReactPointerEvent<HTMLButtonElement>) => drag("side", e),
    dragWidget: (e: ReactPointerEvent<HTMLButtonElement>) => drag("widget", e),
  };
}
