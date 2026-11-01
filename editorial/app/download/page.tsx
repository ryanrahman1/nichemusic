import { Navbar } from "@/components/Navbar";
import { DownloadView } from "@/components/download/DownloadView";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Download",
  description:
    "Download Niche Music on iOS, macOS, Windows, or use the web app. Discover underground artists on any platform.",
  path: "/download",
});

export default function DownloadPage() {
  return (
    <>
      <Navbar />
      <main className="page-main">
        <DownloadView />
      </main>
    </>
  );
}
