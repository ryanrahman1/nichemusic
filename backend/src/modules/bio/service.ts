import { supabase } from "../../config/supabase.js"

export type BioSettings = {
    id: string
    title: string
    tagline: string | null
    avatar_url: string | null
    profile_id: string | null
    instagram_handle: string | null
    spotify_url: string | null
    tiktok_handle: string | null
    theme_accent: string
}

export type BioLink = {
    id: string
    label: string
    url: string
    emoji: string | null
    description: string | null
    sort_order: number
    featured: boolean
}

export type BioUpdate = {
    id: string
    title: string
    body: string | null
    link_url: string | null
    link_label: string | null
    image_url: string | null
    published_at: string
}

export type BioMessage = {
    id: string
    author_name: string
    author_handle: string | null
    author_avatar_url: string | null
    message: string
    source_url: string | null
    published_at: string
}

export type BioInstagramPost = {
    id: string
    instagram_id: string
    caption: string | null
    media_url: string
    media_type: string
    permalink: string
    thumbnail_url: string | null
    posted_at: string
}

export type BioEditorial = {
    id: string
    name: string
    subtitle: string | null
    link: string
    image_url: string | null
    created_at: string
}

type EditorialRow = {
    id: string
    slug: string
    title: string
    subtitle: string | null
    type: string
    cover_image_url: string | null
    created_at: string
}

export type BioPageData = {
    settings: BioSettings | null
    links: BioLink[]
    updates: BioUpdate[]
    messages: BioMessage[]
    instagramPosts: BioInstagramPost[]
    editorials: BioEditorial[]
}

// turn the new editorial rows back into the old bio card contract
function editorialLink(article: Pick<EditorialRow, "type" | "slug">): string {
    const section = article.type === "review"
        ? "reviews"
        : article.type === "spotlight"
            ? "spotlights"
            : "news"

    return `https://nichemusic.app/${section}/${encodeURIComponent(article.slug)}`
}

// grab everything for the link-in-bio page
export async function fetchBioPageData(): Promise<BioPageData> {
    const [
        settingsRes,
        linksRes,
        updatesRes,
        messagesRes,
        instagramRes,
        editorialsRes,
    ] = await Promise.all([
        supabase
            .schema("public")
            .from("bio_settings")
            .select("*")
            .eq("active", true)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("bio_links")
            .select("*")
            .eq("active", true)
            .order("sort_order"),
        supabase
            .schema("public")
            .from("bio_updates")
            .select("*")
            .eq("active", true)
            .order("published_at", { ascending: false }),
        supabase
            .schema("public")
            .from("bio_messages")
            .select("*")
            .eq("active", true)
            .order("published_at", { ascending: false }),
        supabase
            .schema("public")
            .from("bio_instagram_posts")
            .select("*")
            .eq("active", true)
            .order("posted_at", { ascending: false }),
        supabase
            .schema("public")
            .from("editorials")
            .select("id, slug, title, subtitle, type, cover_image_url, created_at")
            .eq("status", "published")
            .lte("published_at", new Date().toISOString())
            .order("published_at", { ascending: false, nullsFirst: false }),
    ])

    const firstError =
        settingsRes.error ??
        linksRes.error ??
        updatesRes.error ??
        messagesRes.error ??
        instagramRes.error ??
        editorialsRes.error

    if (firstError) throw new Error(firstError.message)

    return {
        settings: settingsRes.data,
        links: linksRes.data ?? [],
        updates: updatesRes.data ?? [],
        messages: messagesRes.data ?? [],
        instagramPosts: instagramRes.data ?? [],
        editorials: ((editorialsRes.data ?? []) as EditorialRow[]).map((article) => ({
            id: article.id,
            name: article.title,
            subtitle: article.subtitle,
            link: editorialLink(article),
            image_url: article.cover_image_url,
            created_at: article.created_at,
        })),
    }
}
