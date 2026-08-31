import type { ArticleCard, ArticleCredit, PublicWriter } from "@/lib/editorial/types";

// pull the lead writer credit off an article card
export function primaryWriterCredit(article: ArticleCard) {
  return (article.credits ?? []).find((credit) => credit.creditType === "writer");
}

// map db roles to the short desk badge copy
export function writerRoleLabel(role: string | null | undefined) {
  if (!role) return "";
  if (role === "contributor") return "Contributor";
  if (role === "verified") return "Verified";
  if (role === "senior") return "Senior";
  if (role === "editor") return "Editor";
  if (role === "admin") return "Admin";
  return role;
}

export function writerDisplayName(credit: ArticleCredit | undefined) {
  if (!credit?.writer) return "";
  return (
    credit.writer.profile?.displayName ||
    credit.writer.profile?.username ||
    credit.writer.slug
  );
}

// public writer page name — desk name first then app name
export function publicWriterName(writer: PublicWriter) {
  return (
    writer.displayName ||
    writer.profile?.displayName ||
    writer.profile?.username ||
    writer.slug
  );
}

export function writerAppHref(username: string | null | undefined) {
  if (!username) return "";
  return `https://open.nichemusic.app/u/${encodeURIComponent(username)}`;
}

// your own face goes to /profile, not the public writer url
export function writerProfileHref({
  profileId,
  slug,
  selfId,
}: {
  profileId?: string | null;
  slug?: string | null;
  selfId?: string | null;
}) {
  if (selfId && profileId && selfId === profileId) return "/profile";
  return slug ? `/writers/${slug}` : "";
}
