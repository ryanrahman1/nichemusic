const userSockets = new Map<string, Set<any>>();

export function addSocket(userId: string, socket: any) {
    if (!socket || typeof socket.readyState !== "number") return;
    if (!userSockets.has(userId)) {
        userSockets.set(userId, new Set());
    }
    userSockets.get(userId)!.add(socket);
}

export function removeSocket(userId: string, socket: any) {
    const set = userSockets.get(userId);
    if (!set) return;
    if (!socket) return;

    set.delete(socket);
    if (set.size === 0) {
        userSockets.delete(userId);
    }
}

export function emitToUser(userId: string, event: any) {
    const sockets = userSockets.get(userId);
    if (!sockets) return;

    const msg = JSON.stringify(event);

    for (const ws of sockets) {
        if (ws == null || typeof ws.readyState !== "number") continue;
        if (ws.readyState === ws.OPEN) {
            try {
                ws.send(msg);
            } catch {
                // stale / half-closed socket; drop on next close
            }
        }
    }
}

export function hasActiveSocket(userId: string) {
    const sockets = userSockets.get(userId);
    if (!sockets || sockets.size === 0) return false;

    for (const ws of sockets) {
        if (ws == null || typeof ws.readyState !== "number") continue;
        if (ws.readyState === ws.OPEN) {
            return true;
        }
    }

    return false;
}