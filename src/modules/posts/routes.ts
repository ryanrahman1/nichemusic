import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { presignPostUploadSchema, createPostSchema, updatePostSchema, listCommentsQuerySchema, createCommentSchema, postListQuerySchema } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js" // placeholder
import { getPostMediaPresignedUrl, getPostVideoPresignedUrl } from "../../lib/image.js"
import {
    sendCommentLikeNotification,
    sendCommentReplyNotification,
    sendPostCommentNotification,
    sendPostCreateFanout,
    sendPostLikeNotification,
    sendPostRepostNotification,
} from "../../lib/notifications.js"
import { addViewerToComments, buildCommentContent, cleanPostForInsert, cleanPostForUpdate, decodeCommentCursor, encodeCommentCursor, getPostViewerContextMap } from "./helpers.js"

type PostInteractionQuery = {
    cursorCreatedAt?: string
    cursorUserId?: string
    limit: number
}

function parseInteractionQuery(raw: unknown): PostInteractionQuery {
    const q = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>
    const cursorCreatedAt =
        typeof q.cursorCreatedAt === "string" ? q.cursorCreatedAt : undefined
    const cursorUserId =
        typeof q.cursorUserId === "string" ? q.cursorUserId : undefined
    const parsedLimit =
        typeof q.limit === "string" ? Number(q.limit) : typeof q.limit === "number" ? q.limit : 20
    const limit = Number.isFinite(parsedLimit)
        ? Math.min(50, Math.max(1, Math.floor(parsedLimit)))
        : 20
    const out: PostInteractionQuery = { limit }
    if (cursorCreatedAt !== undefined) out.cursorCreatedAt = cursorCreatedAt
    if (cursorUserId !== undefined) out.cursorUserId = cursorUserId
    return out
}

async function ensureCanViewPost(postId: string, userId: string) {
    const { data: post, error } = await supabase
        .schema("public")
        .from("posts")
        .select("id, owner_id, visibility, group_id")
        .eq("id", postId)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!post) throw new Error("Post not found")

    const isOwner = post.owner_id === userId
    if (post.visibility === "private" && !isOwner) {
        throw new Error("Post is private")
    }
    if (post.visibility === "group" && !isOwner) {
        const { data: member, error: memberError } = await supabase
            .schema("public")
            .from("group_members")
            .select("user_id")
            .eq("user_id", userId)
            .eq("group_id", post.group_id)
            .maybeSingle()
        if (memberError) throw new Error(memberError.message)
        if (!member) throw new Error("User is not in group")
    }
}

const postsRoutes: FastifyPluginAsync = async (app) => {

    app.get('/posts/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data, error } = await supabase
            .schema("public")
            .from("posts")
            .select(`
            *,
            owner:profiles!posts_owner_id_fkey(id, username, avatar_url),
            group:groups!posts_group_id_fkey(id, name), track:tracks!posts_track_id_fkey(id, source, source_id, name, artwork_url, preview_url, artist:artists!tracks_artist_id_fkey(id, name))
          `)
            .eq("id", id)
            .single()

        if (error) return sendError(res, "POST_FETCH_FAILED", error.message, 500)

        const isOwner = !!req.userId && data.owner_id === req.userId

        if (data.visibility === "private" && !isOwner) {
            return sendError(res, "POST_FETCH_FAILED", "Post is private", 403)
        }

        if (data.visibility === "group" && !isOwner) {
            if (!req.userId) {
                return sendError(res, "POST_FETCH_FAILED", "Post is group-only", 403)
            }

            const { data: groupData, error: groupError } = await supabase
                .schema("public")
                .from("group_members")
                .select("user_id")
                .eq("user_id", req.userId)
                .eq("group_id", data.group_id)
                .maybeSingle()

            if (groupError) return sendError(res, "POST_FETCH_FAILED", groupError.message, 500)
            if (!groupData) return sendError(res, "POST_FETCH_FAILED", "User is not in group", 403)
        }

        let isLiked = false
        let isReposted = false

        if (req.userId) {
            const [{ data: likeRow }, { data: repostRow }] = await Promise.all([
                supabase
                    .schema("public")
                    .from("post_likes")
                    .select("liker_id")
                    .eq("post_id", id)
                    .eq("liker_id", req.userId)
                    .maybeSingle(),
                supabase
                    .schema("public")
                    .from("post_reposts")
                    .select("reposter_id")
                    .eq("post_id", id)
                    .eq("reposter_id", req.userId)
                    .maybeSingle(),
            ])

            isLiked = !!likeRow
            isReposted = !!repostRow
        }

        return sendSuccess(res, {
            post: data,
            viewer: {
                is_owner: isOwner,
                is_liked: isLiked,
                is_reposted: isReposted,
            }
        })
    })

    app.post('/posts/:id/like', { preHandler: app.authenticate }, async (req, res) => {

        const { id } = req.params as { id: string }
        const { data, error } = await supabase.schema("public").from("posts").select("*").eq("id", id).single()

        // visibility check -- if private, shouldn't be able to like. if group, must be in group to like.

        if (error) return sendError(res, "POST_FETCH_FAILED", error.message, 500)
        if (data.visibility == "private") return sendError(res, "POST_FETCH_FAILED", "Post is private", 403)
        // check if group only; then see if user is in group
        if (data.visibility == "group") {
            const { data: group_data, error } = await supabase.schema("public").from("group_members").select("*").eq("user_id", req.userId).eq("group_id", data.group_id).single()
            if (error) return sendError(res, "POST_FETCH_FAILED", error.message, 500)
            if (!group_data) return sendError(res, "POST_FETCH_FAILED", "User is not in group", 403)
        }

        const { data: like_data, error: like_error } = await supabase.schema("public").rpc("like_post", {
            actor_id: req.userId,
            target_post_id: id,
        })

        if (like_error) return sendError(res, "POST_LIKE_FAILED", like_error.message, 500)

        void sendPostLikeNotification(req.userId, data.owner_id, id).catch((notifyError) => {
            req.log.warn({ err: notifyError }, "post like notification failed")
        })

        return sendSuccess(res, { message: "Post liked successfully", like_data: like_data })

    })

    app.post('/posts/:id/unlike', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        // no need to check visibility -- user can't even like if its private or group so its ok

        const { data: unlike_data, error: unlike_error } = await supabase.schema("public").rpc("unlike_post", {
            actor_id: req.userId,
            target_post_id: id,
        })

        if (unlike_error) return sendError(res, "POST_UNLIKE_FAILED", unlike_error.message, 500)
        return sendSuccess(res, { message: "Post unliked successfully", unlike_data: unlike_data })
    })

    app.post('/posts/:id/repost', { preHandler: app.authenticate }, async (req, res) => {

        const { id } = req.params as { id: string }
        const { data, error } = await supabase.schema("public").from("posts").select("*").eq("id", id).single()

        // visibility check -- if private, shouldn't be able to repost. if group, must be in group to repost.

        if (error) return sendError(res, "POST_FETCH_FAILED", error.message, 500)
        if (data.visibility == "private") return sendError(res, "POST_FETCH_FAILED", "Post is private", 403)
        // check if group only; then see if user is in group
        if (data.visibility == "group") {
            const { data: group_data, error } = await supabase.schema("public").from("group_members").select("*").eq("user_id", req.userId).eq("group_id", data.group_id).single()
            if (error) return sendError(res, "POST_FETCH_FAILED", error.message, 500)
            if (!group_data) return sendError(res, "POST_FETCH_FAILED", "User is not in group", 403)
        }

        const { data: repost_data, error: repost_error } = await supabase.schema("public").rpc("repost_post", {
            actor_id: req.userId,
            target_post_id: id,
        })

        if (repost_error) return sendError(res, "POST_LIKE_FAILED", repost_error.message, 500)

        void sendPostRepostNotification(req.userId, data.owner_id, id).catch((notifyError) => {
            req.log.warn({ err: notifyError }, "post repost notification failed")
        })

        return sendSuccess(res, { message: "Post reposted successfully", repost_data: repost_data })

    })

    app.get("/posts/:id/likes", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursorCreatedAt, cursorUserId, limit } = parseInteractionQuery(req.query)

        try {
            await ensureCanViewPost(id, req.userId)
        } catch (e) {
            const msg = e instanceof Error ? e.message : "Could not load likes"
            const status = msg === "Post not found" ? 404 : 403
            return sendError(res, "POST_LIKES_FETCH_FAILED", msg, status)
        }

        let query = supabase
            .schema("public")
            .from("post_likes")
            .select(
                "created_at, liker_id, user:profiles!post_likes_liker_id_fkey(id, username, display_name, avatar_url)"
            )
            .eq("post_id", id)
            .order("created_at", { ascending: false })
            .order("liker_id", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorUserId) {
            query = query.or(
                `created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},liker_id.lt.${cursorUserId})`
            )
        }

        const { data, error } = await query
        if (error) return sendError(res, "POST_LIKES_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const sliced = hasMore ? rows.slice(0, limit) : rows
        const last = sliced[sliced.length - 1]

        return sendSuccess(
            res,
            {
                users: sliced.map((row) => ({
                    ...(row.user ?? {}),
                    interacted_at: row.created_at,
                })),
            },
            {
                pagination: {
                    nextCursor: hasMore
                        ? JSON.stringify({
                            cursorCreatedAt: last?.created_at ?? null,
                            cursorUserId: last?.liker_id ?? null,
                        })
                        : null,
                    limit,
                    hasMore,
                },
            }
        )
    })

    app.get("/posts/:id/reposts", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursorCreatedAt, cursorUserId, limit } = parseInteractionQuery(req.query)

        try {
            await ensureCanViewPost(id, req.userId)
        } catch (e) {
            const msg = e instanceof Error ? e.message : "Could not load reposts"
            const status = msg === "Post not found" ? 404 : 403
            return sendError(res, "POST_REPOSTS_FETCH_FAILED", msg, status)
        }

        let query = supabase
            .schema("public")
            .from("post_reposts")
            .select(
                "created_at, reposter_id, user:profiles!post_reposts_reposter_id_fkey(id, username, display_name, avatar_url)"
            )
            .eq("post_id", id)
            .order("created_at", { ascending: false })
            .order("reposter_id", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorUserId) {
            query = query.or(
                `created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},reposter_id.lt.${cursorUserId})`
            )
        }

        const { data, error } = await query
        if (error) return sendError(res, "POST_REPOSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const sliced = hasMore ? rows.slice(0, limit) : rows
        const last = sliced[sliced.length - 1]

        return sendSuccess(
            res,
            {
                users: sliced.map((row) => ({
                    ...(row.user ?? {}),
                    interacted_at: row.created_at,
                })),
            },
            {
                pagination: {
                    nextCursor: hasMore
                        ? JSON.stringify({
                            cursorCreatedAt: last?.created_at ?? null,
                            cursorUserId: last?.reposter_id ?? null,
                        })
                        : null,
                    limit,
                    hasMore,
                },
            }
        )
    })

    app.post('/posts/:id/unrepost', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        // no need to check visibility -- user can't even like if its private or group so its ok

        const { data: unrepost_data, error: unrepost_error } = await supabase.schema("public").rpc("unrepost_post", {
            actor_id: req.userId,
            target_post_id: id,
        })

        if (unrepost_error) return sendError(res, "POST_UNREPOST_FAILED", unrepost_error.message, 500)
        return sendSuccess(res, { message: "Post unreposted successfully", unrepost_data: unrepost_data })
    })

    app.post('/posts/media/presign', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = presignPostUploadSchema.parse(req.body)

        const postId = parsedBody.postId ?? generateRandomId(16)

        if (parsedBody.mediaKind === "image") {
            const upload = await getPostMediaPresignedUrl(postId, parsedBody.format)

            return sendSuccess(res, {
                postId,
                upload,
            })
        }

        const upload = await getPostVideoPresignedUrl(postId, parsedBody.format)

        return sendSuccess(res, {
            postId,
            upload,
        })
    })

    app.post('/posts/create', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = createPostSchema.parse(req.body)

        try {
            const prepared = await cleanPostForInsert({
                ownerId: req.userId,
                postId: parsedBody.postId,
                groupId: parsedBody.groupId ?? null,
                kind: parsedBody.kind,
                visibility: parsedBody.visibility,
                trackId: parsedBody.trackId ?? null,
                content: parsedBody.content,
            })

            const { data, error } = await supabase
                .schema("public")
                .from("posts")
                .insert(prepared.row)
                .select("*")
                .single()

            if (error) {
                return sendError(res, "POST_CREATE_FAILED", error.message, 500)
            }

            if (parsedBody.visibility === "public") {
                void sendPostCreateFanout(data.id).catch((notifyError) => {
                    req.log.warn({ err: notifyError }, "post fanout enqueue failed")
                })
            }

            return sendSuccess(res, {
                post: data,
            }, undefined, 201)
        } catch (error) {
            return sendError(res, 'INVALID_POST_CONTENT', error instanceof Error ? error.message : 'Invalid post content', 400)
        }
    })

    app.post("/posts/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const parsedBody = updatePostSchema.parse(req.body)

        const { data: existingPost, error: existingPostError } = await supabase
            .schema("public")
            .from("posts")
            .select(`
            *,
            owner:profiles!posts_owner_id_fkey (
              id,
              username,
              avatar_url
            )
          `)
            .eq("id", id)
            .single()

        if (existingPostError) {
            return sendError(res, "POST_NOT_FOUND", "Post not found", 404)
        }

        if (!existingPost) {
            return sendError(res, "POST_NOT_FOUND", "Post not found", 404)
        }

        if (existingPost.owner_id !== req.userId) {
            return sendError(res, "FORBIDDEN", "You do not own this post", 403)
        }

        try {
            const prepared = await cleanPostForUpdate({
                existingPost,
                updates: parsedBody,
            })

            const { data: updatedPost, error: updateError } = await supabase
                .schema("public")
                .from("posts")
                .update(prepared.row)
                .eq("id", id)
                .select(`
              *,
              owner:profiles!posts_owner_id_fkey (
                id,
                username,
                avatar_url
              )
            `)
                .single()

            if (updateError) {
                return sendError(res, "POST_UPDATE_FAILED", updateError.message, 500)
            }

            return sendSuccess(res, {
                post: updatedPost,
                viewer: {
                    is_owner: true,
                    is_liked: false,
                    is_reposted: false,
                },
            })
        } catch (error) {
            return sendError(
                res,
                "INVALID_POST_UPDATE",
                error instanceof Error ? error.message : "Invalid post update",
                400
            )
        }
    })

    app.post("/posts/:id/delete", { preHandler: [app.authenticate] }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: post, error: postError } = await supabase.schema("public").from("posts").select("id, owner_id").eq("id", id).maybeSingle()

        if (postError) { return sendError(res, "POST_FETCH_FAILED", postError.message, 500) }

        if (!post) { return sendError(res, "POST_NOT_FOUND", "Post not found", 404) }

        if (post.owner_id !== req.userId) { return sendError(res, "FORBIDDEN", "You do not own this post", 403) }

        const { error: deleteError } = await supabase.schema("public").from("posts").delete().eq("id", id)

        if (deleteError) { return sendError(res, "POST_DELETE_FAILED", deleteError.message, 500) }

        return sendSuccess(res, { message: "Post deleted successfully" })
    })

    // comments
    app.get("/posts/:id/comments", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { cursor, limit } = listCommentsQuerySchema.parse(req.query)
        const decoded = decodeCommentCursor(cursor)

        let query = supabase
            .schema("public")
            .from("post_comments")
            .select(`
            id,
            post_id,
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
            owner:profiles!post_comments_owner_id_fkey(id, username, avatar_url),
            comment_likes!left(liker_id)
          `)
            .eq("post_id", id)
            .is("parent_comment_id", null)
            .order("is_pinned", { ascending: false })
            .order("is_hidden", { ascending: true })
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(limit + 1)

        if (req.userId) query = query.eq("comment_likes.liker_id", req.userId)
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

    app.get("/posts/:id/comments/:commentId/replies", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { postId, commentId } = req.params as { postId: string; commentId: string }
        const { cursor, limit } = listCommentsQuerySchema.parse(req.query)
        const decoded = decodeCommentCursor(cursor)

        let query = supabase
            .schema("public")
            .from("post_comments")
            .select(`
            id,
            post_id,
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
            owner:profiles!post_comments_owner_id_fkey(id, username, avatar_url),
            comment_likes!left(liker_id)
          `)
            .eq("post_id", postId)
            .eq("parent_comment_id", commentId)
            .order("is_hidden", { ascending: true })
            .order("created_at", { ascending: true })
            .order("id", { ascending: true })
            .limit(limit + 1)

        if (req.userId) query = query.eq("comment_likes.liker_id", req.userId)
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

    app.post("/posts/:id/comments/create", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const parsedBody = createCommentSchema.parse(req.body)

        try {
            const commentId = generateRandomId(16)
            const content = await buildCommentContent(parsedBody)

            const { data, error } = await supabase.rpc("create_post_comment", {
                actor_id: req.userId,
                target_post_id: id,
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
                    .from("post_comments")
                    .select("id, owner_id")
                    .eq("id", parsedBody.replyToCommentId)
                    .maybeSingle()

                if (replyTarget?.owner_id) {
                    void sendCommentReplyNotification(
                        req.userId,
                        replyTarget.owner_id,
                        replyTarget.id,
                        id
                    ).catch((notifyError) => {
                        req.log.warn({ err: notifyError }, "comment reply notification failed")
                    })
                }
            } else {
                const { data: postOwner } = await supabase
                    .schema("public")
                    .from("posts")
                    .select("owner_id")
                    .eq("id", id)
                    .maybeSingle()

                if (postOwner?.owner_id) {
                    void sendPostCommentNotification(req.userId, postOwner.owner_id, id, commentId).catch(
                        (notifyError) => {
                            req.log.warn({ err: notifyError }, "post comment notification failed")
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

    app.post("/comments/:id/delete", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("delete_post_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_DELETE_FAILED", error.message, 400)

        return sendSuccess(res, {
            message: "Comment deleted successfully",
        })
    })

    app.post("/comments/:id/like", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { data: comment, error: commentError } = await supabase
            .schema("public")
            .from("post_comments")
            .select("id, owner_id, post_id")
            .eq("id", id)
            .maybeSingle()
        if (commentError) return sendError(res, "COMMENT_LIKE_FAILED", commentError.message, 400)
        if (!comment) return sendError(res, "COMMENT_LIKE_FAILED", "Comment not found", 404)

        const { error } = await supabase.rpc("like_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_LIKE_FAILED", error.message, 400)

        void sendCommentLikeNotification(req.userId, comment.owner_id, comment.id, comment.post_id).catch(
            (notifyError) => {
                req.log.warn({ err: notifyError }, "comment like notification failed")
            }
        )

        return sendSuccess(res, {
            liked: true,
        })
    })


    app.post("/comments/:id/unlike", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unlike_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNLIKE_FAILED", error.message, 400)

        return sendSuccess(res, {
            liked: false,
        })
    })

    app.post("/comments/:id/pin", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("pin_post_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_PIN_FAILED", error.message, 400)

        return sendSuccess(res, {
            pinned: true,
        })
    })

    app.post("/comments/:id/unpin", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unpin_post_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNPIN_FAILED", error.message, 400)

        return sendSuccess(res, {
            pinned: false,
        })
    })

    app.post("/comments/:id/hide", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("hide_post_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_HIDE_FAILED", error.message, 400)

        return sendSuccess(res, {
            hidden: true,
        })
    })

    app.post("/comments/:id/unhide", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("unhide_post_comment", {
            actor_id: req.userId,
            target_comment_id: id,
        })

        if (error) return sendError(res, "COMMENT_UNHIDE_FAILED", error.message, 400)

        return sendSuccess(res, {
            hidden: false,
        })
    })

    app.get('/me/posts', { preHandler: app.authenticate }, async (req, res) => {
        const { cursorCreatedAt, cursorId, limit } = postListQuerySchema.parse(req.query)

        let query = supabase
            .schema("public")
            .from("posts")
            .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name)")
            .eq("owner_id", req.userId)
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorId) query = query.or(`created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},id.lt.${cursorId})`)

        const { data, error } = await query
        if (error) return sendError(res, "POSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const posts = hasMore ? rows.slice(0, limit) : rows
        const last = posts.at(-1)

        return sendSuccess(res, { posts }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at, cursorId: last.id }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get('/users/:username/posts', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { cursorCreatedAt, cursorId, limit } = postListQuerySchema.parse(req.query)

        const { data: otherUser, error: otherUserError } = await supabase.schema("public").from("profiles").select("id").eq("username", username).maybeSingle()
        if (otherUserError) return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500)
        if (!otherUser) return sendError(res, "USER_NOT_FOUND", "User not found", 404)

        let query = supabase
            .schema("public")
            .from("posts")
            .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name)")
            .eq("owner_id", otherUser.id)
            .order("created_at", { ascending: false })
            .order("id", { ascending: false })
            .limit(limit + 1)

        if (cursorCreatedAt && cursorId) query = query.or(`created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},id.lt.${cursorId})`)

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

    app.post('/posts/:id/share', async (req, res) => {
        const { id } = req.params as { id: string }

        const { error } = await supabase.rpc("share_post", { post_id: id })

        if (error) return sendError(res, "POST_SHARE_FAILED", error.message, 400)

        return sendSuccess(res, { message: "Post shared successfully" }, undefined, 204)

    })


    app.get("/me/reposts", { preHandler: app.authenticate }, async (req, res) => {
        const { cursorCreatedAt, cursorId, limit } = postListQuerySchema.parse(req.query)

        let query = supabase
            .schema("public")
            .from("post_reposts") // reposter_id, post_id, created_at; no id
            .select("*, post:posts(*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name))")
            .eq("reposter_id", req.userId)
            .order("created_at", { ascending: false })
            .limit(limit + 1)
            
        if (cursorCreatedAt && cursorId) query = query.or(`created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},id.lt.${cursorId})`)

        const { data, error } = await query
        if (error) return sendError(res, "POSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const posts = hasMore ? rows.slice(0, limit) : rows
        const last = posts.at(-1)
        const viewerMap = await getPostViewerContextMap(
            req.userId,
            posts.map((row) => row.post_id).filter((id): id is string => typeof id === "string"),
        )

        return sendSuccess(res, {
            posts: posts.map((row) => ({
                ...row,
                viewer: viewerMap.get(row.post_id) ?? { isLiked: false, isReposted: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at, cursorId: last.id }) : null,
                limit,
                hasMore,
            },
        })
    })

    app.get("/users/:username/reposts", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { username } = req.params as { username: string }
        const { cursorCreatedAt, cursorId, limit } = postListQuerySchema.parse(req.query)

        const { data: otherUser, error: otherUserError } = await supabase.schema("public").from("profiles").select("id").eq("username", username).maybeSingle()
        if (otherUserError) return sendError(res, "USER_LOOKUP_FAILED", otherUserError.message, 500)
        if (!otherUser) return sendError(res, "USER_NOT_FOUND", "User not found", 404)

        let query = supabase
            .schema("public")
            .from("post_reposts")
            .select("*, post:posts(*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name))")
            .eq("reposter_id", otherUser.id)
            .order("created_at", { ascending: false })
            .limit(limit + 1)
            
        if (cursorCreatedAt && cursorId) query = query.or(`created_at.lt.${cursorCreatedAt},and(created_at.eq.${cursorCreatedAt},id.lt.${cursorId})`)

        const { data, error } = await query
        if (error) return sendError(res, "POSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const posts = hasMore ? rows.slice(0, limit) : rows
        const last = posts.at(-1)
        const viewerMap = await getPostViewerContextMap(req.userId, posts.map((row) => row.post_id))

        return sendSuccess(res, {
            posts: posts.map((row) => ({
                ...row,
                viewer: viewerMap.get(row.post_id) ?? { isLiked: false, isReposted: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorCreatedAt: last.created_at, cursorId: last.id }) : null,
                limit,
                hasMore,
            },
        })
    })

}

export default postsRoutes