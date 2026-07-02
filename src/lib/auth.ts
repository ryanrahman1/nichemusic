import crypto from "crypto"
import argon2 from "argon2"
import { createRemoteJWKSet, jwtVerify } from "jose"
import { supabase } from "../config/supabase.js"
import env from "../config/env.js"

const SESSION_TTL_MS = 1000 * 60 * 60 * 24 * 365 // 1 year
const SESSION_REFRESH_WINDOW_MS = 1000 * 60 * 60 * 24 * 30 // 30 days
const OAUTH_SIGNUP_STATE_TTL_MS = 1000 * 60 * 10 // 10 min
const EMAIL_TOKEN_TTL_MS = 1000 * 60 * 60 * 24 // 24h
const RESET_TOKEN_TTL_MS = 1000 * 60 * 30 // 30 min

const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
const GOOGLE_USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"

const APPLE_AUTH_URL = "https://appleid.apple.com/auth/authorize"
const APPLE_TOKEN_URL = "https://appleid.apple.com/auth/token"

const googleJwks = createRemoteJWKSet(new URL("https://www.googleapis.com/oauth2/v3/certs"))
const appleJwks = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"))

export const SESSION_COOKIE_NAME = "session"
export const OAUTH_STATE_COOKIE_NAME = "oauth_state"

export type OAuthProvider = "google" | "apple"

export type SessionAuthResult = {
    sessionId: string
    userId: string
    emailVerified: boolean
}

export type ProfileType = "artist" | "user" | "producer" | "dj"

export type SignupEmailInput = {
    email: string
    password: string
    username: string
    profileType?: ProfileType
    avatarUrl?: string | undefined
}

export type SignupOAuthInput = {
    provider: OAuthProvider
    signupToken: string
    username: string
    profileType?: ProfileType
}

export type UsernameAvailabilityResult = {
    available: boolean
    reason?: "invalid" | "taken"
    message?: string
}

export type AuthSuccess = {
    kind: "authenticated"
    userId: string
    sessionToken: string
    avatarUrl: string | null
}

export type OAuthNeedsSignup = {
    kind: "needs_signup"
    provider: OAuthProvider
    signupToken: string
    email: string | null
    avatarUrl: string | null
}

export type OAuthCallbackResult = AuthSuccess | OAuthNeedsSignup

type OAuthSignupStateRecord = {
    id: string
    provider: OAuthProvider
    provider_user_id: string
    email: string | null
    avatar_url: string | null
    expires_at: string
}

export function generateRandomId(bytes = 16): string {
    // generate random id, filter out dashes, underscores, and plus signs to make it more URL-friendly
    return crypto.randomBytes(bytes).toString("base64url").replace(/[-_]/g, "")
}

export function sha256(input: string): string {
    return crypto.createHash("sha256").update(input).digest("hex")
}

export async function hashPassword(password: string): Promise<string> {
    return argon2.hash(password, {
        type: argon2.argon2id,
    })
}

export async function verifyPassword(hash: string, password: string): Promise<boolean> {
    return argon2.verify(hash, password)
}

function normalizeEmail(email: string): string {
    return email.trim().toLowerCase()
}

const USERNAME_PATTERN = /^[a-z0-9_.]{3,30}$/

function normalizeUsername(username: string): string {
    return username.trim().toLowerCase()
}

export function validateUsernameFormat(username: string): string | null {
    const normalized = normalizeUsername(username)
    if (!normalized) return "Username is required"
    if (normalized.length < 3) return "Username must be at least 3 characters"
    if (normalized.length > 30) return "Username must be at most 30 characters"
    if (!USERNAME_PATTERN.test(normalized)) {
        return "Username may only contain lowercase letters, numbers, underscores, and periods"
    }
    return null
}

function futureIso(msFromNow: number): string {
    return new Date(Date.now() + msFromNow).toISOString()
}

function requireNonEmpty(value: string, message: string) {
    if (!value.trim()) throw new Error(message)
}

function requireValidPassword(password: string) {
    if (!password || password.length < 8) {
        throw new Error("Password must be at least 8 characters")
    }
    if (!/[A-Z]/.test(password)) {
        throw new Error("Password must contain at least one uppercase letter")
    }
    if (!/[0-9]/.test(password)) {
        throw new Error("Password must contain at least one number")
    }
}

function isUniqueViolation(error: { code?: string; message?: string } | null | undefined): boolean {
    return error?.code === "23505"
}

function mapInsertUserError(error: { code?: string; message?: string }): Error {
    if (isUniqueViolation(error)) {
        const message = error.message ?? ""
        if (message.includes("users_email_key") || message.includes("email")) {
            return new SignupConflictError("EMAIL_TAKEN", "An account with this email already exists")
        }
        if (message.includes("users_username_key") || message.includes("username")) {
            return new SignupConflictError("USERNAME_TAKEN", "This username is already taken")
        }
        return new SignupConflictError("CONFLICT", "Account already exists")
    }
    return new Error(error?.message ?? "Failed to create account")
}

export class PasswordResetSamePasswordError extends Error {
    readonly code = "PASSWORD_RESET_SAME_AS_CURRENT" as const

    constructor(message = "Your new password must be different from your current password.") {
        super(message)
        this.name = "PasswordResetSamePasswordError"
    }
}

export class SignupConflictError extends Error {
    constructor(
        public readonly code: "EMAIL_TAKEN" | "USERNAME_TAKEN" | "CONFLICT",
        message: string
    ) {
        super(message)
        this.name = "SignupConflictError"
    }
}

async function setProfileType(userId: string, profileType: ProfileType): Promise<void> {
    const { error } = await supabase
        .schema("public")
        .from("profiles")
        .update({
            profile_type: profileType,
            type_updated_at: new Date().toISOString(),
        })
        .eq("id", userId)

    if (error) throw new Error(error.message)
}

export async function checkUsernameAvailability(username: string): Promise<UsernameAvailabilityResult> {
    const normalized = normalizeUsername(username)
    const formatError = validateUsernameFormat(normalized)
    if (formatError) {
        return {
            available: false,
            reason: "invalid",
            message: formatError,
        }
    }

    const { data, error } = await supabase
        .schema("authn")
        .from("users")
        .select("id")
        .eq("username", normalized)
        .maybeSingle()

    if (error) throw new Error(error.message)

    if (data) {
        return {
            available: false,
            reason: "taken",
            message: "This username is already taken",
        }
    }

    return { available: true }
}

async function getUserByEmail(email: string) {
    const { data, error } = await supabase
        .schema("authn")
        .from("users")
        .select("id, email, username, email_verified, avatar_url")
        .eq("email", email)
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data
}

async function getOAuthAccount(provider: OAuthProvider, providerUserId: string) {
    const { data, error } = await supabase
        .schema("authn")
        .from("oauth_accounts")
        .select("id, user_id, provider, provider_user_id")
        .eq("provider", provider)
        .eq("provider_user_id", providerUserId)
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data
}

async function insertUser(params: {
    email: string | null
    username: string
    emailVerified: boolean
    avatarUrl?: string | null
}): Promise<string> {
    const userId = generateRandomId(16)

    const { error } = await supabase
        .schema("authn")
        .from("users")
        .insert({
            id: userId,
            email: params.email,
            username: params.username,
            email_verified: params.emailVerified,
            avatar_url: params.avatarUrl ?? null,
        })

    if (error) throw mapInsertUserError(error)
    return userId
}

async function insertPassword(userId: string, password: string): Promise<void> {
    const passwordHash = await hashPassword(password)

    const { error } = await supabase
        .schema("authn")
        .from("user_passwords")
        .insert({
            user_id: userId,
            password_hash: passwordHash,
        })

    if (error) throw new Error(error.message)
}

async function insertOAuthAccount(params: {
    userId: string
    provider: OAuthProvider
    providerUserId: string
}): Promise<void> {
    const { error } = await supabase
        .schema("authn")
        .from("oauth_accounts")
        .insert({
            id: generateRandomId(16),
            user_id: params.userId,
            provider: params.provider,
            provider_user_id: params.providerUserId,
        })

    if (error) throw new Error(error.message)
}

async function deleteUserById(userId: string): Promise<void> {
    await supabase.schema("authn").from("users").delete().eq("id", userId)
}

/**
 * Cookie-backed server session.
 * Store raw token in cookie, store only token_hash in DB.
 */
export async function createSession(
    userId: string,
    ipAddress?: string,
    userAgent?: string
): Promise<string> {
    const sessionId = generateRandomId(16)
    const rawToken = generateRandomId(32)
    const tokenHash = sha256(rawToken)

    const { error } = await supabase
        .schema("authn")
        .from("sessions")
        .insert({
            id: sessionId,
            user_id: userId,
            token_hash: tokenHash,
            expires_at: futureIso(SESSION_TTL_MS),
            ip_address: ipAddress ?? null,
            user_agent: userAgent ?? null,
        })

    if (error) throw new Error(error.message)
    return rawToken
}

/**
 * Lightweight auth check for Fastify preHandler.
 */
export async function authenticateSessionToken(rawToken: string): Promise<SessionAuthResult | null> {
    const tokenHash = sha256(rawToken)

    const { data, error } = await supabase
        .schema("authn")
        .from("sessions")
        .select("id, user_id, expires_at, users!inner(email_verified)")
        .eq("token_hash", tokenHash)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) return null

    const expiresAtMs = new Date(data.expires_at).getTime()
    const now = Date.now()

    if (expiresAtMs <= now) {
        await supabase.schema("authn").from("sessions").delete().eq("id", data.id)
        return null
    }

    if (expiresAtMs - now <= SESSION_REFRESH_WINDOW_MS) {
        await supabase
            .schema("authn")
            .from("sessions")
            .update({
                expires_at: futureIso(SESSION_TTL_MS),
                refreshed_at: new Date().toISOString(),
            })
            .eq("id", data.id)
    }

    const users = data.users
    const user = Array.isArray(users) ? users[0] : users

    return {
        sessionId: data.id,
        userId: data.user_id,
        emailVerified: user?.email_verified === true,
    }
}

/**
 * Heavier helper for /auth/me or device/session management screens.
 */
export async function getSessionFromToken(rawToken: string) {
    const tokenHash = sha256(rawToken)

    const { data, error } = await supabase
        .schema("authn")
        .from("sessions")
        .select(`
            id,
            user_id,
            expires_at,
            created_at,
            refreshed_at,
            ip_address,
            user_agent
        `)
        .eq("token_hash", tokenHash)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) return null

    const authResult = await authenticateSessionToken(rawToken)
    if (!authResult) return null

    const { data: user, error: userError } = await supabase
        .schema("authn")
        .from("users")
        .select("id, username, email, email_verified, avatar_url, created_at")
        .eq("id", authResult.userId)
        .single()

    if (userError) throw new Error(userError.message)

    return {
        session: data,
        user,
    }
}

export async function revokeSession(rawToken: string): Promise<void> {
    const tokenHash = sha256(rawToken)

    const { error } = await supabase
        .schema("authn")
        .from("sessions")
        .delete()
        .eq("token_hash", tokenHash)

    if (error) throw new Error(error.message)
}

export async function revokeAllUserSessions(userId: string): Promise<void> {
    const { error } = await supabase
        .schema("authn")
        .from("sessions")
        .delete()
        .eq("user_id", userId)

    if (error) throw new Error(error.message)
}

export async function signupWithEmail(
    input: SignupEmailInput,
    meta?: { ipAddress?: string | undefined; userAgent?: string | undefined }
): Promise<AuthSuccess> {
    const email = normalizeEmail(input.email)
    const username = normalizeUsername(input.username)
    const profileType: ProfileType = input.profileType ?? "user"

    requireNonEmpty(email, "Email is required")
    requireNonEmpty(username, "Username is required")
    const usernameError = validateUsernameFormat(username)
    if (usernameError) throw new Error(usernameError)
    requireValidPassword(input.password)

    let userId: string | null = null

    try {
        userId = await insertUser({
            email,
            username,
            emailVerified: false,
        })

        await insertPassword(userId, input.password)
        await setProfileType(userId, profileType)

        const sessionToken = await createSession(userId, meta?.ipAddress, meta?.userAgent)

        return {
            kind: "authenticated",
            userId,
            sessionToken,
            avatarUrl: null,
        }
    } catch (error) {
        if (userId) await deleteUserById(userId)
        throw error
    }
}

export async function loginWithEmail(
    email: string,
    password: string,
    meta?: { ipAddress?: string | undefined; userAgent?: string | undefined }
): Promise<AuthSuccess> {
    const normalizedEmail = normalizeEmail(email)

    const { data, error } = await supabase
        .schema("authn")
        .from("users")
        .select(`
      id,
      email,
      avatar_url,
      user_passwords (
        password_hash
      )
    `)
        .eq("email", normalizedEmail)
        .single()

    if (error || !data) {
        throw new Error("Invalid email or password")
    }

    const passwordHash =
        Array.isArray(data.user_passwords)
            ? data.user_passwords[0]?.password_hash
            : (data.user_passwords as { password_hash?: string } | null)?.password_hash

    if (!passwordHash) {
        throw new Error("Invalid email or password")
    }

    const ok = await verifyPassword(passwordHash, password)
    if (!ok) throw new Error("Invalid email or password")

    const sessionToken = await createSession(data.id, meta?.ipAddress, meta?.userAgent)

    return {
        kind: "authenticated",
        userId: data.id,
        sessionToken,
        avatarUrl: data.avatar_url,
    }
}

/**
 * OAuth state for CSRF protection.
 * Route layer should set this in a short-lived HttpOnly cookie,
 * then callback should compare cookie vs query/body state.
 */
export function generateOAuthState(): string {
    return generateRandomId(16)
}

export function buildGoogleAuthUrl(state: string): string {
    const url = new URL(GOOGLE_AUTH_URL)

    url.searchParams.set("client_id", env.google.clientId)
    url.searchParams.set("redirect_uri", env.google.redirectUri)
    url.searchParams.set("response_type", "code")
    url.searchParams.set("scope", "openid email profile")
    url.searchParams.set("state", state)
    url.searchParams.set("access_type", "offline")
    url.searchParams.set("prompt", "select_account")

    return url.toString()
}

export function buildAppleAuthUrl(state: string): string {
    const url = new URL(APPLE_AUTH_URL)

    url.searchParams.set("client_id", env.apple.clientId)
    url.searchParams.set("redirect_uri", env.apple.redirectUri)
    url.searchParams.set("response_type", "code")
    url.searchParams.set("response_mode", "form_post")
    url.searchParams.set("scope", "name email")
    url.searchParams.set("state", state)

    return url.toString()
}

async function exchangeGoogleCode(code: string) {
    const body = new URLSearchParams({
        code,
        client_id: env.google.clientId,
        client_secret: env.google.clientSecret,
        redirect_uri: env.google.redirectUri,
        grant_type: "authorization_code",
    })

    const res = await fetch(GOOGLE_TOKEN_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/x-www-form-urlencoded",
        },
        body,
    })

    if (!res.ok) {
        throw new Error("Failed to exchange Google code")
    }

    return res.json() as Promise<{
        access_token: string
        id_token: string
        refresh_token?: string
        expires_in: number
        token_type: string
        scope?: string
    }>
}

async function verifyGoogleIdToken(idToken: string) {
    const verified = await jwtVerify(idToken, googleJwks, {
        issuer: ["https://accounts.google.com", "accounts.google.com"],
        audience: env.google.clientId,
    })

    const payload = verified.payload

    return {
        providerUserId: String(payload.sub),
        email: typeof payload.email === "string" ? payload.email : null,
        emailVerified: payload.email_verified === true,
        picture: typeof payload.picture === "string" ? payload.picture : null,
    }
}

async function fetchGoogleUserInfo(accessToken: string) {
    const res = await fetch(GOOGLE_USERINFO_URL, {
        headers: {
            Authorization: `Bearer ${accessToken}`,
        },
    })

    if (!res.ok) {
        throw new Error("Failed to fetch Google profile")
    }

    return res.json() as Promise<{
        sub: string
        email?: string
        email_verified?: boolean
        picture?: string
    }>
}

async function exchangeAppleCode(code: string) {
    const body = new URLSearchParams({
        code,
        client_id: env.apple.clientId,
        client_secret: env.apple.clientSecret,
        redirect_uri: env.apple.redirectUri,
        grant_type: "authorization_code",
    })

    const res = await fetch(APPLE_TOKEN_URL, {
        method: "POST",
        headers: {
            "Content-Type": "application/x-www-form-urlencoded",
        },
        body,
    })

    if (!res.ok) {
        throw new Error("Failed to exchange Apple code")
    }

    return res.json() as Promise<{
        access_token: string
        expires_in: number
        id_token: string
        refresh_token?: string
        token_type: string
    }>
}

async function verifyAppleIdToken(idToken: string) {
    const verified = await jwtVerify(idToken, appleJwks, {
        issuer: "https://appleid.apple.com",
        audience: env.apple.clientId,
    })

    const payload = verified.payload

    return {
        providerUserId: String(payload.sub),
        email: typeof payload.email === "string" ? payload.email : null,
        emailVerified: payload.email_verified === true || payload.email_verified === "true",
    }
}

/**
 * Temporary OAuth signup state.
 * Needed because your frontend wants user to choose username manually.
 *
 * Table needed:
 * authn.oauth_signup_states (
 *   id text primary key,
 *   provider text not null,
 *   provider_user_id text not null,
 *   email text,
 *   avatar_url text,
 *   token_hash text not null unique,
 *   expires_at timestamptz not null,
 *   created_at timestamptz not null default now()
 * )
 */
async function createOAuthSignupState(params: {
    provider: OAuthProvider
    providerUserId: string
    email: string | null
    avatarUrl: string | null
}): Promise<string> {
    const rawToken = generateRandomId(32)
    const tokenHash = sha256(rawToken)

    const { error } = await supabase
        .schema("authn")
        .from("oauth_signup_states")
        .insert({
            id: generateRandomId(16),
            provider: params.provider,
            provider_user_id: params.providerUserId,
            email: params.email,
            avatar_url: params.avatarUrl,
            token_hash: tokenHash,
            expires_at: futureIso(OAUTH_SIGNUP_STATE_TTL_MS),
        })

    if (error) throw new Error(error.message)
    return rawToken
}

async function consumeOAuthSignupState(signupToken: string): Promise<OAuthSignupStateRecord> {
    const tokenHash = sha256(signupToken)

    const { data, error } = await supabase
        .schema("authn")
        .from("oauth_signup_states")
        .select("id, provider, provider_user_id, email, avatar_url, expires_at")
        .eq("token_hash", tokenHash)
        .single()

    if (error || !data) {
        throw new Error("Invalid or expired signup token")
    }

    if (new Date(data.expires_at).getTime() <= Date.now()) {
        await supabase.schema("authn").from("oauth_signup_states").delete().eq("id", data.id)
        throw new Error("Invalid or expired signup token")
    }

    await supabase.schema("authn").from("oauth_signup_states").delete().eq("id", data.id)

    return data as OAuthSignupStateRecord
}

/**
 * Called by /auth/signup when frontend already completed Google/Apple callback
 * but user still needs to choose a username.
 */
export async function signupWithOAuth(
    input: SignupOAuthInput,
    meta?: { ipAddress?: string | undefined; userAgent?: string | undefined }
): Promise<AuthSuccess> {
    const username = normalizeUsername(input.username)
    const profileType: ProfileType = input.profileType ?? "user"
    requireNonEmpty(username, "Username is required")
    const usernameError = validateUsernameFormat(username)
    if (usernameError) throw new Error(usernameError)

    const pending = await consumeOAuthSignupState(input.signupToken)

    if (pending.provider !== input.provider) {
        throw new Error("Provider mismatch")
    }

    const existingOAuth = await getOAuthAccount(pending.provider, pending.provider_user_id)
    if (existingOAuth) {
        const sessionToken = await createSession(existingOAuth.user_id, meta?.ipAddress, meta?.userAgent)
        return {
            kind: "authenticated",
            userId: existingOAuth.user_id,
            sessionToken,
            avatarUrl: null,
        }
    }

    if (pending.email) {
        const existingUserByEmail = await getUserByEmail(pending.email)
        if (existingUserByEmail) {
            throw new Error("An account with this email already exists")
        }
    }

    let userId: string | null = null

    try {
        userId = await insertUser({
            email: pending.email,
            username,
            emailVerified: true,
            avatarUrl: pending.avatar_url,
        })

        await insertOAuthAccount({
            userId,
            provider: pending.provider,
            providerUserId: pending.provider_user_id,
        })

        await setProfileType(userId, profileType)

        const sessionToken = await createSession(userId, meta?.ipAddress, meta?.userAgent)

        return {
            kind: "authenticated",
            userId,
            sessionToken,
            avatarUrl: null,
        }
    } catch (error) {
        if (userId) await deleteUserById(userId)
        throw error
    }
}

export async function handleGoogleCallback(
    code: string,
    meta?: { ipAddress?: string | undefined; userAgent?: string | undefined }
): Promise<OAuthCallbackResult> {
    const tokens = await exchangeGoogleCode(code)
    const idProfile = await verifyGoogleIdToken(tokens.id_token)
    const userInfo = await fetchGoogleUserInfo(tokens.access_token)

    const providerUserId = idProfile.providerUserId || userInfo.sub
    const email = idProfile.email ?? userInfo.email ?? null
    const avatarUrl = idProfile.picture ?? userInfo.picture ?? null

    const existingOAuth = await getOAuthAccount("google", providerUserId)
    if (existingOAuth) {
        const sessionToken = await createSession(existingOAuth.user_id, meta?.ipAddress, meta?.userAgent)
        return {
            kind: "authenticated",
            userId: existingOAuth.user_id,
            sessionToken,
            avatarUrl: null,
        }
    }

    const signupToken = await createOAuthSignupState({
        provider: "google",
        providerUserId,
        email,
        avatarUrl,
    })

    return {
        kind: "needs_signup",
        provider: "google",
        signupToken,
        email,
        avatarUrl,
    }
}

export async function handleAppleCallback(
    code: string,
    meta?: { ipAddress?: string; userAgent?: string }
): Promise<OAuthCallbackResult> {
    const tokens = await exchangeAppleCode(code)
    const profile = await verifyAppleIdToken(tokens.id_token)

    const existingOAuth = await getOAuthAccount("apple", profile.providerUserId)
    if (existingOAuth) {
        const sessionToken = await createSession(existingOAuth.user_id, meta?.ipAddress, meta?.userAgent)
        return {
            kind: "authenticated",
            userId: existingOAuth.user_id,
            sessionToken,
            avatarUrl: null,
        }
    }

    const signupToken = await createOAuthSignupState({
        provider: "apple",
        providerUserId: profile.providerUserId,
        email: profile.email,
        avatarUrl: null,
    })

    return {
        kind: "needs_signup",
        provider: "apple",
        signupToken,
        email: profile.email,
        avatarUrl: null,
    }
}

/**
 * Future helpers for email verification + password reset
 */
export async function createEmailVerificationToken(userId: string): Promise<string> {
    const rawToken = generateRandomId(32)
    const tokenHash = sha256(rawToken)

    const { error } = await supabase
        .schema("authn")
        .from("email_verifications")
        .insert({
            id: generateRandomId(16),
            user_id: userId,
            token_hash: tokenHash,
            expires_at: futureIso(EMAIL_TOKEN_TTL_MS),
        })

    if (error) throw new Error(error.message)
    return rawToken
}

export async function verifyEmailToken(rawToken: string): Promise<string> {
    const tokenHash = sha256(rawToken)

    const { data, error } = await supabase
        .schema("authn")
        .from("email_verifications")
        .select("id, user_id, expires_at")
        .eq("token_hash", tokenHash)
        .single()

    if (error || !data) throw new Error("Invalid or expired verification token")

    if (new Date(data.expires_at).getTime() <= Date.now()) {
        await supabase.schema("authn").from("email_verifications").delete().eq("id", data.id)
        throw new Error("Invalid or expired verification token")
    }

    const { error: updateError } = await supabase
        .schema("authn")
        .from("users")
        .update({
            email_verified: true,
            updated_at: new Date().toISOString(),
        })
        .eq("id", data.user_id)

    if (updateError) throw new Error(updateError.message)

    await supabase.schema("authn").from("email_verifications").delete().eq("id", data.id)
    return data.user_id
}

async function getUserPasswordHash(userId: string): Promise<string | null> {
    const { data, error } = await supabase
        .schema("authn")
        .from("user_passwords")
        .select("password_hash")
        .eq("user_id", userId)
        .maybeSingle()

    if (error) throw new Error(error.message)
    return data?.password_hash ?? null
}

export async function createPasswordResetToken(email: string): Promise<string | null> {
    const normalizedEmail = normalizeEmail(email)
    const user = await getUserByEmail(normalizedEmail)
    if (!user) return null

    const existingPasswordHash = await getUserPasswordHash(user.id)
    if (!existingPasswordHash) return null

    const now = new Date().toISOString()

    await supabase
        .schema("authn")
        .from("password_reset_tokens")
        .update({ used_at: now })
        .eq("user_id", user.id)
        .is("used_at", null)

    const rawToken = generateRandomId(32)
    const tokenHash = sha256(rawToken)

    const { error } = await supabase
        .schema("authn")
        .from("password_reset_tokens")
        .insert({
            id: generateRandomId(16),
            user_id: user.id,
            token_hash: tokenHash,
            expires_at: futureIso(RESET_TOKEN_TTL_MS),
        })

    if (error) throw new Error(error.message)
    return rawToken
}

export async function resetPasswordWithToken(rawToken: string, newPassword: string): Promise<void> {
    requireValidPassword(newPassword)

    const tokenHash = sha256(rawToken)

    const { data, error } = await supabase
        .schema("authn")
        .from("password_reset_tokens")
        .select("id, user_id, expires_at, used_at")
        .eq("token_hash", tokenHash)
        .single()

    if (error || !data) throw new Error("Invalid or expired reset token")
    if (data.used_at) throw new Error("Invalid or expired reset token")
    if (new Date(data.expires_at).getTime() <= Date.now()) {
        throw new Error("Invalid or expired reset token")
    }

    const existingPasswordHash = await getUserPasswordHash(data.user_id)
    if (existingPasswordHash) {
        const isSamePassword = await verifyPassword(existingPasswordHash, newPassword)
        if (isSamePassword) {
            throw new PasswordResetSamePasswordError()
        }
    }

    const passwordHash = await hashPassword(newPassword)

    const { error: passwordError } = await supabase
        .schema("authn")
        .from("user_passwords")
        .update({
            password_hash: passwordHash,
            updated_at: new Date().toISOString(),
        })
        .eq("user_id", data.user_id)

    if (passwordError) throw new Error(passwordError.message)

    await supabase
        .schema("authn")
        .from("password_reset_tokens")
        .update({
            used_at: new Date().toISOString(),
        })
        .eq("id", data.id)

    await revokeAllUserSessions(data.user_id)
}