// supabase data api
import { createClient } from "@supabase/supabase-js"
import env from "./env.js"

export const supabase = createClient(env.database.url, env.database.key)

