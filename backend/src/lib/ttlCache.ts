type CacheEntry<T> = {
    value: T
    expiresAt: number
}

const stores = new Map<string, Map<string, CacheEntry<unknown>>>()

function getStore(namespace: string) {
    let store = stores.get(namespace)
    if (!store) {
        store = new Map()
        stores.set(namespace, store)
    }
    return store
}

export async function getOrSetCachedValue<T>(options: {
    namespace: string
    key: string
    ttlMs: number
    loader: () => Promise<T>
}): Promise<T> {
    const store = getStore(options.namespace)
    const now = Date.now()
    const hit = store.get(options.key) as CacheEntry<T> | undefined

    if (hit && hit.expiresAt > now) {
        return hit.value
    }

    const value = await options.loader()
    store.set(options.key, {
        value,
        expiresAt: now + options.ttlMs,
    })

    return value
}

export function invalidateCachedNamespace(namespace: string) {
    stores.delete(namespace)
}
