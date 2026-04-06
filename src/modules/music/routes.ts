import { FastifyPluginAsync } from "fastify"
import env from "../../config/env.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { supabase } from "../../config/supabase.js"
import { getProfileByUsername, checkFollowing, upsertAlbum, upsertArtist, upsertTrack, syncAppleAlbumTracks, syncAppleArtistDiscography, getTrackViewerContext, getAlbumViewerContext, getArtistViewerContext, getTrackViewerContextMap, getAlbumViewerContextMap, getArtistViewerContextMap } from "./helpers.js"
import { musicLibraryQuerySchema, musicMeQuerySchema, musicFollowingQuerySchema, type Track } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"

const MUSIC_BASE_URL = "https://api.music.apple.com/v1/catalog/us"

function firstRow<T>(value: T | T[] | null | undefined): T | null {
    if (!value) return null
    return Array.isArray(value) ? (value[0] ?? null) : value
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

            return sendSuccess(res, {
                songs: tracks.map((track) => ({
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

            return sendSuccess(res, {
                songs: tracks.map((track) => ({
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

            return sendSuccess(res, {
                songs: tracks.map((track) => ({
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

export default musicRoutes