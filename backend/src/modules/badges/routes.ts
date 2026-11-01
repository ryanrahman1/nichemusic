import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { badgeHoldersQuerySchema } from "./schemas.js"
import { decodeBadgeHolderCursor, encodeBadgeHolderCursor } from "./helpers.js"

const BADGE_HOLDER_SELECT = `
    user_id,
    index,
    profile:profiles!profile_badges_user_id_fkey(
        id,
        username,
        display_name,
        avatar_url,
        is_verified,
        verification_type
    )
`

const badgesRoutes: FastifyPluginAsync = async (app) => {
    app.get("/badges/:badgeId", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { badgeId } = req.params as { badgeId: string }

        const [{ data: badge, error: badgeError }, { count, error: countError }] = await Promise.all([
            supabase
                .schema("public")
                .from("badges")
                .select("id, text, color_hex, created_at")
                .eq("id", badgeId)
                .maybeSingle(),
            supabase
                .schema("public")
                .from("profile_badges")
                .select("*", { count: "exact", head: true })
                .eq("badge_id", badgeId),
        ])

        if (badgeError) {
            return sendError(res, "BADGE_FETCH_FAILED", badgeError.message, 500)
        }

        if (countError) {
            return sendError(res, "BADGE_HOLDERS_COUNT_FAILED", countError.message, 500)
        }

        if (!badge) {
            return sendError(res, "BADGE_NOT_FOUND", "Badge not found", 404)
        }

        return sendSuccess(res, {
            badge: {
                id: badge.id,
                text: badge.text,
                colorHex: badge.color_hex,
                createdAt: badge.created_at,
                holderCount: count ?? 0,
            },
        })
    })

    app.get("/badges/:badgeId/holders", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { badgeId } = req.params as { badgeId: string }
        const { limit, cursor } = badgeHoldersQuerySchema.parse(req.query)
        const decodedCursor = decodeBadgeHolderCursor(cursor)

        const { data: badge, error: badgeError } = await supabase
            .schema("public")
            .from("badges")
            .select("id")
            .eq("id", badgeId)
            .maybeSingle()

        if (badgeError) {
            return sendError(res, "BADGE_FETCH_FAILED", badgeError.message, 500)
        }

        if (!badge) {
            return sendError(res, "BADGE_NOT_FOUND", "Badge not found", 404)
        }

        let query = supabase
            .schema("public")
            .from("profile_badges")
            .select(BADGE_HOLDER_SELECT)
            .eq("badge_id", badgeId)
            .order("index", { ascending: true })
            .order("user_id", { ascending: true })
            .limit(limit + 1)

        if (decodedCursor) {
            query = query.or(
                `index.gt.${decodedCursor.index},and(index.eq.${decodedCursor.index},user_id.gt.${decodedCursor.userId})`
            )
        }

        const { data, error } = await query

        if (error) {
            return sendError(res, "BADGE_HOLDERS_FETCH_FAILED", error.message, 500)
        }

        const rows = data ?? []
        const hasMore = rows.length > limit
        const pageRows = hasMore ? rows.slice(0, limit) : rows
        const lastRow = pageRows.at(-1)

        const holders = pageRows
            .map((row) => {
                const profile = Array.isArray(row.profile) ? row.profile[0] : row.profile
                if (!profile) return null

                return {
                    userId: row.user_id,
                    badgeIndex: row.index,
                    username: profile.username,
                    displayName: profile.display_name,
                    avatarUrl: profile.avatar_url,
                    isVerified: profile.is_verified,
                    verificationType: profile.verification_type,
                }
            })
            .filter(Boolean)

        return sendSuccess(res, { holders }, {
            pagination: {
                limit,
                hasMore,
                nextCursor: hasMore && lastRow
                    ? encodeBadgeHolderCursor({ index: lastRow.index, userId: lastRow.user_id })
                    : null,
            },
        })
    })
}

export default badgesRoutes
