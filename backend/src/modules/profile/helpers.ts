//helpers

import { supabase } from "../../config/supabase.js"

export const PROFILE_TYPE_COOLDOWN_DAYS = 14

export function canUpdateProfileType(
    typeUpdatedAt: string | null | undefined,
    now: Date = new Date()
): boolean {
    if (!typeUpdatedAt) return true

    const lastUpdated = new Date(typeUpdatedAt)
    if (Number.isNaN(lastUpdated.getTime())) return true

    const elapsedMs = now.getTime() - lastUpdated.getTime()
    return elapsedMs >= PROFILE_TYPE_COOLDOWN_DAYS * 24 * 60 * 60 * 1000
}

/** Same shape for `GET /me` and full `GET /users/:username` profile rows. */
export const PROFILE_DETAIL_SELECT =
  "*, user_status(*, track:tracks!user_status_track_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))), profile_song:tracks!profiles_profile_song_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name)), badges:profile_badges!profile_badges_user_id_fkey(index, badge:badges!profile_badges_badge_id_fkey(id, text, color_hex, created_at))"

/** Narrow profile fetch for `GET /me/friends/activity` (statuses loaded separately). */
export const FRIEND_ACTIVITY_PROFILE_SELECT =
    "id, username, display_name, avatar_url, updated_at, profile_song:tracks!profiles_profile_song_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))"

/** Direct `user_status` read so rows resolve even when the profile embed shape/RLS differs. */
export const FRIEND_ACTIVITY_USER_STATUS_SELECT =
    "profile_id, text, track_id, created_at, expires_at, track:tracks!user_status_track_id_fkey(id, name, preview_url, artwork_url, source, source_id, artist:artists!tracks_artist_id_fkey(name))"

export type ViewerProfileContext = {
    isSelf: boolean
    /** You follow them; `null` when {@link isSelf} (not applicable). */
    isFollowing: boolean | null
    /** They follow you. */
    isFollowedBy: boolean
    /** You blocked them. */
    isBlocked: boolean
    /** They blocked you. */
    isBlockedBy: boolean
    /** Pending follow request from you to them (e.g. private account). */
    outgoingFollowRequest: boolean
    /** Pending follow request from them to you. */
    incomingFollowRequest: boolean
}

/**
 * Relationship flags between the optional viewer and the profile user.
 * Call with `viewerId === undefined` for unauthenticated requests (all false, no self).
 */
export async function getViewerProfileContext(
    viewerId: string | undefined,
    targetUserId: string
): Promise<ViewerProfileContext> {
    if (!viewerId) {
        return {
            isSelf: false,
            isFollowing: null,
            isFollowedBy: false,
            isBlocked: false,
            isBlockedBy: false,
            outgoingFollowRequest: false,
            incomingFollowRequest: false,
        }
    }

    if (viewerId === targetUserId) {
        return {
            isSelf: true,
            isFollowing: null,
            isFollowedBy: false,
            isBlocked: false,
            isBlockedBy: false,
            outgoingFollowRequest: false,
            incomingFollowRequest: false,
        }
    }

    const [
        followOut,
        followIn,
        blockOut,
        blockIn,
        reqOut,
        reqIn,
    ] = await Promise.all([
        supabase
            .schema("public")
            .from("follows")
            .select("follower_id")
            .eq("follower_id", viewerId)
            .eq("following_id", targetUserId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follows")
            .select("follower_id")
            .eq("follower_id", targetUserId)
            .eq("following_id", viewerId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("blocks")
            .select("blocker_id")
            .eq("blocker_id", viewerId)
            .eq("blocked_id", targetUserId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("blocks")
            .select("blocker_id")
            .eq("blocker_id", targetUserId)
            .eq("blocked_id", viewerId)
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follow_requests")
            .select("follower_id")
            .eq("follower_id", viewerId)
            .eq("following_id", targetUserId)
            .eq("status", "sent")
            .maybeSingle(),
        supabase
            .schema("public")
            .from("follow_requests")
            .select("follower_id")
            .eq("follower_id", targetUserId)
            .eq("following_id", viewerId)
            .eq("status", "sent")
            .maybeSingle(),
    ])

    const errors = [
        followOut.error,
        followIn.error,
        blockOut.error,
        blockIn.error,
        reqOut.error,
        reqIn.error,
    ].filter(Boolean)
    if (errors.length > 0) {
        throw new Error(errors[0]!.message)
    }

    return {
        isSelf: false,
        isFollowing: !!followOut.data,
        isFollowedBy: !!followIn.data,
        isBlocked: !!blockOut.data,
        isBlockedBy: !!blockIn.data,
        outgoingFollowRequest: !!reqOut.data,
        incomingFollowRequest: !!reqIn.data,
    }
}

export type ViewerBlockSets = {
    blockedByViewer: Set<string>
    blockedViewer: Set<string>
}

export async function getViewerBlockSets(viewerId: string): Promise<ViewerBlockSets> {
    const [outRes, inRes] = await Promise.all([
        supabase.schema("public").from("blocks").select("blocked_id").eq("blocker_id", viewerId),
        supabase.schema("public").from("blocks").select("blocker_id").eq("blocked_id", viewerId),
    ])

    if (outRes.error) throw new Error(outRes.error.message)
    if (inRes.error) throw new Error(inRes.error.message)

    return {
        blockedByViewer: new Set((outRes.data ?? []).map((row) => row.blocked_id as string)),
        blockedViewer: new Set((inRes.data ?? []).map((row) => row.blocker_id as string)),
    }
}

export function isBlockedWithViewer(sets: ViewerBlockSets, targetUserId: string): boolean {
    return sets.blockedByViewer.has(targetUserId) || sets.blockedViewer.has(targetUserId)
}

export function filterBlockedUserIds(sets: ViewerBlockSets, ids: string[]): string[] {
    return ids.filter((id) => !isBlockedWithViewer(sets, id))
}

export type FollowListProfileRow = {
    id: string
    username: string
    display_name: string | null
    avatar_url: string | null
    profile_type: string | null
    type_updated_at: string | null
}

/**
 * Loads public profile fields for the given ids and returns them in the same order as `ids`
 * (skips missing rows, e.g. deleted accounts).
 */
export async function profilesForUserIdsOrdered(ids: string[]): Promise<FollowListProfileRow[]> {
    if (ids.length === 0) return []

    const unique = [...new Set(ids)]
    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, display_name, avatar_url, profile_type, type_updated_at")
        .in("id", unique)

    if (error) {
        throw new Error(error.message)
    }

    const map = new Map(
        (data ?? []).map((row) => [
            row.id,
            {
                id: row.id,
                username: row.username,
                display_name: row.display_name,
                avatar_url: row.avatar_url,
                profile_type: row.profile_type ?? null,
                type_updated_at: row.type_updated_at ?? null,
            } satisfies FollowListProfileRow,
        ])
    )

    const out: FollowListProfileRow[] = []
    for (const id of ids) {
        const row = map.get(id)
        if (row) out.push(row)
    }
    return out
}

export async function checkFollowing(userId: string, otherUserId: string) {
    const { data, error } = await supabase.schema('public').from('follows').select('*').eq('follower_id', userId).eq('following_id', otherUserId).maybeSingle()
    if (error) { throw new Error(error.message) }
    if (!data) { return false } else { return true }
}

/** Normalized friend row for the Friends tab activity carousel (camelCase JSON). */
export type FriendActivityItem = {
    userId: string
    username: string
    displayName: string | null
    avatarUrl: string | null
    kind: "music" | "text"
    updatedAt: string | null
    track: {
        id: string
        name: string
        artistName: string | null
        artworkUrl: string | null
        source: string | null
        sourceId: string | null
    } | null
    /** Status caption (e.g. `user_status.text` alongside a status track). */
    text: string | null
    /** Shown when the card uses `profiles.profile_song` because there is no active status. */
    footerNote: string | null
}

function asRecord(v: unknown): Record<string, unknown> | null {
    if (v == null) return null
    if (Array.isArray(v)) {
        const first = v[0]
        return first != null && typeof first === "object" && !Array.isArray(first)
            ? (first as Record<string, unknown>)
            : null
    }
    if (typeof v === "object") return v as Record<string, unknown>
    return null
}

function pickString(v: unknown): string | null {
    if (typeof v !== "string") return null
    const t = v.trim()
    return t.length > 0 ? t : null
}

function artistNameFromEmbed(artist: unknown): string | null {
    const o = asRecord(artist)
    if (!o) return null
    return pickString(o.name)
}

function profileSongTrackFromRow(ps: unknown): FriendActivityItem["track"] {
    const o = asRecord(ps)
    if (!o) return null
    const id = pickString(o.id)
    const name = pickString(o.name)
    if (!id || !name) return null
    return {
        id,
        name,
        artistName: artistNameFromEmbed(o.artist),
        artworkUrl: pickString(o.artwork_url),
        source: pickString(o.source),
        sourceId: pickString(o.source_id),
    }
}

function userStatusExpired(us: Record<string, unknown>): boolean {
    const raw = us.expires_at
    if (raw == null) return false
    if (typeof raw !== "string") return false
    const t = new Date(raw).getTime()
    if (Number.isNaN(t)) return false
    return t < Date.now()
}

function indexUserStatusByProfileId(statusRows: unknown[]): Map<string, Record<string, unknown>> {
    const map = new Map<string, Record<string, unknown>>()
    for (const raw of statusRows) {
        const row = asRecord(raw)
        const profileId = row ? pickString(row.profile_id) : null
        if (profileId && row) map.set(profileId, row)
    }
    return map
}

/**
 * Builds friend activity cards: **active** `user_status` (not past `expires_at`) first
 * (track and/or text); otherwise `profile_song` with a footer note; otherwise omitted.
 */
export function buildFriendActivitiesFromFriendData(
    profiles: unknown[],
    statusRows: unknown[]
): FriendActivityItem[] {
    const statusByProfile = indexUserStatusByProfileId(statusRows)
    const out: FriendActivityItem[] = []

    for (const raw of profiles) {
        const row = asRecord(raw)
        if (!row) continue
        const userId = pickString(row.id)
        const username = pickString(row.username)
        if (!userId || !username) continue

        const displayName = pickString(row.display_name)
        const avatarUrl = pickString(row.avatar_url)
        const profileUpdated = pickString(row.updated_at)
        const profileSongTrack = profileSongTrackFromRow(row.profile_song)

        const usRaw = statusByProfile.get(userId) ?? null
        const activeStatus =
            usRaw && !userStatusExpired(usRaw) ? usRaw : null

        const statusText = activeStatus ? pickString(activeStatus.text) : null
        const statusTrack = activeStatus
            ? profileSongTrackFromRow(activeStatus.track)
            : null
        const statusCreated = activeStatus
            ? pickString(activeStatus.created_at)
            : null

        const hasStatusContent =
            !!activeStatus &&
            (!!statusText || !!statusTrack || !!pickString(activeStatus.track_id))

        let kind: FriendActivityItem["kind"] | null = null
        let trackOut: FriendActivityItem["track"] = null
        let text: string | null = null
        let footerNote: string | null = null
        let updatedAt: string | null = null

        if (hasStatusContent) {
            if (statusTrack) {
                kind = "music"
                trackOut = statusTrack
                text = statusText
                updatedAt = statusCreated
            } else if (statusText) {
                kind = "text"
                text = statusText
                trackOut = null
                updatedAt = statusCreated
            } else if (pickString(activeStatus?.track_id) && !statusTrack) {
                /* `track_id` set but embed failed — fall back so the card still shows something */
                if (profileSongTrack) {
                    kind = "music"
                    trackOut = profileSongTrack
                    text = null
                    footerNote = "Profile song"
                    updatedAt = profileUpdated
                } else {
                    continue
                }
            } else {
                continue
            }
        } else if (profileSongTrack) {
            kind = "music"
            trackOut = profileSongTrack
            text = null
            footerNote = "Profile song"
            updatedAt = profileUpdated
        } else {
            continue
        }

        out.push({
            userId,
            username,
            displayName,
            avatarUrl,
            kind,
            updatedAt,
            track: trackOut,
            text,
            footerNote,
        })
    }

    out.sort((a, b) => {
        const ta = a.updatedAt ? new Date(a.updatedAt).getTime() : 0
        const tb = b.updatedAt ? new Date(b.updatedAt).getTime() : 0
        return tb - ta
    })

    return out
}

export type DiscographyItemType = "album" | "ep" | "single" | "featured_on"

export type DiscographyItem = {
    id: string
    title: string
    release_date: string
    image_url: string | null
    type: DiscographyItemType
}

const DISCOGRAPHY_TYPE_ORDER: Record<DiscographyItemType, number> = {
    album: 0,
    ep: 0,
    single: 1,
    featured_on: 2,
}

type DiscographyTrackRow = {
    id: string
    name: string
    artwork_url: string | null
    release_date: string | null
    owner_id: string
}

function mapTrackToDiscographyItem(
    track: DiscographyTrackRow,
    type: DiscographyItemType
): DiscographyItem | null {
    if (!track.release_date) return null

    return {
        id: track.id,
        title: track.name,
        release_date: track.release_date,
        image_url: track.artwork_url,
        type,
    }
}

type DiscographyReleaseRow = {
    id: string
    name: string
    artwork_url: string | null
    release_date: string | null
    release_type: string
    owner_id: string
}

function mapReleaseToDiscographyItem(release: DiscographyReleaseRow): DiscographyItem | null {
    if (!release.release_date) return null

    return {
        id: release.id,
        title: release.name,
        release_date: release.release_date,
        image_url: release.artwork_url,
        type: release.release_type === "ep" ? "ep" : "album",
    }
}

function compareDiscographyItems(a: DiscographyItem, b: DiscographyItem): number {
    const typeDiff = DISCOGRAPHY_TYPE_ORDER[a.type] - DISCOGRAPHY_TYPE_ORDER[b.type]
    if (typeDiff !== 0) return typeDiff

    const dateDiff = b.release_date.localeCompare(a.release_date)
    if (dateDiff !== 0) return dateDiff

    return b.id.localeCompare(a.id)
}

function isAfterDiscographyCursor(
    item: DiscographyItem,
    cursor: { cursorReleaseDate: string; cursorType: DiscographyItemType; cursorId: string }
): boolean {
    const itemTypeRank = DISCOGRAPHY_TYPE_ORDER[item.type]
    const cursorTypeRank = DISCOGRAPHY_TYPE_ORDER[cursor.cursorType]

    if (itemTypeRank > cursorTypeRank) return true
    if (itemTypeRank < cursorTypeRank) return false

    if (item.release_date < cursor.cursorReleaseDate) return true
    if (item.release_date > cursor.cursorReleaseDate) return false

    return item.id < cursor.cursorId
}

async function fetchOwnedReleaseTrackIds(userId: string): Promise<Set<string>> {
    const { data, error } = await supabase
        .schema("public")
        .from("niche_release_tracks")
        .select("track_id, release:niche_releases!inner(owner_id)")
        .eq("release.owner_id", userId)

    if (error) throw new Error(error.message)

    return new Set(
        (data ?? [])
            .map((row) => row.track_id)
            .filter((trackId): trackId is string => typeof trackId === "string" && trackId.length > 0)
    )
}

async function fetchOwnedDiscographyTracks(userId: string, publicOnly: boolean) {
    const releaseTrackIds = await fetchOwnedReleaseTrackIds(userId)

    let query = supabase
        .schema("public")
        .from("niche_tracks")
        .select("id, name, artwork_url, release_date, owner_id")
        .eq("owner_id", userId)
        .is("deleted_at", null)
        .not("release_date", "is", null)

    if (publicOnly) {
        query = query.eq("visibility", "public")
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return (data ?? []).filter((track) => !releaseTrackIds.has(track.id)) as DiscographyTrackRow[]
}

async function fetchOwnedDiscographyReleases(userId: string, publicOnly: boolean) {
    let query = supabase
        .schema("public")
        .from("niche_releases")
        .select("id, name, artwork_url, release_date, release_type, owner_id")
        .eq("owner_id", userId)
        .is("deleted_at", null)
        .not("release_date", "is", null)

    if (publicOnly) {
        query = query.eq("visibility", "public")
    }

    const { data, error } = await query
    if (error) throw new Error(error.message)

    return (data ?? []) as DiscographyReleaseRow[]
}

async function fetchFeaturedDiscographyTracks(userId: string, publicOnly: boolean) {
    let query = supabase
        .schema("public")
        .from("niche_track_artists")
        .select(`
            track:niche_tracks!niche_track_artists_track_id_fkey(
                id,
                name,
                artwork_url,
                release_date,
                owner_id,
                visibility,
                deleted_at
            )
        `)
        .eq("artist_id", userId)
        .eq("is_primary", false)

    const { data, error } = await query
    if (error) throw new Error(error.message)

    const tracks: DiscographyTrackRow[] = []
    const seen = new Set<string>()

    for (const row of data ?? []) {
        const track = Array.isArray(row.track) ? row.track[0] : row.track
        if (!track || typeof track !== "object") continue

        const typed = track as DiscographyTrackRow & {
            visibility?: string | null
            deleted_at?: string | null
        }

        if (typed.deleted_at) continue
        if (typed.owner_id === userId) continue
        if (!typed.release_date) continue
        if (publicOnly && typed.visibility !== "public") continue
        if (seen.has(typed.id)) continue

        seen.add(typed.id)
        tracks.push(typed)
    }

    return tracks
}

export async function fetchDiscographyPage(input: {
    userId: string
    publicOnly: boolean
    type?: "all" | DiscographyItemType
    cursorReleaseDate?: string | undefined
    cursorType?: DiscographyItemType | undefined
    cursorId?: string | undefined
    limit: number
}) {
    const filterType = input.type ?? "all"
    const [ownedTracks, ownedReleases, featuredTracks] = await Promise.all([
        fetchOwnedDiscographyTracks(input.userId, input.publicOnly),
        fetchOwnedDiscographyReleases(input.userId, input.publicOnly),
        fetchFeaturedDiscographyTracks(input.userId, input.publicOnly),
    ])

    const merged: DiscographyItem[] = []

    for (const release of ownedReleases) {
        const item = mapReleaseToDiscographyItem(release)
        if (item) merged.push(item)
    }

    for (const track of ownedTracks) {
        const item = mapTrackToDiscographyItem(track, "single")
        if (item) merged.push(item)
    }

    for (const track of featuredTracks) {
        const item = mapTrackToDiscographyItem(track, "featured_on")
        if (item) merged.push(item)
    }

    merged.sort(compareDiscographyItems)

    const filtered =
        filterType === "all"
            ? merged
            : filterType === "album"
              ? merged.filter((item) => item.type === "album" || item.type === "ep")
              : merged.filter((item) => item.type === filterType)

    const hasCursor = Boolean(input.cursorReleaseDate && input.cursorType && input.cursorId)
    const cursor = hasCursor
        ? {
              cursorReleaseDate: input.cursorReleaseDate!,
              cursorType: input.cursorType!,
              cursorId: input.cursorId!,
          }
        : null

    const pageSource = cursor
        ? filtered.filter((item) => isAfterDiscographyCursor(item, cursor))
        : filtered

    const hasMore = pageSource.length > input.limit
    const items = hasMore ? pageSource.slice(0, input.limit) : pageSource
    const last = items.at(-1)

    const latestRelease =
        !cursor && filterType === "all"
            ? [...merged].sort((a, b) => {
                  const dateDiff = b.release_date.localeCompare(a.release_date)
                  if (dateDiff !== 0) return dateDiff
                  const typeDiff = DISCOGRAPHY_TYPE_ORDER[a.type] - DISCOGRAPHY_TYPE_ORDER[b.type]
                  if (typeDiff !== 0) return typeDiff
                  return b.id.localeCompare(a.id)
              })[0] ?? null
            : null

    return {
        latestRelease,
        items,
        hasMore,
        nextCursor:
            hasMore && last
                ? JSON.stringify({
                      cursorReleaseDate: last.release_date,
                      cursorType: last.type,
                      cursorId: last.id,
                  })
                : null,
    }
}

export async function getProfileByUsername(username: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("profiles")
        .select("id, username, is_private")
        .eq("username", username)
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data
}