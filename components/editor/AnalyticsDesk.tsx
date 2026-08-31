"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { getDeskAnalytics, getWriterAnalytics } from "@/lib/editorial/api";
import { articleHref } from "@/lib/editorial/cms";
import type {
  AnalyticsArticle,
  DeskAnalytics,
  WriterAnalytics,
} from "@/lib/editorial/types";
import { StatusView } from "@/components/status/StatusView";
import { DeskFold } from "@/components/editor/DeskFold";
import styles from "@/components/editor/write-home.module.css";

const WINDOWS = [7, 30, 90] as const;

function pretty(n: number) {
  return new Intl.NumberFormat("en-US").format(n);
}

function pieceHref(row: AnalyticsArticle) {
  if (row.status === "published" && row.type && row.slug) {
    return articleHref({ type: row.type, slug: row.slug });
  }
  return `/write/${row.id}`;
}

export function AnalyticsDesk({ canReview }: { canReview: boolean }) {
  const [days, setDays] = useState<(typeof WINDOWS)[number]>(30);
  const [mine, setMine] = useState<WriterAnalytics | null>(null);
  const [desk, setDesk] = useState<DeskAnalytics | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let live = true;
    setError(null);
    void (async () => {
      try {
        const [writer, site] = await Promise.all([
          getWriterAnalytics(days),
          canReview ? getDeskAnalytics(days) : Promise.resolve(null),
        ]);
        if (!live) return;
        setMine(writer);
        setDesk(site);
      } catch (err) {
        if (!live) return;
        setError(err instanceof Error ? err.message : "Couldnt load analytics");
      }
    })();
    return () => {
      live = false;
    };
  }, [days, canReview]);

  return (
    <DeskFold id="analytics" title="Analytics">
      <div className={styles.daySwitch}>
        {WINDOWS.map((n) => (
          <button
            key={n}
            type="button"
            className={days === n ? styles.dayOn : styles.dayOff}
            onClick={() => setDays(n)}
          >
            {n}d
          </button>
        ))}
      </div>
      <p className={styles.nmfLede}>
        A view is 15 seconds plus some scroll. Sitting still doesn&apos;t count. Your own bylines don&apos;t either. Editors still do.
      </p>

      {error ? (
        <StatusView compact kicker="Analytics" title="Couldn’t load stats." body={error} />
      ) : null}

      {mine ? (
        <>
          <p className={styles.statKicker}>Your pieces</p>
          <StatRow totals={mine.totals} />
          {mine.articles.length > 0 ? (
            <ol className={styles.rankList}>
              {mine.articles.slice(0, 12).map((row) => (
                <RankRow key={row.id} row={row} />
              ))}
            </ol>
          ) : (
            <StatusView
              compact
              kicker="Your pieces"
              title="No view data yet."
              body="Once people sit with a published piece for 15 seconds and actually scroll, it’ll show up here."
            />
          )}
        </>
      ) : !error ? (
        <p className={styles.mutedInline}>Loading stats…</p>
      ) : null}

      {canReview && desk ? (
        <>
          <p className={`${styles.statKicker} ${styles.statKickerGap}`}>Site</p>
          <StatRow totals={desk.totals} />
          {desk.popular.length > 0 ? (
            <ol className={styles.rankList}>
              {desk.popular.map((row) => (
                <RankRow key={row.id} row={row} />
              ))}
            </ol>
          ) : (
            <StatusView
              compact
              kicker="Popular"
              title="Nothing’s bubbling yet."
              body="Published pieces pick up views after 15 seconds and some scroll."
            />
          )}
        </>
      ) : null}
    </DeskFold>
  );
}

function StatRow({
  totals,
}: {
  totals: WriterAnalytics["totals"];
}) {
  return (
    <div className={styles.statGrid}>
      <div className={styles.statBox}>
        <p className={styles.statLabel}>Views</p>
        <p className={styles.statNum}>{pretty(totals.pageViews)}</p>
      </div>
      <div className={styles.statBox}>
        <p className={styles.statLabel}>Readers</p>
        <p className={styles.statNum}>{pretty(totals.uniqueReaders)}</p>
      </div>
      <div className={styles.statBox}>
        <p className={styles.statLabel}>Reads</p>
        <p className={styles.statNum}>{pretty(totals.qualifiedReads)}</p>
      </div>
    </div>
  );
}

function RankRow({ row }: { row: AnalyticsArticle }) {
  return (
    <li className={styles.rankRow}>
      <Link href={pieceHref(row)} className={styles.rankLink}>
        <span className={styles.rankTitle}>{row.title}</span>
        <span className={styles.rankMeta}>
          {pretty(row.stats.pageViews)} views · {pretty(row.stats.qualifiedReads)} reads
        </span>
      </Link>
    </li>
  );
}
