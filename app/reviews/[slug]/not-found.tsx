import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function ReviewNotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Review"
          title="No review at this slug."
          body="It might still be in the queue, or the url is stale. The live scores are on the reviews desk."
          actions={[
            { href: "/reviews", label: "All reviews" },
            { href: "/search", label: "Search" },
          ]}
        />
      </StatusPage>
    </>
  );
}
