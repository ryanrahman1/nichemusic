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

export type BioPageData = {
    settings: BioSettings | null
    links: BioLink[]
    updates: BioUpdate[]
    messages: BioMessage[]
    instagramPosts: BioInstagramPost[]
    editorials: BioEditorial[]
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
            .select("id, name, subtitle, link, image_url, created_at")
            .eq("active", true)
            .is("deleted_at", null)
            .order("created_at", { ascending: false }),
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
        editorials: editorialsRes.data ?? [],
    }
}
