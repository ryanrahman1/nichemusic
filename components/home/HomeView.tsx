import Link from "next/link";
import { CoverImage } from "@/components/home/CoverImage";
import { ArticleTeaserGrid } from "@/components/editorial/ArticleTeaserCard";
import styles from "@/components/home/home.module.css";
import articleStyles from "@/components/article/article.module.css";
import { articleHref, articleTypeLabel, editorialHero } from "@/lib/editorial/cms";
import type { ArticleCard, EditorialHome, HomeNewMusicPick } from "@/lib/editorial/types";
import { StatusView } from "@/components/status/StatusView";
import { siteConfig } from "@/lib/site";

function shortDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
}

function kickerLine(article: ArticleCard, extra?: string) {
  const bits = [articleTypeLabel(article.type), extra, shortDate(article.publishedAt)].filter(Boolean);
  return bits.join(" · ");
}

function SponsoredBlock({
  article,
  compact = false,
}: {
  article: ArticleCard;
  compact?: boolean;
}) {
  const cover = editorialHero(article);
  const sponsor = article.sponsorName;

  return (
    <section className={styles.section}>
      <Link
        href={articleHref(article)}
        className={compact ? `${styles.promo} ${styles.promoCompact}` : styles.promo}
      >
        <div>
          <div className={styles.promoFlags}>
            <span className={styles.paid}>{compact ? "Sponsored" : "Paid promotion"}</span>
            <span className={styles.paidNote}>
              {sponsor ? `Paid for by ${sponsor}.` : ""}
            </span>
          </div>
          <h2>{article.title}</h2>
          {(article.excerpt || article.subtitle) && <p>{article.excerpt || article.subtitle}</p>}
          <span className="underline-link underline-link--action">Read the promo</span>
        </div>
        {cover ? (
          <div className={styles.promoMedia}>
            <CoverImage
              src={cover}
              alt={article.coverImageAlt || article.title}
              sizes={compact ? "220px" : "(max-width: 980px) 100vw, 36vw"}
            />
          </div>
        ) : null}
      </Link>
    </section>
  );
}

function NewMusicCard({ pick }: { pick: HomeNewMusicPick }) {
  const title = pick.track.name || "Untitled";
  const artist = pick.track.artist?.name;

  return (
    <article className={styles.track}>
      <div className={styles.trackMedia}>
        {pick.track.artworkUrl ? (
          <CoverImage src={pick.track.artworkUrl} alt={title} sizes="(max-width: 640px) 196px, 25vw" />
        ) : null}
      </div>
      <b className={styles.trackTitle}>{title}</b>
      {artist ? <span className={styles.trackMeta}>{artist}</span> : null}
      {pick.review ? (
        <Link href={articleHref(pick.review)} className={`underline-link ${styles.reviewLink}`}>
          Read the review
        </Link>
      ) : null}
    </article>
  );
}

export function HomeView({ data }: { data: EditorialHome }) {
  const hero = data.hero;
  const heroCover = hero ? editorialHero(hero) : null;
  const heroData = (hero?.templateData ?? {}) as { rating?: string; badge?: string };
  const hasDesk =
    !data.error &&
    Boolean(
      hero ||
        data.premiumPromo ||
        data.featured.length > 0 ||
        data.newMusic.length > 0 ||
        data.promo ||
        data.latest.length > 0,
    );

  return (
    <div className={styles.home}>
      {data.error ? (
        <StatusView
          compact
          kicker="Home"
          title="The editorial board is unavailable."
          body={data.error}
          actions={[
            { href: "/", label: "Try again" },
            { href: "/search", label: "Search" },
          ]}
        />
      ) : null}
      {hero ? (
        <Link href={articleHref(hero)} className={styles.hero}>
          {heroCover ? (
            <div className={styles.heroMedia}>
              <CoverImage
                src={heroCover}
                alt={hero.coverImageAlt || hero.title}
                sizes="100vw"
                priority
              />
            </div>
          ) : null}
          <div className={styles.heroShade} />
          <div className={styles.heroCopy}>
            <p className={articleStyles.kicker}>{kickerLine(hero, heroData.badge)}</p>
            <h1>{hero.title}</h1>
            <div className={styles.heroRow}>
              {heroData.rating ? (
                <div>
                  <span className={styles.score}>{heroData.rating}</span>
                  <span className={styles.over}> / 10</span>
                </div>
              ) : null}
              <div>
                {(hero.excerpt || hero.subtitle) && (
                  <p className={styles.heroBlurb}>{hero.excerpt || hero.subtitle}</p>
                )}
                <span className="underline-link underline-link--action">
                  {hero.type === "review" ? "Read the review" : "Read the story"}
                </span>
              </div>
            </div>
          </div>
        </Link>
      ) : null}

      {data.premiumPromo ? <SponsoredBlock article={data.premiumPromo} /> : null}

      {data.featured.length > 0 ? (
        <section className={styles.section}>
          <p className={articleStyles.kicker}>Featured</p>
          <ArticleTeaserGrid
            articles={data.featured}
            priorityCount={hero ? 1 : 3}
          />
        </section>
      ) : null}

      {data.newMusic.length > 0 ? (
        <section className={styles.section} id="new-music">
          <div className={styles.sectionHead}>
            <div>
              <p className={articleStyles.kicker}>New Music Friday</p>
              <h2>The hottest tracks from the underground this week.</h2>
            </div>
            <Link href="#new-music" className="underline-link underline-link--action">
              See the full list
            </Link>
          </div>
          <div className={styles.tracks}>
            {data.newMusic.map((pick) => (
              <NewMusicCard key={pick.track.id} pick={pick} />
            ))}
          </div>
        </section>
      ) : null}

      {data.promo ? <SponsoredBlock article={data.promo} compact /> : null}

      {data.latest.length > 0 ? (
        <section className={styles.section}>
          <p className={articleStyles.kicker}>Latest</p>
          <ArticleTeaserGrid articles={data.latest} />
        </section>
      ) : null}

      {!hasDesk ? (
        <StatusView
          compact
          kicker="Home"
          title="The board’s still empty."
          body="Nothing on the homepage yet. The desk is still setting the board — news, reviews, and spotlights will land here first."
          actions={[
            { href: "/news", label: "News" },
            { href: "/search", label: "Search" },
          ]}
        />
      ) : null}

      <section className={`${styles.section} ${styles.aboutSection}`} id="about">
        <div className={styles.about}>
          <div>
            <p className={articleStyles.kicker}>Niche Music</p>
            <h2>Discover the artists shaping the future of music.</h2>
            <p>
              {siteConfig.name} is where the desk writes and where the scene actually lives.
              Read the coverage, then follow the artists in the app.
            </p>
          </div>
          <div className={styles.aboutActions}>
            <Link href="/about" className="underline-link underline-link--action">
              About Niche
            </Link>
            <Link href="/download" className="cta-download">
              Get the app
            </Link>
          </div>
        </div>
      </section>
    </div>
  );
}
