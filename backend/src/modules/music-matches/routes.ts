import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from "fastify"
import { supabase } from "../../config/supabase.js"
import env from "../../config/env.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { matchIdParamsSchema, respondMatchSchema } from "./schemas.js"
import {
    buildMatchCheckPayload,
    createOrGetDirectConversation,
} from "./helpers.js"
import { generateMatches } from "./generation.js"

type MusicMatchRow = {
    id: string
    user_a_id: string
    user_b_id: string
    score: number
    reason_json: Record<string, unknown>
    status: string
    user_a_seen_at: string | null
    user_b_seen_at: string | null
    user_a_responded_at: string | null
    user_b_responded_at: string | null
    expires_at: string
}

function requireCronSecret(req: FastifyRequest, res: FastifyReply): boolean {
    const secret = req.headers["x-cron-secret"]
    if (!env.cronSecret || typeof secret !== "string" || secret !== env.cronSecret) {
        sendError(res, "CRON_UNAUTHORIZED", "Unauthorized", 401)
        return false
    }
    return true
}

function otherUserId(match: MusicMatchRow, userId: string) {
    return match.user_a_id === userId ? match.user_b_id : match.user_a_id
}

function isUserA(match: MusicMatchRow, userId: string) {
    return match.user_a_id === userId
}

const PROFILE_SELECT = "id, username, display_name, avatar_url, is_verified, verification_type"

async function loadMatchPayloadForUser(match: MusicMatchRow, userId: string) {
    const otherId = otherUserId(match, userId)
    const { data: profile, error: profileErr } = await supabase
        .schema("public")
        .from("profiles")
        .select(PROFILE_SELECT)
        .eq("id", otherId)
        .maybeSingle()

    if (profileErr) throw new Error(profileErr.message)
    if (!profile) return null

    const viewerRespondedField = isUserA(match, userId) ? "user_a_responded_at" : "user_b_responded_at"
    const otherRespondedField = isUserA(match, userId) ? "user_b_responded_at" : "user_a_responded_at"
    const declinedByUserId =
        typeof match.reason_json?.declinedByUserId === "string"
            ? match.reason_json.declinedByUserId
            : null

    return buildMatchCheckPayload({
        id: match.id,
        score: match.score,
        reason_json: match.reason_json,
        expires_at: match.expires_at,
        status: match.status,
        otherUser: profile,
        viewerHasResponded: !!match[viewerRespondedField],
        otherHasResponded: !!match[otherRespondedField],
        declinedByUserId,
    })
}

const musicMatchesRoutes: FastifyPluginAsync = async (app) => {
    app.get("/music-matches/check", { preHandler: app.authenticate }, async (req, res) => {
        const userId = req.userId
        const now = new Date().toISOString()

        const { data: matches, error } = await supabase
            .schema("public")
            .from("music_matches")
            .select("*")
            .eq("status", "pending")
            .gt("expires_at", now)
            .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
            .order("created_at", { ascending: false })
            .limit(1)

        if (error) return sendError(res, "MATCH_CHECK_FAILED", error.message, 500)

        const match = (matches?.[0] ?? null) as MusicMatchRow | null
        if (!match) {
            return sendSuccess(res, { match: null })
        }

        const viewerRespondedField = isUserA(match, userId) ? "user_a_responded_at" : "user_b_responded_at"
        if (match[viewerRespondedField]) {
            return sendSuccess(res, { match: null })
        }

        const seenField = isUserA(match, userId) ? "user_a_seen_at" : "user_b_seen_at"
        if (!match[seenField]) {
            const { error: seenErr } = await supabase
                .schema("public")
                .from("music_matches")
                .update({ [seenField]: now })
                .eq("id", match.id)
            if (seenErr) return sendError(res, "MATCH_CHECK_FAILED", seenErr.message, 500)
        }

        try {
            const payload = await loadMatchPayloadForUser(match, userId)
            if (!payload) return sendError(res, "MATCH_CHECK_FAILED", "Matched user not found", 500)
            return sendSuccess(res, { match: payload })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load match"
            return sendError(res, "MATCH_CHECK_FAILED", message, 500)
        }
    })

    app.get("/music-matches/latest", { preHandler: app.authenticate }, async (req, res) => {
        const userId = req.userId

        const { data: matches, error } = await supabase
            .schema("public")
            .from("music_matches")
            .select("*")
            .or(`user_a_id.eq.${userId},user_b_id.eq.${userId}`)
            .order("created_at", { ascending: false })
            .limit(1)

        if (error) return sendError(res, "MATCH_LATEST_FAILED", error.message, 500)

        const match = (matches?.[0] ?? null) as MusicMatchRow | null
        if (!match) {
            return sendSuccess(res, { match: null })
        }

        try {
            const payload = await loadMatchPayloadForUser(match, userId)
            if (!payload) return sendError(res, "MATCH_LATEST_FAILED", "Matched user not found", 500)
            return sendSuccess(res, { match: payload })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load match"
            return sendError(res, "MATCH_LATEST_FAILED", message, 500)
        }
    })

    app.post("/music-matches/:id/respond", { preHandler: app.authenticate }, async (req, res) => {
        const userId = req.userId
        const { id } = matchIdParamsSchema.parse(req.params)
        const { action } = respondMatchSchema.parse(req.body)
        const now = new Date().toISOString()

        const { data: match, error } = await supabase
            .schema("public")
            .from("music_matches")
            .select("*")
            .eq("id", id)
            .maybeSingle()

        if (error) return sendError(res, "MATCH_RESPOND_FAILED", error.message, 500)
        if (!match) return sendError(res, "MATCH_NOT_FOUND", "Match not found", 404)

        const row = match as MusicMatchRow
        if (row.user_a_id !== userId && row.user_b_id !== userId) {
            return sendError(res, "MATCH_FORBIDDEN", "You are not part of this match", 403)
        }
        if (row.status !== "pending") {
            return sendError(res, "MATCH_NOT_PENDING", "This match is no longer active", 400)
        }
        if (new Date(row.expires_at).getTime() <= Date.now()) {
            return sendError(res, "MATCH_EXPIRED", "This match has expired", 400)
        }

        const respondedField = isUserA(row, userId) ? "user_a_responded_at" : "user_b_responded_at"
        const otherRespondedField = isUserA(row, userId) ? "user_b_responded_at" : "user_a_responded_at"

        if (action === "decline") {
            const { error: declineErr } = await supabase
                .schema("public")
                .from("music_matches")
                .update({
                    status: "declined",
                    [respondedField]: now,
                    reason_json: {
                        ...row.reason_json,
                        declinedByUserId: userId,
                    },
                })
                .eq("id", id)
            if (declineErr) return sendError(res, "MATCH_RESPOND_FAILED", declineErr.message, 500)
            return sendSuccess(res, { success: true })
        }

        const otherAlreadyAccepted = !!row[otherRespondedField]
        const patch: Record<string, unknown> = {
            [respondedField]: now,
        }
        if (otherAlreadyAccepted) {
            patch.status = "accepted"
        }

        const { error: acceptErr } = await supabase
            .schema("public")
            .from("music_matches")
            .update(patch)
            .eq("id", id)
        if (acceptErr) return sendError(res, "MATCH_RESPOND_FAILED", acceptErr.message, 500)

        if (!otherAlreadyAccepted) {
            return sendSuccess(res, { accepted: false })
        }

        const otherId = otherUserId(row, userId)
        try {
            const { conversation } = await createOrGetDirectConversation(userId, otherId)
            return sendSuccess(res, { accepted: true, conversation })
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to create conversation"
            return sendError(res, "CONVERSATION_CREATE_FAILED", message, 500)
        }
    })

    app.post("/internal/cron/music-matches/generate", async (req, res) => {
        if (!requireCronSecret(req, res)) return

        try {
            const result = await generateMatches()
            return sendSuccess(res, result)
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to generate matches"
            return sendError(res, "MATCH_GENERATE_FAILED", message, 500)
        }
    })
}

export default musicMatchesRoutes
