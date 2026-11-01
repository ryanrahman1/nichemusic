import { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { createPlaylistSchema, updatePlaylistSchema } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import { getPlaylistImagePresignedUrl } from "../../lib/image.js"
import { z } from "zod"
import { decodePlaylistCursor, encodePlaylistCursor, encodeCursor, decodeCursor, PLAYLIST_ITEM_SELECT } from "./helpers.js"


const playlistsRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me/playlists', { preHandler: app.authenticate }, async (req, res) => {
        const { cursor, limit } = req.query as {
            cursor?: string
            limit?: string
        }

        const pageSize = Math.min(Math.max(Number(limit) || 30, 1), 50)
        const decodedCursor = decodeCursor(cursor)

        let query = supabase
            .schema("public")
            .from("playlists")
            .select("*")
            .eq("owner_id", req.userId)
            .is("deleted_at", null)
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(pageSize + 1)

        if (decodedCursor) {
            query = query.or(
                `created_at.lt.${decodedCursor.createdAt},and(created_at.eq.${decodedCursor.createdAt},id.lt.${decodedCursor.id})`
            )
        }

        const { data, error } = await query

        if (error) {
            return sendError(res, "PLAYLISTS_FETCH_FAILED", error.message, 500)
        }

        const hasMore = (data?.length ?? 0) > pageSize
        const playlists = hasMore ? data!.slice(0, pageSize) : data ?? []

        const lastPlaylist = playlists[playlists.length - 1]

        const nextCursor = hasMore && lastPlaylist
            ? encodeCursor({
                createdAt: lastPlaylist.created_at,
                id: lastPlaylist.id,
            })
            : null

        return sendSuccess(res, {
            playlists,
            pagination: {
                limit: pageSize,
                hasMore,
                nextCursor,
            },
        })
    })

    app.get('/users/:username/playlists', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { cursor, limit } = req.query as {
            cursor?: string
            limit?: string
        }

        const { data: otherUser, error: otherUserError } = await supabase.schema("public").from("profiles").select("id").eq("username", username).maybeSingle()
        if (otherUserError) return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500)
        if (!otherUser) return sendError(res, "USER_NOT_FOUND", "User not found", 404)

        const pageSize = Math.min(Math.max(Number(limit) || 30, 1), 50)
        const decodedCursor = decodeCursor(cursor)

        let query = supabase
            .schema("public")
            .from("playlists")
            .select("*")
            .eq("owner_id", otherUser.id)
            .is("deleted_at", null)
            .eq("visibility", "public")
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(pageSize + 1)

        if (decodedCursor) {
            query = query.or(
                `created_at.lt.${decodedCursor.createdAt},and(created_at.eq.${decodedCursor.createdAt},id.lt.${decodedCursor.id})`
            )
        }

        const { data, error } = await query

        if (error) {
            return sendError(res, "PLAYLISTS_FETCH_FAILED", error.message, 500)
        }

        const hasMore = (data?.length ?? 0) > pageSize
        const playlists = hasMore ? data!.slice(0, pageSize) : data ?? []

        const lastPlaylist = playlists[playlists.length - 1]

        const nextCursor = hasMore && lastPlaylist
            ? encodeCursor({
                createdAt: lastPlaylist.created_at,
                id: lastPlaylist.id,
            })
            : null

        return sendSuccess(res, {
            playlists,
            pagination: {
                limit: pageSize,
                hasMore,
                nextCursor,
            },
        })
    })

    app.get('/me/playlists/track-membership', { preHandler: app.authenticate }, async (req, res) => {
        const { nicheTrackId } = req.query as { nicheTrackId?: string }

        if (!nicheTrackId) {
            return sendError(res, "INVALID_REQUEST", "nicheTrackId is required", 400)
        }

        const { data, error } = await supabase
            .schema("public")
            .from("playlist_track_memberships")
            .select("playlist_id, playlist_item_id, niche_track_id, created_at")
            .eq("owner_id", req.userId)
            .eq("niche_track_id", nicheTrackId)

        if (error) {
            return sendError(res, "PLAYLIST_MEMBERSHIP_FETCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, {
            memberships: (data ?? []).map((row) => ({
                playlistId: row.playlist_id,
                itemId: row.playlist_item_id,
                nicheTrackId: row.niche_track_id,
                createdAt: row.created_at,
            })),
        })
    })

    app.get('/playlists/:playlistId', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { playlistId } = req.params as { playlistId: string }
        const { cursor, limit } = req.query as {
            cursor?: string
            limit?: string
        }

        const pageSize = Math.min(Math.max(Number(limit) || 30, 1), 50)
        const decodedCursor = decodePlaylistCursor(cursor)

        const { data: playlist, error: playlistError } = await supabase
            .schema("public")
            .from("playlists")
            .select(`
                *,
                owner:profiles!playlists_owner_id_fkey (
                    id,
                    username,
                    display_name,
                    avatar_url,
                    is_verified,
                    verification_type
                )
            `)
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (playlistError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", playlistError.message, 500)
        }

        if (!playlist) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (playlist.visibility === "private" && playlist.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_PRIVATE", "Playlist is private", 403)
        }

        let itemsQuery = supabase
            .schema("public")
            .from("playlist_items")
            .select(PLAYLIST_ITEM_SELECT)
            .eq("playlist_id", playlist.id)
            .is("deleted_at", null)
            .order("sort_key", { ascending: true })
            .order("created_at", { ascending: true })
            .limit(pageSize + 1)

        if (decodedCursor) {
            itemsQuery = itemsQuery.or(
                `sort_key.gt.${decodedCursor.sortKey},and(sort_key.eq.${decodedCursor.sortKey},created_at.gt.${decodedCursor.createdAt})`
            )
        }

        const { data: rawItems, error: itemsError } = await itemsQuery

        if (itemsError) {
            return sendError(res, "PLAYLIST_ITEMS_FETCH_FAILED", itemsError.message, 500)
        }

        const hasMore = (rawItems?.length ?? 0) > pageSize
        const items = hasMore ? rawItems!.slice(0, pageSize) : rawItems ?? []

        const trackIds = items
            .map((item) => item.niche_track_id)
            .filter(Boolean)

        let likedTrackIds = new Set<string>()

        if (req.userId && trackIds.length > 0) {
            const { data: likes, error: likesError } = await supabase
                .schema("public")
                .from("niche_track_likes")
                .select("track_id")
                .eq("liker_id", req.userId)
                .in("track_id", trackIds)

            if (likesError) {
                return sendError(res, "PLAYLIST_VIEWER_CONTEXT_FAILED", likesError.message, 500)
            }

            likedTrackIds = new Set((likes ?? []).map((like) => like.track_id))
        }

        const itemsWithViewerContext = items.map((item) => ({
            ...item,
            track: item.track
                ? {
                    ...item.track,
                    viewerContext: {
                        isLiked: likedTrackIds.has(item.niche_track_id),
                    },
                }
                : null,
        }))

        const lastItem = items[items.length - 1]

        const nextCursor = hasMore && lastItem
            ? encodePlaylistCursor({
                sortKey: lastItem.sort_key,
                createdAt: lastItem.created_at,
            })
            : null

        return sendSuccess(res, {
            playlist: {
                ...playlist,
                items: itemsWithViewerContext,
                pagination: {
                    limit: pageSize,
                    hasMore,
                    nextCursor,
                },
            },
        })
    })

    app.post('/playlists/create', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = createPlaylistSchema.parse(req.body)
        const playlistId = generateRandomId(16)
        const { data, error } = await supabase.schema("public").from("playlists").insert({
            id: playlistId,
            name: parsedBody.name,
            description: parsedBody.description ?? null,
            visibility: parsedBody.visibility,
            owner_id: req.userId,
        }).select("*").single()
        if (error) return sendError(res, "PLAYLIST_CREATE_FAILED", error.message, 500)

        // if has image, return presigned url
        if (parsedBody.has_image) {
            const upload = await getPlaylistImagePresignedUrl(playlistId, parsedBody.format)
            return sendSuccess(res, {
                playlistId,
                upload,
            })
        }

        return sendSuccess(res, {
            playlist: data,
        })

    })

    app.post('/playlists/:playlistId/update', { preHandler: app.authenticate }, async (req, res) => {
        const { playlistId } = req.params as { playlistId: string }
        const parsedBody = updatePlaylistSchema.parse(req.body)

        const { data: existing, error: fetchError } = await supabase
            .schema("public")
            .from("playlists")
            .select("id, owner_id")
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", fetchError.message, 500)
        }

        if (!existing) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (existing.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_FORBIDDEN", "You do not own this playlist", 403)
        }

        const patch: Record<string, unknown> = {}

        if (parsedBody.name !== undefined) {
            patch.name = parsedBody.name
        }
        if (parsedBody.description !== undefined) {
            patch.description = parsedBody.description === null || parsedBody.description.length === 0
                ? null
                : parsedBody.description
        }
        if (parsedBody.visibility !== undefined) {
            patch.visibility = parsedBody.visibility
        }

        if (Object.keys(patch).length === 0 && !parsedBody.has_image) {
            return sendError(res, "INVALID_REQUEST", "No fields to update", 400)
        }

        if (Object.keys(patch).length > 0) {
            patch.updated_at = new Date().toISOString()
        }

        let playlist = existing

        if (Object.keys(patch).length > 0) {
            const { data, error } = await supabase
                .schema("public")
                .from("playlists")
                .update(patch)
                .eq("id", playlistId)
                .eq("owner_id", req.userId)
                .select("*")
                .maybeSingle()

            if (error) {
                return sendError(res, "PLAYLIST_UPDATE_FAILED", error.message, 500)
            }

            if (!data) {
                return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
            }

            playlist = data
        } else {
            const { data, error } = await supabase
                .schema("public")
                .from("playlists")
                .select("*")
                .eq("id", playlistId)
                .eq("owner_id", req.userId)
                .is("deleted_at", null)
                .maybeSingle()

            if (error) {
                return sendError(res, "PLAYLIST_FETCH_FAILED", error.message, 500)
            }

            if (!data) {
                return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
            }

            playlist = data
        }

        if (parsedBody.has_image) {
            const upload = await getPlaylistImagePresignedUrl(playlistId, parsedBody.format)
            return sendSuccess(res, {
                playlist,
                upload,
            })
        }

        return sendSuccess(res, {
            playlist,
        })
    })

    app.post('/playlists/:playlistId/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { playlistId } = req.params as { playlistId: string }

        const { data: existing, error: fetchError } = await supabase
            .schema("public")
            .from("playlists")
            .select("id, owner_id")
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (fetchError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", fetchError.message, 500)
        }

        if (!existing) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (existing.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_FORBIDDEN", "You do not own this playlist", 403)
        }

        const now = new Date().toISOString()
        const { error } = await supabase
            .schema("public")
            .from("playlists")
            .update({
                deleted_at: now,
                updated_at: now,
            })
            .eq("id", playlistId)
            .eq("owner_id", req.userId)
            .is("deleted_at", null)

        if (error) {
            return sendError(res, "PLAYLIST_DELETE_FAILED", error.message, 500)
        }

        return sendSuccess(res, { success: true })
    })

    app.post('/playlists/:playlistId/image', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = z.object({
            image_url: z.url(),
        }).parse(req.body)
        const { data, error } = await supabase.schema("public").from("playlists").update({
            image_url: parsedBody.image_url,
            updated_at: new Date().toISOString(),
        }).eq("id", (req.params as { playlistId: string }).playlistId).eq("owner_id", req.userId).select("*").maybeSingle()
        if (error) return sendError(res, "PLAYLIST_IMAGE_UPDATE_FAILED", error.message, 500)
        return sendSuccess(res, { playlist: data })
    })

    app.post('/playlists/:playlistId/items/add', { preHandler: app.authenticate }, async (req, res) => {
        const { playlistId } = req.params as { playlistId: string }
        const parsedBody = z.object({
            nicheTrackId: z.string(),
        }).parse(req.body)

        const { data: playlist, error: playlistError } = await supabase
            .schema("public")
            .from("playlists")
            .select("id, owner_id, deleted_at")
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (playlistError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", playlistError.message, 500)
        }

        if (!playlist) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (playlist.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_FORBIDDEN", "You do not own this playlist", 403)
        }

        const { data: item, error } = await supabase.schema("public").rpc("add_playlist_item", {
            p_id: req.userId,
            item_id: generateRandomId(16),
            playlist_id_arg: playlistId,
            added_by_id_arg: req.userId,
            niche_track_id_arg: parsedBody.nicheTrackId,
        })

        if (error) {
            return sendError(res, "PLAYLIST_ITEM_ADD_FAILED", error.message, 500)
        }

        const insertedItem = Array.isArray(item) ? item[0] : item
        if (!insertedItem?.id) {
            return sendError(res, "PLAYLIST_ITEM_ADD_FAILED", "Failed to create playlist item", 500)
        }

        const { data: fullItem, error: fullItemError } = await supabase
            .schema("public")
            .from("playlist_items")
            .select(PLAYLIST_ITEM_SELECT)
            .eq("id", insertedItem.id)
            .is("deleted_at", null)
            .maybeSingle()

        if (fullItemError) {
            return sendError(res, "PLAYLIST_ITEM_ADD_FAILED", fullItemError.message, 500)
        }

        if (!fullItem) {
            return sendError(res, "PLAYLIST_ITEM_ADD_FAILED", "Failed to load playlist item", 500)
        }

        let isLiked = false
        if (req.userId && fullItem.niche_track_id) {
            const { data: like } = await supabase
                .schema("public")
                .from("niche_track_likes")
                .select("track_id")
                .eq("liker_id", req.userId)
                .eq("track_id", fullItem.niche_track_id)
                .maybeSingle()

            isLiked = !!like
        }

        const itemWithViewerContext = {
            ...fullItem,
            track: fullItem.track
                ? {
                    ...fullItem.track,
                    viewerContext: {
                        isLiked,
                    },
                }
                : null,
        }

        return sendSuccess(res, { item: itemWithViewerContext })
    })

    app.post("/playlists/:playlistId/items/:itemId/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { playlistId, itemId } = req.params as {
            playlistId: string
            itemId: string
        }

        const { data: playlist, error: playlistError } = await supabase
            .schema("public")
            .from("playlists")
            .select("id, owner_id")
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (playlistError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", playlistError.message, 500)
        }

        if (!playlist) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (playlist.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_FORBIDDEN", "You do not own this playlist", 403)
        }

        const { error: removeError } = await supabase
            .schema("public")
            .rpc("remove_playlist_item", {
                playlist_item_id_arg: itemId,
            })

        if (removeError) {
            return sendError(res, "PLAYLIST_ITEM_REMOVE_FAILED", removeError.message, 500)
        }

        return sendSuccess(res, { success: true })
    })

    app.post("/playlists/:playlistId/items/:itemId/move", { preHandler: app.authenticate }, async (req, res) => {
        const { playlistId, itemId } = req.params as {
            playlistId: string
            itemId: string
        }

        const parsedBody = z.object({
            after_sort_key: z.number().nullable().optional(),
            before_sort_key: z.number().nullable().optional(),
        }).parse(req.body)

        const { data: playlist, error: playlistError } = await supabase
            .schema("public")
            .from("playlists")
            .select("id, owner_id")
            .eq("id", playlistId)
            .is("deleted_at", null)
            .maybeSingle()

        if (playlistError) {
            return sendError(res, "PLAYLIST_FETCH_FAILED", playlistError.message, 500)
        }

        if (!playlist) {
            return sendError(res, "PLAYLIST_NOT_FOUND", "Playlist not found", 404)
        }

        if (playlist.owner_id !== req.userId) {
            return sendError(res, "PLAYLIST_FORBIDDEN", "You do not own this playlist", 403)
        }

        const { data: item, error } = await supabase.schema("public").rpc("move_playlist_item", {
            playlist_item_id_arg: itemId,
            after_sort_key: parsedBody.after_sort_key ?? null,
            before_sort_key: parsedBody.before_sort_key ?? null,
        })

        if (error) {
            return sendError(res, "PLAYLIST_ITEM_MOVE_FAILED", error.message, 500)
        }

        return sendSuccess(res, { item })
    })



}

export default playlistsRoutes