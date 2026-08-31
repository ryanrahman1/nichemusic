import Link from "next/link";
import { articleHref, editorialHero, youtubeId } from "@/lib/editorial/cms";
import type { ArticleCard, SpotlightWidget } from "@/lib/editorial/types";
import styles from "./article.module.css";

export function SpotlightRail({
  widgets,
  featured,
  artistName,
}: {
  widgets: SpotlightWidget[];
  featured: Record<string, ArticleCard>;
  artistName?: string;
}) {
  if (widgets.length === 0) return null;

  return (
    <>
      {widgets.map((widget) => {
        if (widget.type === "essential_tracks" && widget.items.length > 0) {
          return (
            <section key={widget.id} className={styles.railCard}>
              <p className={styles.kicker}>Essential tracks</p>
              <div className={styles.railScroll}>
                {widget.items.map((item) => {
                  const inner = (
                    <>
                      {item.cover && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={item.cover} alt="" />
                      )}
                      <span>
                        <b>{item.title}</b>
                        {item.blurb ? <em>{item.blurb}</em> : null}
                      </span>
                    </>
                  );
                  return item.href ? (
                    <a key={item.id} href={item.href} className={styles.railTrack} target="_blank" rel="noreferrer">
                      {inner}
                    </a>
                  ) : (
                    <div key={item.id} className={styles.railTrack}>
                      {inner}
                    </div>
                  );
                })}
              </div>
            </section>
          );
        }

        if (widget.type === "if_you_like" && widget.items.length > 0) {
          return (
            <section key={widget.id} className={styles.railCard}>
              <p className={styles.kicker}>
                If you like {widget.artistName || artistName || "this"}…
              </p>
              <div className={styles.railScroll}>
                {widget.items.map((item) => {
                  const inner = (
                    <>
                      {item.cover && (
                        // eslint-disable-next-line @next/next/no-img-element
                        <img src={item.cover} alt="" />
                      )}
                      <b>{item.title}</b>
                    </>
                  );
                  return item.href ? (
                    <a key={item.id} href={item.href} className={styles.railArtist} target="_blank" rel="noreferrer">
                      {inner}
                    </a>
                  ) : (
                    <div key={item.id} className={styles.railArtist}>
                      {inner}
                    </div>
                  );
                })}
              </div>
            </section>
          );
        }

        if (widget.type === "watch") {
          const id = youtubeId(widget.youtubeUrl);
          if (!id) return null;
          return (
            <section key={widget.id} className={styles.railCard}>
              <p className={styles.kicker}>Watch</p>
              <div className={styles.railEmbed}>
                <iframe
                  src={`https://www.youtube-nocookie.com/embed/${id}`}
                  title={widget.caption || "Watch"}
                  allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
                  allowFullScreen
                />
              </div>
              {widget.caption && <p className={styles.railCap}>{widget.caption}</p>}
            </section>
          );
        }

        if (widget.type === "featured_on_niche") {
          const piece = featured[widget.id];
          if (!piece) return null;
          const hero = editorialHero(piece);
          return (
            <section key={widget.id} className={styles.railCard}>
              <p className={styles.kicker}>Featured on Niche</p>
              <Link href={articleHref(piece)} className={styles.railFeature}>
                {hero ? (
                  // eslint-disable-next-line @next/next/no-img-element
                  <img src={hero} alt={piece.coverImageAlt || piece.title} />
                ) : null}
                <span>
                  <span className={styles.kicker}>{piece.type}</span>
                  <b>{piece.title}</b>
                </span>
              </Link>
            </section>
          );
        }

        return null;
      })}
    </>
  );
}
