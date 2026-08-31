"use client";

import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function RootError({
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Error"
          title="The desk hit a snag."
          body="Something on this page failed to load. Refresh and if it’s still busted, come back in a minute."
          actions={[
            { href: "/", label: "Home" },
            { href: "/search", label: "Search" },
          ]}
        />
        <button type="button" className="cta-download" onClick={() => reset()} style={{ marginInline: "var(--gutter)", marginBottom: "var(--space-16)" }}>
          Try again
        </button>
      </StatusPage>
    </>
  );
}
