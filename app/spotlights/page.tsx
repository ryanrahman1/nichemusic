import { Navbar } from "@/components/Navbar";
import { SpotlightIndex } from "@/components/editorial/SpotlightIndex";
import styles from "@/components/article/article.module.css";
import { StatusView } from "@/components/status/StatusView";
import { listPublishedSpotlights } from "@/lib/editorial/public";
import { buildPageMetadata, siteConfig } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Spotlights",
  description: "Artist profiles from the Niche desk.",
  path: "/spotlights",
});

export default async function SpotlightsPage() {
  const { articles, error } = await listPublishedSpotlights(40);

  return (
    <>
      <Navbar />
      <main className={styles.index}>
        <header className={styles.indexHead}>
          <h1>Spotlights.</h1>
          <p className={styles.lede}>
            Faces behind the records. {siteConfig.name} profiles the artists
            shaping underground scenes — where they&apos;re from, what they
            sound like, why they matter now.
          </p>
        </header>

        {error ? (
          <StatusView
            compact
            kicker="Spotlights"
            title="The spotlight desk is unavailable."
            body={error}
            actions={[
              { href: "/spotlights", label: "Try again" },
              { href: "/", label: "Home" },
            ]}
          />
        ) : articles.length > 0 ? (
          <div className={styles.newsGrid}>
            <SpotlightIndex articles={articles} />
          </div>
        ) : (
          <StatusView
            compact
            kicker="Spotlights"
            title="No profiles live yet."
            body="Artist spotlights land here once they’re published. Until then, the rest of the desk is still open."
            actions={[
              { href: "/reviews", label: "Reviews" },
              { href: "/news", label: "News" },
            ]}
          />
        )}
      </main>
    </>
  );
}
