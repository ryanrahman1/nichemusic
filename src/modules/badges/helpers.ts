export type BadgeHolderCursor = {
    index: number
    userId: string
}

export function encodeBadgeHolderCursor(input: BadgeHolderCursor) {
    return JSON.stringify(input)
}

export function decodeBadgeHolderCursor(raw?: string): BadgeHolderCursor | null {
    if (!raw?.trim()) return null

    try {
        const parsed = JSON.parse(raw) as { index?: unknown; userId?: unknown }
        if (typeof parsed.index === "number" && typeof parsed.userId === "string" && parsed.userId.length > 0) {
            return { index: parsed.index, userId: parsed.userId }
        }
    } catch {
        return null
    }

    return null
}
