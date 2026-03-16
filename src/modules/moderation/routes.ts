import { FastifyPluginAsync } from "fastify"
import { createReportSchema, CreateReportSchema } from "./schemas.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { supabase } from "../../config/supabase.js"
import { generateRandomId } from "../../lib/auth.js"

const moderationRoutes: FastifyPluginAsync = async (app) => {

    app.post('/reports/create', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody: CreateReportSchema = createReportSchema.parse(req.body)
        const reportId = generateRandomId(16)
        const { data, error } = await supabase.schema("public").from("reports").insert({
            id: reportId,
            reporter_id: parsedBody.reporterId,
            target_type: parsedBody.targetType,
            target_id: parsedBody.targetId,
            content: parsedBody.content,
            status: parsedBody.status,
            priority: parsedBody.priority,
        })
        if (error) return sendError(res, "REPORT_CREATE_FAILED", error.message, 500)
        return sendSuccess(res, { report: data })
    })

}

export default moderationRoutes