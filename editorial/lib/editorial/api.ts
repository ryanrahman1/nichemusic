import { apiRequest } from "@/lib/api/client";
import { Endpoints } from "@/lib/api/endpoints";
import type {
  AdminNewMusicPick,
  ArticleCard,
  ArticleTag,
  ArticleType,
  DeskAnalytics,
  EditorialContent,
  EditorialSearch,
  PresignedUpload,
  PublicWriter,
  WriterAnalytics,
  WriterPermissions,
  WriterProfile,
  WriterWorkspace,
} from "@/lib/editorial/types";

const emptyPerms = (): WriterPermissions => ({
  canWrite: false,
  canSubmit: false,
  canReview: false,
  canPublish: false,
  canManageWriters: false,
  canEditAny: false,
  canDelete: false,
});

export async function getWriterWorkspace() {
  const data = await apiRequest<Partial<WriterWorkspace>>(
    Endpoints.editorialMeWorkspace,
  );

  return {
    writer: data.writer ?? null,
    permissions: { ...emptyPerms(), ...data.permissions },
    articles: data.articles ?? [],
    queue: data.queue ?? [],
    catalog: data.catalog ?? [],
  } satisfies WriterWorkspace;
}

export async function getMyWriter() {
  const data = await apiRequest<{
    writer: WriterProfile | null;
    permissions?: Partial<WriterPermissions>;
  }>(Endpoints.editorialMe);

  return {
    writer: data.writer,
    permissions: { ...emptyPerms(), ...data.permissions },
  };
}

export async function createWriterOnboarding(body: {
  slug: string;
  bio: string;
  displayName?: string;
  specialties?: string[];
  location?: string | null;
}) {
  return apiRequest<{ writer: WriterProfile }>(Endpoints.editorialWriterCreate, {
    method: "POST",
    body,
  });
}

export async function listMyArticles() {
  return apiRequest<{ articles: ArticleCard[] }>(Endpoints.editorialMyArticles);
}

export async function createDraft(body: {
  title: string;
  slug: string;
  type: ArticleType;
  template?: string;
  templateData?: Record<string, unknown>;
}) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialMyArticles, {
    method: "POST",
    body,
  });
}

export async function getMyArticle(id: string) {
  return apiRequest<{ article: ArticleCard }>(
    Endpoints.editorialMyArticle(id),
  );
}

export type UpdateArticleBody = {
  title?: string;
  slug?: string;
  subtitle?: string | null;
  excerpt?: string | null;
  content?: EditorialContent;
  template?: string;
  templateData?: Record<string, unknown>;
  coverImageUrl?: string | null;
  coverImageAlt?: string | null;
  coverImageCredit?: string | null;
  tagSlugs?: string[];
  metaTitle?: string | null;
  metaDescription?: string | null;
};

export async function updateMyArticle(id: string, body: UpdateArticleBody) {
  return apiRequest<{ article: ArticleCard }>(
    Endpoints.editorialUpdateArticle(id),
    { method: "POST", body },
  );
}

export async function submitMyArticle(id: string) {
  return apiRequest<{ article: ArticleCard }>(
    Endpoints.editorialSubmitArticle(id),
    { method: "POST", body: {} },
  );
}

export async function publishMyArticle(id: string) {
  return apiRequest<{ article: ArticleCard }>(
    Endpoints.editorialPublishArticle(id),
    { method: "POST", body: {} },
  );
}

export async function listReviewQueue() {
  return apiRequest<{ submissions: ArticleCard[] }>(
    Endpoints.editorialAdminSubmissions,
    { query: { status: "all", limit: 50 } },
  );
}

export async function listDeskArticles() {
  return apiRequest<{ articles: ArticleCard[] }>(
    Endpoints.editorialAdminArticles,
    { query: { status: "all", limit: 50 } },
  );
}

export async function getDeskArticle(id: string) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialAdminArticle(id));
}

export async function updateDeskArticle(id: string, body: UpdateArticleBody) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialAdminUpdate(id), {
    method: "POST",
    body,
  });
}

export async function publishDeskArticle(id: string) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialAdminPublish(id), {
    method: "POST",
    body: {},
  });
}

export async function deleteDeskArticle(id: string) {
  return apiRequest<{ id: string; deleted: boolean }>(
    Endpoints.editorialAdminDelete(id),
    { method: "POST", body: {} },
  );
}

export async function checkArticleSlug(
  slug: string,
  type: ArticleType,
  excludeArticleId?: string,
) {
  return apiRequest<{ slug: string; available: boolean }>(
    Endpoints.editorialSlugCheck,
    { query: { slug, type, excludeArticleId } },
  );
}

export async function presignEditorialMedia(
  editorialId: string,
  format: "jpeg" | "webp" | "png" | "avif" = "webp",
) {
  return apiRequest<{ editorialId: string; upload: PresignedUpload }>(
    Endpoints.editorialMediaUpload,
    { method: "POST", body: { editorialId, format } },
  );
}

export async function uploadEditorialFile(
  editorialId: string,
  file: File,
) {
  const format = file.type.includes("png")
    ? "png"
    : file.type.includes("jpeg") || file.type.includes("jpg")
      ? "jpeg"
      : file.type.includes("avif")
        ? "avif"
        : "webp";

  const { upload } = await presignEditorialMedia(editorialId, format);
  if (file.size > upload.maxBytes) {
    throw new Error("That image is too large");
  }

  const put = await fetch(upload.uploadUrl, {
    method: "PUT",
    headers: { "Content-Type": upload.contentType },
    body: file,
  });

  if (!put.ok) {
    throw new Error("Couldnt upload that image");
  }

  return upload.publicUrl;
}

export type MusicSearchHit = {
  id: string;
  title: string;
  subtitle?: string;
  cover?: string | null;
  kind: "track" | "artist" | "album";
  href?: string | null;
};

type NestedArtist = { name?: string; image_url?: string | null };

type SearchRow = {
  id?: string;
  title?: string;
  name?: string;
  displayName?: string;
  display_name?: string;
  artistName?: string;
  artist?: string | NestedArtist | null;
  artwork_url?: string | null;
  artworkUrl?: string | null;
  coverUrl?: string | null;
  cover_url?: string | null;
  imageUrl?: string | null;
  image_url?: string | null;
  avatarUrl?: string | null;
  source?: string | null;
  sourceId?: string | null;
  source_id?: string | null;
};

type AppleArt = { url?: string | null };
type AppleItem = {
  id?: string;
  attributes?: {
    name?: string | null;
    artistName?: string | null;
    artwork?: AppleArt | null;
  } | null;
};

type AppleSearchResult = {
  data?: {
    results?: {
      songs?: { data?: AppleItem[] | null } | null;
      artists?: { data?: AppleItem[] | null } | null;
    } | null;
  } | null;
};

function sizedArt(url: string | null | undefined, size = 200) {
  if (!url) return null;
  return url
    .replaceAll("{w}x{h}", `${size}x${size}`)
    .replaceAll("{w}", String(size))
    .replaceAll("{h}", String(size));
}

function nestedName(artist: SearchRow["artist"]) {
  if (!artist) return undefined;
  if (typeof artist === "string") return artist;
  return artist.name || undefined;
}

function rowCover(row: SearchRow) {
  const nested = typeof row.artist === "object" && row.artist ? row.artist.image_url : null;
  return sizedArt(
    row.artwork_url ??
      row.artworkUrl ??
      row.coverUrl ??
      row.cover_url ??
      row.imageUrl ??
      row.image_url ??
      row.avatarUrl ??
      nested,
  );
}

function catalogHref(kind: MusicSearchHit["kind"], sourceId: string, from: "niche" | "catalog") {
  if (kind === "artist") {
    return `https://open.nichemusic.app/artists/apple/${encodeURIComponent(sourceId)}`;
  }
  if (kind === "album") {
    return from === "niche"
      ? `https://open.nichemusic.app/albums/niche/${encodeURIComponent(sourceId)}`
      : `https://open.nichemusic.app/albums/apple/${encodeURIComponent(sourceId)}`;
  }
  return from === "niche"
    ? `https://open.nichemusic.app/tracks/${encodeURIComponent(sourceId)}`
    : `https://open.nichemusic.app/tracks/apple/${encodeURIComponent(sourceId)}`;
}

function pushRows(
  hits: MusicSearchHit[],
  items: SearchRow[] | undefined,
  kind: MusicSearchHit["kind"],
  from: "niche" | "catalog",
) {
  for (const item of items ?? []) {
    const title = item.title || item.name || item.displayName || item.display_name || "";
    if (!item.id || !title) continue;
    const sourceId = String(item.sourceId || item.source_id || item.id);
    hits.push({
      id: item.id,
      title,
      subtitle: item.artistName || nestedName(item.artist),
      cover: rowCover(item),
      kind,
      href: catalogHref(kind, sourceId, from),
    });
  }
}

function pushApple(
  hits: MusicSearchHit[],
  items: AppleItem[] | null | undefined,
  kind: "track" | "artist",
) {
  for (const item of items ?? []) {
    const title = item.attributes?.name?.trim() || "";
    if (!item.id || !title) continue;
    hits.push({
      id: item.id,
      title,
      subtitle: item.attributes?.artistName || undefined,
      cover: sizedArt(item.attributes?.artwork?.url),
      kind,
      href: catalogHref(kind, item.id, "catalog"),
    });
  }
}

export async function searchMusic(
  q: string,
  kind: "track" | "artist" = "track",
): Promise<MusicSearchHit[]> {
  const appleTypes = kind === "artist" ? "artists" : "songs";
  const hits: MusicSearchHit[] = [];

  const apple = apiRequest<AppleSearchResult>(Endpoints.appleSearch, {
    query: { q, types: appleTypes },
  })
    .then((data) => {
      const results = data.data?.results;
      if (kind === "artist") pushApple(hits, results?.artists?.data, "artist");
      else pushApple(hits, results?.songs?.data, "track");
    })
    .catch(() => undefined);

  const niche = apiRequest<{
    results?: {
      nicheTracks?: SearchRow[];
      tracks?: SearchRow[];
      artists?: SearchRow[];
    };
  }>(Endpoints.search, {
    query: {
      q,
      types: kind === "artist" ? "artists" : "tracks,nicheTracks",
      perTypeLimit: 8,
    },
  })
    .then((data) => {
      const results = data.results ?? {};
      if (kind === "artist") pushRows(hits, results.artists, "artist", "catalog");
      else {
        pushRows(hits, results.nicheTracks, "track", "niche");
        pushRows(hits, results.tracks, "track", "catalog");
      }
    })
    .catch(() => undefined);

  await Promise.all([apple, niche]);

  const seen = new Set<string>();
  const unique: MusicSearchHit[] = [];
  for (const hit of hits) {
    const key = `${hit.kind}:${hit.id}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(hit);
  }
  return unique.slice(0, 8);
}

// apple songs only — nmf board doesnt take niche uploads
export async function searchAppleSongs(q: string): Promise<MusicSearchHit[]> {
  const hits: MusicSearchHit[] = [];
  try {
    const data = await apiRequest<AppleSearchResult>(Endpoints.appleSearch, {
      query: { q, types: "songs" },
    });
    pushApple(hits, data.data?.results?.songs?.data, "track");
  } catch {
    return [];
  }
  return hits.slice(0, 8);
}

export async function listNewMusicPicks() {
  return apiRequest<{ picks: AdminNewMusicPick[] }>(Endpoints.editorialAdminNewMusic);
}

export async function addNewMusicPick(body: {
  appleSongId: string;
  editorialId?: string | null;
  showFrom?: string | null;
  showUntil?: string | null;
}) {
  return apiRequest<{ picks: AdminNewMusicPick[] }>(Endpoints.editorialAdminNewMusic, {
    method: "POST",
    body,
  });
}

export async function updateNewMusicPick(
  id: string,
  body: {
    editorialId?: string | null;
    showFrom?: string | null;
    showUntil?: string | null;
  },
) {
  return apiRequest<{ picks: AdminNewMusicPick[] }>(
    Endpoints.editorialAdminNewMusicUpdate(id),
    { method: "POST", body },
  );
}

export async function reorderNewMusicPicks(pickIds: string[]) {
  return apiRequest<{ picks: AdminNewMusicPick[] }>(
    Endpoints.editorialAdminNewMusicReorder,
    { method: "POST", body: { pickIds } },
  );
}

export async function deleteNewMusicPick(id: string) {
  return apiRequest<{ picks: AdminNewMusicPick[] }>(
    Endpoints.editorialAdminNewMusicDelete(id),
    { method: "POST" },
  );
}

function emptySearch(query = "", error?: string): EditorialSearch {
  return {
    query,
    articles: [],
    writers: [],
    tags: [],
    ...(error ? { error } : {}),
  };
}

export async function searchEditorials(q: string) {
  const data = await searchPublicEditorials(q, 8);
  return { query: data.query, articles: data.articles };
}

// live archive search from the browser, no full page bounce
export async function searchPublicEditorials(q: string, limit = 24) {
  const query = q.trim();
  if (query.length < 2) return emptySearch(query);

  try {
    const data = await apiRequest<{
      query?: string;
      articles?: ArticleCard[];
      writers?: PublicWriter[];
      tags?: ArticleTag[];
    }>(Endpoints.editorialSearch, { query: { q: query, limit } });

    return {
      query: data.query ?? query,
      articles: data.articles ?? [],
      writers: data.writers ?? [],
      tags: data.tags ?? [],
    };
  } catch (error) {
    console.error("[editorial] client search unavailable", error);
    return emptySearch(
      query,
      "Editorial search is temporarily unavailable. Try again in a moment.",
    );
  }
}

export async function trackArticleEngagement(
  articleId: string,
  body: {
    sessionId: string;
    referrer?: string | null;
    engagedSeconds: number;
    scrollDepth: number;
  },
) {
  return apiRequest<{
    tracked: boolean;
    skipped?: string;
    viewId?: string;
  }>(Endpoints.editorialArticleEngagement(articleId), {
    method: "POST",
    body,
  });
}

export async function getWriterAnalytics(days = 30) {
  const data = await apiRequest<{ analytics: WriterAnalytics }>(
    Endpoints.editorialMeAnalytics,
    { query: { days } },
  );
  return data.analytics;
}

export async function getDeskAnalytics(days = 30) {
  const data = await apiRequest<{ analytics: DeskAnalytics }>(
    Endpoints.editorialAdminAnalytics,
    { query: { days } },
  );
  return data.analytics;
}

export async function getPublishedEditorial(slug: string) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialArticle(slug));
}

export async function getEditorialById(id: string) {
  return apiRequest<{ article: ArticleCard }>(Endpoints.editorialArticleById(id));
}
