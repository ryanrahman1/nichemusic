import Link from "next/link";
import { redirect } from "next/navigation";
import { Navbar } from "@/components/Navbar";
import { WriterProfileView } from "@/components/editorial/WriterProfileView";
import { CoverImage } from "@/components/home/CoverImage";
import { getPublicWriterPage } from "@/lib/editorial/public";
import { loadSession, loadWriterWorkspace } from "@/lib/editorial/server";
import type { PublicWriter, WriterProfile } from "@/lib/editorial/types";
import { writerAppHref } from "@/lib/editorial/writers";
import { buildPageMetadata } from "@/lib/site";
import styles from "@/components/editorial/writer-profile.module.css";

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
  const writer = workspace?.writer ?? null;

  if (writer) {
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

  const name = session.user.username || session.user.email;
  const appHref = writerAppHref(session.user.username);

  return (
    <>
      <Navbar />
      <main className={styles.page}>
        <section className={styles.hero}>
          <div className={styles.portrait}>
            {session.user.avatarUrl ? (
              <CoverImage src={session.user.avatarUrl} alt={name} sizes="420px" priority />
            ) : (
              <span className={styles.initials} aria-hidden>
                {(name[0] ?? "?").toUpperCase()}
              </span>
            )}
          </div>
          <div className={styles.intro}>
            <p className={styles.handle}>
              {session.user.username ? `@${session.user.username}` : session.user.email}
            </p>
            <h1>Your profile.</h1>
            <p className={styles.bio}>
              This is you on Niche. Become a writer to publish on the desk, or open the app profile.
            </p>
            <div className={styles.actions}>
              <Link href="/write" className="underline-link underline-link--action">
                Become a writer
              </Link>
              {appHref ? (
                <a
                  href={appHref}
                  className="underline-link underline-link--action"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  View profile in app ↗
                </a>
              ) : null}
            </div>
          </div>
        </section>
      </main>
    </>
  );
}
