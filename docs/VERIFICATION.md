# Verification

## What has been checked

The Lua 5.4 suite covers the match engine, command permissions, rate limits, catalogue behavior, persistence, native adapter call shapes, and entry-point hooks with mock Unreal objects. It includes a 50-match / 1,000-player scheduler simulation.

Important cases include groups of 19 versus 20; multiple simultaneous arenas; FIFO spillover; unique spawn assignments; global teleport budgets; refused or delayed teleports; countdown protection; same-match damage permissions; simultaneous full wipes; one-time victory; disconnect/reconnect forfeits; character replacement; boundary grace; return failures; disabled-mode behavior; spoofed chat sender data; item grants during combat; and missing native APIs.

All shipped Lua files are syntax-checked. The built-in default configuration starts disabled and contains no fabricated spawn positions. No live player save is used by the tests.

## API evidence

The bridge targets API metadata inspected from Dragonwilds CL 251392 / Unreal 5.6.1:

| Native path | Recorded signature |
| --- | --- |
| `PlayerChatComponent:Server_SendChatMessage` | `ChatMessageData`, `ChatPlayerFilterData` |
| `PlayerChatComponent:Client_ReceiveChatMessage` | `ChatMessageData` |
| `DamageComponent:CanBeDamagedBy` | `Instigator → bool` |
| `DamageComponent:SetIsInvulnerable` | `bool, LockerObj → bool` |
| `HealthComponent:SetIsImmortal` | `bool, LockerObj → bool` |
| `HealthComponent:SetHealth` | `float, Context` |
| `HealthComponent:OnDeathEvent` | No arguments |
| `DominionPlayerCharacter:BP_TriggerDelayedTeleport` | `PlayerTeleportParams → bool` |
| `DominionPlayerCharacter:IsTeleporting` | `→ bool` |
| `DominionPlayerController:IsPlayerReady` | `→ bool` |
| `InventoryComponent:AddItemByData` | `ItemData, Count, DurabilityPercentage, GameplayTags → bool` |

Metadata establishes names and signatures, not execution order or behavior. A Lua mock cannot validate Unreal's struct marshaling, replication, lock semantics, every damage route, or a changed game build.

The bridge checks that required UFunctions exist and disables match processing after a runtime failure. Preflight also requires server authority, sufficient readable GameSession capacity, an operator-confirmed PvP world, and matching recorded world ID. These checks reduce avoidable errors; they are not a substitute for gameplay testing.

## Required live acceptance checks

1. Confirm the server actually loads UE4SS and the mod. Check the current game build and native signatures.
2. Confirm owner/admin identification and ordinary chat, then test replies on two remote clients. Check that SenderData cannot grant admin access.
3. Confirm experimental player-cap changes with 20 actual simultaneous connections. A config value alone is insufficient.
4. Record and individually test every lobby/arena spawn. Test slow destination streaming, loading-screen completion, collision, and failed travel.
5. Verify native immortality allows health to reach the knockout threshold while preventing normal death/inventory loss. Verify BR releases only its intended protection locks.
6. Verify melee, ranged, magic, projectiles, damage-over-time, reflected damage, and environmental damage. Confirm outsiders, lobby players, and other matches cannot interfere. The damage-permission hook may not cover every game-specific damage route.
7. Run a full 20-player round, including simultaneous knockouts, disconnects, reconnects, respawns, and a single victor. Confirm inventory/equipment persist as intended.
8. Run two full matches at once and check that combat, chat, winners, and returns remain separate.
9. Measure native server frame time, memory, bandwidth, and streaming behavior while increasing load. Verify cell unloading with the optional streaming profile rather than inferring it from Lua timing.
10. Test `br_stop`, graceful shutdown, backups, and restart before exposing the server publicly.

The game is not installed on the development machine. None of those live acceptance checks has been completed for this package. It is a source prototype requiring integration testing, not a verified production server.
