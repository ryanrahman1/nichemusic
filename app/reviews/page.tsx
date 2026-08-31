import { Navbar } from "@/components/Navbar";
import { ReviewIndex } from "@/components/editorial/ReviewIndex";
import styles from "@/components/article/article.module.css";
import { StatusView } from "@/components/status/StatusView";
import { listPublishedReviews } from "@/lib/editorial/public";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Reviews",
  description: "Album scores and verdicts from the Niche desk.",
  path: "/reviews",
});

export default async function ReviewsPage() {
  const { articles, error } = await listPublishedReviews(40);

  return (
    <>
      <Navbar />
      <main className={styles.index}>
        <header className={styles.indexHead}>
          <h1>Reviews.</h1>
          <p className={styles.lede}>
            Albums reviewed by the community (and us), plus their verdicts.
          </p>
        </header>

        {error ? (
          <StatusView
            compact
            kicker="Reviews"
            title="The review desk is unavailable."
            body={error}
            actions={[
              { href: "/reviews", label: "Try again" },
              { href: "/", label: "Home" },
            ]}
          />
        ) : articles.length > 0 ? (
          <div className={styles.newsGrid}>
            <ReviewIndex articles={articles} />
          </div>
        ) : (
          <StatusView
            compact
            kicker="Reviews"
            title="No scores on the board."
            body="Nothing’s been published yet. When the desk sits with a record, it shows up here first."
            actions={[
              { href: "/news", label: "News" },
              { href: "/search", label: "Search" },
            ]}
          />
        )}
      </main>
    </>
  );
}
