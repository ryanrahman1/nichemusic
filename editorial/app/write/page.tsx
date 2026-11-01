import { redirect } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { WriteHome } from "@/components/editor/WriteHome";
import { loadOnboardingProfile, loadSession, loadWriterWorkspace } from "@/lib/editorial/server";

export default async function WriteIndexPage() {
  const session = await loadSession();
  if (!session) redirect("/login");

  const workspace = await loadWriterWorkspace();
  if (!workspace) redirect("/login");
  const profile = workspace.writer ? null : await loadOnboardingProfile();

  return (
    <>
      <Navbar />
      <WriteHome initial={workspace} onboardingProfile={profile} />
    </>
  );
}
