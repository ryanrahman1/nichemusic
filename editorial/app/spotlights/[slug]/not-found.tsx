import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function SpotlightNotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Spotlight"
          title="No spotlight here."
          body="This profile isn’t published, or the link aged out. See who the desk is covering now."
          actions={[
            { href: "/spotlights", label: "All spotlights" },
            { href: "/search", label: "Search" },
          ]}
        />
      </StatusPage>
    </>
  );
}
