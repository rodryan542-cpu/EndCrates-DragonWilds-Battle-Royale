# EndCrates-DragonWilds-Battle-Royale

20-player free-for-all arenas around the Dragonwilds map. Build a kit in the lobby, type `!ffa`, and wait for a group of 20. Each group gets a free arena. The last player standing wins, returns to the lobby, and can queue again.

**This is a development build.** The game is not installed on the development machine, so the match rules and native bridge have been tested with simulated players, not a running Dragonwilds server. The server owner still needs to record safe arena spawns and test the multiplayer integration.

## What it does

- Runs several matches in different regions of one shared world.
- Starts each match with exactly 20 queued players and distinct recorded spawns.
- Waits for players to finish teleporting before the countdown.
- Tracks knockouts, disconnects, forfeits, and players leaving their arena.
- Announces the victor and returns players to a protected kit lobby.
- Provides a searchable lobby item catalogue through `!items` and `!give`. Equip items through the normal inventory menu.

The lobby uses a catalogue rather than thousands of item actors. Item grants are locked during matches. Knockouts use an immortality lock and a low-health threshold to avoid normal inventory-loss deaths; that native behavior still needs an in-game test.

## Player commands

| Command | Use |
| --- | --- |
| `!brhelp` | Show commands |
| `!items dragon` | Find item names |
| `!give Scimitar_Dragon 1` | Get an item in the kit lobby |
| `!more` | Next page of item results |
| `!ffa` | Join the next group of 20 |
| `!leave` | Leave the queue or forfeit a match |
| `!lobby` | Return to the kit lobby |
| `!brstatus` | Check your state, queue, and matches |

## Server setup

Requires a Windows server/host with **UE4SS already working**. Copy `Mods/EndCratesBR` into its UE4SS `Mods` folder and enable:

```text
EndCratesBR : 1
```

Use a separate arena world with PvP enabled. Follow [SETUP.md](docs/SETUP.md) to configure the server capacity, record the lobby and arena spawn points, and enable BR. It stays in setup mode until these checks pass.

Jagex [documents six-player dedicated-server support](https://runescapedragonwilds.help.jagex.com/hc/en-gb/articles/45365343055249-Dedicated-Servers-How-to-Guide). Higher player counts are experimental. This mod does not install a server loader or establish that 20+ players can connect on your particular setup.

## Performance

The default limit is four concurrent matches. Teleports and chat deliveries have server-wide budgets; roster discovery happens every two seconds. Item data is loaded on demand, and match state is discarded after a round.

A 50-match / 1,000-player simulation is included. It measures the Lua scheduler only. It does **not** measure terrain, AI, physics, replication, or actual server capacity. See [PERFORMANCE.md](docs/PERFORMANCE.md).

World Partition controls which terrain cells are loaded. An optional startup profile is included for testing server streaming. The Lua mod cannot guarantee that Dragonwilds unloads everything outside active arenas.

## Tests and credits

```text
python -m pip install -r requirements-dev.txt
python -m unittest discover -s tests -p "test_*.py" -v
```

See [VERIFICATION.md](docs/VERIFICATION.md) for coverage and the remaining live checks.

MIT licensed. Some UObject access patterns derive from Glooboo's [Dragonwilds Toolkit](https://github.com/MyNameIsGlooboo/Dragonwilds-Toolkit); its notice is in `ThirdParty-LICENSE.txt`. Game assets and saves are not included. Unaffiliated with Jagex.
