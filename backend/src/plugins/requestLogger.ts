import fp from "fastify-plugin"
import type { FastifyPluginAsync } from "fastify"

const requestLoggerPlugin: FastifyPluginAsync = async (app) => {
    app.addHook("onRequest", async (req) => {
        req.log.info({
            tag: "REQ",
            reqId: req.id,
            method: req.method,
            url: req.url,
            ip: req.ip,
            userId: req.userId ?? null,
        }, "request started")
    })

    app.addHook("onResponse", async (req, reply) => {
        const time = reply.elapsedTime

        req.log.info({
            tag: "RES",
            reqId: req.id,
            method: req.method,
            url: req.url,
            status: reply.statusCode,
            responseTimeMs: Number(time.toFixed(1)),
            ip: req.ip,
            userId: req.userId ?? null,
        }, "request completed")
    })

    app.addHook("onError", async (req, reply, error) => {
        req.log.error({
            tag: "ERR",
            reqId: req.id,
            method: req.method,
            url: req.url,
            status: reply.statusCode,
            ip: req.ip,
            userId: req.userId ?? null,
            errorName: error.name,
            errorMessage: error.message,
            stack: error.stack,
        }, "request failed")
    })
}

export default fp(requestLoggerPlugin)