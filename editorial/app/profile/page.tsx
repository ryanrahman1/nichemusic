import { redirect } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { WriterProfileView } from "@/components/editorial/WriterProfileView";
import { getPublicWriterPage } from "@/lib/editorial/public";
import { loadSession, loadWriterWorkspace } from "@/lib/editorial/server";
import type { PublicWriter, WriterProfile } from "@/lib/editorial/types";
import { buildPageMetadata } from "@/lib/site";

export const metadata = buildPageMetadata({
  title: "Your profile",
  description: "Your Niche Music profile.",
  path: "/profile",
  noIndex: true,
});

function asPublicWriter(writer: WriterProfile): PublicWriter {
  return {
    id: writer.id,
    slug: writer.slug,
    role: writer.role,
    bio: writer.bio,
    displayName: writer.displayName,
    specialties: writer.specialties,
    location: writer.location,
    joinedAt: writer.joinedAt ?? "",
    stats: writer.stats ?? {
      publishedCount: 0,
      editedCount: 0,
      followersCount: 0,
      totalViews: 0,
      qualifiedReads: 0,
    },
    profile: writer.profile,
  };
}

export default async function ProfilePage() {
  const session = await loadSession();
  if (!session) redirect("/login");

  const workspace = await loadWriterWorkspace();
  if (!workspace) redirect("/login");

  const writer = workspace.writer;
  if (!writer) redirect("/write");

  let page;
  try {
    page = await getPublicWriterPage(writer.slug);
  } catch {
    page = { writer: asPublicWriter(writer), articles: [] };
  }

  return (
    <>
      <Navbar />
      <WriterProfileView self writer={page.writer} articles={page.articles} />
    </>
  );

}
