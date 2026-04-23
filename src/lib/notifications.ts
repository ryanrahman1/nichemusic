import { generateRandomId } from "./auth.js"
import { supabase } from "../config/supabase.js"
import { env } from "../config/env.js"
import { sendDirectAPNS } from "./apns.js"

export type NotificationKind =
    | "message"
    | "follow"
    | "follow_request"
    | "follow_accept"
    | "post_like"
    | "post_comment"
    | "comment_like"
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

type ProfilePreview = {
    id: string
    username: string
    avatar_url: string | null
}

type GroupMemberPreview = {
    id: string
    username: string | null
    display_name: string | null
    avatar_url: string | null
}

export type NotificationPreferences = {
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

async function getProfilePreview(userId: string): Promise<ProfilePreview | null> {
    const { data, error } = await supabase.schema("public").from("profiles").select("id, username, avatar_url").eq("id", userId).maybeSingle()
    if (error) throw new Error(error.message)
    return data
}

async function getGroupMemberPreviews(userIds: string[]): Promise<GroupMemberPreview[]> {
    const uniqueIds = Array.from(new Set(userIds.filter(Boolean)))
    if (uniqueIds.length === 0) return []

    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, display_name, avatar_url")
        .in("id", uniqueIds)
    if (error) throw new Error(error.message)
    return (data ?? []) as GroupMemberPreview[]
}

function groupMemberLabel(member: GroupMemberPreview) {
    return (member.username ?? member.display_name ?? "unknown").trim()
}

function buildGroupMemberListLabel(members: GroupMemberPreview[]) {
    const labels = members
        .map(groupMemberLabel)
        .map((label) => (label.length > 0 ? label : "unknown"))
    const firstFew = labels.slice(0, 3)
    if (labels.length > 3) {
        return `${firstFew.join(", ")}, ...`
    }
    return firstFew.join(", ")
}

function buildGroupAvatarCollageDataUri(avatarUrls: string[]) {
    const urls = avatarUrls.slice(0, 3)
    if (urls.length === 0) return null

    const escaped = urls.map((url) => url.replace(/&/g, "&amp;").replace(/"/g, "&quot;"))
    const svg = (() => {
        if (escaped.length === 1) {
            return `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120"><rect width="120" height="120" fill="#111827"/><image href="${escaped[0]}" x="0" y="0" width="120" height="120" preserveAspectRatio="xMidYMid slice"/></svg>`
        }
        if (escaped.length === 2) {
            return `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120"><rect width="120" height="120" fill="#111827"/><image href="${escaped[0]}" x="0" y="0" width="60" height="120" preserveAspectRatio="xMidYMid slice"/><image href="${escaped[1]}" x="60" y="0" width="60" height="120" preserveAspectRatio="xMidYMid slice"/></svg>`
        }
        return `<svg xmlns="http://www.w3.org/2000/svg" width="120" height="120"><rect width="120" height="120" fill="#111827"/><image href="${escaped[0]}" x="0" y="0" width="60" height="60" preserveAspectRatio="xMidYMid slice"/><image href="${escaped[1]}" x="60" y="0" width="60" height="60" preserveAspectRatio="xMidYMid slice"/><image href="${escaped[2]}" x="0" y="60" width="120" height="60" preserveAspectRatio="xMidYMid slice"/></svg>`
    })()
    return `data:image/svg+xml;utf8,${encodeURIComponent(svg)}`
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
        case "message":
            return true
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
        case "comment_like":
            return prefs.comment_replies_enabled
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
        .select("id, recipient_id, actor_id, kind, entity_type, entity_id, title, body, data, created_at")
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

async function updateNotificationJobStatus(
    jobId: string,
    status: "processing" | "sent" | "partial" | "failed" | "cancelled",
    lastError?: string
) {
    const patch: Record<string, unknown> = {
        status,
    }
    if (status === "processing") {
        patch.last_attempted_at = new Date().toISOString()
    }
    if (status === "sent" || status === "partial" || status === "failed" || status === "cancelled") {
        patch.completed_at = new Date().toISOString()
    }
    if (lastError) {
        patch.last_error = lastError
    }
    const { error } = await supabase
        .schema("public")
        .from("notification_jobs")
        .update(patch)
        .eq("id", jobId)
    if (error) throw new Error(error.message)
}

type PushEndpoint = {
    id: string
    environment: "development" | "production"
    device_token: string | null
    app_bundle_id: string | null
}

async function getActiveIosEndpoints(recipientId: string): Promise<PushEndpoint[]> {
    const { data, error } = await supabase
        .schema("public")
        .from("push_endpoints")
        .select("id, environment, device_token, app_bundle_id")
        .eq("user_id", recipientId)
        .eq("platform", "ios")
        .eq("is_active", true)
    if (error) throw new Error(error.message)
    const rows = (data ?? []) as PushEndpoint[]
    return rows.filter((row) => !!row.device_token)
}

async function recordNotificationDelivery(params: {
    notificationId: string
    endpointId: string
    status: "sent" | "failed" | "invalidated"
    providerMessageId?: string | null
    statusCode?: number | null
    errorCode?: string | null
    errorMessage?: string | null
}) {
    const { error } = await supabase
        .schema("public")
        .from("notification_deliveries")
        .insert({
            id: generateRandomId(16),
            notification_id: params.notificationId,
            endpoint_id: params.endpointId,
            provider: "apns",
            status: params.status,
            provider_message_id: params.providerMessageId ?? null,
            status_code: params.statusCode ?? null,
            error_code: params.errorCode ?? null,
            error_message: params.errorMessage ?? null,
        })
    if (error) throw new Error(error.message)
}

async function invalidatePushEndpoint(endpointId: string, reason: string) {
    const { error } = await supabase
        .schema("public")
        .from("push_endpoints")
        .update({
            is_active: false,
            invalidated_at: new Date().toISOString(),
            invalidation_reason: reason,
            updated_at: new Date().toISOString(),
        })
        .eq("id", endpointId)
    if (error) throw new Error(error.message)
}

function buildNotificationCopy(params: {
    kind: NotificationKind
    actorUsername: string
    messagePreview?: string | null
}) {
    const preview = params.messagePreview?.trim()
    switch (params.kind) {
        case "message":
            return {
                title: "Niche Music",
                body:
                    preview && preview.length > 0
                        ? `@${params.actorUsername}: ${preview}`
                        : `New message from @${params.actorUsername}`,
            }
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
        case "comment_like":
            return {
                title: "Niche Music",
                body: `@${params.actorUsername} liked your comment`,
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

async function deliverNotificationDirect(notification: {
    id: string
    recipient_id: string
    actor_id: string | null
    kind: NotificationKind
    entity_type: string
    entity_id: string | null
    title: string
    body: string
    data: Record<string, unknown>
}) {
    const job = await createNotificationJob(notification.id, notification.recipient_id)
    await updateNotificationJobStatus(job.id, "processing")
    const endpoints = await getActiveIosEndpoints(notification.recipient_id)

    if (endpoints.length === 0) {
        await updateNotificationJobStatus(job.id, "sent")
        return
    }

    let sent = 0
    let failed = 0

    for (const endpoint of endpoints) {
        if (!endpoint.device_token) continue
        const result = await sendDirectAPNS(
            env.apns,
            {
                id: endpoint.id,
                environment: endpoint.environment,
                deviceToken: endpoint.device_token,
                appBundleId: endpoint.app_bundle_id,
            },
            {
                title: notification.title,
                body: notification.body,
                kind: notification.kind,
                entityType: notification.entity_type,
                entityId: notification.entity_id,
                actorId: notification.actor_id,
                data: notification.data ?? {},
            }
        )

        if (result.ok) {
            sent++
            await recordNotificationDelivery({
                notificationId: notification.id,
                endpointId: endpoint.id,
                status: "sent",
                providerMessageId: result.messageId ?? null,
            })
            continue
        }

        failed++
        await recordNotificationDelivery({
            notificationId: notification.id,
            endpointId: endpoint.id,
            status: result.invalidateEndpoint ? "invalidated" : "failed",
            statusCode: result.statusCode,
            errorCode: result.reason ?? null,
            errorMessage: result.reason ?? null,
        })

        if (result.invalidateEndpoint) {
            await invalidatePushEndpoint(endpoint.id, result.reason ?? "BadDeviceToken")
        }
    }

    if (sent > 0 && failed === 0) {
        await updateNotificationJobStatus(job.id, "sent")
    } else if (sent > 0 && failed > 0) {
        await updateNotificationJobStatus(job.id, "partial", `Sent ${sent}, failed ${failed}`)
    } else {
        await updateNotificationJobStatus(job.id, "failed", "All endpoints failed")
    }
}

async function createAndSendSingleRecipientNotification(input: {
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
        messagePreview:
            typeof input.data?.messagePreview === "string"
                ? input.data.messagePreview
                : null,
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
        data: {
            actorId: actor.id,
            actorUsername: actor.username,
            ...(input.data ?? {}),
        },
    })

    await deliverNotificationDirect(notification)

    return notification
}

export async function sendFollowNotification(actorId: string, recipientId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow",
        entityType: "profile",
        entityId: actorId,
        data: {},
    })
}

export async function sendFollowRequestNotification(actorId: string, recipientId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow_request",
        entityType: "follow_request",
        entityId: actorId,
        data: {},
    })
}

export async function sendFollowAcceptNotification(actorId: string, recipientId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "follow_accept",
        entityType: "follow_request",
        entityId: actorId,
        data: {},
    })
}

export async function sendPostLikeNotification(actorId: string, recipientId: string, postId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_like",
        entityType: "post",
        entityId: postId,
        data: { postId },
    })
}

export async function sendPostCommentNotification(actorId: string, recipientId: string, postId: string, commentId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_comment",
        entityType: "comment",
        entityId: commentId,
        data: { postId, commentId },
    })
}

export async function sendCommentReplyNotification(actorId: string, recipientId: string, commentId: string, postId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "comment_reply",
        entityType: "comment",
        entityId: commentId,
        data: { postId, commentId },
    })
}

export async function sendPostRepostNotification(actorId: string, recipientId: string, postId: string) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "post_repost",
        entityType: "post",
        entityId: postId,
        data: { postId },
    })
}

export async function sendCommentLikeNotification(
    actorId: string,
    recipientId: string,
    commentId: string,
    postId: string
) {
    return createAndSendSingleRecipientNotification({
        recipientId,
        actorId,
        kind: "comment_like",
        entityType: "comment",
        entityId: commentId,
        data: { commentId, postId },
    })
}

function fanoutKindForPost(postKind: string): "new_post_from_following" | "new_video_from_following" | null {
    if (postKind === "video") return "new_video_from_following"
    if (["text", "image", "track", "pmo", "poll"].includes(postKind)) return "new_post_from_following"
    return null
}

async function hasFanoutNotification(recipientId: string, kind: NotificationKind, postId: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("notifications")
        .select("id")
        .eq("recipient_id", recipientId)
        .eq("kind", kind)
        .eq("entity_id", postId)
        .limit(1)
        .maybeSingle()
    if (error) throw new Error(error.message)
    return !!data
}

export async function sendPostCreateFanout(postId: string) {
    const { data: post, error: postError } = await supabase
        .schema("public")
        .from("posts")
        .select("id, owner_id, kind, visibility")
        .eq("id", postId)
        .maybeSingle()
    if (postError) throw new Error(postError.message)
    if (!post?.owner_id) return null
    if (post.visibility !== "public") return null

    const fanoutKind = fanoutKindForPost(post.kind)
    if (!fanoutKind) return null

    const owner = await getProfilePreview(post.owner_id)
    if (!owner) return null

    const { data: follows, error: followsError } = await supabase
        .schema("public")
        .from("follows")
        .select("follower_id")
        .eq("following_id", post.owner_id)
        .neq("follower_id", post.owner_id)
    if (followsError) throw new Error(followsError.message)

    for (const row of follows ?? []) {
        const recipientId = row.follower_id
        const prefs = await getNotificationPreferences(recipientId)
        if (!isNotificationEnabledForKind(prefs, fanoutKind)) continue

        const exists = await hasFanoutNotification(recipientId, fanoutKind, postId)
        if (exists) continue

        const body =
            fanoutKind === "new_video_from_following"
                ? `@${owner.username} posted a new video`
                : `@${owner.username} posted`

        const notification = await createNotificationRow({
            recipientId,
            actorId: post.owner_id,
            kind: fanoutKind,
            entityType: "post",
            entityId: postId,
            title: "Niche Music",
            body,
            imageUrl: owner.avatar_url,
            data: {
                actorId: owner.id,
                actorUsername: owner.username,
                postId,
            },
        })

        await deliverNotificationDirect(notification)
    }

    return { ok: true }
}

export async function sendMessageNotification(
    actorId: string,
    recipientId: string,
    conversationId: string,
    messageId: string,
    messagePreview?: string | null
) {
    if (actorId === recipientId) return null

    const [prefs, actor] = await Promise.all([
        getNotificationPreferences(recipientId),
        getProfilePreview(actorId),
    ])

    if (!actor) return null
    if (!isNotificationEnabledForKind(prefs, "message")) return null

    const copy = buildNotificationCopy({
        kind: "message",
        actorUsername: actor.username,
        messagePreview: messagePreview ?? null,
    })

    const notification = await createNotificationRow({
        recipientId,
        actorId,
        kind: "message",
        entityType: "system",
        entityId: conversationId,
        title: copy.title,
        body: copy.body,
        imageUrl: actor.avatar_url,
        data: {
            actorId: actor.id,
            actorUsername: actor.username,
            conversationId,
            messageId,
            messagePreview: messagePreview ?? null,
        },
    })

    await deliverNotificationDirect(notification)

    return notification
}

export async function sendGroupAddedNotification(input: {
    actorId: string
    recipientId: string
    conversationId: string
    participantIds: string[]
}) {
    if (input.actorId === input.recipientId) return null

    const [prefs, actor, members] = await Promise.all([
        getNotificationPreferences(input.recipientId),
        getProfilePreview(input.actorId),
        getGroupMemberPreviews(input.participantIds),
    ])

    if (!actor) return null
    if (!isNotificationEnabledForKind(prefs, "message")) return null

    const sortedMembers = members
        .filter((m) => m.id !== input.recipientId)
        .sort((a, b) => groupMemberLabel(a).localeCompare(groupMemberLabel(b)))
    const memberListLabel = buildGroupMemberListLabel(sortedMembers)
    const collage = buildGroupAvatarCollageDataUri(
        sortedMembers.map((m) => m.avatar_url).filter((v): v is string => Boolean(v))
    )

    const notification = await createNotificationRow({
        recipientId: input.recipientId,
        actorId: input.actorId,
        kind: "message",
        entityType: "system",
        entityId: input.conversationId,
        title: memberListLabel.length > 0 ? memberListLabel : "Niche Music",
        body: `@${actor.username} has added you to a group chat`,
        imageUrl: collage,
        data: {
            actorId: actor.id,
            actorUsername: actor.username,
            conversationId: input.conversationId,
            isGroupAdd: true,
            groupMembersLabel: memberListLabel,
        },
    })

    await deliverNotificationDirect(notification)
    return notification
}

export async function sendAdminBroadcastNotification(input: {
    title: string
    body: string
    actorId?: string | null
    link?: string | null
    subtitle?: string | null
}) {
    const { data: endpoints, error: endpointsError } = await supabase
        .schema("public")
        .from("push_endpoints")
        .select("user_id")
        .eq("platform", "ios")
        .eq("is_active", true)
    if (endpointsError) throw new Error(endpointsError.message)

    const uniqueRecipients = Array.from(
        new Set((endpoints ?? []).map((row) => row.user_id).filter(Boolean))
    )

    for (const recipientId of uniqueRecipients) {
        const notification = await createNotificationRow({
            recipientId,
            actorId: input.actorId ?? null,
            kind: "message",
            entityType: "system",
            entityId: null,
            title: input.title,
            body: input.body,
            data: {
                link: input.link ?? null,
                subtitle: input.subtitle ?? null,
                isAdminBroadcast: true,
            },
        })
        await deliverNotificationDirect(notification)
    }

    return { recipients: uniqueRecipients.length }
}