import { z } from "zod"

export const groupPostsQuerySchema = z.object({
    sort: z.enum(["new", "old", "top_today", "top_week", "top_month", "top_year", "top_all"]).default("new"),
    cursorCreatedAt: z.string().datetime().optional(),
    cursorId: z.string().optional(),
    cursorScore: z.coerce.number().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const presignGroupUploadSchema = z.object({
    groupId: z.string().min(1).optional(),
    format: z.enum(["jpeg", "webp", "png", "avif"]),
})

export const createGroupSchema = z.object({
    id: z.string().min(1).optional(),
    name: z.string().min(1).max(100),
    slug: z.string().min(1).max(100).optional(),
    description: z.string().min(0).max(1000),
    is_private: z.boolean().optional().default(false),
    avatar_object_key: z.string().min(1).optional(),
})

export const updateGroupSchema = z.object({
    name: z.string().min(1).max(100).optional(),
    slug: z.string().min(1).max(100).optional(),
    description: z.string().min(0).max(1000).optional(),
    is_private: z.boolean().optional().default(false),
    avatar_object_key: z.string().min(1).optional(),
})

export const inviteUserToGroupSchema = z.object({
    userId: z.string().min(1),
})

export const acceptGroupRequestSchema = z.object({
    requesterId: z.string().min(1)
})

export const promoteMemberToRoleSchema = z.object({
    role: z.enum(["moderator", "admin"]),
})