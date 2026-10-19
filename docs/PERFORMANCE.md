# Performance and world loading

Every arena uses coordinates in the existing world. The mod does not open a new level or clone the world for a match. An unused arena is a small configuration table with recorded positions; it adds no streaming source or item actors.

## Work limits

| Work | Default |
| --- | --- |
| Concurrent matches | 4 |
| Players per match | 20 |
| Arenas loading at once | 1 |
| Native teleports per 250-ms update | 4, shared by matches and lobby returns |
| Active combat samples | Once per second per participant |
| Controller discovery | Once every 2 seconds |
| Chat inputs handled per update | 16 |
| Pending chat inputs | 256 maximum |
| Player command rate | 3 per 2 seconds |
| Chat deliveries per update | 8 |
| Buffered chat replies | 4,096 maximum; old low-priority replies discarded first |
| Catalogue query cache | 64 searches |
| Catalogue UObject cache | 128 references |

Match lookup and damage permission checks use direct player/match indexes. Active sampling is linear in the number of participants, rather than scanning every player against every other player. Geometry is validated when configuration changes, not on every active tick. Completed match tables are removed; idle disconnected peers expire.

The item catalogue contains identifiers and paths. A grant loads only the requested item asset. This avoids spawning or preloading a copy of every item in the lobby. Loading an item can still cause the game to load its normal dependencies.

## Offline simulation

```text
python tools/benchmark_scheduler.py --output docs/scheduler-benchmark.json
```

The test suite also creates 50 concurrent matches with 1,000 simulated players and checks that 100 combat samples produce exactly 100,000 player samples. [scheduler-benchmark.json](scheduler-benchmark.json) records a local timing run.

These are mock objects. There is no terrain, AI, physics, networking, asset loading, game thread contention, or client rendering in that measurement. It cannot predict RAM requirements, frame rate, or the number of real players Dragonwilds can support. Raising `max_active_matches` to 50 would require at least 1,000 fighter connections plus lobby capacity; this has not been validated.

## World Partition

[Epic's World Partition documentation](https://dev.epicgames.com/documentation/en-us/unreal-engine/world-partition-in-unreal-engine?application_version=5.6) explains that cells load around streaming sources, including player controllers. The server must retain cells needed by all connected players. The mod uses Dragonwilds' native delayed teleport and waits for its teleport state to finish rather than directly moving a pawn into unloaded terrain.

`server/Engine.streaming.experimental.ini` contains optional startup settings for server streaming and streaming-out. These apply only where the game's cooked World Partition settings permit them. They cannot unload always-loaded actors or override every game-specific streaming rule. See Epic's [server-streaming mode](https://dev.epicgames.com/documentation/en-us/unreal-engine/python-api/class/WorldPartitionServerStreamingMode?application_version=5.3) and [server streaming discussion](https://forums.unrealengine.com/t/server-closing-client-connection-with-missinglevelpackage-in-pie/2682793/2).

Do not assume that the packaged game will load only the arena circles. Test client arrivals, collision, buildings, outgoing cell unloads, and memory use with streaming enabled before using that profile. The profile is separate from the mod and is not applied automatically.

Start with a small live test, then increase concurrent matches while recording server frame time, memory, bandwidth, teleport duration, and disconnect rates. Keep the active-match limit below the point where any of those becomes unstable. This repository does not claim to optimize the native engine into a 1,000-player server.
