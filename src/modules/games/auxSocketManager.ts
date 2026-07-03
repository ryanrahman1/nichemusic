// user-centric socket registry — sockets register on connect, rooms on subscribe

const WS_OPEN = 1

type AuxSocket = {
    readyState: number
    send: (data: string) => void
}

type SocketMeta = {
    roomId: string | null
    userId: string
}

const userSockets = new Map<string, Set<AuxSocket>>()
const roomUsers = new Map<string, Set<string>>()
const socketMeta = new Map<AuxSocket, SocketMeta>()

function addUserSocket(userId: string, socket: AuxSocket) {
    if (!userSockets.has(userId)) {
        userSockets.set(userId, new Set())
    }
    userSockets.get(userId)!.add(socket)
}

function removeUserSocket(userId: string, socket: AuxSocket) {
    const set = userSockets.get(userId)
    if (!set) return
    set.delete(socket)
    if (set.size === 0) {
        userSockets.delete(userId)
    }
}

function trackRoomUser(roomId: string, userId: string) {
    if (!roomUsers.has(roomId)) {
        roomUsers.set(roomId, new Set())
    }
    roomUsers.get(roomId)!.add(userId)
}

function untrackRoomUser(roomId: string, userId: string) {
    const set = roomUsers.get(roomId)
    if (!set) return
    set.delete(userId)
    if (set.size === 0) {
        roomUsers.delete(roomId)
    }
}

/** Called as soon as the WS connection is authenticated. */
export function registerAuxSocket(userId: string, socket: AuxSocket) {
    if (!socket || typeof socket.readyState !== "number") return

    const prior = socketMeta.get(socket)
    if (prior) {
        removeUserSocket(prior.userId, socket)
        if (prior.roomId) {
            untrackRoomUser(prior.roomId, prior.userId)
        }
    }

    socketMeta.set(socket, { roomId: null, userId })
    addUserSocket(userId, socket)
}

/** Subscribe an authenticated socket to a room's broadcast channel. */
export function subscribeAuxSocketToRoom(roomId: string, userId: string, socket: AuxSocket) {
    if (!socket || typeof socket.readyState !== "number") return

    let meta = socketMeta.get(socket)
    if (!meta) {
        registerAuxSocket(userId, socket)
        meta = socketMeta.get(socket)!
    }

    if (meta.userId !== userId) {
        removeUserSocket(meta.userId, socket)
        meta.userId = userId
        addUserSocket(userId, socket)
    }

    if (meta.roomId && meta.roomId !== roomId) {
        untrackRoomUser(meta.roomId, userId)
    }

    meta.roomId = roomId
    trackRoomUser(roomId, userId)
}

export function unregisterAuxSocket(socket: AuxSocket) {
    const meta = socketMeta.get(socket)
    if (!meta) return

    socketMeta.delete(socket)
    removeUserSocket(meta.userId, socket)
    if (meta.roomId) {
        untrackRoomUser(meta.roomId, meta.userId)
    }
}

/** @deprecated use subscribeAuxSocketToRoom */
export function addAuxSocket(roomId: string, userId: string, socket: AuxSocket) {
    registerAuxSocket(userId, socket)
    subscribeAuxSocketToRoom(roomId, userId, socket)
}

export function removeAuxSocket(roomId: string, socket: AuxSocket) {
    const meta = socketMeta.get(socket)
    if (!meta || meta.roomId !== roomId) return

    meta.roomId = null
    untrackRoomUser(roomId, meta.userId)
}

export function removeAuxSocketFromAllRooms(socket: AuxSocket) {
    unregisterAuxSocket(socket)
}

export function emitToAuxUser(userId: string, event: unknown) {
    const sockets = userSockets.get(userId)
    if (!sockets?.size) return

    const msg = JSON.stringify(event)
    for (const socket of sockets) {
        if (socket.readyState !== WS_OPEN) continue
        try {
            socket.send(msg)
        } catch {
            // stale
        }
    }
}

export function emitToAuxUsers(userIds: Iterable<string>, event: unknown, exceptUserId?: string) {
    const msg = JSON.stringify(event)
    for (const userId of userIds) {
        if (exceptUserId && userId === exceptUserId) continue
        const sockets = userSockets.get(userId)
        if (!sockets?.size) continue

        for (const socket of sockets) {
            if (socket.readyState !== WS_OPEN) continue
            try {
                socket.send(msg)
            } catch {
                // stale
            }
        }
    }
}

export function emitToAuxRoom(roomId: string, event: unknown, exceptUserId?: string) {
    const users = roomUsers.get(roomId)
    if (!users?.size) return
    emitToAuxUsers(users, event, exceptUserId)
}

export function getAuxRoomUserIds(roomId: string): string[] {
    return [...(roomUsers.get(roomId) ?? [])]
}
