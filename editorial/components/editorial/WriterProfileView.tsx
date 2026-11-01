import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { WriterRoleBadge } from "@/components/editorial/WriterRoleBadge";
import {
  articleHref,
  articleTypeLabel,
} from "@/lib/editorial/cms";
import type { AlbumReviewData, ArticleCard, PublicWriter } from "@/lib/editorial/types";
import {
  publicWriterName,
  writerAppHref,
} from "@/lib/editorial/writers";
import styles from "./writer-profile.module.css";

// comma-fy the big desk numbers
function prettyCount(value: number) {
  return new Intl.NumberFormat("en-US").format(value);
}

// month + year they showed up
function joinedLabel(value: string | null | undefined) {
  if (!value) return "";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return "";
  return date.toLocaleDateString("en-US", { month: "long", year: "numeric" });
}

function shortDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

// fallback letters if they aint got a pic
function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() ?? "")
    .join("");
}

// score only shows up on album reviews
function reviewScore(article: ArticleCard) {
  const data = (article.templateData ?? {}) as Partial<AlbumReviewData>;
  return data.rating || "";
}

// little under-title line
function pieceMeta(article: ArticleCard) {
  return article.excerpt || article.subtitle || shortDate(article.publishedAt);
}

export function WriterProfileView({
  writer,
  articles,
  self = false,
}: {
  writer: PublicWriter;
  articles: ArticleCard[];
  self?: boolean;
}) {
  const name = publicWriterName(writer);
  const username = writer.profile?.username;
  const avatar = writer.profile?.avatarUrl;
  const appHref = writerAppHref(username);
  const joined = joinedLabel(writer.joinedAt);
  const followers =
    writer.stats.followersCount ?? writer.profile?.followersCount ?? 0;

  return (
    <main className={styles.page}>
      <section className={styles.hero}>
        <div className={styles.portrait}>
          {avatar ? (
            <CoverImage src={avatar} alt={name} sizes="420px" priority />
          ) : (
            <span className={styles.initials} aria-hidden>
              {initials(name)}
            </span>
          )}
        </div>

        <div className={styles.intro}>
          <div className={styles.metaRow}>
            <WriterRoleBadge role={writer.role} />
            <span className={styles.handle}>
              {username ? `@${username}` : writer.slug}
              {joined ? ` · joined ${joined}` : ""}
            </span>
          </div>

          <h1>{name}</h1>

          {writer.bio ? <p className={styles.bio}>{writer.bio}</p> : null}

          <div className={self ? `${styles.stats} ${styles.statsWide}` : styles.stats}>
            <Stat label="Published" value={prettyCount(writer.stats.publishedCount)} />
            <Stat label="Edited" value={prettyCount(writer.stats.editedCount)} />
            <Stat label="Followers" value={prettyCount(followers)} />
            {self ? (
              <Stat label="Views" value={prettyCount(writer.stats.totalViews ?? 0)} />
            ) : null}
          </div>

          <div className={styles.actions}>
            {self ? (
              <Link href="/write" className="underline-link underline-link--action">
                Write
              </Link>
            ) : null}
            {appHref ? (
              <a
                href={appHref}
                className="underline-link underline-link--action"
                target="_blank"
                rel="noopener noreferrer"
              >
                View profile in app ↗
              </a>
            ) : null}
          </div>
        </div>
      </section>

      <section className={styles.published}>
        <p className={styles.kicker}>Published</p>
        {articles.length > 0 ? (
          <div>
            {articles.map((article) => {
              const score = reviewScore(article);
              const meta = pieceMeta(article);
              return (
                <Link
                  key={article.id}
                  href={articleHref(article)}
                  className={styles.row}
                >
                  <span className={styles.rowType}>
                    {articleTypeLabel(article.type)}
                  </span>
                  <span>
                    <span className={styles.rowTitle}>{article.title}</span>
                    {meta ? <span className={styles.rowMeta}>{meta}</span> : null}
                  </span>
                  <span className={styles.rowScore}>{score}</span>
                </Link>
              );
            })}
          </div>
        ) : (
          <p className={styles.empty}>
            {self
              ? "Nothing published yet. Start a piece and it’ll land here."
              : "Nothing published yet. When their first piece goes live, it shows up here."}
          </p>
        )}
      </section>
    </main>
  );
}

// one of those big hero counters
function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <p className={styles.statLabel}>{label}</p>
      <p className={styles.statValue}>{value}</p>
    </div>
  );
}
