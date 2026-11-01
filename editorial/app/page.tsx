import { HomeView } from "@/components/home/HomeView";
import { Navbar } from "@/components/Navbar";
import { getEditorialHome } from "@/lib/editorial/public";
import { buildPageMetadata, siteConfig } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: siteConfig.title,
  description: siteConfig.editorialDescription,
  path: "/",
});

export default async function Home() {
  const home = await getEditorialHome();

  return (
    <>
      <Navbar />
      <main className="page-main page-main--flush">
        <HomeView data={home} />
      </main>
    </>
  );
}
