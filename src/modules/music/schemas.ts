import { z } from "zod"
import { baseMetadataSchema, successResponseSchema } from "../../global/schemas.js"

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

export const commentKindSchema = z.enum(["text", "track", "gif"])

export const commentGifSchema = z.object({
    id: z.string(),
    url: z.string().url(),
    width: z.number().int().positive(),
    height: z.number().int().positive(),
})

export const createTextCommentSchema = z.object({
    kind: z.literal("text"),
    text: z.string().min(1).max(1000),
    parentCommentId: z.string().nullable().optional(),
    replyToCommentId: z.string().nullable().optional(),
})

export const createTrackCommentSchema = z.object({
    kind: z.literal("track"),
    text: z.string().max(1000).optional().default(""),
    trackId: z.string(),
    parentCommentId: z.string().nullable().optional(),
    replyToCommentId: z.string().nullable().optional(),
})

export const createGifCommentSchema = z.object({
    kind: z.literal("gif"),
    text: z.string().max(1000).optional().default(""),
    gif: commentGifSchema,
    parentCommentId: z.string().nullable().optional(),
    replyToCommentId: z.string().nullable().optional(),
})

export const createCommentSchema = z.discriminatedUnion("kind", [
    createTextCommentSchema,
    createTrackCommentSchema,
    createGifCommentSchema,
])

export type CreateCommentSchema = z.infer<typeof createCommentSchema>

export const commentCursorSchema = z.object({
    createdAt: z.string(),
    id: z.string(),
})

export const listCommentsQuerySchema = z.object({
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(30).default(15),
})

export const commentOwnerSchema = z.object({
    id: z.string(),
    username: z.string(),
    avatar_url: z.string().nullable().optional(),
})

export const commentViewerSchema = z.object({
    is_owner: z.boolean(),
    is_liked: z.boolean(),
})

export const commentResultSchema = z.object({
    id: z.string(),
    track_id: z.string(),
    owner_id: z.string(),
    parent_comment_id: z.string().nullable(),
    reply_to_comment_id: z.string().nullable(),
    reply_to_user_id: z.string().nullable(),
    kind: commentKindSchema,
    content: z.unknown(),
    like_count: z.number().int(),
    reply_count: z.number().int(),
    is_hidden: z.boolean(),
    is_pinned: z.boolean(),
    created_at: z.string(),
    owner: commentOwnerSchema,
    viewer: commentViewerSchema,
})

export const commentListResultSchema = z.object({
    comments: z.array(commentResultSchema),
})

export const commentMutationResultSchema = z.object({
    message: z.string().optional(),
    commentId: z.string().optional(),
    liked: z.boolean().optional(),
    pinned: z.boolean().optional(),
    hidden: z.boolean().optional(),
})

export const commentPaginationMetadataSchema = baseMetadataSchema.extend({
    pagination: z.object({
        nextCursor: z.string().nullable(),
        limit: z.number().int().positive(),
        hasMore: z.boolean(),
    }),
})

export const listCommentsResponseSchema = successResponseSchema(
    commentListResultSchema,
    commentPaginationMetadataSchema
)

export const createCommentResponseSchema = successResponseSchema(commentMutationResultSchema)


// create track

export const uploadFormatSchema = z.enum(["jpeg", "webp", "png", "avif"])
export const videoFormatSchema = z.enum(["mp4", "webm", "mov", "mkv"])
export const musicFormatSchema = z.enum(["mp3", "m4a", "wav", "flac", "aac"])

export const updateNicheTrackDraftSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    release_date: z.iso.date().optional(),
    image: z.object({
        hasImage: z.boolean().optional(),
        imageFormat: uploadFormatSchema.optional(),
    }).optional(),
    explicit: z.boolean().optional(),
    duration_ms: z.number().int().positive().optional(), // determined by the music file, always set
    bpm: z.number().int().positive().optional(),
    visibility: z.enum(["public", "private"]).optional(),
    moment: z.object({
        hasMoment: z.boolean().optional(),
        momentFormat: z.enum(["mp4", "webm", "mov", "mkv"]).optional(),
    }).optional(),
    credits: z.object({
        hasCredits: z.boolean().optional(),
        artists: z.array(z.object({
            artistId: z.string(),
            isPrimary: z.boolean().optional(),
        })).optional()
    }).optional(),
})

export const updateReleaseDraftSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    release_date: z.iso.date().optional(),
    image: z.object({
        hasImage: z.boolean().optional(),
        imageFormat: uploadFormatSchema.optional(),
    }).optional(),
    visibility: z.enum(["public", "private"]).optional(),
    release_type: z.enum(["album", "ep"]).optional(),
})

// exact same as update niche track, just with a index field
export const updateNicheTrackOnReleaseDraftSchema = updateNicheTrackDraftSchema.extend({
    track_number: z.number().int().positive(),
})

export const updateNicheTrackSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    image: z.object({
        hasImage: z.boolean().optional(),
        imageFormat: uploadFormatSchema.optional(),
    }).optional(),
    explicit: z.boolean().optional(),
    bpm: z.number().int().positive().optional(),
    visibility: z.enum(["public", "private"]).optional(),
    moment: z.object({
        hasMoment: z.boolean().optional(),
        momentFormat: z.enum(["mp4", "webm", "mov", "mkv"]).optional(),
    }).optional(),
    credits: z.object({
        hasCredits: z.boolean().optional(),
        artists: z.array(z.object({
            artistId: z.string(),
            isPrimary: z.boolean().optional(),
        })).optional()
    }).optional(),
})

export const updateReleaseSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    image: z.object({
        hasImage: z.boolean().optional(),
        imageFormat: uploadFormatSchema.optional(),
    }).optional(),
    visibility: z.enum(["public", "private"]).optional(),
    release_type: z.enum(["album", "ep"]).optional(),
})

export const draftMusicUploadSchema = z.object({
    musicFormat: musicFormatSchema,
})

export const listDraftsQuerySchema = z.object({
    limit: z.coerce.number().int().min(1).max(50).default(50),
})

export const recordNicheTrackPlaySchema = z.object({
    listenMs: z.number().int().min(30_000).default(30_000),
    source: z.string().trim().min(1).max(64).optional(),
    contextType: z.string().trim().min(1).max(64).optional(),
    contextId: z.string().trim().min(1).max(64).optional(),
    percentPlayed: z.number().min(0).max(1).optional(),
    completed: z.boolean().optional(),
    appVersion: z.string().trim().min(1).max(32).optional(),
})