import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function ArticleNotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Article"
          title="That piece isn’t up."
          body="Unpublished, moved, or it never ran. Search the archive or browse what’s live."
          actions={[
            { href: "/search", label: "Search" },
            { href: "/news", label: "News" },
            { href: "/reviews", label: "Reviews" },
          ]}
        />
      </StatusPage>
    </>
  );
}
