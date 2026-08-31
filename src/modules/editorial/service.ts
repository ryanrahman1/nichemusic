import { supabase } from "../../config/supabase.js"
import { generateRandomId } from "../../lib/auth.js"
import { getOrSetCachedValue, invalidateCachedNamespace } from "../../lib/ttlCache.js"
import { upsertTrack } from "../music/helpers.js"
import type {
    AddNewMusicPickSchema,
    CreateDraftSchema,
    CreateWriterOnboardingSchema,
    EngagementEventSchema,
    ListArticlesQuerySchema,
    PublishArticleSchema,
    ReorderNewMusicPicksSchema,
    UpdateAdminArticleSchema,
    UpdateAdminWriterProfileSchema,
    UpdateNewMusicPickSchema,
    UpdateWriterArticleSchema,
    UpdateWriterOnboardingSchema,
} from "./schemas.js"
import { listArticlesQuerySchema } from "./schemas.js"
import {
    ARTICLE_ADMIN_SELECT,
    ARTICLE_DESK_LIST_SELECT,
    ARTICLE_PUBLIC_SELECT,
    ARTICLE_WRITER_LIST_SELECT,
    ARTICLE_WRITER_SELECT,
    ARTICLE_CARD_SELECT,
    ARTICLE_HOME_SELECT,
    WRITER_PROFILE_SELECT,
    WRITER_ADMIN_SELECT,
    decodeEditorialCursor,
    decodeUpdatedAtCursor,
    publishedBeforeNowIso,
    toIlikePattern,
    WRITER_EDITABLE_STATUSES,
    WRITER_SUBMITTABLE_STATUSES,
    WRITER_SELF_PUBLISH_STATUSES,
    DESK_PUBLISH_STATUSES,
    canAccessDeskArticle,
    createRevisionSnapshot,
    encodeEditorialCursor,
    encodeUpdatedAtCursor,
    assertArticleSlugAvailable,
    assertWriterSlugAvailable,
    isArticleSlugAvailable,
    isWriterSlugAvailable,
    formatArticleAdmin,
    formatArticleDeskList,
    formatArticleCard,
    formatArticleHome,
    formatArticlePublic,
    formatArticleWriter,
    formatArticleWriterList,
    formatWriterAdmin,
    formatWriterPublic,
    formatWriterSelf,
    buildWriterPermissions,
    getWriterByProfileId,
    isWriterOnArticle,
    isAdminRole,
    isEditorRole,
    isWriterActive,
    syncArticleTags,
    type ArticleRow,
    type WriterRow,
} from "./helpers.js"

type Paginated<T> = {
    items: T[]
    nextCursor: string | null
    hasMore: boolean
}

function buildArticleUpdateRow(body: UpdateWriterArticleSchema | UpdateAdminArticleSchema) {
    const row: Record<string, unknown> = {}

    if (body.title !== undefined) row.title = body.title
    if (body.subtitle !== undefined) row.subtitle = body.subtitle
    if (body.excerpt !== undefined) row.excerpt = body.excerpt
    if (body.content !== undefined) row.content = body.content
    if (body.template !== undefined) row.template = body.template
    if (body.templateData !== undefined) row.template_data = body.templateData
    if (body.coverImageUrl !== undefined) row.cover_image_url = body.coverImageUrl
    if (body.coverImageAlt !== undefined) row.cover_image_alt = body.coverImageAlt
    if (body.coverImageCredit !== undefined) row.cover_image_credit = body.coverImageCredit
    if (body.metaTitle !== undefined) row.meta_title = body.metaTitle
    if (body.metaDescription !== undefined) row.meta_description = body.metaDescription

    if ("type" in body && body.type !== undefined) row.type = body.type
    if ("isSponsored" in body && body.isSponsored !== undefined) row.is_sponsored = body.isSponsored
    if ("sponsorName" in body && body.sponsorName !== undefined) row.sponsor_name = body.sponsorName
    if ("slug" in body && body.slug !== undefined) row.slug = body.slug

    return row
}

async function transitionArticleStatus(
    editorialId: string,
    allowedFrom: readonly string[],
    toStatus: string,
    extraUpdates: Record<string, unknown> = {}
): Promise<void> {
    const { data, error } = await supabase
        .schema("public")
        .from("editorials")
        .update({ status: toStatus, ...extraUpdates })
        .eq("id", editorialId)
        .in("status", [...allowedFrom])
        .select("id")
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("INVALID_STATUS_TRANSITION")
}

function isPubliclyVisibleArticle(article: { status: string; published_at: string | null }): boolean {
    if (article.status !== "published") return false
    if (!article.published_at) return false
    return Date.parse(article.published_at) <= Date.now()
}

async function fetchArticleIdsByIlikeColumn(
    column: "title" | "subtitle" | "excerpt",
    pattern: string,
    limit: number,
    type?: string | undefined
): Promise<string[]> {
    let query = supabase
        .schema("public")
        .from("editorials")
        .select("id")
        .eq("status", "published")
        .lte("published_at", publishedBeforeNowIso())
        .ilike(column, pattern)
        .limit(limit)

    if (type) {
        query = query.eq("type", type)
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)
    return (data ?? []).map((row) => row.id)
}

async function fetchArticleById(
    editorialId: string,
    select: string,
    statusFilter?: string
): Promise<ArticleRow | null> {
    let query = supabase
        .schema("public")
        .from("editorials")
        .select(select)
        .eq("id", editorialId)

    if (statusFilter) {
        query = query.eq("status", statusFilter)
    }

    const { data, error } = await query.maybeSingle()
    if (error) throw new Error(error.message)
    return data as ArticleRow | null
}

async function fetchPublishedArticleBySlug(slug: string): Promise<ArticleRow | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_PUBLIC_SELECT)
        .eq("slug", slug)
        .eq("status", "published")
        .lte("published_at", publishedBeforeNowIso())
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data as ArticleRow | null
}

async function filterArticleIdsByTag(tagSlug: string): Promise<string[] | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("editorial_tag_links")
        .select("editorial_id, tag:editorial_tags!inner(slug)")
        .eq("editorial_tags.slug", tagSlug)

    if (error) throw new Error(error.message)

    const ids = (data ?? []).map((row) => row.editorial_id)
    return ids.length > 0 ? ids : []
}

async function filterArticleIdsByWriter(writerSlug: string): Promise<string[] | null> {
    const { data: writer, error: writerError } = await supabase
        .schema("public")
        .from("writers")
        .select("id")
        .eq("slug", writerSlug)
        .maybeSingle()

    if (writerError) throw new Error(writerError.message)
    if (!writer) return []

    const { data, error } = await supabase
        .schema("public")
        .from("editorial_credits")
        .select("editorial_id")
        .eq("writer_id", writer.id)
        .eq("credit_type", "writer")

    if (error) throw new Error(error.message)

    const ids = (data ?? []).map((row) => row.editorial_id)
    return ids.length > 0 ? ids : []
}

export async function listPublishedArticles(
    query: ListArticlesQuerySchema
): Promise<Paginated<ReturnType<typeof formatArticleCard>>> {
    const ascending = query.sort === "oldest"

    let filterIds: string[] | null = null

    if (query.tag) {
        const tagIds = await filterArticleIdsByTag(query.tag.toLowerCase())
        if (!tagIds || tagIds.length === 0) {
            return { items: [], nextCursor: null, hasMore: false }
        }
        filterIds = tagIds
    }

    if (query.writer) {
        const writerArticleIds = await filterArticleIdsByWriter(query.writer.toLowerCase())
        if (!writerArticleIds || writerArticleIds.length === 0) {
            return { items: [], nextCursor: null, hasMore: false }
        }

        filterIds = filterIds
            ? filterIds.filter((id) => writerArticleIds.includes(id))
            : writerArticleIds

        if (filterIds.length === 0) {
            return { items: [], nextCursor: null, hasMore: false }
        }
    }

    let dbQuery = supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_CARD_SELECT)
        .eq("status", "published")
        .lte("published_at", publishedBeforeNowIso())
        .order("published_at", { ascending, nullsFirst: false })
        .order("id", { ascending })
        .limit(query.limit + 1)

    if (query.type) {
        dbQuery = dbQuery.eq("type", query.type)
    }

    if (query.template) {
        dbQuery = dbQuery.eq("template", query.template)
    }

    if (filterIds) {
        dbQuery = dbQuery.in("id", filterIds)
    }

    const decodedCursor = decodeEditorialCursor(query.cursor)
    if (decodedCursor) {
        const op = ascending ? "gt" : "lt"
        dbQuery = dbQuery.or(
            `published_at.${op}.${decodedCursor.cursorPublishedAt},and(published_at.eq.${decodedCursor.cursorPublishedAt},id.${ascending ? "gt" : "lt"}.${decodedCursor.cursorId})`
        )
    }

    const { data, error } = await dbQuery
    if (error) throw new Error(error.message)

    const rows = (data ?? []) as ArticleRow[]
    const hasMore = rows.length > query.limit
    const pageRows = hasMore ? rows.slice(0, query.limit) : rows
    const lastRow = pageRows.at(-1)

    return {
        items: pageRows.map(formatArticleCard),
        nextCursor:
            hasMore && lastRow?.published_at
                ? encodeEditorialCursor(lastRow.published_at, lastRow.id)
                : null,
        hasMore,
    }
}

export async function getPublishedArticleBySlug(slug: string) {
    const article = await fetchPublishedArticleBySlug(slug)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")
    return formatArticlePublic(article)
}

export async function getPublishedArticleById(editorialId: string) {
    const article = await fetchArticleById(editorialId, ARTICLE_PUBLIC_SELECT)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")
    if (!isPubliclyVisibleArticle(article)) throw new Error("ARTICLE_NOT_FOUND")
    return formatArticlePublic(article)
}

const EDITORIAL_HOME_CACHE_TTL_MS = 20_000
const HOME_LATEST_LIMIT = 5
const HOME_FEATURED_LIMIT = 3
const HOME_NEW_MUSIC_LIMIT = 12

type HomeSlotRow = {
    section: "hero" | "premium_promo" | "featured" | "promo"
    position: number
    show_from: string | null
    show_until: string | null
    editorial: ArticleRow | ArticleRow[] | null
}

type HomeTrackRow = {
    id: string
    source: string
    source_id: string
    name: string | null
    artwork_url: string | null
    preview_url: string | null
    release_date: string | null
    artist?: { id: string; name: string | null } | { id: string; name: string | null }[] | null
}

type HomePickRow = {
    position: number
    show_from: string | null
    show_until: string | null
    track: HomeTrackRow | HomeTrackRow[] | null
    editorial: ArticleRow | ArticleRow[] | null
}

// supabase loves returning either the row or a weird one-item array
function firstEmbedded<T>(value: T | T[] | null | undefined): T | null {
    if (!value) return null
    return Array.isArray(value) ? value[0] ?? null : value
}

// live if the window has started and hasnt ended yet
function isActiveWindow(row: { show_from: string | null; show_until: string | null }, now: number) {
    const fromOk = !row.show_from || Date.parse(row.show_from) <= now
    const untilOk = !row.show_until || Date.parse(row.show_until) > now
    return fromOk && untilOk
}

// apple artwork urls come in with {w}x{h} tokens
function sizedArtworkUrl(url: string | null, size = 600): string | null {
    if (!url) return null
    return url.replace(/\{w\}/g, String(size)).replace(/\{h\}/g, String(size))
}

function isLivePublishedArticle(article: ArticleRow | null): article is ArticleRow {
    return !!article && isPubliclyVisibleArticle(article)
}

// smash the slots, nmf picks, and latest feed into one homepage payload
async function loadEditorialHome() {
    const nowIso = publishedBeforeNowIso()
    const nowMs = Date.parse(nowIso)

    const [slotsRes, picksRes, latestRes] = await Promise.all([
        supabase
            .schema("public")
            .from("editorial_home_slots")
            .select(`
                section,
                position,
                show_from,
                show_until,
                editorial:editorials!editorial_home_slots_editorial_id_fkey!inner(
                    ${ARTICLE_HOME_SELECT}
                )
            `)
            .eq("editorial.status", "published")
            .lte("editorial.published_at", nowIso)
            .order("position", { ascending: true }),
        supabase
            .schema("public")
            .from("editorial_new_music_picks")
            .select(`
                position,
                show_from,
                show_until,
                track:tracks!editorial_new_music_picks_track_id_fkey!inner(
                    id,
                    source,
                    source_id,
                    name,
                    artwork_url,
                    preview_url,
                    release_date,
                    artist:artists!tracks_artist_id_fkey(id, name)
                ),
                editorial:editorials!editorial_new_music_picks_editorial_id_fkey(
                    ${ARTICLE_HOME_SELECT}
                )
            `)
            .eq("track.source", "apple_music")
            .order("position", { ascending: true })
            .limit(48),
        supabase
            .schema("public")
            .from("editorials")
            .select(ARTICLE_HOME_SELECT)
            .eq("status", "published")
            .lte("published_at", nowIso)
            .order("published_at", { ascending: false, nullsFirst: false })
            .order("id", { ascending: false })
            .limit(HOME_LATEST_LIMIT + 8),
    ])

    if (slotsRes.error) throw new Error(slotsRes.error.message)
    if (picksRes.error) throw new Error(picksRes.error.message)
    if (latestRes.error) throw new Error(latestRes.error.message)

    const slotted = new Map<string, ReturnType<typeof formatArticleHome>>()
    let hero: ReturnType<typeof formatArticleHome> | null = null
    let premiumPromo: ReturnType<typeof formatArticleHome> | null = null
    let promo: ReturnType<typeof formatArticleHome> | null = null
    const featured: ReturnType<typeof formatArticleHome>[] = []

    for (const row of (slotsRes.data ?? []) as HomeSlotRow[]) {
        if (!isActiveWindow(row, nowMs)) continue
        const article = firstEmbedded(row.editorial)
        if (!isLivePublishedArticle(article)) continue

        const formatted = formatArticleHome(article)
        slotted.set(formatted.id, formatted)

        if (row.section === "hero" && !hero) {
            hero = formatted
            continue
        }
        if (row.section === "premium_promo" && !premiumPromo) {
            premiumPromo = formatted
            continue
        }
        if (row.section === "promo" && !promo) {
            promo = formatted
            continue
        }
        if (row.section === "featured" && featured.length < HOME_FEATURED_LIMIT) {
            featured.push(formatted)
        }
    }

    const newMusic = ((picksRes.data ?? []) as HomePickRow[])
        .filter((row) => isActiveWindow(row, nowMs))
        .slice(0, HOME_NEW_MUSIC_LIMIT)
        .map((row) => {
            const track = firstEmbedded(row.track)
            if (!track || track.source !== "apple_music") return null

            const artist = firstEmbedded(track.artist)
            const related = firstEmbedded(row.editorial)
            const review = isLivePublishedArticle(related)
                ? { slug: related.slug, title: related.title, type: related.type }
                : null

            return {
                track: {
                    id: track.id,
                    source: "apple_music" as const,
                    sourceId: track.source_id,
                    name: track.name,
                    artworkUrl: sizedArtworkUrl(track.artwork_url),
                    previewUrl: track.preview_url,
                    releaseDate: track.release_date,
                    artist: artist
                        ? { id: artist.id, name: artist.name }
                        : null,
                },
                review,
            }
        })
        .filter((pick): pick is NonNullable<typeof pick> => !!pick)

    const latest = ((latestRes.data ?? []) as ArticleRow[])
        .filter((row) => !slotted.has(row.id))
        .slice(0, HOME_LATEST_LIMIT)
        .map(formatArticleHome)

    return {
        hero,
        premiumPromo,
        featured,
        newMusic,
        promo,
        latest,
    }
}

export async function getEditorialHome() { // cached so the homepage aint hitting supabase every refresh
    return getOrSetCachedValue({
        namespace: "editorial:home",
        key: "public",
        ttlMs: EDITORIAL_HOME_CACHE_TTL_MS,
        loader: loadEditorialHome,
    })
}

function bustHomeCache() {
    invalidateCachedNamespace("editorial:home")
}

function parseScheduleIso(value: string | null | undefined) {
    if (!value) return null
    const ms = Date.parse(value)
    if (Number.isNaN(ms)) throw new Error("INVALID_SCHEDULE")
    return new Date(ms).toISOString()
}

function assertScheduleWindow(showFrom: string | null, showUntil: string | null) {
    if (showFrom && showUntil && Date.parse(showUntil) <= Date.parse(showFrom)) {
        throw new Error("INVALID_SCHEDULE")
    }
}

type AdminPickRow = HomePickRow & { id: string; editorial_id?: string | null }

function formatAdminNewMusicPick(row: AdminPickRow, nowMs: number) {
    const track = firstEmbedded(row.track)
    const related = firstEmbedded(row.editorial)
    const artist = track ? firstEmbedded(track.artist) : null

    return {
        id: row.id,
        position: row.position,
        showFrom: row.show_from,
        showUntil: row.show_until,
        live: isActiveWindow(row, nowMs),
        track: track
            ? {
                  id: track.id,
                  source: "apple_music" as const,
                  sourceId: track.source_id,
                  name: track.name,
                  artworkUrl: sizedArtworkUrl(track.artwork_url),
                  previewUrl: track.preview_url,
                  releaseDate: track.release_date,
                  artist: artist ? { id: artist.id, name: artist.name } : null,
              }
            : null,
        review: related
            ? {
                  id: related.id,
                  slug: related.slug,
                  title: related.title,
                  type: related.type,
                  status: related.status,
              }
            : null,
    }
}

const ADMIN_NEW_MUSIC_SELECT = `
    id,
    position,
    show_from,
    show_until,
    editorial_id,
    track:tracks!editorial_new_music_picks_track_id_fkey!inner(
        id,
        source,
        source_id,
        name,
        artwork_url,
        preview_url,
        release_date,
        artist:artists!tracks_artist_id_fkey(id, name)
    ),
    editorial:editorials!editorial_new_music_picks_editorial_id_fkey(
        id,
        slug,
        title,
        type,
        status
    )
`

// desk view of the friday board, scheduled stuff included
export async function listAdminNewMusicPicks() {
    const { data, error } = await supabase
        .schema("public")
        .from("editorial_new_music_picks")
        .select(ADMIN_NEW_MUSIC_SELECT)
        .order("position", { ascending: true })
        .limit(48)

    if (error) throw new Error(error.message)

    const nowMs = Date.now()
    return ((data ?? []) as AdminPickRow[]).map((row) => formatAdminNewMusicPick(row, nowMs))
}

export async function addAdminNewMusicPick(body: AddNewMusicPickSchema) {
    const track = await upsertTrack(body.appleSongId, "apple_music")
    if (!track) throw new Error("TRACK_NOT_FOUND")

    const { data: existing, error: existingError } = await supabase
        .schema("public")
        .from("editorial_new_music_picks")
        .select("id")
        .eq("track_id", track.id)
        .maybeSingle()

    if (existingError) throw new Error(existingError.message)
    if (existing) throw new Error("TRACK_ALREADY_ON_BOARD")

    const { data: last, error: lastError } = await supabase
        .schema("public")
        .from("editorial_new_music_picks")
        .select("position")
        .order("position", { ascending: false })
        .limit(1)
        .maybeSingle()

    if (lastError) throw new Error(lastError.message)

    const showFrom = parseScheduleIso(body.showFrom)
    const showUntil = parseScheduleIso(body.showUntil)
    assertScheduleWindow(showFrom, showUntil)

    const { error } = await supabase.schema("public").from("editorial_new_music_picks").insert({
        id: generateRandomId(16),
        track_id: track.id,
        editorial_id: body.editorialId || null,
        position: (last?.position ?? -1) + 1,
        show_from: showFrom,
        show_until: showUntil,
    })

    if (error) throw new Error(error.message)
    bustHomeCache()
    return listAdminNewMusicPicks()
}

export async function updateAdminNewMusicPick(id: string, body: UpdateNewMusicPickSchema) {
    const patch: Record<string, unknown> = { updated_at: new Date().toISOString() }

    if (body.editorialId !== undefined) {
        patch.editorial_id = body.editorialId ? body.editorialId : null
    }
    if (body.showFrom !== undefined) patch.show_from = parseScheduleIso(body.showFrom)
    if (body.showUntil !== undefined) patch.show_until = parseScheduleIso(body.showUntil)

    if (patch.show_from !== undefined || patch.show_until !== undefined) {
        const { data: current, error: currentError } = await supabase
            .schema("public")
            .from("editorial_new_music_picks")
            .select("show_from, show_until")
            .eq("id", id)
            .maybeSingle()

        if (currentError) throw new Error(currentError.message)
        if (!current) throw new Error("NEW_MUSIC_PICK_NOT_FOUND")

        const showFrom =
            patch.show_from !== undefined ? (patch.show_from as string | null) : current.show_from
        const showUntil =
            patch.show_until !== undefined ? (patch.show_until as string | null) : current.show_until
        assertScheduleWindow(showFrom, showUntil)
    }

    const { data, error } = await supabase
        .schema("public")
        .from("editorial_new_music_picks")
        .update(patch)
        .eq("id", id)
        .select("id")
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("NEW_MUSIC_PICK_NOT_FOUND")
    bustHomeCache()
    return listAdminNewMusicPicks()
}

export async function reorderAdminNewMusicPicks(body: ReorderNewMusicPicksSchema) {
    await Promise.all(
        body.pickIds.map((pickId, index) =>
            supabase
                .schema("public")
                .from("editorial_new_music_picks")
                .update({ position: index, updated_at: new Date().toISOString() })
                .eq("id", pickId)
        )
    )
    bustHomeCache()
    return listAdminNewMusicPicks()
}

export async function deleteAdminNewMusicPick(id: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("editorial_new_music_picks")
        .delete()
        .eq("id", id)
        .select("id")
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("NEW_MUSIC_PICK_NOT_FOUND")
    bustHomeCache()
    return listAdminNewMusicPicks()
}

// how many times this writer got that credit on a piece
async function countWriterCredits(writerId: string, creditType: string) {
    const { count, error } = await supabase
        .schema("public")
        .from("editorial_credits")
        .select("id", { count: "exact", head: true })
        .eq("writer_id", writerId)
        .eq("credit_type", creditType)

    if (error) throw new Error(error.message)
    return count ?? 0
}

export async function getWriterPublicProfile(writerSlug: string) {
    const { data: writer, error } = await supabase
        .schema("public")
        .from("writers")
        .select(WRITER_PROFILE_SELECT)
        .eq("slug", writerSlug)
        .eq("status", "active")
        .eq("onboarding_completed", true)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!writer) throw new Error("WRITER_NOT_FOUND")

    const row = writer as WriterRow

    const [followersCount, editedCount] = await Promise.all([
        supabase
            .schema("public")
            .from("profiles")
            .select("followers_count")
            .eq("id", row.profile_id)
            .maybeSingle()
            .then(({ data, error }) => {
                if (error) return 0
                return data?.followers_count ?? 0
            })
            .catch(() => 0),
        countWriterCredits(row.id, "editor").catch(() => 0),
    ])

    return formatWriterPublic(row, { editedCount, followersCount })
}

// one payload for the public writer page
export async function getWriterPublicPage(writerSlug: string) {
    const writer = await getWriterPublicProfile(writerSlug)
    const page = await listWriterPublicArticles(
        writerSlug,
        listArticlesQuerySchema.parse({ sort: "newest", limit: 40 }),
    )

    return {
        writer,
        articles: page.items,
    }
}

// public tag page — the tag itself plus every live piece on it
export async function getPublicTagPage(tagSlug: string) {
    const slug = tagSlug.trim().toLowerCase()
    const { data, error } = await supabase
        .schema("public")
        .from("editorial_tags")
        .select("id, name, slug")
        .eq("slug", slug)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("TAG_NOT_FOUND")

    const page = await listPublishedArticles(
        listArticlesQuerySchema.parse({ tag: slug, sort: "newest", limit: 40 }),
    )

    return {
        tag: { id: data.id, name: data.name, slug: data.slug },
        articles: page.items,
    }
}

export async function listWriterPublicArticles(
    writerSlug: string,
    query: ListArticlesQuerySchema
): Promise<Paginated<ReturnType<typeof formatArticleCard>>> {
    return listPublishedArticles({
        ...query,
        writer: writerSlug,
    })
}

type EditorialSearchHit = {
    kind: string
    id: string
    slug: string
    title: string
    subtitle: string | null
    score: number
}

function isMissingSearchRpc(error: { message?: string; code?: string }) {
    const msg = (error.message || "").toLowerCase()
    return (
        error.code === "PGRST202" ||
        msg.includes("could not find the function") ||
        (msg.includes("search_editorials") && msg.includes("schema cache"))
    )
}

function emptyEditorialSearch(query: string) {
    return {
        query,
        articles: [] as ReturnType<typeof formatArticleCard>[],
        writers: [] as ReturnType<typeof formatWriterPublic>[],
        tags: [] as { id: string; name: string; slug: string }[],
    }
}

// try the trigram rpc first, fall back to the old ilike mashup
export async function searchPublishedArticles(input: {
    q: string
    type?: string | undefined
    limit: number
}) {
    const rpc = await searchEditorialsViaRpc(input)
    if (rpc) return rpc
    return searchPublishedArticlesIlike(input)
}

async function searchEditorialsViaRpc(input: {
    q: string
    type?: string | undefined
    limit: number
}) {
    const { data, error } = await supabase.schema("public").rpc("search_editorials", {
        p_query: input.q,
        p_limit: input.limit,
        p_type: input.type ?? null,
    })

    if (error) {
        if (isMissingSearchRpc(error)) return null
        throw new Error(error.message)
    }

    const hits = (data ?? []) as EditorialSearchHit[]
    if (hits.length === 0) return emptyEditorialSearch(input.q)

    const articleIds = hits.filter((hit) => hit.kind === "article").map((hit) => hit.id)
    const writerIds = hits.filter((hit) => hit.kind === "writer").map((hit) => hit.id)
    const tagHits = hits.filter((hit) => hit.kind === "tag")

    const [articlesRes, writersRes] = await Promise.all([
        articleIds.length > 0
            ? supabase
                  .schema("public")
                  .from("editorials")
                  .select(ARTICLE_CARD_SELECT)
                  .in("id", articleIds)
                  .eq("status", "published")
                  .lte("published_at", publishedBeforeNowIso())
            : Promise.resolve({ data: [], error: null }),
        writerIds.length > 0
            ? supabase
                  .schema("public")
                  .from("writers")
                  .select(WRITER_PROFILE_SELECT)
                  .in("id", writerIds)
            : Promise.resolve({ data: [], error: null }),
    ])

    if (articlesRes.error) throw new Error(articlesRes.error.message)
    if (writersRes.error) throw new Error(writersRes.error.message)

    const articlesById = new Map(
        ((articlesRes.data ?? []) as ArticleRow[]).map((row) => [row.id, formatArticleCard(row)])
    )
    const writersById = new Map(
        ((writersRes.data ?? []) as WriterRow[]).map((row) => [row.id, formatWriterPublic(row)])
    )

    return {
        query: input.q,
        articles: articleIds
            .map((id) => articlesById.get(id))
            .filter((article): article is ReturnType<typeof formatArticleCard> => Boolean(article)),
        writers: writerIds
            .map((id) => writersById.get(id))
            .filter((writer): writer is ReturnType<typeof formatWriterPublic> => Boolean(writer)),
        tags: tagHits.map((hit) => ({
            id: hit.id,
            name: hit.title,
            slug: hit.slug,
        })),
    }
}

async function searchPublishedArticlesIlike(input: {
    q: string
    type?: string | undefined
    limit: number
}) {
    const pattern = toIlikePattern(input.q)
    const matchedIds = new Set<string>()
    const nowIso = publishedBeforeNowIso()

    const [titleIds, subtitleIds, excerptIds] = await Promise.all([
        fetchArticleIdsByIlikeColumn("title", pattern, input.limit, input.type),
        fetchArticleIdsByIlikeColumn("subtitle", pattern, input.limit, input.type),
        fetchArticleIdsByIlikeColumn("excerpt", pattern, input.limit, input.type),
    ])

    for (const id of [...titleIds, ...subtitleIds, ...excerptIds]) matchedIds.add(id)

    const { data: matchingTags, error: tagLookupError } = await supabase
        .schema("public")
        .from("editorial_tags")
        .select("id")
        .ilike("name", pattern)
        .limit(input.limit)

    if (tagLookupError) throw new Error(tagLookupError.message)

    const { data: matchingTagsBySlug, error: tagSlugError } = await supabase
        .schema("public")
        .from("editorial_tags")
        .select("id")
        .ilike("slug", pattern)
        .limit(input.limit)

    if (tagSlugError) throw new Error(tagSlugError.message)

    const tagIds = [...new Set([...(matchingTags ?? []), ...(matchingTagsBySlug ?? [])].map((tag) => tag.id))]
    const tagLinksPromise =
        tagIds.length > 0
            ? supabase
                  .schema("public")
                  .from("editorial_tag_links")
                  .select("editorial_id")
                  .in("tag_id", tagIds)
                  .limit(input.limit)
            : Promise.resolve({ data: [], error: null })

    const { data: matchingProfilesByUsername, error: usernameError } = await supabase
        .schema("public")
        .from("profiles")
        .select("id")
        .ilike("username", pattern)
        .limit(input.limit)

    if (usernameError) throw new Error(usernameError.message)

    const { data: matchingProfilesByDisplayName, error: displayNameError } = await supabase
        .schema("public")
        .from("profiles")
        .select("id")
        .ilike("display_name", pattern)
        .limit(input.limit)

    if (displayNameError) throw new Error(displayNameError.message)

    const profileIds = [
        ...new Set(
            [...(matchingProfilesByUsername ?? []), ...(matchingProfilesByDisplayName ?? [])].map(
                (profile) => profile.id
            )
        ),
    ]
    let writerCreditRows: { editorial_id: string }[] = []

    if (profileIds.length > 0) {
        const { data: writers, error: writersError } = await supabase
            .schema("public")
            .from("writers")
            .select("id")
            .in("profile_id", profileIds)

        if (writersError) throw new Error(writersError.message)

        const writerIds = (writers ?? []).map((writer) => writer.id)
        if (writerIds.length > 0) {
            const { data: credits, error: creditsError } = await supabase
                .schema("public")
                .from("editorial_credits")
                .select("editorial_id")
                .in("writer_id", writerIds)
                .eq("credit_type", "writer")
                .limit(input.limit)

            if (creditsError) throw new Error(creditsError.message)
            writerCreditRows = credits ?? []
        }
    }

    const tagLinkRes = await tagLinksPromise

    if (tagLinkRes.error) throw new Error(tagLinkRes.error.message)

    for (const row of tagLinkRes.data ?? []) matchedIds.add(row.editorial_id)
    for (const row of writerCreditRows) matchedIds.add(row.editorial_id)

    if (matchedIds.size === 0) {
        return emptyEditorialSearch(input.q)
    }

    let articlesQuery = supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_CARD_SELECT)
        .in("id", [...matchedIds])
        .eq("status", "published")
        .lte("published_at", nowIso)
        .order("published_at", { ascending: false })
        .limit(input.limit)

    if (input.type) {
        articlesQuery = articlesQuery.eq("type", input.type)
    }

    const { data, error } = await articlesQuery
    if (error) throw new Error(error.message)

    return {
        ...emptyEditorialSearch(input.q),
        articles: ((data ?? []) as ArticleRow[]).map(formatArticleCard),
    }
}

export async function getMyWriterProfile(profileId: string) {
    const writer = await supabase
        .schema("public")
        .from("writers")
        .select(WRITER_PROFILE_SELECT)
        .eq("profile_id", profileId)
        .maybeSingle()

    if (writer.error) throw new Error(writer.error.message)

    if (!writer.data) {
        return {
            writer: null,
            permissions: buildWriterPermissions(null),
        }
    }

    const row = writer.data as WriterRow
    return {
        writer: formatWriterSelf(row),
        permissions: buildWriterPermissions(row),
    }
}

// one payload for /write so the page aint doing a waterfall
export async function getWriterWorkspace(profileId: string) {
    const writer = await getWriterByProfileId(profileId)
    const permissions = buildWriterPermissions(writer)

    if (!writer || !isWriterActive(writer)) {
        return {
            writer: writer ? formatWriterSelf(writer) : null,
            permissions,
            articles: [],
            queue: [],
            catalog: [],
        }
    }

    const empty = { items: [] as ReturnType<typeof formatArticleWriterList>[] }
    const [mine, queue, catalog] = await Promise.all([
        listMyArticles(writer, { limit: 50 }),
        permissions.canReview
            ? listAdminSubmissions({ status: "all", limit: 50 })
            : Promise.resolve(empty),
        permissions.canEditAny
            ? listAdminArticles({ status: "all", limit: 50 })
            : Promise.resolve(empty),
    ])

    return {
        writer: formatWriterSelf(writer),
        permissions,
        articles: mine.items,
        queue: queue.items,
        catalog: catalog.items,
    }
}

export async function checkWriterSlugAvailability(
    slug: string,
    excludeWriterId?: string | undefined
) {
    const available = await isWriterSlugAvailable(slug, excludeWriterId)
    return { slug, available }
}

export async function createWriterOnboarding(
    profileId: string,
    body: CreateWriterOnboardingSchema
) {
    const existing = await getWriterByProfileId(profileId)
    if (existing) {
        throw new Error("WRITER_ALREADY_EXISTS")
    }

    await assertWriterSlugAvailable(body.slug)

    const { data: profile, error: profileError } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, display_name")
        .eq("id", profileId)
        .maybeSingle()

    if (profileError) throw new Error(profileError.message)
    if (!profile) throw new Error("PROFILE_NOT_FOUND")

    const writerId = generateRandomId(16)
    const now = new Date().toISOString()

    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .insert({
            id: writerId,
            profile_id: profileId,
            slug: body.slug,
            role: "contributor",
            bio: body.bio,
            display_name: body.displayName ?? profile.display_name ?? profile.username,
            specialties: body.specialties ?? [],
            location: body.location ?? null,
            status: "active",
            is_active: true,
            onboarding_completed: true,
            created_by: profileId,
            last_active_at: now,
            joined_at: now,
        })
        .select(WRITER_PROFILE_SELECT)
        .single()

    if (error) throw new Error(error.message)

    return formatWriterSelf(data as WriterRow)
}

export async function updateWriterOnboarding(
    profileId: string,
    body: UpdateWriterOnboardingSchema
) {
    const writer = await getWriterByProfileId(profileId)
    if (!writer) {
        throw new Error("NOT_A_WRITER")
    }

    if (writer.status === "left") {
        throw new Error("INVALID_STATUS_TRANSITION")
    }

    if (body.slug !== undefined) {
        await assertWriterSlugAvailable(body.slug, writer.id)
    }

    const updateRow: Record<string, unknown> = {
        last_active_at: new Date().toISOString(),
    }

    if (body.slug !== undefined) updateRow.slug = body.slug
    if (body.displayName !== undefined) updateRow.display_name = body.displayName
    if (body.bio !== undefined) updateRow.bio = body.bio
    if (body.specialties !== undefined) updateRow.specialties = body.specialties
    if (body.location !== undefined) updateRow.location = body.location
    if (body.onboardingCompleted !== undefined) {
        updateRow.onboarding_completed = body.onboardingCompleted
    }

    const hasChanges =
        body.slug !== undefined ||
        body.displayName !== undefined ||
        body.bio !== undefined ||
        body.specialties !== undefined ||
        body.location !== undefined ||
        body.onboardingCompleted !== undefined

    if (!hasChanges) {
        throw new Error("No changes provided")
    }

    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .update(updateRow)
        .eq("id", writer.id)
        .select(WRITER_PROFILE_SELECT)
        .single()

    if (error) throw new Error(error.message)

    return formatWriterSelf(data as WriterRow)
}

export async function deleteWriterOnboarding(profileId: string) {
    const writer = await getWriterByProfileId(profileId)
    if (!writer) {
        throw new Error("NOT_A_WRITER")
    }

    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .update({
            status: "left",
            is_active: false,
            onboarding_completed: false,
            last_active_at: new Date().toISOString(),
        })
        .eq("id", writer.id)
        .select(WRITER_PROFILE_SELECT)
        .single()

    if (error) throw new Error(error.message)

    return formatWriterSelf(data as WriterRow)
}

export async function listMyArticles(
    writer: WriterRow,
    input: {
        status?: string | undefined
        cursor?: string | undefined
        limit: number
    }
): Promise<Paginated<ReturnType<typeof formatArticleWriterList>>> {
    const { data: creditRows, error: creditError } = await supabase
        .schema("public")
        .from("editorial_credits")
        .select("editorial_id")
        .eq("writer_id", writer.id)
        .eq("credit_type", "writer")

    if (creditError) throw new Error(creditError.message)

    const editorialIds = (creditRows ?? []).map((row) => row.editorial_id)
    if (editorialIds.length === 0) {
        return { items: [], nextCursor: null, hasMore: false }
    }

    let query = supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_WRITER_LIST_SELECT)
        .in("id", editorialIds)
        .order("updated_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(input.limit + 1)

    if (input.status) {
        query = query.eq("status", input.status)
    }

    const decodedCursor = decodeUpdatedAtCursor(input.cursor)
    if (decodedCursor) {
        query = query.or(
            `updated_at.lt.${decodedCursor.cursorUpdatedAt},and(updated_at.eq.${decodedCursor.cursorUpdatedAt},id.lt.${decodedCursor.cursorId})`
        )
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    const rows = (data ?? []) as ArticleRow[]
    const hasMore = rows.length > input.limit
    const pageRows = hasMore ? rows.slice(0, input.limit) : rows
    const lastRow = pageRows.at(-1)

    return {
        items: pageRows.map(formatArticleWriterList),
        nextCursor: hasMore && lastRow ? encodeUpdatedAtCursor(lastRow.updated_at, lastRow.id) : null,
        hasMore,
    }
}

export async function checkArticleSlugAvailability(
    slug: string,
    type: string,
    excludeArticleId?: string | undefined
) {
    const available = await isArticleSlugAvailable(slug, type, excludeArticleId)
    return { slug, available }
}

export async function createDraftArticle(writer: WriterRow, body: CreateDraftSchema) {
    const editorialId = generateRandomId(16)

    await assertArticleSlugAvailable(body.slug, body.type)

    const { data, error } = await supabase.schema("public").rpc("create_editorial_draft", {
        p_id: editorialId,
        p_slug: body.slug,
        p_title: body.title,
        p_type: body.type,
        p_writer_id: writer.id,
        p_template: body.template,
        p_template_data: body.templateData ?? {},
    })

    if (error) {
        // fallback if rpc not deployed yet — still avoid orphan rows
        const { error: insertError } = await supabase.schema("public").from("editorials").insert({
            id: editorialId,
            slug: body.slug,
            title: body.title,
            type: body.type,
            template: body.template,
            template_data: body.templateData ?? {},
            status: "draft",
        })

        if (insertError) throw new Error(insertError.message)

        const { error: creditError } = await supabase.schema("public").from("editorial_credits").insert({
            editorial_id: editorialId,
            writer_id: writer.id,
            credit_type: "writer",
            position: 0,
        })

        if (creditError) {
            await supabase.schema("public").from("editorials").delete().eq("id", editorialId)
            throw new Error(creditError.message)
        }

        const article = await fetchArticleById(editorialId, ARTICLE_WRITER_SELECT)
        if (!article) throw new Error("ARTICLE_NOT_FOUND")
        return formatArticleWriter(article)
    }

    const row = (Array.isArray(data) ? data[0] : data) as ArticleRow | undefined
    if (!row) throw new Error("ARTICLE_NOT_FOUND")

    const article = await fetchArticleById(row.id, ARTICLE_WRITER_SELECT)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    return formatArticleWriter(article)
}

export async function getWriterArticle(writer: WriterRow, editorialId: string) {
    await requireWriterArticleAccess(writer, editorialId)

    const article = await fetchArticleById(editorialId, ARTICLE_WRITER_SELECT)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    return formatArticleWriter(article)
}

async function requireWriterArticleAccess(writer: WriterRow, editorialId: string) {
    // /editorial/me routes are owner-only — editors use admin routes
    const hasAccess = await isWriterOnArticle(writer.id, editorialId)
    if (!hasAccess) throw new Error("FORBIDDEN")
}

export async function updateWriterArticle(
    writer: WriterRow,
    editorialId: string,
    body: UpdateWriterArticleSchema
) {
    await requireWriterArticleAccess(writer, editorialId)

    const existing = await fetchArticleById(editorialId, "id, status, type")
    if (!existing) throw new Error("ARTICLE_NOT_FOUND")

    if (!WRITER_EDITABLE_STATUSES.includes(existing.status as (typeof WRITER_EDITABLE_STATUSES)[number])) {
        throw new Error("INVALID_STATUS_TRANSITION")
    }

    if (body.slug !== undefined) {
        await assertArticleSlugAvailable(body.slug, existing.type, editorialId)
    }

    const updateRow = {
        ...buildArticleUpdateRow(body),
        ...(existing.status === "published"
            ? { status: "changes_requested", published_at: null }
            : {}),
    }
    if (Object.keys(updateRow).length > 0) {
        const { error } = await supabase
            .schema("public")
            .from("editorials")
            .update(updateRow)
            .eq("id", editorialId)

        if (error) throw new Error(error.message)
    }

    if (body.tagSlugs) {
        await syncArticleTags(editorialId, body.tagSlugs)
    }

    const article = await fetchArticleById(editorialId, ARTICLE_WRITER_SELECT)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    return formatArticleWriter(article)
}

export async function submitArticle(writer: WriterRow, editorialId: string) {
    await requireWriterArticleAccess(writer, editorialId)

    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    if (!WRITER_SUBMITTABLE_STATUSES.includes(article.status as (typeof WRITER_SUBMITTABLE_STATUSES)[number])) {
        throw new Error("INVALID_STATUS_TRANSITION")
    }

    await transitionArticleStatus(editorialId, WRITER_SUBMITTABLE_STATUSES, "submitted")

    await createRevisionSnapshot({
        editorialId,
        createdBy: writer.id,
        revisionType: "submitted",
        title: article.title,
        subtitle: article.subtitle,
        excerpt: article.excerpt,
        content: article.content,
    })

    return getWriterArticle(writer, editorialId)
}

export async function selfPublishArticle(writer: WriterRow, editorialId: string) {
    const fresh = await getWriterByProfileId(writer.profile_id)
    if (
        !fresh ||
        fresh.id !== writer.id ||
        !isWriterActive(fresh) ||
        !isEditorRole(fresh.role)
    ) {
        throw new Error("FORBIDDEN")
    }

    await requireWriterArticleAccess(fresh, editorialId)

    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content, slug"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    if (
        !WRITER_SELF_PUBLISH_STATUSES.includes(
            article.status as (typeof WRITER_SELF_PUBLISH_STATUSES)[number]
        )
    ) {
        throw new Error("INVALID_STATUS_TRANSITION")
    }

    const publishedAt = new Date().toISOString()

    await transitionArticleStatus(editorialId, WRITER_SELF_PUBLISH_STATUSES, "published", {
        published_at: publishedAt,
    })

    await createRevisionSnapshot({
        editorialId,
        createdBy: fresh.id,
        revisionType: "published",
        title: article.title,
        subtitle: article.subtitle,
        excerpt: article.excerpt,
        content: article.content,
    })

    return getWriterArticle(fresh, editorialId)
}

export async function withdrawArticle(writer: WriterRow, editorialId: string) {
    await requireWriterArticleAccess(writer, editorialId)

    const article = await fetchArticleById(editorialId, "id, status")
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["submitted", "in_review"], "draft")

    return getWriterArticle(writer, editorialId)
}

async function requireDeskArticleAccess(actor: WriterRow, editorialId: string) {
    const article = await fetchArticleById(editorialId, "id, status")
    if (!article) throw new Error("ARTICLE_NOT_FOUND")
    if (!canAccessDeskArticle(actor, article.status)) throw new Error("FORBIDDEN")
    return article
}

// credit the desk person as editor — never swap the original writer
async function ensureEditorCredit(editorialId: string, editorId: string) {
    if (await isWriterOnArticle(editorId, editorialId)) return

    const { error } = await supabase.schema("public").from("editorial_credits").upsert(
        {
            editorial_id: editorialId,
            writer_id: editorId,
            credit_type: "editor",
            position: 1,
        },
        { onConflict: "editorial_id,writer_id,credit_type", ignoreDuplicates: true }
    )

    if (error) throw new Error(error.message)
}

export async function listAdminSubmissions(input: {
    status: "submitted" | "in_review" | "approved" | "all"
    cursor?: string | undefined
    limit: number
}) {
    let query = supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_DESK_LIST_SELECT)
        .order("updated_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(input.limit + 1)

    if (input.status === "all") {
        query = query.in("status", ["submitted", "in_review", "approved"])
    } else {
        query = query.eq("status", input.status)
    }

    const decodedCursor = decodeUpdatedAtCursor(input.cursor)
    if (decodedCursor) {
        query = query.or(
            `updated_at.lt.${decodedCursor.cursorUpdatedAt},and(updated_at.eq.${decodedCursor.cursorUpdatedAt},id.lt.${decodedCursor.cursorId})`
        )
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    const rows = (data ?? []) as ArticleRow[]
    const hasMore = rows.length > input.limit
    const pageRows = hasMore ? rows.slice(0, input.limit) : rows
    const lastRow = pageRows.at(-1)

    return {
        items: pageRows.map(formatArticleDeskList),
        nextCursor: hasMore && lastRow ? encodeUpdatedAtCursor(lastRow.updated_at, lastRow.id) : null,
        hasMore,
    }
}

async function loadAdminArticle(editorialId: string) {
    const article = await fetchArticleById(editorialId, ARTICLE_ADMIN_SELECT)
    if (!article) throw new Error("ARTICLE_NOT_FOUND")
    return formatArticleAdmin(article)
}

export async function getAdminArticle(actor: WriterRow, editorialId: string) {
    await requireDeskArticleAccess(actor, editorialId)
    return loadAdminArticle(editorialId)
}

export async function listAdminArticles(input: {
    status: string
    cursor?: string | undefined
    limit: number
}) {
    let query = supabase
        .schema("public")
        .from("editorials")
        .select(ARTICLE_DESK_LIST_SELECT)
        .order("updated_at", { ascending: false })
        .order("id", { ascending: false })
        .limit(input.limit + 1)

    if (input.status && input.status !== "all") {
        query = query.eq("status", input.status)
    }

    const decodedCursor = decodeUpdatedAtCursor(input.cursor)
    if (decodedCursor) {
        query = query.or(
            `updated_at.lt.${decodedCursor.cursorUpdatedAt},and(updated_at.eq.${decodedCursor.cursorUpdatedAt},id.lt.${decodedCursor.cursorId})`
        )
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    const rows = (data ?? []) as ArticleRow[]
    const hasMore = rows.length > input.limit
    const pageRows = hasMore ? rows.slice(0, input.limit) : rows
    const lastRow = pageRows.at(-1)

    return {
        items: pageRows.map(formatArticleDeskList),
        nextCursor: hasMore && lastRow ? encodeUpdatedAtCursor(lastRow.updated_at, lastRow.id) : null,
        hasMore,
    }
}

export async function deleteAdminArticle(actor: WriterRow, editorialId: string) {
    if (!isAdminRole(actor.role)) throw new Error("FORBIDDEN")

    const existing = await fetchArticleById(editorialId, "id")
    if (!existing) throw new Error("ARTICLE_NOT_FOUND")

    const { error } = await supabase.schema("public").from("editorials").delete().eq("id", editorialId)
    if (error) throw new Error(error.message)

    return { id: editorialId, deleted: true }
}

async function insertReviewRecord(input: {
    editorialId: string
    reviewerId: string
    decision: string | null
    notes?: string | null
}) {
    const { error } = await supabase.schema("public").from("editorial_reviews").insert({
        id: generateRandomId(16),
        editorial_id: input.editorialId,
        reviewer_id: input.reviewerId,
        decision: input.decision,
        notes: input.notes ?? null,
    })

    if (error) throw new Error(error.message)
}

export async function startReview(reviewer: WriterRow, editorialId: string) {
    const article = await fetchArticleById(editorialId, "id, status")
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["submitted"], "in_review")

    return loadAdminArticle(editorialId)
}

export async function requestChanges(
    reviewer: WriterRow,
    editorialId: string,
    notes?: string
) {
    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["submitted", "in_review"], "changes_requested")

    await Promise.all([
        insertReviewRecord({
            editorialId,
            reviewerId: reviewer.id,
            decision: "changes_requested",
            notes: notes ?? null,
        }),
        createRevisionSnapshot({
            editorialId,
            createdBy: reviewer.id,
            revisionType: "changes_requested",
            title: article.title,
            subtitle: article.subtitle,
            excerpt: article.excerpt,
            content: article.content,
        }),
    ])

    return loadAdminArticle(editorialId)
}

export async function approveArticle(reviewer: WriterRow, editorialId: string, notes?: string) {
    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["submitted", "in_review"], "approved")

    await Promise.all([
        insertReviewRecord({
            editorialId,
            reviewerId: reviewer.id,
            decision: "approved",
            notes: notes ?? null,
        }),
        createRevisionSnapshot({
            editorialId,
            createdBy: reviewer.id,
            revisionType: "approved",
            title: article.title,
            subtitle: article.subtitle,
            excerpt: article.excerpt,
            content: article.content,
        }),
    ])

    return loadAdminArticle(editorialId)
}

export async function rejectArticle(reviewer: WriterRow, editorialId: string, reason: string) {
    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["submitted", "in_review", "approved"], "rejected")

    await insertReviewRecord({
        editorialId,
        reviewerId: reviewer.id,
        decision: "rejected",
        notes: reason,
    })

    return loadAdminArticle(editorialId)
}

export async function publishArticle(
    reviewer: WriterRow,
    editorialId: string,
    body: PublishArticleSchema
) {
    await requireDeskArticleAccess(reviewer, editorialId)

    const article = await fetchArticleById(
        editorialId,
        "id, status, title, subtitle, excerpt, content, slug"
    )
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    const publishedAt = body.publishedAt ?? new Date().toISOString()

    await transitionArticleStatus(editorialId, [...DESK_PUBLISH_STATUSES], "published", {
        published_at: publishedAt,
    })

    await ensureEditorCredit(editorialId, reviewer.id)

    await createRevisionSnapshot({
        editorialId,
        createdBy: reviewer.id,
        revisionType: "published",
        title: article.title,
        subtitle: article.subtitle,
        excerpt: article.excerpt,
        content: article.content,
    })

    return loadAdminArticle(editorialId)
}

export async function archiveArticle(reviewer: WriterRow, editorialId: string) {
    if (!isAdminRole(reviewer.role)) throw new Error("FORBIDDEN")

    const article = await fetchArticleById(editorialId, "id, status")
    if (!article) throw new Error("ARTICLE_NOT_FOUND")

    await transitionArticleStatus(editorialId, ["published"], "archived")

    return loadAdminArticle(editorialId)
}

export async function updateAdminArticle(
    actor: WriterRow,
    editorialId: string,
    body: UpdateAdminArticleSchema
) {
    await requireDeskArticleAccess(actor, editorialId)

    const existing = await fetchArticleById(editorialId, "id, slug, type, status")
    if (!existing) throw new Error("ARTICLE_NOT_FOUND")

    if (body.slug !== undefined || body.type !== undefined) {
        await assertArticleSlugAvailable(
            body.slug ?? existing.slug,
            body.type ?? existing.type,
            editorialId
        )
    }

    const updateRow = {
        ...buildArticleUpdateRow(body),
        ...(existing.status === "published"
            ? { status: "in_review", published_at: null }
            : {}),
    }

    if (Object.keys(updateRow).length > 0) {
        const { error } = await supabase
            .schema("public")
            .from("editorials")
            .update(updateRow)
            .eq("id", editorialId)

        if (error) throw new Error(error.message)
    }

    if (body.tagSlugs) {
        await syncArticleTags(editorialId, body.tagSlugs)
    }

    await ensureEditorCredit(editorialId, actor.id)

    return loadAdminArticle(editorialId)
}

export async function listAllWriters() {
    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .select(WRITER_ADMIN_SELECT)
        .order("created_at", { ascending: false })

    if (error) throw new Error(error.message)

    return (data ?? []).map((row) => formatWriterAdmin(row as WriterRow))
}

export async function updateWriterAdmin(writerId: string, body: UpdateAdminWriterProfileSchema) {
    const { data: existing, error: existingError } = await supabase
        .schema("public")
        .from("writers")
        .select("id, role")
        .eq("id", writerId)
        .maybeSingle()

    if (existingError) throw new Error(existingError.message)
    if (!existing) throw new Error("WRITER_NOT_FOUND")

    if (body.slug !== undefined) {
        await assertWriterSlugAvailable(body.slug, writerId)
    }

    const updateRow: Record<string, unknown> = {}

    if (body.bio !== undefined) updateRow.bio = body.bio
    if (body.displayName !== undefined) updateRow.display_name = body.displayName
    if (body.specialties !== undefined) updateRow.specialties = body.specialties
    if (body.location !== undefined) updateRow.location = body.location
    if (body.internalNotes !== undefined) updateRow.internal_notes = body.internalNotes
    if (body.onboardingCompleted !== undefined) {
        updateRow.onboarding_completed = body.onboardingCompleted
    }
    if (body.slug !== undefined) updateRow.slug = body.slug

    if (body.status !== undefined) {
        updateRow.status = body.status
        updateRow.is_active = body.status === "active"
    }

    if (body.isActive !== undefined) {
        updateRow.is_active = body.isActive
        if (body.status === undefined) {
            updateRow.status = body.isActive ? "active" : "inactive"
        }
    }

    if (body.role !== undefined && body.role !== existing.role) {
        updateRow.role = body.role
        updateRow.role_updated_at = new Date().toISOString()

        if (body.role === "verified") updateRow.verified_at = new Date().toISOString()
        if (body.role === "senior") updateRow.senior_at = new Date().toISOString()
        if (body.role === "editor" || body.role === "admin") {
            updateRow.editor_at = new Date().toISOString()
        }
    }

    if (Object.keys(updateRow).length === 0) {
        throw new Error("No changes provided")
    }

    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .update(updateRow)
        .eq("id", writerId)
        .select(WRITER_ADMIN_SELECT)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("WRITER_NOT_FOUND")

    return formatWriterAdmin(data as WriterRow)
}

export async function trackEngagement(
    editorialId: string,
    viewerId: string | null,
    body: EngagementEventSchema
) {
    const article = await fetchArticleById(editorialId, "id, status, published_at")
    if (!article || !isPubliclyVisibleArticle(article)) {
        throw new Error("ARTICLE_NOT_FOUND")
    }

    const sessionId = body.sessionId.trim()
    if (!sessionId) {
        throw new Error("SESSION_REQUIRED")
    }

    if (body.engagedSeconds < 15) {
        throw new Error("ENGAGEMENT_TOO_SHORT")
    }

    if ((body.scrollDepth ?? 0) < 1) {
        throw new Error("ENGAGEMENT_NO_SCROLL")
    }

    // authors dont pad their own numbers. editors still count if they didnt write it
    if (viewerId) {
        const writer = await getWriterByProfileId(viewerId)
        if (writer && (await isWriterOnArticle(writer.id, editorialId))) {
            return { tracked: false, skipped: "own_article" as const }
        }
    }

    const todayStart = new Date()
    todayStart.setUTCHours(0, 0, 0, 0)

    let dedupeQuery = supabase
        .schema("public")
        .from("editorial_views")
        .select("id", { count: "exact", head: true })
        .eq("editorial_id", editorialId)
        .gte("viewed_at", todayStart.toISOString())

    if (viewerId) {
        dedupeQuery = dedupeQuery.eq("viewer_id", viewerId)
    } else {
        dedupeQuery = dedupeQuery.eq("session_id", sessionId)
    }

    const { count: priorViews, error: dedupeError } = await dedupeQuery
    if (dedupeError) throw new Error(dedupeError.message)

    // one view per person (or anon session) per piece per day
    if ((priorViews ?? 0) > 0) {
        return { tracked: false, skipped: "already_counted" as const }
    }

    const countUniqueReader = true
    const viewId = generateRandomId(16)

    const { data, error } = await supabase.schema("public").rpc("track_editorial_engagement", {
        p_view_id: viewId,
        p_editorial_id: editorialId,
        p_viewer_id: viewerId,
        p_session_id: sessionId,
        p_referrer: body.referrer ?? null,
        p_engaged_seconds: body.engagedSeconds,
        p_scroll_depth: body.scrollDepth ?? null,
        p_count_unique_reader: countUniqueReader,
    })

    if (error) {
        // fallback when rpc isn't deployed yet
        const { error: viewError } = await supabase.schema("public").from("editorial_views").insert({
            id: viewId,
            editorial_id: editorialId,
            viewer_id: viewerId,
            session_id: sessionId,
            referrer: body.referrer ?? null,
            engaged_seconds: body.engagedSeconds,
            scroll_depth: body.scrollDepth ?? null,
        })

        if (viewError) throw new Error(viewError.message)

        return { tracked: true, viewId, countedUniqueReader: countUniqueReader }
    }

    return {
        tracked: true,
        viewId,
        countedUniqueReader: countUniqueReader,
        ...(typeof data === "object" && data !== null ? data : {}),
    }
}

export async function getWriterAnalytics(writer: WriterRow, days: number) {
    const since = new Date()
    since.setDate(since.getDate() - days)
    const sinceDate = since.toISOString().slice(0, 10)

    const { data: credits, error: creditError } = await supabase
        .schema("public")
        .from("editorial_credits")
        .select("editorial_id")
        .eq("writer_id", writer.id)
        .eq("credit_type", "writer")

    if (creditError) throw new Error(creditError.message)

    const editorialIds = (credits ?? []).map((row) => row.editorial_id)
    if (editorialIds.length === 0) {
        return {
            days,
            totals: {
                pageViews: 0,
                uniqueReaders: 0,
                qualifiedReads: 0,
                totalEngagedSeconds: 0,
            },
            articles: [],
        }
    }

    const { data: stats, error: statsError } = await supabase
        .schema("public")
        .from("editorial_daily_stats")
        .select("editorial_id, page_views, unique_readers, qualified_reads, total_engaged_seconds")
        .in("editorial_id", editorialIds)
        .gte("date", sinceDate)

    if (statsError) throw new Error(statsError.message)

    const totals = {
        pageViews: 0,
        uniqueReaders: 0,
        qualifiedReads: 0,
        totalEngagedSeconds: 0,
    }

    const byArticle = new Map<
        string,
        {
            pageViews: number
            uniqueReaders: number
            qualifiedReads: number
            totalEngagedSeconds: number
        }
    >()

    for (const row of stats ?? []) {
        totals.pageViews += Number(row.page_views)
        totals.uniqueReaders += Number(row.unique_readers)
        totals.qualifiedReads += Number(row.qualified_reads)
        totals.totalEngagedSeconds += Number(row.total_engaged_seconds)

        const current = byArticle.get(row.editorial_id) ?? {
            pageViews: 0,
            uniqueReaders: 0,
            qualifiedReads: 0,
            totalEngagedSeconds: 0,
        }

        current.pageViews += Number(row.page_views)
        current.uniqueReaders += Number(row.unique_readers)
        current.qualifiedReads += Number(row.qualified_reads)
        current.totalEngagedSeconds += Number(row.total_engaged_seconds)
        byArticle.set(row.editorial_id, current)
    }

    const { data: articles, error: articlesError } = await supabase
        .schema("public")
        .from("editorials")
        .select("id, title, slug, type, status, published_at")
        .in("id", editorialIds)

    if (articlesError) throw new Error(articlesError.message)

    return {
        days,
        totals,
        articles: (articles ?? [])
            .map((article) => ({
                id: article.id,
                title: article.title,
                slug: article.slug,
                type: article.type,
                status: article.status,
                publishedAt: article.published_at,
                stats: byArticle.get(article.id) ?? {
                    pageViews: 0,
                    uniqueReaders: 0,
                    qualifiedReads: 0,
                    totalEngagedSeconds: 0,
                },
            }))
            .sort((a, b) => b.stats.pageViews - a.stats.pageViews),
    }
}

// sitewide popular board for editors, last N days
export async function getDeskAnalytics(days: number, limit = 20) {
    const since = new Date()
    since.setDate(since.getDate() - days)
    const sinceDate = since.toISOString().slice(0, 10)

    const { data: stats, error: statsError } = await supabase
        .schema("public")
        .from("editorial_daily_stats")
        .select("editorial_id, page_views, unique_readers, qualified_reads, total_engaged_seconds")
        .gte("date", sinceDate)

    if (statsError) throw new Error(statsError.message)

    const totals = {
        pageViews: 0,
        uniqueReaders: 0,
        qualifiedReads: 0,
        totalEngagedSeconds: 0,
    }

    const byArticle = new Map<
        string,
        {
            pageViews: number
            uniqueReaders: number
            qualifiedReads: number
            totalEngagedSeconds: number
        }
    >()

    for (const row of stats ?? []) {
        totals.pageViews += Number(row.page_views)
        totals.uniqueReaders += Number(row.unique_readers)
        totals.qualifiedReads += Number(row.qualified_reads)
        totals.totalEngagedSeconds += Number(row.total_engaged_seconds)

        const current = byArticle.get(row.editorial_id) ?? {
            pageViews: 0,
            uniqueReaders: 0,
            qualifiedReads: 0,
            totalEngagedSeconds: 0,
        }

        current.pageViews += Number(row.page_views)
        current.uniqueReaders += Number(row.unique_readers)
        current.qualifiedReads += Number(row.qualified_reads)
        current.totalEngagedSeconds += Number(row.total_engaged_seconds)
        byArticle.set(row.editorial_id, current)
    }

    const topIds = [...byArticle.entries()]
        .sort((a, b) => b[1].pageViews - a[1].pageViews)
        .slice(0, limit)
        .map(([id]) => id)

    if (topIds.length === 0) {
        return { days, totals, popular: [] }
    }

    const { data: articles, error: articlesError } = await supabase
        .schema("public")
        .from("editorials")
        .select("id, title, slug, type, status, published_at")
        .in("id", topIds)

    if (articlesError) throw new Error(articlesError.message)

    const articleById = new Map((articles ?? []).map((row) => [row.id, row]))

    return {
        days,
        totals,
        popular: topIds
            .map((id) => {
                const article = articleById.get(id)
                if (!article || article.status !== "published") return null
                return {
                    id: article.id,
                    title: article.title,
                    slug: article.slug,
                    type: article.type,
                    status: article.status,
                    publishedAt: article.published_at,
                    stats: byArticle.get(id) ?? {
                        pageViews: 0,
                        uniqueReaders: 0,
                        qualifiedReads: 0,
                        totalEngagedSeconds: 0,
                    },
                }
            })
            .filter((row): row is NonNullable<typeof row> => Boolean(row)),
    }
}

export async function getArticleAnalytics(writer: WriterRow, editorialId: string, days: number) {
    await requireWriterArticleAccess(writer, editorialId)

    const since = new Date()
    since.setDate(since.getDate() - days)
    const sinceDate = since.toISOString().slice(0, 10)

    const { data: stats, error } = await supabase
        .schema("public")
        .from("editorial_daily_stats")
        .select("date, page_views, unique_readers, qualified_reads, total_engaged_seconds")
        .eq("editorial_id", editorialId)
        .gte("date", sinceDate)
        .order("date", { ascending: true })

    if (error) throw new Error(error.message)

    const totals = (stats ?? []).reduce(
        (acc, row) => {
            acc.pageViews += Number(row.page_views)
            acc.uniqueReaders += Number(row.unique_readers)
            acc.qualifiedReads += Number(row.qualified_reads)
            acc.totalEngagedSeconds += Number(row.total_engaged_seconds)
            return acc
        },
        {
            pageViews: 0,
            uniqueReaders: 0,
            qualifiedReads: 0,
            totalEngagedSeconds: 0,
        }
    )

    return {
        editorialId,
        days,
        totals,
        daily: (stats ?? []).map((row) => ({
            date: row.date,
            pageViews: Number(row.page_views),
            uniqueReaders: Number(row.unique_readers),
            qualifiedReads: Number(row.qualified_reads),
            totalEngagedSeconds: Number(row.total_engaged_seconds),
        })),
    }
}
