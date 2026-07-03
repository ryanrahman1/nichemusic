import { supabase } from "../../config/supabase.js"
import { trackSchema, type Track, albumSchema, type Album, artistSchema, type Artist } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import { normalizePublicAssetUrl } from "../../lib/image.js"
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
export async function syncAppleAlbumTracks(albumCatalogSourceId: string): Promise<boolean> {
    let url: string | null =
        `${MUSIC_BASE_URL}/albums/${encodeURIComponent(albumCatalogSourceId)}/tracks?limit=100`
    const headers = { Authorization: `Bearer ${env.apple.musicApiKey}` }
    while (url) {
        const result = await fetch(url, { headers })
        if (!result.ok) return false
        const res = (await result.json()) as { data?: { id?: string }[]; next?: unknown }
        const songs = res.data ?? []
        for (const song of songs) {
            if (typeof song?.id === "string") await upsertTrack(song.id, "apple_music")
        }
        url = resolveAppleCatalogNext(res.next)
    }
    return true
}

export type SyncAppleArtistDiscographySummary = {
    catalogAlbumsSeen: number
    distinctAlbumsSynced: number
    albumsTracksLoaded: number
    /** All Apple Music catalog requests for this run completed without HTTP failure. */
    syncSucceeded: boolean
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
    let artistCatalogSyncOk = true
    while (url) {
        const result = await fetch(url, { headers })
        if (!result.ok) {
            artistCatalogSyncOk = false
            break
        }
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
    let albumTracksSyncOk = true
    for (const sid of albumSourceIds) {
        const tracksOk = await syncAppleAlbumTracks(sid)
        if (!tracksOk) albumTracksSyncOk = false
        albumsTracksLoaded++
    }
    const syncSucceeded = artistCatalogSyncOk && albumTracksSyncOk
    return {
        catalogAlbumsSeen,
        distinctAlbumsSynced: albumSourceIds.length,
        albumsTracksLoaded,
        syncSucceeded,
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

export async function getNicheTrackViewerContext(userId: string | undefined, trackId: string) {
    if (!userId) return { isLiked: false, isSaved: false }

    const [{ data: liked }, { data: saved }] = await Promise.all([
        supabase.schema("public").from("niche_track_likes").select("track_id").eq("liker_id", userId).eq("track_id", trackId).maybeSingle(),
        supabase.schema("public").from("niche_track_saves").select("track_id").eq("saver_id", userId).eq("track_id", trackId).maybeSingle(),
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

export async function attachArtistNamesToTracks<
    T extends { artist_id?: string | null }
>(tracks: T[]): Promise<(T & { artist_name: string | null })[]> {
    const artistIds = [
        ...new Set(
            tracks
                .map((track) => track.artist_id)
                .filter((id): id is string => typeof id === "string" && id.length > 0)
        ),
    ]

    if (!artistIds.length) {
        return tracks.map((track) => ({ ...track, artist_name: null }))
    }

    const { data, error } = await supabase
        .schema("public")
        .from("artists")
        .select("id, name")
        .in("id", artistIds)

    if (error) throw new Error(error.message)

    const nameById = new Map((data ?? []).map((row) => [row.id, row.name as string | null]))

    return tracks.map((track) => ({
        ...track,
        artist_name: track.artist_id ? nameById.get(track.artist_id) ?? null : null,
    }))
}

function firstJoinedRow<T>(value: T | T[] | null | undefined): T | null {
    if (!value) return null
    return Array.isArray(value) ? (value[0] ?? null) : value
}

function coalesceAssetUrl(...values: Array<string | null | undefined>): string {
    for (const value of values) {
        const normalized = normalizePublicAssetUrl(value) ?? (typeof value === "string" ? value.trim() : "")
        if (normalized) return normalized
    }
    return ""
}

export function normalizeNicheTrackUrls<T extends Record<string, unknown>>(
    track: T,
    releaseArtworkUrl?: string | null
): T & { artwork_url: string; music_url: string } {
    return {
        ...track,
        artwork_url: coalesceAssetUrl(
            typeof track.artwork_url === "string" ? track.artwork_url : null,
            releaseArtworkUrl
        ),
        music_url: coalesceAssetUrl(typeof track.music_url === "string" ? track.music_url : null),
    }
}

function releaseArtworkFromTrackJoins(
    releaseTracks: unknown
): string {
    if (!Array.isArray(releaseTracks)) return ""

    for (const row of releaseTracks) {
        if (!row || typeof row !== "object") continue
        const release = firstJoinedRow(
            (row as { release?: { artwork_url?: string | null } | Array<{ artwork_url?: string | null }> }).release
        )
        const artwork = coalesceAssetUrl(release?.artwork_url ?? null)
        if (artwork) return artwork
    }

    return ""
}

export async function fetchNicheTrackDetail(trackId: string, viewerUserId?: string) {
    const { data, error } = await supabase.schema("public").from("niche_tracks").select(`
        *,
        owner:profiles!niche_tracks_owner_id_fkey(*),
        metadata:niche_track_metadata(
            mood,
            energy,
            danceability,
            valence,
            intensity,
            topics,
            language,
            explicit_score,
            metadata
        ),
        credits:niche_track_artists!niche_track_artists_track_id_fkey(
            track_id,
            artist_id,
            is_primary,
            artist:profiles!niche_track_artists_artist_id_fkey(
                id,
                username,
                display_name,
                avatar_url,
                is_verified
            )
        ),
        release_tracks:niche_release_tracks(
            release:niche_releases(artwork_url)
        )
    `).eq("id", trackId).maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) return null

    if (data.visibility === "private" && data.owner_id !== viewerUserId) {
        return null
    }

    const releaseArtworkUrl = releaseArtworkFromTrackJoins(data.release_tracks)
    const { release_tracks: _releaseTracks, ...trackRow } = data
    const track = normalizeNicheTrackUrls(trackRow, releaseArtworkUrl)
    const viewer = viewerUserId
        ? await getNicheTrackViewerContext(viewerUserId, trackId)
        : { isLiked: false, isSaved: false }

    return { track, viewer }
}

export async function getNicheTrackViewerContextMap(userId: string, trackIds: string[]) {
    if (!trackIds.length) return new Map<string, { isLiked: boolean; isSaved: boolean }>()

    const [{ data: likes }, { data: saves }] = await Promise.all([
        supabase.schema("public").from("niche_track_likes").select("track_id").eq("liker_id", userId).in("track_id", trackIds),
        supabase.schema("public").from("niche_track_saves").select("track_id").eq("saver_id", userId).in("track_id", trackIds),
    ])

    const likedSet = new Set((likes ?? []).map((row) => row.track_id))
    const savedSet = new Set((saves ?? []).map((row) => row.track_id))

    return new Map(trackIds.map((id) => [id, { isLiked: likedSet.has(id), isSaved: savedSet.has(id) }]))
}

export async function fetchNicheReleaseDetail(releaseId: string, viewerUserId?: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("niche_releases")
        .select(`
            *,
            owner:profiles!niche_releases_owner_id_fkey(*),
            release_tracks:niche_release_tracks(
                track_number,
                track:niche_tracks!niche_release_tracks_track_id_fkey(
                    *,
                    credits:niche_track_artists!niche_track_artists_track_id_fkey(
                        track_id,
                        artist_id,
                        is_primary,
                        artist:profiles!niche_track_artists_artist_id_fkey(
                            id,
                            username,
                            display_name,
                            avatar_url,
                            is_verified
                        )
                    )
                )
            )
        `)
        .eq("id", releaseId)
        .is("deleted_at", null)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) return null

    if (data.visibility === "private" && data.owner_id !== viewerUserId) {
        return null
    }

    type ReleaseTrackJoin = {
        track_number: number | null
        track: Record<string, unknown> | Record<string, unknown>[] | null
    }

    const releaseTracks = ((data.release_tracks ?? []) as ReleaseTrackJoin[])
        .map((row) => ({
            track_number: row.track_number,
            track: firstJoinedRow(row.track),
        }))
        .filter((row): row is { track_number: number | null; track: Record<string, unknown> } => {
            if (!row.track) return false
            return !row.track.deleted_at
        })
        .sort((a, b) => (a.track_number ?? 0) - (b.track_number ?? 0))

    const trackIds = releaseTracks.map((row) => String(row.track.id))
    const trackViewerMap = viewerUserId
        ? await getNicheTrackViewerContextMap(viewerUserId, trackIds)
        : new Map<string, { isLiked: boolean; isSaved: boolean }>()

    const releaseArtworkUrl = coalesceAssetUrl(
        typeof data.artwork_url === "string" ? data.artwork_url : null
    )

    const tracks = releaseTracks.map((row) => {
        const track = row.track
        return normalizeNicheTrackUrls(
            {
                ...track,
                name: track.name ?? "Untitled",
                track_number: row.track_number,
                credits: track.credits ?? [],
                viewer: trackViewerMap.get(String(track.id)) ?? { isLiked: false, isSaved: false },
            },
            releaseArtworkUrl
        )
    })

    const { release_tracks: _releaseTracks, owner, ...release } = data

    return {
        release,
        owner,
        tracks,
        track_count: tracks.length,
        viewer: { isLiked: false, isSaved: false },
    }
}