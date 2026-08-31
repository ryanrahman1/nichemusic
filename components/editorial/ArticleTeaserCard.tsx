import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { WriterRoleBadge } from "@/components/editorial/WriterRoleBadge";
import styles from "@/components/editorial/article-teaser.module.css";
import articleStyles from "@/components/article/article.module.css";
import { articleHref, articleTypeLabel, editorialHero } from "@/lib/editorial/cms";
import {
  primaryWriterCredit,
  writerDisplayName,
} from "@/lib/editorial/writers";
import type { ArticleCard } from "@/lib/editorial/types";

function shortDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

function kickerLine(article: ArticleCard) {
  return [articleTypeLabel(article.type), shortDate(article.publishedAt)]
    .filter(Boolean)
    .join(" · ");
}

function CardByline({ article }: { article: ArticleCard }) {
  const credit = primaryWriterCredit(article);
  const name = writerDisplayName(credit);
  const avatar = credit?.writer?.profile?.avatarUrl;
  if (!name) return null;

  return (
    <div className={styles.byline}>
      {avatar ? (
        // eslint-disable-next-line @next/next/no-img-element
        <img className={styles.avatar} src={avatar} alt="" />
      ) : null}
      <span>{name}</span>
      <WriterRoleBadge role={credit?.writer?.role} />
    </div>
  );
}

export function ArticleTeaserCard({
  article,
  priority = false,
}: {
  article: ArticleCard;
  priority?: boolean;
}) {
  const cover = editorialHero(article);
  const data = (article.templateData ?? {}) as { rating?: string };
  const blurb = article.excerpt || article.subtitle || "";

  return (
    <Link href={articleHref(article)} className={styles.card}>
      <div className={styles.cardMedia}>
        {cover ? (
          <CoverImage
            src={cover}
            alt={article.coverImageAlt || article.title}
            sizes="(max-width: 640px) 100vw, (max-width: 980px) 50vw, 33vw"
            priority={priority}
          />
        ) : null}
      </div>
      <p className={`${articleStyles.kicker} ${styles.cardMeta}`}>{kickerLine(article)}</p>
      <h3 className={styles.cardTitle}>{article.title}</h3>
      {(blurb || data.rating) && (
        <p className={styles.cardExcerpt}>
          {blurb}
          {data.rating ? (
            <>
              {blurb ? " " : ""}
              <span className={styles.cardScore}>{data.rating}</span>
            </>
          ) : null}
        </p>
      )}
      <CardByline article={article} />
    </Link>
  );
}

export function ArticleTeaserGrid({
  articles,
  className,
  priorityCount = 0,
}: {
  articles: ArticleCard[];
  className?: string;
  priorityCount?: number;
}) {
  return (
    <div className={className ? `${styles.grid} ${className}` : styles.grid}>
      {articles.map((article, index) => (
        <ArticleTeaserCard
          key={article.id}
          article={article}
          priority={index < priorityCount}
        />
      ))}
    </div>
  );
}
