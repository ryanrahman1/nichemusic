import { z } from "zod"

export const errorObjectSchema = z.object({
    code: z.string(),
    message: z.string(),
    details: z.unknown().optional(),
})

export const paginationMetadataSchema = z.object({
    cursor: z.string().nullable().optional(),
    nextCursor: z.string().nullable().optional(),
    limit: z.number().int().positive().optional(),
    hasMore: z.boolean().optional(),
})

export const baseMetadataSchema = z.object({
    apiVersion: z.string().default("1"),
    pagination: paginationMetadataSchema.optional(),
})

export const successResponseSchema = <
    TResult extends z.ZodTypeAny,
    TMetadata extends z.ZodTypeAny = typeof baseMetadataSchema
>(
    resultSchema: TResult,
    metadataSchema?: TMetadata
) =>
    z.object({
        success: z.literal(true),
        result: resultSchema,
        error: z.null().optional().default(null),
        metadata: (metadataSchema ?? baseMetadataSchema).optional(),
    })

export const errorResponseSchema = <
    TMetadata extends z.ZodTypeAny = typeof baseMetadataSchema
>(
    metadataSchema?: TMetadata
) =>
    z.object({
        success: z.literal(false),
        result: z.null().optional().default(null),
        error: errorObjectSchema,
        metadata: (metadataSchema ?? baseMetadataSchema).optional(),
    })

export const apiResponseSchema = <
    TResult extends z.ZodTypeAny,
    TMetadata extends z.ZodTypeAny = typeof baseMetadataSchema
>(
    resultSchema: TResult,
    metadataSchema?: TMetadata
) =>
    z.union([
        successResponseSchema(resultSchema, metadataSchema),
        errorResponseSchema(metadataSchema),
    ])

export type ErrorObject = z.infer<typeof errorObjectSchema>