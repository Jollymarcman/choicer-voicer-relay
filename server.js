"use strict";

const crypto = require("node:crypto");
const http = require("node:http");
const { WebSocket, WebSocketServer } = require("ws");

const PROTOCOL_VERSION = 1;
const MAX_PLAYERS = 4;
const MAX_PAYLOAD_BYTES = 20 * 1024 * 1024;
const ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

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
  if (socket.readyState === WebSocket.OPEN) {
    socket.send(JSON.stringify(value));
  }
}

function closeSocket(socket, code, reason) {
  if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
    socket.close(code, reason);
  }
}

function createRelayServer(options = {}) {
  const rooms = new Map();
  const port = Number(options.port ?? process.env.PORT ?? 10000);
  const host = options.host ?? "0.0.0.0";

  const server = http.createServer((request, response) => {
    if (request.url === "/health" || request.url === "/") {
      response.writeHead(200, { "content-type": "application/json", "cache-control": "no-store" });
      response.end(JSON.stringify({ ok: true, service: "choicer-voicer-relay", rooms: rooms.size }));
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
        if (Number(message.protocol) !== PROTOCOL_VERSION) {
          closeSocket(socket, 4002, "Game version mismatch");
          return;
        }
        if (message.type === "create") {
          const roomCode = randomRoomCode(rooms);
          const room = { host: socket, peers: new Map([[1, socket]]), nextPeerId: 2 };
          rooms.set(roomCode, room);
          socket.roomCode = roomCode;
          socket.peerId = 1;
          socket.isHost = true;
          sendJson(socket, { type: "created", room: roomCode, peerId: 1 });
          return;
        }
        if (message.type === "join") {
          const roomCode = String(message.room ?? "").trim().toUpperCase();
          const room = rooms.get(roomCode);
          if (!room || room.host.readyState !== WebSocket.OPEN) {
            closeSocket(socket, 4004, "Room not found");
            return;
          }
          if (room.peers.size >= MAX_PLAYERS) {
            closeSocket(socket, 4003, "Room is full");
            return;
          }
          const peerId = room.nextPeerId++;
          room.peers.set(peerId, socket);
          socket.roomCode = roomCode;
          socket.peerId = peerId;
          sendJson(socket, { type: "joined", room: roomCode, peerId });
          sendJson(room.host, {
            type: "peer_joined",
            peerId,
            name: String(message.name ?? "Player").slice(0, 24),
          });
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
          if (peerId !== socket.peerId && peer.readyState === WebSocket.OPEN) peer.send(forwarded);
        }
        return;
      }
      const target = room.peers.get(targetPeerId);
      if (target?.readyState === WebSocket.OPEN) target.send(forwarded);
    });

    socket.on("close", () => {
      if (!socket.roomCode) return;
      const room = rooms.get(socket.roomCode);
      if (!room) return;
      room.peers.delete(socket.peerId);
      if (socket.isHost) {
        rooms.delete(socket.roomCode);
        for (const peer of room.peers.values()) closeSocket(peer, 4001, "Host disconnected");
      } else {
        sendJson(room.host, { type: "peer_left", peerId: socket.peerId });
      }
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
      for (const socket of webSockets.clients) socket.terminate();
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
