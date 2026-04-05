import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"

/**
 * Minimal, unauthenticated metadata for link previews (OG) and share workers.
 * Does not include follower counts or PII beyond public names + artwork / preview URLs.
 */
const shareRoutes: FastifyPluginAsync = async (app) => {
    app.get("/artist/:id", async (req, res) => {
        const { id } = req.params as { id: string }

        const { data, error } = await supabase
            .schema("public")
            .from("artists")
            .select("id, name, image_url")
            .eq("id", id)
            .maybeSingle()

        if (error) return sendError(res, "SHARE_ARTIST_FETCH_FAILED", error.message, 500)
        if (!data) return sendError(res, "SHARE_ARTIST_NOT_FOUND", "Artist not found", 404)

        return sendSuccess(res, {
            name: data.name,
            image_url: data.image_url,
        })
    })

    app.get("/track/:id", async (req, res) => {
        const { id } = req.params as { id: string }

        const { data, error } = await supabase
            .schema("public")
            .from("tracks")
            .select("id, name, artwork_url, preview_url")
            .eq("id", id)
            .maybeSingle()

        if (error) return sendError(res, "SHARE_TRACK_FETCH_FAILED", error.message, 500)
        if (!data) return sendError(res, "SHARE_TRACK_NOT_FOUND", "Track not found", 404)

        return sendSuccess(res, {
            name: data.name,
            artwork_url: data.artwork_url,
            preview_url: data.preview_url,
        })
    })
}

export default shareRoutes
