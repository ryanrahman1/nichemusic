import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { updateProfileSchema } from "./schemas.js"
import { getAvatarPresignedUrl } from "../../lib/image.js"
import { checkFollowing } from "./helpers.js"


const profileRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me', { preHandler: [app.authenticate] }, async (req, res) => {
        const userId = req.userId

        const { data, error } = await supabase.schema('public').from('profiles').select('*').eq('id', userId).single()

        if (error) {
            return res.status(500).send({ error: error.message })
        }

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    ...data
                }
            }
        })
    })

    app.patch('/me', { preHandler: app.authenticate }, async (req, res) => {

        const parsedBody = updateProfileSchema.parse(req.body)

        const { data, error } = await supabase.schema('public').from('profiles').update({
            username: parsedBody.username,
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

        let avatarUrl: string | undefined = undefined
        let uploadUrl: string | undefined = undefined
        let objectKey: string | undefined = undefined
        let contentType: string | undefined = undefined
        let maxBytes: number | undefined = undefined
        if (parsedBody.update_avatar) {
            const upload = await getAvatarPresignedUrl(req.userId)
            uploadUrl = upload.uploadUrl
            avatarUrl = upload.publicUrl
            objectKey = upload.objectKey
            contentType = upload.contentType
            maxBytes = upload.maxBytes
        }

        if (error) {
            return res.status(500).send({ error: error.message })
        }

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    id: req.userId,
                },
                avatarUpload: parsedBody.update_avatar ? {
                    uploadUrl: uploadUrl,
                    avatarUrl: avatarUrl,
                    objectKey: objectKey,
                    contentType: contentType,
                    maxBytes: maxBytes,
                } : null,
            }
        })
    })

    // others
    app.get('/users/:username', { preHandler: app.authenticate }, async (req, res) => { // TODO: add optional authentication; doesn't matter for now cause its only ios, and ios must be signed in, but once web then yeah
        const { username } = req.params as { username: string }

        const { data, error } = await supabase.schema('public').from('profiles').select('*, user_status(*)').eq('username', username).single()

        if (error) {
            return res.status(500).send({ error: error.message })
        }

        if (!data) {
            return res.status(404).send({ error: "User not found" })
        }

        if (data?.is_private) {
            const isFollowing = await checkFollowing(req.userId, data.id) // not friends, just if the user is folliwing (since for private its requests anyway)
            if (!isFollowing) {
                return res.status(200).send({ // return public profile; no sensitive info, and also new tag that says you are not friends
                    success: true,
                    result: {
                        user: {
                            id: data.id,
                            username: data.username,
                            avatar_url: data.avatar_url,
                            display_name: data.display_name
                        },
                        isFollowing: false,
                    }
                })
            }
        }

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    ...data
                }
            }
        })

    })

    app.post('/users/:username/follow', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }

        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id, is_private').eq('username', username).maybeSingle()

        if (otherUser?.is_private) {
            // send follow request, and 200
            const { data, error } = await supabase.schema('public').from('follow_requests').insert({
                follower_id: req.userId,
                following_id: otherUser?.id,
                status: 'sent'
            })
            if (error) { return res.status(500).send({ error: error.message }) }
            return res.status(200).send({
                success: true
            })
        }

        const { data, error } = await supabase.schema('public').from('follows').insert({
            follower_id: req.userId,
            following_id: otherUser?.id,
        })

        // check if mutual follow
        const { data: mutualFollow } = await supabase.schema('public').from('follows').select('id').eq('follower_id', otherUser?.id).eq('following_id', req.userId).maybeSingle()
        if (mutualFollow) {
            // create friendship
            const { data: friendship, error: friendshipError } = await supabase.schema('public').from('friends').insert({
                user_a_id: req.userId,
                user_b_id: otherUser?.id,
            })
            if (friendshipError) { return res.status(500).send({ error: friendshipError.message }) }
            if (!friendship) { return res.status(500).send({ error: "Failed to create friendship" }) }
        }

        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({
            success: true,
            result: {
                follow: {
                    id: otherUser?.id,
                }
            }
        })
    })

    app.post('/users/:username/unfollow', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('follows').delete().eq('follower_id', req.userId).eq('following_id', otherUser?.id)
        // friendship deletion (since must be mutual follows)
        const { data: friendship, error: friendshipError } = await supabase.schema('public').from('friends').delete().eq('user_a_id', req.userId).eq('user_b_id', otherUser?.id)

        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({
            success: true,
        })
    })

    app.post('/users/:username/block', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('blocks').insert({
            blocker_id: req.userId,
            blocked_id: otherUser?.id,
        })
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({
            success: true,
        })
        // use triggers to delete friendship and follow relationships, as to not have to do it manually
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

    app.get('/me/followers', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follows').select('following_id').eq('follower_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { followers: data.map((follower) => follower.following_id) } })
    })

    app.get('/users/:username/followers', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', otherUser?.id)
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { followers: data.map((follower) => follower.follower_id) } })
    })

    app.get('/me/following', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { following: data.map((following) => following.follower_id) } })
    })

    app.get('/users/:username/following', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('follows').select('follower_id').eq('following_id', otherUser?.id)
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { following: data.map((following) => following.follower_id) } })
    })

    app.get('/me/blocks', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('blocks').select('blocked_id').eq('blocker_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { blocks: data.map((block) => block.blocked_id) } })
    })

    app.get('/users/:username/blocks', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        const { data, error } = await supabase.schema('public').from('blocks').select('blocked_id').eq('blocker_id', otherUser?.id)
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { blocks: data.map((block) => block.blocked_id) } })
    })

    app.get('/me/friends', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('friends').select('user_b_id').eq('user_a_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { friends: data.map((friend) => friend.user_b_id) } })
    })

    app.get('/users/:username/friends', { preHandler: app.authenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { data: otherUser, error: otherUserError } = await supabase.schema('public').from('profiles').select('id').eq('username', username).maybeSingle()
        // maybe implement a check to see if the user is friends with the other user; this is just to avoid returning all friends for everyone? but not needed for now i guess
        const { data, error } = await supabase.schema('public').from('friends').select('user_b_id').eq('user_a_id', otherUser?.id)
        if (otherUserError) { return res.status(500).send({ error: otherUserError.message }) }
        if (!otherUser) { return res.status(404).send({ error: "User not found" }) }
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { friends: data.map((friend) => friend.user_b_id) } })
    })

    app.get('/me/follow_requests', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('public').from('follow_requests').select('follower_id, profiles(*), status').eq('following_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: { followRequests: data.map((followRequest) => followRequest.follower_id) } })
    })

    app.post('/me/follows/:userId/accept', { preHandler: app.authenticate }, async (req, res) => {
        const { userId } = req.params as { userId: string }
        const { data, error } = await supabase.schema('public').from('follow_requests').update({
            status: 'accepted'
        }).eq('follower_id', userId).eq('following_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        const { data: follow, error: followError } = await supabase.schema('public').from('follows').insert({
            follower_id: userId,
            following_id: req.userId,
        })
        const { data: mutualFollow } = await supabase.schema('public').from('follows').select('id').eq('follower_id', userId).eq('following_id', req.userId).maybeSingle()
        if (mutualFollow) {
            // create friendship
            const { data: friendship, error: friendshipError } = await supabase.schema('public').from('friends').insert({
                user_a_id: req.userId,
                user_b_id: userId,
            })
            if (friendshipError) { return res.status(500).send({ error: friendshipError.message }) }
            if (!friendship) { return res.status(500).send({ error: "Failed to create friendship" }) }
        }
        if (followError) { return res.status(500).send({ error: followError.message }) }
        if (!follow) { return res.status(500).send({ error: "Failed to create follow relationship" }) }
        return res.status(200).send({ success: true })
    })

    app.post('/me/follows/:userId/reject', { preHandler: app.authenticate }, async (req, res) => {
        const { userId } = req.params as { userId: string }
        const { data, error } = await supabase.schema('public').from('follow_requests').delete().eq('follower_id', userId).eq('following_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true })
    })
    
}

export default profileRoutes