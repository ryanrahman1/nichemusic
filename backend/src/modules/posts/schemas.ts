import { z } from "zod"
import { baseMetadataSchema, successResponseSchema } from "../../global/schemas.js"
import { normalizeQueryDateTime } from "../../lib/datetime.js"

const cursorCreatedAtQuerySchema = z.preprocess(
  (value) => (typeof value === "string" && value.length > 0 ? normalizeQueryDateTime(value) : value),
  z.string().datetime({ offset: true }).optional()
)

export const postListQuerySchema = z.object({
  cursorCreatedAt: cursorCreatedAtQuerySchema,
  cursorId: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(50).default(20),
})

export const postKindSchema = z.enum([
  "text",
  "image",
  "video",
  "track",
  "pmo",
  "poll",
])

export const postVisibilitySchema = z.enum([
  "public",
  "private",
  "group",
])

export const uploadImageFormatSchema = z.enum([
  "jpeg",
  "webp",
  "png",
  "avif",
])

export const uploadVideoFormatSchema = z.enum([
  "mp4",
  "webm",
  "mov",
  "mkv",
])

export const postMediaInputSchema = z.object({
  kind: z.enum(["image", "video"]),
  objectKey: z.string().min(1),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
  duration_ms: z.number().int().positive().nullable().optional(),
})

export const pmoTemplateSchema = z.object({
  name: z.literal("pmo"),
  data: z.object({
    prompt: z.string().min(1).max(120),
    allow_track_replies: z.boolean().default(true),
  }),
})

export const pollOptionSchema = z.object({
  id: z.string().min(1).max(32),
  label: z.string().min(1).max(80),
})

export const pollTemplateSchema = z.object({
  name: z.literal("poll"),
  data: z.object({
    question: z.string().min(1).max(140),
    options: z.array(pollOptionSchema).min(2).max(6),
    multiple: z.boolean().default(false),
  }),
})

export const postTemplateSchema = z.union([
  pmoTemplateSchema,
  pollTemplateSchema,
])

export const postMetadataSchema = z
  .object({
    layout: z.string().optional(),
    source: z.string().optional(),
  })
  .catchall(z.unknown())

export const createPostContentInputSchema = z.object({
  version: z.literal(1).default(1),
  kind: postKindSchema,
  caption: z.string().max(2000).default(""),
  media: z.array(postMediaInputSchema).max(10).default([]),
  template: postTemplateSchema.nullable().optional().default(null),
  metadata: postMetadataSchema.default({}),
})

export const createPostSchema = z
  .object({
    postId: z.string().min(1),
    groupId: z.string().nullable().optional(),
    kind: postKindSchema,
    visibility: postVisibilitySchema.default("public"),
    trackId: z.string().nullable().optional(),
    nicheTrackId: z.string().nullable().optional(),
    content: createPostContentInputSchema,
  })
  .refine(
    (data) => !(data.trackId && data.nicheTrackId),
    { message: "Cannot attach both a catalog track and a niche track" }
  )

export const presignPostUploadSchema = z.discriminatedUnion("mediaKind", [
  z.object({
    postId: z.string().min(1).optional(),
    mediaKind: z.literal("image"),
    format: uploadImageFormatSchema,
  }),
  z.object({
    postId: z.string().min(1).optional(),
    mediaKind: z.literal("video"),
    format: uploadVideoFormatSchema,
  }),
])

export const createPostResultSchema = z.object({
  post: z.object({
    id: z.string(),
    owner_id: z.string(),
    group_id: z.string().nullable(),
    kind: postKindSchema,
    track_id: z.string().nullable(),
    niche_track_id: z.string().nullable(),
    visibility: postVisibilitySchema,
    like_count: z.number().int(),
    repost_count: z.number().int(),
    comment_count: z.number().int(),
    view_count: z.number().int(),
    has_media: z.boolean(),
    has_track: z.boolean(),
    has_sound: z.boolean(),
    content: z.unknown(),
    created_at: z.string(),
  }),
})

export const createPostResponseSchema = successResponseSchema(createPostResultSchema)

export const presignPostUploadResultSchema = z.object({
  postId: z.string(),
  upload: z.object({
    uploadUrl: z.url(),
    objectKey: z.string(),
    publicUrl: z.url(),
    contentType: z.string(),
    maxBytes: z.number().int().positive(),
  }),
})

export const presignPostUploadResponseSchema = successResponseSchema(
  presignPostUploadResultSchema
)

export type CreatePostSchema = z.infer<typeof createPostSchema>
export type CreatePostContentInputSchema = z.infer<typeof createPostContentInputSchema>
export type PresignPostUploadSchema = z.infer<typeof presignPostUploadSchema>


export const updatePostContentSchema = z.object({
  caption: z.string().max(2000).optional(),
  template: postTemplateSchema.nullable().optional(),
  metadata: postMetadataSchema.optional(),
})

export const updatePostSchema = z
  .object({
    visibility: postVisibilitySchema.optional(),
    trackId: z.string().nullable().optional(),
    nicheTrackId: z.string().nullable().optional(),
    content: updatePostContentSchema.optional(),
  })
  .refine(
    (data) => data.trackId === undefined || data.nicheTrackId === undefined || !(data.trackId && data.nicheTrackId),
    { message: "Cannot attach both a catalog track and a niche track" }
  )

export type UpdatePostSchema = z.infer<typeof updatePostSchema>

// comments

export const commentKindSchema = z.enum(["text", "track", "gif"])

export const commentGifSchema = z.object({
  id: z.string(),
  url: z.string().url(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
})

export const createTextCommentSchema = z.object({
  kind: z.literal("text"),
  text: z.string().min(1).max(1000),
  parentCommentId: z.string().nullable().optional(),
  replyToCommentId: z.string().nullable().optional(),
})

export const createTrackCommentSchema = z.object({
  kind: z.literal("track"),
  text: z.string().max(1000).optional().default(""),
  trackId: z.string(),
  parentCommentId: z.string().nullable().optional(),
  replyToCommentId: z.string().nullable().optional(),
})

export const createGifCommentSchema = z.object({
  kind: z.literal("gif"),
  text: z.string().max(1000).optional().default(""),
  gif: commentGifSchema,
  parentCommentId: z.string().nullable().optional(),
  replyToCommentId: z.string().nullable().optional(),
})

export const createCommentSchema = z.discriminatedUnion("kind", [
  createTextCommentSchema,
  createTrackCommentSchema,
  createGifCommentSchema,
])

export type CreateCommentSchema = z.infer<typeof createCommentSchema>

export const commentCursorSchema = z.object({
  createdAt: z.string(),
  id: z.string(),
})

export const listCommentsQuerySchema = z.object({
  cursor: z.string().optional(),
  limit: z.coerce.number().int().min(1).max(30).default(15),
})

export const commentOwnerSchema = z.object({
  id: z.string(),
  username: z.string(),
  avatar_url: z.string().nullable().optional(),
})

export const commentViewerSchema = z.object({
  is_owner: z.boolean(),
  is_liked: z.boolean(),
})

export const commentResultSchema = z.object({
  id: z.string(),
  post_id: z.string(),
  owner_id: z.string(),
  parent_comment_id: z.string().nullable(),
  reply_to_comment_id: z.string().nullable(),
  reply_to_user_id: z.string().nullable(),
  kind: commentKindSchema,
  content: z.unknown(),
  like_count: z.number().int(),
  reply_count: z.number().int(),
  is_hidden: z.boolean(),
  is_pinned: z.boolean(),
  created_at: z.string(),
  owner: commentOwnerSchema,
  viewer: commentViewerSchema,
})

export const commentListResultSchema = z.object({
  comments: z.array(commentResultSchema),
})

export const commentMutationResultSchema = z.object({
  message: z.string().optional(),
  commentId: z.string().optional(),
  liked: z.boolean().optional(),
  pinned: z.boolean().optional(),
  hidden: z.boolean().optional(),
})

export const commentPaginationMetadataSchema = baseMetadataSchema.extend({
  pagination: z.object({
    nextCursor: z.string().nullable(),
    limit: z.number().int().positive(),
    hasMore: z.boolean(),
  }),
})

export const listCommentsResponseSchema = successResponseSchema(
  commentListResultSchema,
  commentPaginationMetadataSchema
)

export const createCommentResponseSchema = successResponseSchema(commentMutationResultSchema)