import type { LegalDocument } from "@/lib/legal/types";

function prettyDate(value: string | null | undefined) {
  if (!value) return "";
  return new Date(value).toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
}

// drop a matching leading h1 so we dont double the title
function bodyWithoutTitle(content: string, title: string) {
  const trimmed = content.trim();
  const heading = new RegExp(
    `^#\\s+${title.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\s*`,
    "i",
  );
  return trimmed.replace(heading, "").replace(/^\n+/, "");
}

// title as markdown h1, then the updated / effective line like the old site
export function legalMarkdown(document: LegalDocument) {
  const updated = prettyDate(document.updatedAt);
  const effective = prettyDate(document.effectiveAt);
  const meta = [
    document.version ? `Version ${document.version}` : "",
    updated ? `Updated at ${updated}` : "",
    effective ? `Effective from ${effective}` : "",
  ]
    .filter(Boolean)
    .join(" · ");

  const body = normalizeHeadings(bodyWithoutTitle(document.content, document.title));
  return [`# ${document.title}`, meta, body].filter(Boolean).join("\n\n");
}

// turn "1\\. Title\\n----" into a real h2 so it stays smaller than lettered h3s
function normalizeHeadings(content: string) {
  return content.replace(
    /^(\d+)\\\.\s+(.+)\n[-=]{3,}\s*$/gm,
    "## $1. $2",
  );
}
