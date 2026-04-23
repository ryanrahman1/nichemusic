import { z } from "zod"

export const updateProfileSchema = z.object({
    displayName: z.string().max(20).optional(),
    bio: z.string().max(100).optional(),
    location_name: z.string().max(100).optional(),
    is_private: z.boolean().optional(), // whether the profile is private
    profile_song_id: z.string().optional(),
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