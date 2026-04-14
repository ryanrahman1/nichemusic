const userSockets = new Map<string, Set<any>>();

export function addSocket(userId: string, socket: any) {
    if (!userSockets.has(userId)) {
        userSockets.set(userId, new Set());
    }
    userSockets.get(userId)!.add(socket);
}

export function removeSocket(userId: string, socket: any) {
    const set = userSockets.get(userId);
    if (!set) return;

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
        if (ws.readyState === ws.OPEN) {
            ws.send(msg);
        }
    }
}

export function hasActiveSocket(userId: string) {
    const sockets = userSockets.get(userId);
    if (!sockets || sockets.size === 0) return false;

    for (const ws of sockets) {
        if (ws.readyState === ws.OPEN) {
            return true;
        }
    }

    return false;
}