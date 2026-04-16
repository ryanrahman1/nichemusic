import { z } from "zod"

export const updateProfileSchema = z.object({
    displayName: z.string().min(3).max(20).optional(),
    bio: z.string().min(0).max(100).optional(),
    location_name: z.string().min(3).max(100).optional(),
    is_private: z.boolean().optional(), // whether the profile is private
    profile_song_id: z.string().optional(),
    allow_messages_from: z.enum(["followers", "friends", "none", "all"]).optional(),
    allow_group_invites: z.boolean().optional(),
    spotify_account: z.string().optional(),
    instagram_handle: z.string().optional(),
    tiktok_handle: z.string().optional(),
    update_avatar: z.boolean().optional()
})