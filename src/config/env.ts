// env config
import "dotenv/config"
import { z } from "zod"

const envSchema = z.object({
    database: z.object({
        url: z.string().url(),
        connectionString: z.string(),
        key: z.string(),
    }),
    google: z.object({
        clientId: z.string(),
        clientSecret: z.string(),
        redirectUri: z.string().url(),
    }),
    apple: z.object({
        clientId: z.string(),
        clientSecret: z.string(),
        bundleId: z.string().optional().default("com.nichemusic.app"),
        redirectUri: z.url(),
        musicApiKey: z.string(),
    }),
    r2: z.object({
        accountId: z.string(),
        accessKeyId: z.string(),
        secretAccessKey: z.string(),
        publicBaseUrl: z.string().url(),
    }),
    notificationWorker: z.object({
        url: z.url(),
        apiKey: z.string(),
    }),
    apns: z.object({
        keyId: z.string().optional(),
        teamId: z.string().optional(),
        bundleId: z.string().optional().default("com.nichemusic.app"),
        privateKey: z.string().optional(),
    }),
    admin: z.object({
        userIds: z.array(z.string()).default([]),
    }),
    cronSecret: z.string().optional(),
    port: z.coerce.number().default(3932),
    state: z.enum(["development", "production"]).default("development"),
    resendApiKey: z.string(),
    emailCodePepper: z.string(),
    passwordResetBaseUrl: z.url(),
    apiPublicUrl: z.url(),
})

export const env = envSchema.parse({
    database: {
        url: process.env.DATABASE_URL!,
        connectionString: process.env.DATABASE_CONNECTION_STRING!,
        key: process.env.DATABASE_KEY!,
    },
    google: {
        clientId: process.env.GOOGLE_CLIENT_ID!,
        clientSecret: process.env.GOOGLE_CLIENT_SECRET!,
        redirectUri: process.env.GOOGLE_REDIRECT_URI!,
    },
    apple: {
        clientId: process.env.APPLE_CLIENT_ID!,
        clientSecret: process.env.APPLE_CLIENT_SECRET ?? process.env.APPLE_CLIENT_SCECRET ?? "",
        bundleId: process.env.APPLE_BUNDLE_ID,
        redirectUri: process.env.APPLE_REDIRECT_URI!,
        musicApiKey: process.env.APPLE_MUSIC_API_KEY!,
    },
    r2: {
        accountId: process.env.R2_ACCOUNT_ID!,
        accessKeyId: process.env.R2_ACCESS_KEY_ID!,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
        publicBaseUrl: process.env.R2_PUBLIC_BASE_URL!,
    },
    notificationWorker: {
        url: process.env.NOTIFICATION_WORKER_URL!,
        apiKey: process.env.NOTIFICATION_QUEUE_API_KEY!,
    },
    apns: {
        keyId: process.env.APNS_KEY_ID,
        teamId: process.env.APNS_TEAM_ID,
        bundleId: process.env.APNS_BUNDLE_ID,
        privateKey: process.env.APNS_PRIVATE_KEY,
    },
    admin: {
        userIds: (process.env.ADMIN_USER_IDS ?? "")
            .split(",")
            .map((v) => v.trim())
            .filter((v) => v.length > 0),
    },
    cronSecret: process.env.CRON_SECRET,
    port: process.env.PORT,
    state: process.env.STATE,
    resendApiKey: process.env.RESEND_API_KEY!,
    emailCodePepper: process.env.EMAIL_CODE_PEPPER!,
    passwordResetBaseUrl: process.env.PASSWORD_RESET_BASE_URL ?? "https://auth.nichemusic.app",
    apiPublicUrl: process.env.API_PUBLIC_URL ?? "https://api.nichemusic.app",
})

export default env
