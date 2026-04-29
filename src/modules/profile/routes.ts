import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { updateProfileSchema, upsertStatusSchema } from "./schemas.js"
import { getAvatarPresignedUrl } from "../../lib/image.js"
import { sendError, sendSuccess } from "../../global/response.js"
import {
    sendFollowAcceptNotification,
    sendFollowNotification,
    sendFollowRequestNotification,
} from "../../lib/notifications.js"
import {
    PROFILE_DETAIL_SELECT,
    FRIEND_ACTIVITY_PROFILE_SELECT,
    FRIEND_ACTIVITY_USER_STATUS_SELECT,
    buildFriendActivitiesFromFriendData,
    getViewerProfileContext,
    type ViewerProfileContext,
    profilesForUserIdsOrdered,
} from "./helpers.js"



const profileRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me', { preHandler: [app.authenticate] }, async (req, res) => {
        const userId = req.userId

        const { data, error } = await supabase
            .schema("public")
            .from("profiles")
            .select(PROFILE_DETAIL_SELECT)
            .eq("id", userId)
            .single()

        if (error) {
            return sendError(res, "PROFILE_FETCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, { user: data })
    })

    app.post('/me/update', { preHandler: app.authenticate }, async (req, res) => {

        const parsedBody = updateProfileSchema.parse(req.body)

        const patch: Record<string, unknown> = {}
        if (parsedBody.displayName !== undefined) {
            patch.display_name = parsedBody.displayName
        }
        if (parsedBody.bio !== undefined) {
            patch.bio = parsedBody.bio
        }
        if (parsedBody.location_name !== undefined) {
            patch.location_name = parsedBody.location_name
        }
        if (parsedBody.is_private !== undefined) {
            patch.is_private = parsedBody.is_private
        }
        if (parsedBody.profile_song_id !== undefined) {
            patch.profile_song_id = parsedBody.profile_song_id
        }
        if (parsedBody.allow_messages_from !== undefined) {
            patch.allow_messages_from = parsedBody.allow_messages_from
        }
        if (parsedBody.allow_group_invites !== undefined) {
            patch.allow_group_invites = parsedBody.allow_group_invites
        }
        if (parsedBody.spotify_account !== undefined) {
            patch.spotify_account = parsedBody.spotify_account
        }
        if (parsedBody.instagram_handle !== undefined) {
            patch.instagram_handle = parsedBody.instagram_handle
        }
        if (parsedBody.tiktok_handle !== undefined) {
            patch.tiktok_handle = parsedBody.tiktok_handle
        }

        let profileUpdateError: { message: string } | null = null
        if (Object.keys(patch).length > 0) {
            const { error } = await supabase
                .schema("public")
                .from("profiles")
                .update(patch)
                .eq("id", req.userId)
            if (error) {
                profileUpdateError = error
            }
        }

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

        if (profileUpdateError) {
            return sendError(res, "PROFILE_UPDATE_FAILED", profileUpdateError.message, 500)
        }

        return sendSuccess(res, { user: { id: req.userId }, avatarUpload })
    })

    // others
    app.get("/users/:username", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data, error } = await supabase
            .schema("public")
            .from("profiles")
            .select(PROFILE_DETAIL_SELECT)
            .eq("username", username)
            .single()

        if (error) {
            return sendError(res, "PROFILE_FETCH_FAILED", error.message, 500)
        }

        if (!data) {
            return sendError(res, "USER_NOT_FOUND", "User not found", 404)
        }

        let viewer: ViewerProfileContext | null = null
        if (req.userId !== undefined) {
            try {
                viewer = await getViewerProfileContext(req.userId, data.id)
            } catch (e) {
                const message = e instanceof Error ? e.message : "Viewer context failed"
                return sendError(res, "VIEWER_CONTEXT_FAILED", message, 500)
            }
        }

        const showPrivateTeaser =
            data.is_private === true &&
            viewer?.isSelf !== true &&
            viewer?.isFollowing !== true

        if (showPrivateTeaser) {
            return sendSuccess(res, {
                user: {
                    id: data.id,
                    username: data.username,
                    avatar_url: data.avatar_url,
                    display_name: data.display_name,
                    is_private: data.is_private,
                    followers_count: data.followers_count ?? 0,
                    following_count: data.following_count ?? 0,
                    posts_count: data.posts_count ?? 0,
                },
                viewer,
            })
        }

        return sendSuccess(res, { user: data, viewer })
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

        if (data.kind === "request_sent") {
            void sendFollowRequestNotification(req.userId, otherUser.id).catch((error) => {
                req.log.warn({ err: error }, "follow request notification failed")
            })
        } else {
            void sendFollowNotification(req.userId, otherUser.id).catch((error) => {
                req.log.warn({ err: error }, "follow notification failed")
            })
        }

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

        const ids = (data ?? []).map((row) => row.follower_id)
        try {
            const followers = await profilesForUserIdsOrdered(ids)
            return sendSuccess(res, { followers })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load followers"
            return sendError(res, "FOLLOWERS_FETCH_FAILED", message, 500)
        }
    })

    app.get("/users/:username/followers", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase
            .schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }

        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', otherUser.id)

        if (error) { return sendError(res, "FOLLOWERS_FETCH_FAILED", error.message, 500) }

        const ids = (data ?? []).map((row) => row.follower_id)
        try {
            const followers = await profilesForUserIdsOrdered(ids)
            return sendSuccess(res, { followers })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load followers"
            return sendError(res, "FOLLOWERS_FETCH_FAILED", message, 500)
        }
    })

    app.get("/me/following", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follows').select('following_id').eq('follower_id', req.userId)

        if (error) { return sendError(res, "FOLLOWING_FETCH_FAILED", error.message, 500) }

        const ids = (data ?? []).map((row) => row.following_id)
        try {
            const following = await profilesForUserIdsOrdered(ids)
            return sendSuccess(res, { following })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load following"
            return sendError(res, "FOLLOWING_FETCH_FAILED", message, 500)
        }
    })

    app.get("/users/:username/following", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase
            .schema('public').from('profiles').select('id').eq('username', username).maybeSingle()

        if (otherUserError) { return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500) }
        if (!otherUser) { return sendError(res, "USER_NOT_FOUND", "User not found", 404) }

        const { data, error } = await supabase.schema('public').from('follows').select('following_id').eq('follower_id', otherUser.id)
        if (error) { return sendError(res, "FOLLOWING_FETCH_FAILED", error.message, 500) }

        const ids = (data ?? []).map((row) => row.following_id)
        try {
            const following = await profilesForUserIdsOrdered(ids)
            return sendSuccess(res, { following })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load following"
            return sendError(res, "FOLLOWING_FETCH_FAILED", message, 500)
        }
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
        const ids = data.map((row) => row.user_a_id === req.userId ? row.user_b_id : row.user_a_id)
        try {
            const friends = await profilesForUserIdsOrdered(ids)
            return sendSuccess(res, { friends })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load friends"
            return sendError(res, "FRIENDS_FETCH_FAILED", message, 500)
        }
    })

    app.post("/me/status", { preHandler: app.authenticate }, async (req, res) => {
        const parsed = upsertStatusSchema.parse(req.body)
        const nowIso = new Date().toISOString()
        const expiresIso = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString()

        const { error: clearError } = await supabase
            .schema("public")
            .from("user_status")
            .delete()
            .eq("profile_id", req.userId)
        if (clearError) {
            return sendError(res, "STATUS_UPSERT_FAILED", clearError.message, 500)
        }

        const { error } = await supabase
            .schema("public")
            .from("user_status")
            .insert({
                profile_id: req.userId,
                text: parsed.text ?? null,
                track_id: parsed.track_id ?? null,
                created_at: nowIso,
                expires_at: expiresIso,
            })
        if (error) {
            return sendError(res, "STATUS_UPSERT_FAILED", error.message, 500)
        }
        return sendSuccess(res, { ok: true })
    })

    app.delete("/me/status", { preHandler: app.authenticate }, async (req, res) => {
        const { error } = await supabase
            .schema("public")
            .from("user_status")
            .delete()
            .eq("profile_id", req.userId)
        if (error) {
            return sendError(res, "STATUS_DELETE_FAILED", error.message, 500)
        }
        return sendSuccess(res, { ok: true })
    })

    /**
     * Friend activity rail: active `user_status` (before `expires_at`) first, else `profile_song`.
     * Loads statuses in a separate query so rows and `track` embeds resolve reliably.
     */
    app.get("/me/friends/activity", { preHandler: app.authenticate }, async (req, res) => {
        const { data: friendRows, error: friendsError } = await supabase
            .schema("public")
            .from("friends")
            .select("user_a_id, user_b_id")
            .or(`user_a_id.eq.${req.userId},user_b_id.eq.${req.userId}`)

        if (friendsError) {
            return sendError(res, "FRIENDS_ACTIVITY_FETCH_FAILED", friendsError.message, 500)
        }

        const friendIds = (friendRows ?? []).map((row) =>
            row.user_a_id === req.userId ? row.user_b_id : row.user_a_id
        )

        if (friendIds.length === 0) {
            return sendSuccess(res, { activities: [] })
        }

        const [profilesRes, statusRes] = await Promise.all([
            supabase
                .schema("public")
                .from("profiles")
                .select(FRIEND_ACTIVITY_PROFILE_SELECT)
                .in("id", friendIds),
            supabase
                .schema("public")
                .from("user_status")
                .select(FRIEND_ACTIVITY_USER_STATUS_SELECT)
                .in("profile_id", friendIds),
        ])

        if (profilesRes.error) {
            return sendError(res, "FRIENDS_ACTIVITY_FETCH_FAILED", profilesRes.error.message, 500)
        }
        if (statusRes.error) {
            return sendError(res, "FRIENDS_ACTIVITY_FETCH_FAILED", statusRes.error.message, 500)
        }

        const activities = buildFriendActivitiesFromFriendData(
            profilesRes.data ?? [],
            statusRes.data ?? []
        )
        return sendSuccess(res, { activities })
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

        void sendFollowAcceptNotification(req.userId, userId).catch((notifyError) => {
            req.log.warn({ err: notifyError }, "follow accept notification failed")
        })

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