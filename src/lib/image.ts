import crypto from "crypto"
import { env } from "../config/env.js"
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3"
import { getSignedUrl } from "@aws-sdk/s3-request-presigner"

const R2 = new S3Client({
    region: "auto",
    endpoint: `https://${env.r2.accountId}.r2.cloudflarestorage.com`,
    credentials: {
        accessKeyId: env.r2.accessKeyId,
        secretAccessKey: env.r2.secretAccessKey,
    },
})

const MAX_IMAGE_BYTES = 30 * 1024 * 1024
const MAX_VIDEO_BYTES = 500 * 1024 * 1024 // 500MB
const MAX_AUDIO_BYTES = 500 * 1024 * 1024 // 500MB
const STREAM_PUBLIC_BASE_URL = "https://stream.nichemusic.app"

export function normalizePublicAssetUrl(url: string | null | undefined): string | null {
    if (!url) return null

    const trimmed = url.trim()
    if (!trimmed) return null
    if (/^https?:\/\//i.test(trimmed)) return trimmed

    const withoutHost = trimmed.replace(/^stream\.nichemusic\.app\/?/i, "").replace(/^\/+/, "")
    return `${STREAM_PUBLIC_BASE_URL}/${withoutHost}`
}

export async function fetchAssetHead(url: string): Promise<Response> {
    const normalized = normalizePublicAssetUrl(url)
    if (!normalized) {
        throw new Error("Invalid asset URL")
    }

    return fetch(normalized, { method: "HEAD" })
}

type UploadFormat = "jpeg" | "webp" | "png" | "avif"
type VideoFormat = "mp4" | "webm" | "mov" | "mkv"
type MusicFormat = "mp3" | "m4a" | "wav" | "flac" | "aac"

export interface PresignedUploadResult {
    uploadUrl: string
    objectKey: string
    publicUrl: string
    contentType: string
    maxBytes: number
}

function generateRandomId(bytes = 16): string {
    return crypto.randomBytes(bytes).toString("base64url")
}

function contentTypeFor(format: UploadFormat): string {
    switch (format) {
        case "jpeg":
            return "image/jpeg"
        case "webp":
            return "image/webp"
        case "png":
            return "image/png"
        case "avif":
            return "image/avif"
    }
}

function extensionFor(format: UploadFormat): string {
    switch (format) {
        case "jpeg":
            return "jpg"
        case "webp":
            return "webp"
        case "png":
            return "png"
        case "avif":
            return "avif"
    }
}

function extensionForMusic(format: MusicFormat): string {
    switch (format) {
        case "mp3":
            return "mp3"
        case "m4a":
            return "m4a"
        case "wav":
            return "wav"
        case "flac":
            return "flac"
        case "aac":
            return "aac"
    }
}

function contentTypeForMusic(format: MusicFormat): string {
    switch (format) {
        case "mp3":
            return "audio/mpeg"
        case "m4a":
            return "audio/mp4"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "aac":
            return "audio/aac"
    }
}

function extensionForVideo(format: VideoFormat): string {
    switch (format) {
        case "mp4":
            return "mp4"
        case "webm":
            return "webm"
        case "mov":
            return "mov"
        case "mkv":
            return "mkv"
    }
}

function contentTypeForVideo(format: VideoFormat): string {
    switch (format) {
        case "mp4":
            return "video/mp4"
        case "webm":
            return "video/webm"
        case "mov":
            return "video/quicktime"
        case "mkv":
            return "video/x-matroska"
    }
}

export async function getAvatarPresignedUrl(userId: string): Promise<PresignedUploadResult> {
    const bucketName = "profile-pics"
    const publicBucket = 'avatars'
    const format: UploadFormat = "jpeg"
    const extension = extensionFor(format)
    const contentType = contentTypeFor(format)

    const objectKey = `${userId}/avatar-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable",
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${env.r2.publicBaseUrl}/${publicBucket}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_IMAGE_BYTES,
    }
}

export async function getNicheTrackImagePresignedUrl(trackId: string, format: UploadFormat): Promise<PresignedUploadResult> {
    const bucketName = 'music'
    const extension = extensionFor(format)
    const contentType = contentTypeFor(format)
    const objectKey = `${trackId}/images/image-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${STREAM_PUBLIC_BASE_URL}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_IMAGE_BYTES,
    }
}

export async function getNicheTrackMusicPresignedUrl(trackId: string, format: MusicFormat): Promise<PresignedUploadResult> {
    const bucketName = 'music'
    const extension = extensionForMusic(format)
    const contentType = contentTypeForMusic(format)
    const objectKey = `${trackId}/audio/track-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${STREAM_PUBLIC_BASE_URL}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_AUDIO_BYTES,
    }
}

export async function getNicheTrackMomentPresignedUrl(trackId: string, format: VideoFormat): Promise<PresignedUploadResult> {
    const bucketName = 'music'
    const extension = extensionForVideo(format)
    const contentType = contentTypeForVideo(format)
    const objectKey = `${trackId}/video/moment-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${STREAM_PUBLIC_BASE_URL}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_VIDEO_BYTES,
    }
}

export async function getPlaylistImagePresignedUrl(playlistId: string, format: UploadFormat): Promise<PresignedUploadResult> {
    const bucketName = 'playlist-covers'
    const publicBucket = 'covers/playlists'
    const extension = extensionFor(format)
    const contentType = contentTypeFor(format)
    const objectKey=`${playlistId}/cover-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName, 
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${env.r2.publicBaseUrl}/${publicBucket}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_IMAGE_BYTES,
    }
}

export async function getPostMediaPresignedUrl(postId: string, format: UploadFormat):Promise<PresignedUploadResult> {
    const bucketName = "post-media" 
    const publicBucket = "media/posts"
    const extension = extensionFor(format)
    const contentType = contentTypeFor(format)
    const objectKey = `${postId}/media-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${env.r2.publicBaseUrl}/${publicBucket}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_IMAGE_BYTES,
    }
}

export async function getPostVideoPresignedUrl(postId: string, format: VideoFormat): Promise<PresignedUploadResult> {
    const bucketName = "post-media"
    const publicBucket = "media/posts"
    const extension = extensionForVideo(format)
    const contentType = contentTypeForVideo(format)
    const objectKey = `${postId}/video-${generateRandomId(12)}.${extension}`

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${env.r2.publicBaseUrl}/${publicBucket}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_VIDEO_BYTES,
    }
}

export async function getGroupAvatarPresignedUrl(groupId: string, format: UploadFormat): Promise<PresignedUploadResult> {
    const bucketName = "profile-pics"
    const publicBucket = "avatars"
    const extension = extensionFor(format)
    const contentType = contentTypeFor(format)
    const objectKey = `groups/${groupId}/avatar-${generateRandomId(12)}.${extension}` // url will be like cdn.com/avatars/groups/groupid/avatar-349343.jpg

    const command = new PutObjectCommand({
        Bucket: bucketName,
        Key: objectKey,
        ContentType: contentType,
        CacheControl: "public, max-age=31536000, immutable", // 1 yr
    })

    const uploadUrl = await getSignedUrl(R2, command, {
        expiresIn: 60 * 5, // 5 minutes
    })

    const publicUrl = `${env.r2.publicBaseUrl}/${publicBucket}/${objectKey}`

    return {
        uploadUrl,
        objectKey,
        publicUrl,
        contentType,
        maxBytes: MAX_IMAGE_BYTES,
    }

}