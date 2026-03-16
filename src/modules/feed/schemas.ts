import { z } from "zod"

export const feedEntityTypeSchema = z.enum(["post", "track", "album", "artist", "profile", "feed_item"])

export const feedImpressionSchema = z.object({
    entityType: feedEntityTypeSchema,
    entityId: z.string().min(1),
})

export const feedViewSchema = z.object({
    entityType: feedEntityTypeSchema,
    entityId: z.string().min(1),
    watchTimeMs: z.coerce.number().int().min(0).max(60 * 60 * 1000).optional(),
})

export const feedSkipSchema = z.object({
    entityType: feedEntityTypeSchema,
    entityId: z.string().min(1),
    watchTimeMs: z.coerce.number().int().min(0).max(60 * 60 * 1000).optional(),
})

export const feedOpenProfileSchema = z.object({
    profileId: z.string().min(1),
})