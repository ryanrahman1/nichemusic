import { FastifyPluginAsync } from "fastify"
import { ZodError, z } from "zod"
import { SignupEmailSchema, signupEmailSchema, loginEmailSchema, LoginEmailSchema, googleCallbackQuerySchema, SignupOAuthSchema, signupOAuthSchema, exchangeSessionSchema, usernameAvailabilityQuerySchema, passwordResetSendSchema, passwordResetConfirmSchema } from "./schemas.js"
import { signupWithEmail, loginWithEmail, revokeSession, revokeAllUserSessions, generateOAuthState, buildGoogleAuthUrl, handleGoogleCallback, SESSION_COOKIE_NAME, OAUTH_STATE_COOKIE_NAME, signupWithOAuth, checkUsernameAvailability, SignupConflictError, generateRandomId, createPasswordResetToken, resetPasswordWithToken, PasswordResetSamePasswordError } from "../../lib/auth.js"
import { getAvatarPresignedUrl } from "../../lib/image.js"
import { supabase } from "../../config/supabase.js"
import env from "../../config/env.js"
import { sendError, sendSuccess } from "../../global/response.js"
import { sendEmailVerificationCode, sendResetPasswordEmail } from "../../lib/email.js"
import crypto from "crypto"
import {
    webCsrfCookieOptions,
    webSessionCookieOptions,
    clearWebAuthCookies,
} from "../../lib/webCookies.js"


const emailVerifyConfirmSchema = z.object({
    code: z.string().regex(/^\d{6}$/),
})


function generateSixDigitCode() {
    return crypto.randomInt(100000, 1000000).toString()
}

function hashEmailCode(code: string) {
    const pepper = env.emailCodePepper
    return crypto.createHash("sha256").update(`${code}.${pepper}`).digest("hex")
}

// signup flow: post to signup -> client gets url, uploads the image -> on success, client makes patch request to /auth/me/avatar with the object key and avatar url

const authRoutes: FastifyPluginAsync = async (app) => {
    app.get("/signup/username/available", async (req, res) => {
        const parsedQuery = usernameAvailabilityQuerySchema.parse(req.query)
        const result = await checkUsernameAvailability(parsedQuery.username)
        return sendSuccess(res, result)
    })

    app.post("/signup/email", async (req, res) => {
        let parsedBody: SignupEmailSchema
        try {
            parsedBody = signupEmailSchema.parse(req.body)
        } catch (error) {
            if (error instanceof ZodError) {
                const message = error.issues[0]?.message ?? "Invalid signup request"
                return sendError(res, "VALIDATION_ERROR", message, 400)
            }
            throw error
        }

        const ipAddress = req.ip
        const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined

        let result: Awaited<ReturnType<typeof signupWithEmail>>
        try {
            result = await signupWithEmail(
                {
                    email: parsedBody.email,
                    password: parsedBody.password,
                    username: parsedBody.username,
                    profileType: parsedBody.profileType,
                },
                { ipAddress, userAgent }
            )
        } catch (error) {
            if (error instanceof SignupConflictError) {
                return sendError(res, error.code, error.message, 409)
            }
            const message = error instanceof Error && error.message ? error.message : "Signup failed"
            return sendError(res, "SIGNUP_FAILED", message, 400)
        }

        // get avatar presigned url, if chose avatar is true
        let avatarUrl: string | undefined = undefined
        let uploadUrl: string | undefined = undefined
        let objectKey: string | undefined = undefined
        let contentType: string | undefined = undefined
        let maxBytes: number | undefined = undefined
        if (parsedBody.choseAvatar) {
            const upload = await getAvatarPresignedUrl(result.userId)
            uploadUrl = upload.uploadUrl
            avatarUrl = upload.publicUrl
            objectKey = upload.objectKey
            contentType = upload.contentType
            maxBytes = upload.maxBytes
        }

        res.setCookie("session", result.sessionToken, {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
            maxAge: 60 * 60 * 24 * 365
        })

        return sendSuccess(res, {
            user: {
                id: result.userId,
                avatarUrl: avatarUrl ?? null,
            },
            avatarUpload: parsedBody.choseAvatar ? {
                uploadUrl: uploadUrl,
                avatarUrl: avatarUrl,
                objectKey: objectKey,
                contentType: contentType,
                maxBytes: maxBytes,
            } : null,
        })
    })

    app.post('/signup/email/web', async (req, res) => { // need extra for csrf
        let parsedBody: SignupEmailSchema
        try {
            parsedBody = signupEmailSchema.parse(req.body)
        } catch (error) {
            if (error instanceof ZodError) {
                const message = error.issues[0]?.message ?? "Invalid signup request"
                return sendError(res, "VALIDATION_ERROR", message, 400)
            }
            throw error
        }

        const ipAddress = req.ip
        const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined

        let result: Awaited<ReturnType<typeof signupWithEmail>>
        try {
            result = await signupWithEmail(
                {
                    email: parsedBody.email,
                    password: parsedBody.password,
                    username: parsedBody.username,
                    profileType: parsedBody.profileType,
                },
                { ipAddress, userAgent }
            )
        } catch (error) {
            if (error instanceof SignupConflictError) {
                return sendError(res, error.code, error.message, 409)
            }
            const message = error instanceof Error && error.message ? error.message : "Signup failed"
            return sendError(res, "SIGNUP_FAILED", message, 400)
        }

        // get avatar presigned url, if chose avatar is true
        let avatarUrl: string | undefined = undefined
        let uploadUrl: string | undefined = undefined
        let objectKey: string | undefined = undefined
        let contentType: string | undefined = undefined
        let maxBytes: number | undefined = undefined
        if (parsedBody.choseAvatar) {
            const upload = await getAvatarPresignedUrl(result.userId)
            uploadUrl = upload.uploadUrl
            avatarUrl = upload.publicUrl
            objectKey = upload.objectKey
            contentType = upload.contentType
            maxBytes = upload.maxBytes
        }

        // csrf token is essentially the session token plus HMAC of (session token, secret key)
        const csrfToken = crypto.createHmac("sha256", env.csrfSecretKey).update(result.sessionToken).digest("hex")

        res.setCookie("session", result.sessionToken, webSessionCookieOptions())
        res.setCookie("csrfToken", csrfToken, webCsrfCookieOptions())

        return sendSuccess(res, {
            user: {
                id: result.userId,
                avatarUrl: avatarUrl ?? null,
            },
            avatarUpload: parsedBody.choseAvatar ? {
                uploadUrl: uploadUrl,
                avatarUrl: avatarUrl,
                objectKey: objectKey,
                contentType: contentType,
                maxBytes: maxBytes,
            } : null,
        })
    })

    app.patch("/auth/me/avatar", { preHandler: [app.preAuthenticate] }, async (req, res) => {
        const { objectKey, avatarUrl } = req.body as { objectKey: string, avatarUrl: string }

        if (!objectKey.startsWith(`${req.userId}/avatar-`)) {
            return res.status(400).send({ error: "Invalid object key" })
        } // checking against key injection

        const serverUrl = `${env.r2.publicBaseUrl}/avatars/${objectKey}`
        if (serverUrl !== avatarUrl) {
            return res.status(400).send({ error: "Invalid avatar url" })
        } // checking against url injection

        // update supabase
        const { data, error } = await supabase.schema('authn').from('users').update({ avatar_url: avatarUrl, updated_at: new Date().toISOString() }).eq('id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({
            success: true,
            result: {
                user: {
                    id: req.userId,
                }
            }
        })
    })

    app.post("/login/email", async (req, res) => {
        const parsedBody: LoginEmailSchema = loginEmailSchema.parse(req.body)
        const ipAddress = req.ip
        const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined

        let result: Awaited<ReturnType<typeof loginWithEmail>>
        try {
            result = await loginWithEmail(parsedBody.email, parsedBody.password, { ipAddress, userAgent })
        } catch (e) {
            const message =
                e instanceof Error && e.message ? e.message : "Invalid email or password"
            return sendError(res, "LOGIN_FAILED", message, 401)
        }

        res.setCookie("session", result.sessionToken, {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
            maxAge: 60 * 60 * 24 * 365
        })

        return sendSuccess(res, {
            user: {
                id: result.userId,
                avatarUrl: result.avatarUrl
            },
        })
    })

    app.post("/login/email/web", async (req, res) => {
        const parsedBody: LoginEmailSchema = loginEmailSchema.parse(req.body)
        const ipAddress = req.ip
        const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined

        let result: Awaited<ReturnType<typeof loginWithEmail>>
        try {
            result = await loginWithEmail(parsedBody.email, parsedBody.password, { ipAddress, userAgent })
        } catch (e) {
            const message =
                e instanceof Error && e.message ? e.message : "Invalid email or password"
            return sendError(res, "LOGIN_FAILED", message, 401)
        }

        const csrfToken = crypto.createHmac("sha256", env.csrfSecretKey).update(result.sessionToken).digest("hex")

        res.setCookie("session", result.sessionToken, webSessionCookieOptions())
        res.setCookie("csrfToken", csrfToken, webCsrfCookieOptions())

        return sendSuccess(res, {
            user: {
                id: result.userId,
                avatarUrl: result.avatarUrl
            },
        })
    })

    // email stuff

    app.post("/email/verify/send", { preHandler: app.preAuthenticate }, async (req, res) => {
        const userId = req.userId

        // use email_verified (same flag as /session) — not email_verified_at alone
        const { data: user, error: userError } = await supabase
            .schema("authn")
            .from("users")
            .select("id, email, email_verified, email_verified_at")
            .eq("id", userId)
            .maybeSingle()

        if (userError) {
            return sendError(res, "EMAIL_VERIFY_SEND_FAILED", userError.message, 500)
        }

        if (!user) {
            return sendError(res, "USER_NOT_FOUND", "User not found", 404)
        }

        if (user.email_verified === true) {
            return sendSuccess(res, { alreadyVerified: true })
        }

        const now = new Date()
        const cooldownSeconds = 45
        const expiresInMinutes = 10

        const { data: activeCode, error: activeCodeError } = await supabase
            .schema("authn")
            .from("email_verifications")
            .select("id, last_sent_at, expires_at, attempts")
            .eq("user_id", user.id)
            .eq("email", user.email)
            .is("consumed_at", null)
            .gt("expires_at", now.toISOString())
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle()

        if (activeCodeError) {
            return sendError(res, "EMAIL_VERIFY_SEND_FAILED", activeCodeError.message, 500)
        }

        if (activeCode?.last_sent_at) {
            const lastSentAt = new Date(activeCode.last_sent_at).getTime()
            const secondsSinceLastSend = (Date.now() - lastSentAt) / 1000

            if (secondsSinceLastSend < cooldownSeconds) {
                return sendError(
                    res,
                    "EMAIL_VERIFY_COOLDOWN",
                    `Please wait ${Math.ceil(cooldownSeconds - secondsSinceLastSend)} seconds before requesting another code.`,
                    429
                )
            }
        }

        // Only one active code per user/email.
        await supabase
            .schema("authn")
            .from("email_verifications")
            .update({ consumed_at: now.toISOString() })
            .eq("user_id", user.id)
            .eq("email", user.email)
            .is("consumed_at", null)

        const code = generateSixDigitCode()
        const tokenHash = hashEmailCode(code)
        const verificationId = generateRandomId(16)
        const expiresAt = new Date(Date.now() + expiresInMinutes * 60 * 1000).toISOString()

        const { error: insertError } = await supabase
            .schema("authn")
            .from("email_verifications")
            .insert({
                id: verificationId,
                user_id: user.id,
                email: user.email,
                token_hash: tokenHash,
                expires_at: expiresAt,
                last_sent_at: now.toISOString(),
            })

        if (insertError) {
            return sendError(res, "EMAIL_VERIFY_SEND_FAILED", insertError.message, 500)
        }

        await sendEmailVerificationCode({
            email: user.email,
            code,
            expiresInMinutes
        })

        return sendSuccess(res, {
            sent: true,
            expiresAt,
            cooldownSeconds,
        })
    })

    app.post("/email/verify/confirm", { preHandler: app.preAuthenticate }, async (req, res) => {
        const userId = req.userId
        const { code } = emailVerifyConfirmSchema.parse(req.body)

        const codeHash = hashEmailCode(code)
        const now = new Date().toISOString()
        const maxAttempts = 5

        // same email_verified flag as /session so we dont false-positive alreadyVerified
        const { data: user, error: userError } = await supabase
            .schema("authn")
            .from("users")
            .select("id, email, email_verified, email_verified_at")
            .eq("id", userId)
            .maybeSingle()

        if (userError) {
            return sendError(res, "EMAIL_VERIFY_CONFIRM_FAILED", userError.message, 500)
        }

        if (!user) {
            return sendError(res, "USER_NOT_FOUND", "User not found", 404)
        }

        if (user.email_verified === true) {
            return sendSuccess(res, { verified: true, alreadyVerified: true })
        }

        const { data: verification, error: verificationError } = await supabase
            .schema("authn")
            .from("email_verifications")
            .select("id, token_hash, attempts, expires_at")
            .eq("user_id", user.id)
            .eq("email", user.email)
            .is("consumed_at", null)
            .gt("expires_at", now)
            .order("created_at", { ascending: false })
            .limit(1)
            .maybeSingle()

        if (verificationError) {
            return sendError(res, "EMAIL_VERIFY_CONFIRM_FAILED", verificationError.message, 500)
        }

        if (!verification) {
            return sendError(res, "EMAIL_VERIFY_CODE_EXPIRED", "Code expired or not found.", 400)
        }

        if (verification.attempts >= maxAttempts) {
            await supabase
                .schema("authn")
                .from("email_verifications")
                .update({ consumed_at: now })
                .eq("id", verification.id)

            return sendError(res, "EMAIL_VERIFY_TOO_MANY_ATTEMPTS", "Too many attempts. Please request a new code.", 429)
        }

        if (verification.token_hash !== codeHash) {
            const nextAttempts = verification.attempts + 1
            const attemptsRemaining = Math.max(0, maxAttempts - nextAttempts)

            await supabase
                .schema("authn")
                .from("email_verifications")
                .update({
                    attempts: nextAttempts,
                    consumed_at: nextAttempts >= maxAttempts ? now : null,
                })
                .eq("id", verification.id)

            return sendError(
                res,
                "EMAIL_VERIFY_INVALID_CODE",
                attemptsRemaining > 0
                    ? `Invalid code. ${attemptsRemaining} attempt${attemptsRemaining === 1 ? "" : "s"} remaining.`
                    : "Invalid code. Too many attempts.",
                400,
                { attemptsRemaining, maxAttempts }
            )
        }

        const [{ error: userUpdateError }, { error: verificationUpdateError }] = await Promise.all([
            supabase
                .schema("authn")
                .from("users")
                .update({ email_verified_at: now, email_verified: true })
                .eq("id", user.id),

            supabase
                .schema("authn")
                .from("email_verifications")
                .update({ consumed_at: now })
                .eq("id", verification.id),
        ])

        if (userUpdateError) {
            return sendError(res, "EMAIL_VERIFY_CONFIRM_FAILED", userUpdateError.message, 500)
        }

        if (verificationUpdateError) {
            return sendError(res, "EMAIL_VERIFY_CONFIRM_FAILED", verificationUpdateError.message, 500)
        }

        return sendSuccess(res, {
            verified: true,
        })
    })


    app.post("/password/reset/send", async (req, res) => {
        const { email } = passwordResetSendSchema.parse(req.body)
        const expiresInMinutes = 30

        try {
            const rawToken = await createPasswordResetToken(email)

            if (rawToken) {
                const link = `${env.passwordResetBaseUrl}/reset-password?token=${encodeURIComponent(rawToken)}`
                await sendResetPasswordEmail({
                    email,
                    link,
                    expiresInMinutes,
                })
            }
        } catch (error) {
            req.log.error({ err: error }, "password reset send failed")
        }

        return sendSuccess(res, { sent: true })
    })

    app.post("/password/reset/confirm", async (req, res) => {
        const { token, password } = passwordResetConfirmSchema.parse(req.body)

        try {
            await resetPasswordWithToken(token, password)
        } catch (error) {
            if (error instanceof PasswordResetSamePasswordError) {
                return sendError(res, error.code, error.message, 400)
            }

            const message =
                error instanceof Error && error.message
                    ? error.message
                    : "Invalid or expired reset token"

            if (message.includes("Password must")) {
                return sendError(res, "VALIDATION_ERROR", message, 400)
            }

            return sendError(res, "PASSWORD_RESET_INVALID_TOKEN", message, 400)
        }

        return sendSuccess(res, { reset: true })
    })





    // oauth
    // get google auth url, set state cookie; supports both JSON and browser redirect
    app.get("/signup/google", async (req, res) => {
        const state = generateOAuthState()
        const url = buildGoogleAuthUrl(state)

        res.setCookie(OAUTH_STATE_COOKIE_NAME, state, {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
            maxAge: 60 * 10, // 10 min
        })

        const appRedirect =
            typeof (req.query as { app_redirect?: string }).app_redirect === "string"
                ? (req.query as { app_redirect?: string }).app_redirect
                : null
        if (appRedirect && appRedirect.length > 0) {
            res.setCookie("oauth_app_redirect", appRedirect, {
                httpOnly: true,
                secure: env.state === "production",
                sameSite: "lax",
                path: "/",
                maxAge: 60 * 10,
            })
        }

        const wantRedirect =
            (req.query as { redirect?: string }).redirect === "1" ||
            (typeof req.headers["accept"] === "string" &&
                req.headers["accept"].includes("text/html"))

        if (wantRedirect) {
            return res.redirect(url)
        }

        return res.status(200).send({
            success: true,
            result: {
                url,
            },
        })
    })

    app.get("/signup/google/callback", async (req, res) => {

        const parsedQuery = googleCallbackQuerySchema.parse(req.query)
        const cookieState = req.cookies[OAUTH_STATE_COOKIE_NAME]

        if (!cookieState || cookieState !== parsedQuery.state) {
            return res.status(400).send({
                success: false,
                error: "Invalid OAuth state",
            })
        }

        res.clearCookie(OAUTH_STATE_COOKIE_NAME, {
            path: "/",
        })

        const ipAddress = req.ip
        const userAgent =
            typeof req.headers["user-agent"] === "string"
                ? req.headers["user-agent"]
                : undefined

        const result = await handleGoogleCallback(parsedQuery.code, {
            ipAddress,
            userAgent,
        })

        if (result.kind === "authenticated") {
            res.setCookie(SESSION_COOKIE_NAME, result.sessionToken, {
                httpOnly: true,
                secure: env.state === "production",
                sameSite: "lax",
                path: "/",
                maxAge: 60 * 60 * 24 * 365,
            })
            const appRedirect = req.cookies["oauth_app_redirect"]
            if (typeof appRedirect === "string" && appRedirect.length > 0) {
                res.clearCookie("oauth_app_redirect", { path: "/" })
                const u = new URL(appRedirect)
                u.searchParams.set("kind", "authenticated")
                u.searchParams.set("sessionToken", result.sessionToken)
                return res.redirect(u.toString())
            }

            return res.status(200).send({
                success: true,
                result: {
                    kind: "authenticated",
                    user: {
                        id: result.userId,
                    },
                },
            })
        }

        const appRedirect = req.cookies["oauth_app_redirect"]
        if (typeof appRedirect === "string" && appRedirect.length > 0) {
            res.clearCookie("oauth_app_redirect", { path: "/" })
            const u = new URL(appRedirect)
            u.searchParams.set("kind", "needs_signup")
            u.searchParams.set("provider", result.provider)
            u.searchParams.set("signupToken", result.signupToken)
            if (result.email) u.searchParams.set("email", result.email)
            if (result.avatarUrl) u.searchParams.set("avatarUrl", result.avatarUrl)
            return res.redirect(u.toString())
        }

        return res.status(200).send({
            success: true,
            result: {
                kind: "needs_signup",
                provider: result.provider,
                signupToken: result.signupToken,
                email: result.email,
                avatarUrl: result.avatarUrl,
            },
        })
    })

    app.get("/signup/apple", async (req, res) => {
        //todo
    })

    app.get("/signup/apple/callback", async (req, res) => {
        //todo
    })

    // general signup helper once we get info from oauth provider
    app.post("/signup/oauth", async (req, res) => {

        const parsedBody = signupOAuthSchema.parse(req.body)
        const ipAddress = req.ip
        const userAgent =
            typeof req.headers["user-agent"] === "string"
                ? req.headers["user-agent"]
                : undefined

        // signupwithoauth handles getting the email and avatar url from the oauth table that already exists
        const result = await signupWithOAuth({
            provider: parsedBody.provider,
            signupToken: parsedBody.signupToken,
            username: parsedBody.username,
        }, { ipAddress, userAgent })

        res.setCookie(SESSION_COOKIE_NAME, result.sessionToken, {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
            maxAge: 60 * 60 * 24 * 365,
        })

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    id: result.userId
                }
            }
        })
    })

    /**
     * Mobile OAuth: after browser-based callback, app receives `sessionToken`
     * via deep link and then exchanges it for an HttpOnly session cookie in the
     * app's networking context.
     */
    app.post("/session/exchange", async (req, res) => {
        const parsedBody = exchangeSessionSchema.parse(req.body)
        res.setCookie(SESSION_COOKIE_NAME, parsedBody.sessionToken, {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
            maxAge: 60 * 60 * 24 * 365,
        })
        return sendSuccess(res, { ok: true })
    })

    app.post("/logout", { preHandler: [app.preAuthenticate] }, async (req, res) => {
        const token = req.cookies.session
        if (!token) {
            return res.status(401).send({ error: "Unauthorized" })
        }

        await revokeSession(token)
        clearWebAuthCookies(res)
        return res.status(200).send({
            success: true,
        })
    })

    app.post("/logout/all", { preHandler: [app.authenticate] }, async (req, res) => {
        await revokeAllUserSessions(req.userId)
        clearWebAuthCookies(res)
        return res.status(200).send({
            success: true,
        })
    })

    app.get("/me/sessions", { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('authn').from('sessions').select('id, expires_at, user_agent, created_at, refreshed_at').eq('user_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: data })
    })

    app.post("/me/sessions/:id/revoke", { preHandler: app.authenticate }, async (req, res) => {
        const { id } = req.params as { id: string }
        const { data, error } = await supabase.schema('authn').from('sessions').delete().eq('id', id).eq('user_id', req.userId)
        if (error) { return res.status(500).send({ error: error.message }) }
        return res.status(200).send({ success: true, result: data })
    })

    app.post("/me/sessions/all/revoke", { preHandler: app.authenticate }, async (req, res) => {
        await revokeAllUserSessions(req.userId)
        clearWebAuthCookies(res)
        return res.status(200).send({ success: true })
    })

    app.get("/session", { preHandler: app.preAuthenticate }, async (req, res) => { // quick check if session is valid; if so return true

        const { data: user, error: userError } = await supabase
            .schema("authn")
            .from("users")
            .select("id, avatar_url, email, email_verified, username")
            .eq("id", req.userId)
            .single()

        if (userError) { return sendError(res, "USER_NOT_FOUND", userError.message, 404) }

        return sendSuccess(res, {
            user: {
                id: req.userId,
                avatarUrl: user.avatar_url,
                email: user.email,
                username: user.username ?? null,
            },
            emailVerified: user.email_verified,
        })

    })


    // for apple: delete account
    app.post('/me/delete', { preHandler: app.authenticate }, async (req, res) => {
        const { data, error } = await supabase.schema('authn').from('users').delete().eq('id', req.userId).select('*').single()

        if (error) { return sendError(res, "USER_DELETE_FAILED", error.message, 500) }

        const { error: delRequestError } = await supabase.from('delete_requests').insert({
            user_id: req.userId
        })
        if (delRequestError) { return sendError(res, "DELETE_REQUEST_FAILED", delRequestError.message, 500) }

        return sendSuccess(res, { message: "User deleted successfully — awaiting further review." })
    })
}

export default authRoutes