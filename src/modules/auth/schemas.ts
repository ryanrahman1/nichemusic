import { z } from "zod"

export const profileTypeSchema = z.enum(["artist", "user", "producer", "dj"])

export const usernameSchema = z
    .string()
    .min(3)
    .max(30)
    .regex(
        /^[a-z0-9_.]+$/,
        "Username may only contain lowercase letters, numbers, underscores, and periods"
    )

export const signupEmailSchema = z.object({
    email: z.email(),
    password: z.string().min(8),
    username: usernameSchema,
    profileType: profileTypeSchema.default("user"),
    choseAvatar: z.boolean().optional().default(false),
})

export const usernameAvailabilityQuerySchema = z.object({
    username: z.string().min(1),
})

export const loginEmailSchema = z.object({
    email: z.email(),
    password: z.string().min(8)
})

export const googleCallbackQuerySchema = z.object({
    code: z.string().min(1),
    state: z.string().min(1),
})

export const signupOAuthSchema = z.object({
    provider: z.enum(["google", "apple"]),
    signupToken: z.string().min(1),
    username: usernameSchema,
    profileType: profileTypeSchema.default("user"),
})

export const exchangeSessionSchema = z.object({
    sessionToken: z.string().min(1),
})

export const passwordResetSendSchema = z.object({
    email: z.email(),
})

export const passwordResetConfirmSchema = z.object({
    token: z.string().min(1),
    password: z.string().min(8),
})

export type SignupEmailSchema = z.infer<typeof signupEmailSchema>
export type LoginEmailSchema = z.infer<typeof loginEmailSchema>
export type SignupOAuthSchema = z.infer<typeof signupOAuthSchema>
export type ExchangeSessionSchema = z.infer<typeof exchangeSessionSchema>