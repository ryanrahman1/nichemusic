import { supabase } from "../config/supabase.js"
import { generateRandomId } from "./auth.js"

export type FeedEntityType = "post" | "track" | "album" | "artist" | "feed_item" | "profile"
export type FeedClientEventType = "impression" | "view" | "skip" | "open_profile"

type BaseFeedEventParams = {
    userId: string
    entityType: FeedEntityType
    entityId: string
}

type LogViewParams = BaseFeedEventParams & {
    watchTimeMs?: number | undefined
}

type LogImpressionParams = BaseFeedEventParams

type LogSkipParams = BaseFeedEventParams & {
    watchTimeMs?: number | undefined
}

type LogProfileOpenParams = {
    userId: string
    profileId: string
}

async function insertFeedEvent(params: {
    userId: string
    entityType: FeedEntityType
    entityId: string
    eventType: FeedClientEventType
    watchTimeMs?: number | undefined
}) {
    const { data, error } = await supabase
        .schema("public")
        .from("feed_events")
        .insert({
            id: generateRandomId(16),
            user_id: params.userId,
            entity_type: params.entityType,
            entity_id: params.entityId,
            event_type: params.eventType,
            watch_time_ms: params.watchTimeMs ?? null,
        })
        .select("*")
        .single()

    if (error) throw new Error(error.message)
    return data
}

export async function logImpression(params: LogImpressionParams) {
    return insertFeedEvent({
        userId: params.userId,
        entityType: params.entityType,
        entityId: params.entityId,
        eventType: "impression",
    })
}

export async function logView(params: LogViewParams) {
    return insertFeedEvent({
        userId: params.userId,
        entityType: params.entityType,
        entityId: params.entityId,
        eventType: "view",
        watchTimeMs: params.watchTimeMs,
    })
}

export async function logSkip(params: LogSkipParams) {
    return insertFeedEvent({
        userId: params.userId,
        entityType: params.entityType,
        entityId: params.entityId,
        eventType: "skip",
        watchTimeMs: params.watchTimeMs,
    })
}

export async function logProfileOpen(params: LogProfileOpenParams) {
    return insertFeedEvent({
        userId: params.userId,
        entityType: "profile",
        entityId: params.profileId,
        eventType: "open_profile",
    })
}