"use client";

import { useEffect } from "react";

// kill page bounce so the desk stays in its own panes
export function WriteLock() {
  useEffect(() => {
    const html = document.documentElement;
    html.classList.add("write-lock");
    return () => html.classList.remove("write-lock");
  }, []);

  return null;
}
