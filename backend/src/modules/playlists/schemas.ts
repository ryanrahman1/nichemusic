import { z } from "zod"

export const createPlaylistSchema = z.object({
    name: z.string().min(1).max(100),
    description: z.string().min(0).max(1000).optional(),
    visibility: z.enum(["public", "private", "unlisted"]).default("public"),
    has_image: z.boolean().default(false),
    format: z.enum(["jpeg", "webp", "png", "avif"]).default("jpeg"),
})

export const updatePlaylistSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    description: z.string().min(0).max(1000).nullable().optional(),
    visibility: z.enum(["public", "private", "unlisted"]).optional(),
    has_image: z.boolean().default(false),
    format: z.enum(["jpeg", "webp", "png", "avif"]).default("jpeg"),
})