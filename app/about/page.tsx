import { AboutView, type CollagePiece } from "@/components/about/AboutView";
import { Navbar } from "@/components/Navbar";
import { articleHref, editorialHero } from "@/lib/editorial/cms";
import { getEditorialHome, listPublishedArticles } from "@/lib/editorial/public";
import type { ArticleCard } from "@/lib/editorial/types";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "About",
  description:
    "Niche is for finding music before everyone else — a publication and a scene, not another algorithm.",
  path: "/about",
});

export default async function AboutPage() {
  const [home, { articles }] = await Promise.all([
    getEditorialHome(),
    listPublishedArticles(12),
  ]);

  const collage: CollagePiece[] = [];

  const desk = [home.hero, ...home.featured, ...articles].filter(
    (item): item is ArticleCard => !!item,
  );

  for (const article of desk) {
    if (collage.some((item) => item.id === article.id)) continue;
    collage.push({
      id: article.id,
      kind: article.type === "review" ? "review" : "story",
      title: article.title,
      meta: article.type,
      image: editorialHero(article),
      href: articleHref(article),
    });
    if (collage.length >= 8) break;
  }

  for (const pick of home.newMusic) {
    collage.push({
      id: pick.track.id,
      kind: "track",
      title: pick.track.name || "Untitled",
      meta: pick.track.artist?.name || "New music",
      image: pick.track.artworkUrl,
    });
    if (collage.length >= 12) break;
  }

  return (
    <>
      <Navbar />
      <AboutView collage={collage} />
    </>
  );
}
