import { supabase } from "../../config/supabase.js"
import { env } from "../../config/env.js"

export async function slugifyString(str: string): Promise<string> {
    return str.toLowerCase().replace(/ /g, "-").replace(/[^\w-]+/g, "")
}

export async function checkSlugAvailability(slug: string): Promise<boolean> { // check if slug is available
    const { data, error } = await supabase.schema('public').from('groups').select('*').eq('slug', slug).maybeSingle()
    if (error) throw new Error(error.message)
    return !data
}

export async function getPublicUrl(objectKey: string): Promise<string> {
    return `${env.r2.publicBaseUrl}/avatars/${objectKey}`
}