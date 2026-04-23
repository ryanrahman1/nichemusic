import { SignJWT, importPKCS8 } from "jose"
import { connect } from "node:http2"
import type { env } from "../config/env.js"

const APNS_PROD = "https://api.push.apple.com"
const APNS_SANDBOX = "https://api.sandbox.push.apple.com"
const TOKEN_TTL_MS = 50 * 60 * 1000

type APNSEnvironment = "development" | "production"

export type APNSEndpoint = {
    id: string
    environment: APNSEnvironment
    deviceToken: string
    appBundleId: string | null
}

export type APNSNotification = {
    title: string
    body: string
    kind: string
    entityType: string
    entityId: string | null
    actorId: string | null
    data: Record<string, unknown>
}

export type APNSResult =
    | { ok: true; messageId?: string }
    | {
        ok: false
        statusCode: number
        reason?: string
        invalidateEndpoint: boolean
    }

let cachedToken: string | null = null
let tokenExpiresAt = 0

function normalizePrivateKey(raw: string): string {
    const trimmed = raw.trim()
    const unquoted =
        (trimmed.startsWith('"') && trimmed.endsWith('"')) ||
            (trimmed.startsWith("'") && trimmed.endsWith("'"))
            ? trimmed.slice(1, -1)
            : trimmed
    const withNewlines = unquoted.replace(/\\r\\n/g, "\n").replace(/\\n/g, "\n").replace(/\r/g, "\n")
    const begin = "-----BEGIN PRIVATE KEY-----"
    const end = "-----END PRIVATE KEY-----"

    const hasPemHeaders = withNewlines.includes(begin) && withNewlines.includes(end)
    if (hasPemHeaders) return withNewlines

    const base64Body = withNewlines.replace(/\s+/g, "")
    const wrappedBody = base64Body.match(/.{1,64}/g)?.join("\n") ?? base64Body
    return `${begin}\n${wrappedBody}\n${end}`
}

function assertAPNSConfig(config: typeof env.apns): asserts config is {
    keyId: string
    teamId: string
    bundleId: string
    privateKey: string
} {
    if (!config.keyId || !config.teamId || !config.bundleId || !config.privateKey) {
        throw new Error("APNS configuration missing in API environment")
    }
}

async function getAPNSToken(config: typeof env.apns): Promise<string> {
    assertAPNSConfig(config)
    const now = Date.now()

    if (!cachedToken || now > tokenExpiresAt) {
        const privateKeyPem = normalizePrivateKey(config.privateKey)
        const privateKey = await importPKCS8(privateKeyPem, "ES256")
        cachedToken = await new SignJWT({})
            .setProtectedHeader({ alg: "ES256", kid: config.keyId })
            .setIssuer(config.teamId)
            .setIssuedAt(Math.floor(now / 1000))
            .sign(privateKey)
        tokenExpiresAt = now + TOKEN_TTL_MS
    }

    return cachedToken
}

function buildPayload(notification: APNSNotification): Record<string, unknown> {
    return {
        aps: {
            alert: {
                title: notification.title,
                body: notification.body,
            },
            sound: "default",
            "mutable-content": 1,
        },
        data: {
            kind: notification.kind,
            entity_type: notification.entityType,
            entity_id: notification.entityId ?? undefined,
            actor_id: notification.actorId ?? undefined,
            ...notification.data,
        },
    }
}

export async function sendDirectAPNS(
    config: typeof env.apns,
    endpoint: APNSEndpoint,
    notification: APNSNotification
): Promise<APNSResult> {
    assertAPNSConfig(config)
    const token = await getAPNSToken(config)
    const baseUrl = endpoint.environment === "development" ? APNS_SANDBOX : APNS_PROD
    const topic = endpoint.appBundleId ?? config.bundleId
    const url = `${baseUrl}/3/device/${endpoint.deviceToken}`
    const payload = buildPayload(notification)

    const response = await sendAPNSHttp2Request(baseUrl, endpoint.deviceToken, {
        authorization: `bearer ${token}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
    }, JSON.stringify(payload))

    const messageId = response.headers["apns-id"]
    if (response.statusCode >= 200 && response.statusCode < 300) {
        return { ok: true, messageId }
    }

    let reason: string | undefined
    try {
        const parsed = JSON.parse(response.body) as { reason?: string }
        reason = parsed.reason
    } catch {
        reason = undefined
    }

    const invalidReasons = new Set([
        "BadDeviceToken",
        "DeviceTokenNotForTopic",
        "Unregistered",
        "UnregisteredTimestamp",
        "InvalidProviderToken",
    ])

    return {
        ok: false,
        statusCode: response.statusCode,
        reason,
        invalidateEndpoint: !!reason && invalidReasons.has(reason),
    }
}

async function sendAPNSHttp2Request(
    baseUrl: string,
    deviceToken: string,
    headers: Record<string, string>,
    body: string
): Promise<{
    statusCode: number
    headers: Record<string, string>
    body: string
}> {
    return new Promise((resolve, reject) => {
        const client = connect(baseUrl)
        client.on("error", (err) => {
            client.close()
            reject(err)
        })

        const req = client.request({
            ":method": "POST",
            ":path": `/3/device/${deviceToken}`,
            ...headers,
        })

        let statusCode = 0
        const responseHeaders: Record<string, string> = {}
        let responseBody = ""

        req.setEncoding("utf8")
        req.on("response", (h) => {
            const rawStatus = h[":status"]
            statusCode = typeof rawStatus === "number" ? rawStatus : Number(rawStatus ?? 0)
            for (const [key, value] of Object.entries(h)) {
                if (key.startsWith(":")) continue
                if (Array.isArray(value)) {
                    responseHeaders[key] = value.join(",")
                } else if (value != null) {
                    responseHeaders[key] = String(value)
                }
            }
        })
        req.on("data", (chunk: string) => {
            responseBody += chunk
        })
        req.on("end", () => {
            client.close()
            resolve({
                statusCode,
                headers: responseHeaders,
                body: responseBody,
            })
        })
        req.on("error", (err) => {
            client.close()
            reject(err)
        })

        req.end(body)
    })
}
