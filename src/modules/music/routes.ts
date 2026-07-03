import { FastifyPluginAsync } from "fastify"
import env from "../../config/env.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { supabase } from "../../config/supabase.js"
import { getProfileByUsername, checkFollowing, upsertAlbum, upsertArtist, upsertTrack, syncAppleAlbumTracks, syncAppleArtistDiscography, getTrackViewerContext, getAlbumViewerContext, getArtistViewerContext, getTrackViewerContextMap, getAlbumViewerContextMap, getArtistViewerContextMap, getNicheTrackViewerContext, attachArtistNamesToTracks, fetchNicheReleaseDetail, fetchNicheTrackDetail } from "./helpers.js"
import { musicLibraryQuerySchema, musicMeQuerySchema, musicFollowingQuerySchema, type Track, listCommentsQuerySchema, updateNicheTrackDraftSchema, updateReleaseDraftSchema, updateNicheTrackOnReleaseDraftSchema, updateNicheTrackSchema, updateReleaseSchema, draftMusicUploadSchema, listDraftsQuerySchema, recordNicheTrackPlaySchema } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import { addViewerToComments, buildCommentContent, decodeCommentCursor, encodeCommentCursor, getPostViewerContextMap, POST_LIST_SELECT } from "../posts/helpers.js"
import { createCommentSchema, postListQuerySchema } from "../posts/schemas.js"
import { normalizeQueryDateTime, toUtcZulu } from "../../lib/datetime.js"
import {
    sendNicheTrackCommentLikeNotification,
    sendNicheTrackCommentNotification,
    sendNicheTrackCommentReplyNotification,
} from "../../lib/notifications.js"
import { fetchAssetHead, getNicheTrackImagePresignedUrl, getNicheTrackMomentPresignedUrl, getNicheTrackMusicPresignedUrl, normalizePublicAssetUrl, PresignedUploadResult } from "../../lib/image.js"

type UploadFormat = "jpeg" | "webp" | "png" | "avif"
type VideoFormat = "mp4" | "webm" | "mov" | "mkv"
type MusicFormat = "mp3" | "m4a" | "wav" | "flac" | "aac"

const MUSIC_BASE_URL = "https://api.music.apple.com/v1/catalog/us"


function firstRow<T>(value: T | T[] | null | undefined): T | null {
    if (!value) return null
    return Array.isArray(value) ? (value[0] ?? null) : value
}

type MusicInteractionQuery = {
    cursorCreatedAt?: string
    cursorUserId?: string
    limit: number
}

function parseInteractionQuery(raw: unknown): MusicInteractionQuery {
    const q = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>
    const cursorCreatedAt =
        typeof q.cursorCreatedAt === "string" ? normalizeQueryDateTime(q.cursorCreatedAt) : undefined
    const cursorUserId =
        typeof q.cursorUserId === "string" ? q.cursorUserId : undefined
    const parsedLimit =
        typeof q.limit === "string" ? Number(q.limit) : typeof q.limit === "number" ? q.limit : 20
    const limit = Number.isFinite(parsedLimit)
        ? Math.min(50, Math.max(1, Math.floor(parsedLimit)))
        : 20
    const out: MusicInteractionQuery = { limit }
    if (cursorCreatedAt !== undefined) out.cursorCreatedAt = cursorCreatedAt
    if (cursorUserId !== undefined) out.cursorUserId = cursorUserId
    return out
}

const TRACK_DRAFT_LIST_COLUMNS =
    "id, name, artwork_url, release_date, duration_ms, explicit, visibility, track_number, release_draft_id, created_at, updated_at"

const TRACK_DRAFT_DETAIL_COLUMNS =
    "id, owner_id, name, artwork_url, music_url, moment_url, release_date, explicit, duration_ms, bpm, visibility, track_number, release_draft_id, draft_status, created_at, updated_at"

const RELEASE_DRAFT_LIST_COLUMNS =
    "id, name, artwork_url, release_type, release_date, visibility, created_at, updated_at"

const RELEASE_DRAFT_DETAIL_COLUMNS =
    "id, owner_id, name, artwork_url, release_type, release_date, visibility, draft_status, created_at, updated_at"

const TRACK_DRAFT_CREDITS_SELECT =
    "artist_id, is_primary, artist:profiles!niche_track_artist_drafts_artist_id_fkey(id, username, display_name, avatar_url)"

async function draftAssetUploadStatus(draft: {
    music_url?: string | null
    artwork_url?: string | null
    moment_url?: string | null
}) {
    const status = {
        music: false,
        artwork: false,
        moment: false,
    }

    const checks: Promise<void>[] = []

    if (draft.music_url) {
        checks.push(
            fetchAssetHead(draft.music_url).then((response) => {
                status.music = response.ok
            })
        )
    }

    if (draft.artwork_url) {
        checks.push(
            fetchAssetHead(draft.artwork_url).then((response) => {
                status.artwork = response.ok
            })
        )
    }

    if (draft.moment_url) {
        checks.push(
            fetchAssetHead(draft.moment_url).then((response) => {
                status.moment = response.ok
            })
        )
    }

    await Promise.all(checks)
    return status
}

const musicRoutes: FastifyPluginAsync = async (app) => {

    app.get("/music/apple/search", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { q, types } = req.query as { q: string; types?: string }
        if (!q || typeof q !== "string" || !q.trim()) {
            return sendError(res, "MUSIC_SEARCH_QUERY_REQUIRED", "Query `q` is required", 400)
        }
        const typesParam =
            typeof types === "string" && types.trim().length > 0
                ? types.trim()
                : "songs,albums,artists"
        const url = `${MUSIC_BASE_URL}/search?term=${encodeURIComponent(q.trim())}&types=${encodeURIComponent(typesParam)}`
        const result = await fetch(url, {
            headers: {
                Authorization: `Bearer ${env.apple.musicApiKey}`,
            },
        })

        if (!result.ok)
            return sendError(res, "MUSIC_SEARCH_FAILED", result.statusText, result.status)

        const data = await result.json()
        return sendSuccess(res, { data })
    })


    app.get('/music/apple/songs/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        let track = await supabase.schema("public").from("tracks").select("*").eq("source", "apple_music").eq("source_id", id).maybeSingle()
        if (track.error) return sendError(res, "MUSIC_SONG_FETCH_FAILED", track.error.message, 500)

        let trackRow = track.data
        if (!trackRow) {
            trackRow = await upsertTrack(id, "apple_music")
            if (!trackRow) return sendError(res, "MUSIC_SONG_UPSERT_FAILED", "Failed to upsert track", 500)
        }

        const [{ data: artist }, { data: album }, viewer] = await Promise.all([
            trackRow.artist_id ? supabase.schema("public").from("artists").select("*").eq("id", trackRow.artist_id).maybeSingle() : Promise.resolve({ data: null }),
            trackRow.album_id ? supabase.schema("public").from("albums").select("*").eq("id", trackRow.album_id).maybeSingle() : Promise.resolve({ data: null }),
            getTrackViewerContext(req.userId, trackRow.id),
        ])

        return sendSuccess(res, {
            track: trackRow,
            artist: artist ?? null,
            album: album ?? null,
            viewer,
        })
    })

    app.get('/music/apple/albums/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        let album = await supabase.schema("public").from("albums").select("*").eq("source", "apple_music").eq("source_id", id).maybeSingle()
        if (album.error) return sendError(res, "MUSIC_ALBUM_FETCH_FAILED", album.error.message, 500)

        let albumRow = album.data
        if (!albumRow) {
            albumRow = await upsertAlbum(id, "apple_music")
            if (!albumRow) return sendError(res, "MUSIC_ALBUM_UPSERT_FAILED", "Failed to upsert album", 500)
        }

        const [{ data: artist }, { data: trackRows }, viewer] = await Promise.all([
            albumRow.artist_id ? supabase.schema("public").from("artists").select("*").eq("id", albumRow.artist_id).maybeSingle() : Promise.resolve({ data: null }),
            supabase.schema("public").from("tracks").select("*").eq("album_id", albumRow.id).order("name", { ascending: true }),
            getAlbumViewerContext(req.userId, albumRow.id),
        ])

        const tracks = trackRows ?? []
        const trackViewerMap = await getTrackViewerContextMap(req.userId, tracks.map((t) => t.id))
        const artistName = artist?.name ?? null

        return sendSuccess(res, {
            album: albumRow,
            artist: artist ?? null,
            viewer,
            songs: tracks.map((t) => ({
                ...t,
                viewer: trackViewerMap.get(t.id) ?? { isLiked: false, isSaved: false },
                artist_name: artistName,
            })),
        })
    })

    app.post(
        "/music/apple/albums/:id/sync-tracks",
        { preHandler: app.optionalAuthenticate },
        async (req, res) => {
            const { id } = req.params as { id: string }

            let album = await supabase
                .schema("public")
                .from("albums")
                .select("*")
                .eq("source", "apple_music")
                .eq("source_id", id)
                .maybeSingle()
            if (album.error)
                return sendError(res, "MUSIC_ALBUM_FETCH_FAILED", album.error.message, 500)

            if (!album.data) {
                const inserted = await upsertAlbum(id, "apple_music")
                if (!inserted)
                    return sendError(res, "MUSIC_ALBUM_UPSERT_FAILED", "Failed to upsert album", 500)
            }

            const syncSucceeded = await syncAppleAlbumTracks(id)
            return sendSuccess(res, { syncSucceeded })
        }
    )

    app.get('/music/apple/artists/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        let artist = await supabase.schema("public").from("artists").select("*").eq("source", "apple_music").eq("source_id", id).maybeSingle()
        if (artist.error) return sendError(res, "MUSIC_ARTIST_FETCH_FAILED", artist.error.message, 500)

        let artistRow = artist.data
        if (!artistRow) {
            artistRow = await upsertArtist(id, "apple_music")
            if (!artistRow) return sendError(res, "MUSIC_ARTIST_UPSERT_FAILED", "Failed to upsert artist", 500)
        }

        const [{ data: albumRows }, { data: trackRows }, viewer] = await Promise.all([
            supabase.schema("public").from("albums").select("*").eq("artist_id", artistRow.id).order("release_date", { ascending: false }),
            supabase.schema("public").from("tracks").select("*").eq("artist_id", artistRow.id).order("name", { ascending: true }),
            getArtistViewerContext(req.userId, artistRow.id, artistRow.owner_id),
        ])

        const albums = albumRows ?? []
        const tracks = trackRows ?? []
        const [albumViewerMap, trackViewerMap] = await Promise.all([
            getAlbumViewerContextMap(req.userId, albums.map((a) => a.id)),
            getTrackViewerContextMap(req.userId, tracks.map((t) => t.id)),
        ])

        return sendSuccess(res, {
            artist: artistRow,
            viewer,
            albums: albums.map((a) => ({
                ...a,
                viewer: albumViewerMap.get(a.id) ?? { isLiked: false, isSaved: false },
            })),
            songs: tracks.map((t) => ({
                ...t,
                viewer: trackViewerMap.get(t.id) ?? { isLiked: false, isSaved: false },
                artist_name: artistRow.name,
            })),
        })
    })

    app.post(
        "/music/apple/artists/:id/load-discography",
        { preHandler: app.optionalAuthenticate },
        async (req, res) => {
            const { id } = req.params as { id: string }

            let artist = await supabase
                .schema("public")
                .from("artists")
                .select("*")
                .eq("source", "apple_music")
                .eq("source_id", id)
                .maybeSingle()
            if (artist.error)
                return sendError(res, "MUSIC_ARTIST_FETCH_FAILED", artist.error.message, 500)

            let artistRow = artist.data
            if (!artistRow) {
                artistRow = await upsertArtist(id, "apple_music")
                if (!artistRow)
                    return sendError(res, "MUSIC_ARTIST_UPSERT_FAILED", "Failed to upsert artist", 500)
            }

            const summary = await syncAppleArtistDiscography(id)
            if (summary.syncSucceeded) {
                const { error: updateError } = await supabase
                    .schema("public")
                    .from("artists")
                    .update({ has_full_discography: true })
                    .eq("id", artistRow.id)
                if (updateError)
                    return sendError(
                        res,
                        "MUSIC_ARTIST_DISCOGRAPHY_FLAG_FAILED",
                        updateError.message,
                        500
                    )
            }
            return sendSuccess(res, summary)
        }
    )

    // social
    app.post('/music/songs/:id/like', { preHandler: app.authenticate }, async (req, res) => { // ACTUAL id, not source_id
        const { id } = req.params as { id: string }

        const { data: like_data, error: like_error } = await supabase.schema("public").rpc("like_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (like_error) return sendError(res, "MUSIC_SONG_LIKE_FAILED", like_error.message, 500)
        return sendSuccess(res, { message: "Song liked successfully", like_data: like_data })
    })

    app.post('/music/songs/:id/unlike', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unlike_data, error: unlike_error } = await supabase.schema("public").rpc("unlike_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (unlike_error) return sendError(res, "MUSIC_SONG_UNLIKE_FAILED", unlike_error.message, 500)
        return sendSuccess(res, { message: "Song unliked successfully", unlike_data: unlike_data })
    })

    app.post('/music/songs/:id/save', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: save_data, error: save_error } = await supabase.schema("public").rpc("save_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (save_error) return sendError(res, "MUSIC_SONG_SAVE_FAILED", save_error.message, 500)
        return sendSuccess(res, { message: "Song saved successfully", save_data: save_data })
    })

    app.post('/music/songs/:id/unsave', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unsave_data, error: unsave_error } = await supabase.schema("public").rpc("unsave_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (unsave_error) return sendError(res, "MUSIC_SONG_UNSAVE_FAILED", unsave_error.message, 500)
        return sendSuccess(res, { message: "Song unsaved successfully", unsave_data: unsave_data })
    })

    app.post('/music/songs/:id/share', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const shareId = generateRandomId(16)

        const { data: share_data, error: share_error } = await supabase.schema("public").rpc("share_track", {
            actor_id: req.userId,
            target_track_id: id,
            share_id: shareId,
        })

        if (share_error) return sendError(res, "MUSIC_SONG_SHARE_FAILED", share_error.message, 500)
        return sendSuccess(res, { message: "Song shared successfully", share_data: share_data })
    })

    app.post('/music/albums/:id/like', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: like_data, error: like_error } = await supabase.schema("public").rpc("like_album", {
            actor_id: req.userId,
            target_album_id: id,
        })
        if (like_error) return sendError(res, "MUSIC_ALBUM_LIKE_FAILED", like_error.message, 500)
        return sendSuccess(res, { message: "Album liked successfully", like_data: like_data })
    })

    app.post('/music/albums/:id/unlike', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unlike_data, error: unlike_error } = await supabase.schema("public").rpc("unlike_album", {
            actor_id: req.userId,
            target_album_id: id,
        })
        if (unlike_error) return sendError(res, "MUSIC_ALBUM_UNLIKE_FAILED", unlike_error.message, 500)
        return sendSuccess(res, { message: "Album unliked successfully", unlike_data: unlike_data })
    })

    app.post('/music/albums/:id/save', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: save_data, error: save_error } = await supabase.schema("public").rpc("save_album", {
            actor_id: req.userId,
            target_album_id: id,
        })
        if (save_error) return sendError(res, "MUSIC_ALBUM_SAVE_FAILED", save_error.message, 500)
        return sendSuccess(res, { message: "Album saved successfully", save_data: save_data })
    })

    app.post('/music/albums/:id/unsave', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unsave_data, error: unsave_error } = await supabase.schema("public").rpc("unsave_album", {
            actor_id: req.userId,
            target_album_id: id,
        })
        if (unsave_error) return sendError(res, "MUSIC_ALBUM_UNSAVE_FAILED", unsave_error.message, 500)
        return sendSuccess(res, { message: "Album unsaved successfully", unsave_data: unsave_data })
    })

    app.post('/music/albums/:id/share', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const shareId = generateRandomId(16)

        const { data: share_data, error: share_error } = await supabase.schema("public").rpc("share_album", {
            actor_id: req.userId,
            target_album_id: id,
            share_id: shareId,
        })
        if (share_error) return sendError(res, "MUSIC_ALBUM_SHARE_FAILED", share_error.message, 500)
        return sendSuccess(res, { message: "Album shared successfully", share_data: share_data })
    })

    app.post('/music/artists/:id/follow', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: fans_data, error: fans_error } = await supabase.schema("public").rpc("fan_artist", {
            actor_id: req.userId,
            target_artist_id: id,
        })
        if (fans_error) return sendError(res, "MUSIC_ARTIST_FANS_FAILED", fans_error.message, 500)
        return sendSuccess(res, { message: "Artist followed successfully", fans_data: fans_data })
    })

    app.post('/music/artists/:id/unfollow', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unfollow_data, error: unfollow_error } = await supabase.schema("public").rpc("unfan_artist", {
            actor_id: req.userId,
            target_artist_id: id,
        })
        if (unfollow_error) return sendError(res, "MUSIC_ARTIST_UNFOLLOW_FAILED", unfollow_error.message, 500)
        return sendSuccess(res, { message: "Artist unfollowed successfully", unfollow_data: unfollow_data })
    })

    app.post('/music/artists/:id/share', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const shareId = generateRandomId(16)

        const { data: share_data, error: share_error } = await supabase.schema("public").rpc("share_artist", {
            actor_id: req.userId,
            target_artist_id: id,
            share_id: shareId,
        })
        if (share_error) return sendError(res, "MUSIC_ARTIST_SHARE_FAILED", share_error.message, 500)
        return sendSuccess(res, { message: "Artist shared successfully", share_data: share_data })
    })

    app.get("/music/library/songs", { preHandler: [app.optionalAuthenticate] }, async (req, res) => {
        const { cursorScore, cursorCreatedAt, cursorId, limit, windowDays } =
            musicLibraryQuerySchema.parse(req.query)

        const { data, error } = await supabase.rpc("get_trending_tracks", {
            window_days: windowDays,
            page_limit: limit,
            cursor_score: cursorScore ?? null,
            cursor_created_at: cursorCreatedAt ?? null,
            cursor_id: cursorId ?? null,
        })

        if (error) return sendError(res, "MUSIC_LIBRARY_SONGS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)

        return sendSuccess(res, { songs: items }, {
            pagination: {
                nextCursor:
                    hasMore && last
                        ? JSON.stringify({
                            cursorScore: last.score,
                            cursorCreatedAt: last.created_at,
                            cursorId: last.id,
                        })
                        : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/library/albums", { preHandler: [app.optionalAuthenticate] }, async (req, res) => {
        const { cursorScore, cursorCreatedAt, cursorId, limit, windowDays } =
            musicLibraryQuerySchema.parse(req.query)

        const { data, error } = await supabase.rpc("get_trending_albums", {
            window_days: windowDays,
            page_limit: limit,
            cursor_score: cursorScore ?? null,
            cursor_created_at: cursorCreatedAt ?? null,
            cursor_id: cursorId ?? null,
        })

        if (error) return sendError(res, "MUSIC_LIBRARY_ALBUMS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)

        return sendSuccess(res, { albums: items }, {
            pagination: {
                nextCursor:
                    hasMore && last
                        ? JSON.stringify({
                            cursorScore: last.score,
                            cursorCreatedAt: last.created_at,
                            cursorId: last.id,
                        })
                        : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/library/artists", { preHandler: [app.optionalAuthenticate] }, async (req, res) => {
        const { cursorScore, cursorCreatedAt, cursorId, limit, windowDays } =
            musicLibraryQuerySchema.parse(req.query)

        const { data, error } = await supabase.rpc("get_trending_artists", {
            window_days: windowDays,
            page_limit: limit,
            cursor_score: cursorScore ?? null,
            cursor_created_at: cursorCreatedAt ?? null,
            cursor_id: cursorId ?? null,
        })

        if (error) return sendError(res, "MUSIC_LIBRARY_ARTISTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)

        return sendSuccess(res, { artists: items }, {
            pagination: {
                nextCursor:
                    hasMore && last
                        ? JSON.stringify({
                            cursorScore: last.score,
                            cursorCreatedAt: last.created_at,
                            cursorId: last.id,
                        })
                        : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/me/liked", { preHandler: [app.authenticate] }, async (req, res) => {
        const { type = "songs", cursorCreatedAt, limit } = musicMeQuerySchema.parse(req.query)

        if (type === "songs") {
            let query = supabase.schema("public").from("track_likes").select("created_at, track:tracks(*)").eq("user_id", req.userId).order("created_at", { ascending: false }).limit(limit + 1)
            if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

            const { data, error } = await query
            if (error) return sendError(res, "MUSIC_ME_LIKED_SONGS_FETCH_FAILED", error.message, 500)

            const rows = data ?? []
            const hasMore = rows.length > limit
            const items = hasMore ? rows.slice(0, limit) : rows
            const last = items.at(-1)
            const tracks = items.map((row) => firstRow(row.track)).filter((track): track is NonNullable<typeof track> => !!track)
            const viewerMap = await getTrackViewerContextMap(req.userId, tracks.map((track) => track.id))
            const enrichedTracks = await attachArtistNamesToTracks(tracks)

            return sendSuccess(res, {
                songs: enrichedTracks.map((track) => ({
                    ...track,
                    viewer: viewerMap.get(track.id) ?? { isLiked: false, isSaved: false },
                })),
            }, {
                pagination: {
                    nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                    limit,
                    hasMore,
                },
            })
        }

        let query = supabase.schema("public").from("album_likes").select("created_at, album:albums(*)").eq("user_id", req.userId).order("created_at", { ascending: false }).limit(limit + 1)
        if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

        const { data, error } = await query
        if (error) return sendError(res, "MUSIC_ME_LIKED_ALBUMS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)
        const albums = items.map((row) => firstRow(row.album)).filter((album): album is NonNullable<typeof album> => !!album)
        const viewerMap = await getAlbumViewerContextMap(req.userId, albums.map((album) => album.id))

        return sendSuccess(res, {
            albums: albums.map((album) => ({
                ...album,
                viewer: viewerMap.get(album.id) ?? { isLiked: false, isSaved: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/me/saved", { preHandler: [app.authenticate] }, async (req, res) => {
        const { type = "songs", cursorCreatedAt, limit } = musicMeQuerySchema.parse(req.query)

        if (type === "songs") {
            let query = supabase.schema("public").from("track_saves").select("created_at, track:tracks(*)").eq("user_id", req.userId).order("created_at", { ascending: false }).limit(limit + 1)
            if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

            const { data, error } = await query
            if (error) return sendError(res, "MUSIC_ME_SAVED_SONGS_FETCH_FAILED", error.message, 500)

            const rows = data ?? []
            const hasMore = rows.length > limit
            const items = hasMore ? rows.slice(0, limit) : rows
            const last = items.at(-1)
            const tracks = items.map((row) => firstRow(row.track)).filter((track): track is NonNullable<typeof track> => !!track)
            const viewerMap = await getTrackViewerContextMap(req.userId, tracks.map((track) => track.id))
            const enrichedTracks = await attachArtistNamesToTracks(tracks)

            return sendSuccess(res, {
                songs: enrichedTracks.map((track) => ({
                    ...track,
                    viewer: viewerMap.get(track.id) ?? { isLiked: false, isSaved: false },
                })),
            }, {
                pagination: {
                    nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                    limit,
                    hasMore,
                },
            })
        }

        let query = supabase.schema("public").from("album_saves").select("created_at, album:albums(*)").eq("user_id", req.userId).order("created_at", { ascending: false }).limit(limit + 1)
        if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

        const { data, error } = await query
        if (error) return sendError(res, "MUSIC_ME_SAVED_ALBUMS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)
        const albums = items.map((row) => firstRow(row.album)).filter((album): album is NonNullable<typeof album> => !!album)
        const viewerMap = await getAlbumViewerContextMap(req.userId, albums.map((album) => album.id))

        return sendSuccess(res, {
            albums: albums.map((album) => ({
                ...album,
                viewer: viewerMap.get(album.id) ?? { isLiked: false, isSaved: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/me/following", { preHandler: [app.authenticate] }, async (req, res) => {
        const { cursorCreatedAt, limit } = musicFollowingQuerySchema.parse(req.query)

        let query = supabase.schema("public").from("artist_fans").select("created_at, artist:artists(*)").eq("user_id", req.userId).order("created_at", { ascending: false }).limit(limit + 1)
        if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

        const { data, error } = await query
        if (error) return sendError(res, "MUSIC_ME_FOLLOWING_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)
        const artists = items.map((row) => firstRow(row.artist)).filter((artist): artist is NonNullable<typeof artist> => !!artist)
        const viewerMap = await getArtistViewerContextMap(req.userId, artists.map((artist) => ({ id: artist.id, owner_id: artist.owner_id })))

        return sendSuccess(res, {
            artists: artists.map((artist) => ({
                ...artist,
                viewer: viewerMap.get(artist.id) ?? { isFan: false, isOwner: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/users/:username/liked", { preHandler: [app.authenticate] }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { type = "songs", cursorCreatedAt, limit } = musicMeQuerySchema.parse(req.query)

        const profile = await getProfileByUsername(username)
        if (!profile) return sendError(res, "USER_NOT_FOUND", "User not found", 404)

        if (profile.is_private && profile.id !== req.userId) {
            const isFollowing = await checkFollowing(req.userId, profile.id)
            if (!isFollowing) return sendError(res, "FORBIDDEN", "User is private", 403)
        }

        if (type === "songs") {
            let query = supabase.schema("public").from("track_likes").select("created_at, track:tracks(*)").eq("user_id", profile.id).order("created_at", { ascending: false }).limit(limit + 1)
            if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

            const { data, error } = await query
            if (error) return sendError(res, "MUSIC_USER_LIKED_SONGS_FETCH_FAILED", error.message, 500)

            const rows = data ?? []
            const hasMore = rows.length > limit
            const items = hasMore ? rows.slice(0, limit) : rows
            const last = items.at(-1)
            const tracks = items.map((row) => firstRow(row.track)).filter((track): track is NonNullable<typeof track> => !!track)
            const viewerMap = await getTrackViewerContextMap(req.userId, tracks.map((track) => track.id))
            const enrichedTracks = await attachArtistNamesToTracks(tracks)

            return sendSuccess(res, {
                songs: enrichedTracks.map((track) => ({
                    ...track,
                    viewer: viewerMap.get(track.id) ?? { isLiked: false, isSaved: false },
                })),
            }, {
                pagination: {
                    nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                    limit,
                    hasMore,
                },
            })
        }

        let query = supabase.schema("public").from("album_likes").select("created_at, album:albums(*)").eq("user_id", profile.id).order("created_at", { ascending: false }).limit(limit + 1)
        if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

        const { data, error } = await query
        if (error) return sendError(res, "MUSIC_USER_LIKED_ALBUMS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)
        const albums = items.map((row) => firstRow(row.album)).filter((album): album is NonNullable<typeof album> => !!album)
        const viewerMap = await getAlbumViewerContextMap(req.userId, albums.map((album) => album.id))

        return sendSuccess(res, {
            albums: albums.map((album) => ({
                ...album,
                viewer: viewerMap.get(album.id) ?? { isLiked: false, isSaved: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/users/:username/following", { preHandler: [app.authenticate] }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { cursorCreatedAt, limit } = musicFollowingQuerySchema.parse(req.query)

        const profile = await getProfileByUsername(username)
        if (!profile) return sendError(res, "USER_NOT_FOUND", "User not found", 404)

        if (profile.is_private && profile.id !== req.userId) {
            const isFollowing = await checkFollowing(req.userId, profile.id)
            if (!isFollowing) return sendError(res, "FORBIDDEN", "User is private", 403)
        }

        let query = supabase.schema("public").from("artist_fans").select("created_at, artist:artists(*)").eq("user_id", profile.id).order("created_at", { ascending: false }).limit(limit + 1)
        if (cursorCreatedAt) query = query.lt("created_at", cursorCreatedAt)

        const { data, error } = await query
        if (error) return sendError(res, "MUSIC_USER_FOLLOWING_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const last = items.at(-1)
        const artists = items.map((row) => firstRow(row.artist)).filter((artist): artist is NonNullable<typeof artist> => !!artist)
        const viewerMap = await getArtistViewerContextMap(req.userId, artists.map((artist) => ({ id: artist.id, owner_id: artist.owner_id })))

        return sendSuccess(res, {
            artists: artists.map((artist) => ({
                ...artist,
                viewer: viewerMap.get(artist.id) ?? { isFan: false, isOwner: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at }) : null,
                limit,
                hasMore,
            },
        })
    })
}

const nicheMusicRoutes: FastifyPluginAsync = async (app) => {
    // routes for niche music creator uploaded music

    app.get("/music/niche/search", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { q, limit } = req.query as { q?: string; limit?: string }
        const search = typeof q === "string" ? q.trim() : ""

        if (!search) {
            return sendError(res, "MUSIC_SEARCH_QUERY_REQUIRED", "Query `q` is required", 400)
        }

        const limitCount = Math.min(Math.max(Number(limit) || 20, 1), 50)

        const { data, error } = await supabase.schema("public").rpc("search_niche_tracks", {
            query_text: search,
            limit_count: limitCount,
        })

        if (error) {
            return sendError(res, "MUSIC_NICHE_SEARCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, {
            tracks: data ?? [],
        })
    })

    app.get("/niche-tracks/:id/posts", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursorCreatedAt, cursorId, limit } = postListQuerySchema.parse(req.query)

        const { data: nicheTrack, error: nicheTrackError } = await supabase
            .schema("public")
            .from("niche_tracks")
            .select("id")
            .eq("id", id)
            .is("deleted_at", null)
            .maybeSingle()

        if (nicheTrackError) return sendError(res, "MUSIC_NICHE_SONG_FETCH_FAILED", nicheTrackError.message, 500)
        if (!nicheTrack) return sendError(res, "MUSIC_NICHE_SONG_NOT_FOUND", "Song not found", 404)

        let query = supabase
            .schema("public")
            .from("posts")
            .select(POST_LIST_SELECT)
            .eq("niche_track_id", id)
            .eq("visibility", "public")
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorId) {
            query = query.or(`created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},id.lt.${cursorId})`)
        }

        const { data, error } = await query
        if (error) return sendError(res, "POSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const posts = hasMore ? rows.slice(0, limit) : rows
        const last = posts.at(-1)
        const viewerMap = await getPostViewerContextMap(req.userId, posts.map((post) => post.id))

        return sendSuccess(res, {
            posts: posts.map((post) => ({
                ...post,
                viewer: viewerMap.get(post.id) ?? { isLiked: false, isReposted: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at, cursorId: last.id }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get('/music/niche/songs/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        try {
            const detail = await fetchNicheTrackDetail(id, req.userId)
            if (!detail) {
                return sendError(res, "MUSIC_NICHE_SONG_NOT_FOUND", "Song not found", 404)
            }

            return sendSuccess(res, detail)
        } catch (error) {
            const message = error instanceof Error ? error.message : "Song fetch failed"
            return sendError(res, "MUSIC_NICHE_SONG_FETCH_FAILED", message, 500)
        }
    })

    const handleGetNicheRelease = async (req: { params: unknown; userId?: string }, res: Parameters<typeof sendSuccess>[0]) => {
        const { id } = req.params as { id: string }

        try {
            const detail = await fetchNicheReleaseDetail(id, req.userId)
            if (!detail) {
                return sendError(res, "MUSIC_NICHE_RELEASE_NOT_FOUND", "Release not found", 404)
            }

            const { release, owner, tracks, track_count, viewer } = detail

            return sendSuccess(res, {
                release,
                album: {
                    id: release.id,
                    name: release.name ?? "",
                    artwork_url: release.artwork_url ?? "",
                    owner_id: release.owner_id,
                    release_date: release.release_date,
                    release_type: release.release_type,
                    visibility: release.visibility,
                    description: release.description,
                    track_count,
                    like_count: release.like_count,
                    save_count: release.save_count,
                    share_count: release.share_count,
                    created_at: release.created_at,
                    updated_at: release.updated_at,
                },
                owner,
                tracks,
                viewer,
            })
        } catch (error) {
            const message = error instanceof Error ? error.message : "Release fetch failed"
            return sendError(res, "MUSIC_NICHE_RELEASE_FETCH_FAILED", message, 500)
        }
    }

    app.get("/music/niche/releases/:id", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        return handleGetNicheRelease(req, res)
    })

    app.get("/music/niche/albums/:id", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        return handleGetNicheRelease(req, res)
    })

    app.get('/music/niche/songs/:id/lyrics', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { data, error } = await supabase.schema("public").from("niche_track_lyrics").select("*").eq("track_id", id).maybeSingle()
        if (error) return sendError(res, "MUSIC_NICHE_SONG_LYRICS_FETCH_FAILED", error.message, 500)

        if (!data) return sendError(res, "MUSIC_NICHE_SONG_LYRICS_NOT_FOUND", "Lyrics not found", 404)

        return sendSuccess(res, {
            lyrics: data,
        })
    })

    app.post('/music/niche/songs/:id/like', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: like_data, error: like_error } = await supabase.schema("public").rpc("like_niche_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (like_error) return sendError(res, "MUSIC_SONG_LIKE_FAILED", like_error.message, 500)
        return sendSuccess(res, { message: "Song liked successfully", like_data: like_data })
    })

    app.post('/music/niche/songs/:id/unlike', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unlike_data, error: unlike_error } = await supabase.schema("public").rpc("unlike_niche_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (unlike_error) return sendError(res, "MUSIC_SONG_UNLIKE_FAILED", unlike_error.message, 500)
        return sendSuccess(res, { message: "Song unliked successfully", unlike_data: unlike_data })
    })

    app.post('/music/niche/songs/:id/save', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: save_data, error: save_error } = await supabase.schema("public").rpc("save_niche_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (save_error) return sendError(res, "MUSIC_SONG_SAVE_FAILED", save_error.message, 500)
        return sendSuccess(res, { message: "Song saved successfully", save_data: save_data })
    })

    app.post('/music/niche/songs/:id/unsave', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: unsave_data, error: unsave_error } = await supabase.schema("public").rpc("unsave_niche_track", {
            actor_id: req.userId,
            target_track_id: id,
        })

        if (unsave_error) return sendError(res, "MUSIC_SONG_UNSAVE_FAILED", unsave_error.message, 500)
        return sendSuccess(res, { message: "Song unsaved successfully", unsave_data: unsave_data })
    })

    app.post('/music/niche/songs/:id/play', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const parsedBody = recordNicheTrackPlaySchema.parse(req.body ?? {})

        const { data: track, error: trackError } = await supabase
            .schema("public")
            .from("niche_tracks")
            .select("id, owner_id, duration_ms, deleted_at")
            .eq("id", id)
            .maybeSingle()

        if (trackError) {
            return sendError(res, "MUSIC_SONG_PLAY_FETCH_FAILED", trackError.message, 500)
        }

        if (!track || track.deleted_at) {
            return sendError(res, "MUSIC_SONG_NOT_FOUND", "Song not found", 404)
        }

        if (track.owner_id === req.userId) {
            return sendSuccess(res, { recorded: false, reason: "owner_play_excluded" })
        }

        const now = new Date().toISOString()
        const durationMs = typeof track.duration_ms === "number" && track.duration_ms > 0 ? track.duration_ms : null
        const percentPlayed =
            parsedBody.percentPlayed ??
            (durationMs ? Math.min(1, parsedBody.listenMs / durationMs) : null)

        const { error: insertError } = await supabase
            .schema("public")
            .from("niche_track_play_events")
            .insert({
                id: generateRandomId(16),
                track_id: id,
                user_id: req.userId,
                listen_ms: parsedBody.listenMs,
                source: parsedBody.source ?? "ios",
                platform: "ios",
                app_version: parsedBody.appVersion ?? null,
                context_type: parsedBody.contextType ?? null,
                context_id: parsedBody.contextId ?? null,
                percent_played: percentPlayed,
                completed: parsedBody.completed ?? false,
                started_at: now,
                ended_at: now,
                metadata: {},
            })

        if (insertError) {
            return sendError(res, "MUSIC_SONG_PLAY_RECORD_FAILED", insertError.message, 500)
        }

        return sendSuccess(res, { recorded: true })
    })

    // comments
    app.get("/music/niche/songs/:id/comments", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursor, limit } = listCommentsQuerySchema.parse(req.query)
        const decoded = decodeCommentCursor(cursor)

        let query = supabase
            .schema("public")
            .from("niche_track_comments")
            .select(`
                id,
                track_id,
                owner_id,
                parent_comment_id,
                reply_to_comment_id,
                reply_to_user_id,
                kind,
                content,
                like_count,
                reply_count,
                is_hidden,
                is_pinned,
                created_at,
                owner:profiles!niche_track_comments_owner_id_fkey(id, username, avatar_url),
                niche_track_comment_likes!left(liker_id)
              `)
            .eq("track_id", id)
            .is("parent_comment_id", null)
            .order("is_pinned", { ascending: false })
            .order("is_hidden", { ascending: true })
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(limit + 1)

        if (req.userId) query = query.eq("niche_track_comment_likes.liker_id", req.userId)
        if (decoded) query = query.lt("created_at", decoded.createdAt)

        const { data, error } = await query

        if (error) return sendError(res, "COMMENTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const sliced = hasMore ? rows.slice(0, limit) : rows
        const nextCursor = hasMore ? encodeCommentCursor({ createdAt: sliced[sliced.length - 1]?.created_at, id: sliced[sliced.length - 1]?.id }) : null

        return sendSuccess(res, {
            comments: addViewerToComments(sliced, req.userId),
        }, {
            pagination: {
                nextCursor,
                limit,
                hasMore,
            },
        })
    })

    app.get("/music/niche/songs/:id/comments/:commentId/replies", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id, commentId } = req.params as { id: string; commentId: string }
        const { cursor, limit } = listCommentsQuerySchema.parse(req.query)
        const decoded = decodeCommentCursor(cursor)

        let query = supabase
            .schema("public")
            .from("niche_track_comments")
            .select(`
                id,
                track_id,
                owner_id,
                parent_comment_id,
                reply_to_comment_id,
                reply_to_user_id,
                kind,
                content,
                like_count,
                reply_count,
                is_hidden,
                is_pinned,
                created_at,
                owner:profiles!niche_track_comments_owner_id_fkey(id, username, avatar_url),
                niche_track_comment_likes!left(liker_id)
              `)
            .eq("track_id", id)
            .eq("parent_comment_id", commentId)
            .order("is_hidden", { ascending: true })
            .order("created_at", { ascending: true })
            .order("id", { ascending: true })
            .limit(limit + 1)

        if (req.userId) query = query.eq("niche_track_comment_likes.liker_id", req.userId)
        if (decoded) query = query.gt("created_at", decoded.createdAt)

        const { data, error } = await query

        if (error) return sendError(res, "REPLIES_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const sliced = hasMore ? rows.slice(0, limit) : rows
        const nextCursor = hasMore ? encodeCommentCursor({ createdAt: sliced[sliced.length - 1]?.created_at, id: sliced[sliced.length - 1]?.id }) : null

        return sendSuccess(res, {
            comments: addViewerToComments(sliced, req.userId),
        }, {
            pagination: {
                nextCursor,
                limit,
                hasMore,
            },
        })
    })

    app.post("/music/niche/songs/:id/comments/create", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const parsedBody = createCommentSchema.parse(req.body)

        try {
            const commentId = generateRandomId(16)
            const content = await buildCommentContent(parsedBody)

            const { data, error } = await supabase.rpc("create_niche_track_comment", {
                actor_id: req.userId,
                target_track_id: id,
                comment_id: commentId,
                comment_kind: parsedBody.kind,
                comment_content: content,
                parent_id: parsedBody.parentCommentId ?? null,
                reply_to_id: parsedBody.replyToCommentId ?? null,
            })

            if (error) return sendError(res, "COMMENT_CREATE_FAILED", error.message, 400)

            if (parsedBody.replyToCommentId) {
                const { data: replyTarget } = await supabase
                    .schema("public")
                    .from("niche_track_comments")
                    .select("id, owner_id")
                    .eq("id", parsedBody.replyToCommentId)
                    .maybeSingle()

                if (replyTarget?.owner_id) {
                    void sendNicheTrackCommentReplyNotification(
                        req.userId,
                        replyTarget.owner_id,
                        replyTarget.id,
                        id
                    ).catch((notifyError) => {
                        req.log.warn({ err: notifyError }, "track comment reply notification failed")
                    })
                }
            } else {
                const { data: trackOwner } = await supabase
                    .schema("public")
                    .from("niche_tracks")
                    .select("owner_id")
                    .eq("id", id)
                    .maybeSingle()

                if (trackOwner?.owner_id) {
                    void sendNicheTrackCommentNotification(req.userId, trackOwner.owner_id, id, commentId).catch(
                        (notifyError) => {
                            req.log.warn({ err: notifyError }, "track comment notification failed")
                        }
                    )
                }
            }

            return sendSuccess(res, {
                message: "Comment created successfully",
                commentId,
            }, undefined, 201)
        } catch (error) {
            return sendError(res, "INVALID_COMMENT", error instanceof Error ? error.message : "Invalid comment", 400)
        }
    })

    app.post("/music/niche/comments/:id/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("delete_niche_track_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_DELETE_FAILED", error.message, 400)

        return sendSuccess(res, {
            message: "Comment deleted successfully",
        })
    })

    app.post("/music/niche/comments/:id/like", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { data: comment, error: commentError } = await supabase
            .schema("public")
            .from("niche_track_comments")
            .select("id, owner_id, track_id")
            .eq("id", id)
            .maybeSingle()
        if (commentError) return sendError(res, "COMMENT_LIKE_FAILED", commentError.message, 400)
        if (!comment) return sendError(res, "COMMENT_LIKE_FAILED", "Comment not found", 404)

        const { error } = await supabase.rpc("like_niche_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_LIKE_FAILED", error.message, 400)

        void sendNicheTrackCommentLikeNotification(
            req.userId,
            comment.owner_id,
            comment.id,
            comment.track_id
        ).catch((notifyError) => {
            req.log.warn({ err: notifyError }, "track comment like notification failed")
        })

        return sendSuccess(res, {
            liked: true,
        })
    })


    app.post("/music/niche/comments/:id/unlike", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unlike_niche_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNLIKE_FAILED", error.message, 400)

        return sendSuccess(res, {
            liked: false,
        })
    })

    app.get('/music/niche/comments/:id/likes', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursorCreatedAt, cursorUserId, limit } = parseInteractionQuery(req.query)

        let query = supabase
            .schema("public")
            .from("niche_track_comment_likes")
            .select("created_at, liker_id, user:profiles!niche_track_comment_likes_liker_id_fkey(id, username, avatar_url, display_name, followers_count)")
            .eq("comment_id", id) // we can order by created at and by followers (so people with more followers are at the top)
            .order("created_at", { ascending: false })
            .order("followers_count", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorUserId) {
            query = query.or(
                `created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},liker_id.lt.${cursorUserId})`
            )
        }

        const { data, error } = await query
        if (error) return sendError(res, "COMMENT_LIKES_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const sliced = hasMore ? rows.slice(0, limit) : rows
        const last = sliced[sliced.length - 1]

        return sendSuccess(res, {
            users: sliced.map((row) => ({
                ...(row.user ?? {}),
                interacted_at: row.created_at,
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: toUtcZulu(last.created_at), cursorUserId: last.liker_id }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.post("/music/niche/comments/:id/pin", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("pin_niche_track_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_PIN_FAILED", error.message, 400)

        return sendSuccess(res, {
            pinned: true,
        })
    })

    app.post("/music/niche/comments/:id/unpin", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unpin_niche_track_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNPIN_FAILED", error.message, 400)

        return sendSuccess(res, {
            pinned: false,
        })
    })

    app.post("/music/niche/comments/:id/hide", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("hide_niche_track_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_HIDE_FAILED", error.message, 400)

        return sendSuccess(res, {
            hidden: true,
        })
    })

    app.post("/music/niche/comments/:id/unhide", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unhide_niche_track_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNHIDE_FAILED", error.message, 400)

        return sendSuccess(res, {
            hidden: false,
        })
    })

    // CREATE TRACK FLOWS

    app.get("/music/niche/songs/drafts", { preHandler: app.authenticate }, async (req, res) => {
        const { limit } = listDraftsQuerySchema.parse(req.query)

        const { data, error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select(TRACK_DRAFT_LIST_COLUMNS)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .is("release_draft_id", null)
            .order("updated_at", { ascending: false, nullsFirst: false })
            .order("created_at", { ascending: false })
            .limit(limit)

        if (error) return sendError(res, "DRAFT_LIST_FAILED", error.message, 500)

        return sendSuccess(res, {
            drafts: data ?? [],
        })
    })

    app.get("/music/niche/songs/draft/:id", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: draft, error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select(`${TRACK_DRAFT_DETAIL_COLUMNS}, credits:niche_track_artist_drafts(${TRACK_DRAFT_CREDITS_SELECT})`)
            .eq("id", id)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .is("release_draft_id", null)
            .maybeSingle()

        if (error) return sendError(res, "DRAFT_FETCH_FAILED", error.message, 500)
        if (!draft) return sendError(res, "DRAFT_NOT_FOUND", "Draft not found", 404)

        const uploadStatus = await draftAssetUploadStatus(draft)

        return sendSuccess(res, {
            draft,
            uploadStatus,
        })
    })

    app.post("/music/niche/songs/draft/:id/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const now = new Date().toISOString()

        const { data: draft, error: fetchError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("id")
            .eq("id", id)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .is("release_draft_id", null)
            .maybeSingle()

        if (fetchError) return sendError(res, "DRAFT_DELETE_FAILED", fetchError.message, 500)
        if (!draft) return sendError(res, "DRAFT_NOT_FOUND", "Draft not found", 404)

        const { error: deleteCreditsError } = await supabase
            .schema("public")
            .from("niche_track_artist_drafts")
            .delete()
            .eq("draft_id", id)

        if (deleteCreditsError) {
            return sendError(res, "DRAFT_DELETE_FAILED", deleteCreditsError.message, 500)
        }

        const { error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .update({ deleted_at: now })
            .eq("id", id)
            .eq("owner_id", req.userId)

        if (error) return sendError(res, "DRAFT_DELETE_FAILED", error.message, 500)

        return sendSuccess(res, { id }, undefined, 204)
    })

    app.post("/music/niche/songs/draft/:id/music/upload", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { musicFormat } = draftMusicUploadSchema.parse(req.body)

        const { data: draft, error: fetchError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("id, release_draft_id")
            .eq("id", id)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) return sendError(res, "DRAFT_MUSIC_UPLOAD_FAILED", fetchError.message, 500)
        if (!draft) return sendError(res, "DRAFT_NOT_FOUND", "Draft not found", 404)
        if (draft.release_draft_id) {
            return sendError(res, "DRAFT_MUSIC_UPLOAD_FAILED", "Use the release track music upload route", 400)
        }

        const upload = await getNicheTrackMusicPresignedUrl(id, musicFormat)

        const { error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .update({ music_url: upload.publicUrl })
            .eq("id", id)
            .eq("owner_id", req.userId)

        if (error) return sendError(res, "DRAFT_MUSIC_UPLOAD_FAILED", error.message, 500)

        return sendSuccess(res, {
            id,
            upload,
        })
    })

    app.get("/music/niche/releases/drafts", { preHandler: app.authenticate }, async (req, res) => {
        const { limit } = listDraftsQuerySchema.parse(req.query)

        const { data: releaseDrafts, error } = await supabase
            .schema("public")
            .from("niche_release_drafts")
            .select(`${RELEASE_DRAFT_LIST_COLUMNS}, tracks:niche_track_drafts(count)`)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .order("updated_at", { ascending: false, nullsFirst: false })
            .order("created_at", { ascending: false })
            .limit(limit)

        if (error) return sendError(res, "RELEASE_DRAFT_LIST_FAILED", error.message, 500)

        const drafts = (releaseDrafts ?? []).map((row) => {
            const trackCount = Array.isArray(row.tracks) && row.tracks[0] && typeof row.tracks[0].count === "number"
                ? row.tracks[0].count
                : 0
            const { tracks: _tracks, ...rest } = row as Record<string, unknown>
            return {
                ...rest,
                track_count: trackCount,
            }
        })

        return sendSuccess(res, {
            drafts,
        })
    })

    app.get("/music/niche/releases/draft/:releaseDraftId", { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId } = req.params as { releaseDraftId: string }

        const { data: releaseDraft, error: releaseError } = await supabase
            .schema("public")
            .from("niche_release_drafts")
            .select(RELEASE_DRAFT_DETAIL_COLUMNS)
            .eq("id", releaseDraftId)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .maybeSingle()

        if (releaseError) return sendError(res, "RELEASE_DRAFT_FETCH_FAILED", releaseError.message, 500)
        if (!releaseDraft) return sendError(res, "RELEASE_DRAFT_NOT_FOUND", "Release draft not found", 404)

        const { data: tracks, error: tracksError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select(`${TRACK_DRAFT_DETAIL_COLUMNS}, credits:niche_track_artist_drafts(${TRACK_DRAFT_CREDITS_SELECT})`)
            .eq("release_draft_id", releaseDraftId)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .order("track_number", { ascending: true, nullsFirst: false })
            .order("created_at", { ascending: true })

        if (tracksError) return sendError(res, "RELEASE_DRAFT_FETCH_FAILED", tracksError.message, 500)

        const releaseUploadStatus = releaseDraft.artwork_url
            ? { artwork: (await fetchAssetHead(releaseDraft.artwork_url)).ok }
            : { artwork: false }

        const trackUploadStatuses = await Promise.all(
            (tracks ?? []).map(async (track) => ({
                id: track.id,
                uploadStatus: await draftAssetUploadStatus(track),
            }))
        )

        return sendSuccess(res, {
            draft: releaseDraft,
            tracks: tracks ?? [],
            uploadStatus: {
                release: releaseUploadStatus,
                tracks: trackUploadStatuses,
            },
        })
    })

    app.post("/music/niche/releases/draft/:releaseDraftId/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId } = req.params as { releaseDraftId: string }
        const now = new Date().toISOString()

        const { data: releaseDraft, error: fetchError } = await supabase
            .schema("public")
            .from("niche_release_drafts")
            .select("id")
            .eq("id", releaseDraftId)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) return sendError(res, "RELEASE_DRAFT_DELETE_FAILED", fetchError.message, 500)
        if (!releaseDraft) return sendError(res, "RELEASE_DRAFT_NOT_FOUND", "Release draft not found", 404)

        const { data: trackDrafts, error: tracksError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("id")
            .eq("release_draft_id", releaseDraftId)
            .eq("owner_id", req.userId)

        if (tracksError) return sendError(res, "RELEASE_DRAFT_DELETE_FAILED", tracksError.message, 500)

        const trackDraftIds = (trackDrafts ?? []).map((track) => track.id)

        if (trackDraftIds.length > 0) {
            const { error: deleteCreditsError } = await supabase
                .schema("public")
                .from("niche_track_artist_drafts")
                .delete()
                .in("draft_id", trackDraftIds)

            if (deleteCreditsError) {
                return sendError(res, "RELEASE_DRAFT_DELETE_FAILED", deleteCreditsError.message, 500)
            }

            const { error: deleteTracksError } = await supabase
                .schema("public")
                .from("niche_track_drafts")
                .update({ deleted_at: now })
                .eq("release_draft_id", releaseDraftId)
                .eq("owner_id", req.userId)

            if (deleteTracksError) {
                return sendError(res, "RELEASE_DRAFT_DELETE_FAILED", deleteTracksError.message, 500)
            }
        }

        const { error } = await supabase
            .schema("public")
            .from("niche_release_drafts")
            .update({ deleted_at: now })
            .eq("id", releaseDraftId)
            .eq("owner_id", req.userId)

        if (error) return sendError(res, "RELEASE_DRAFT_DELETE_FAILED", error.message, 500)

        return sendSuccess(res, { id: releaseDraftId }, undefined, 204)
    })

    app.post("/music/niche/releases/:releaseDraftId/tracks/draft/:trackDraftId/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId, trackDraftId } = req.params as { releaseDraftId: string; trackDraftId: string }
        const now = new Date().toISOString()

        const { data: trackDraft, error: fetchError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("id")
            .eq("id", trackDraftId)
            .eq("release_draft_id", releaseDraftId)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) return sendError(res, "DRAFT_DELETE_FAILED", fetchError.message, 500)
        if (!trackDraft) return sendError(res, "DRAFT_NOT_FOUND", "Track draft not found", 404)

        const { error: deleteCreditsError } = await supabase
            .schema("public")
            .from("niche_track_artist_drafts")
            .delete()
            .eq("draft_id", trackDraftId)

        if (deleteCreditsError) {
            return sendError(res, "DRAFT_DELETE_FAILED", deleteCreditsError.message, 500)
        }

        const { error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .update({ deleted_at: now })
            .eq("id", trackDraftId)
            .eq("owner_id", req.userId)

        if (error) return sendError(res, "DRAFT_DELETE_FAILED", error.message, 500)

        return sendSuccess(res, { id: trackDraftId }, undefined, 204)
    })

    app.post("/music/niche/releases/:releaseDraftId/tracks/draft/:trackDraftId/music/upload", { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId, trackDraftId } = req.params as { releaseDraftId: string; trackDraftId: string }
        const { musicFormat } = draftMusicUploadSchema.parse(req.body)

        const { data: trackDraft, error: fetchError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("id")
            .eq("id", trackDraftId)
            .eq("release_draft_id", releaseDraftId)
            .eq("owner_id", req.userId)
            .eq("draft_status", "draft")
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) return sendError(res, "DRAFT_MUSIC_UPLOAD_FAILED", fetchError.message, 500)
        if (!trackDraft) return sendError(res, "DRAFT_NOT_FOUND", "Track draft not found", 404)

        const upload = await getNicheTrackMusicPresignedUrl(trackDraftId, musicFormat)

        const { error } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .update({ music_url: upload.publicUrl })
            .eq("id", trackDraftId)
            .eq("owner_id", req.userId)

        if (error) return sendError(res, "DRAFT_MUSIC_UPLOAD_FAILED", error.message, 500)

        return sendSuccess(res, {
            id: trackDraftId,
            upload,
        })
    })


    // create draft for a single; literally just creates a draft, and returns a signed url for the MUSIC upload
    app.post("/music/niche/songs/draft/create", { preHandler: app.authenticate }, async (req, res) => { // CRET
        const id = generateRandomId(16) // generate random id for the song (and draft)
        const { musicFormat } = req.body as { musicFormat: MusicFormat }
        const upload = await getNicheTrackMusicPresignedUrl(id, musicFormat)

        const { data, error } = await supabase.schema("public").from("niche_track_drafts").insert({
            id,
            owner_id: req.userId,
            // dont set name
            music_url: upload.publicUrl,
            // release date is in YYYY-MM-DD format
            release_date: new Date().toISOString().split('T')[0]
        })

        if (error) return sendError(res, "DRAFT_CREATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id,
            upload
        })

    })
    // next, the user uploads the music in the background, and starts actually creating the metadata of the track

    app.post("/music/niche/songs/draft/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const parsedBody = updateNicheTrackDraftSchema.parse(req.body)

        // update credits
        if (parsedBody.credits?.hasCredits) {
            const { error: deleteCreditsError } = await supabase
                .schema("public")
                .from("niche_track_artist_drafts")
                .delete()
                .eq("draft_id", id)

            if (deleteCreditsError) {
                return sendError(res, "DRAFT_UPDATE_FAILED", deleteCreditsError.message, 500)
            }

            const artists = parsedBody.credits.artists ?? []

            if (artists.length > 0) {
                const { error: insertCreditsError } = await supabase
                    .schema("public")
                    .from("niche_track_artist_drafts")
                    .insert(
                        artists.map((artist) => ({
                            draft_id: id,
                            artist_id: artist.artistId,
                            is_primary: artist.isPrimary ?? false,
                        }))
                    )

                if (insertCreditsError) {
                    return sendError(res, "DRAFT_UPDATE_FAILED", insertCreditsError.message, 500)
                }
            }
        }

        const updateData: Record<string, any> = {
            name: parsedBody.name,
            release_date: parsedBody.release_date,
            explicit: parsedBody.explicit,
            duration_ms: parsedBody.duration_ms,
            bpm: parsedBody.bpm,
            visibility: parsedBody.visibility,
        }

        var imageUpload: PresignedUploadResult | null = null
        var momentUpload: PresignedUploadResult | null = null

        // do image and moment uploads if needed
        if (parsedBody.image?.hasImage) {
            imageUpload = await getNicheTrackImagePresignedUrl(id, parsedBody.image.imageFormat as UploadFormat)
            updateData.artwork_url = imageUpload?.publicUrl
        }
        if (parsedBody.moment?.hasMoment) {
            momentUpload = await getNicheTrackMomentPresignedUrl(id, parsedBody.moment.momentFormat as VideoFormat)
            updateData.moment_url = momentUpload?.publicUrl
        }

        const cleanedUpdateData = Object.fromEntries(
            Object.entries(updateData).filter(([, value]) => value !== undefined)
        )

        const { data, error } = await supabase.schema("public").from("niche_track_drafts").update(cleanedUpdateData).eq("id", id).eq("owner_id", req.userId).select().maybeSingle()

        if (error) return sendError(res, "DRAFT_UPDATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id,
            draft: data,
            upload: {
                image: imageUpload,
                moment: momentUpload,
            },
        })
    })

    app.post("/music/niche/songs/draft/:id/publish", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        // check if draft exists, everything is good, fetch image + music + moment and check if we get a good repsonse
        // if all is good, change draft status to published, and then create a new track with all the metadata (and credits)
        const { data: draft, error } = await supabase.schema("public").from("niche_track_drafts").select().eq("id", id).eq("owner_id", req.userId).maybeSingle()
        if (error) return sendError(res, "DRAFT_PUBLISH_FAILED", error.message, 500)
        if (!draft) return sendError(res, "DRAFT_PUBLISH_FAILED", "Draft not found", 404)

        // in parallel, fetch a small sample of music and moment and image and check if we get a good repsonse (headers)
        const checks: Promise<Response>[] = [
            fetchAssetHead(draft.music_url)
        ]
        if (draft.moment_url) checks.push(fetchAssetHead(draft.moment_url))
        if (draft.artwork_url) checks.push(fetchAssetHead(draft.artwork_url))
        let responses: Response[]
        try {
            responses = await Promise.all(checks)
        } catch (err) {
            const message = err instanceof Error ? err.message : "Asset URL check failed"
            return sendError(res, "DRAFT_PUBLISH_FAILED", message, 400)
        }

        for (const response of responses) {
            if (!response.ok) return sendError(res, "DRAFT_PUBLISH_FAILED", "File not found", 404)
        }

        // create a new actual track with metadata
        const { data: track, error: trackError } = await supabase.schema("public").from("niche_tracks").insert({
            id: draft.id,
            owner_id: req.userId,
            name: draft.name,
            release_date: draft.release_date,
            artwork_url: normalizePublicAssetUrl(draft.artwork_url) ?? draft.artwork_url,
            music_url: normalizePublicAssetUrl(draft.music_url) ?? draft.music_url,
            explicit: draft.explicit,
            has_lyrics: false, // all tracks dont have lyrics to start
            duration_ms: draft.duration_ms,
            popularity: 0,
            bpm: draft.bpm ?? 0,
            visibility: draft.visibility,
            gain: 0,
            moment_url: normalizePublicAssetUrl(draft.moment_url) ?? draft.moment_url,
        }).select().single()
        if (trackError) return sendError(res, "DRAFT_PUBLISH_FAILED", trackError.message, 500)
        if (!track) return sendError(res, "DRAFT_PUBLISH_FAILED", "Track not created", 500)

        // create credits

        const { data: draftCredits, error: draftCreditsError } = await supabase.schema("public").from("niche_track_artist_drafts").select().eq("draft_id", id)
        if (draftCreditsError) return sendError(res, "DRAFT_PUBLISH_FAILED", draftCreditsError.message, 500)
        const creditsToAdd = draftCredits.map((credit) => ({
            track_id: track.id,
            artist_id: credit.artist_id,
            is_primary: credit.is_primary,
        }))
        const { data: credits, error: creditsError } = await supabase.schema("public").from("niche_track_artists").insert(creditsToAdd)
        if (creditsError) return sendError(res, "DRAFT_PUBLISH_FAILED", creditsError.message, 500)


        // change draft status to published
        const { error: updateError } = await supabase.schema("public").from("niche_track_drafts").update({
            draft_status: "published",
            published_at: new Date().toISOString(),
        }).eq("id", id).eq("owner_id", req.userId)
        if (updateError) return sendError(res, "DRAFT_PUBLISH_FAILED", updateError.message, 500)


        return sendSuccess(res, {
            id: track.id,
            track,
        })
    })

    // album + ep flows
    app.post('/music/niche/releases/draft/create', { preHandler: app.authenticate }, async (req, res) => {
        const id = generateRandomId(16)
        const { releaseType } = req.body as { releaseType: "album" | "ep" }
        const { data, error } = await supabase.schema("public").from("niche_release_drafts").insert({
            id,
            owner_id: req.userId,
            release_type: releaseType,
            release_date: new Date().toISOString().split('T')[0]
        })

        if (error) return sendError(res, "RELEASE_DRAFT_CREATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id
        })


    })

    app.post('/music/niche/releases/draft/:releaseDraftId/update', { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId } = req.params as { releaseDraftId: string }
        const parsedBody = updateReleaseDraftSchema.parse(req.body)

        const updateData: Record<string, any> = {
            name: parsedBody.name,
            release_date: parsedBody.release_date,
            visibility: parsedBody.visibility,
            release_type: parsedBody.release_type,
        }

        var imageUpload: PresignedUploadResult | null = null
        if (parsedBody.image?.hasImage) {
            imageUpload = await getNicheTrackImagePresignedUrl(releaseDraftId, parsedBody.image.imageFormat as UploadFormat)
            updateData.artwork_url = imageUpload?.publicUrl
        }

        const cleanedUpdateData = Object.fromEntries(
            Object.entries(updateData).filter(([, value]) => value !== undefined)
        )

        const { data, error } = await supabase.schema("public").from("niche_release_drafts").update(cleanedUpdateData).eq("id", releaseDraftId).eq("owner_id", req.userId).select().maybeSingle()
        if (error) return sendError(res, "RELEASE_DRAFT_UPDATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id: releaseDraftId,
            draft: data,
            upload: {
                image: imageUpload,
            },
        })
    })

    app.post('/music/niche/releases/:releaseDraftId/tracks/draft/create', { preHandler: app.authenticate }, async (req, res) => {
        const id = generateRandomId(16) // generate random id for the song (and draft)
        const { releaseDraftId } = req.params as { releaseDraftId: string }
        const { musicFormat } = req.body as { musicFormat: MusicFormat }
        const upload = await getNicheTrackMusicPresignedUrl(id, musicFormat)

        // check if release draft exists and user owns it
        const { data: releaseDraft, error: releaseDraftError } = await supabase.schema("public").from("niche_release_drafts").select().eq("id", releaseDraftId).eq("owner_id", req.userId).maybeSingle()
        if (releaseDraftError) return sendError(res, "DRAFT_CREATE_FAILED", releaseDraftError.message, 500)
        if (!releaseDraft) return sendError(res, "DRAFT_CREATE_FAILED", "Release draft not found", 404)

        const { data, error } = await supabase.schema("public").from("niche_track_drafts").insert({
            id,
            owner_id: req.userId,
            // dont set name
            music_url: upload.publicUrl,
            // release date is in YYYY-MM-DD format
            release_date: new Date().toISOString().split('T')[0],
            release_draft_id: releaseDraftId,
        })

        if (error) return sendError(res, "DRAFT_CREATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id,
            upload
        })
    })

    app.post('/music/niche/releases/:releaseDraftId/tracks/draft/:trackDraftId/update', { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId, trackDraftId } = req.params as { releaseDraftId: string, trackDraftId: string }
        const parsedBody = updateNicheTrackOnReleaseDraftSchema.parse(req.body)

        // check if release draft exists and user owns it
        const { data: releaseDraft, error: releaseDraftError } = await supabase.schema("public").from("niche_release_drafts").select().eq("id", releaseDraftId).eq("owner_id", req.userId).maybeSingle()
        if (releaseDraftError) return sendError(res, "DRAFT_UPDATE_FAILED", releaseDraftError.message, 500)
        if (!releaseDraft) return sendError(res, "DRAFT_UPDATE_FAILED", "Release draft not found", 404)

        const updateData: Record<string, any> = {
            name: parsedBody.name,
            release_date: parsedBody.release_date,
            explicit: parsedBody.explicit,
            duration_ms: parsedBody.duration_ms,
            bpm: parsedBody.bpm,
            visibility: parsedBody.visibility,
            track_number: parsedBody.track_number,
        }

        var imageUpload: PresignedUploadResult | null = null
        var momentUpload: PresignedUploadResult | null = null

        // do image and moment uploads if needed
        if (parsedBody.image?.hasImage) {
            imageUpload = await getNicheTrackImagePresignedUrl(trackDraftId, parsedBody.image.imageFormat as UploadFormat)
            updateData.artwork_url = imageUpload?.publicUrl
        } // ui will default to release artwork if no image is uploaded

        if (parsedBody.moment?.hasMoment) {
            momentUpload = await getNicheTrackMomentPresignedUrl(trackDraftId, parsedBody.moment.momentFormat as VideoFormat)
            updateData.moment_url = momentUpload?.publicUrl
        }

        const cleanedUpdateData = Object.fromEntries(
            Object.entries(updateData).filter(([, value]) => value !== undefined)
        )

        const { data, error } = await supabase.schema("public").from("niche_track_drafts").update(cleanedUpdateData).eq("id", trackDraftId).eq("owner_id", req.userId).eq("release_draft_id", releaseDraftId).select().maybeSingle()
        if (error) return sendError(res, "DRAFT_UPDATE_FAILED", error.message, 500)


        // update credits
        if (parsedBody.credits?.hasCredits) {
            const { error: deleteCreditsError } = await supabase
                .schema("public")
                .from("niche_track_artist_drafts")
                .delete()
                .eq("draft_id", trackDraftId)

            if (deleteCreditsError) {
                return sendError(res, "DRAFT_UPDATE_FAILED", deleteCreditsError.message, 500)
            }

            const artists = parsedBody.credits.artists ?? []

            if (artists.length > 0) {
                const { error: insertCreditsError } = await supabase
                    .schema("public")
                    .from("niche_track_artist_drafts")
                    .insert(
                        artists.map((artist) => ({
                            draft_id: trackDraftId,
                            artist_id: artist.artistId,
                            is_primary: artist.isPrimary ?? false,
                        }))
                    )

                if (insertCreditsError) {
                    return sendError(res, "DRAFT_UPDATE_FAILED", insertCreditsError.message, 500)
                }
            }
        }

        return sendSuccess(res, {
            id: trackDraftId,
            draft: data,
            upload: {
                image: imageUpload,
                moment: momentUpload,
            },
        })
    })

    app.post('/music/niche/releases/:releaseDraftId/publish', { preHandler: app.authenticate }, async (req, res) => {
        const { releaseDraftId } = req.params as { releaseDraftId: string }

        const { data: releaseDraft, error: releaseDraftError } = await supabase
            .schema("public")
            .from("niche_release_drafts")
            .select()
            .eq("id", releaseDraftId)
            .eq("owner_id", req.userId)
            .maybeSingle()

        if (releaseDraftError) {
            return sendError(res, "RELEASE_PUBLISH_FAILED", releaseDraftError.message, 500)
        }

        if (!releaseDraft) {
            return sendError(res, "RELEASE_PUBLISH_FAILED", "Release draft not found", 404)
        }

        const { data: tracks, error: tracksError } = await supabase
            .schema("public")
            .from("niche_track_drafts")
            .select("music_url, artwork_url, moment_url")
            .eq("release_draft_id", releaseDraftId)
            .eq("owner_id", req.userId)

        if (tracksError) {
            return sendError(res, "RELEASE_PUBLISH_FAILED", tracksError.message, 500)
        }

        const checks: Promise<Response>[] = []

        if (releaseDraft.artwork_url) {
            checks.push(fetchAssetHead(releaseDraft.artwork_url))
        }

        for (const track of tracks ?? []) {
            checks.push(fetchAssetHead(track.music_url))

            if (track.artwork_url) {
                checks.push(fetchAssetHead(track.artwork_url))
            }

            if (track.moment_url) {
                checks.push(fetchAssetHead(track.moment_url))
            }
        }

        const responses = await Promise.all(checks)

        for (const response of responses) {
            if (!response.ok) {
                return sendError(
                    res,
                    "RELEASE_PUBLISH_FAILED",
                    "One or more uploaded files could not be found.",
                    400
                )
            }
        }

        const { data: release, error } = await supabase.rpc(
            "publish_niche_release",
            {
                actor_id: req.userId,
                release_draft_id_arg: releaseDraftId,
            }
        )

        if (error) {
            return sendError(res, "RELEASE_PUBLISH_FAILED", error.message, 500)
        }

        return sendSuccess(res, {
            id: release.id,
            release,
        })
    })

    // TRACK ROUTES

    app.post('/music/niche/tracks/:trackId/update', { preHandler: app.authenticate }, async (req, res) => {
        const { trackId } = req.params as { trackId: string }
        const parsedBody = updateNicheTrackSchema.parse(req.body)

        const { data: existingTrack, error: fetchError } = await supabase
            .schema("public")
            .from("niche_tracks")
            .select("*")
            .eq("id", trackId)
            .eq("owner_id", req.userId)
            .maybeSingle()

        if (fetchError) return sendError(res, "TRACK_UPDATE_FAILED", fetchError.message, 500)
        if (!existingTrack) return sendError(res, "TRACK_NOT_FOUND", "Track not found", 404)

        if (parsedBody.credits?.hasCredits) {
            const { error: deleteCreditsError } = await supabase
                .schema("public")
                .from("niche_track_artists")
                .delete()
                .eq("track_id", trackId)

            if (deleteCreditsError) {
                return sendError(res, "TRACK_UPDATE_FAILED", deleteCreditsError.message, 500)
            }

            const artists = parsedBody.credits.artists ?? []

            if (artists.length > 0) {
                const { error: insertCreditsError } = await supabase
                    .schema("public")
                    .from("niche_track_artists")
                    .insert(
                        artists.map((artist) => ({
                            track_id: trackId,
                            artist_id: artist.artistId,
                            is_primary: artist.isPrimary ?? false,
                        }))
                    )

                if (insertCreditsError) {
                    return sendError(res, "TRACK_UPDATE_FAILED", insertCreditsError.message, 500)
                }
            }
        }

        const updateData: Record<string, any> = {
            name: parsedBody.name,
            explicit: parsedBody.explicit,
            bpm: parsedBody.bpm,
            visibility: parsedBody.visibility,
        }

        var imageUpload: PresignedUploadResult | null = null
        var momentUpload: PresignedUploadResult | null = null

        if (parsedBody.image?.hasImage) {
            imageUpload = await getNicheTrackImagePresignedUrl(trackId, parsedBody.image.imageFormat as UploadFormat)
            updateData.artwork_url = imageUpload?.publicUrl
        }

        if (parsedBody.moment?.hasMoment) {
            momentUpload = await getNicheTrackMomentPresignedUrl(trackId, parsedBody.moment.momentFormat as VideoFormat)
            updateData.moment_url = momentUpload?.publicUrl
        }

        const cleanedUpdateData = Object.fromEntries(
            Object.entries(updateData).filter(([, value]) => value !== undefined)
        )

        if (Object.keys(cleanedUpdateData).length > 0) {
            const { error } = await supabase
                .schema("public")
                .from("niche_tracks")
                .update(cleanedUpdateData)
                .eq("id", trackId)
                .eq("owner_id", req.userId)

            if (error) return sendError(res, "TRACK_UPDATE_FAILED", error.message, 500)
        }

        const detail = await fetchNicheTrackDetail(trackId, req.userId)
        if (!detail) {
            return sendError(res, "TRACK_UPDATE_FAILED", "Track not found after update", 500)
        }

        return sendSuccess(res, {
            id: trackId,
            track: detail.track,
            upload: {
                image: imageUpload,
                moment: momentUpload,
            },
        })
    })

    app.post('/music/niche/tracks/:trackId/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { trackId } = req.params as { trackId: string }
        // soft delete
        const { error } = await supabase.schema("public").from("niche_tracks").update({
            deleted_at: new Date().toISOString(),
            visibility: "private",
        }).eq("id", trackId).eq("owner_id", req.userId)
        if (error) return sendError(res, "TRACK_DELETE_FAILED", error.message, 500)

        // in future remove from other places aswell

        // return sendSuccess with 204
        return sendSuccess(res, null, undefined, 204)
    })

    app.post('/music/niche/releases/:releaseId/update', { preHandler: app.authenticate }, async (req, res) => {
        const { releaseId } = req.params as { releaseId: string }
        const parsedBody = updateReleaseSchema.parse(req.body)

        const updateData: Record<string, any> = {
            name: parsedBody.name,
            visibility: parsedBody.visibility,
            release_type: parsedBody.release_type,
        }

        var imageUpload: PresignedUploadResult | null = null
        if (parsedBody.image?.hasImage) {
            imageUpload = await getNicheTrackImagePresignedUrl(releaseId, parsedBody.image.imageFormat as UploadFormat)
            updateData.artwork_url = imageUpload?.publicUrl
        }

        const cleanedUpdateData = Object.fromEntries(
            Object.entries(updateData).filter(([, value]) => value !== undefined)
        )

        const { data, error } = await supabase.schema("public").from("niche_releases").update(cleanedUpdateData).eq("id", releaseId).eq("owner_id", req.userId).select().maybeSingle()
        if (error) return sendError(res, "RELEASE_UPDATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            id: releaseId,
            release: data,
            upload: {
                image: imageUpload,
            },
        })
    })

    app.post('/music/niche/releases/:releaseId/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { releaseId } = req.params as { releaseId: string }
        // soft delete
        const { error: deleteError } = await supabase.schema("public").from("niche_releases").update({
            deleted_at: new Date().toISOString(),
            visibility: "private",
        }).eq("id", releaseId).eq("owner_id", req.userId).select().maybeSingle()
        if (deleteError) return sendError(res, "RELEASE_DELETE_FAILED", deleteError.message, 500)

        // in future remove from other places aswell
        // return sendSuccess with 204
        return sendSuccess(res, null, undefined, 204)
    })


}

export { musicRoutes, nicheMusicRoutes }