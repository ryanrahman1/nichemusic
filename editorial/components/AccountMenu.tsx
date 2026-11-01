"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { useSession } from "@/components/providers/SessionProvider";

// square avatar trigger + hairline menu
export function AccountMenu() {
  const { user, logout } = useSession();
  const [open, setOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  const src = user?.avatarUrl;
  const initial = (user?.email?.[0] || "?").toUpperCase();

  useEffect(() => {
    if (!open) return;

    function onPointer(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) setOpen(false);
    }

    function onKey(e: KeyboardEvent) {
      if (e.key === "Escape") setOpen(false);
    }

    document.addEventListener("mousedown", onPointer);
    document.addEventListener("keydown", onKey);
    return () => {
      document.removeEventListener("mousedown", onPointer);
      document.removeEventListener("keydown", onKey);
    };
  }, [open]);

  async function onLogout() {
    setBusy(true);
    try {
      await logout();
    } finally {
      setBusy(false);
      setOpen(false);
    }
  }

  return (
    <div className="account-menu" ref={rootRef}>
      <button
        type="button"
        className="account-menu__trigger"
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Account menu"
        onClick={() => setOpen((v) => !v)}
      >
        {src ? (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt="" className="account-menu__avatar" />
        ) : (
          <span className="account-menu__fallback">{initial}</span>
        )}
      </button>

      {open && (
        <div className="account-menu__panel" role="menu">
          {user?.email && (
            <p className="account-menu__email">{user.email}</p>
          )}

          <Link
            href="/profile"
            role="menuitem"
            className="account-menu__logout underline-link"
            onClick={() => setOpen(false)}
          >
            Profile
          </Link>

          <Link
            href="/write"
            role="menuitem"
            className="account-menu__logout underline-link"
            onClick={() => setOpen(false)}
          >
            Write an article
          </Link>

          <button
            type="button"
            role="menuitem"
            className="account-menu__logout underline-link"
            disabled={busy}
            onClick={() => void onLogout()}
          >
            {busy ? "Logging out…" : "Log out"}
          </button>
        </div>
      )}
    </div>
  );
}
