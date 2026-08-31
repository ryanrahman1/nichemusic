import { Endpoints } from "@/lib/api/endpoints";
import type { ApiPagination } from "@/lib/api/types";
import type {
  ArticleCard,
  ArticleTag,
  ArticleType,
  EditorialHome,
  PublicWriter,
} from "@/lib/editorial/types";

type Envelope<T> = {
  success: boolean;
  result: T | null;
  error: { code?: string; message?: string } | null;
  metadata?: {
    pagination?: ApiPagination;
  };
};

export type EditorialListResult = {
  articles: ArticleCard[];
  nextCursor: string | null;
  hasMore: boolean;
  error?: string;
};

const editorialUnavailable =
  "Editorial content is temporarily unavailable. Try again in a moment.";

function apiOrigin() {
  return (
    process.env.API_PROXY_TARGET ||
    process.env.API_INTERNAL_URL ||
    "http://localhost:3932"
  );
}

async function publicGet<T>(
  path: string,
  query?: Record<string, string | number | undefined>,
  revalidate = 15,
): Promise<T> {
  const data = await publicGetEnvelope<T>(path, query, revalidate);
  return data.result as T;
}

async function publicGetEnvelope<T>(
  path: string,
  query?: Record<string, string | number | undefined>,
  revalidate = 15,
): Promise<Envelope<T>> {
  // keep the real failure visible in server logs
  try {
    const url = new URL(path, `${apiOrigin()}/`);
    if (query) {
      for (const [key, value] of Object.entries(query)) {
        if (value === undefined) continue;
        url.searchParams.set(key, String(value));
      }
    }

    const res = await fetch(url.toString(), {
      next: { revalidate },
      headers: { "x-requested-via": "nichewebapp" },
    });

    const data = (await res.json()) as Envelope<T>;
    if (!res.ok || !data?.success || !data.result) {
      throw new Error(data?.error?.message || `Request failed (${res.status})`);
    }
    return data;
  } catch (error) {
    console.error(`[editorial] public request failed: ${path}`, error);
    throw error;
  }
}

async function publicGetPage<T>(
  path: string,
  query?: Record<string, string | number | undefined>,
  revalidate = 15,
) {
  // pass cursor info through for when the archive gets bigger
  const envelope = await publicGetEnvelope<T>(path, query, revalidate);
  return {
    data: envelope.result as T,
    pagination: envelope.metadata?.pagination ?? {},
  };
}

const emptyHome = (error?: string): EditorialHome => ({
  hero: null,
  premiumPromo: null,
  featured: [],
  newMusic: [],
  promo: null,
  latest: [],
  ...(error ? { error } : {}),
});

// one call for the whole homepage board
export async function getEditorialHome() {
  try {
    return await publicGet<EditorialHome>(Endpoints.editorialHome);
  } catch (error) {
    console.error("[editorial] homepage unavailable", error);
    return emptyHome(editorialUnavailable);
  }
}

export async function listPublishedArticles(
  limit = 30,
  options?: {
    type?: ArticleType;
    sort?: "newest" | "oldest";
    tag?: string;
    cursor?: string;
  },
): Promise<EditorialListResult> {
  try {
    const page = await publicGetPage<{ articles: ArticleCard[] }>(
      Endpoints.editorialArticles,
      {
        limit,
        sort: options?.sort ?? "newest",
        type: options?.type,
        tag: options?.tag,
        cursor: options?.cursor,
      },
    );
    return {
      articles: page.data.articles,
      nextCursor: page.pagination.nextCursor ?? null,
      hasMore: page.pagination.hasMore ?? false,
    };
  } catch (error) {
    console.error("[editorial] article list unavailable", {
      error,
      type: options?.type,
      tag: options?.tag,
    });
    return {
      articles: [],
      nextCursor: null,
      hasMore: false,
      error: editorialUnavailable,
    };
  }
}

// rss only — let it throw so we dont cache an empty feed for an hour
export async function listFeedArticles(limit = 50) {
  const page = await publicGetPage<{ articles: ArticleCard[] }>(
    Endpoints.editorialArticles,
    { limit, sort: "newest" },
    3600,
  );
  return {
    articles: page.data.articles,
    nextCursor: page.pagination.nextCursor ?? null,
    hasMore: page.pagination.hasMore ?? false,
  };
}

// tag page payload — 404s if that slug aint a real tag
export async function getPublicTagPage(slug: string) {
  return publicGet<{ tag: ArticleTag; articles: ArticleCard[] }>(
    Endpoints.editorialTag(slug),
  );
}

// dedicated review list so the page doesnt filter client-side
export async function listPublishedReviews(limit = 40, cursor?: string) {
  try {
    const page = await publicGetPage<{ articles: ArticleCard[] }>(
      Endpoints.editorialReviews,
      { limit, sort: "newest", cursor },
    );
    return {
      articles: page.data.articles,
      nextCursor: page.pagination.nextCursor ?? null,
      hasMore: page.pagination.hasMore ?? false,
    };
  } catch {
    return listPublishedArticles(limit, { type: "review", cursor });
  }
}

// same deal for artist spotlights
export async function listPublishedSpotlights(limit = 40, cursor?: string) {
  try {
    const page = await publicGetPage<{ articles: ArticleCard[] }>(
      Endpoints.editorialSpotlights,
      { limit, sort: "newest", cursor },
    );
    return {
      articles: page.data.articles,
      nextCursor: page.pagination.nextCursor ?? null,
      hasMore: page.pagination.hasMore ?? false,
    };
  } catch {
    return listPublishedArticles(limit, { type: "spotlight", cursor });
  }
}

export async function searchPublishedEditorials(q: string, limit = 24) {
  try {
    const data = await publicGet<{
      query?: string;
      articles?: ArticleCard[];
      writers?: PublicWriter[];
      tags?: { id: string; name: string; slug: string }[];
    }>(Endpoints.editorialSearch, { q, limit });

    return {
      query: data.query ?? q,
      articles: data.articles ?? [],
      writers: data.writers ?? [],
      tags: data.tags ?? [],
    };
  } catch (error) {
    console.error("[editorial] search unavailable", error);
    return {
      query: q,
      articles: [],
      writers: [],
      tags: [],
      error: editorialUnavailable,
    };
  }
}

export async function getPublishedArticle(slug: string) {
  return publicGet<{ article: ArticleCard }>(
    Endpoints.editorialArticle(slug),
  );
}

export async function getPublishedArticleById(id: string) {
  return publicGet<{ article: ArticleCard }>(
    Endpoints.editorialArticleById(id),
  );
}

// writer page payload — profile + their published stack
export async function getPublicWriterPage(slug: string) {
  const data = await publicGet<{
    writer: PublicWriter;
    articles?: ArticleCard[];
  }>(Endpoints.editorialWriter(slug));

  if (data.articles) {
    return { writer: data.writer, articles: data.articles };
  }

  try {
    const extra = await publicGet<{ articles: ArticleCard[] }>(
      Endpoints.editorialWriterArticles(slug),
      { limit: 40, sort: "newest" },
    );
    return { writer: data.writer, articles: extra.articles };
  } catch {
    return { writer: data.writer, articles: [] as ArticleCard[] };
  }
}

// pull the live piece — slug first because that public route already works
export async function resolveFeaturedArticle(widget: {
  editorialId?: string;
  slug?: string;
}) {
  if (widget.slug) {
    try {
      const { article } = await getPublishedArticle(widget.slug);
      return article;
    } catch {
      // try id next
    }
  }
  if (widget.editorialId) {
    try {
      const { article } = await getPublishedArticleById(widget.editorialId);
      return article;
    } catch {
      return null;
    }
  }
  return null;
}
