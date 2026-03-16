import { z } from "zod"

export const searchProfilesQuerySchema = z.object({
    q: z.string().trim().min(1).max(50),
    limit: z.coerce.number().int().min(1).max(30).default(15),
    cursorScore: z.coerce.number().optional(),
    cursorId: z.string().optional(),
})