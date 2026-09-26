"use strict";

const crypto = require("node:crypto");
const http = require("node:http");
const { WebSocket, WebSocketServer } = require("ws");

const SUPPORTED_PROTOCOLS = new Set([3, 4, 5, 6, 7]);
const MAX_PLAYERS = 4;
const MAX_PAYLOAD_BYTES = 64 * 1024 * 1024;
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const DEFAULT_RECONNECT_GRACE_MS = 120_000;

function randomRoomCode(rooms) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    let code = "";
    for (let index = 0; index < 8; index += 1) {
      code += ROOM_ALPHABET[crypto.randomInt(ROOM_ALPHABET.length)];
    }
    if (!rooms.has(code)) return code;
  }
  throw new Error("Could not allocate a room code");
}

function sendJson(socket, value) {
  if (socket?.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(value));
  }
}

function closeSocket(socket, code, reason) {
  if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
    socket.close(code, reason);
  }
}

function newResumeToken() {
  return crypto.randomBytes(24).toString("hex");
}

function createRelayServer(options = {}) {
  const rooms = new Map();
  const port = Number(options.port ?? process.env.PORT ?? 10000);
  const host = options.host ?? "0.0.0.0";
  const reconnectGraceMs = Number(options.reconnectGraceMs ?? DEFAULT_RECONNECT_GRACE_MS);

  function connectedSocket(room, peerId) {
    const socket = room?.peers.get(peerId)?.socket;
    return socket?.readyState === WebSocket.OPEN ? socket : null;
  }

  function clearReconnectTimer(peer) {
    if (peer?.reconnectTimer) clearTimeout(peer.reconnectTimer);
    if (peer) peer.reconnectTimer = null;
  }

  function finishDisconnect(roomCode, peerId) {
    const room = rooms.get(roomCode);
    const peer = room?.peers.get(peerId);
    if (!room || !peer || peer.socket) return;
    clearReconnectTimer(peer);
    if (peerId === 1) {
      rooms.delete(roomCode);
      for (const [otherPeerId, otherPeer] of room.peers) {
        clearReconnectTimer(otherPeer);
        if (otherPeerId !== 1 && otherPeer.socket) closeSocket(otherPeer.socket, 4001, "Host disconnected");
      }
      return;
    }
    room.peers.delete(peerId);
    sendJson(connectedSocket(room, 1), { type: "peer_left", peerId });
  }

  function scheduleDisconnect(roomCode, peerId) {
    const room = rooms.get(roomCode);
    const peer = room?.peers.get(peerId);
    if (!peer || peer.reconnectTimer) return;
    peer.reconnectTimer = setTimeout(() => finishDisconnect(roomCode, peerId), reconnectGraceMs);
    peer.reconnectTimer.unref?.();
  }

  const server = http.createServer((request, response) => {
    if (request.url === "/health" || request.url === "/") {
      response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      response.end(JSON.stringify({ ok: true, service: "choicer-voicer-relay", protocols: [...SUPPORTED_PROTOCOLS], rooms: rooms.size }));
      return;
    }
    response.writeHead(404, { "content-type": "application/json" });
    response.end(JSON.stringify({ ok: false, error: "Not found" }));
  });

  const webSockets = new WebSocketServer({ server, maxPayload: MAX_PAYLOAD_BYTES });

  webSockets.on("connection", (socket) => {
    socket.isAlive = true;
    socket.roomCode = "";
    socket.peerId = 0;
    socket.isHost = false;

    socket.on("pong", () => {
      socket.isAlive = true;
    });

    socket.on("message", (data, isBinary) => {
      if (!socket.roomCode) {
        if (isBinary) {
          closeSocket(socket, 4000, "Register before sending data");
          return;
        }
        let message;
        try {
          message = JSON.parse(data.toString("utf8"));
        } catch {
          closeSocket(socket, 4000, "Invalid registration message");
          return;
        }
        const protocol = Number(message.protocol);
        if (!SUPPORTED_PROTOCOLS.has(protocol)) {
          closeSocket(socket, 4002, "Game version mismatch");
          return;
        }
        if (message.type === "create") {
          const roomCode = randomRoomCode(rooms);
          const resumeToken = newResumeToken();
          const room = {
            peers: new Map([[1, {
              socket,
              name: String(message.name ?? "Host").slice(0, 24),
              resumeToken,
              reconnectTimer: null,
            }]]),
            nextPeerId: 2,
            protocol,
          };
          rooms.set(roomCode, room);
          socket.roomCode = roomCode;
          socket.peerId = 1;
          socket.isHost = true;
          socket.resumeToken = resumeToken;
          sendJson(socket, { type: "created", room: roomCode, peerId: 1, resumeToken });
          return;
        }
        if (message.type === "join") {
          const roomCode = String(message.room ?? "").trim().toUpperCase();
          const room = rooms.get(roomCode);
          if (!room) {
            closeSocket(socket, 4004, "Room not found");
            return;
          }
          if (room.protocol !== protocol) {
            closeSocket(socket, 4002, "Game version mismatch");
            return;
          }
          if (room.peers.size >= MAX_PLAYERS) {
            closeSocket(socket, 4003, "Room is full");
            return;
          }
          if (!connectedSocket(room, 1)) {
            closeSocket(socket, 4005, "Host is reconnecting");
            return;
          }
          const peerId = room.nextPeerId++;
          const name = String(message.name ?? "Player").slice(0, 24);
          const resumeToken = newResumeToken();
          room.peers.set(peerId, { socket, name, resumeToken, reconnectTimer: null });
          socket.roomCode = roomCode;
          socket.peerId = peerId;
          socket.resumeToken = resumeToken;
          sendJson(socket, { type: "joined", room: roomCode, peerId, resumeToken });
          sendJson(connectedSocket(room, 1), {
            type: "peer_joined",
            peerId,
            name,
          });
          return;
        }
        if (message.type === "resume") {
          const roomCode = String(message.room ?? "").trim().toUpperCase();
          const peerId = Number(message.peerId);
          const room = rooms.get(roomCode);
          const peer = room?.peers.get(peerId);
          if (!room || !peer || room.protocol !== protocol || peer.resumeToken !== String(message.resumeToken ?? "")) {
            closeSocket(socket, 4006, "Session resume expired");
            return;
          }
          if (peer.socket && peer.socket !== socket) {
            peer.socket.skipDisconnectCleanup = true;
            peer.socket.terminate();
          }
          clearReconnectTimer(peer);
          peer.socket = socket;
          socket.roomCode = roomCode;
          socket.peerId = peerId;
          socket.isHost = peerId === 1;
          socket.resumeToken = peer.resumeToken;
          const response = { type: "resumed", room: roomCode, peerId, resumeToken: peer.resumeToken };
          if (peerId === 1) {
            response.players = [...room.peers.entries()]
              .filter(([, entry]) => entry.socket?.readyState === WebSocket.OPEN)
              .map(([id, entry]) => ({ peerId: id, name: entry.name }));
          }
          sendJson(socket, response);
          if (peerId !== 1) {
            sendJson(connectedSocket(room, 1), { type: "peer_resumed", peerId, name: peer.name });
          }
          return;
        }
        closeSocket(socket, 4000, "Expected create or join");
        return;
      }

      if (!isBinary) {
        let message;
        try {
          message = JSON.parse(data.toString("utf8"));
        } catch {
          return;
        }
        if (message.type === "keepalive") sendJson(socket, { type: "keepalive" });
        return;
      }

      const room = rooms.get(socket.roomCode);
      const packet = Buffer.from(data);
      if (!room || packet.length < 4) return;
      const targetPeerId = packet.readUInt32BE(0);
      const payload = packet.subarray(4);
      if (!socket.isHost && targetPeerId !== 1) return;

      const forwarded = Buffer.allocUnsafe(payload.length + 4);
      forwarded.writeUInt32BE(socket.peerId, 0);
      payload.copy(forwarded, 4);

      if (targetPeerId === 0 && socket.isHost) {
        for (const [peerId, peer] of room.peers) {
          if (peerId !== socket.peerId && peer.socket?.readyState === WebSocket.OPEN) peer.socket.send(forwarded);
        }
        return;
      }
      const target = connectedSocket(room, targetPeerId);
      if (target) target.send(forwarded);
    });

    socket.on("close", (code) => {
      if (!socket.roomCode || socket.skipDisconnectCleanup) return;
      const room = rooms.get(socket.roomCode);
      if (!room) return;
      const peer = room.peers.get(socket.peerId);
      if (!peer || peer.socket !== socket) return;
      peer.socket = null;
      if (code === 1000) finishDisconnect(socket.roomCode, socket.peerId);
      else scheduleDisconnect(socket.roomCode, socket.peerId);
    });
  });

  const heartbeat = setInterval(() => {
    for (const socket of webSockets.clients) {
      if (!socket.isAlive) {
        socket.terminate();
        continue;
      }
      socket.isAlive = false;
      socket.ping();
    }
  }, 30_000);
  heartbeat.unref();

  webSockets.on("close", () => clearInterval(heartbeat));

  return {
    rooms,
    server,
    webSockets,
    listen() {
      return new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(port, host, () => {
          server.off("error", reject);
          resolve(server.address());
        });
      });
    },
    close() {
      for (const room of rooms.values()) {
        for (const peer of room.peers.values()) clearReconnectTimer(peer);
      }
      for (const socket of webSockets.clients) {
        socket.skipDisconnectCleanup = true;
        socket.terminate();
      }
      return new Promise((resolve) => webSockets.close(() => server.close(resolve)));
    },
  };
}

if (require.main === module) {
  const relay = createRelayServer();
  relay.listen().then((address) => {
    console.log(`Choicer Voicer relay listening on ${address.address}:${address.port}`);
  });
}

module.exports = { createRelayServer };
