import Image from "next/image";
import Link from "next/link";
import { siteConfig } from "@/lib/site";
import styles from "./site-footer.module.css";

const nicheLinks = [
  { href: "/download", label: "Download Niche" },
  { href: "/news", label: "News / Editorial" },
  { href: "/write", label: "Become a Writer" },
  { href: "/about", label: "About Niche" },
  { href: "https://open.nichemusic.app", label: "Open Niche", external: true },
] as const;

const legalLinks = [
  { href: "/terms", label: "Terms of Service" },
  { href: "/privacy", label: "Privacy Policy" },
  { href: "/eula", label: "EULA" },
  { href: "/artist-agreement", label: "Artist Agreement" },
  { href: "/guidelines", label: "Community Guidelines" },
] as const;

const connectLinks = [
  {
    href: "https://instagram.com/nichemusicapp",
    label: "Instagram",
    external: true,
  },
  {
    href: "https://www.tiktok.com/@nichemusicapp",
    label: "TikTok",
    external: true,
  },
  { href: "mailto:hello@nichemusic.app", label: "Contact" },
  { href: "mailto:hello@nichemusic.app", label: "Support" },
  { href: "mailto:hello@nichemusic.app?subject=Artist%20%2F%20Press%20Inquiries", label: "Artist / Press Inquiries" },
] as const;

type FooterLink = {
  href: string;
  label: string;
  external?: boolean;
};

function FooterNavLink({ href, label, external }: FooterLink) {
  if (external || href.startsWith("mailto:")) {
    return (
      <a
        href={href}
        className={styles.link}
        {...(external
          ? { target: "_blank", rel: "noopener noreferrer" }
          : {})}
      >
        {label}
      </a>
    );
  }

  return (
    <Link href={href} className={styles.link}>
      {label}
    </Link>
  );
}

function FooterColumn({
  title,
  links,
}: {
  title: string;
  links: readonly FooterLink[];
}) {
  return (
    <nav className={styles.col} aria-label={title}>
      <p className={styles.colTitle}>{title}</p>
      <ul className={styles.list}>
        {links.map((link) => (
          <li key={`${title}-${link.label}`}>
            <FooterNavLink {...link} />
          </li>
        ))}
      </ul>
    </nav>
  );
}

export function SiteFooter() {
  return (
    <footer className={styles.footer}>
      <div className={styles.inner}>
        <div className={styles.brand}>
          <Link href="/" className={styles.brandLink}>
            <Image
              src="/favicon.png"
              alt=""
              width={32}
              height={32}
              className={styles.mark}
            />
            <span className="wordmark">
              niche music<span className="wordmark-dot">.</span>
            </span>
          </Link>
          <p className={styles.blurb}>{siteConfig.editorialDescription}</p>
        </div>

        <div className={styles.cols}>
          <FooterColumn title="Niche" links={nicheLinks} />
          <FooterColumn title="Legal" links={legalLinks} />
          <FooterColumn title="Connect" links={connectLinks} />
        </div>

        <p className={styles.copy}>© 2026 {siteConfig.author}</p>
      </div>
    </footer>
  );
}
