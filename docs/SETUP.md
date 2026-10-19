# Server setup

Use a new arena world and separate characters/backups for testing. The kit lobby can grant valuable and quest items; it belongs on a server intended for this mode.

## Loader and capacity

1. Install a Windows Dragonwilds server or listen host whose UE4SS loader actually runs Lua mods. Check `UE4SS.log` for mod startup. The `dwmapi.dll` loader used by a normal game client is not guaranteed to load in a dedicated server. Linux server loading is outside this package.
2. Copy `Mods/EndCratesBR` to `ue4ss/Mods` and add `EndCratesBR : 1` to the existing `mods.txt`. If your loader also uses `mods.json`, enable its matching entry. Keep the license files with redistributed copies.
3. Disable the earlier Maxer/WorldCommands mod on this arena setup. Its chat interception and unrestricted cheats can conflict with BR commands and fairness.
4. Enable PvP in the arena world's normal game settings. Then set `pvp_world_confirmed=true` in `Scripts/config.lua`. This is an operator declaration, not an automatic check of every native damage rule.
5. Configure the server's connection capacity before startup. `server/start-server.ps1` demonstrates the experimental Unreal GameSession override. The default four arenas need room for 80 fighters plus the lobby; the example uses 100 slots. Neither the setting nor a successful readback proves that the online service will admit 100 connections. Verify real joins past the normal limit first.

Jagex's [dedicated-server guide](https://runescapedragonwilds.help.jagex.com/hc/en-gb/articles/45365343055249-Dedicated-Servers-How-to-Guide) documents six-player support. The [Pelican server definition](https://github.com/pelican-eggs/games-steamcmd/blob/main/runescape_dragonwilds/egg-pterodactyl-runescape-dragonwilds.json) shows the GameSession override used in the example. Above-standard counts remain experimental.

## Record the lobby and arenas

The listen host is an admin. On a dedicated server, the native configured Owner ID is recognized; additional trusted owner IDs can be placed in `admin_owner_ids`. Identity comes from the server-owned player state, never the sender fields in a chat packet. `!br whoami` reports your authenticated owner ID to your client.

Walk to the intended safe lobby and enter:

```text
!br lobby 1500
```

Distances are Unreal units (normally centimeters). This records the current character position and a 15-meter lobby radius. The lobby location is pinned to that world's ID.

Walk to the center of the first arena:

```text
!br zone ashlands 12000
```

That records a 120-meter radius. Walk to a safe, standing spawn location and enter:

```text
!br spawn ashlands
```

Repeat at **20 different safe positions** inside that arena. Spawns must be at least 3 meters apart and 5 meters inside its boundary. Test standing and teleporting at every recorded point. The mod does not guess ground height from a map image or generate untested positions around a circle.

Repeat `!br zone` and `!br spawn` for other areas around the world. Arenas must not overlap, must leave the configured gap, and must stay clear of the lobby. Avoid boss instances, quest-only rooms, water, cliffs, locked destinations, and areas whose terrain changes with quest progress.

When the geometry is ready:

```text
!br save
!br diagnose
!br enable
```

`arena_state.lua` stores the recorded geometry beside the scripts; the previous successful version is retained. The game process must be able to write there. Geometry is not bundled with this repository because safe positions have not been checked in a running game.

## Run matches

Players enter the protected lobby, use `!items` and `!give`, and equip through the game's inventory UI. The catalogue includes 1,492 active/non-deprecated item identifiers from CL 251392 and merges currently loaded assets. Game updates can add or remove items; an unavailable item is rejected. It is a virtual armory, not a room containing thousands of chests or pickups.

The global FIFO queue reserves 20 players for a free arena. One arena loads at a time by default. Once all 20 characters have arrived and report that teleporting has ended, the ten-second countdown begins. Other arenas can already be fighting.

Each arena is a fixed circular boundary. Players have ten seconds to return if they leave it. There is no shrinking-circle visual or duplicated map instance in this build. The default round has no time limit. An optional configured time limit produces a draw if several players remain.

At one health or below, a player is eliminated and sent back to the lobby. Disconnects and character replacements forfeit the round. If all remaining players are eliminated in one sample, the result is a draw. Players manually enter `!ffa` again after choosing or adjusting a kit.

## Admin controls

- `!br pause` / `!br resume`: pause/resume new matches.
- `!br cancel <match ID>`: cancel a round and return participants.
- `!br disable`: stop BR and release its native protection locks.
- `!br diagnose`: check authority, capacity, geometry count, and preflight.
- Server console `br_status`: report match, queue, teleport, and message statistics.
- Server console `br_stop`: stop BR if chat is unavailable.

Run `!br disable` or `br_stop` **before hot-reloading or unloading scripts**. Changing/removing Lua files during active matches is unsupported. Restart the server to clear native state if the mod was removed without stopping it first.

## Before opening the server

Complete the live checks in [VERIFICATION.md](VERIFICATION.md). This source package has not established cross-client PvP isolation, death/knockout behavior, RPC struct marshaling, 20-player admission, or terrain streaming on the current game build.
