import { PublishedArticlePage } from "@/components/article/PublishedArticlePage";
import {
  articleMetadata,
  loadPublishedArticle,
  relatedArticles,
} from "@/lib/editorial/article-page";

export const generateMetadata = articleMetadata;

export default async function NewsArticlePage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const article = await loadPublishedArticle(slug);
  const related = await relatedArticles(article);

  return <PublishedArticlePage article={article} related={related} />;
}
