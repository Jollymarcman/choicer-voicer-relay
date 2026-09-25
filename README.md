# Choicer Voicer Relay

Small room-based WebSocket relay for private 2–4 player Choicer Voicer games.

## Render

Deploy the repository as a free Render Blueprint using `render.yaml`. The health
endpoint is `/health`; no environment variables or persistent storage are needed.

Rooms exist only while their host is connected. An eight-character room code is
generated for each session. The relay accepts at most four players per room and
binary messages up to 20 MiB.

## Local verification

```sh
npm install
npm test
npm start
```
