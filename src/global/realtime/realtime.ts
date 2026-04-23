// realtime websocket route

import { FastifyPluginAsync } from "fastify"
import { authenticateSessionToken } from "../../lib/auth.js"
import { supabase } from "../../config/supabase.js"
import { addSocket, emitToUser, removeSocket } from "./socketManager.js"

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
                const parsed = JSON.parse(raw) as {
                    type?: unknown
                    conversationId?: unknown
                    messageId?: unknown
                    isTyping?: unknown
                }
                if (parsed?.type === "ping") {
                    socket.send(
                        JSON.stringify({
                            type: "pong",
                            ts: Date.now(),
                        })
                    )
                    return
                }

                if (
                    parsed?.type === "typing" &&
                    typeof parsed.conversationId === "string"
                ) {
                    const conversationId = parsed.conversationId
                    const isTyping = parsed.isTyping === true

                    void (async () => {
                        const { data: members, error } = await supabase
                            .from('conversation_members')
                            .select('user_id')
                            .eq('conversation_id', conversationId)
                        if (error || !members?.some((m) => m.user_id === userId)) return

                        const { data: profile } = await supabase
                            .from('profiles')
                            .select('username')
                            .eq('id', userId)
                            .maybeSingle()
                        const username =
                            typeof profile?.username === "string" ? profile.username : null

                        const event = {
                            type: "typing",
                            conversationId,
                            userId,
                            username,
                            isTyping,
                            at: new Date().toISOString(),
                        }

                        for (const member of members) {
                            if (member.user_id === userId) continue
                            emitToUser(member.user_id, event)
                        }
                    })()
                    return
                }

                if (
                    parsed?.type === "message.delivered" &&
                    typeof parsed.conversationId === "string" &&
                    typeof parsed.messageId === "string"
                ) {
                    const conversationId = parsed.conversationId
                    const messageId = parsed.messageId

                    void (async () => {
                        const { data: members, error } = await supabase
                            .from('conversation_members')
                            .select('user_id')
                            .eq('conversation_id', conversationId)
                        if (error || !members?.some((m) => m.user_id === userId)) return

                        const { data: message, error: messageError } = await supabase
                            .from('messages')
                            .select('sender_id')
                            .eq('id', messageId)
                            .eq('conversation_id', conversationId)
                            .maybeSingle()
                        if (messageError || !message?.sender_id) return
                        if (message.sender_id === userId) return

                        emitToUser(message.sender_id, {
                            type: "message.delivered",
                            conversationId,
                            messageId,
                            deliveredByUserId: userId,
                            at: new Date().toISOString(),
                        })
                    })()
                }
            } catch {
                // ignore non-json messages
            }
        })
    })


}

export default realtimeRoutes