import {
  ARTICLE_TEMPLATES,
  type AlbumReviewData,
  type ArticleCard,
  type ArticleTemplate,
  type ArticleType,
  type CmsPayload,
  type EditorialContent,
  type InterviewData,
  type RichTextDoc,
  type SpotlightData,
  type SpotlightEntity,
  type SpotlightWidget,
  type TemplateData,
} from "@/lib/editorial/types";

export const ARTICLE_TYPE_LABEL: Record<ArticleType, string> = {
  review: "Album review",
  news: "News",
  feature: "Feature",
  interview: "Interview",
  spotlight: "Artist spotlight",
};

export function articleTypeLabel(type: string) {
  return ARTICLE_TYPE_LABEL[type as ArticleType] ?? type;
}

// send folks to the desk that matches the piece
export function tagHref(tag: { slug: string }) {
  return `/tags/${tag.slug}`;
}

export function articleHref(article: { type: string; slug: string }) {
  if (article.type === "review") return `/reviews/${article.slug}`;
  if (article.type === "spotlight") return `/spotlights/${article.slug}`;
  return `/news/${article.slug}`;
}

export const TEMPLATE_META: Record<
  ArticleTemplate,
  { label: string; blurb: string; type: ArticleType }
> = {
  standard: {
    label: "Standard",
    blurb: "News, features, and most desk pieces.",
    type: "news",
  },
  album_review: {
    label: "Album review",
    blurb: "Score, artwork, and a verdict up top.",
    type: "review",
  },
  interview: {
    label: "Interview",
    blurb: "Portrait and subject fields, then Q&A.",
    type: "interview",
  },
  artist_spotlight: {
    label: "Artist spotlight",
    blurb: "Image-forward intro for an artist.",
    type: "spotlight",
  },
};

export const emptyAlbum = (): AlbumReviewData => ({
  album: "",
  artist: "",
  releaseDate: "",
  rating: "",
  verdict: "",
  artworkUrl: "",
  label: "",
  scene: "",
  badge: "",
});

export const emptyInterview = (): InterviewData => ({
  interviewee: "",
  role: "",
  portraitUrl: "",
  location: "",
  interviewDate: "",
});

export const emptySpotlight = (): SpotlightData => ({
  artist: "",
  portraitUrl: "",
  location: "",
  scene: "",
  widgets: [],
});

export function emptyTemplateData(): TemplateData {
  return {
    ...emptyAlbum(),
    ...emptyInterview(),
    ...emptySpotlight(),
  };
}

export function emptyDoc(): RichTextDoc {
  return { type: "doc", content: [{ type: "paragraph" }] };
}

export function createCmsPayload(template: ArticleTemplate = "standard"): CmsPayload {
  return {
    type: "cms",
    template,
    templateData: emptyTemplateData(),
    doc: emptyDoc(),
  };
}

// dump the tiptap doc into the content blob the api already knows
export function packContent(payload: CmsPayload): EditorialContent {
  return {
    version: 1,
    blocks: payload.doc.content ?? [],
  };
}

function asTemplate(value: unknown): ArticleTemplate {
  return ARTICLE_TEMPLATES.includes(value as ArticleTemplate)
    ? (value as ArticleTemplate)
    : "standard";
}

// pull a tiptap doc outta whatever we stuffed in blocks
export function unpackDoc(content: unknown): RichTextDoc {
  if (!content || typeof content !== "object") return emptyDoc();
  const raw = content as { blocks?: unknown[] };
  const blocks = Array.isArray(raw.blocks) ? raw.blocks : [];
  const first = blocks[0];

  if (first && typeof first === "object") {
    const block = first as {
      type?: string;
      doc?: RichTextDoc;
      content?: unknown[];
    };
    if (block.type === "cms" && block.doc?.type === "doc") return block.doc;
    if (block.type === "doc") return { type: "doc", content: block.content ?? [] };
  }

  if (blocks.length === 0) return emptyDoc();
  return { type: "doc", content: blocks };
}

// article row + content json → what the editor/renderer actually uses
export function unpackArticle(article: {
  content?: unknown;
  template?: ArticleTemplate | string;
  templateData?: Partial<TemplateData> | Record<string, unknown> | null;
}): CmsPayload {
  const content = article.content as { blocks?: unknown[] } | undefined;
  const first = Array.isArray(content?.blocks) ? content.blocks[0] : null;
  const legacy =
    first && typeof first === "object" && (first as { type?: string }).type === "cms"
      ? (first as CmsPayload)
      : null;

  const templateData: TemplateData = {
    ...emptyTemplateData(),
    ...(legacy?.templateData ?? {}),
    ...(article.templateData ?? {}),
  };
  templateData.widgets = parseWidgets(templateData);

  return {
    type: "cms",
    template: asTemplate(article.template ?? legacy?.template),
    templateData,
    doc: unpackDoc(article.content),
  };
}

export function slugify(value: string) {
  return value
    .toLowerCase()
    .trim()
    .replace(/['"]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 80);
}

type WalkNode = {
  type?: string;
  text?: string;
  attrs?: { credit?: string; caption?: string; src?: string };
  content?: WalkNode[];
};

export function collectImageCredits(doc: RichTextDoc, coverCredit?: string | null) {
  const credits: string[] = [];
  if (coverCredit) credits.push(coverCredit);

  function walk(nodes: WalkNode[] | undefined) {
    for (const node of nodes ?? []) {
      if (node.type === "image" && node.attrs?.credit) {
        credits.push(node.attrs.credit);
      }
      walk(node.content);
    }
  }

  walk(doc.content as WalkNode[] | undefined);
  return [...new Set(credits.filter(Boolean))];
}

export function wordCount(doc: RichTextDoc) {
  let count = 0;
  function walk(nodes: WalkNode[] | undefined) {
    for (const node of nodes ?? []) {
      if (node.text) count += node.text.trim().split(/\s+/).filter(Boolean).length;
      walk(node.content);
    }
  }
  walk(doc.content as WalkNode[] | undefined);
  return count;
}

export function parseWidgets(data: TemplateData | Record<string, unknown> | undefined): SpotlightWidget[] {
  const raw = (data as { widgets?: unknown } | undefined)?.widgets;
  if (!Array.isArray(raw)) return [];
  const out: SpotlightWidget[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const w = item as Partial<SpotlightWidget> & { type?: string; id?: string };
    if (!w.id || !w.type) continue;
    if (w.type === "essential_tracks") {
      out.push({ id: w.id, type: "essential_tracks", items: parseEntities((w as { items?: unknown }).items) });
    } else if (w.type === "if_you_like") {
      out.push({
        id: w.id,
        type: "if_you_like",
        artistName: String((w as { artistName?: string }).artistName ?? ""),
        items: parseEntities((w as { items?: unknown }).items),
      });
    } else if (w.type === "watch") {
      out.push({
        id: w.id,
        type: "watch",
        youtubeUrl: String((w as { youtubeUrl?: string }).youtubeUrl ?? ""),
        caption: String((w as { caption?: string }).caption ?? ""),
      });
    } else if (w.type === "featured_on_niche") {
      const featured = w as {
        editorialId?: string;
        editorial_id?: string;
        slug?: string;
      };
      out.push({
        id: w.id,
        type: "featured_on_niche",
        editorialId: String(featured.editorialId ?? featured.editorial_id ?? ""),
        slug: String(featured.slug ?? ""),
      });
    }
  }
  return out;
}

function parseEntities(raw: unknown): SpotlightEntity[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .filter((row) => row && typeof row === "object" && (row as { id?: string }).id)
    .map((row) => {
      const item = row as Record<string, string | null | undefined>;
      return {
        id: String(item.id),
        title: String(item.title ?? ""),
        subtitle: item.subtitle ? String(item.subtitle) : undefined,
        cover: item.cover ?? null,
        href: item.href ?? null,
        blurb: item.blurb ? String(item.blurb) : "",
      };
    })
    .slice(0, 5);
}

export function youtubeId(url: string) {
  if (!url.trim()) return "";
  try {
    const parsed = new URL(url.trim());
    if (parsed.hostname.includes("youtu.be")) {
      return parsed.pathname.replace(/^\//, "").split("/")[0] ?? "";
    }
    const v = parsed.searchParams.get("v");
    if (v) return v;
    const parts = parsed.pathname.split("/").filter(Boolean);
    const embed = parts.indexOf("embed");
    if (embed >= 0) return parts[embed + 1] ?? "";
    const shorts = parts.indexOf("shorts");
    if (shorts >= 0) return parts[shorts + 1] ?? "";
  } catch {
    return "";
  }
  return "";
}

// live cover for featured cards so writers dont paste a stale image
export function editorialHero(article: ArticleCard) {
  const data = (article.templateData ?? {}) as Partial<TemplateData>;
  return article.coverImageUrl || data.artworkUrl || data.portraitUrl || null;
}

function sizedShareImage(url: string) {
  return url
    .replaceAll("{w}x{h}", "1200x630")
    .replaceAll("{w}", "1200")
    .replaceAll("{h}", "1200");
}

// og/twitter image — reviews get art, spotlights get the face
export function articleShareImage(article: ArticleCard) {
  const data = (article.templateData ?? {}) as Partial<TemplateData>;
  const template = article.template;
  let url: string | null = null;

  if (template === "album_review" || article.type === "review") {
    url = data.artworkUrl || article.coverImageUrl || null;
  } else if (template === "artist_spotlight" || article.type === "spotlight") {
    url = data.portraitUrl || article.coverImageUrl || null;
  } else if (template === "interview") {
    url = data.portraitUrl || article.coverImageUrl || null;
  } else {
    url = article.coverImageUrl || data.artworkUrl || data.portraitUrl || null;
  }

  return url ? sizedShareImage(url) : null;
}
