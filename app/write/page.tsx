import { redirect } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { WriteHome } from "@/components/editor/WriteHome";
import { loadWriterWorkspace } from "@/lib/editorial/server";

export default async function WriteIndexPage() {
  const workspace = await loadWriterWorkspace();
  if (!workspace) redirect("/login");

  return (
    <>
      <Navbar />
      <WriteHome initial={workspace} />
    </>
  );
}
