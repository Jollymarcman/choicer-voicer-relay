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
  host.send(JSON.stringify({ type: "create", protocol: 3 }));
  const created = JSON.parse((await nextMessage(host)).data.toString());
  assert.match(created.room, /^[A-Z2-9]{8}$/);

  const friend = new WebSocket(url);
  await once(friend, "open");
  const hostJoinNotice = nextMessage(host);
  friend.send(JSON.stringify({ type: "join", protocol: 3, room: created.room, name: "Friend" }));
  const joined = JSON.parse((await nextMessage(friend)).data.toString());
  const notice = JSON.parse((await hostJoinNotice).data.toString());
  assert.equal(joined.peerId, 2);
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
