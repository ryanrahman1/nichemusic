import type { FastifyPluginAsync } from "fastify"
import { supabase } from "../../config/supabase.js"


const profileRoutes: FastifyPluginAsync = async (app) => {

    app.get('/me', { preHandler: [app.authenticate]}, async (req, res) => {
        const userId = req.userId

        const { data, error } = await supabase.schema('public').from('profiles').select('id, username, avatar_url, created_at').eq('id', userId).single()

        if (error) {
            return res.status(500).send({ error: error.message })
        }

        return res.status(200).send({
            success: true,
            result: {
                user: {
                    ...data
                }
            }
        })
    })

}

export default profileRoutes