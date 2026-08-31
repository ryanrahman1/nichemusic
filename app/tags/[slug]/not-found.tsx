import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function TagNotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Tag"
          title="No tag by that name."
          body="Wrong slug, or nobody’s used it on a published piece yet. Search the archive."
          actions={[
            { href: "/search", label: "Search" },
            { href: "/", label: "Home" },
          ]}
        />
      </StatusPage>
    </>
  );
}
