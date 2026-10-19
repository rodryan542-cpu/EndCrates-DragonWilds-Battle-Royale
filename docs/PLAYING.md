# Playing a round

In the lobby, search with `!items`, grant items with `!give`, and equip them through the normal inventory menu. Type `!ffa` when ready. `!queue` shows your place. When a group of 20 and a free arena are available, the server reserves the round and sends everyone to different recorded spawn points.

The countdown starts after every character finishes arriving. You are protected during setup. If a player leaves before combat begins, the round is cancelled and the others return to the lobby and requeue. The person who left is not requeued.

After FIGHT, only surviving players in your own match are eligible for BR PvP. A knockout, disconnect, character replacement, forfeit, or failure to return inside the safe circle eliminates you. You return to the lobby and can build another kit while the remaining players finish.

## The circle

Every round uses its own clock and recorded arena center. Default timing:

| Elapsed time | Safe circle |
| --- | --- |
| 0:00–2:00 | Full radius |
| 2:00–4:00 | Shrinks to 60% |
| 4:00–5:00 | Holds at 60% |
| 5:00–6:30 | Shrinks to 25% |
| 6:30–7:00 | Holds at 25% |
| 7:00–8:00 | Shrinks to 6% |
| After 8:00 | Holds at 6% until the fight ends |

Use `!ring` for center coordinates, current radius, phase, and your distance from center. Distances are Unreal units. There is no visible storm wall in this build. Outside the circle, you have ten seconds to return; entering the current circle resets that timer. The server can configure different stages or a fixed boundary.

## Kit lists

```text
!kit add Scimitar_Dragon 1
!kit show
!kit load
```

Add up to 12 different items. Adding the same item again changes its target count. `!kit remove <item>` removes an entry; `!kit clear` clears the list. Neither removes anything from your actual inventory.

Loading tops up missing counts one item type at a time. Stay in the lobby until the completion message, equip your gear, then queue. You cannot start a load while queued or queue during a load. Inventory capacity still applies, and equipped items are counted according to the game's inventory API. This feature does not guarantee a spare copy of equipped gear or repair durability.

Your list lasts for the current world session, including brief reconnects. It resets after a server/world restart or ten minutes disconnected. Nothing is automatically equipped or deleted.

## Results and the next match

`!matches` lists running rounds. `!results` and `!results 2` show all 20 placements from your latest completed round. Knockouts in the same server sample share a placement. If everyone remaining falls in that sample, the round is a draw; the server does not choose an arbitrary winner. Cancelled rounds do not count toward stats.

`!stats` shows your rounds, wins, top-three finishes, best place, and last place. `!top` ranks the top ten retained session players by wins, then top-three finishes. A shared top-three placement counts as a top-three finish; a draw never awards a win. These stats reset with the session or peer expiry.

Type `!ffa` again when ready, or enable `!autoqueue on` to queue after confirmed lobby arrival. `!autoqueue off` disables it. `!leave` withdraws or forfeits and disables automatic requeue; `!lobby` does the same and returns you to the lobby. No command lets you rejoin a round you left.
