import { articleHref, articleTypeLabel } from "@/lib/editorial/cms";
import type { ArticleCard } from "@/lib/editorial/types";
import { primaryWriterCredit, writerDisplayName } from "@/lib/editorial/writers";
import { siteConfig } from "@/lib/site";

function cdata(value: string) {
  return `<![CDATA[${value.replaceAll("]]>", "]]]]><![CDATA[>")}]]>`;
}

function absUrl(path: string) {
  return `${siteConfig.url}${path.startsWith("/") ? path : `/${path}`}`;
}

// turn the newest stack into a legit rss 2.0 blob
export function buildArticlesRss(articles: ArticleCard[]) {
  const latest = articles.find((article) => article.publishedAt)?.publishedAt;
  const builtAt = latest ? new Date(latest) : new Date();
  const feedUrl = absUrl("/feed.xml");

  const items = articles
    .map((article) => {
      const path = articleHref(article);
      const link = absUrl(path);
      const pubDate = article.publishedAt
        ? new Date(article.publishedAt).toUTCString()
        : "";
      const blurb = article.excerpt || article.subtitle || "";
      const author = writerDisplayName(primaryWriterCredit(article));

      return `
    <item>
      <title>${cdata(article.title)}</title>
      <link>${link}</link>
      <guid isPermaLink="true">${link}</guid>
      ${pubDate ? `<pubDate>${pubDate}</pubDate>` : ""}
      <category>${cdata(articleTypeLabel(article.type))}</category>
      ${author ? `<dc:creator>${cdata(author)}</dc:creator>` : ""}
      <description>${cdata(blurb)}</description>
    </item>`;
    })
    .join("");

  return `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>${cdata(siteConfig.name)}</title>
    <link>${siteConfig.url}</link>
    <description>${cdata(siteConfig.editorialDescription)}</description>
    <language>en-us</language>
    <lastBuildDate>${builtAt.toUTCString()}</lastBuildDate>
    <atom:link href="${feedUrl}" rel="self" type="application/rss+xml" />
    ${items}
  </channel>
</rss>
`;
}
