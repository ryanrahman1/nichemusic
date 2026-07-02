import { z } from "zod"

export const respondMatchSchema = z.object({
    action: z.enum(["accept", "decline"]),
})

export const matchIdParamsSchema = z.object({
    id: z.string().min(1),
})
