import type { ReactNode } from "react";
import Link from "next/link";
import styles from "@/components/status/status.module.css";

export type StatusAction = {
  href: string;
  label: string;
};

export type StatusViewProps = {
  kicker?: string;
  title: string;
  body?: string;
  actions?: StatusAction[];
  tone?: "paper" | "ink";
  compact?: boolean;
};

// one shared empty/error block so the site doesnt look half-built
export function StatusView({
  kicker = "Niche Music",
  title,
  body,
  actions,
  tone = "paper",
  compact = false,
}: StatusViewProps) {
  const className = [
    styles.block,
    tone === "ink" ? styles.ink : "",
    compact ? styles.compact : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <section className={className}>
      <p className={styles.kicker}>{kicker}</p>
      <h1 className={styles.title}>{title}</h1>
      {body ? <p className={styles.body}>{body}</p> : null}
      {actions?.length ? (
        <div className={styles.actions}>
          {actions.map((action) => (
            <Link key={action.href} href={action.href} className={styles.link}>
              {action.label}
            </Link>
          ))}
        </div>
      ) : null}
    </section>
  );
}

export function StatusPage({
  children,
}: {
  children: ReactNode;
}) {
  return (
    <main className={styles.page}>
      {children}
    </main>
  );
}
