import { supabase } from "../../config/supabase.js"

export type LegalDocumentRow = {
    id: string
    slug: string
    version: string
    title: string
    content: string
    is_active: boolean
    effective_at: string | null
    created_at: string
    updated_at: string
}

const LEGAL_SELECT =
    "id, slug, version, title, content, is_active, effective_at, created_at, updated_at"

// camelCase the row so the site doesnt have to think about postgres
function formatLegalDocument(row: LegalDocumentRow) {
    return {
        id: row.id,
        slug: row.slug,
        version: row.version,
        title: row.title,
        content: row.content,
        isActive: row.is_active,
        effectiveAt: row.effective_at,
        createdAt: row.created_at,
        updatedAt: row.updated_at,
    }
}

export async function listActiveLegalDocuments() {
    const { data, error } = await supabase
        .schema("public")
        .from("legal_documents")
        .select(LEGAL_SELECT)
        .eq("is_active", true)
        .order("slug", { ascending: true })

    if (error) throw new Error(error.message)
    return (data ?? []).map((row) => formatLegalDocument(row as LegalDocumentRow))
}

export async function getActiveLegalDocument(slug: string) {
    const { data, error } = await supabase
        .schema("public")
        .from("legal_documents")
        .select(LEGAL_SELECT)
        .eq("slug", slug)
        .eq("is_active", true)
        .maybeSingle()

    if (error) throw new Error(error.message)
    if (!data) throw new Error("LEGAL_DOCUMENT_NOT_FOUND")
    return formatLegalDocument(data as LegalDocumentRow)
}
