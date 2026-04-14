// realtime websocket route

import { FastifyPluginAsync } from "fastify"
import { authenticateSessionToken } from "../../lib/auth.js"
import { addSocket, removeSocket } from "./socketManager.js"

const realtimeRoutes: FastifyPluginAsync = async (app) => {

    app.get('/ws', { websocket: true}, async (connection: any, req) => {
        const socket = connection.socket
        const token = req.cookies.session
        if (!token) {
            connection.close()
            return
        }
        const session = await authenticateSessionToken(token)
        if (!session) {
            connection.close()
            return
        }

        const userId = session.userId
        addSocket(userId, socket)

        socket.on('close', () => {
            removeSocket(userId, socket)
        })

        socket.on('message', (msg: Buffer) => {
            // whtv

        })

    })


}