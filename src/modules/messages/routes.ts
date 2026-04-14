// messages routes

// core flow: user sends message via post message; server receives message, puts in database, and checks if anyone from conversation_members table is connected to the websocket; if so, send the message payload to them; if not, then queue push notification for all conversation members; websocket is hosted in this server


import { FastifyPluginAsync } from "fastify"
import { createMessageSchema, markConversationAsReadSchema, getConversationParamsSchema, getConversationQuerySchema, ensureDmSchema } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { emitToUser, hasActiveSocket } from "../../global/realtime/socketManager.js"

async function requireConversationMembership(conversationId: string, userId: string) {
    const { data, error } = await supabase
        .from('conversation_members')
        .select('conversation_id')
        .eq('conversation_id', conversationId)
        .eq('user_id', userId)
        .maybeSingle()

    if (error) throw error
    if (!data) return false

    return true
}

function uniqueStrings(values: Array<string | null | undefined>) {
    return [...new Set(values.filter((v): v is string => Boolean(v)))]
}

async function findDirectConversationId(userA: string, userB: string): Promise<string | null> {
    const { data: mine, error } = await supabase
        .from("conversation_members")
        .select("conversation_id")
        .eq("user_id", userA)
    if (error || !mine?.length) return null
    const convIds = [...new Set(mine.map((m) => m.conversation_id))]
    const { data: members, error: mErr } = await supabase
        .from("conversation_members")
        .select("conversation_id, user_id")
        .in("conversation_id", convIds)
    if (mErr || !members) return null
    const byConv = new Map<string, Set<string>>()
    for (const row of members) {
        if (!byConv.has(row.conversation_id)) byConv.set(row.conversation_id, new Set())
        byConv.get(row.conversation_id)!.add(row.user_id)
    }
    for (const [cid, set] of byConv) {
        if (set.size === 2 && set.has(userA) && set.has(userB)) return cid
    }
    return null
}

async function assertFriendship(actorId: string, otherUserId: string): Promise<boolean> {
    const { data, error } = await supabase
        .schema("public")
        .from("friends")
        .select("user_a_id, user_b_id")
        .or(`user_a_id.eq.${actorId},user_b_id.eq.${actorId}`)
    if (error || !data) return false
    return data.some(
        (r) =>
            (r.user_a_id === actorId && r.user_b_id === otherUserId) ||
            (r.user_b_id === actorId && r.user_a_id === otherUserId)
    )
}

const messagesRoutes: FastifyPluginAsync = async (app) => {
    app.post("/messages/dm/ensure", { preHandler: app.authenticate }, async (req, res) => {
        const { otherUserId } = ensureDmSchema.parse(req.body)
        if (otherUserId === req.userId) {
            return sendError(res, "DM_INVALID", "Cannot open a conversation with yourself", 400)
        }
        const okFriend = await assertFriendship(req.userId, otherUserId)
        if (!okFriend) {
            return sendError(res, "DM_FORBIDDEN", "You can only message friends", 403)
        }
        const existing = await findDirectConversationId(req.userId, otherUserId)
        if (existing) {
            return sendSuccess(res, { conversationId: existing, created: false })
        }
        const conversationId = generateRandomId(12)
        const { error: cErr } = await supabase.from("conversations").insert({ id: conversationId })
        if (cErr) return sendError(res, "DM_CREATE_FAILED", cErr.message, 500)
        const { error: memErr } = await supabase.from("conversation_members").insert([
            { conversation_id: conversationId, user_id: req.userId },
            { conversation_id: conversationId, user_id: otherUserId },
        ])
        if (memErr) {
            await supabase.from("conversations").delete().eq("id", conversationId)
            return sendError(res, "DM_CREATE_FAILED", memErr.message, 500)
        }
        return sendSuccess(res, { conversationId, created: true })
    })

    app.post('/messages/create', { preHandler: app.authenticate }, async (req, res) => {
        // create message, send to somebody

        const parsedBody = createMessageSchema.parse(req.body)
        const messageId = generateRandomId(16)
        const { conversationId, replyToMessageId, clientId } = parsedBody
        const kind = parsedBody.kind


        // verify membership
        const { data: member, error: memberError } = await supabase.from('conversation_members').select('conversation_id').eq('conversation_id', conversationId).eq('user_id', req.userId).maybeSingle()

        if (memberError) return sendError(res, "MESSAGE_CREATE_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "MESSAGE_CREATE_FAILED", "You are not a member of this conversation", 403)

        let content: Record<string, unknown>

        let textPlain: string | null = null


        switch (kind) {
            case 'text':
                content = {
                    text: parsedBody.text,
                }
                textPlain = parsedBody.text
                break

            case 'track_share':
                content = {
                    trackId: parsedBody.trackId,
                    caption: parsedBody.caption,
                }
                textPlain = parsedBody.caption ?? null
                break

            case 'album_share':
                content = {
                    albumId: parsedBody.albumId,
                    caption: parsedBody.caption,
                }
                textPlain = parsedBody.caption ?? null
                break

            case 'artist_share':
                content = {
                    artistId: parsedBody.artistId,
                    caption: parsedBody.caption,
                }
                textPlain = parsedBody.caption ?? null
                break

            case 'profile_share':
                content = {
                    userId: parsedBody.userId,
                    caption: parsedBody.caption,
                }
                textPlain = parsedBody.caption ?? null
                break

            case 'gif':
                content = {
                    gifUrl: parsedBody.gifUrl,
                    width: parsedBody.width,
                    height: parsedBody.height,
                    provider: parsedBody.provider,
                    caption: parsedBody.caption,
                }
                textPlain = parsedBody.caption ?? null
                break

            default:
                return sendError(res, "MESSAGE_CREATE_FAILED", "Invalid message kind", 400)
        }


        // insert msg

        const { data: msg, error: msgError } = await supabase.from('messages').insert({
            id: messageId,
            conversation_id: conversationId,
            sender_id: req.userId,
            kind,
            client_id: clientId,
            content,
            text_plain: textPlain,
            reply_to_message_id: replyToMessageId ?? null,
        }).select('*').single()

        if (msgError) {
            if (msgError.code === '23505') {
                const { data: existing } = await supabase.from('messages').select('id').eq('sender_id', req.userId).eq('client_id', clientId).maybeSingle()
                return sendSuccess(res, { message: existing })
            }

            throw msgError
        }

        // update conversation last message
        await supabase.from('conversations').update({
            last_message_id: msg.id,
            last_message_at: msg.created_at,
        }).eq('id', conversationId)

        // get other members
        const { data: members, error: membersError } = await supabase.from('conversation_members').select('user_id').eq('conversation_id', conversationId)
        if (membersError) return sendError(res, "MESSAGE_CREATE_FAILED", membersError.message, 500)
        const recipientIds = members?.map((m) => m.user_id).filter((id) => id !== req.userId) ?? []

        const event = {
            type: 'message_created',
            conversationId,
            msg
        }

        // emit to all members (including sender for multidevice sync)
        for (const member of members ?? []) {
            emitToUser(member.user_id, event)
        }

        // notif
        for (const recipientId of recipientIds) {
            const isOnline = hasActiveSocket(recipientId)
        }

        return sendSuccess(res, { message: msg })


    })

    app.post('/messages/read', { preHandler: app.authenticate }, async (req, res) => {

        const parsedBody = markConversationAsReadSchema.parse(req.body)
        const { conversationId, messageId } = parsedBody

        const now = new Date().toISOString()

        const { data: member, error: memberError } = await supabase.from('conversation_members').select('conversation_id, last_read_message_id, last_read_at').eq('conversation_id', conversationId).eq('user_id', req.userId).maybeSingle()

        if (memberError) return sendError(res, "MESSAGE_READ_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "MESSAGE_READ_FAILED", "You are not a member of this conversation", 403)

        const { data: msg, error: msgError } = await supabase.from('messages').select('id, conversation_id, created_at, sender_id').eq('id', messageId).eq('conversation_id', conversationId).maybeSingle()

        if (msgError) return sendError(res, "MESSAGE_READ_FAILED", msgError.message, 500)
        if (!msg) return sendError(res, "MESSAGE_READ_FAILED", "Message not found", 404)


        if (member.last_read_message_id) {
            const { data: previousReadMessage, error: previousReadMessageError } = await supabase
                .from('messages')
                .select('id, created_at')
                .eq('id', member.last_read_message_id)
                .maybeSingle()

            if (previousReadMessageError) throw previousReadMessageError

            if (
                previousReadMessage &&
                new Date(msg.created_at).getTime() < new Date(previousReadMessage.created_at).getTime()
            ) {
                return sendError(res, "MESSAGE_READ_FAILED", "Read state cannot move backward", 409)
            }
        }

        if (member.last_read_message_id === messageId) {
            return sendSuccess(res, { conversationId, userId: req.userId, lastReadMessageId: messageId, lastReadAt: msg.created_at })
        }

        const { error: updateError } = await supabase.from('conversation_members').update({
            last_read_message_id: messageId,
            last_read_at: now,
        }).eq('conversation_id', conversationId).eq('user_id', req.userId)

        if (updateError) return sendError(res, "MESSAGE_READ_FAILED", updateError.message, 500)

        const event = {
            type: 'conversation.read',
            conversationId,
            userId: req.userId,
            lastReadmessageId: messageId,
            lastReadAt: now,
        }

        const { data: members, error: membersError } = await supabase.from('conversation_members').select('user_id').eq('conversation_id', conversationId)

        if (membersError) return sendError(res, "MESSAGE_READ_FAILED", membersError.message, 500)

        for (const member of members ?? []) {
            emitToUser(member.user_id, event)
        }

        return sendSuccess(res, { conversationId, userId: req.userId, lastReadMessageId: messageId, lastReadAt: now })

    })

    app.get('/inbox', { preHandler: app.authenticate }, async (req, res) => {
        const userId = req.userId

        const { data: memberships, error: membershipsError } = await supabase
            .from('conversation_members')
            .select('conversation_id, last_read_message_id, last_read_at')
            .eq('user_id', userId)

        if (membershipsError) throw membershipsError

        if (!memberships || memberships.length === 0) {
            return sendSuccess(res, { inbox: [] })
        }

        const membershipByConversationId = new Map(
            memberships.map((m) => [m.conversation_id, m])
        )

        const conversationIds = memberships.map((m) => m.conversation_id)

        const { data: conversations, error: conversationsError } = await supabase
            .from('conversations')
            .select('id, created_at, last_message_id, last_message_at')
            .in('id', conversationIds)
            .order('last_message_at', { ascending: false, nullsFirst: false })

        if (conversationsError) throw conversationsError

        const { data: allMembers, error: allMembersError } = await supabase
            .from('conversation_members')
            .select('conversation_id, user_id')
            .in('conversation_id', conversationIds)

        if (allMembersError) throw allMembersError

        const otherMemberIds = uniqueStrings(
            (allMembers ?? [])
                .filter((m) => m.user_id !== userId)
                .map((m) => m.user_id)
        )

        const { data: profiles, error: profilesError } = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url, is_verified, verification_type')
            .in('id', otherMemberIds)

        if (profilesError) throw profilesError

        const profileById = new Map((profiles ?? []).map((p) => [p.id, p]))

        const lastMessageIds = uniqueStrings((conversations ?? []).map((c) => c.last_message_id))

        const { data: lastMessages, error: lastMessagesError } = await supabase
            .from('messages')
            .select(`
            id,
            conversation_id,
            sender_id,
            kind,
            created_at,
            unsent_at,
            reply_to_message_id,
            client_id,
            preview_url,
            preview_title,
            preview_description,
            preview_image_url,
            preview_audio_url,
            text_plain,
            content
          `)
            .in('id', lastMessageIds)

        if (lastMessagesError) throw lastMessagesError

        const lastMessageById = new Map((lastMessages ?? []).map((m) => [m.id, m]))

        const inbox = (conversations ?? []).map((conversation) => {
            const membership = membershipByConversationId.get(conversation.id) ?? null
            const otherMember = (allMembers ?? []).find(
                (m) => m.conversation_id === conversation.id && m.user_id !== userId
            )

            const otherProfile = otherMember ? profileById.get(otherMember.user_id) ?? null : null
            const lastMessage = conversation.last_message_id
                ? lastMessageById.get(conversation.last_message_id) ?? null
                : null

            return {
                id: conversation.id,
                createdAt: conversation.created_at,
                lastMessageAt: conversation.last_message_at,
                otherUser: otherProfile,
                lastReadMessageId: membership?.last_read_message_id ?? null,
                lastReadAt: membership?.last_read_at ?? null,
                lastMessage,
            }
        })

        return sendSuccess(res, { inbox })
    })

    app.get('/conversations/:id', { preHandler: app.authenticate }, async (req, res) => {
        const userId = req.userId

        const { id: conversationId } = getConversationParamsSchema.parse(req.params)
        const { cursor, limit = 30 } = getConversationQuerySchema.parse(req.query)

        const isMember = await requireConversationMembership(conversationId, userId)

        if (!isMember) {
            return sendError(res, "FORBIDDEN", "You are not a member of this conversation", 403)
        }

        let messagesQuery = supabase
            .from('messages')
            .select('*')
            .eq('conversation_id', conversationId)
            .is('unsent_at', null)
            .order('created_at', { ascending: false })
            .limit(limit + 1)

        if (cursor) {
            messagesQuery = messagesQuery.lt('created_at', cursor)
        }

        const { data: rawMessages, error: messagesError } = await messagesQuery

        if (messagesError) throw messagesError

        const hasMore = (rawMessages?.length ?? 0) > limit
        const pageMessages = hasMore ? rawMessages!.slice(0, limit) : rawMessages ?? []

        const senderIds = uniqueStrings(pageMessages.map((m) => m.sender_id))
        const replyIds = uniqueStrings(pageMessages.map((m) => m.reply_to_message_id))

        const trackIds = uniqueStrings(
            pageMessages
                .filter((m) => m.kind === 'track_share')
                .map((m) => (m.content as { trackId?: string }).trackId)
        )

        const albumIds = uniqueStrings(
            pageMessages
                .filter((m) => m.kind === 'album_share')
                .map((m) => (m.content as { albumId?: string }).albumId)
        )

        const artistIds = uniqueStrings(
            pageMessages
                .filter((m) => m.kind === 'artist_share')
                .map((m) => (m.content as { artistId?: string }).artistId)
        )

        const sharedProfileIds = uniqueStrings(
            pageMessages
                .filter((m) => m.kind === 'profile_share')
                .map((m) => (m.content as { userId?: string }).userId)
        )

        const profileIds = uniqueStrings([...senderIds, ...sharedProfileIds])

        const [
            profilesResult,
            replyMessagesResult,
            tracksResult,
            albumsResult,
            artistsResult,
        ] = await Promise.all([
            profileIds.length > 0
                ? supabase
                    .from('profiles')
                    .select('id, username, display_name, avatar_url, is_verified, verification_type')
                    .in('id', profileIds)
                : Promise.resolve({ data: [], error: null }),

            replyIds.length > 0
                ? supabase
                    .from('messages')
                    .select('*')
                    .in('id', replyIds)
                : Promise.resolve({ data: [], error: null }),

            trackIds.length > 0
                ? supabase
                    .from('tracks')
                    .select(`
                  id,
                  name,
                  source,
                  source_id,
                  artwork_url,
                  preview_url,
                  artist_id,
                  album_id,
                  artists (
                    id,
                    name,
                    image_url
                  ),
                  albums (
                    id,
                    name,
                    artwork_url
                  )
                `)
                    .in('id', trackIds)
                : Promise.resolve({ data: [], error: null }),

            albumIds.length > 0
                ? supabase
                    .from('albums')
                    .select(`
                  id,
                  name,
                  artwork_url,
                  artist_id,
                  artists (
                    id,
                    name,
                    image_url
                  )
                `)
                    .in('id', albumIds)
                : Promise.resolve({ data: [], error: null }),

            artistIds.length > 0
                ? supabase
                    .from('artists')
                    .select('id, name, image_url')
                    .in('id', artistIds)
                : Promise.resolve({ data: [], error: null }),
        ])

        if (profilesResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", profilesResult.error.message, 500)
        if (replyMessagesResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", replyMessagesResult.error.message, 500)
        if (tracksResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", tracksResult.error.message, 500)
        if (albumsResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", albumsResult.error.message, 500)
        if (artistsResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", artistsResult.error.message, 500)

        const profileById = new Map((profilesResult.data ?? []).map((p) => [p.id, p]))
        const replyMessageById = new Map((replyMessagesResult.data ?? []).map((m) => [m.id, m]))
        const trackById = new Map((tracksResult.data ?? []).map((t) => [t.id, t]))
        const albumById = new Map((albumsResult.data ?? []).map((a) => [a.id, a]))
        const artistById = new Map((artistsResult.data ?? []).map((a) => [a.id, a]))

        const enrichedMessages = pageMessages.map((message) => {
            let entity = null

            if (message.kind === 'track_share') {
                const trackId = (message.content as { trackId?: string }).trackId
                entity = trackId ? trackById.get(trackId) ?? null : null
            } else if (message.kind === 'album_share') {
                const albumId = (message.content as { albumId?: string }).albumId
                entity = albumId ? albumById.get(albumId) ?? null : null
            } else if (message.kind === 'artist_share') {
                const artistId = (message.content as { artistId?: string }).artistId
                entity = artistId ? artistById.get(artistId) ?? null : null
            } else if (message.kind === 'profile_share') {
                const sharedUserId = (message.content as { userId?: string }).userId
                entity = sharedUserId ? profileById.get(sharedUserId) ?? null : null
            }

            return {
                ...message,
                sender: profileById.get(message.sender_id) ?? null,
                replyToMessage: message.reply_to_message_id
                    ? replyMessageById.get(message.reply_to_message_id) ?? null
                    : null,
                entity,
            }
        })

        return sendSuccess(res, {
            conversationId,
            messages: enrichedMessages,
            nextCursor: hasMore ? enrichedMessages[enrichedMessages.length - 1]?.created_at ?? null : null,
            hasMore,
        })
    })


}

export default messagesRoutes