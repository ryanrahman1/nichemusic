import type { FastifyPluginAsync } from "fastify"
import { ZodError } from "zod"
import { sendError, sendSuccess } from "../../global/response.js"
import { legalSlugSchema } from "./schemas.js"
import { getActiveLegalDocument, listActiveLegalDocuments } from "./service.js"

const legalRoutes: FastifyPluginAsync = async (app) => {
    // active legal docs only — one row per slug
    app.get("/legal/documents", { preHandler: app.optionalAuthenticate }, async (_req, res) => {
        try {
            const documents = await listActiveLegalDocuments()
            res.header("Cache-Control", "public, max-age=60, stale-while-revalidate=300")
            return sendSuccess(res, { documents })
        } catch (error) {
            const message = error instanceof Error ? error.message : "Failed to load legal documents"
            return sendError(res, "LEGAL_LIST_FAILED", message, 500)
        }
    })

    app.get("/legal/documents/:slug", { preHandler: app.optionalAuthenticate }, async (req, res) => {
        try {
            const slug = legalSlugSchema.parse((req.params as { slug: string }).slug)
            const document = await getActiveLegalDocument(slug)
            res.header("Cache-Control", "public, max-age=60, stale-while-revalidate=300")
            return sendSuccess(res, { document })
        } catch (error) {
            if (error instanceof ZodError) {
                return sendError(res, "VALIDATION_ERROR", error.issues[0]?.message ?? "Invalid slug", 400)
            }
            const message = error instanceof Error ? error.message : "Failed to load legal document"
            if (message === "LEGAL_DOCUMENT_NOT_FOUND") {
                return sendError(res, "LEGAL_DOCUMENT_NOT_FOUND", "Legal document not found", 404)
            }
            return sendError(res, "LEGAL_FETCH_FAILED", message, 500)
        }
    })
}

export default legalRoutes
