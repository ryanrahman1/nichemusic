import type { MetadataRoute } from "next";
import { articleHref } from "@/lib/editorial/cms";
import { listPublishedArticles } from "@/lib/editorial/public";
import { listLegalDocuments } from "@/lib/legal/public";
import { legalPath } from "@/lib/legal/types";
import { siteConfig } from "@/lib/site";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const [{ articles }, { documents }] = await Promise.all([
    listPublishedArticles(50),
    listLegalDocuments(),
  ]);

  return [
    {
      url: siteConfig.url,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
    },
    {
      url: `${siteConfig.url}/news`,
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/reviews`,
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/spotlights`,
      lastModified: new Date(),
      changeFrequency: "daily",
      priority: 0.9,
    },
    {
      url: `${siteConfig.url}/download`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.8,
    },
    {
      url: `${siteConfig.url}/about`,
      lastModified: new Date(),
      changeFrequency: "monthly",
      priority: 0.7,
    },
    ...documents.map((document) => ({
      url: `${siteConfig.url}${legalPath(document.slug)}`,
      lastModified: document.updatedAt ? new Date(document.updatedAt) : new Date(),
      changeFrequency: "monthly" as const,
      priority: 0.4,
    })),
    ...articles.map((article) => ({
      url: `${siteConfig.url}${articleHref(article)}`,
      lastModified: article.publishedAt
        ? new Date(article.publishedAt)
        : new Date(),
      changeFrequency: "weekly" as const,
      priority: 0.7,
    })),
  ];
}
