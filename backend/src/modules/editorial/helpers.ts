import { supabase } from "../../config/supabase.js"
import { toUtcZulu } from "../../lib/datetime.js"

export type WriterRole = "contributor" | "verified" | "senior" | "editor" | "admin"

export type ProfileSnippet = {
    id: string
    username: string
    display_name: string | null
    avatar_url: string | null
    is_verified: boolean | null
    verification_type: string | null
    followers_count?: number | null
}

export type WriterStatus = "active" | "inactive" | "suspended" | "left"

export type WriterRow = {
    id: string
    profile_id: string
    slug: string
    role: WriterRole
    bio: string | null
    is_active: boolean
    status: WriterStatus
    display_name: string | null
    specialties: string[]
    location: string | null
    onboarding_completed: boolean
    internal_notes?: string | null
    published_count: number
    total_views: number
    qualified_reads: number
    articles_submitted: number
    articles_approved: number
    articles_rejected: number
    last_active_at: string | null
    last_published_at: string | null
    verified_at: string | null
    senior_at: string | null
    editor_at: string | null
    role_updated_at: string | null
    joined_at: string
    created_by: string | null
    created_at: string
    updated_at: string
    profile?: ProfileSnippet | ProfileSnippet[] | null
}

export type TagRow = {
    id: string
    name: string
    slug: string
}

export type CreditWriter = {
    id: string
    slug: string
    role?: WriterRole | string | null
    bio?: string | null
    profile: ProfileSnippet | ProfileSnippet[] | null
}

export type CreditRow = {
    credit_type: string
    position: number
    writer: CreditWriter | CreditWriter[] | null
}

export type ArticleRow = {
    id: string
    slug: string
    title: string
    subtitle: string | null
    excerpt: string | null
    type: string
    template: string
    template_data: unknown
    status: string
    cover_image_url: string | null
    cover_image_alt: string | null
    cover_image_credit: string | null
    content: unknown
    meta_title: string | null
    meta_description: string | null
    is_sponsored: boolean
    sponsor_name: string | null
    published_at: string | null
    created_at: string
    updated_at: string
    credits?: CreditRow[] | null
    tags?: { tag: TagRow | TagRow[] | null }[] | null
    reviews?: ReviewRow[] | null
}

export type ReviewRow = {
    id: string
    decision: string | null
    notes: string | null
    created_at: string
    reviewer: {
        id: string
        slug: string
        profile: ProfileSnippet | ProfileSnippet[] | null
    } | {
        id: string
        slug: string
        profile: ProfileSnippet | ProfileSnippet[] | null
    }[] | null
}

export const WRITER_BASE_COLUMNS = `
    id,
    profile_id,
    slug,
    role,
    bio,
    is_active,
    status,
    display_name,
    specialties,
    location,
    onboarding_completed,
    published_count,
    total_views,
    qualified_reads,
    articles_submitted,
    articles_approved,
    articles_rejected,
    last_active_at,
    last_published_at,
    verified_at,
    senior_at,
    editor_at,
    role_updated_at,
    joined_at,
    created_by,
    created_at,
    updated_at
`

export const WRITER_PROFILE_SELECT = `
    ${WRITER_BASE_COLUMNS},
    profile:profiles!writers_profile_id_fkey(
        id,
        username,
        display_name,
        avatar_url,
        is_verified,
        verification_type
    )
`

export const WRITER_ADMIN_SELECT = `
    ${WRITER_BASE_COLUMNS},
    internal_notes,
    profile:profiles!writers_profile_id_fkey(
        id,
        username,
        display_name,
        avatar_url,
        is_verified,
        verification_type
    )
`

export const ARTICLE_CARD_SELECT = `
    id,
    slug,
    title,
    subtitle,
    excerpt,
    type,
    template,
    cover_image_url,
    cover_image_alt,
    template_data,
    is_sponsored,
    sponsor_name,
    published_at,
    created_at,
    credits:editorial_credits(
        credit_type,
        position,
        writer:writers(
            id,
            slug,
            role,
            bio,
            profile:profiles!writers_profile_id_fkey(id, username, display_name, avatar_url, is_verified, verification_type)
        )
    ),
    tags:editorial_tag_links(
        tag:editorial_tags(id, name, slug)
    )
`

export const ARTICLE_PUBLIC_SELECT = `
    ${ARTICLE_CARD_SELECT},
    cover_image_credit,
    content,
    meta_title,
    meta_description
`

// homepage cards need status plus the same slim template bits
export const ARTICLE_HOME_SELECT = `
    ${ARTICLE_CARD_SELECT},
    status
`

// desk list dont need the body — keep this skinny
export const ARTICLE_WRITER_LIST_SELECT = `
    id,
    slug,
    title,
    subtitle,
    excerpt,
    type,
    template,
    status,
    cover_image_url,
    cover_image_alt,
    template_data,
    is_sponsored,
    sponsor_name,
    published_at,
    created_at,
    updated_at
`

export const ARTICLE_WRITER_SELECT = `
    ${ARTICLE_PUBLIC_SELECT},
    status,
    updated_at,
    reviews:editorial_reviews(
        id,
        decision,
        notes,
        created_at,
        reviewer:writers(
            id,
            slug,
            profile:profiles!writers_profile_id_fkey(id, username, display_name, avatar_url)
        )
    )
`

export const ARTICLE_ADMIN_SELECT = ARTICLE_WRITER_SELECT

// desk queues dont need the body, just credits so we know who wrote it
export const ARTICLE_DESK_LIST_SELECT = `
    ${ARTICLE_WRITER_LIST_SELECT},
    credits:editorial_credits(
        credit_type,
        position,
        writer:writers(
            id,
            slug,
            role,
            bio,
            profile:profiles!writers_profile_id_fkey(id, username, display_name, avatar_url, is_verified, verification_type)
        )
    )
`

export const WRITER_EDITABLE_STATUSES = ["draft", "changes_requested", "rejected", "published"] as const
export const WRITER_SUBMITTABLE_STATUSES = ["draft", "changes_requested", "rejected", "published"] as const
export const WRITER_SELF_PUBLISH_STATUSES = ["submitted", "in_review", "approved"] as const
export const EDITOR_QUEUE_STATUSES = ["submitted", "in_review", "approved"] as const
export const DESK_PUBLISH_STATUSES = ["submitted", "in_review", "approved"] as const

export function publishedBeforeNowIso(): string {
    return new Date().toISOString()
}

/** escape user text for safe ilike patterns */
export function sanitizeIlikePattern(value: string): string {
    return value
        .replace(/\\/g, "\\\\")
        .replace(/%/g, "\\%")
        .replace(/_/g, "\\_")
        .replace(/,/g, "")
}

export function toIlikePattern(value: string): string {
    return `%${sanitizeIlikePattern(value.trim())}%`
}

export function isEditorRole(role: string): boolean {
    return role === "editor" || role === "admin"
}

export function isAdminRole(role: string): boolean {
    return role === "admin"
}

// editors can reopen published pieces for a fresh review pass
export function canAccessDeskArticle(actor: WriterRow, status: string) {
    if (isAdminRole(actor.role)) return true
    if (isEditorRole(actor.role)) {
        return (
            (EDITOR_QUEUE_STATUSES as readonly string[]).includes(status) ||
            status === "published"
        )
    }
    return false
}

export function encodeEditorialCursor(publishedAt: string, id: string): string {
    return JSON.stringify({
        cursorPublishedAt: toUtcZulu(publishedAt),
        cursorId: id,
    })
}

export function decodeEditorialCursor(cursor: string | undefined): {
    cursorPublishedAt: string
    cursorId: string
} | null {
    if (!cursor) return null

    try {
        const parsed = JSON.parse(cursor) as {
            cursorPublishedAt?: string
            cursorId?: string
        }

        if (!parsed.cursorPublishedAt || !parsed.cursorId) return null

        return {
            cursorPublishedAt: toUtcZulu(parsed.cursorPublishedAt),
            cursorId: parsed.cursorId,
        }
    } catch {
        return null
    }
}

export function encodeUpdatedAtCursor(updatedAt: string, id: string): string {
    return JSON.stringify({
        cursorUpdatedAt: toUtcZulu(updatedAt),
        cursorId: id,
    })
}

export function decodeUpdatedAtCursor(cursor: string | undefined): {
    cursorUpdatedAt: string
    cursorId: string
} | null {
    if (!cursor) return null

    try {
        const parsed = JSON.parse(cursor) as {
            cursorUpdatedAt?: string
            cursorId?: string
        }

        if (!parsed.cursorUpdatedAt || !parsed.cursorId) return null

        return {
            cursorUpdatedAt: toUtcZulu(parsed.cursorUpdatedAt),
            cursorId: parsed.cursorId,
        }
    } catch {
        return null
    }
}

function pickProfile(profile: ProfileSnippet | ProfileSnippet[] | null | undefined) {
    if (!profile) return null
    return Array.isArray(profile) ? profile[0] ?? null : profile
}

function pickWriter(writer: CreditRow["writer"]) {
    if (!writer) return null
    return Array.isArray(writer) ? writer[0] ?? null : writer
}

function pickTag(tag: TagRow | TagRow[] | null | undefined) {
    if (!tag) return null
    return Array.isArray(tag) ? tag[0] ?? null : tag
}

export function formatProfileSnippet(profile: ProfileSnippet | null) {
    if (!profile) return null

    return {
        id: profile.id,
        username: profile.username,
        displayName: profile.display_name,
        avatarUrl: profile.avatar_url,
        isVerified: profile.is_verified ?? false,
        verificationType: profile.verification_type,
        followersCount: profile.followers_count ?? 0,
    }
}

export function isWriterActive(row: WriterRow): boolean {
    return row.status === "active" && row.is_active && row.onboarding_completed
}

export function formatWriterStats(
    row: WriterRow,
    extras?: { editedCount?: number; followersCount?: number }
) {
    const profile = pickProfile(row.profile ?? null)

    return {
        publishedCount: row.published_count,
        editedCount: extras?.editedCount ?? 0,
        followersCount: extras?.followersCount ?? profile?.followers_count ?? 0,
        totalViews: row.total_views,
        qualifiedReads: row.qualified_reads,
        articlesSubmitted: row.articles_submitted,
        articlesApproved: row.articles_approved,
        articlesRejected: row.articles_rejected,
    }
}

export function formatWriterPublic(
    row: WriterRow,
    extras?: { editedCount?: number; followersCount?: number }
) {
    const profile = pickProfile(row.profile ?? null)

    return {
        id: row.id,
        slug: row.slug,
        role: row.role,
        bio: row.bio,
        displayName: row.display_name,
        specialties: row.specialties,
        location: row.location,
        status: row.status,
        joinedAt: row.joined_at,
        lastPublishedAt: row.last_published_at,
        createdAt: row.created_at,
        profile: formatProfileSnippet(profile),
        stats: formatWriterStats(row, extras),
    }
}

export function formatWriterSelf(row: WriterRow) {
    return {
        ...formatWriterPublic(row),
        onboardingCompleted: row.onboarding_completed,
        lastActiveAt: row.last_active_at,
        verifiedAt: row.verified_at,
        seniorAt: row.senior_at,
        editorAt: row.editor_at,
        roleUpdatedAt: row.role_updated_at,
    }
}

export function formatWriterAdmin(row: WriterRow) {
    return {
        ...formatWriterSelf(row),
        internalNotes: row.internal_notes ?? null,
        createdBy: row.created_by,
        isActive: row.is_active,
    }
}

export function formatCredit(credit: CreditRow) {
    const writer = pickWriter(credit.writer)
    const profile = writer ? pickProfile(writer.profile) : null

    return {
        creditType: credit.credit_type,
        position: credit.position,
        writer: writer
            ? {
                  id: writer.id,
                  slug: writer.slug,
                  role: writer.role ?? null,
                  bio: writer.bio ?? null,
                  profile: formatProfileSnippet(profile),
              }
            : null,
    }
}

export function formatTags(tags: ArticleRow["tags"]) {
    return (tags ?? [])
        .map((link) => pickTag(link.tag))
        .filter((tag): tag is TagRow => !!tag)
        .map((tag) => ({
            id: tag.id,
            name: tag.name,
            slug: tag.slug,
        }))
}

export function formatArticleCard(row: ArticleRow) {
    return {
        id: row.id,
        slug: row.slug,
        title: row.title,
        subtitle: row.subtitle,
        excerpt: row.excerpt,
        type: row.type,
        template: row.template,
        coverImageUrl: row.cover_image_url,
        coverImageAlt: row.cover_image_alt,
        // portraits/artwork so cards dont go blank when theres no hero
        templateData: slimHomeTemplateData(row.template_data),
        isSponsored: row.is_sponsored,
        sponsorName: row.sponsor_name,
        publishedAt: row.published_at,
        createdAt: row.created_at,
        credits: (row.credits ?? []).map(formatCredit),
        tags: formatTags(row.tags),
    }
}

const HOME_TEMPLATE_KEYS = [
    "rating",
    "badge",
    "artworkUrl",
    "artist",
    "album",
    "portraitUrl",
] as const

// only ship the template bits the homepage actually paints
export function slimHomeTemplateData(data: unknown) {
    if (!data || typeof data !== "object") return {}

    const raw = data as Record<string, unknown>
    const out: Record<string, unknown> = {}

    for (const key of HOME_TEMPLATE_KEYS) {
        const value = raw[key]
        if (value == null || value === "") continue
        out[key] = value
    }

    return out
}

export function formatArticleHome(row: ArticleRow) { // card plus the tiny template bits the hero needs
    return {
        ...formatArticleCard(row),
        templateData: slimHomeTemplateData(row.template_data),
    }
}

export function formatArticlePublic(row: ArticleRow) {
    return {
        ...formatArticleCard(row),
        templateData: row.template_data ?? {},
        coverImageCredit: row.cover_image_credit,
        content: row.content,
        metaTitle: row.meta_title,
        metaDescription: row.meta_description,
    }
}

export function formatArticleWriterList(row: ArticleRow) {
    return {
        id: row.id,
        slug: row.slug,
        title: row.title,
        subtitle: row.subtitle,
        excerpt: row.excerpt,
        type: row.type,
        template: row.template,
        status: row.status,
        coverImageUrl: row.cover_image_url,
        coverImageAlt: row.cover_image_alt,
        // portraits/artwork so spotlight cards aint blank without a hero
        templateData: slimHomeTemplateData(row.template_data),
        isSponsored: row.is_sponsored,
        sponsorName: row.sponsor_name,
        publishedAt: row.published_at,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
        tags: [] as ReturnType<typeof formatTags>,
    }
}

export function formatArticleDeskList(row: ArticleRow) {
    return {
        ...formatArticleWriterList(row),
        credits: (row.credits ?? []).map(formatCredit),
    }
}

export function formatArticleWriter(row: ArticleRow) {
    return {
        ...formatArticlePublic(row),
        status: row.status,
        updatedAt: row.updated_at,
        reviews: (row.reviews ?? []).map(formatReview),
    }
}

export function formatArticleAdmin(row: ArticleRow) {
    return formatArticleWriter(row)
}

export function formatReview(review: ReviewRow) {
    const reviewer = pickWriter(review.reviewer as CreditRow["writer"])
    const profile = reviewer ? pickProfile(reviewer.profile) : null

    return {
        id: review.id,
        decision: review.decision,
        notes: review.notes,
        createdAt: review.created_at,
        reviewer: reviewer
            ? {
                  id: reviewer.id,
                  slug: reviewer.slug,
                  profile: formatProfileSnippet(profile),
              }
            : null,
    }
}

export function buildWriterPermissions(row: WriterRow | null) {
    const active = row ? isWriterActive(row) : false

    return {
        canWrite: active,
        canSubmit: active,
        canReview: row ? isEditorRole(row.role) && row.status === "active" : false,
        canPublish: row ? isEditorRole(row.role) && row.status === "active" : false,
        canManageWriters: row ? isAdminRole(row.role) && row.status === "active" : false,
        canEditAny: row ? isAdminRole(row.role) && row.status === "active" : false,
        canDelete: row ? isAdminRole(row.role) && row.status === "active" : false,
    }
}

export async function getWriterByProfileId(profileId: string): Promise<WriterRow | null> {
    const { data, error } = await supabase
        .schema("public")
        .from("writers")
        .select(WRITER_PROFILE_SELECT)
        .eq("profile_id", profileId)
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data as WriterRow | null
}

export async function requireActiveWriter(profileId: string): Promise<WriterRow> {
    const writer = await getWriterByProfileId(profileId)

    if (!writer || !isWriterActive(writer)) {
        throw new Error("NOT_A_WRITER")
    }

    return writer
}

export async function requireEditorWriter(profileId: string): Promise<WriterRow> {
    const writer = await requireActiveWriter(profileId)

    if (!isEditorRole(writer.role)) {
        throw new Error("FORBIDDEN")
    }

    return writer
}

export async function requireAdminWriter(profileId: string): Promise<WriterRow> {
    const writer = await requireActiveWriter(profileId)

    if (!isAdminRole(writer.role)) {
        throw new Error("FORBIDDEN")
    }

    return writer
}

export async function isWriterOnArticle(writerId: string, editorialId: string): Promise<boolean> {
    const { count, error } = await supabase
        .schema("public")
        .from("editorial_credits")
        .select("*", { count: "exact", head: true })
        .eq("editorial_id", editorialId)
        .eq("writer_id", writerId)
        .eq("credit_type", "writer")

    if (error) throw new Error(error.message)
    return (count ?? 0) > 0
}

export async function requireArticleWriterAccess(
    writer: WriterRow,
    editorialId: string
): Promise<void> {
    const hasAccess = await isWriterOnArticle(writer.id, editorialId)
    if (!hasAccess) {
        throw new Error("FORBIDDEN")
    }
}

export async function syncArticleTags(editorialId: string, tagSlugs: string[]): Promise<void> {
    const normalizedSlugs = [...new Set(tagSlugs.map((slug) => slug.trim().toLowerCase()).filter(Boolean))]

    if (normalizedSlugs.length === 0) {
        const { error } = await supabase
            .schema("public")
            .from("editorial_tag_links")
            .delete()
            .eq("editorial_id", editorialId)

        if (error) throw new Error(error.message)
        return
    }

    const { data: existingTags, error: existingTagsError } = await supabase
        .schema("public")
        .from("editorial_tags")
        .select("id, slug")
        .in("slug", normalizedSlugs)

    if (existingTagsError) throw new Error(existingTagsError.message)

    const tagIdBySlug = new Map((existingTags ?? []).map((tag) => [tag.slug, tag.id]))
    const missingSlugs = normalizedSlugs.filter((slug) => !tagIdBySlug.has(slug))

    if (missingSlugs.length > 0) {
        const { generateRandomId } = await import("../../lib/auth.js")
        const newTags = missingSlugs.map((slug) => ({
            id: generateRandomId(16),
            name: slug.replace(/-/g, " "),
            slug,
        }))

        const { data: insertedTags, error: insertTagsError } = await supabase
            .schema("public")
            .from("editorial_tags")
            .insert(newTags)
            .select("id, slug")

        if (insertTagsError) throw new Error(insertTagsError.message)

        for (const tag of insertedTags ?? []) {
            tagIdBySlug.set(tag.slug, tag.id)
        }
    }

    const tagIds = normalizedSlugs
        .map((slug) => tagIdBySlug.get(slug))
        .filter((id): id is string => !!id)

    const { error: deleteError } = await supabase
        .schema("public")
        .from("editorial_tag_links")
        .delete()
        .eq("editorial_id", editorialId)

    if (deleteError) throw new Error(deleteError.message)

    if (tagIds.length === 0) return

    const links = tagIds.map((tagId) => ({
        editorial_id: editorialId,
        tag_id: tagId,
    }))

    const { error: linkError } = await supabase
        .schema("public")
        .from("editorial_tag_links")
        .insert(links)

    if (linkError) throw new Error(linkError.message)
}

export async function createRevisionSnapshot(input: {
    editorialId: string
    createdBy: string | null
    revisionType: string
    title: string
    subtitle: string | null
    excerpt: string | null
    content: unknown
}): Promise<void> {
    const { generateRandomId } = await import("../../lib/auth.js")

    const { error } = await supabase.schema("public").from("editorial_revisions").insert({
        id: generateRandomId(16),
        editorial_id: input.editorialId,
        created_by: input.createdBy,
        title: input.title,
        subtitle: input.subtitle,
        excerpt: input.excerpt,
        content: input.content,
        revision_type: input.revisionType,
    })

    if (error) throw new Error(error.message)
}

export async function isWriterSlugAvailable(
    slug: string,
    excludeWriterId?: string | undefined
): Promise<boolean> {
    let query = supabase
        .schema("public")
        .from("writers")
        .select("id")
        .eq("slug", slug)
        .limit(1)

    if (excludeWriterId) {
        query = query.neq("id", excludeWriterId)
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return !data || data.length === 0
}

export async function assertWriterSlugAvailable(
    slug: string,
    excludeWriterId?: string | undefined
): Promise<void> {
    const available = await isWriterSlugAvailable(slug, excludeWriterId)
    if (!available) {
        throw new Error("SLUG_TAKEN")
    }
}

export async function isArticleSlugAvailable(
    slug: string,
    type: string,
    excludeEditorialId?: string | undefined
): Promise<boolean> {
    let query = supabase
        .schema("public")
        .from("editorials")
        .select("id")
        .eq("slug", slug)
        .eq("type", type)
        .limit(1)

    if (excludeEditorialId) {
        query = query.neq("id", excludeEditorialId)
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return !data || data.length === 0
}

export async function assertArticleSlugAvailable(
    slug: string,
    type: string,
    excludeEditorialId?: string | undefined
): Promise<void> {
    const available = await isArticleSlugAvailable(slug, type, excludeEditorialId)
    if (!available) {
        throw new Error("SLUG_TAKEN")
    }
}

export function mapServiceError(error: unknown): { code: string; message: string; status: number } {
    const message = error instanceof Error ? error.message : "Request failed"

    switch (message) {
        case "NOT_A_WRITER":
            return { code: "NOT_A_WRITER", message: "Writer profile required", status: 403 }
        case "FORBIDDEN":
            return { code: "FORBIDDEN", message: "You do not have permission for this action", status: 403 }
        case "ARTICLE_NOT_FOUND":
            return { code: "ARTICLE_NOT_FOUND", message: "Article not found", status: 404 }
        case "WRITER_NOT_FOUND":
            return { code: "WRITER_NOT_FOUND", message: "Writer not found", status: 404 }
        case "TAG_NOT_FOUND":
            return { code: "TAG_NOT_FOUND", message: "Tag not found", status: 404 }
        case "TRACK_NOT_FOUND":
            return { code: "TRACK_NOT_FOUND", message: "Could not load that Apple Music track", status: 400 }
        case "TRACK_ALREADY_ON_BOARD":
            return { code: "TRACK_ALREADY_ON_BOARD", message: "That track is already on New Music Friday", status: 409 }
        case "NEW_MUSIC_PICK_NOT_FOUND":
            return { code: "NEW_MUSIC_PICK_NOT_FOUND", message: "New Music Friday pick not found", status: 404 }
        case "INVALID_SCHEDULE":
            return { code: "INVALID_SCHEDULE", message: "showUntil has to be after showFrom", status: 400 }
        case "INVALID_STATUS_TRANSITION":
            return { code: "INVALID_STATUS_TRANSITION", message: "This action is not allowed in the current status", status: 400 }
        case "SLUG_TAKEN":
            return { code: "SLUG_TAKEN", message: "That slug is already in use", status: 409 }
        case "WRITER_ALREADY_EXISTS":
            return { code: "WRITER_ALREADY_EXISTS", message: "You already have a writer profile", status: 409 }
        case "WRITER_NOT_ONBOARDED":
            return { code: "WRITER_NOT_ONBOARDED", message: "Complete writer onboarding first", status: 403 }
        case "PROFILE_NOT_FOUND":
            return { code: "PROFILE_NOT_FOUND", message: "Profile not found", status: 404 }
        case "SESSION_REQUIRED":
            return { code: "SESSION_REQUIRED", message: "sessionId is required for engagement tracking", status: 400 }
        case "ENGAGEMENT_TOO_SHORT":
            return { code: "ENGAGEMENT_TOO_SHORT", message: "Need 15s on the piece before it counts", status: 400 }
        case "ENGAGEMENT_NO_SCROLL":
            return { code: "ENGAGEMENT_NO_SCROLL", message: "Need some scroll before it counts as a view", status: 400 }
        case "No changes provided":
            return { code: "VALIDATION_ERROR", message: "No changes provided", status: 400 }
        default:
            return { code: "EDITORIAL_REQUEST_FAILED", message, status: 500 }
    }
}
