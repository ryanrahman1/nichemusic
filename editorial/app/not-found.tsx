import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "404",
  description: "This page is not on Niche Music.",
  path: "/404",
  noIndex: true,
});

export default function NotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="404"
          title="This page isn’t on the site."
          body="Try searching for what you're looking for or head back to the homepage."
          actions={[
            { href: "/search", label: "Search" },
            { href: "/", label: "Home" },
            { href: "/news", label: "News" },
          ]}
        />
      </StatusPage>
    </>
  );
}
