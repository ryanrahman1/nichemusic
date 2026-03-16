import type { FastifyPluginAsync } from "fastify"
import { sendError, sendSuccess } from "../../global/response.js"
import { logImpression, logProfileOpen, logSkip, logView } from "../../lib/feed.js"
import { getHomeFeed } from "./service.js"
import { feedImpressionSchema, feedOpenProfileSchema, feedQuerySchema, feedSkipSchema, feedViewSchema } from "./schemas.js"

const feedRoutes: FastifyPluginAsync = async (app) => {
    app.get("/feed/home", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { cursor, limit } = feedQuerySchema.parse(req.query)

        try {
            const result = await getHomeFeed({
                userId: req.userId,
                limit,
                cursor,
            })

            return sendSuccess(res, {
                items: result.items,
            }, {
                pagination: {
                    nextCursor: result.nextCursor,
                    limit,
                    hasMore: result.hasMore,
                },
            })
        } catch (error) {
            return sendError(res, "FEED_HOME_FETCH_FAILED", error instanceof Error ? error.message : "Failed to fetch home feed", 500)
        }
    })

    app.post("/feed/impression", { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = feedImpressionSchema.parse(req.body)

        try {
            await logImpression({
                userId: req.userId,
                entityType: parsedBody.entityType,
                entityId: parsedBody.entityId,
            })

            return sendSuccess(res, { logged: true })
        } catch (error) {
            return sendError(res, "FEED_IMPRESSION_LOG_FAILED", error instanceof Error ? error.message : "Failed to log impression", 500)
        }
    })

    app.post("/feed/view", { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = feedViewSchema.parse(req.body)

        try {
            await logView({
                userId: req.userId,
                entityType: parsedBody.entityType,
                entityId: parsedBody.entityId,
                watchTimeMs: parsedBody.watchTimeMs,
            })

            return sendSuccess(res, { logged: true })
        } catch (error) {
            return sendError(res, "FEED_VIEW_LOG_FAILED", error instanceof Error ? error.message : "Failed to log view", 500)
        }
    })

    app.post("/feed/skip", { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = feedSkipSchema.parse(req.body)

        try {
            await logSkip({
                userId: req.userId,
                entityType: parsedBody.entityType,
                entityId: parsedBody.entityId,
                watchTimeMs: parsedBody.watchTimeMs,
            })

            return sendSuccess(res, { logged: true })
        } catch (error) {
            return sendError(res, "FEED_SKIP_LOG_FAILED", error instanceof Error ? error.message : "Failed to log skip", 500)
        }
    })

    app.post("/feed/open-profile", { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = feedOpenProfileSchema.parse(req.body)

        try {
            await logProfileOpen({
                userId: req.userId,
                profileId: parsedBody.profileId,
            })

            return sendSuccess(res, { logged: true })
        } catch (error) {
            return sendError(res, "FEED_PROFILE_OPEN_LOG_FAILED", error instanceof Error ? error.message : "Failed to log profile open", 500)
        }
    })
}

export default feedRoutes