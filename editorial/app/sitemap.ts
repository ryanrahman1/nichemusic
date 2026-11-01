import type { MetadataRoute } from "next";
import { articleHref } from "@/lib/editorial/cms";
import type { ArticleCard } from "@/lib/editorial/types";
import { listPublishedArticles } from "@/lib/editorial/public";
import { listLegalDocuments } from "@/lib/legal/public";
import { legalPath } from "@/lib/legal/types";
import { siteConfig } from "@/lib/site";

const SITEMAP_PAGE_SIZE = 50;

// walk every cursor page so older stories dont vanish from search
async function listAllPublishedArticles() {
  const articles: ArticleCard[] = [];
  const cursors = new Set<string>();
  let cursor: string | undefined;

  while (true) {
    const page = await listPublishedArticles(SITEMAP_PAGE_SIZE, {
      cursor,
    });
    if (page.error) {
      throw new Error(page.error);
    }

    articles.push(...page.articles);
    if (!page.hasMore || !page.nextCursor || cursors.has(page.nextCursor)) {
      return articles;
    }

    cursors.add(page.nextCursor);
    cursor = page.nextCursor;
  }
}

function articleLastModified(article: ArticleCard) {
  const value = article.updatedAt || article.publishedAt || article.createdAt;
  return value ? new Date(value) : undefined;
}

function addLatestDate(
  dates: Map<string, Date>,
  key: string,
  value: Date | undefined,
) {
  if (!value) return;
  const current = dates.get(key);
  if (!current || value > current) dates.set(key, value);
}

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [articles, legalResult] = await Promise.all([
    listAllPublishedArticles(),
    listLegalDocuments(),
  ]);
  if (legalResult.error) throw new Error(legalResult.error);

  const writerDates = new Map<string, Date>();
  const tagDates = new Map<string, Date>();

  for (const article of articles) {
    const lastModified = articleLastModified(article);
    for (const credit of article.credits ?? []) {
      const slug = credit.writer?.slug;
      if (credit.creditType === "writer" && slug) {
        addLatestDate(writerDates, slug, lastModified);
      }
    }
    for (const tag of article.tags) {
      if (tag.slug) addLatestDate(tagDates, tag.slug, lastModified);
    }
  }

  return [
    {
      url: siteConfig.url,
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${siteConfig.url}/news`,
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/reviews`,
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/spotlights`,
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/download`,
      changeFrequency: "weekly",
      priority: 0.8,
    },
    {
      url: `${siteConfig.url}/about`,
      changeFrequency: "monthly",
      priority: 0.7,
    },
    ...legalResult.documents.map((document) => ({
      url: `${siteConfig.url}${legalPath(document.slug)}`,
      lastModified: document.updatedAt ? new Date(document.updatedAt) : undefined,
      changeFrequency: "monthly" as const,
      priority: 0.4,
    })),
    ...articles.map((article) => ({
      url: `${siteConfig.url}${articleHref(article)}`,
      lastModified: articleLastModified(article),
      changeFrequency: "weekly" as const,
      priority: 0.7,
    })),
    ...Array.from(writerDates, ([slug, lastModified]) => ({
      url: `${siteConfig.url}/writers/${encodeURIComponent(slug)}`,
      lastModified,
      changeFrequency: "monthly" as const,
      priority: 0.5,
    })),
    ...Array.from(tagDates, ([slug, lastModified]) => ({
      url: `${siteConfig.url}/tags/${encodeURIComponent(slug)}`,
      lastModified,
      changeFrequency: "weekly" as const,
      priority: 0.5,
    })),
  ];
}
