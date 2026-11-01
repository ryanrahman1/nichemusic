// messages routes

// core flow: user sends message via post message; server receives message, puts in database, and checks if anyone from conversation_members table is connected to the websocket; if so, send the message payload to them; if not, then queue push notification for all conversation members; websocket is hosted in this server


import { FastifyPluginAsync } from "fastify"
import { createMessageSchema, markConversationAsReadSchema, getConversationParamsSchema, getConversationQuerySchema, ensureDmSchema, unsendMessageSchema, createGroupChatSchema, groupAddMemberSchema, groupIdParamsSchema, updateGroupNameSchema } from "./schemas.js"
import { generateRandomId } from "../../lib/auth.js"
import { supabase } from "../../config/supabase.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { emitToUser } from "../../global/realtime/socketManager.js"
import { sendGroupAddedNotification, sendMessageNotification } from "../../lib/notifications.js"

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

const TRACK_ENTITY_SELECT = `
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
                `

const ALBUM_ENTITY_SELECT = `
                  id,
                  name,
                  source,
                  source_id,
                  artwork_url,
                  artist_id,
                  artists (
                    id,
                    name,
                    image_url
                  )
                `

const ARTIST_ENTITY_SELECT = `
                  id,
                  name,
                  source,
                  source_id,
                  image_url
                `

type InsertedMessage = Record<string, unknown> & {
    sender_id: string
    kind: string
    content: unknown
}

/** Attach sender + resolved entity for share kinds (matches GET /conversations/:id). */
async function enrichOutboundMessage(msg: InsertedMessage): Promise<Record<string, unknown>> {
    const { data: sender } = await supabase
        .from('profiles')
        .select('id, username, display_name, avatar_url, is_verified, verification_type')
        .eq('id', msg.sender_id)
        .maybeSingle()

    let entity: unknown = null
    const content =
        msg.content && typeof msg.content === 'object' && !Array.isArray(msg.content)
            ? (msg.content as Record<string, unknown>)
            : null

    if (msg.kind === 'track_share' && content && typeof content.trackId === 'string') {
        const { data } = await supabase
            .from('tracks')
            .select(TRACK_ENTITY_SELECT)
            .eq('id', content.trackId)
            .maybeSingle()
        entity = data
    } else if (msg.kind === 'album_share' && content && typeof content.albumId === 'string') {
        const { data } = await supabase
            .from('albums')
            .select(ALBUM_ENTITY_SELECT)
            .eq('id', content.albumId)
            .maybeSingle()
        entity = data
    } else if (msg.kind === 'artist_share' && content && typeof content.artistId === 'string') {
        const { data } = await supabase
            .from('artists')
            .select(ARTIST_ENTITY_SELECT)
            .eq('id', content.artistId)
            .maybeSingle()
        entity = data
    } else if (msg.kind === 'profile_share' && content && typeof content.userId === 'string') {
        const { data } = await supabase
            .from('profiles')
            .select('id, username, display_name, avatar_url, is_verified, verification_type')
            .eq('id', content.userId)
            .maybeSingle()
        entity = data
    }

    return { ...msg, sender: sender ?? null, entity }
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
        const { otherUserId, name } = ensureDmSchema.parse(req.body)
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
        const { error: cErr } = await supabase.from("conversations").insert({
            id: conversationId,
            name: name ?? null,
        })
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

        const msgOut = await enrichOutboundMessage(msg as InsertedMessage)

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
            msg: msgOut,
        }

        // emit to all members (including sender for multidevice sync)
        for (const member of members ?? []) {
            emitToUser(member.user_id, event)
        }

        // push notifications
        for (const recipientId of recipientIds) {
            void sendMessageNotification(
                req.userId,
                recipientId,
                conversationId,
                msg.id,
                textPlain
            ).catch((notifyError) => {
                req.log.warn({ err: notifyError }, "message notification failed")
            })
        }

        return sendSuccess(res, { message: msgOut })


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

    app.post("/messages/unsend", { preHandler: app.authenticate }, async (req, res) => {
        const { conversationId, messageId } = unsendMessageSchema.parse(req.body)
        const userId = req.userId

        const isMember = await requireConversationMembership(conversationId, userId)
        if (!isMember) {
            return sendError(res, "FORBIDDEN", "You are not a member of this conversation", 403)
        }

        const { data: row, error: selErr } = await supabase
            .from("messages")
            .select("id, sender_id, unsent_at")
            .eq("id", messageId)
            .eq("conversation_id", conversationId)
            .maybeSingle()

        if (selErr) return sendError(res, "MESSAGE_UNSEND_FAILED", selErr.message, 500)
        if (!row) return sendError(res, "MESSAGE_UNSEND_FAILED", "Message not found", 404)
        if (row.sender_id !== userId) {
            return sendError(res, "MESSAGE_UNSEND_FAILED", "You can only unsend your own messages", 403)
        }
        if (row.unsent_at) {
            return sendSuccess(res, { conversationId, messageId, alreadyUnsent: true })
        }

        const now = new Date().toISOString()
        const { error: updErr } = await supabase
            .from("messages")
            .update({ unsent_at: now })
            .eq("id", messageId)
            .eq("conversation_id", conversationId)

        if (updErr) return sendError(res, "MESSAGE_UNSEND_FAILED", updErr.message, 500)

        const event = {
            type: "message_unsent",
            conversationId,
            messageId,
        }

        const { data: members, error: membersError } = await supabase
            .from("conversation_members")
            .select("user_id")
            .eq("conversation_id", conversationId)

        if (membersError) return sendError(res, "MESSAGE_UNSEND_FAILED", membersError.message, 500)

        for (const member of members ?? []) {
            emitToUser(member.user_id, event)
        }

        return sendSuccess(res, { conversationId, messageId, unsentAt: now })
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
            .select('id, created_at, last_message_id, last_message_at, name')
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

        const membersByConversationId = new Map<string, Array<{ user_id: string }>>()
        for (const member of allMembers ?? []) {
            const existing = membersByConversationId.get(member.conversation_id) ?? []
            existing.push({ user_id: member.user_id })
            membersByConversationId.set(member.conversation_id, existing)
        }

        const inbox = (conversations ?? []).map((conversation) => {
            const membership = membershipByConversationId.get(conversation.id) ?? null
            const conversationMembers = membersByConversationId.get(conversation.id) ?? []
            const otherMemberIds = conversationMembers
                .map((member) => member.user_id)
                .filter((memberId) => memberId !== userId)
            const otherProfiles = otherMemberIds
                .map((memberId) => profileById.get(memberId) ?? null)
                .filter((profile): profile is NonNullable<typeof profile> => Boolean(profile))
            const otherProfile = otherProfiles[0] ?? null
            const isGroup = conversationMembers.length > 2
            const previewNames = otherProfiles
                .map((profile) => profile.display_name ?? profile.username ?? "unknown")
                .slice(0, 3)
            const titleBase = previewNames.join(", ")
            const fallbackTitle = otherProfiles.length > 3 ? `${titleBase}, ...` : titleBase
            const conversationName =
                typeof conversation.name === "string" ? conversation.name.trim() : ""
            const title = conversationName.length > 0 ? conversationName : fallbackTitle
            const lastMessage = conversation.last_message_id
                ? lastMessageById.get(conversation.last_message_id) ?? null
                : null

            return {
                id: conversation.id,
                createdAt: conversation.created_at,
                lastMessageAt: conversation.last_message_at,
                otherUser: otherProfile,
                conversationType: isGroup ? "group" : "dm",
                title: title,
                members: otherProfiles,
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
                    .select(TRACK_ENTITY_SELECT)
                    .in('id', trackIds)
                : Promise.resolve({ data: [], error: null }),

            albumIds.length > 0
                ? supabase
                    .from('albums')
                    .select(ALBUM_ENTITY_SELECT)
                    .in('id', albumIds)
                : Promise.resolve({ data: [], error: null }),

            artistIds.length > 0
                ? supabase
                    .from('artists')
                    .select(ARTIST_ENTITY_SELECT)
                    .in('id', artistIds)
                : Promise.resolve({ data: [], error: null }),
        ])

        if (profilesResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", profilesResult.error.message, 500)
        if (replyMessagesResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", replyMessagesResult.error.message, 500)
        if (tracksResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", tracksResult.error.message, 500)
        if (albumsResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", albumsResult.error.message, 500)
        if (artistsResult.error) return sendError(res, "MESSAGE_FETCH_FAILED", artistsResult.error.message, 500)

        const { data: readStates, error: readStatesError } = await supabase
            .from('conversation_members')
            .select('user_id, last_read_message_id, last_read_at')
            .eq('conversation_id', conversationId)
        if (readStatesError) return sendError(res, "MESSAGE_FETCH_FAILED", readStatesError.message, 500)

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
            readStates: readStates ?? [],
            nextCursor: hasMore ? enrichedMessages[enrichedMessages.length - 1]?.created_at ?? null : null,
            hasMore,
        })
    })

    // group chats

    app.post('/messages/group/create', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = createGroupChatSchema.parse(req.body) // list of user ids to add to the convo

        const conversationId = generateRandomId(12)
        const memberIds = Array.from(new Set([req.userId, ...parsedBody.memberIds]))

        // now we need to add the conversation then add all members to the convo
        const { error: convErr } = await supabase.from('conversations').insert({
            id: conversationId,
            name: parsedBody.name ?? null,
        })

        if (convErr) return sendError(res, "GROUP_CREATE_FAILED", convErr.message, 500)

        // add each
        for (const memberId of memberIds) {
            const { error: memErr } = await supabase.from('conversation_members').insert({ conversation_id: conversationId, user_id: memberId })
            if (memErr) return sendError(res, "GROUP_CREATE_FAILED", memErr.message, 500)
        }

        return sendSuccess(res, { conversationId })
    })

    app.post('/messages/group/:id/add', { preHandler: app.authenticate }, async (req, res) => {
        // for v1.1, invites are not encessary, you can just add members regardless of whether they are private or public
        // (since to add somebody you need ot be friends with them anyway)

        const { id } = groupIdParamsSchema.parse(req.params)
        const userToAdd = groupAddMemberSchema.parse(req.body)

        // check if the authenticated user is a member of the group
        const { data: member, error: memberError } = await supabase.from('conversation_members').select('conversation_id').eq('conversation_id', id).eq('user_id', req.userId).maybeSingle()
        if (memberError) return sendError(res, "GROUP_ADD_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "GROUP_ADD_FAILED", "You are not a member of this group", 403)

        // check if the user to add is a friend
        const { data: friend, error: friendError } = await supabase.from('friends').select('user_a_id, user_b_id').eq('user_a_id', req.userId).eq('user_b_id', userToAdd.userId).maybeSingle()
        if (friendError) return sendError(res, "GROUP_ADD_FAILED", friendError.message, 500)
        if (!friend) return sendError(res, "GROUP_ADD_FAILED", "User is not a friend", 403)

        // now finally add the user to the group
        const { error: memErr } = await supabase.from('conversation_members').insert({ conversation_id: id, user_id: userToAdd.userId })
        if (memErr) return sendError(res, "GROUP_ADD_FAILED", memErr.message, 500)

        const { data: updatedMembers, error: updatedMembersError } = await supabase
            .from('conversation_members')
            .select('user_id')
            .eq('conversation_id', id)

        if (updatedMembersError) {
            req.log.warn({ err: updatedMembersError }, "group add fetch members failed")
        } else {
            void sendGroupAddedNotification({
                actorId: req.userId,
                recipientId: userToAdd.userId,
                conversationId: id,
                participantIds: (updatedMembers ?? []).map((row) => row.user_id),
            }).catch((notifyError) => {
                req.log.warn({ err: notifyError }, "group add notification failed")
            })
        }

        return sendSuccess(res, { success: true })
    })

    app.post('/messages/group/:id/name', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = groupIdParamsSchema.parse(req.params)
        const { name } = updateGroupNameSchema.parse(req.body)

        const { data: member, error: memberError } = await supabase
            .from('conversation_members')
            .select('conversation_id')
            .eq('conversation_id', id)
            .eq('user_id', req.userId)
            .maybeSingle()
        if (memberError) return sendError(res, "GROUP_UPDATE_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "GROUP_UPDATE_FAILED", "You are not a member of this group", 403)

        const { count, error: countError } = await supabase
            .from('conversation_members')
            .select('conversation_id', { count: 'exact', head: true })
            .eq('conversation_id', id)
        if (countError) return sendError(res, "GROUP_UPDATE_FAILED", countError.message, 500)
        if ((count ?? 0) < 3) {
            return sendError(res, "GROUP_UPDATE_FAILED", "Only group chats can be renamed", 400)
        }

        const { error: updateError } = await supabase
            .from('conversations')
            .update({ name })
            .eq('id', id)
        if (updateError) return sendError(res, "GROUP_UPDATE_FAILED", updateError.message, 500)

        return sendSuccess(res, { success: true, conversationId: id, name })
    })

    // remove can come later like for v1.1 not needed maybe v1.1.1
    app.post('/messages/group/:id/leave', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = groupIdParamsSchema.parse(req.params)

        // check if you are in the group
        const { data: member, error: memberError } = await supabase.from('conversation_members').select('conversation_id').eq('conversation_id', id).eq('user_id', req.userId).maybeSingle()
        if (memberError) return sendError(res, "GROUP_LEAVE_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "GROUP_LEAVE_FAILED", "You are not a member of this group", 403)

        // now remove yourself from the group
        const { error: memErr } = await supabase.from('conversation_members').delete().eq('conversation_id', id).eq('user_id', req.userId)
        if (memErr) return sendError(res, "GROUP_LEAVE_FAILED", memErr.message, 500)

        return sendSuccess(res, { success: true })
    })


}

export default messagesRoutes