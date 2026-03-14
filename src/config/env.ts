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
        redirectUri: z.string().url(),
    }),
    r2: z.object({
        accountId: z.string(),
        accessKeyId: z.string(),
        secretAccessKey: z.string(),
        publicBaseUrl: z.string().url(),
    }),
    port: z.number().default(3932),
    state: z.enum(["development", "production"]).default("development"),
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
    },
    r2: {
        accountId: process.env.R2_ACCOUNT_ID!,
        accessKeyId: process.env.R2_ACCESS_KEY_ID!,
        secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
        publicBaseUrl: process.env.R2_PUBLIC_BASE_URL!,
    },
    port: Number(process.env.PORT) || 3932,
})

export default env
