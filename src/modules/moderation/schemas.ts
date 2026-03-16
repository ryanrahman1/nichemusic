import { string, z } from "zod"

export const createReportSchema = z.object({
    reporterId: z.string().nullable(),
    targetType: z.enum(["user", "post", "comment", "message", "group", "track", "album", "artist", "other"]),
    targetId: string(),
    content: z.object({}), //jsonb
    status: z.enum(["open", "under_review", "resolved", "dismissed"]).default("open"),
    priority: z.enum(["low", "normal", "high", "urgent"]).default("normal")
})

export type CreateReportSchema = z.infer<typeof createReportSchema>