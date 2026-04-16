// realtime websocket route

import { FastifyPluginAsync } from "fastify"
import { authenticateSessionToken } from "../../lib/auth.js"
import { addSocket, removeSocket } from "./socketManager.js"

const realtimeRoutes: FastifyPluginAsync = async (app) => {

    /** First arg is the `ws` WebSocket; second is FastifyRequest (@fastify/websocket v11). */
    app.get('/ws', { websocket: true }, async (socket, req) => {
        const token = req.cookies.session
        if (!token) {
            socket.close()
            return
        }
        const session = await authenticateSessionToken(token)
        if (!session) {
            socket.close()
            return
        }

        const userId = session.userId
        addSocket(userId, socket)

        socket.on('close', () => {
            removeSocket(userId, socket)
        })

        socket.on('message', (msg: Buffer) => {
            try {
                const raw = String(msg)
                const parsed = JSON.parse(raw) as { type?: unknown }
                if (parsed?.type === "ping") {
                    socket.send(
                        JSON.stringify({
                            type: "pong",
                            ts: Date.now(),
                        })
                    )
                }
            } catch {
                // ignore non-json messages
            }
        })
    })


}

export default realtimeRoutes