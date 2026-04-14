// fastify
import fastify from "fastify"
import cors from "@fastify/cors"
import cookie from "@fastify/cookie"
import multipart from "@fastify/multipart"
import rateLimit from "@fastify/rate-limit"
import websocket from "@fastify/websocket"

import { authenticate, optionalAuthenticate } from "./plugins/authenticate.js"
import requestLoggerPlugin from "./plugins/requestLogger.js"
import env from "./config/env.js"

// routes
import authRoutes from "./modules/auth/routes.js"
import profileRoutes from "./modules/profile/routes.js"
import postsRoutes from "./modules/posts/routes.js"
import groupsRoutes from "./modules/groups/routes.js"
import musicRoutes from "./modules/music/routes.js"
import notificationsRoutes from "./modules/notifications/routes.js"
import searchRoutes from "./modules/search/routes.js"
import feedRoutes from "./modules/feed/routes.js"
import shareRoutes from "./modules/share/routes.js"
import messagesRoutes from "./modules/messages/routes.js"


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
app.register(optionalAuthenticate)
app.register(requestLoggerPlugin)
app.register(cors, {
    origin: env.state === 'production'
        ? ['https://nichemusic.app', 'https://www.nichemusic.app']
        : ['http://localhost:3000', 'http://localhost:5173'],
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
app.register(notificationsRoutes)
app.register(searchRoutes)
app.register(feedRoutes)
app.register(shareRoutes, { prefix: "/public/share" })
app.register(messagesRoutes)


export default app