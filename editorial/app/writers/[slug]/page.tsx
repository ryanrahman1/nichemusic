import { notFound, redirect } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { WriterProfileView } from "@/components/editorial/WriterProfileView";
import { getPublicWriterPage } from "@/lib/editorial/public";
import { loadSession } from "@/lib/editorial/server";
import { publicWriterName } from "@/lib/editorial/writers";
import { buildPageMetadata, siteConfig } from "@/lib/site";

type PageProps = {
  params: Promise<{ slug: string }>;
};

// pull the public writer page or 404
async function loadWriterPage(slug: string) {
  try {
    return await getPublicWriterPage(slug);
  } catch {
    notFound();
  }
}

export async function generateMetadata({ params }: PageProps) {
  const { slug } = await params;
  try {
    const { writer } = await getPublicWriterPage(slug);
    const name = publicWriterName(writer);
    return buildPageMetadata({
      title: name,
      description: writer.bio || `${name} writes for ${siteConfig.name}.`,
      path: `/writers/${writer.slug}`,
    });
  } catch {
    return buildPageMetadata({
      title: "Writer",
      description: `Writers at ${siteConfig.name}.`,
      path: `/writers/${slug}`,
    });
  }
}

export default async function WriterPage({ params }: PageProps) {
  const { slug } = await params;
  const { writer, articles } = await loadWriterPage(slug);
  const session = await loadSession();
  if (session?.user.id && writer.profile?.id === session.user.id) {
    redirect("/profile");
  }

  return (
    <>
      <Navbar />
      <WriterProfileView writer={writer} articles={articles} />
    </>
  );
}
