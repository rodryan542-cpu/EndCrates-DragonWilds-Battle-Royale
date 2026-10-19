# EndCrates-DragonWilds-Battle-Royale

20-player free-for-all arenas around the Dragonwilds map. Build a kit in the lobby and type `!ffa`. Each group gets a free arena, the circle shrinks, and the last player standing wins. Several rounds can run at once in different regions of the same world.

**This is a development build.** The game is not installed on the development machine, so the match rules and native bridge have been tested with simulated players, not a running Dragonwilds server. The server owner still needs to record safe arena spawns and test the multiplayer integration.

## What it does

- Runs several matches in different regions of one shared world.
- Starts each match with exactly 20 queued players and distinct recorded spawns.
- Waits for players to finish teleporting before the countdown.
- Tracks knockouts, disconnects, forfeits, and players leaving their arena.
- Shrinks each arena's safe circle in three timed stages, ending at 6% of its original radius after eight minutes.
- Announces the victor and returns players to a protected kit lobby.
- Provides a searchable lobby item catalogue through `!items` and `!give`. Equip items through the normal inventory menu.
- Keeps a personal kit list and tops up missing items without repeatedly handing out copies you already have.
- Shows queue positions, running matches, round placements, session stats, and a leaderboard.
- Supports optional automatic requeue. Leaving or returning manually turns it off.

The lobby uses a catalogue rather than thousands of item actors. Item grants are locked during matches. Knockouts use an immortality lock and a low-health threshold to avoid normal inventory-loss deaths; that native behavior still needs an in-game test.

Circle information is delivered through chat and `!ring`; this build has no rendered storm wall or map overlay. Session kit lists and stats survive a brief reconnect but reset on a server/world restart or after ten minutes disconnected.

## Player commands

| Command | Use |
| --- | --- |
| `!brhelp` | Show commands |
| `!items dragon` | Find item names |
| `!give Scimitar_Dragon 1` | Get an item in the kit lobby |
| `!more` | Next page of item results |
| `!ffa` | Join the next group of 20 |
| `!queue` | Your position and the number waiting |
| `!autoqueue on` / `!autoqueue off` | Rejoin after returning to the lobby |
| `!leave` | Leave the queue or forfeit a match |
| `!lobby` | Return to the kit lobby |
| `!brstatus` | Check your state, queue, and matches |
| `!matches [page]` | Browse running rounds |
| `!ring` | Safe circle center, radius, phase, and your distance from its center |
| `!kit add <item> [count]` | Save or update a kit entry; up to 12 different items |
| `!kit show` / `!kit remove <item>` / `!kit clear` | Review or edit your kit list |
| `!kit load` | Top up missing kit items in the lobby |
| `!stats` / `!top` | Personal session stats / top ten players |
| `!results [1\|2]` | Placements from your most recently completed round |

For example: `!kit add Scimitar_Dragon 1`, then `!kit load`. Loading grants one item type per server update, counts existing inventory, and stops if you leave the lobby. Wait for it to finish before typing `!ffa`. A kit list does not clear your inventory or change equipped items. See [the player guide](docs/PLAYING.md) for circle timing and results rules.

## Server setup

Requires a Windows server/host with **UE4SS already working**. Copy `Mods/EndCratesBR` into its UE4SS `Mods` folder and enable:

```text
EndCratesBR : 1
```

Use a separate arena world with PvP enabled. Follow [SETUP.md](docs/SETUP.md) to configure the server capacity, record the lobby and arena spawn points, and enable BR. It stays in setup mode until these checks pass.

Jagex [documents six-player dedicated-server support](https://runescapedragonwilds.help.jagex.com/hc/en-gb/articles/45365343055249-Dedicated-Servers-How-to-Guide). Higher player counts are experimental. This mod does not install a server loader or establish that 20+ players can connect on your particular setup.

## Performance

The default limit is four concurrent matches. Teleports, kit grants, and chat deliveries have server-wide budgets; roster discovery happens every two seconds. Critical notices bypass item-search replies. Old countdowns expire, repeated notices replace each other, and simultaneous eliminations share one broadcast. Server-wide result history holds 20 rounds; each retained player also keeps their latest result.

A 50-match / 1,000-player simulation is included. It measures the Lua scheduler only. It does **not** measure terrain, AI, physics, replication, or actual server capacity. See [PERFORMANCE.md](docs/PERFORMANCE.md).

World Partition controls which terrain cells are loaded. An optional startup profile is included for testing server streaming. The Lua mod cannot guarantee that Dragonwilds unloads everything outside active arenas.

## Tests and credits

```text
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py" -v
```

See [VERIFICATION.md](docs/VERIFICATION.md) for coverage and the remaining live checks.

MIT licensed. Some UObject access patterns derive from Glooboo's [Dragonwilds Toolkit](https://github.com/MyNameIsGlooboo/Dragonwilds-Toolkit); its notice is in `ThirdParty-LICENSE.txt`. Game assets and saves are not included. Unaffiliated with Jagex.
