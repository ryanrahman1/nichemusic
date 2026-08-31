import { notFound } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { ArticleTeaserGrid } from "@/components/editorial/ArticleTeaserCard";
import teaserStyles from "@/components/editorial/article-teaser.module.css";
import styles from "@/components/article/article.module.css";
import { StatusView } from "@/components/status/StatusView";
import { getPublicTagPage } from "@/lib/editorial/public";
import { buildPageMetadata, siteConfig } from "@/lib/site";

type PageProps = {
  params: Promise<{ slug: string }>;
};

// pull the tag or 404
async function loadTagPage(slug: string) {
  try {
    return await getPublicTagPage(slug);
  } catch {
    notFound();
  }
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  try {
    const { tag, articles } = await getPublicTagPage(slug);
    return buildPageMetadata({
      title: tag.name,
      description: `${articles.length} ${articles.length === 1 ? "piece" : "pieces"} tagged ${tag.name} on ${siteConfig.name}.`,
      path: `/tags/${tag.slug}`,
    });
  } catch {
    return buildPageMetadata({
      title: "Tag",
      description: `Stories tagged on ${siteConfig.name}.`,
      path: `/tags/${slug}`,
    });
  }
}

export default async function TagPage({ params }: PageProps) {
  const { slug } = await params;
  const { tag, articles } = await loadTagPage(slug);
  const count =
    articles.length === 1 ? "1 piece" : `${articles.length} pieces`;

  return (
    <>
      <Navbar />
      <main className={styles.index}>
        <header className={styles.indexHead}>
          <p className={styles.kicker}>Tag</p>
          <h1>{tag.name}.</h1>
          <p className={styles.lede}>
            Everything the desk filed under {tag.name}. {count} live now.
          </p>
        </header>

        {articles.length > 0 ? (
          <div className={styles.newsGrid}>
            <ArticleTeaserGrid articles={articles} className={teaserStyles.gridFlush} />
          </div>
        ) : (
          <StatusView
            compact
            kicker="Tag"
            title="Nothing live under this tag."
            body="The tag exists, but no published pieces are on it yet. Search or browse the desks."
            actions={[
              { href: "/search", label: "Search" },
              { href: "/news", label: "News" },
            ]}
          />
        )}
      </main>
    </>
  );
}
