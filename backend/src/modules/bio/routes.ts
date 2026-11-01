import type { FastifyPluginAsync } from "fastify"
import { sendError, sendSuccess } from "../../global/response.js"
import { fetchBioPageData } from "./service.js"

// public link-in-bio page data
const bioRoutes: FastifyPluginAsync = async (app) => {
    app.get("/", async (_req, res) => {
        try {
            const data = await fetchBioPageData()
            return sendSuccess(res, data)
        } catch (e) {
            const message = e instanceof Error ? e.message : "Failed to load bio page"
            return sendError(res, "BIO_FETCH_FAILED", message, 500)
        }
    })
}

export default bioRoutes
