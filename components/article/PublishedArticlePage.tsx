import { ArticleView } from "@/components/article/ArticleView";
import { JsonLd } from "@/components/JsonLd";
import { Navbar } from "@/components/Navbar";
import { articleHref, articleShareImage } from "@/lib/editorial/cms";
import type { ArticleCard } from "@/lib/editorial/types";
import { primaryWriterCredit, writerDisplayName } from "@/lib/editorial/writers";
import { siteConfig } from "@/lib/site";

export function PublishedArticlePage({
  article,
  related,
}: {
  article: ArticleCard;
  related: ArticleCard[];
}) {
  const author = writerDisplayName(primaryWriterCredit(article));
  const schemaType =
    article.type === "review"
      ? "Review"
      : article.type === "news"
        ? "NewsArticle"
        : "Article";

  return (
    <>
      <Navbar />
      <main className="page-main">
        <JsonLd
          data={{
            "@context": "https://schema.org",
            "@type": schemaType,
            headline: article.title,
            alternativeHeadline: article.subtitle || undefined,
            description: article.excerpt || article.subtitle,
            datePublished: article.publishedAt,
            image: articleShareImage(article) || undefined,
            mainEntityOfPage: `${siteConfig.url}${articleHref(article)}`,
            author: author
              ? {
                  "@type": "Person",
                  name: author,
                }
              : undefined,
            publisher: {
              "@type": "Organization",
              name: siteConfig.author,
              url: siteConfig.url,
            },
          }}
        />
        <ArticleView article={article} related={related.slice(0, 2)} />
      </main>
    </>
  );
}
