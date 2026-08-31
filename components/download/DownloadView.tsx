"use client";

import { useSyncExternalStore } from "react";
import styles from "./download.module.css";

type Platform = "ios" | "macos" | "windows" | "web";

const PLATFORMS: {
  id: Platform;
  name: string;
  version: string;
  blurb: string;
  href: string;
  action: string;
}[] = [
  {
    id: "ios",
    name: "iOS",
    version: "v2",
    blurb: "iPhone and iPad. Available on the App Store.",
    href: "https://apps.apple.com/app/id6758951039",
    action: "App Store",
  },
  {
    id: "macos",
    name: "macOS",
    version: "v1",
    blurb: "Native desktop app for Mac.",
    href: "https://downloads.nichemusic.app/NicheMusic-macOS.dmg",
    action: "Download",
  },
  {
    id: "windows",
    name: "Windows",
    version: "v1",
    blurb: "Native desktop app for PC.",
    href: "https://downloads.nichemusic.app/NicheMusic-Windows.exe",
    action: "Download",
  },
  {
    id: "web",
    name: "Web",
    version: "v1",
    blurb: "Use Niche Music directly in your browser.",
    href: "https://open.nichemusic.app",
    action: "Open app",
  },
];

const LABELS: Record<Platform, string> = {
  ios: "iOS",
  macos: "macOS",
  windows: "Windows",
  web: "Web",
};

function detectPlatform(): Platform {
  // sniff the visitor so we can shove their platform up top
  const ua = navigator.userAgent;
  const platform = navigator.platform || "";

  if (/iPhone|iPad|iPod/.test(ua) || (platform === "MacIntel" && navigator.maxTouchPoints > 1)) {
    return "ios";
  }
  if (/Mac/.test(platform) || /Macintosh/.test(ua)) return "macos";
  if (/Win/.test(platform) || /Windows/.test(ua)) return "windows";
  return "web";
}

function subscribePlatform() {
  // platform doesnt change mid-visit
  return () => {};
}

function getServerPlatform(): Platform | null {
  return null;
}

function PlatformIcon({ id }: { id: Platform }) {
  if (id === "windows") {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img src="/assets/images/windows-8.png" alt="" />
    );
  }
  if (id === "web") {
    return (
      <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5">
        <circle cx="12" cy="12" r="9" />
        <path d="M3 12h18M12 3a15 15 0 0 1 0 18M12 3a15 15 0 0 0 0 18" />
      </svg>
    );
  }
  return (
    <svg viewBox="0 0 24 24" fill="currentColor">
      <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.8-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
    </svg>
  );
}

function PlatformCard({
  platform,
  featured,
}: {
  platform: (typeof PLATFORMS)[number];
  featured?: boolean;
}) {
  const Title = featured ? "h2" : "h3";
  return (
    <a
      className={featured ? `${styles.card} ${styles.featuredCard}` : styles.card}
      href={platform.href}
    >
      <span className={styles.icon} aria-hidden="true">
        <PlatformIcon id={platform.id} />
      </span>
      <div className={styles.info}>
        <Title>
          {platform.name}
          <span className={styles.version}> | {platform.version} |</span>
        </Title>
        <p>{platform.blurb}</p>
      </div>
      <span className={styles.action}>{platform.action}</span>
    </a>
  );
}

export function DownloadView() {
  const detected = useSyncExternalStore(subscribePlatform, detectPlatform, getServerPlatform);

  const featured = detected ? PLATFORMS.find((row) => row.id === detected) : null;
  const others = detected ? PLATFORMS.filter((row) => row.id !== detected) : [];

  return (
    <>
      <section className={styles.hero}>
        <p className={styles.kicker}>Get Niche Music</p>
        <h1>
          Available on every platform<span className={styles.dot}>.</span>
        </h1>
        <p className={styles.heroSub}>
          Discover underground artists wherever you listen — on your phone, desktop, or in the browser.
        </p>
      </section>

      <section className={styles.featured}>
        {featured ? (
          <>
            <p className={styles.kicker}>Recommended for {LABELS[featured.id]}</p>
            <PlatformCard platform={featured} featured />
          </>
        ) : (
          <p className={styles.loading}>Loading your platform…</p>
        )}
      </section>

      {others.length > 0 && (
        <section className={styles.others}>
          <h2>All platforms</h2>
          <div className={styles.list}>
            {others.map((row) => (
              <PlatformCard key={row.id} platform={row} />
            ))}
          </div>
        </section>
      )}

    </>
  );
}
