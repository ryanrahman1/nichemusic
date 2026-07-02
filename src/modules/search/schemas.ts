import { z } from "zod"

export const searchProfilesQuerySchema = z.object({
    q: z.string().trim().min(1).max(50),
    limit: z.coerce.number().int().min(1).max(30).default(15),
    cursorScore: z.coerce.number().optional(),
    cursorId: z.string().optional(),
})

export const globalSearchQuerySchema = z.object({
    q: z.string().trim().min(1).max(100),
    limit: z.coerce.number().int().min(1).max(30).optional(),
    perTypeLimit: z.coerce.number().int().min(1).max(30).optional(),
    types: z.string().optional(),
})

export function parseSearchFilterTypes(types?: string): string[] | null {
    if (!types?.trim()) return null

    const parsed = types
        .split(",")
        .map((value) => value.trim())
        .filter(Boolean)

    return parsed.length > 0 ? parsed : null
}

export const discoverHomeQuerySchema = z.object({
    sectionLimit: z.coerce.number().int().min(1).max(30).default(10),
})