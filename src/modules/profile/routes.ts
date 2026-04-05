import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { updateProfileSchema } from "./schemas.js"
import { getAvatarPresignedUrl } from "../../lib/image.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { sendFollowNotification, sendFollowRequestNotification } from "../../lib/notifications.js"



const profileRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me', { preHandler: [app.authenticate] }, async (req, res) => {
        const userId = req.userId

        const { data, error } = await supabase.schema('public').from('profiles').select('*, profile_song:tracks!profiles_profile_song_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))').eq('id', userId).single()

        if (error) {
            return sendError(res, "PROFILE_FETCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, { user: data })
    })

    app.patch('/me', { preHandler: app.authenticate }, async (req, res) => {

        const parsedBody = updateProfileSchema.parse(req.body)

        const { data, error } = await supabase.schema('public').from('profiles').update({
            display_name: parsedBody.displayName,
            bio: parsedBody.bio,
            location_name: parsedBody.location_name,
            is_private: parsedBody.is_private,
            profile_song_id: parsedBody.profile_song_id,
            allow_messages_from: parsedBody.allow_messages_from,
            allow_group_invites: parsedBody.allow_group_invites,
            spotify_account: parsedBody.spotify_account,
            instagram_handle: parsedBody.instagram_handle,
            tiktok_handle: parsedBody.tiktok_handle,
        }).eq('id', req.userId)

        let avatarUpload: null | {
            uploadUrl: string
            avatarUrl: string
            objectKey: string
            contentType: string
            maxBytes: number
        } = null
        if (parsedBody.update_avatar) {
            const upload = await getAvatarPresignedUrl(req.userId)
            avatarUpload = {
                uploadUrl: upload.uploadUrl,
                avatarUrl: upload.publicUrl,
                objectKey: upload.objectKey,
                contentType: upload.contentType,
                maxBytes: upload.maxBytes,
            }
        }

        if (error) {
            return sendError(res, "PROFILE_UPDATE_FAILED", error.message, 500)
        }

        return sendSuccess(res, { user: { id: req.userId }, avatarUpload })
    })

    // others
    app.get('/users/:username', { preHandler: app.optionalAuthenticate }, async (req, res) => { // TODO: add optional authentication; doesn't matter for now cause its only ios, and ios must be signed in, but once web then yeah
        const { username } = req.params as { username: string }

        const { data, error } = await supabase.schema('public').from('profiles').select('*, user_status(*), profile_song:tracks!profiles_profile_song_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))').eq('username', username).single()

        if (error) {
            return sendError(res, "PROFILE_FETCH_FAILED", error.message, 500)
        }

        if (!data) {
            return sendError(res, "USER_NOT_FOUND", "User not found", 404)
        }

        if (data.is_private && data.id !== req.userId && req.userId !== undefined) {
            const { data: followRow, error: followError } = await supabase
                .schema("public")
                .from("follows")
                .select("follower_id")
                .eq("follower_id", req.userId)
                .eq("following_id", data.id)
                .maybeSingle()

            if (followError) {
                return sendError(res, "FOLLOW_CHECK_FAILED", followError.message, 500)
            }

            if (!followRow) {
                return sendSuccess(res, {
                    user: {
                        id: data.id,
                        username: data.username,
                        avatar_url: data.avatar_url,
                        display_name: data.display_name,
                        is_private: data.is_private,
                    },
                    isFollowing: false,
                })
            }
        }

        return sendSuccess(res, { user: data })

    })

    app.post('/users/:username/follow', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "PROFILE_FETCH_FAILED", otherUserError.message, 500) }
        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        if (otherUser.id === req.userId) {
            return sendError(res, "FOLLOW_SELF", "You cannot follow yourself", 400)
        }


        const { data, error } = await supabase.rpc("follow_user", {
            actor_id: req.userId,
            target_id: otherUser.id,
        })

        if (error) { return sendError(res, "FOLLOW_FAILED", error.message, 400) }

        /**
        if (data.kind === "request_sent") {
            await sendFollowRequestNotification(req.userId, otherUser.id)
        } else {
            await sendFollowNotification(req.userId, otherUser.id)
        }
        */

        return sendSuccess(res, { follow: data })
    })

    app.post("/users/:username/unfollow", { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }

        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        const { data, error } = await supabase.rpc("unfollow_user", {
            actor_id: req.userId,
            target_id: otherUser.id,
        })

        if (error) { return sendError(res, "UNFOLLOW_FAILED", error.message, 400) }

        return sendSuccess(res, { unfollow: data })
    })

    app.post("/users/:username/block", { preHandler: [app.authenticate] }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }

        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        if (otherUser.id === req.userId) { return sendError(res, "INVALID_BLOCK", "You cannot block yourself", 400) }

        const { data, error } = await supabase.rpc("block_user", {
            actor_id: req.userId,
            target_id: otherUser.id,
        })

        if (error) { return sendError(res, "BLOCK_FAILED", error.message, 400) }

        return sendSuccess(res, { block: data })
    })

    app.post('/users/:username/unblock', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('blocks').delete().eq('blocker_id', req.userId).eq('blocked_id', otherUser?.id)
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true })
    })

    app.get("/me/followers", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', req.userId)

        if (error) {
            return sendError(res, "FOLLOWERS_FETCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, {
            followers: data.map((row) => row.follower_id),
        })
    })

    app.get("/users/:username/followers", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase
            .schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }

        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', otherUser.id)

        if (error) { return sendError(res, "FOLLOWERS_FETCH_FAILED", error.message, 500) }

        return sendSuccess(res, {
            followers: data.map((row) => row.follower_id),
        })
    })

    app.get("/me/following", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follows').select('following_id').eq('follower_id', req.userId)

        if (error) { return sendError(res, "FOLLOWING_FETCH_FAILED", error.message, 500) }

        return sendSuccess(res, {
            following: data.map((row) => row.following_id),
        })
    })

    app.get("/users/:username/following", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase
            .schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }
        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        const { data, error } = await supabase.schema('public').from('follows').select('following_id').eq('follower_id', otherUser.id)
        if (error) { return sendError(res, "FOLLOWING_FETCH_FAILED", error.message, 500) }

        return sendSuccess(res, {
            following: data.map((row) => row.following_id),
        })
    })

    app.get("/me/blocks", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase
            .schema('public').from('blocks').select('blocked_id').eq('blocker_id', req.userId)
        if (error) { return sendError(res, "BLOCKS_FETCH_FAILED", error.message, 500) }
        return sendSuccess(res, { blocks: data.map((row) => row.blocked_id) })
    })

    app.get("/me/friends", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('friends').select('user_a_id, user_b_id').or(`user_a_id.eq.${req.userId},user_b_id.eq.${req.userId}`)
        if (error) { return sendError(res, "FRIENDS_FETCH_FAILED", error.message, 500) }
        return sendSuccess(res, { friends: data.map((row) => row.user_a_id === req.userId ? row.user_b_id : row.user_a_id) })
    })
    
    app.get("/me/follow_requests", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follow_requests').select('follower_id, status').eq('following_id', req.userId).eq('status', 'sent')

        if (error) { return sendError(res, "FOLLOW_REQUESTS_FETCH_FAILED", error.message, 500) }
        return sendSuccess(res, { followRequests: data })
    })

    app.post("/me/follows/:userId/accept", { preHandler: app.authenticate }, async (req, res) => {
        const { userId } = req.params as { userId: string }

        const { data, error } = await supabase.rpc("accept_follow_request", {
            actor_id: req.userId,
            requester_id: userId,
        })

        if (error) {
            return sendError(res, "FOLLOW_REQUEST_ACCEPT_FAILED", error.message, 400)
        }

        return sendSuccess(res, { accept: data })
    })

    app.post("/me/follows/:userId/reject", { preHandler: app.authenticate }, async (req, res) => {
        const { userId } = req.params as { userId: string }

        const { data, error } = await supabase.rpc("reject_follow_request", { actor_id: req.userId, requester_id: userId })
        if (error) { return sendError(res, "FOLLOW_REQUEST_REJECT_FAILED", error.message, 400) }
        return sendSuccess(res, { reject: data })
    })

}

export default profileRoutes