import { z } from "zod"

export const editorialTypeSchema = z.enum([
    "review",
    "news",
    "feature",
    "interview",
    "spotlight",
])

export const editorialStatusSchema = z.enum([
    "draft",
    "submitted",
    "in_review",
    "changes_requested",
    "approved",
    "published",
    "rejected",
    "archived",
])

export const writerRoleSchema = z.enum([
    "contributor",
    "verified",
    "senior",
    "editor",
    "admin",
])

export const creditTypeSchema = z.enum([
    "writer",
    "editor",
    "photographer",
    "illustrator",
    "fact_checker",
])

export const editorialContentSchema = z.object({
    version: z.literal(1).default(1),
    blocks: z.array(z.unknown()).default([]),
})

export const editorialTemplateSchema = z.enum([
    "standard",
    "album_review",
    "interview",
    "artist_spotlight",
])

export const editorialTemplateDataSchema = z.record(z.string(), z.unknown()).default({})

export const uploadImageFormatSchema = z.enum(["jpeg", "webp", "png", "avif"])

export const editorialSlugSchema = z
    .string()
    .trim()
    .min(1)
    .max(80)
    .transform((value) => value.toLowerCase())
    .refine((value) => /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(value), {
        message: "Slug must use lowercase letters, numbers, and hyphens only",
    })

export const listArticlesQuerySchema = z.object({
    type: editorialTypeSchema.optional(),
    template: editorialTemplateSchema.optional(),
    tag: z.string().min(1).optional(),
    writer: z.string().min(1).optional(),
    sort: z.enum(["newest", "oldest"]).default("newest"),
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

// reviews + spotlights lock the type so the desk pages stay skinny
export const listTypedArticlesQuerySchema = listArticlesQuerySchema.omit({
    type: true,
    template: true,
})

export const editorialSearchQuerySchema = z.object({
    q: z.string().trim().min(1).max(200),
    type: editorialTypeSchema.optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const createDraftSchema = z.object({
    title: z.string().min(1).max(200),
    slug: editorialSlugSchema,
    type: editorialTypeSchema,
    template: editorialTemplateSchema.default("standard"),
    templateData: editorialTemplateDataSchema.optional(),
})

export const updateWriterArticleSchema = z.object({
    title: z.string().min(1).max(200).optional(),
    slug: editorialSlugSchema.optional(),
    subtitle: z.string().max(300).nullable().optional(),
    excerpt: z.string().max(500).nullable().optional(),
    content: editorialContentSchema.optional(),
    template: editorialTemplateSchema.optional(),
    templateData: editorialTemplateDataSchema.optional(),
    coverImageUrl: z.string().url().nullable().optional(),
    coverImageAlt: z.string().max(200).nullable().optional(),
    coverImageCredit: z.string().max(200).nullable().optional(),
    tagSlugs: z.array(z.string().min(1).max(80)).max(20).optional(),
    metaTitle: z.string().max(200).nullable().optional(),
    metaDescription: z.string().max(300).nullable().optional(),
})

export const updateAdminArticleSchema = updateWriterArticleSchema.extend({
    type: editorialTypeSchema.optional(),
    isSponsored: z.boolean().optional(),
    sponsorName: z.string().max(120).nullable().optional(),
})

export const writerStatusSchema = z.enum(["active", "inactive", "suspended", "left"])

export const writerSlugSchema = editorialSlugSchema

export const writerSpecialtiesSchema = z.array(z.string().trim().min(1).max(50)).max(10).default([])

export const createWriterOnboardingSchema = z.object({
    slug: writerSlugSchema,
    displayName: z.string().trim().min(1).max(80).optional(),
    bio: z.string().trim().min(1).max(2000),
    specialties: writerSpecialtiesSchema.optional(),
    location: z.string().trim().max(120).nullable().optional(),
})

export const updateWriterOnboardingSchema = z.object({
    slug: writerSlugSchema.optional(),
    displayName: z.string().trim().min(1).max(80).nullable().optional(),
    bio: z.string().trim().min(1).max(2000).optional(),
    specialties: writerSpecialtiesSchema.optional(),
    location: z.string().trim().max(120).nullable().optional(),
    onboardingCompleted: z.boolean().optional(),
})

export const checkWriterSlugQuerySchema = z.object({
    slug: writerSlugSchema,
    excludeWriterId: z.string().min(1).optional(),
})

export const checkArticleSlugQuerySchema = z.object({
    slug: editorialSlugSchema,
    type: editorialTypeSchema,
    excludeArticleId: z.string().min(1).optional(),
})

export const reviewDecisionSchema = z.object({
    notes: z.string().max(5000).optional(),
})

export const rejectArticleSchema = z.object({
    reason: z.string().min(1).max(5000),
})

export const publishArticleSchema = z.object({
    publishedAt: z.string().datetime({ offset: true }).optional(),
})

export const engagementEventSchema = z.object({
    sessionId: z.string().min(1).max(128),
    referrer: z.string().max(500).nullable().optional(),
    engagedSeconds: z.coerce.number().int().min(15).max(86400),
    scrollDepth: z.coerce.number().int().min(1).max(100),
})

export const presignEditorialMediaSchema = z.object({
    editorialId: z.string().min(1).optional(),
    format: uploadImageFormatSchema.default("webp"),
})

export const updateAdminWriterProfileSchema = z.object({
    role: writerRoleSchema.optional(),
    bio: z.string().max(2000).nullable().optional(),
    displayName: z.string().trim().min(1).max(80).nullable().optional(),
    specialties: writerSpecialtiesSchema.optional(),
    location: z.string().trim().max(120).nullable().optional(),
    status: writerStatusSchema.optional(),
    isActive: z.boolean().optional(),
    slug: writerSlugSchema.optional(),
    internalNotes: z.string().max(5000).nullable().optional(),
    onboardingCompleted: z.boolean().optional(),
})

export const writerArticlesQuerySchema = z.object({
    status: editorialStatusSchema.optional(),
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const adminSubmissionsQuerySchema = z.object({
    status: z.enum(["submitted", "in_review", "approved", "all"]).default("all"),
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const adminArticlesQuerySchema = z.object({
    status: editorialStatusSchema.or(z.literal("all")).default("all"),
    cursor: z.string().optional(),
    limit: z.coerce.number().int().min(1).max(50).default(30),
})

export const analyticsQuerySchema = z.object({
    days: z.coerce.number().int().min(1).max(365).default(30),
})

const optionalIso = z
    .string()
    .trim()
    .optional()
    .nullable()
    .transform((value) => (value ? value : null))

export const addNewMusicPickSchema = z.object({
    appleSongId: z.string().trim().min(1).max(80),
    editorialId: z.string().trim().min(1).max(40).optional().nullable(),
    showFrom: optionalIso,
    showUntil: optionalIso,
})

export const updateNewMusicPickSchema = z.object({
    editorialId: z.string().trim().max(40).optional().nullable(),
    showFrom: optionalIso,
    showUntil: optionalIso,
})

export const reorderNewMusicPicksSchema = z.object({
    pickIds: z.array(z.string().min(1)).min(1).max(48),
})

export type ListArticlesQuerySchema = z.infer<typeof listArticlesQuerySchema>
export type CreateDraftSchema = z.infer<typeof createDraftSchema>
export type UpdateWriterArticleSchema = z.infer<typeof updateWriterArticleSchema>
export type UpdateAdminArticleSchema = z.infer<typeof updateAdminArticleSchema>
export type PublishArticleSchema = z.infer<typeof publishArticleSchema>
export type EngagementEventSchema = z.infer<typeof engagementEventSchema>
export type PresignEditorialMediaSchema = z.infer<typeof presignEditorialMediaSchema>
export type UpdateAdminWriterProfileSchema = z.infer<typeof updateAdminWriterProfileSchema>
export type CreateWriterOnboardingSchema = z.infer<typeof createWriterOnboardingSchema>
export type UpdateWriterOnboardingSchema = z.infer<typeof updateWriterOnboardingSchema>
export type AddNewMusicPickSchema = z.infer<typeof addNewMusicPickSchema>
export type UpdateNewMusicPickSchema = z.infer<typeof updateNewMusicPickSchema>
export type ReorderNewMusicPicksSchema = z.infer<typeof reorderNewMusicPicksSchema>
