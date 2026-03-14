// fastify
import fastify from "fastify"
import cors from "@fastify/cors"
import cookie from "@fastify/cookie"
import multipart from "@fastify/multipart"
import rateLimit from "@fastify/rate-limit"

import authenticatePlugin from "./plugins/authenticate.js"
import env from "./config/env.js"

// routes
import authRoutes from "./modules/auth/routes.js"
import profileRoutes from "./modules/profile/routes.js"


const app = fastify({ logger: true })

app.register(cookie)
app.register(multipart)
app.register(authenticatePlugin)
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


export default app