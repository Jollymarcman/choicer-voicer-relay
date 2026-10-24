# Choicer Voicer Relay

Small room-based WebSocket relay for private 2–8 player Choicer Voicer games.

## Browser guest

Friends can join a desktop host's multiplayer Video Dub without installing the
game at <https://jollymarcman.github.io/choicer-voicer-relay/>. The browser
client contains only the guest dubbing flow: room-code joining, confirmed pack
download, character selection, line recording, progress, and synchronized
playback. Hosting and single-player modes remain in the Windows game.

Browser guests can change the compatible secure WebSocket (`wss://`) relay on
the join screen. The choice is saved in that browser's local game storage.
Paste an `https://` address or a bare hostname and the guest converts it to
`wss://`; insecure `ws://` is blocked by browsers on this HTTPS site. The
desktop host and all guests must use the same relay address; the relay does not
need to be this repository's Render deployment.

The deployable build is in `docs/`; its Godot 4.4.1 source is in
`web-client-source/`. Packs are transferred from the active desktop host and
stored in that browser. Packs larger than 512 MiB are intentionally rejected.

## Render

Deploy the repository as a free Render Blueprint using `render.yaml`. The health
endpoint is `/health`; no environment variables or persistent storage are needed.

Rooms exist only while their host is connected. An eight-character room code is
generated for each session. The relay accepts at most eight players per room and
binary messages up to 64 MiB.

## Local verification

```sh
npm install
npm test
npm start
```
