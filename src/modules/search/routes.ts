import { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { searchProfilesQuerySchema } from "./schemas.js"
import { sendError, sendSuccess } from "../../global/response.js"

const searchRoutes: FastifyPluginAsync = async (app) => {
    app.get('/search/users', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { q, limit, cursorScore, cursorId } = searchProfilesQuerySchema.parse(req.query)

        const { data, error } = await supabase.rpc("search_profiles", {
            query_text: q,
            page_limit: limit,
            cursor_score: cursorScore ?? null,
            cursor_id: cursorId ?? null,
        })

        if (error) return sendError(res, "USER_SEARCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const users = hasMore ? rows.slice(0, limit) : rows
        const last = users.at(-1)

        return sendSuccess(res, { users }, {
            pagination: {
                nextCursor: hasMore && last ? JSON.stringify({ cursorScore: last.score, cursorId: last.id }) : null,
                limit,
                hasMore,
            },
        })
    })
}

export default searchRoutes