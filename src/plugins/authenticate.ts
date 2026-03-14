import fp from 'fastify-plugin'
import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify'
import { authenticateSessionToken } from "../lib/auth.js"


declare module 'fastify' {
    interface FastifyInstance {
        authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>
        requireAdmin: (req: FastifyRequest, reply: FastifyReply) => Promise<void>
    }
    interface FastifyRequest {
        userId: string
        sessionId: string
    }
}

const authenticatePlugin: FastifyPluginAsync = async (app) => {
    app.decorate("authenticate", async (req: FastifyRequest, rep: FastifyReply) => {
        const token = req.cookies.session
        if (!token) {
            return rep.code(401).send({ error: "Unauthorized" })
        }

        const session = await authenticateSessionToken(token)
        if (!session) {
            return rep.code(401).send({ error: "Unauthorized" })
        }

        req.userId = session.userId
        req.sessionId = session.sessionId
    })
}

export default fp(authenticatePlugin)