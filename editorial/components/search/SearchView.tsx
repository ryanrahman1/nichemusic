"use client";

import Link from "next/link";
import { useEffect, useRef, useState, type FormEvent } from "react";
import { ArticleTeaserGrid } from "@/components/editorial/ArticleTeaserCard";
import teaserStyles from "@/components/editorial/article-teaser.module.css";
import articleStyles from "@/components/article/article.module.css";
import { StatusView } from "@/components/status/StatusView";
import { WriterRoleBadge } from "@/components/editorial/WriterRoleBadge";
import { WriterProfileLink } from "@/components/editorial/WriterProfileLink";
import { tagHref } from "@/lib/editorial/cms";
import { searchPublicEditorials } from "@/lib/editorial/api";
import type { EditorialSearch } from "@/lib/editorial/types";
import { publicWriterName } from "@/lib/editorial/writers";
import styles from "@/app/search/search.module.css";

const DEBOUNCE_MS = 600;

function syncSearchUrl(q: string) {
  const next = q ? `/search?q=${encodeURIComponent(q)}` : "/search";
  if (`${window.location.pathname}${window.location.search}` === next) return;
  window.history.replaceState(window.history.state, "", next);
}

export function SearchView({
  initialQuery,
  initialResults,
}: {
  initialQuery: string;
  initialResults: EditorialSearch;
}) {
  const [draft, setDraft] = useState(initialQuery);
  const [active, setActive] = useState(initialQuery);
  const [results, setResults] = useState(initialResults);
  const [busy, setBusy] = useState(false);
  const timer = useRef<number | null>(null);
  const stamp = useRef(0);

  // kick a search after they stop typing for a bit
  async function runSearch(raw: string) {
    const q = raw.trim();
    stamp.current += 1;
    const id = stamp.current;
    setActive(q);
    syncSearchUrl(q);

    if (q.length < 2) {
      setResults({ query: q, articles: [], writers: [], tags: [] });
      setBusy(false);
      return;
    }

    setBusy(true);
    const next = await searchPublicEditorials(q);
    if (id !== stamp.current) return;
    setResults(next);
    setBusy(false);
  }

  function queueSearch(value: string) {
    if (timer.current) window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      void runSearch(value);
    }, DEBOUNCE_MS);
  }

  useEffect(() => {
    return () => {
      if (timer.current) window.clearTimeout(timer.current);
    };
  }, []);

  function onSubmit(e: FormEvent) {
    e.preventDefault();
    if (timer.current) window.clearTimeout(timer.current);
    void runSearch(draft);
  }

  function clearDraft() {
    setDraft("");
    if (timer.current) window.clearTimeout(timer.current);
    void runSearch("");
  }

  const total =
    results.articles.length + results.writers.length + results.tags.length;
  const heading = active || "Find a piece.";

  return (
    <main className={articleStyles.index}>
      <header className={articleStyles.indexHead}>
        <p className={articleStyles.kicker}>Search</p>
        <h1>{heading}</h1>
        <form className={styles.form} onSubmit={onSubmit} role="search">
          <label className={styles.field}>
            <span className={styles.sr}>Search articles, writers, tags</span>
            <input
              type="text"
              name="q"
              value={draft}
              onChange={(e) => {
                const value = e.target.value;
                setDraft(value);
                queueSearch(value);
              }}
              placeholder="Article, writer, tag…"
              autoComplete="off"
              autoCorrect="off"
              spellCheck={false}
              autoFocus={!initialQuery}
            />
            {draft ? (
              <button
                type="button"
                className={styles.clear}
                onClick={clearDraft}
                aria-label="Clear search"
              >
                ×
              </button>
            ) : null}
          </label>
          <button type="submit" className={styles.go}>
            {busy ? "…" : "Search"}
          </button>
        </form>
      </header>

      {!active ? (
        <StatusView
          compact
          kicker="Search"
          title="Type a name, a tag, a title."
          body="Try searching for what you're looking for."
        />
      ) : null}

      {active && !busy && results.error ? (
        <StatusView
          compact
          kicker="Search"
          title="Search is unavailable right now."
          body={results.error}
          actions={[
            { href: "/news", label: "News" },
            { href: "/", label: "Home" },
          ]}
        />
      ) : null}

      {active && !busy && !results.error && total === 0 ? (
        <StatusView
          compact
          kicker="No results"
          title="Nothing matched that."
          body={`No published articles, writers, or tags for “${active}”. Try a shorter name or a different spelling.`}
          actions={[
            { href: "/news", label: "News" },
            { href: "/reviews", label: "Reviews" },
            { href: "/spotlights", label: "Spotlights" },
          ]}
        />
      ) : null}

      {results.articles.length > 0 ? (
        <section className={styles.section}>
          <p className={articleStyles.kicker}>Articles</p>
          <ArticleTeaserGrid
            articles={results.articles}
            className={teaserStyles.gridFlush}
          />
        </section>
      ) : null}

      {results.writers.length > 0 ? (
        <section className={styles.section}>
          <p className={articleStyles.kicker}>Writers</p>
          <ul className={styles.people}>
            {results.writers.map((writer) => {
              const name = publicWriterName(writer);
              return (
                <li key={writer.id}>
                  <WriterProfileLink
                    profileId={writer.profile?.id}
                    slug={writer.slug}
                    className={styles.person}
                  >
                    {writer.profile?.avatarUrl ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img src={writer.profile.avatarUrl} alt="" />
                    ) : (
                      <span className={styles.fallback}>{name.slice(0, 1)}</span>
                    )}
                    <span>
                      <strong>
                        {name} <WriterRoleBadge role={writer.role} />
                      </strong>
                      {writer.bio ? <em>{writer.bio}</em> : null}
                    </span>
                  </WriterProfileLink>
                </li>
              );
            })}
          </ul>
        </section>
      ) : null}

      {results.tags.length > 0 ? (
        <section className={styles.section}>
          <p className={articleStyles.kicker}>Tags</p>
          <ul className={styles.tags}>
            {results.tags.map((tag) => (
              <li key={tag.id}>
                <Link href={tagHref(tag)}>{tag.name}</Link>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </main>
  );
}
