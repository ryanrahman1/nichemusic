//helpers

import { supabase } from "../../config/supabase.js"


export async function checkFollowing(userId: string, otherUserId: string) {
    const { data, error } = await supabase.schema('public').from('follows').select('*').eq('follower_id', userId).eq('following_id', otherUserId).maybeSingle()
    if (error) { throw new Error(error.message) }
    if (!data) { return false } else { return true }
}