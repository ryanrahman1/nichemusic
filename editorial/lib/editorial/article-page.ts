import type { Metadata } from "next";
import { notFound, redirect } from "next/navigation";
import { articleHref, articleShareImage, articleTypeLabel } from "@/lib/editorial/cms";
import {
  getPublishedArticle,
  listPublishedArticles,
} from "@/lib/editorial/public";
import type { ArticleCard, ArticleType } from "@/lib/editorial/types";
import { primaryWriterCredit, writerDisplayName } from "@/lib/editorial/writers";
import { buildPageMetadata } from "@/lib/site";

type PageProps = {
  params: Promise<{ slug: string }>;
};

// grab the live piece or 404
export async function loadPublishedArticle(slug: string) {
  try {
    const { article } = await getPublishedArticle(slug);
    return article;
  } catch {
    notFound();
  }
}

// send mismatched types over to the right desk
export function ensureArticleType(article: ArticleCard, type: ArticleType) {
  if (article.type !== type) {
    redirect(articleHref(article));
  }
}

export async function articleMetadata({ params }: PageProps): Promise<Metadata> {
  const { slug } = await params;
  try {
    const { article } = await getPublishedArticle(slug);
    const title = article.metaTitle || article.title;
    const description =
      article.metaDescription || article.subtitle || article.excerpt || "";
    const image = articleShareImage(article);
    const author = writerDisplayName(primaryWriterCredit(article));
    return buildPageMetadata({
      title,
      description,
      path: articleHref(article),
      type: "article",
      publishedTime: article.publishedAt,
      authors: author ? [author] : undefined,
      section: articleTypeLabel(article.type),
      tags: article.tags.map((tag) => tag.name).filter(Boolean),
      images: image
        ? [
            {
              url: image,
              alt: article.coverImageAlt || title,
            },
          ]
        : undefined,
    });
  } catch {
    return buildPageMetadata({ title: "Article", path: `/news/${slug}` });
  }
}

export async function relatedArticles(article: ArticleCard, limit = 2) {
  const { articles } = await listPublishedArticles(8);
  return articles.filter((item) => item.slug !== article.slug).slice(0, limit);
}
