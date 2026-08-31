import { Navbar } from "@/components/Navbar";
import { StatusPage, StatusView } from "@/components/status/StatusView";

export default function WriterNotFound() {
  return (
    <>
      <Navbar />
      <StatusPage>
        <StatusView
          kicker="Writer"
          title="Nobody writes under that name."
          body="Wrong slug, or this writer isn’t public yet. Search the desk or go home."
          actions={[
            { href: "/search", label: "Search writers" },
            { href: "/", label: "Home" },
          ]}
        />
      </StatusPage>
    </>
  );
}
