"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const { once } = require("node:events");
const { WebSocket } = require("ws");
const { createRelayServer } = require("./server");

function nextMessage(socket) {
  return once(socket, "message").then(([data, isBinary]) => ({ data, isBinary }));
}

test("creates a room, joins a friend, and relays binary packets", async (context) => {
  const relay = createRelayServer({ port: 0, host: "127.0.0.1" });
  const address = await relay.listen();
  context.after(() => relay.close());
  const url = `ws://127.0.0.1:${address.port}`;

  const host = new WebSocket(url);
  await once(host, "open");
  host.send(JSON.stringify({ type: "create", protocol: 7, name: "Host" }));
  const created = JSON.parse((await nextMessage(host)).data.toString());
  assert.match(created.room, /^[A-Z2-9]{8}$/);
  assert.match(created.resumeToken, /^[a-f0-9]{48}$/);

  const friend = new WebSocket(url);
  await once(friend, "open");
  const hostJoinNotice = nextMessage(host);
  friend.send(JSON.stringify({ type: "join", protocol: 7, room: created.room, name: "Friend" }));
  const joined = JSON.parse((await nextMessage(friend)).data.toString());
  const notice = JSON.parse((await hostJoinNotice).data.toString());
  assert.equal(joined.peerId, 2);
  assert.match(joined.resumeToken, /^[a-f0-9]{48}$/);
  assert.deepEqual(notice, { type: "peer_joined", peerId: 2, name: "Friend" });

  const toFriend = Buffer.alloc(7);
  toFriend.writeUInt32BE(2, 0);
  Buffer.from([10, 20, 30]).copy(toFriend, 4);
  const friendPacket = nextMessage(friend);
  host.send(toFriend);
  const receivedByFriend = await friendPacket;
  assert.equal(receivedByFriend.isBinary, true);
  assert.equal(receivedByFriend.data.readUInt32BE(0), 1);
  assert.deepEqual([...receivedByFriend.data.subarray(4)], [10, 20, 30]);

  const toHost = Buffer.alloc(6);
  toHost.writeUInt32BE(1, 0);
  Buffer.from([40, 50]).copy(toHost, 4);
  const hostPacket = nextMessage(host);
  friend.send(toHost);
  const receivedByHost = await hostPacket;
  assert.equal(receivedByHost.data.readUInt32BE(0), 2);
  assert.deepEqual([...receivedByHost.data.subarray(4)], [40, 50]);

  host.close();
  friend.close();
});

test("resumes the same host room and friend slot after interrupted sockets", async (context) => {
  const relay = createRelayServer({ port: 0, host: "127.0.0.1", reconnectGraceMs: 2_000 });
  const address = await relay.listen();
  context.after(() => relay.close());
  const url = `ws://127.0.0.1:${address.port}`;

  const host = new WebSocket(url);
  await once(host, "open");
  host.send(JSON.stringify({ type: "create", protocol: 7, name: "Host" }));
  const created = JSON.parse((await nextMessage(host)).data.toString());

  const friend = new WebSocket(url);
  await once(friend, "open");
  const joinedAtHost = nextMessage(host);
  friend.send(JSON.stringify({ type: "join", protocol: 7, room: created.room, name: "Friend" }));
  const joined = JSON.parse((await nextMessage(friend)).data.toString());
  await joinedAtHost;

  const hostClosed = once(host, "close");
  host.terminate();
  await hostClosed;
  assert.equal(relay.rooms.has(created.room), true);

  const resumedHost = new WebSocket(url);
  await once(resumedHost, "open");
  resumedHost.send(JSON.stringify({
    type: "resume",
    protocol: 7,
    room: created.room,
    peerId: 1,
    resumeToken: created.resumeToken,
  }));
  const hostResume = JSON.parse((await nextMessage(resumedHost)).data.toString());
  assert.equal(hostResume.type, "resumed");
  assert.deepEqual(hostResume.players, [
    { peerId: 1, name: "Host" },
    { peerId: 2, name: "Friend" },
  ]);

  const friendClosed = once(friend, "close");
  friend.terminate();
  await friendClosed;

  const resumedFriend = new WebSocket(url);
  await once(resumedFriend, "open");
  const friendNotice = nextMessage(resumedHost);
  resumedFriend.send(JSON.stringify({
    type: "resume",
    protocol: 7,
    room: created.room,
    peerId: joined.peerId,
    resumeToken: joined.resumeToken,
  }));
  const friendResume = JSON.parse((await nextMessage(resumedFriend)).data.toString());
  assert.equal(friendResume.type, "resumed");
  assert.equal(friendResume.peerId, 2);
  assert.deepEqual(JSON.parse((await friendNotice).data.toString()), {
    type: "peer_resumed",
    peerId: 2,
    name: "Friend",
  });

  const packet = Buffer.alloc(5);
  packet.writeUInt32BE(2, 0);
  packet[4] = 99;
  const delivered = nextMessage(resumedFriend);
  resumedHost.send(packet);
  const received = await delivered;
  assert.equal(received.data.readUInt32BE(0), 1);
  assert.equal(received.data[4], 99);

  resumedHost.close(1000);
  resumedFriend.close(1000);
});

test("keeps protocol 3 rooms working and rejects a different-version client", async (context) => {
  const relay = createRelayServer({ port: 0, host: "127.0.0.1" });
  const address = await relay.listen();
  context.after(() => relay.close());
  const url = `ws://127.0.0.1:${address.port}`;

  const host = new WebSocket(url);
  await once(host, "open");
  host.send(JSON.stringify({ type: "create", protocol: 3 }));
  const created = JSON.parse((await nextMessage(host)).data.toString());

  const oldFriend = new WebSocket(url);
  await once(oldFriend, "open");
  const hostJoinNotice = nextMessage(host);
  oldFriend.send(JSON.stringify({ type: "join", protocol: 3, room: created.room, name: "Old Friend" }));
  const joined = JSON.parse((await nextMessage(oldFriend)).data.toString());
  await hostJoinNotice;
  assert.equal(joined.peerId, 2);

  const newFriend = new WebSocket(url);
  await once(newFriend, "open");
  const closed = once(newFriend, "close");
  newFriend.send(JSON.stringify({ type: "join", protocol: 4, room: created.room, name: "New Friend" }));
  const [code] = await closed;
  assert.equal(code, 4002);

  host.close();
  oldFriend.close();
});
