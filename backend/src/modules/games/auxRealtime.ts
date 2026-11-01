import { FastifyPluginAsync } from "fastify"
import { authenticateSessionToken } from "../../lib/auth.js"
import {
    registerAuxSocket,
    removeAuxSocket,
    subscribeAuxSocketToRoom,
    unregisterAuxSocket,
} from "./auxSocketManager.js"
import { assertActivePlayer, buildPlayersSyncPayload } from "./service.js"

const auxRealtimeRoutes: FastifyPluginAsync = async (app) => {
    app.get("/ws/aux", { websocket: true }, async (socket, req) => {
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
        registerAuxSocket(userId, socket)

        let joinedRoomId: string | null = null

        socket.on("close", () => {
            if (joinedRoomId) {
                removeAuxSocket(joinedRoomId, socket)
            }
            unregisterAuxSocket(socket)
        })

        socket.on("message", (msg: Buffer) => {
            try {
                const parsed = JSON.parse(String(msg)) as {
                    type?: unknown
                    roomId?: unknown
                }

                if (parsed?.type === "ping") {
                    socket.send(JSON.stringify({ type: "pong", ts: Date.now() }))
                    return
                }

                if (parsed?.type === "join" && typeof parsed.roomId === "string") {
                    const roomId = parsed.roomId

                    void (async () => {
                        try {
                            await assertActivePlayer(roomId, userId)
                        } catch {
                            socket.send(JSON.stringify({ type: "aux.error", code: "NOT_IN_ROOM" }))
                            return
                        }

                        if (joinedRoomId && joinedRoomId !== roomId) {
                            removeAuxSocket(joinedRoomId, socket)
                        }

                        joinedRoomId = roomId
                        subscribeAuxSocketToRoom(roomId, userId, socket)

                        try {
                            const sync = await buildPlayersSyncPayload(roomId)
                            socket.send(JSON.stringify({ type: "aux.joined", ...sync }))
                        } catch {
                            socket.send(
                                JSON.stringify({
                                    type: "aux.joined",
                                    roomId,
                                    playerCount: 0,
                                    players: [],
                                })
                            )
                        }
                    })()
                    return
                }

                if (parsed?.type === "leave") {
                    if (joinedRoomId) {
                        removeAuxSocket(joinedRoomId, socket)
                        joinedRoomId = null
                    }
                }
            } catch {
                // ignore bad packets
            }
        })
    })
}

export default auxRealtimeRoutes
