// run the app
import app from "./src/app.js"
import env from "./src/config/env.js"

app.listen({port: env.port, host: "0.0.0.0"}, (err) => {
    if (err) {
        app.log.error(err)
        process.exit(1)
    } else {
        app.log.info(`Server is running on port ${env.port}`)
    }
})