import { z } from "zod"

export const trackSchema = z.object({
    id: z.string(),
    source: z.enum(["apple_music", "spotify", "deezer", "internal"]),
    source_id: z.string(),
    name: z.string().nullable(),
    artwork_url: z.url().nullable(),
    artist_id: z.string().nullable(),
    album_id: z.string().nullable(),
    preview_url: z.string().nullable(),
    release_date: z.string().nullable()
})

export type Track = z.infer<typeof trackSchema>

export const albumSchema = z.object({
    id: z.string(),
    source: z.enum(["apple_music", "spotify", "deezer", "internal"]),
    source_id: z.string(),
    name: z.string().nullable(),
    artist_id: z.string().nullable(),
    artwork_url: z.url().nullable(),
    copyright: z.string().nullable(),
    editorial_note: z.string().nullable(),
    release_date: z.string().nullable(),
    track_count: z.number().nullable(),
})

export type Album = z.infer<typeof albumSchema>

export const artistSchema = z.object({
    id: z.string(),
    source: z.enum(["apple_music", "spotify", "deezer", "internal"]),
    source_id: z.string(),
    name: z.string().nullable(),
    image_url: z.url().nullable(),
})

export type Artist = z.infer<typeof artistSchema>


export const musicEntityTypeSchema = z.enum(["songs", "albums", "artists"])

export const musicLibraryQuerySchema = z.object({
    cursorScore: z.coerce.number().optional(),
    /** Tie-breaker for `get_trending_tracks` (with {@link cursorScore} + {@link cursorId}). */
    cursorCreatedAt: z.string().optional(),
    cursorId: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
    windowDays: z.coerce.number().int().min(1).max(60).default(14),
})

export const musicMeQuerySchema = z.object({
    type: z.enum(["songs", "albums"]).optional(),
    cursorCreatedAt: z.string().optional(),
    cursorId: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const musicFollowingQuerySchema = z.object({
    cursorCreatedAt: z.string().optional(),
    cursorId: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})