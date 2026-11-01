import { z } from "zod"

export const badgeHoldersQuerySchema = z.object({
    limit: z.coerce.number().int().min(1).max(50).default(30),
    cursor: z.string().optional(),
})
