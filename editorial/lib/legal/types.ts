export const LEGAL_DB_SLUGS = [
  "terms",
  "privacy",
  "eula",
  "artist-agreement",
  "guidelines",
  "standards",
] as const;

export type LegalDbSlug = (typeof LEGAL_DB_SLUGS)[number];

export type LegalDocument = {
  id: string;
  slug: LegalDbSlug | string;
  version: string;
  title: string;
  content: string;
  isActive: boolean;
  effectiveAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export const LEGAL_PAGES = [
  { slug: "terms", path: "/terms", label: "Terms of Service" },
  { slug: "privacy", path: "/privacy", label: "Privacy Policy" },
  { slug: "eula", path: "/eula", label: "EULA" },
  { slug: "artist-agreement", path: "/artist-agreement", label: "Artist Agreement" },
  { slug: "guidelines", path: "/guidelines", label: "Community Guidelines" },
  { slug: "standards", path: "/standards", label: "Editorial Standards" },
] as const;

export function legalPath(slug: string) {
  return LEGAL_PAGES.find((page) => page.slug === slug)?.path ?? `/${slug}`;
}
