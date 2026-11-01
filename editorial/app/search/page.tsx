import { Navbar } from "@/components/Navbar";
import { SearchView } from "@/components/search/SearchView";
import { searchPublishedEditorials } from "@/lib/editorial/public";
import { buildPageMetadata } from "@/lib/site";

type PageProps = {
  searchParams: Promise<{ q?: string }>;
};

export async function generateMetadata({ searchParams }: PageProps) {
  const { q } = await searchParams;
  const query = q?.trim();
  return buildPageMetadata({
    title: query ? `Search: ${query}` : "Search",
    description: "Search Niche Music articles, writers, and tags.",
    path: query ? `/search?q=${encodeURIComponent(query)}` : "/search",
  });
}

export default async function SearchPage({ searchParams }: PageProps) {
  const { q } = await searchParams;
  const query = (q ?? "").trim();
  const results = query
    ? await searchPublishedEditorials(query)
    : { query: "", articles: [], writers: [], tags: [] };

  return (
    <>
      <Navbar />
      <SearchView initialQuery={query} initialResults={results} />
    </>
  );
}
