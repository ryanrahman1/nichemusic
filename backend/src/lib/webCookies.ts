import type { CookieSerializeOptions } from "@fastify/cookie"
import env from "../config/env.js"

const ONE_YEAR_SEC = 60 * 60 * 24 * 365

// prod web app lives on nichemusic.app, api on api.nichemusic.app — share cookies across subdomains
const WEB_COOKIE_DOMAIN =
    env.state === "production" ? ".nichemusic.app" : undefined

function withDomain(options: CookieSerializeOptions): CookieSerializeOptions {
    if (!WEB_COOKIE_DOMAIN) return options
    return { ...options, domain: WEB_COOKIE_DOMAIN }
}

// session cookie for /login/email/web + /signup/email/web
export function webSessionCookieOptions(): CookieSerializeOptions {
    return withDomain({
        httpOnly: true,
        secure: env.state === "production",
        sameSite: "lax",
        path: "/",
        maxAge: ONE_YEAR_SEC,
    })
}

// readable csrf cookie — nichemusic.app js needs to mirror this into x-csrf-token
export function webCsrfCookieOptions(): CookieSerializeOptions {
    return withDomain({
        httpOnly: false,
        secure: env.state === "production",
        sameSite: "lax",
        path: "/",
        maxAge: ONE_YEAR_SEC,
    })
}

export function webCsrfClearOptions(): CookieSerializeOptions {
    return withDomain({
        httpOnly: false,
        secure: env.state === "production",
        sameSite: "lax",
        path: "/",
        maxAge: 0,
    })
}

export function webSessionClearOptions(): CookieSerializeOptions {
    return withDomain({
        httpOnly: true,
        secure: env.state === "production",
        sameSite: "lax",
        path: "/",
        maxAge: 0,
    })
}

// ios/native login sets host-only session on api.* — clear that too on logout
export function nativeSessionClearOptions(): CookieSerializeOptions {
    return {
        httpOnly: true,
        secure: env.state === "production",
        sameSite: "lax",
        path: "/",
        maxAge: 0,
    }
}

export function clearWebAuthCookies(res: {
    clearCookie: (name: string, options?: CookieSerializeOptions) => void
}) {
    res.clearCookie("session", nativeSessionClearOptions())
    res.clearCookie("session", webSessionClearOptions())
    res.clearCookie("csrfToken", webCsrfClearOptions())
}
