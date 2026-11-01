"use client";

import Image from "next/image";
import Link from "next/link";
import { useEffect, useState } from "react";
import { AccountMenu } from "@/components/AccountMenu";
import { useSession } from "@/components/providers/SessionProvider";

const navLinks = [
  { href: "/reviews", label: "Reviews" },
  { href: "/spotlights", label: "Spotlights" },
  { href: "/news", label: "News" },
];

export function Navbar() {
  const { user } = useSession();
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    // flip to glass once the hero starts sliding under
    const onScroll = () => setScrolled(window.scrollY > 16);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <>
      <div
        className={
          scrolled
            ? "site-header-glass site-header-glass--on backdrop-blur-xl"
            : "site-header-glass"
        }
        aria-hidden
      />
    <header className={scrolled ? "site-header site-header--scrolled" : "site-header"}>
      <nav className="site-header__nav" aria-label="Main navigation">
        <Link href="/" className="site-header__brand">
          <Image
            src="/favicon.png"
            alt=""
            width={32}
            height={32}
            className="site-header__mark"
            priority
          />
          <span className="wordmark">
            niche music<span className="wordmark-dot">.</span>
          </span>
        </Link>

        <div className="site-header__end">
          <ul className="site-header__links">
            {navLinks.map((link) => (
              <li key={link.href}>
                <Link href={link.href} className="underline-link">
                  {link.label}
                </Link>
              </li>
            ))}
            <li>
              <Link href="/download" className="cta-download">
                Download
              </Link>
            </li>
          </ul>

          <Link href="/search" className="site-header__search-icon" aria-label="Search">
            <SearchIcon />
          </Link>

          {user ? <AccountMenu /> : null}
        </div>
      </nav>
    </header>
    </>
  );
}

function SearchIcon() {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.75"
      aria-hidden="true"
    >
      <circle cx="11" cy="11" r="6.5" />
      <path d="M16 16l5 5" />
    </svg>
  );
}

