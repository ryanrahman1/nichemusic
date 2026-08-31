import { Navbar } from "@/components/Navbar";
import { ArticleTeaserGrid } from "@/components/editorial/ArticleTeaserCard";
import teaserStyles from "@/components/editorial/article-teaser.module.css";
import styles from "@/components/article/article.module.css";
import { StatusView } from "@/components/status/StatusView";
import { listPublishedArticles } from "@/lib/editorial/public";
import { buildPageMetadata, siteConfig } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "News",
  description: "Underground music news, documented as it happens.",
  path: "/news",
});

export default async function NewsPage() {
  const { articles, error } = await listPublishedArticles(40, { type: "news" });

  return (
    <>
      <Navbar />
      <main className={styles.index}>
        <header className={styles.indexHead}>
          <p className={styles.kicker}>The desk</p>
          <h1>News.</h1>
          <p className={styles.lede}>
            Underground music, documented as it happens. {siteConfig.name}{" "}
            publishes the story as it lands.
          </p>
        </header>

        {error ? (
          <StatusView
            compact
            kicker="News"
            title="The news desk is unavailable."
            body={error}
            actions={[
              { href: "/news", label: "Try again" },
              { href: "/", label: "Home" },
            ]}
          />
        ) : articles.length > 0 ? (
          <div className={styles.newsGrid}>
            <ArticleTeaserGrid articles={articles} className={teaserStyles.gridFlush} />
          </div>
        ) : (
          <StatusView
            compact
            kicker="News"
            title="Nothing published yet."
            body="The desk hasn’t dropped a story here. Check reviews and spotlights, or come back when the next one lands."
            actions={[
              { href: "/reviews", label: "Reviews" },
              { href: "/spotlights", label: "Spotlights" },
            ]}
          />
        )}
      </main>
    </>
  );
}
