import { z } from "zod"

export const signupEmailSchema = z.object({
    email: z.email(),
    password: z.string().min(8),
    username: z.string().min(3),
    choseAvatar: z.boolean().optional().default(false),
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
    username: z.string().min(3),
})

export const exchangeSessionSchema = z.object({
    sessionToken: z.string().min(1),
})

export type SignupEmailSchema = z.infer<typeof signupEmailSchema>
export type LoginEmailSchema = z.infer<typeof loginEmailSchema>
export type SignupOAuthSchema = z.infer<typeof signupOAuthSchema>
export type ExchangeSessionSchema = z.infer<typeof exchangeSessionSchema>