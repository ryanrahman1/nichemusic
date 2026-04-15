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

        socket.on('message', (_msg: Buffer) => {
            // whtv
        })
    })


}

export default realtimeRoutes