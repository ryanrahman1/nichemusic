import { NextResponse } from "next/server";
import { listFeedArticles } from "@/lib/editorial/public";
import { buildArticlesRss } from "@/lib/editorial/rss";

// cache the xml for an hour, rebuild in the background after that
export const revalidate = 3600;

export async function GET() {
  try {
    const { articles } = await listFeedArticles(50);
    const xml = buildArticlesRss(articles);

    return new NextResponse(xml, {
      headers: {
        "Content-Type": "application/rss+xml; charset=utf-8",
        "Cache-Control": "public, s-maxage=3600, stale-while-revalidate=86400",
      },
    });
  } catch {
    return new NextResponse("Could not build the feed", { status: 500 });
  }
}
