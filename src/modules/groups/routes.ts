import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"
import { sendSuccess, sendError } from "../../global/response.js"
import { generateRandomId } from "../../lib/auth.js" // placeholder
import { getGroupAvatarPresignedUrl } from "../../lib/image.js"
import { presignGroupUploadSchema, createGroupSchema, updateGroupSchema, inviteUserToGroupSchema, acceptGroupRequestSchema, promoteMemberToRoleSchema, groupPostsQuerySchema } from "./schemas.js"
import { slugifyString, checkSlugAvailability, getPublicUrl } from "./helpers.js"
import { getPostViewerContextMap } from "../posts/helpers.js"

function encodePostCursor(input: { cursorCreatedAt: string; cursorId: string }) {
    return JSON.stringify(input)
}

function encodeScoreCursor(input: { cursorScore: number; cursorCreatedAt: string; cursorId: string }) {
    return JSON.stringify(input)
}

const groupsRoutes: FastifyPluginAsync = async (app) => {
    app.get('/groups/:id', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data, error } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()

        let viewer: {
            is_owner: boolean
            role: string | null
        } = {
            is_owner: false,
            role: null,
        }


        if (error) return sendError(res, "GROUP_FETCH_FAILED", error.message, 500)
        if (!data) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        if (data?.is_private) {
            if (!req.userId) return sendError(res, "GROUP_FETCH_FAILED", "Group is private", 403)
            const { data: groupMember, error: groupMemberError } = await supabase.schema('public').from('group_members').select('*').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
            if (groupMemberError) return sendError(res, "GROUP_FETCH_FAILED", groupMemberError.message, 500)
            if (!groupMember) return sendError(res, "GROUP_FETCH_FAILED", "User is not in group", 403)
            viewer.role = groupMember.role // after all checks, set user role since we know they're in the group
        }

        if (req.userId) {
            const { data: role, error: roleError } = await supabase.schema('public').from('group_members').select('role').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
            if (role) { viewer.role = role.role } else { viewer.role = null }
            viewer.is_owner = !!req.userId && data.owner_id === req.userId
        }


        return sendSuccess(res, { group: data, viewer: req.userId ? viewer : null })
    })

    app.get('/groups/slug/:slug', { preHandler: app.optionalAuthenticate }, async (req, res) => { // get group by a slug, cleaner for urls
        const { slug } = req.params as { slug: string }

        const { data, error } = await supabase.schema('public').from('groups').select('*').eq('slug', slug).maybeSingle()

        let viewer: {
            is_owner: boolean
            role: string | null
        } = {
            is_owner: false,
            role: null,
        }


        if (error) return sendError(res, "GROUP_FETCH_FAILED", error.message, 500)
        if (!data) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        if (data?.is_private) {
            if (!req.userId) return sendError(res, "GROUP_FETCH_FAILED", "Group is private", 403)
            const { data: groupMember, error: groupMemberError } = await supabase.schema('public').from('group_members').select('*').eq('group_id', data.id).eq('user_id', req.userId).maybeSingle()
            if (groupMemberError) return sendError(res, "GROUP_FETCH_FAILED", groupMemberError.message, 500)
            if (!groupMember) return sendError(res, "GROUP_FETCH_FAILED", "User is not in group", 403)
            viewer.role = groupMember.role // after all checks, set user role since we know they're in the group
        }

        if (req.userId) {
            const { data: role, error: roleError } = await supabase.schema('public').from('group_members').select('role').eq('group_id', data.id).eq('user_id', req.userId).maybeSingle()
            if (role) { viewer.role = role.role } else { viewer.role = null }
            viewer.is_owner = !!req.userId && data.owner_id === req.userId
        }


        return sendSuccess(res, { group: data, viewer: req.userId ? viewer : null })
    })

    app.get('/groups/members', { preHandler: app.authenticate }, async (req, res) => { // all groups that the user is a member of
        const { data: groups, error: groupsError } = await supabase.schema('public').from('group_members').select('*, groups!group_members_group_id_fkey(id, name, slug, image_url, is_private, member_count, created_at)').eq('user_id', req.userId).order('joined_at', { ascending: false })
        if (groupsError) return sendError(res, "GROUP_MEMBERS_FETCH_FAILED", groupsError.message, 500)
        return sendSuccess(res, { groups: groups })
    })

    app.get('/groups/me/invites', { preHandler: app.authenticate }, async (req, res) => { // all invites that the user has received
        const { data: invites, error: invitesError } = await supabase.schema('public').from('group_invites').select('*, groups!group_invites_group_id_fkey(id, name, slug, image_url, is_private, member_count, created_at), profiles!group_invites_sent_by_fkey(id, username, avatar_url)').eq('user_id', req.userId).order('sent_at', { ascending: false })
        if (invitesError) return sendError(res, "GROUP_INVITES_FETCH_FAILED", invitesError.message, 500)
        return sendSuccess(res, { invites: invites })
    })

    app.get('/groups/me/requests', { preHandler: app.authenticate }, async (req, res) => { // all requests that the user has sent
        const { data: requests, error: requestsError } = await supabase.schema('public').from('group_join_requests').select('*, groups!group_requests_group_id_fkey(id, name, slug, image_url, is_private, member_count, created_at)').eq('user_id', req.userId).order('created_at', { ascending: false })
        if (requestsError) return sendError(res, "GROUP_REQUESTS_FETCH_FAILED", requestsError.message, 500)
        return sendSuccess(res, { requests: requests })
    })

    app.get('/groups/:id/invites', { preHandler: app.authenticate }, async (req, res) => { // all invites for a group
        // mod / admin / owner only -- can see all invites
        const { id } = req.params as { id: string }
        const { data: groupMemberCheck, error: groupMemberCheckError } = await supabase.schema('public').from('group_members').select('role').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
        if (groupMemberCheckError) return sendError(res, "GROUP_FETCH_FAILED", groupMemberCheckError.message, 500)
        if (!groupMemberCheck) return sendError(res, "GROUP_FETCH_FAILED", "You are not a member of this group", 403)
        if (groupMemberCheck.role !== "moderator" && groupMemberCheck.role !== "admin" && groupMemberCheck.role !== "owner") return sendError(res, "GROUP_FETCH_FAILED", "You are not authorized to view invites for this group", 403)

        const { data: invites, error: invitesError } = await supabase.schema('public').from('group_invites').select('*, profiles!group_invites_sent_by_fkey(id, username, avatar_url)').eq('group_id', id).order('sent_at', { ascending: false })
        if (invitesError) return sendError(res, "GROUP_INVITES_FETCH_FAILED", invitesError.message, 500)
        return sendSuccess(res, { invites: invites })
    })

    app.get('/groups/:id/requests', { preHandler: app.authenticate }, async (req, res) => { // all requests for a group
        // mod / admin / owner only -- can see all requests
        const { id } = req.params as { id: string }
        const { data: groupMemberCheck, error: groupMemberCheckError } = await supabase.schema('public').from('group_members').select('role').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
        if (groupMemberCheckError) return sendError(res, "GROUP_FETCH_FAILED", groupMemberCheckError.message, 500)
        if (!groupMemberCheck) return sendError(res, "GROUP_FETCH_FAILED", "You are not a member of this group", 403)
        if (groupMemberCheck.role !== "moderator" && groupMemberCheck.role !== "admin" && groupMemberCheck.role !== "owner") return sendError(res, "GROUP_FETCH_FAILED", "You are not authorized to view requests for this group", 403)

        const { data: requests, error: requestsError } = await supabase.schema('public').from('group_join_requests').select('*, profiles!group_join_requests_user_id_fkey(id, username, avatar_url)').eq('group_id', id).order('requested_at', { ascending: false })
        if (requestsError) return sendError(res, "GROUP_REQUESTS_FETCH_FAILED", requestsError.message, 500)
        return sendSuccess(res, { requests: requests })
    })

    app.post('/groups/:id/join', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: group, error: groupError } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        if (group.is_private) {
            // request to join 

            const { data: groupRequest, error: groupRequestError } = await supabase.schema('public').rpc('request_to_join_group', {
                actor_id: req.userId,
                target_group_id: id
            })
            if (groupRequestError) return sendError(res, "GROUP_JOIN_FAILED", groupRequestError.message, 500)
            return sendSuccess(res, { groupRequest: groupRequest })
        }

        // else, just join since its public
        const { data: groupJoin, error: groupJoinError } = await supabase.schema('public').rpc('join_group', {
            actor_id: req.userId,
            target_group_id: id
        })
        if (groupJoinError) return sendError(res, "GROUP_JOIN_FAILED", groupJoinError.message, 500)
        return sendSuccess(res, { groupJoin: groupJoin })
    })

    app.post('/groups/:id/leave', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        const { data: leaveGroup, error: leaveGroupError } = await supabase.schema('public').rpc('leave_group', {
            actor_id: req.userId,
            target_group_id: id
        })

        if (leaveGroupError) return sendError(res, "GROUP_LEAVE_FAILED", leaveGroupError.message, 500)

        return sendSuccess(res, { leaveGroup: leaveGroup })
    })

    app.post('/groups/avatar/presign', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = presignGroupUploadSchema.parse(req.body)
        const groupId = parsedBody.groupId ?? generateRandomId(16)

        const upload = await getGroupAvatarPresignedUrl(groupId, parsedBody.format)
        return sendSuccess(res, {
            groupId,
            upload,
        })
    })

    app.post('/groups/create', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = createGroupSchema.parse(req.body)

        if (!parsedBody.slug) {
            parsedBody.slug = await slugifyString(parsedBody.name)
        }

        if (!await checkSlugAvailability(parsedBody.slug)) {
            return sendError(res, "GROUP_CREATE_FAILED", "Slug is not available", 400)
        }

        const image_url = parsedBody.avatar_object_key ? await getPublicUrl(parsedBody.avatar_object_key) : null

        const { data: group, error: groupError } = await supabase.schema('public').from('groups').insert({
            id: parsedBody.id ?? generateRandomId(16),
            name: parsedBody.name,
            slug: parsedBody.slug,
            owner_id: req.userId,
            description: parsedBody.description ?? "",
            is_private: parsedBody.is_private,
            image_url: image_url,
        }).select('*').single()

        if (groupError) return sendError(res, "GROUP_CREATE_FAILED", groupError.message, 500)

        // join user to group as owner
        const { data: joinGroup, error: joinGroupError } = await supabase.schema('public').from('group_members').insert({
            group_id: group.id,
            user_id: req.userId,
            role: "owner",
        }).select('*').single()

        if (joinGroupError) return sendError(res, "GROUP_CREATE_FAILED", joinGroupError.message, 500)

        return sendSuccess(res, { group: group })
    })

    app.post('/groups/:id/update', { preHandler: app.authenticate }, async (req, res) => {
        const parsedBody = updateGroupSchema.parse(req.body)
        const { id } = req.params as { id: string }

        // get current group
        const { data: group, error: groupError } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        // check if user is owner
        if (group.owner_id !== req.userId) return sendError(res, "GROUP_UPDATE_FAILED", "You are not the owner of this group", 403)

        // check if slug is available
        if (parsedBody.slug && parsedBody.slug !== group.slug && !await checkSlugAvailability(parsedBody.slug)) {
            return sendError(res, "GROUP_UPDATE_FAILED", "Slug is not available", 400)
        }

        const image_url = parsedBody.avatar_object_key ? await getPublicUrl(parsedBody.avatar_object_key) : null

        const { data: updatedGroup, error: updatedGroupError } = await supabase.schema('public').from('groups').update({
            name: parsedBody.name ?? group.name,
            slug: parsedBody.slug ?? group.slug,
            description: parsedBody.description ?? group.description,
            is_private: parsedBody.is_private ?? group.is_private,
            image_url: image_url ?? group.image_url,
        }).eq('id', id).select('*').single()

        if (updatedGroupError) return sendError(res, "GROUP_UPDATE_FAILED", updatedGroupError.message, 500)

        return sendSuccess(res, { group: updatedGroup })
    })

    app.post('/groups/:id/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }

        // get current group
        const { data: group, error: groupError } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        // check if user is owner
        if (group.owner_id !== req.userId) return sendError(res, "GROUP_DELETE_FAILED", "You are not the owner of this group", 403)

        // delete group
        const { data: deletedGroup, error: deletedGroupError } = await supabase.schema('public').from('groups').delete().eq('id', id).select('*').single()
        if (deletedGroupError) return sendError(res, "GROUP_DELETE_FAILED", deletedGroupError.message, 500)

        // no need to delete the others; cascade delete will handle it

        return sendSuccess(res, { group: deletedGroup })
    })

    app.post('/groups/:id/invite', { preHandler: app.authenticate }, async (req, res) => { // invite a user to a group -- must be a member to invite
        const { id } = req.params as { id: string }

        const parsedBody = inviteUserToGroupSchema.parse(req.body)

        // get the group
        const { data: group, error: groupError } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        // check if user is a member
        const { data: member, error: memberError } = await supabase.schema('public').from('group_members').select('*').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
        if (memberError) return sendError(res, "GROUP_FETCH_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "GROUP_FETCH_FAILED", "You are not a member of this group", 403)

        // invite the user
        const { data: invite, error: inviteError } = await supabase.schema('public').rpc('invite_user_to_group', {
            actor_id: req.userId,
            target_group_id: id,
            invited_user_id: parsedBody.userId,
        })
        if (inviteError) return sendError(res, "GROUP_INVITE_FAILED", inviteError.message, 500)

        return sendSuccess(res, { invite: invite })
    })

    app.post('/groups/:id/invite/delete', { preHandler: app.authenticate }, async (req, res) => { // user who invited can delete the invite
        const { id } = req.params as { id: string }
        const parsedBody = inviteUserToGroupSchema.parse(req.body)

        // get the group
        const { data: group, error: groupError } = await supabase.schema('public').from('groups').select('*').eq('id', id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_FETCH_FAILED", "Group not found", 404)

        // check if user is a member OR owner/admin/moderator
        const { data: member, error: memberError } = await supabase.schema('public').from('group_members').select('*').eq('group_id', id).eq('user_id', req.userId).maybeSingle()
        if (memberError) return sendError(res, "GROUP_FETCH_FAILED", memberError.message, 500)
        if (!member) return sendError(res, "GROUP_FETCH_FAILED", "You are not a member of this group", 403)

        // delete the invite where the invited user is the one being invited and the group id is the one being invited to and the invited by is the user who invited
        const { data: deletedInvite, error: deletedInviteError } = await supabase.schema('public').from('group_invites').delete().eq('group_id', id).eq('user_id', parsedBody.userId).eq('sent_by', req.userId).eq('status', 'sent').select('*').single() // status is sent because we only want to delete sent invites
        if (deletedInviteError) return sendError(res, "GROUP_INVITE_DELETE_FAILED", deletedInviteError.message, 500)
        return sendSuccess(res, { result: deletedInvite })
    })

    app.post('/groups/:id/invite/accept', { preHandler: app.authenticate }, async (req, res) => { // user who is invited can accept the invite
        const { id } = req.params as { id: string }

        const { data: acceptinvite, error: acceptinviteError } = await supabase.schema('public').rpc('accept_group_invite', {
            actor_id: req.userId,
            target_group_id: id
        })

        if (acceptinviteError) return sendError(res, "GROUP_INVITE_ACCEPT_FAILED", acceptinviteError.message, 500) // rpc handles invite not found and other errors
        return sendSuccess(res, { result: acceptinvite })
    })

    app.post('/groups/:id/request/accept', { preHandler: app.authenticate }, async (req, res) => { // requests are from anyone; approved by moderators and up

        const { groupId } = req.params as { groupId: string }
        const parsedBody = acceptGroupRequestSchema.parse(req.body)

        const { data: acceptRequest, error: acceptRequestError } = await supabase.schema('public').rpc('accept_group_join_request', {
            actor_id: req.userId,
            group_id: groupId,
            requester_id: parsedBody.requesterId
        })

        if (acceptRequestError) return sendError(res, "GROUP_REQUEST_ACCEPT_FAILED", acceptRequestError.message, 500)
        return sendSuccess(res, { result: acceptRequest })
    })

    app.post('/groups/:groupId/request/reject', { preHandler: app.authenticate }, async (req, res) => { // requests are from anyone; rejected by moderators and up
        const { groupId } = req.params as { groupId: string }
        const parsedBody = acceptGroupRequestSchema.parse(req.body)

        // check if user is moderator, owner, admin
        const { data: groupMemberCheck, error: groupMemberCheckError } = await supabase.schema('public').from('group_members').select('role').eq('group_id', groupId).eq('user_id', req.userId).maybeSingle()
        if (groupMemberCheckError) return sendError(res, "GROUP_FETCH_FAILED", groupMemberCheckError.message, 500)
        if (!groupMemberCheck) return sendError(res, "GROUP_FETCH_FAILED", "You are not a member of this group", 403)
        if (groupMemberCheck.role !== "moderator" && groupMemberCheck.role !== "admin" && groupMemberCheck.role !== "owner") return sendError(res, "GROUP_FETCH_FAILED", "You are not authorized to reject requests for this group", 403)

        // no rpc -- just delete the request row
        const { data: deletedRequest, error: deletedRequestError } = await supabase.schema('public').from('group_join_requests').delete().eq('group_id', groupId).eq('user_id', parsedBody.requesterId).select('*').single()

        if (deletedRequestError) return sendError(res, "GROUP_REQUEST_REJECT_FAILED", deletedRequestError.message, 500)
        return sendSuccess(res, { result: deletedRequest })
    })

    app.post('/groups/:groupId/members/:userId/promote', { preHandler: app.authenticate }, async (req, res) => { // promote a member to a role
        const { groupId, targetUserId } = req.params as { groupId: string, targetUserId: string }
        const parsedBody = promoteMemberToRoleSchema.parse(req.body)

        const { data: promoteMember, error: promoteMemberError } = await supabase.schema('public').rpc('promote_group_member', {
            actor_id: req.userId,
            target_group_id: groupId,
            target_user_id: targetUserId,
            new_role: parsedBody.role
        })

        if (promoteMemberError) return sendError(res, "GROUP_PROMOTE_MEMBER_FAILED", promoteMemberError.message, 500)

        return sendSuccess(res, { result: promoteMember })

    })

    app.post('/groups/:groupId/members/:userId/demote', { preHandler: app.authenticate }, async (req, res) => { // demote a member to a role
        const { groupId, targetUserId } = req.params as { groupId: string, targetUserId: string }
        const parsedBody = promoteMemberToRoleSchema.parse(req.body)

        const { data: demoteMember, error: demoteMemberError } = await supabase.schema('public').rpc('demote_group_member', {
            actor_id: req.userId,
            target_group_id: groupId,
            target_user_id: targetUserId,
            new_role: parsedBody.role
        })

        if (demoteMemberError) return sendError(res, "GROUP_DEMOTE_MEMBER_FAILED", demoteMemberError.message, 500)
        return sendSuccess(res, { result: demoteMember })
    })

    app.post('/groups/:groupId/members/:userId/kick', { preHandler: app.authenticate }, async (req, res) => { // kick a member from a group
        const { groupId, targetUserId } = req.params as { groupId: string, targetUserId: string }

        const { data: kickMember, error: kickMemberError } = await supabase.schema('public').rpc('kick_group_member', {
            actor_id: req.userId,
            target_group_id: groupId,
            target_user_id: targetUserId
        })

        if (kickMemberError) return sendError(res, "GROUP_KICK_MEMBER_FAILED", kickMemberError.message, 500)
        return sendSuccess(res, { result: kickMember })
    })

    app.post('/groups/:groupId/members/:userId/transfer', { preHandler: app.authenticate }, async (req, res) => { // transfer ownership of a group to a member; only owner can do this
        const { groupId, targetUserId } = req.params as { groupId: string, targetUserId: string }

        const { data: transferOwnership, error: transferOwnershipError } = await supabase.schema('public').rpc('transfer_group_ownership', {
            actor_id: req.userId,
            target_group_id: groupId,
            new_owner_id: targetUserId
        })

        if (transferOwnershipError) return sendError(res, "GROUP_TRANSFER_OWNERSHIP_FAILED", transferOwnershipError.message, 500)
        return sendSuccess(res, { result: transferOwnership })
    })

    app.get('/groups/:id/posts', { preHandler: app.optionalAuthenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { sort, cursorCreatedAt, cursorId, cursorScore, limit } = groupPostsQuerySchema.parse(req.query)

        const { data: group, error: groupError } = await supabase.schema("public").from("groups").select("id, is_private").eq("id", id).maybeSingle()
        if (groupError) return sendError(res, "GROUP_FETCH_FAILED", groupError.message, 500)
        if (!group) return sendError(res, "GROUP_NOT_FOUND", "Group not found", 404)

        if (group.is_private) {
            if (!req.userId) return sendError(res, "FORBIDDEN", "Group is private", 403)

            const { data: membership, error: membershipError } = await supabase.schema("public").from("group_members").select("group_id").eq("group_id", id).eq("user_id", req.userId).maybeSingle()
            if (membershipError) return sendError(res, "GROUP_MEMBERSHIP_FETCH_FAILED", membershipError.message, 500)
            if (!membership) return sendError(res, "FORBIDDEN", "Group is private", 403)
        }

        const { data, error } = await supabase.rpc("get_group_posts", {
            target_group_id: id,
            sort_mode: sort,
            page_limit: limit,
            cursor_score: sort.startsWith("top_") ? (cursorScore ?? null) : null,
            cursor_created_at: cursorCreatedAt ?? null,
            cursor_id: cursorId ?? null,
        })

        if (error) return sendError(res, "GROUP_POSTS_FETCH_FAILED", error.message, 500)

        const rows = data ?? []
        const hasMore = rows.length > limit
        const items = hasMore ? rows.slice(0, limit) : rows
        const postIds = items.map((post: any) => post.id)

        const { data: joinedPosts, error: joinedPostsError } = await supabase
            .schema("public")
            .from("posts")
            .select("*, owner:profiles!posts_owner_id_fkey(id, username, avatar_url), group:groups!posts_group_id_fkey(id, name), track:tracks!posts_track_id_fkey(id, source, source_id, name, artwork_url, preview_url, artist:artists!tracks_artist_id_fkey(id, name))")
            .in("id", postIds)

        if (joinedPostsError) return sendError(res, "GROUP_POSTS_FETCH_FAILED", joinedPostsError.message, 500)

        const postMap = new Map((joinedPosts ?? []).map((post) => [post.id, post]))
        const orderedPosts = items.map((item: any) => postMap.get(item.id)).filter(Boolean)
        const last = items.at(-1)
        const viewerMap = await getPostViewerContextMap(req.userId, orderedPosts.map((post: any) => post.id))

        return sendSuccess(res, {
            posts: orderedPosts.map((post: any) => ({
                ...post,
                viewer: viewerMap.get(post.id) ?? { isLiked: false, isReposted: false },
            })),
        }, {
            pagination: {
                nextCursor: hasMore && last
                    ? JSON.stringify(
                        sort.startsWith("top_")
                            ? { cursorScore: last.score, cursorCreatedAt: last.created_at, cursorId: last.id }
                            : { cursorCreatedAt: last.created_at, cursorId: last.id }
                    )
                    : null,
                limit,
                hasMore,
            },
        })
    })

}

export default groupsRoutes