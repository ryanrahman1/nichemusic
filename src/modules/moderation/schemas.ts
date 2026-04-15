import { z } from "zod"

export const createReportSchema = z.object({
    targetType: z.enum(["user", "post", "comment", "message", "group", "track", "album", "artist", "other"]),
    targetId: z.string().min(1),
    /** Arbitrary JSON metadata (e.g. conversationId, username) stored as jsonb. */
    content: z.record(z.string(), z.unknown()).default({}),
    status: z.enum(["open", "under_review", "resolved", "dismissed"]).default("open"),
    priority: z.enum(["low", "normal", "high", "urgent"]).default("normal"),
})

export type CreateReportSchema = z.infer<typeof createReportSchema>