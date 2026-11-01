import type { FastifyPluginAsync } from "fastify"
import { ZodError } from "zod"
import { sendError, sendSuccess } from "../../global/response.js"
import { generateRandomId } from "../../lib/auth.js"
import { getEditorialMediaPresignedUrl } from "../../lib/image.js"
import {
    addNewMusicPickSchema,
    adminArticlesQuerySchema,
    adminSubmissionsQuerySchema,
    analyticsQuerySchema,
    checkArticleSlugQuerySchema,
    checkWriterSlugQuerySchema,
    createDraftSchema,
    createWriterOnboardingSchema,
    engagementEventSchema,
    editorialSearchQuerySchema,
    listArticlesQuerySchema,
    listTypedArticlesQuerySchema,
    presignEditorialMediaSchema,
    publishArticleSchema,
    reorderNewMusicPicksSchema,
    rejectArticleSchema,
    reviewDecisionSchema,
    updateAdminArticleSchema,
    updateNewMusicPickSchema,
    updateAdminWriterProfileSchema,
    updateWriterArticleSchema,
    updateWriterOnboardingSchema,
    writerArticlesQuerySchema,
} from "./schemas.js"
import {
    mapServiceError,
    requireActiveWriter,
    requireAdminWriter,
    requireEditorWriter,
} from "./helpers.js"
import {
    addAdminNewMusicPick,
    approveArticle,
    archiveArticle,
    checkArticleSlugAvailability,
    checkWriterSlugAvailability,
    createDraftArticle,
    createWriterOnboarding,
    deleteWriterOnboarding,
    deleteAdminArticle,
    deleteAdminNewMusicPick,
    getAdminArticle,
    listAdminArticles,
    listAdminNewMusicPicks,
    getArticleAnalytics,
    getDeskAnalytics,
    getEditorialHome,
    getMyWriterProfile,
    getWriterWorkspace,
    getPublishedArticleBySlug,
    getPublishedArticleById,
    getWriterAnalytics,
    getWriterArticle,
    getPublicTagPage,
    getWriterPublicPage,
    listAdminSubmissions,
    listAllWriters,
    listMyArticles,
    listPublishedArticles,
    listWriterPublicArticles,
    publishArticle,
    rejectArticle,
    reorderAdminNewMusicPicks,
    requestChanges,
    searchPublishedArticles,
    startReview,
    submitArticle,
    selfPublishArticle,
    trackEngagement,
    updateAdminArticle,
    updateAdminNewMusicPick,
    updateWriterAdmin,
    updateWriterArticle,
    updateWriterOnboarding,
    withdrawArticle,
} from "./service.js"

function handleRouteError(res: Parameters<typeof sendError>[0], error: unknown) {
    if (error instanceof ZodError) {
        return sendError(
            res,
            "VALIDATION_ERROR",
            error.issues[0]?.message ?? "Invalid request",
            400
        )
    }

    const mapped = mapServiceError(error)
    return sendError(res, mapped.code, mapped.message, mapped.status)
}

const editorialRoutes: FastifyPluginAsync = async (app) => {
    // public reads
    app.get("/editorial/home", { preHandler: app.optionalAuthenticate }, async (_req, res) => {
        try {
            const home = await getEditorialHome()
            res.header("Cache-Control", "public, max-age=20, stale-while-revalidate=60")
            return sendSuccess(res, home)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/articles", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const query = listArticlesQuerySchema.parse(req.query)
            const page = await listPublishedArticles(query)

            return sendSuccess(res, { articles: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    // album reviews only — same credit/tag joins, no extra hops
    app.get("/editorial/reviews", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const query = listTypedArticlesQuerySchema.parse(req.query)
            const page = await listPublishedArticles({ ...query, type: "review" })
            res.header("Cache-Control", "public, max-age=20, stale-while-revalidate=60")
            return sendSuccess(res, { articles: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    // artist spotlights only — same card select w writer + tags baked in
    app.get("/editorial/spotlights", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const query = listTypedArticlesQuerySchema.parse(req.query)
            const page = await listPublishedArticles({ ...query, type: "spotlight" })
            res.header("Cache-Control", "public, max-age=20, stale-while-revalidate=60")
            return sendSuccess(res, { articles: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/articles/by-id/:id", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const { id } = req.params as { id: string }
            const article = await getPublishedArticleById(id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/articles/:slug", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const { slug } = req.params as { slug: string }
            const article = await getPublishedArticleBySlug(slug)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/writers/:slug", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const { slug } = req.params as { slug: string }
            const page = await getWriterPublicPage(slug)
            return sendSuccess(res, page)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get(
        "/editorial/writers/:slug/articles",
        { preHandler: app.optionalAuthenticate },
        async (req, res) => {
            try {
                const { slug } = req.params as { slug: string }
                const query = listArticlesQuerySchema.parse(req.query)
                const page = await listWriterPublicArticles(slug, query)

                return sendSuccess(res, { articles: page.items }, {
                    pagination: {
                        nextCursor: page.nextCursor,
                        limit: query.limit,
                        hasMore: page.hasMore,
                    },
                })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.get("/editorial/tags/:slug", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const { slug } = req.params as { slug: string }
            const page = await getPublicTagPage(slug)
            res.header("Cache-Control", "public, max-age=20, stale-while-revalidate=60")
            return sendSuccess(res, page)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/search", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const query = editorialSearchQuerySchema.parse(req.query)
            const results = await searchPublishedArticles(query)
            return sendSuccess(res, results)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post(
        "/editorial/articles/:id/engagement",
        { preHandler: app.optionalAuthenticate },
        async (req, res) => {
            try {
                const { id } = req.params as { id: string }
                const body = engagementEventSchema.parse(req.body)
                const viewerId = req.userId ?? null
                const result = await trackEngagement(id, viewerId, body)
                return sendSuccess(res, result, undefined, result.tracked ? 201 : 200)
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    // writer self-service
    app.get("/editorial/me", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const profile = await getMyWriterProfile(req.userId)
            return sendSuccess(res, profile)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/workspace", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const workspace = await getWriterWorkspace(req.userId)
            return sendSuccess(res, workspace)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/slug/check", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireActiveWriter(req.userId)
            const query = checkArticleSlugQuerySchema.parse(req.query)
            const result = await checkArticleSlugAvailability(
                query.slug,
                query.type,
                query.excludeArticleId
            )
            return sendSuccess(res, result)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/writer/slug/check", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const query = checkWriterSlugQuerySchema.parse(req.query)
            const result = await checkWriterSlugAvailability(
                query.slug,
                query.excludeWriterId
            )
            return sendSuccess(res, result)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/writer/create", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const body = createWriterOnboardingSchema.parse(req.body)
            const writer = await createWriterOnboarding(req.userId, body)
            return sendSuccess(res, { writer }, undefined, 201)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/writer/update", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const body = updateWriterOnboardingSchema.parse(req.body)
            const writer = await updateWriterOnboarding(req.userId, body)
            return sendSuccess(res, { writer })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/writer/delete", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await deleteWriterOnboarding(req.userId)
            return sendSuccess(res, { writer })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/articles", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const query = writerArticlesQuerySchema.parse(req.query)
            const page = await listMyArticles(writer, query)

            return sendSuccess(res, { articles: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/articles", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const body = createDraftSchema.parse(req.body)
            const article = await createDraftArticle(writer, body)
            return sendSuccess(res, { article }, undefined, 201)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/articles/:id", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { id } = req.params as { id: string }
            const article = await getWriterArticle(writer, id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/articles/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { id } = req.params as { id: string }
            const body = updateWriterArticleSchema.parse(req.body)
            const article = await updateWriterArticle(writer, id, body)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/articles/:id/submit", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { id } = req.params as { id: string }
            const article = await submitArticle(writer, id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/articles/:id/publish", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireEditorWriter(req.userId)
            const { id } = req.params as { id: string }
            const article = await selfPublishArticle(writer, id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/articles/:id/withdraw", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { id } = req.params as { id: string }
            const article = await withdrawArticle(writer, id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/analytics", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { days } = analyticsQuerySchema.parse(req.query)
            const analytics = await getWriterAnalytics(writer, days)
            return sendSuccess(res, { analytics })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/me/articles/:id/analytics", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const writer = await requireActiveWriter(req.userId)
            const { id } = req.params as { id: string }
            const { days } = analyticsQuerySchema.parse(req.query)
            const analytics = await getArticleAnalytics(writer, id, days)
            return sendSuccess(res, { analytics })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/me/media/upload", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireActiveWriter(req.userId)
            const body = presignEditorialMediaSchema.parse(req.body)
            const editorialId = body.editorialId ?? generateRandomId(16)
            const upload = await getEditorialMediaPresignedUrl(editorialId, body.format)

            return sendSuccess(res, {
                editorialId,
                upload,
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    // editor/admin review flow
    app.get("/editorial/admin/analytics", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const { days } = analyticsQuerySchema.parse(req.query)
            const analytics = await getDeskAnalytics(days)
            return sendSuccess(res, { analytics })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/admin/submissions", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const query = adminSubmissionsQuerySchema.parse(req.query)
            const page = await listAdminSubmissions(query)

            return sendSuccess(res, { submissions: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/admin/articles", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireAdminWriter(req.userId)
            const query = adminArticlesQuerySchema.parse(req.query)
            const page = await listAdminArticles(query)

            return sendSuccess(res, { articles: page.items }, {
                pagination: {
                    nextCursor: page.nextCursor,
                    limit: query.limit,
                    hasMore: page.hasMore,
                },
            })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/admin/articles/:id", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const actor = await requireEditorWriter(req.userId)
            const { id } = req.params as { id: string }
            const article = await getAdminArticle(actor, id)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/articles/:id/delete", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const actor = await requireAdminWriter(req.userId)
            const { id } = req.params as { id: string }
            const result = await deleteAdminArticle(actor, id)
            return sendSuccess(res, result)
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post(
        "/editorial/admin/articles/:id/start-review",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const article = await startReview(reviewer, id)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post(
        "/editorial/admin/articles/:id/request-changes",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const body = reviewDecisionSchema.parse(req.body ?? {})
                const article = await requestChanges(reviewer, id, body.notes)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post(
        "/editorial/admin/articles/:id/approve",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const body = reviewDecisionSchema.parse(req.body ?? {})
                const article = await approveArticle(reviewer, id, body.notes)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post(
        "/editorial/admin/articles/:id/reject",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const body = rejectArticleSchema.parse(req.body)
                const article = await rejectArticle(reviewer, id, body.reason)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post(
        "/editorial/admin/articles/:id/publish",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const body = publishArticleSchema.parse(req.body ?? {})
                const article = await publishArticle(reviewer, id, body)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post(
        "/editorial/admin/articles/:id/archive",
        { preHandler: app.authenticate },
        async (req, res) => {
            try {
                const reviewer = await requireEditorWriter(req.userId)
                const { id } = req.params as { id: string }
                const article = await archiveArticle(reviewer, id)
                return sendSuccess(res, { article })
            } catch (error) {
                return handleRouteError(res, error)
            }
        }
    )

    app.post("/editorial/admin/articles/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        try {
            const actor = await requireEditorWriter(req.userId)
            const { id } = req.params as { id: string }
            const body = updateAdminArticleSchema.parse(req.body)
            const article = await updateAdminArticle(actor, id, body)
            return sendSuccess(res, { article })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    // writer management (admin only)
    app.get("/editorial/admin/writers", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireAdminWriter(req.userId)
            const writers = await listAllWriters()
            return sendSuccess(res, { writers })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.get("/editorial/admin/new-music", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const picks = await listAdminNewMusicPicks()
            return sendSuccess(res, { picks })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/new-music", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const body = addNewMusicPickSchema.parse(req.body)
            const picks = await addAdminNewMusicPick(body)
            return sendSuccess(res, { picks })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/new-music/reorder", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const body = reorderNewMusicPicksSchema.parse(req.body)
            const picks = await reorderAdminNewMusicPicks(body)
            return sendSuccess(res, { picks })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/new-music/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const { id } = req.params as { id: string }
            const body = updateNewMusicPickSchema.parse(req.body)
            const picks = await updateAdminNewMusicPick(id, body)
            return sendSuccess(res, { picks })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/new-music/:id/delete", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireEditorWriter(req.userId)
            const { id } = req.params as { id: string }
            const picks = await deleteAdminNewMusicPick(id)
            return sendSuccess(res, { picks })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })

    app.post("/editorial/admin/writers/:id/update", { preHandler: app.authenticate }, async (req, res) => {
        try {
            await requireAdminWriter(req.userId)
            const { id } = req.params as { id: string }
            const body = updateAdminWriterProfileSchema.parse(req.body)
            const writer = await updateWriterAdmin(id, body)
            return sendSuccess(res, { writer })
        } catch (error) {
            return handleRouteError(res, error)
        }
    })
}

export default editorialRoutes
