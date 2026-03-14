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

type UploadFormat = "jpeg" | "webp" | "png" | "avif"

interface PresignedUploadResult {
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