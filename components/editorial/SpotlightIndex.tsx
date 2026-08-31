import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { articleHref, editorialHero } from "@/lib/editorial/cms";
import type { ArticleCard, SpotlightData } from "@/lib/editorial/types";
import styles from "./desk-index.module.css";

function shortDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

// artist card bits — portrait first, then scene/city
function spotlightBits(article: ArticleCard) {
  const data = (article.templateData ?? {}) as Partial<SpotlightData>;
  return {
    artist: data.artist || article.title,
    location: data.location || "",
    scene: data.scene || "",
    blurb: article.excerpt || article.subtitle || "",
    cover: editorialHero(article),
  };
}

export function SpotlightIndex({ articles }: { articles: ArticleCard[] }) {
  const [lead, ...rest] = articles;
  if (!lead) return null;

  const featured = spotlightBits(lead);
  const place = [featured.location, featured.scene].filter(Boolean).join(" · ");

  return (
    <>
      <Link href={articleHref(lead)} className={styles.spotlightHero}>
        <div className={styles.portrait}>
          {featured.cover ? (
            <CoverImage
              src={featured.cover}
              alt={featured.artist}
              sizes="420px"
              priority
            />
          ) : null}
        </div>
        <div>
          <p className={styles.leadKicker}>
            On the cover · {shortDate(lead.publishedAt)}
          </p>
          <h2>{featured.artist}</h2>
          {place ? <p className={styles.place}>{place}</p> : null}
          {featured.blurb ? <p>{featured.blurb}</p> : null}
        </div>
      </Link>

      {rest.length > 0 ? (
        <div className={styles.roster}>
          {rest.map((article) => {
            const bits = spotlightBits(article);
            const meta = [bits.location, bits.scene, shortDate(article.publishedAt)]
              .filter(Boolean)
              .join(" · ");
            return (
              <Link key={article.id} href={articleHref(article)} className={styles.rosterCard}>
                <div className={styles.rosterMedia}>
                  {bits.cover ? (
                    <CoverImage
                      src={bits.cover}
                      alt={bits.artist}
                      sizes="(max-width: 640px) 50vw, 25vw"
                    />
                  ) : null}
                </div>
                <h3 className={styles.rosterName}>{bits.artist}</h3>
                {meta ? <p className={styles.rosterMeta}>{meta}</p> : null}
              </Link>
            );
          })}
        </div>
      ) : null}
    </>
  );
}
