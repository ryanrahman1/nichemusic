import { generateRandomId } from "./auth.js"
import { supabase } from "../config/supabase.js"
import { env } from "../config/env.js"

export type NotificationKind =
    | "follow"
    | "follow_request"
    | "follow_accept"
    | "post_like"
    | "post_comment"
    | "comment_reply"
    | "post_repost"
    | "new_post_from_following"
    | "new_video_from_following"

type NotificationEntityType =
    | "profile"
    | "post"
    | "comment"
    | "follow_request"
    | "system"

type NotificationRowInput = {
    recipientId: string
    actorId?: string | null
    kind: NotificationKind
    entityType: NotificationEntityType
    entityId?: string | null
    title: string
    body: string
    imageUrl?: string | null
    data?: Record<string, unknown>
}

type QueueMessage =
    | {
        type: "notification_delivery"
        jobId: string
        notificationId: string
        recipientId: string
        kind: NotificationKind
        createdAt: string
    }
    | {
        type: "post_fanout"
        fanoutJobId: string
        postId: string
        createdAt: string
    }

type ProfilePreview = {
    id: string
    username: string
    avatar_url: string | null
}

type NotificationPreferences = {
    user_id: string
    push_enabled: boolean
    follows_enabled: boolean
    follow_requests_enabled: boolean
    follow_accepts_enabled: boolean
    post_likes_enabled: boolean
    post_comments_enabled: boolean
    comment_replies_enabled: boolean
    post_reposts_enabled: boolean
    new_posts_from_following_enabled: boolean
    new_videos_from_following_enabled: boolean
}

async function enqueueNotificationMessage(message: QueueMessage) {

    const res = await fetch(`${env.notificationWorker.url}/enqueue`, {
        method: "POST",
        headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${env.notificationWorker.apiKey}`,
        },
        body: JSON.stringify(message),
    })

    if (!res.ok) throw new Error(`Failed to enqueue notification message: ${res.statusText}`)

    return res.json()
}

async function getProfilePreview(userId: string): Promise<ProfilePreview | null> {
    const { data, error } = await supabase.schema("public").from("profiles").select("id, username, avatar_url").eq("id", userId).maybeSingle()
    if (error) throw new Error(error.message)
    return data
}

async function getNotificationPreferences(userId: string): Promise<NotificationPreferences | null> {
    const { data, error } = await supabase.schema("public").from("notification_preferences").select("*").eq("user_id", userId).maybeSingle()
    if (error) throw new Error(error.message)
    return data
}

function isNotificationEnabledForKind(
    prefs: NotificationPreferences | null,
    kind: NotificationKind
) {
    if (!prefs) return false
    if (!prefs.push_enabled) return false

    switch (kind) {
        case "follow":
            return prefs.follows_enabled
        case "follow_request":
            return prefs.follow_requests_enabled
        case "follow_accept":
            return prefs.follow_accepts_enabled
        case "post_like":
            return prefs.post_likes_enabled
        case "post_comment":
            return prefs.post_comments_enabled
        case "comment_reply":
            return prefs.comment_replies_enabled
        case "post_repost":
            return prefs.post_reposts_enabled
        case "new_post_from_following":
            return prefs.new_posts_from_following_enabled
        case "new_video_from_following":
            return prefs.new_videos_from_following_enabled
        default:
            return false
    }
}

async function createNotificationRow(input: NotificationRowInput) {
    const notificationId = generateRandomId(16)

    const { data, error } = await supabase
        .schema("public")
        .from("notifications")
        .insert({
            id: notificationId,
            recipient_id: input.recipientId,
            actor_id: input.actorId ?? null,
            kind: input.kind,
            entity_type: input.entityType,
            entity_id: input.entityId ?? null,
            title: input.title,
            body: input.body,
            image_url: input.imageUrl ?? null,
            data: input.data ?? {},
        })
        .select("id, recipient_id, kind, created_at")
        .single()

    if (error) throw new Error(error.message)
    return data
}

async function createNotificationJob(notificationId: string, recipientId: string) {
    const jobId = generateRandomId(16)

    const { data, error } = await supabase
        .schema("public")
        .from("notification_jobs")
        .insert({
            id: jobId,
            notification_id: notificationId,
            recipient_id: recipientId,
            status: "pending",
        })
        .select("id, notification_id, recipient_id, created_at")
        .single()

    if (error) throw new Error(error.message)
    return data
}

async function createFanoutJob(postId: string) {
    const fanoutJobId = generateRandomId(16)

    /**
     * Reusing notification_jobs for fanout is awkward.
     * Best long-term: a separate `notification_fanout_jobs` table.
     *
     * For now, store a synthetic "queued" job in notification_jobs is NOT ideal,
     * so this function just returns an ID and enqueues the queue message.
     */
    return {
        id: fanoutJobId,
        postId,
        createdAt: new Date().toISOString(),
    }
}

function buildNotificationCopy(params: {
    kind: NotificationKind
    actorUsername: string
}) {
    switch (params.kind) {
        case "follow":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} started following you`,
            }
        case "follow_request":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} requested to follow you`,
            }
        case "follow_accept":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} accepted your follow request`,
            }
        case "post_like":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} liked your post`,
            }
        case "post_comment":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} commented on your post`,
            }
        case "comment_reply":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} replied to your comment`,
            }
        case "post_repost":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} reposted your post`,
            }
        default:
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} sent you a notification`,
            }
    }
}

async function createAndQueueSingleRecipientNotification(input: {
    recipientId: string
    actorId: string
    kind: Exclude<
        NotificationKind,
        "new_post_from_following" | "new_video_from_following"
    >
    entityType: NotificationEntityType
    entityId?: string | null
    data?: Record<string, unknown>
}) {
    if (input.actorId === input.recipientId) return null

    const [prefs, actor] = await Promise.all([
        getNotificationPreferences(input.recipientId),
        getProfilePreview(input.actorId),
    ])

    if (!actor) return null
    if (!isNotificationEnabledForKind(prefs, input.kind)) return null

    const copy = buildNotificationCopy({
        kind: input.kind,
        actorUsername: actor.username,
    })

    const notification = await createNotificationRow({
        recipientId: input.recipientId,
        actorId: input.actorId,
        kind: input.kind,
        entityType: input.entityType,
        entityId: input.entityId ?? null,
        title: copy.title,
        body: copy.body,
        imageUrl: actor.avatar_url,
        data: input.data ?? {},
    })

    const job = await createNotificationJob(notification.id, input.recipientId)

    await enqueueNotificationMessage({
        type: "notification_delivery",
        jobId: job.id,
        notificationId: notification.id,
        recipientId: notification.recipient_id,
        kind: notification.kind,
        createdAt: notification.created_at,
    })

    return notification
}

export async function sendFollowNotification(actorId: string, recipientId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow",
        entityType: "profile",
        entityId: actorId,
        data: {},
    })
}

export async function sendFollowRequestNotification(actorId: string, recipientId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow_request",
        entityType: "follow_request",
        entityId: actorId,
        data: {},
    })
}

export async function sendFollowAcceptNotification(actorId: string, recipientId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow_accept",
        entityType: "follow_request",
        entityId: actorId,
        data: {},
    })
}

export async function sendPostLikeNotification(actorId: string, recipientId: string, postId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_like",
        entityType: "post",
        entityId: postId,
        data: { postId },
    })
}

export async function sendPostCommentNotification(actorId: string, recipientId: string, postId: string, commentId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_comment",
        entityType: "comment",
        entityId: commentId,
        data: { postId, commentId },
    })
}

export async function sendCommentReplyNotification(actorId: string, recipientId: string, commentId: string, postId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "comment_reply",
        entityType: "comment",
        entityId: commentId,
        data: { postId, commentId },
    })
}

export async function sendPostRepostNotification(actorId: string, recipientId: string, postId: string) {
    return createAndQueueSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_repost",
        entityType: "post",
        entityId: postId,
        data: { postId },
    })
}

export async function sendPostCreateFanout(postId: string) {
    const fanoutJob = await createFanoutJob(postId)

    await enqueueNotificationMessage({
        type: "post_fanout",
        fanoutJobId: fanoutJob.id,
        postId: fanoutJob.postId,
        createdAt: fanoutJob.createdAt,
    })

    return fanoutJob
}