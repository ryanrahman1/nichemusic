import { z } from "zod"

export const registerPushDeviceSchema = z.object({
    platform: z.literal("ios"),
    environment: z.enum(["development", "production"]).default("production"),
    deviceToken: z.string().min(16),
    appBundleId: z.string().min(3),
    deviceName: z.string().max(100).nullable().optional(),
})

export type RegisterPushDeviceSchema = z.infer<typeof registerPushDeviceSchema>

export const notificationPreferencesSchema = z.object({
    pushEnabled: z.boolean().optional(),
    followsEnabled: z.boolean().optional(),
    followRequestsEnabled: z.boolean().optional(),
    followAcceptsEnabled: z.boolean().optional(),
    postLikesEnabled: z.boolean().optional(),
    postCommentsEnabled: z.boolean().optional(),
    commentRepliesEnabled: z.boolean().optional(),
    postRepostsEnabled: z.boolean().optional(),
    newPostsFromFollowingEnabled: z.boolean().optional(),
    newVideosFromFollowingEnabled: z.boolean().optional(),
    quietHoursEnabled: z.boolean().optional(),
    quietHoursStartMinute: z.number().int().min(0).max(1439).optional(),
    quietHoursEndMinute: z.number().int().min(0).max(1439).optional()
})

export type NotificationPreferencesSchema = z.infer<typeof notificationPreferencesSchema>