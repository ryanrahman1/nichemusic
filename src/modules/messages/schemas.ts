import { z } from "zod"

export const messageBaseSchema = z.object({
    conversationId: z.string().min(1),
    replyToMessageId: z.string().nullable().optional(),
    clientId: z.string().min(1),
})

export const messageContentSchema = z.discriminatedUnion('kind', [
    z.object({
        kind: z.literal('text'),
        text: z.string().min(1),
    }),
    z.object({
        kind: z.literal('track_share'),
        trackId: z.string().min(1),
        caption: z.string().min(1).optional(),
    }),
    z.object({
        kind: z.literal('album_share'),
        albumId: z.string().min(1),
        caption: z.string().min(1).optional(),
    }),
    z.object({
        kind: z.literal('artist_share'),
        artistId: z.string().min(1),
        caption: z.string().min(1).optional(),
    }),
    z.object({
        kind: z.literal('profile_share'),
        userId: z.string().min(1),
        caption: z.string().min(1).optional(),
    }),
    z.object({
        kind: z.literal('gif'),
        caption: z.string().min(1).optional(),
        gifUrl: z.url().min(1),
        width: z.number().int().positive(),
        height: z.number().int().positive(),
        provider: z.enum(['giphy', 'tenor', 'custom']),
    }),
    // put image and video here ltr for v2
])

export const createMessageSchema = messageBaseSchema.and(messageContentSchema)

export const markConversationAsReadSchema = z.object({
    conversationId: z.string().min(1),
    messageId: z.string().min(1),
})

export const getConversationParamsSchema = z.object({
    id: z.string().min(1),
})

export const getConversationQuerySchema = z.object({
    cursor: z.string().datetime().optional(),
    limit: z.coerce.number().int().min(1).max(100).optional(),
})

export const ensureDmSchema = z.object({
    otherUserId: z.string().min(1),
})