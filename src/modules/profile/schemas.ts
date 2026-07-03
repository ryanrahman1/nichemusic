import { z } from "zod"

export const updateProfileSchema = z.object({
    displayName: z.string().max(20).optional(),
    bio: z.string().max(100).optional(),
    location_name: z.string().max(100).optional(),
    is_private: z.boolean().optional(), // whether the profile is private
    profile_song_id: z.string().optional(),
    profile_type: z.enum(["artist", "user", "producer", "dj"]).optional(),
    allow_messages_from: z.enum(["followers", "friends", "none", "all"]).optional(),
    allow_group_invites: z.boolean().optional(),
    spotify_account: z.string().optional(),
    instagram_handle: z.string().optional(),
    tiktok_handle: z.string().optional(),
    update_avatar: z.boolean().optional()
})

export const upsertStatusSchema = z
    .object({
        text: z.string().trim().max(180).optional(),
        track_id: z.string().trim().optional(),
    })
    .refine((v) => Boolean(v.text || v.track_id), {
        message: "Status needs text or a track",
    })

export const discographyTypeSchema = z.enum(["album", "ep", "single", "featured_on"])

export const discographyFilterSchema = z.enum(["all", "album", "single", "featured_on"]).default("all")

export const discographyQuerySchema = z.object({
    type: discographyFilterSchema,
    cursorReleaseDate: z.string().optional(),
    cursorType: discographyTypeSchema.optional(),
    cursorId: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})