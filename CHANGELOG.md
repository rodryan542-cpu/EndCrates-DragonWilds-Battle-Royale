# Changes

## 0.2.0-alpha

- Added a three-stage shrinking circle for each active arena, with chat warnings and `!ring`.
- Added session placements, personal results, stats, and a top-ten leaderboard. Simultaneous knockouts tie; cancelled rounds do not count.
- Added session kit lists with inventory-aware top-ups, a shared grant budget, and lobby checks between every item.
- Added queue positions, a match browser, and optional automatic requeue after confirmed lobby arrival.
- Added arena listing and removal of incorrect arenas or spawn points while disabled.
- Replaced the shifting chat backlog with bounded priority FIFOs, expiring/coalesced notices, and stale-warning cleanup.
- Batched elimination broadcasts and fixed pre-start withdrawals being requeued.

Still requires live Dragonwilds integration testing. Player capacity above the game's documented limit, native PvP/death behavior, server loading, and World Partition streaming have not been established by offline tests. This release adds no rendered circle wall or map overlay.
