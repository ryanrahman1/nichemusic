import type { FastifyReply } from "fastify"

export function sendSuccess(
    reply: FastifyReply,
    result: unknown,
    metadata?: Record<string, unknown>,
    statusCode = 200
) {
    return reply.status(statusCode).send({
        success: true,
        result,
        error: null,
        metadata: {
            apiVersion: "2",
            recommendedAppVersion: "2.0.0",
            ...(metadata ?? {}),
        },
    })
}

export function sendError(
    reply: FastifyReply,
    code: string,
    message: string,
    statusCode = 400,
    details?: unknown,
    metadata?: Record<string, unknown>
) {
    return reply.status(statusCode).send({
        success: false,
        result: null,
        error: {
            code,
            message,
            ...(details !== undefined ? { details } : {}),
        },
        metadata: {
            apiVersion: "2",
            recommendedAppVersion: "2.0.0",
            ...(metadata ?? {}),
        },
    })
}