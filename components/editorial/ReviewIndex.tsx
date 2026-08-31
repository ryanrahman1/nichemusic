import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { articleHref, editorialHero } from "@/lib/editorial/cms";
import type { AlbumReviewData, ArticleCard } from "@/lib/editorial/types";
import styles from "./desk-index.module.css";

function shortDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

// pull the album bits writers stuffed in template data
function reviewBits(article: ArticleCard) {
  const data = (article.templateData ?? {}) as Partial<AlbumReviewData>;
  return {
    artist: data.artist || article.title,
    album: data.album || article.subtitle || "",
    rating: data.rating || "",
    blurb: article.excerpt || data.verdict || "",
    cover: editorialHero(article),
  };
}

export function ReviewIndex({ articles }: { articles: ArticleCard[] }) {
  const [lead, ...rest] = articles;
  if (!lead) return null;

  const featured = reviewBits(lead);

  return (
    <>
      <Link href={articleHref(lead)} className={styles.feature}>
        <div className={styles.featureArt}>
          {featured.cover ? (
            <CoverImage
              src={featured.cover}
              alt={featured.album || featured.artist}
              sizes="480px"
              priority
            />
          ) : null}
        </div>
        <div className={styles.featureCopy}>
          <p className={styles.leadKicker}>
            Latest score · {shortDate(lead.publishedAt)}
          </p>
          <h2>{featured.artist}</h2>
          {featured.album ? (
            <p className={styles.album}>
              <em>{featured.album}</em>
            </p>
          ) : null}
          {featured.blurb ? <p>{featured.blurb}</p> : null}
          {featured.rating ? (
            <span className={styles.score}>
              {featured.rating}
              <span className={styles.over}> / 10</span>
            </span>
          ) : null}
        </div>
      </Link>

      {rest.length > 0 ? (
        <div className={styles.ledger}>
          {rest.map((article) => {
            const bits = reviewBits(article);
            return (
              <Link key={article.id} href={articleHref(article)} className={styles.row}>
                <div className={styles.rowArt}>
                  {bits.cover ? (
                    <CoverImage
                      src={bits.cover}
                      alt={bits.album || bits.artist}
                      sizes="72px"
                    />
                  ) : null}
                </div>
                <span className={styles.rowArtist}>{bits.artist}</span>
                <span className={styles.rowAlbum}>{bits.album || article.title}</span>
                <span className={styles.rowScore}>{bits.rating || "—"}</span>
                <span className={styles.rowDate}>{shortDate(article.publishedAt)}</span>
              </Link>
            );
          })}
        </div>
      ) : null}
    </>
  );
}
