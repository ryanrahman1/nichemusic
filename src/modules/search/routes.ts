import { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { getOrSetCachedValue } from "../../lib/ttlCache.js"
import { discoverHomeQuerySchema, globalSearchQuerySchema, parseSearchFilterTypes, searchProfilesQuerySchema } from "./schemas.js"
import { sendError, sendSuccess } from "../../global/response.js"

const DISCOVER_HOME_CACHE_TTL_MS = 90_000

const searchRoutes: FastifyPluginAsync = async (app) => {
    app.get('/discover', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { sectionLimit } = discoverHomeQuerySchema.parse(req.query)
        const viewerId = req.userId ?? null
        const cacheKey = `${viewerId ?? "anonymous"}:${sectionLimit}`

        try {
            const data = await getOrSetCachedValue({
                namespace: "discover:home",
                key: cacheKey,
                ttlMs: DISCOVER_HOME_CACHE_TTL_MS,
                loader: async () => {
                    const { data, error } = await supabase.schema("public").rpc("get_discover_home", {
                        viewer_id_arg: viewerId,
                        section_limit: sectionLimit,
                    })

                    if (error) throw new Error(error.message)
                    return data
                },
            })

            res.header("Cache-Control", viewerId ? "private, max-age=60" : "public, max-age=90")
            return sendSuccess(res, data ?? {
                generatedAt: new Date().toISOString(),
                limitPerSection: sectionLimit,
                sections: {
                    forYou: [],
                    trendingNicheTracks: [],
                    newNicheReleases: [],
                    featuredPlaylists: [],
                    artistSpotlight: null,
                    popularProfiles: [],
                    recentPosts: [],
                    badgesCommunitiesChallenges: [],
                },
            })
        } catch (error) {
            const message = error instanceof Error ? error.message : "Discover home failed"
            return sendError(res, "DISCOVER_HOME_FAILED", message, 500)
        }
    })

    app.get('/search/suggestions', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { q, limit, types } = globalSearchQuerySchema.parse(req.query)
        const filterTypes = parseSearchFilterTypes(types)
        const limitCount = limit ?? 12

        const { data, error } = await supabase.schema("public").rpc("global_search_suggestions", {
            query_text: q,
            filter_types: filterTypes,
            limit_count: limitCount,
        })

        if (error) {
            return sendError(res, "SEARCH_SUGGESTIONS_FAILED", error.message, 500)
        }

        return sendSuccess(res, data ?? { query: q, suggestions: [] })
    })

    app.get('/search', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { q, perTypeLimit, types } = globalSearchQuerySchema.parse(req.query)
        const filterTypes = parseSearchFilterTypes(types)
        const perTypeLimitCount = perTypeLimit ?? 10

        const { data, error } = await supabase.schema("public").rpc("global_search", {
            query_text: q,
            filter_types: filterTypes,
            per_type_limit: perTypeLimitCount,
        })

        if (error) {
            return sendError(res, "SEARCH_FAILED", error.message, 500)
        }

        return sendSuccess(res, data ?? {
            query: q,
            results: {
                nicheTracks: [],
                tracks: [],
                albums: [],
                playlists: [],
                profiles: [],
                artists: [],
                posts: [],
                badges: [],
            },
        })
    })

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