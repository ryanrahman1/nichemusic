/** Query strings decode '+' as space; repair offset timestamps from clients. */
export function normalizeQueryDateTime(value: string): string {
    const trimmed = value.trim()
    if (/[+-]\d{2}:\d{2}$/.test(trimmed) || trimmed.endsWith("Z")) return trimmed

    const repaired = trimmed.match(/^(.+T\d{2}:\d{2}:\d{2}(?:\.\d+)?) (\d{2}:\d{2})$/)
    if (repaired) return `${repaired[1]}+${repaired[2]}`

    return trimmed
}

/** URL-safe UTC cursor timestamp (always ends with Z). */
export function toUtcZulu(value: string): string {
    const ms = Date.parse(normalizeQueryDateTime(value))
    if (Number.isNaN(ms)) return value
    return new Date(ms).toISOString()
}

export function encodePostListCursor(createdAt: string, cursorId: string): string {
    return JSON.stringify({
        cursorCreatedAt: toUtcZulu(createdAt),
        cursorId,
    })
}
