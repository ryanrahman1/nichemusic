import { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { generateRandomId } from "../../lib/auth.js"
import { registerPushDeviceSchema, RegisterPushDeviceSchema } from "./schemas.js"
import { notificationPreferencesSchema, NotificationPreferencesSchema } from "./schemas.js"

const notificationsRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me/notifications', { preHandler: app.authenticate }, async (req, res) => {

        const { data, error } = await supabase.schema("public").from("notifications").select('*').eq("recipient_id", req.userId).order("created_at", { ascending: false })

        if (error) return sendError(res, "NOTIFICATIONS_FETCH_FAILED", error.message, 500)

        return sendSuccess(res, { notifications: data })
    })

    app.post('/me/notifications/:id/read', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { data, error } = await supabase.schema("public").from("notifications").update({ read_at: new Date().toISOString(), read: true }).eq("id", id).eq("recipient_id", req.userId).single()
        if (error) return sendError(res, "NOTIFICATION_READ_FAILED", error.message, 500)

        return sendSuccess(res, { notification: data })
    })

    app.post('/me/notifications/all/read', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema("public").from("notifications").update({ read_at: new Date().toISOString(), read: true }).eq("recipient_id", req.userId)
        if (error) return sendError(res, "NOTIFICATIONS_READ_FAILED", error.message, 500)

        return sendSuccess(res, { notifications: data })
    })

    app.post('/me/notifications/device', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody: RegisterPushDeviceSchema = registerPushDeviceSchema.parse(req.body)

        const { data: existing, error: existingError } = await supabase
            .schema("public")
            .from("push_endpoints")
            .select("id")
            .eq("device_token", parsedBody.deviceToken)
            .maybeSingle()

        if (existingError) return sendError(res, "PUSH_ENDPOINT_LOOKUP_FAILED", existingError.message, 500)

        if (existing) {
            const { data, error } = await supabase
                .schema("public")
                .from("push_endpoints")
                .update({
                    user_id: req.userId,
                    platform: parsedBody.platform,
                    environment: parsedBody.environment,
                    app_bundle_id: parsedBody.appBundleId,
                    device_name: parsedBody.deviceName ?? null,
                    is_active: true,
                    last_seen_at: new Date().toISOString(),
                    invalidated_at: null,
                    invalidation_reason: null,
                })
                .eq("id", existing.id)
                .select("*")
                .single()

            if (error) return sendError(res, "PUSH_ENDPOINT_UPDATE_FAILED", error.message, 500)

            return sendSuccess(res, {
                endpoint: data,
            })
        }

        const { data, error } = await supabase
            .schema("public")
            .from("push_endpoints")
            .insert({
                id: generateRandomId(16),
                user_id: req.userId,
                platform: parsedBody.platform,
                environment: parsedBody.environment,
                device_token: parsedBody.deviceToken,
                app_bundle_id: parsedBody.appBundleId,
                device_name: parsedBody.deviceName ?? null,
                is_active: true,
                last_seen_at: new Date().toISOString(),
            })
            .select("*")
            .single()

        if (error) return sendError(res, "PUSH_ENDPOINT_CREATE_FAILED", error.message, 500)

        return sendSuccess(res, {
            endpoint: data,
        }, undefined, 201)
    })

    app.post('/me/notifications/device/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { deviceToken } = req.body as { deviceToken: string }
        // set is_active fales, set last_seen_at to now
        const { data, error } = await supabase.schema("public").from("push_endpoints").update({ is_active: false, last_seen_at: new Date().toISOString() }).eq("device_token", deviceToken).single()
        if (error) return sendError(res, "PUSH_ENDPOINT_INVALIDATE_FAILED", error.message, 500)

        return sendSuccess(res, { endpoint: data })
    })

    app.post('/me/notifications/preferences', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody: NotificationPreferencesSchema = notificationPreferencesSchema.parse(req.body)

        const updateData: Record<string, any> = {
            push_enabled: parsedBody.pushEnabled,
            follows_enabled: parsedBody.followsEnabled,
            follow_requests_enabled: parsedBody.followRequestsEnabled,
            follow_accepts_enabled: parsedBody.followAcceptsEnabled,
            post_likes_enabled: parsedBody.postLikesEnabled,
            post_comments_enabled: parsedBody.postCommentsEnabled,
            comment_replies_enabled: parsedBody.commentRepliesEnabled,
            post_reposts_enabled: parsedBody.postRepostsEnabled,
            new_posts_from_following_enabled: parsedBody.newPostsFromFollowingEnabled,
            new_videos_from_following_enabled: parsedBody.newVideosFromFollowingEnabled,
            quiet_hours_enabled: parsedBody.quietHoursEnabled,
            quiet_hours_start_minute: parsedBody.quietHoursStartMinute,
            quiet_hours_end_minute: parsedBody.quietHoursEndMinute,
        }

        Object.keys(updateData).forEach(key =>
            updateData[key] === undefined && delete updateData[key]
        )

        if (Object.keys(updateData).length === 0) {
            return sendError(res, "NO_CHANGES_PROVIDED", "No update data provided", 400)
        }

        const { data, error } = await supabase
            .schema("public")
            .from("notification_preferences")
            .update(updateData)
            .eq("user_id", req.userId)
            .select('*')
            .single()


        if (error) return sendError(res, "NOTIFICATION_PREFERENCES_UPDATE_FAILED", error.message, 500)

        return sendSuccess(res, { preferences: data })

    })

}

export default notificationsRoutes