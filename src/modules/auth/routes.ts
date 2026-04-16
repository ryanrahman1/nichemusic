import { FastifyPluginAsync } from "fastify"
import { SignupEmailSchema, signupEmailSchema, loginEmailSchema, LoginEmailSchema, googleCallbackQuerySchema, SignupOAuthSchema, signupOAuthSchema, exchangeSessionSchema } from "./schemas.js"
import { signupWithEmail, loginWithEmail, revokeSession, revokeAllUserSessions, generateOAuthState, buildGoogleAuthUrl, handleGoogleCallback, SESSION_COOKIE_NAME, OAUTH_STATE_COOKIE_NAME, signupWithOAuth } from "../../lib/auth.js"
import { getAvatarPresignedUrl } from "../../lib/image.js"
import { supabase } from "../../config/supabase.js"
import env from "../../config/env.js"
import { sendError, sendSuccess } from "../../global/response.js"


// signup flow: post to signup -> client gets url, uploads the image -> on success, client makes patch request to /auth/me/avatar with the object key and avatar url

const authRoutes: FastifyPluginAsync = async (app) => {
    app.post("/signup/email", async (req, res) => {

        const parsedBody: SignupEmailSchema = signupEmailSchema.parse(req.body)
        const ipAddress = req.ip
        const userAgent = typeof req.headers['user-agent'] === 'string' ? req.headers['user-agent'] : undefined


        const result = await signupWithEmail({ ...parsedBody }, { ipAddress, userAgent })

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

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    id: result.userId,
                },
                avatarUpload: parsedBody.choseAvatar ? {
                    uploadUrl: uploadUrl,
                    avatarUrl: avatarUrl,
                    objectKey: objectKey,
                    contentType: contentType,
                    maxBytes: maxBytes,
                } : null,
            }
        })
    })

    app.patch("/auth/me/avatar", { preHandler: [app.authenticate] }, async (req, res) => {
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
            },
        })
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

    app.post("/logout", { preHandler: [app.authenticate] }, async (req, res) => {
        const token = req.cookies.session
        if (!token) {
            return res.status(401).send({ error: "Unauthorized" })
        }

        await revokeSession(token)
        res.clearCookie("session", {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
        })
        return res.status(200).send({
            success: true,
        })
    })

    app.post("/logout/all", { preHandler: [app.authenticate] }, async (req, res) => {
        await revokeAllUserSessions(req.userId)
        res.clearCookie("session", {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
        })
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
        res.clearCookie("session", {
            httpOnly: true,
            secure: env.state === "production",
            sameSite: "lax",
            path: "/",
        })
        return res.status(200).send({ success: true })
    })

    app.get("/session", { preHandler: app.authenticate }, async (req, res) => { // quick check if session is valid; if so return true

        return sendSuccess(res, { authenticated: true }) // if the route works then it means that the session check succeeded, so just retunr true

    }) 
}

export default authRoutes