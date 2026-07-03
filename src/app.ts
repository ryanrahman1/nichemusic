// fastify
import { readFileSync } from "node:fs"
import { join } from "node:path"
import fastify from "fastify"
import cors from "@fastify/cors"
import cookie from "@fastify/cookie"
import multipart from "@fastify/multipart"
import rateLimit from "@fastify/rate-limit"
import websocket from "@fastify/websocket"

import { authenticate, optionalAuthenticate, preAuthenticate } from "./plugins/authenticate.js"
import requestLoggerPlugin from "./plugins/requestLogger.js"
import env from "./config/env.js"

// routes
import authRoutes from "./modules/auth/routes.js"
import profileRoutes from "./modules/profile/routes.js"
import postsRoutes from "./modules/posts/routes.js"
import groupsRoutes from "./modules/groups/routes.js"
import {musicRoutes, nicheMusicRoutes} from "./modules/music/routes.js"
import notificationsRoutes from "./modules/notifications/routes.js"
import searchRoutes from "./modules/search/routes.js"
import feedRoutes from "./modules/feed/routes.js"
import shareRoutes from "./modules/share/routes.js"
import messagesRoutes from "./modules/messages/routes.js"
import moderationRoutes from "./modules/moderation/routes.js"
import musicMatchesRoutes from "./modules/music-matches/routes.js"
import realtimeRoutes from "./global/realtime/realtime.js"
import auxRealtimeRoutes from "./modules/games/auxRealtime.js"
import playlistsRoutes from "./modules/playlists/routes.js"
import badgesRoutes from "./modules/badges/routes.js"
import gamesRoutes from "./modules/games/routes.js"
import { sendSuccess } from "./global/response.js"


const isProd = env.state === "production"

const app = fastify({
    logger: isProd
        ? true
        : {
            level: "info",
            transport: {
                target: "pino-pretty",
                options: {
                    translateTime: "HH:MM:ss",
                    ignore: "pid,hostname",
                    colorize: true,
                    singleLine: true,
                },
            },
        },

    disableRequestLogging: true,
    trustProxy: true,
})

app.register(cookie)
app.register(multipart)
app.register(websocket)
app.register(authenticate)
app.register(preAuthenticate)
app.register(optionalAuthenticate)
app.register(requestLoggerPlugin)
app.register(cors, {
    origin: [
        'https://nichemusic.app',
        'https://www.nichemusic.app',
        'https://auth.nichemusic.app',
        'http://localhost:5173',
        'http://127.0.0.1:8788',
    ],
    credentials: true,
})


app.register(async (app) => {
    app.register(rateLimit, {
        max: 15,
        timeWindow: '1 minute'
    })
    app.register(authRoutes)
})

app.register(profileRoutes)
app.register(postsRoutes)
app.register(groupsRoutes)
app.register(musicRoutes)
app.register(nicheMusicRoutes)
app.register(notificationsRoutes)
app.register(searchRoutes)
app.register(feedRoutes)
app.register(shareRoutes, { prefix: "/public/share" })
app.register(messagesRoutes)
app.register(moderationRoutes)
app.register(musicMatchesRoutes)
app.register(realtimeRoutes)
app.register(auxRealtimeRoutes)
app.register(playlistsRoutes)
app.register(badgesRoutes)
app.register(gamesRoutes)

if (!isProd) {
    app.get("/aux-test", async (_req, res) => {
        const html = readFileSync(join(process.cwd(), "aux-test.html"), "utf8")
        return res.type("text/html").send(html)
    })
}

app.get("/health", (req, res) => {
    return sendSuccess(res, { healthy: true })
})

export default app