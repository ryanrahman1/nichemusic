import type { Metadata } from "next";
import { notFound } from "next/navigation";
import { LegalDocumentView } from "@/components/legal/LegalDocumentView";
import { getLegalDocument } from "@/lib/legal/public";
import { legalPath, type LegalDbSlug, type LegalDocument } from "@/lib/legal/types";
import { buildPageMetadata } from "@/lib/site";

function legalBlurb(document: LegalDocument) {
  const text = document.content
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/[#>*_`~\[\]]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  if (text.length < 40) return `${document.title} for Niche Music.`;
  const cut = text.slice(0, 170);
  const end = cut.lastIndexOf(" ");
  return `${end > 80 ? cut.slice(0, end) : cut}…`;
}

// 404 if that slug aint live yet
export async function loadLegalDocument(slug: LegalDbSlug) {
  try {
    const { document } = await getLegalDocument(slug);
    return document;
  } catch {
    notFound();
  }
}

export async function legalMetadata(slug: LegalDbSlug, fallbackTitle: string): Promise<Metadata> {
  try {
    const { document } = await getLegalDocument(slug);
    return buildPageMetadata({
      title: document.title,
      description: legalBlurb(document),
      path: legalPath(document.slug),
    });
  } catch {
    return buildPageMetadata({
      title: fallbackTitle,
      description: `${fallbackTitle} for Niche Music.`,
      path: legalPath(slug),
    });
  }
}

export async function LegalRoutePage({ slug }: { slug: LegalDbSlug }) {
  const document = await loadLegalDocument(slug);
  return <LegalDocumentView document={document} />;
}
