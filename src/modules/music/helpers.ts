import { supabase } from "../../config/supabase.js"
import { trackSchema, type Track, albumSchema, type Album, artistSchema, type Artist } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import env from "../../config/env.js"

const MUSIC_BASE_URL = "https://api.music.apple.com/v1/catalog/us"
const APPLE_API_ORIGIN = "https://api.music.apple.com"

function resolveAppleCatalogNext(next: unknown): string | null {
    if (typeof next !== "string" || next.length === 0) return null
    if (next.startsWith("http://") || next.startsWith("https://")) return next
    if (next.startsWith("/v1/")) return `${APPLE_API_ORIGIN}${next}`
    return null
}

/** Fetches catalog track pages for an album and upserts rows (links `album_id` / `artist_id`). */
export async function syncAppleAlbumTracks(albumCatalogSourceId: string): Promise<void> {
    let url: string | null =
        `${MUSIC_BASE_URL}/albums/${encodeURIComponent(albumCatalogSourceId)}/tracks?limit=100`
    const headers = { Authorization: `Bearer ${env.apple.musicApiKey}` }
    while (url) {
        const result = await fetch(url, { headers })
        if (!result.ok) break
        const res = (await result.json()) as { data?: { id?: string }[]; next?: unknown }
        const songs = res.data ?? []
        for (const song of songs) {
            if (typeof song?.id === "string") await upsertTrack(song.id, "apple_music")
        }
        url = resolveAppleCatalogNext(res.next)
    }
}

export type SyncAppleArtistDiscographySummary = {
    catalogAlbumsSeen: number
    distinctAlbumsSynced: number
    albumsTracksLoaded: number
}

/**
 * Paginates Apple Music artist albums, upserts each, then loads every album’s tracks.
 * Heavy — intended for explicit user-triggered sync only.
 */
export async function syncAppleArtistDiscography(
    artistCatalogSourceId: string
): Promise<SyncAppleArtistDiscographySummary> {
    const seen = new Set<string>()
    const albumSourceIds: string[] = []
    let catalogAlbumsSeen = 0
    let url: string | null =
        `${MUSIC_BASE_URL}/artists/${encodeURIComponent(artistCatalogSourceId)}/albums?limit=25`
    const headers = { Authorization: `Bearer ${env.apple.musicApiKey}` }
    while (url) {
        const result = await fetch(url, { headers })
        if (!result.ok) break
        const res = (await result.json()) as { data?: { id?: string }[]; next?: unknown }
        for (const al of res.data ?? []) {
            if (typeof al?.id !== "string") continue
            catalogAlbumsSeen++
            await upsertAlbum(al.id, "apple_music")
            if (!seen.has(al.id)) {
                seen.add(al.id)
                albumSourceIds.push(al.id)
            }
        }
        url = resolveAppleCatalogNext(res.next)
    }
    let albumsTracksLoaded = 0
    for (const sid of albumSourceIds) {
        await syncAppleAlbumTracks(sid)
        albumsTracksLoaded++
    }
    return {
        catalogAlbumsSeen,
        distinctAlbumsSynced: albumSourceIds.length,
        albumsTracksLoaded,
    }
}

export async function upsertTrack(trackSourceId: string, source: "apple_music" | "spotify" | "deezer" | "internal"): Promise<Track | null> {
    const { data: existing, error: existingError } = await supabase
        .schema("public")
        .from("tracks")
        .select("*")
        .eq("source", source)
        .eq("source_id", trackSourceId)
        .maybeSingle()

    if (existingError) return null
    if (existing) return existing

    const result = await fetch(`${MUSIC_BASE_URL}/songs/${trackSourceId}`, {
        headers: { Authorization: `Bearer ${env.apple.musicApiKey}` }
    })

    if (!result.ok) return null

    const res = await result.json()
    const data = res.data?.[0]
    if (!data) return null

    const artistSourceId = data.relationships?.artists?.data?.[0]?.id ?? null
    const albumSourceId = data.relationships?.albums?.data?.[0]?.id ?? null

    let artist: Artist | null = null
    let album: Album | null = null

    if (artistSourceId) artist = await upsertArtist(artistSourceId, "apple_music")
    if (artistSourceId && !artist) return null

    if (albumSourceId) album = await upsertAlbum(albumSourceId, "apple_music")
    if (albumSourceId && !album) return null

    const parsedTrack = trackSchema.parse({
        id: generateRandomId(16),
        source,
        source_id: data.id,
        name: data.attributes?.name ?? null,
        artwork_url: data.attributes?.artwork?.url ?? null,
        artist_id: artist?.id ?? null,
        album_id: album?.id ?? null,
        preview_url: data.attributes?.previews?.[0]?.url ?? null,
        release_date: data.attributes?.releaseDate ?? null,
    })

    const { data: inserted, error } = await supabase
        .schema("public")
        .from("tracks")
        .insert(parsedTrack)
        .select("*")
        .single()

    if (error) return null
    return inserted
}

export async function upsertAlbum(albumSourceId: string, source: "apple_music" | "spotify" | "deezer" | "internal"): Promise<Album | null> {
    const { data: existing, error: existingError } = await supabase
        .schema("public")
        .from("albums")
        .select("*")
        .eq("source", source)
        .eq("source_id", albumSourceId)
        .maybeSingle()

    if (existingError) return null
    if (existing) return existing

    const result = await fetch(`${MUSIC_BASE_URL}/albums/${albumSourceId}`, {
        headers: { Authorization: `Bearer ${env.apple.musicApiKey}` }
    })

    if (!result.ok) return null

    const res = await result.json()
    const data = res.data?.[0]
    if (!data) return null

    const artistSourceId = data.relationships?.artists?.data?.[0]?.id ?? null
    let artist: Artist | null = null

    if (artistSourceId) artist = await upsertArtist(artistSourceId, "apple_music")
    if (artistSourceId && !artist) return null

    const parsedAlbum = albumSchema.parse({
        id: generateRandomId(16),
        source,
        source_id: data.id,
        name: data.attributes?.name ?? null,
        artist_id: artist?.id ?? null,
        artwork_url: data.attributes?.artwork?.url ?? null,
        copyright: data.attributes?.copyright ?? null,
        editorial_note: data.attributes?.editorialNotes?.standard ?? null,
        release_date: data.attributes?.releaseDate ?? null,
        track_count: data.attributes?.trackCount ?? null,
    })

    const { data: inserted, error } = await supabase
        .schema("public")
        .from("albums")
        .insert(parsedAlbum)
        .select("*")
        .single()

    if (error) return null
    return inserted
}

export async function upsertArtist(artistSourceId: string, source: "apple_music" | "spotify" | "deezer" | "internal"): Promise<Artist | null> {
    const { data: existing, error: existingError } = await supabase
        .schema("public")
        .from("artists")
        .select("*")
        .eq("source", source)
        .eq("source_id", artistSourceId)
        .maybeSingle()

    if (existingError) return null
    if (existing) return existing

    const result = await fetch(`${MUSIC_BASE_URL}/artists/${artistSourceId}`, {
        headers: { Authorization: `Bearer ${env.apple.musicApiKey}` }
    })

    if (!result.ok) return null

    const res = await result.json()
    const data = res.data?.[0]
    if (!data) return null

    const parsedArtist = artistSchema.parse({
        id: generateRandomId(16),
        source,
        source_id: data.id,
        name: data.attributes?.name ?? null,
        image_url: data.attributes?.artwork?.url ?? null,
    })

    const { data: inserted, error } = await supabase
        .schema("public")
        .from("artists")
        .insert(parsedArtist)
        .select("*")
        .single()

    if (error) return null
    return inserted
}

export async function getProfileByUsername(username: string) {
    const { data, error } = await supabase.schema("public").from("profiles").select("id, username, is_private").eq("username", username).maybeSingle()
    if (error) throw new Error(error.message)
    return data
}

export async function checkFollowing(followerId: string, followingId: string) {
    const { data, error } = await supabase.schema("public").from("follows").select("follower_id").eq("follower_id", followerId).eq("following_id", followingId).maybeSingle()
    if (error) throw new Error(error.message)
    return !!data
}

export async function getTrackViewerContext(userId: string | undefined, trackId: string) {
    if (!userId) return { isLiked: false, isSaved: false }

    const [{ data: liked }, { data: saved }] = await Promise.all([
        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId).eq("track_id", trackId).maybeSingle(),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId).eq("track_id", trackId).maybeSingle(),
    ])

    return {
        isLiked: !!liked,
        isSaved: !!saved,
    }
}

export async function getAlbumViewerContext(userId: string | undefined, albumId: string) {
    if (!userId) return { isLiked: false, isSaved: false }

    const [{ data: liked }, { data: saved }] = await Promise.all([
        supabase.schema("public").from("album_likes").select("album_id").eq("user_id", userId).eq("album_id", albumId).maybeSingle(),
        supabase.schema("public").from("album_saves").select("album_id").eq("user_id", userId).eq("album_id", albumId).maybeSingle(),
    ])

    return {
        isLiked: !!liked,
        isSaved: !!saved,
    }
}

export async function getArtistViewerContext(userId: string | undefined, artistId: string, ownerId?: string | null) {
    if (!userId) return { isFan: false, isOwner: false }

    const { data } = await supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId).eq("artist_id", artistId).maybeSingle()

    return {
        isFan: !!data,
        isOwner: ownerId === userId,
    }
}

export async function getTrackViewerContextMap(userId: string, trackIds: string[]) {
    if (!trackIds.length) return new Map<string, { isLiked: boolean; isSaved: boolean }>()

    const [{ data: likes }, { data: saves }] = await Promise.all([
        supabase.schema("public").from("track_likes").select("track_id").eq("user_id", userId).in("track_id", trackIds),
        supabase.schema("public").from("track_saves").select("track_id").eq("user_id", userId).in("track_id", trackIds),
    ])

    const likedSet = new Set((likes ?? []).map((row) => row.track_id))
    const savedSet = new Set((saves ?? []).map((row) => row.track_id))

    return new Map(trackIds.map((id) => [id, { isLiked: likedSet.has(id), isSaved: savedSet.has(id) }]))
}

export async function getAlbumViewerContextMap(userId: string, albumIds: string[]) {
    if (!albumIds.length) return new Map<string, { isLiked: boolean; isSaved: boolean }>()

    const [{ data: likes }, { data: saves }] = await Promise.all([
        supabase.schema("public").from("album_likes").select("album_id").eq("user_id", userId).in("album_id", albumIds),
        supabase.schema("public").from("album_saves").select("album_id").eq("user_id", userId).in("album_id", albumIds),
    ])

    const likedSet = new Set((likes ?? []).map((row) => row.album_id))
    const savedSet = new Set((saves ?? []).map((row) => row.album_id))

    return new Map(albumIds.map((id) => [id, { isLiked: likedSet.has(id), isSaved: savedSet.has(id) }]))
}

export async function getArtistViewerContextMap(userId: string, artists: { id: string; owner_id?: string | null }[]) {
    if (!artists.length) return new Map<string, { isFan: boolean; isOwner: boolean }>()

    const { data } = await supabase.schema("public").from("artist_fans").select("artist_id").eq("user_id", userId).in("artist_id", artists.map((artist) => artist.id))
    const fanSet = new Set((data ?? []).map((row) => row.artist_id))

    return new Map(artists.map((artist) => [artist.id, { isFan: fanSet.has(artist.id), isOwner: artist.owner_id === userId }]))
}