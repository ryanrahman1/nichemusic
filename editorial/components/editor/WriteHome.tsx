"use client";

import { useState, type FormEvent } from "react";
import { useRouter } from "next/navigation";
import { ArticleCatalog, PieceCard, ReviewQueue } from "@/components/editor/DeskBoard";
import { AnalyticsDesk } from "@/components/editor/AnalyticsDesk";
import { DeskFold } from "@/components/editor/DeskFold";
import { NewMusicDesk } from "@/components/editor/NewMusicDesk";
import {
  createDraft,
  createWriterOnboarding,
  getWriterWorkspace,
} from "@/lib/editorial/api";
import { slugify, TEMPLATE_META } from "@/lib/editorial/cms";
import {
  ARTICLE_TEMPLATES,
  ARTICLE_TYPES,
  type ArticleCard,
  type ArticleTemplate,
  type ArticleType,
  type OnboardingProfile,
  type WriterWorkspace,
} from "@/lib/editorial/types";
import { StatusView } from "@/components/status/StatusView";
import styles from "@/components/editor/write-home.module.css";
import Link from "next/link";

export function WriteHome({
  initial,
  onboardingProfile,
}: {
  initial: WriterWorkspace;
  onboardingProfile?: OnboardingProfile | null;
}) {
  const router = useRouter();
  const [workspace, setWorkspace] = useState(initial);
  const [error, setError] = useState<string | null>(null);
  const [composing, setComposing] = useState(false);
  const [title, setTitle] = useState("");
  const [slug, setSlug] = useState("");
  const [slugTouched, setSlugTouched] = useState(false);
  const [template, setTemplate] = useState<ArticleTemplate>("standard");
  const [type, setType] = useState<ArticleType>("news");
  const [busy, setBusy] = useState(false);
  const [writerSlug, setWriterSlug] = useState(onboardingProfile?.username ?? "");
  const [displayName, setDisplayName] = useState(
    onboardingProfile?.displayName ?? onboardingProfile?.username ?? "",
  );
  const [bio, setBio] = useState(onboardingProfile?.bio ?? "");
  const [location, setLocation] = useState(onboardingProfile?.location ?? "");

  const onboard = !workspace.writer || !workspace.permissions.canWrite;
  const perms = workspace.permissions;
  const articles = workspace.articles;
  const queue = workspace.queue;
  const catalog = workspace.catalog;

  function dropArticle(id: string) {
    setWorkspace((cur) => ({
      ...cur,
      articles: cur.articles.filter((row) => row.id !== id),
      queue: cur.queue.filter((row) => row.id !== id),
      catalog: cur.catalog.filter((row) => row.id !== id),
    }));
  }

  function pickTemplate(next: ArticleTemplate) {
    setTemplate(next);
    setType(TEMPLATE_META[next].type);
  }

  function onTitle(value: string) {
    setTitle(value);
    if (!slugTouched) setSlug(slugify(value));
  }

  async function onCreate(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      const { article } = await createDraft({
        title: title.trim(),
        slug: slugify(slug.trim() || title.trim()),
        type: template === "standard" ? type : TEMPLATE_META[template].type,
        template,
      });
      if (!article?.id) {
        throw new Error("Draft created but the API didnt return it — refresh and open it from the list");
      }
      router.push(`/write/${article.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldnt create draft");
    } finally {
      setBusy(false);
    }
  }

  async function onOnboard(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await createWriterOnboarding({
        slug: slugify(writerSlug),
        bio: bio.trim(),
        displayName: displayName.trim() || undefined,
        location: location.trim() || null,
      });
      setWorkspace(await getWriterWorkspace());
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldnt create writer profile");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className={styles.page}>
      <header className={styles.head}>
        <div>
          <p className={styles.kicker}>Editorial</p>
          <h1>{onboard ? "Become a writer" : "Write"}</h1>
          <p className={styles.lede}>
            {onboard
              ? "Set a slug and bio, then you can start a piece."
              : perms.canReview
                ? "Review what’s in, or start something of your own."
                : "Your drafts and published pieces, in one place."}
          </p>
          <p className={styles.lede}>
            Review the{" "}
            <Link
              className="underline-link underline-link--inline"
              href="/standards"
              target="_blank"
            >
              Editorial Standards
            </Link>{" "}
            and our{" "}
            <Link
              className="underline-link underline-link--inline"
              href="/guidelines"
              target="_blank"
            >
              Community Guidelines
            </Link>{" "}
            before you start.
          </p>
        </div>
        {!onboard ? (
          <div className={styles.actions}>
            <button
              type="button"
              className="cta-download"
              onClick={() => setComposing((on) => !on)}
            >
              {composing ? "Close" : "New piece"}
            </button>
          </div>
        ) : null}
      </header>

      {error ? (
        <div className={styles.section}>
          <StatusView
            compact
            kicker="Write"
            title="That didn’t go through."
            body={error}
          />
        </div>
      ) : null}

      {onboard ? (
        <section className={styles.section}>
          <form className={styles.create} onSubmit={onOnboard}>
            <label>
              Writer slug
              <input
                required
                value={writerSlug}
                onChange={(e) => setWriterSlug(e.target.value)}
                placeholder="mara-okafor"
              />
            </label>
            <label>
              Display name
              <input
                required
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                placeholder="Mara Okafor"
              />
            </label>
            <label>
              Bio
              <input
                required
                value={bio}
                onChange={(e) => setBio(e.target.value)}
              />
            </label>
            <label>
              Location
              <input
                value={location}
                onChange={(e) => setLocation(e.target.value)}
                placeholder="London, UK"
              />
            </label>
            <button type="submit" className="cta-download" disabled={busy}>
              {busy ? "Creating…" : "Create writer profile"}
            </button>
          </form>
        </section>
      ) : (
        <>
          {composing ? (
            <section className={styles.section}>
              <form className={styles.create} onSubmit={onCreate}>
                <label>
                  Title
                  <input
                    required
                    value={title}
                    onChange={(e) => onTitle(e.target.value)}
                    placeholder="Article title"
                  />
                </label>
                <label>
                  Slug
                  <input
                    required
                    value={slug}
                    onChange={(e) => {
                      setSlugTouched(true);
                      setSlug(e.target.value);
                    }}
                    placeholder="album-name-review"
                  />
                </label>
                <div className={styles.tplGrid}>
                  {ARTICLE_TEMPLATES.map((item) => (
                    <button
                      key={item}
                      type="button"
                      className={template === item ? styles.tplOn : styles.tpl}
                      onClick={() => pickTemplate(item)}
                    >
                      <strong>{TEMPLATE_META[item].label}</strong>
                      <span>{TEMPLATE_META[item].blurb}</span>
                    </button>
                  ))}
                </div>
                {template === "standard" && (
                  <label>
                    Type
                    <select
                      value={type}
                      onChange={(e) => setType(e.target.value as ArticleType)}
                    >
                      {ARTICLE_TYPES.map((item) => (
                        <option key={item} value={item}>
                          {item}
                        </option>
                      ))}
                    </select>
                  </label>
                )}
                <button type="submit" className="cta-download" disabled={busy}>
                  {busy ? "Creating…" : "Start draft"}
                </button>
              </form>
            </section>
          ) : null}

          {perms.canReview ? <ReviewQueue queue={queue} /> : null}

          <DeskFold id="pieces" title="Your pieces" meta={`${articles.length} total`}>
            {articles.length === 0 ? (
              <StatusView
                compact
                kicker="Your pieces"
                title="Nothing of yours yet."
                body="Start a draft and it’ll live here — reviews, news, spotlights, the whole stack."
              />
            ) : (
              <div className={styles.grid}>
                {articles.map((article: ArticleCard) => (
                  <PieceCard key={article.id} article={article} />
                ))}
              </div>
            )}
          </DeskFold>

          <AnalyticsDesk canReview={perms.canReview} />

          {perms.canReview ? <NewMusicDesk /> : null}

          {perms.canEditAny ? (
            <ArticleCatalog
              catalog={catalog}
              canDelete={perms.canDelete}
              onDeleted={dropArticle}
            />
          ) : null}
        </>
      )}
    </main>
  );
}
