# Fortress Frontiers Rulebook

## Overview

Fortress Frontiers is a two-player, host-authoritative, turn-based strategy game on a hex grid. Both players submit orders simultaneously. The host resolves those orders step-by-step and broadcasts authoritative snapshots to clients.

## Core Loop

Each turn has three phases:

1) Upkeep
- Income is granted.
- Healing from the previous turn is applied.
- Orders and action flags reset.
- Neutral respawn timers tick.
- Fog of war updates.

2) Orders
- Each unit can receive exactly one order.
- Orders are hidden from the opponent until execution.
- Units purchased during Orders are visible and interactable only to the purchasing player until the Spawn step.

3) Execution (step-by-step)
- Spawns
- Attacks
- Engineering (sabotage, repair, build)
- Movement
- Neutral attacks

## Orders and Restrictions

Available orders:
- Move
- Ranged attack (ranged units only)
- Melee attack (units with can_melee)
- Heal
- Heal until full (repeats each turn until full)
- Defend
- Always defend (repeats each turn until changed)
- Build (builders only)
- Build Road To (builders only, queued)
- Build Railroad To (builders only, queued)
- Repair (builders only)
- Sabotage (any unit)
- Lookout (scouts only)
- Spawn (purchase during Orders)
- Undo Buy (for units purchased this turn)

Newly purchased units:
- Cannot act on the turn they are purchased.
- May be undone for a full refund during Orders.

Queued and repeating orders:
- Build repeats automatically while a structure is under construction unless the builder lacks gold for a step.
- Build Road To queues move + build steps until complete, a step fails, or a new order is issued.
- Build Railroad To only upgrades intact roads; if a step lands on a non-road tile, the queue ends.
- Build queues may cross enemy-controlled tiles; they only stop when a step fails or is replaced.

## Visibility and Fog of War

- Each unit reveals tiles within sight range.
- Forests and mountains block line of sight.
- A blocking tile is still visible, but tiles beyond it are not.
- Intact traps are hidden from enemies.
- Newly purchased units are hidden from the opponent during Orders.
- Lookout (scout order) increases sight range by 1 and lets scouts see over forests until the next Execution phase.
- Explored (light) fog shows the last known structure and last known dragon on a tile, but not respawn countdowns.
- Dragon color reflects its current reward type and is preserved in last-known fog memory.

## Terrain Rules

Terrain data comes from the tileset custom data:

| Terrain | Move Cost | Blocks Sight | Melee Attack Bonus | Melee Defense Bonus | Ranged Defense Bonus | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Open ground | 1 | No | 0 | 0 | 0 | Default if no terrain data. |
| Forest | 2 | Yes | 0 | +2 | +2 | Blocks line of sight. |
| Mountain | 9999 | Yes | 0 | 0 | 0 | Impassable. |
| River | 2 | No | -2 | -2 | -2 | Passable with combat penalties. |
| Lake | 2 | No | -2 | +3 | -3 | Passable with mixed defenses. |

## Spawning Units

- You can spawn units on your base tile and on any tower tile you control.
- You can also spawn on tiles adjacent to those spawn points.
- Spawn towers only count if they are connected to your road or rail network (bases and towers count as rail endpoints).
- Spawn orders resolve first during Execution.
- Spawn towers have the same combat stats as starting towers but do not provide additional income.

## Movement and Pathing

### Movement Costs
- Base movement cost is determined by terrain.
- Roads and rails modify terrain costs:
  - Road (intact): base_cost * 0.5
  - Rail (building): base_cost * 0.5
  - Rail (intact): base_cost * 0.25
- Scouts treat forest tiles as cost 1 instead of 2.

### Movement Rules
- Mountains are impassable.
- Enemy bases and towers can be entered as a destination, but you cannot path through them.
- Roads and rails can be built across forest and river.
- Road or rail built on a river tile takes +1 turn to complete.
- Friendly units can hop over a stationary friendly builder on a road/rail if the landing tile is free and movement allows it.

### Movement Resolution (Execution)
Movement resolves one step per tick with the following logic:

1) Enemy swaps
- If two enemy units move into each other's tiles on the same tick, they fight immediately.
- Both deal damage. If one dies, the survivor occupies the fallen unit's tile. If both live, they both stop.

2) Uncontested rotations
- Pure cycles of friendly movers with no external entrants rotate atomically.

3) Contested cycle entries
- When a cycle has external entrants, a FIFO melee clash occurs at contested entry tiles before resolving the cycle.

4) Chain resolution from sinks
- For each sink (an empty tile with entrants, or a tile with a stationary occupant), entrants are resolved FIFO:
  - If the tile is empty, the next unfought entrant from each side clashes; survivors may requeue once.
  - If the tile has a stationary defender, enemy entrants fight the defender in FIFO order.
  - If the defender survives, friendly entrants cannot pass that tile this tick.

5) Path trimming
- Any unit that successfully moved one step pops that step from its path.
- If the path finishes, the order is cleared.

6) Traps
- If a unit moves onto an intact enemy trap, it takes 30 damage, stops, and the trap becomes disabled.

## Combat

### Targeting
- Ranged attacks require line of sight and range.
- Melee attacks require adjacency.
- If a unit and a structure share a tile, the structure is the primary attack target.

### Retaliation
- A defending unit retaliates when attacked.
- For ranged attacks, the defender retaliates if they are ranged OR the attacker is adjacent.
- Towers and bases never retaliate directly. If a defending garrison unit is on that tile, the unit retaliates instead.
- Neutral units do not retaliate; they only deal damage during the neutral attack step.

### Damage Formula

Damage is symmetric and exponential:

- Damage = 30 * 1.041^(attack_strength - defense_strength)
- Attack and defense strength scale with current health:
  - at full health: 100 percent strength
  - at 0 health: 50 percent strength
- Neutral units and bases/towers always fight as if at full health.

### Strength Modifiers
- Fortification (intact): +3 melee and +3 ranged (attack and defense).
- Tower garrison bonus: +3 melee, +3 ranged, +1 ranged range.
- Dragon rewards: +3 melee or +3 ranged (stacking per reward).
- Terrain bonuses (see terrain table).
- Multi-attack penalty: defender loses multi_def_penalty per additional attacker (does not apply to neutral units).
- Phalanx defending bonus: +20 and negates multi-attack penalty for the phalanx.
- Adjacent defending phalanx: +2 melee and +2 ranged.

## Units

All units have default stats unless overridden:
- melee_strength: 1
- ranged_strength: 0
- move_range: 2
- ranged_range: 0
- sight_range: 2
- max_health: 100
- regen: 10
- multi_def_penalty: 2
- can_melee: true

### Player Units

| Unit | Cost | Melee | Ranged | Move | Range | Sight | Regen | Notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Archer | 100 | 10 | 25 | 2 | 2 | 2 | 10 | Ranged unit. |
| Soldier | 75 | 20 | 0 | 2 | 0 | 2 | 10 | Melee unit. |
| Scout | 50 | 4 | 0 | 3 | 0 | 3 | 15 | Fast and high vision; lookout; forest move cost 1. |
| Miner | 75 | 1 | 0 | 2 | 0 | 2 | 15 | Provides mine bonus. |
| Builder | 50 | 3 | 0 | 2 | 0 | 2 | 10 | Builds, repairs, sabotages; can queue road/rail builds. |
| Phalanx | 100 | 10 | 0 | 2 | 0 | 2 | 10 | Defend bonus; no multi-attack penalty. |
| Cavalry | 125 | 20 | 0 | 3 | 0 | 3 | 10 | Fast melee unit. |
| Tower | - | 20 | 0 | 0 | 0 | 2 | 0 | Static structure. |
| Base | - | 20 | 0 | 0 | 0 | 2 | 0 | 500 max health; losing it ends the game. |

### Neutral Units

| Unit | Melee | Ranged | Range | Sight | Move | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Camp Archer | 15 | 35 | 2 | 2 | 0 | Ranged attacker. |
| Dragon | 25 | 40 | 3 | 3 | 0 | Ranged fire and melee cleave. |

## Structures and Engineering

Builders construct structures over multiple turns. Costs are paid per build step.

| Structure | Turns | Cost per Step | Rules | Effect |
| --- | --- | --- | --- | --- |
| Fortification | 2 | 15 | Open terrain only | +3 melee, +3 ranged on tile. |
| Road | 2 | 5 | Can cross forest and river | Movement cost x0.5. |
| Railroad | 2 | 10 | Must upgrade an intact road | Movement cost x0.25. |
| Spawn Tower | 4 | 10 | Open terrain only | Adds a new spawn point (no extra gold). |
| Trap | 2 | 15 | Open terrain or forest | Hidden; triggers on entry. |

Roads and rails built on river tiles take +1 additional turn.

### Structure States
- Building: under construction, no benefits.
- Intact: full benefits.
- Disabled: no benefits, can be repaired or destroyed.
- Railroads under construction still count as roads for movement and connectivity.

### Engineering Phase
The Engineering step resolves after Attacks and before Movement:

- Sabotage (any unit, same tile):
  - Intact -> Disabled
  - Disabled -> Destroyed
  - Building -> Canceled
- Repair (builder only, same tile):
  - Disabled structure -> Intact in one step.
  - Base or tower on the same tile -> +30 health (capped).
- Build (builder only, same tile):
  - Deducts gold per step. If insufficient gold, the step does not progress.
- Sabotage can target your own structures (except completed spawn towers).

### Traps
- Intact traps are hidden from enemies.
- When an enemy enters the tile, the trap deals 30 damage and ends their movement.
- After triggering, the trap becomes disabled (visible to enemies).

## Bases and Towers

- Friendly units can occupy base or tower tiles.
- Towers grant garrison bonuses (+3 melee, +3 ranged, +1 ranged range).
- Bases grant no combat bonuses.
- Enemy units can enter enemy base or tower tiles as a destination.
- Bases and towers are primary attack targets when a unit shares the tile.
- Bases and towers never retaliate and always fight as if at full health.
- Destroying a base ends the game.

## Mines

- Mines are captured by occupying their tile.
- The owner retains control until the other player occupies the mine.
- Mine income is granted each Upkeep if the owner controls the tile.
- Road bonus: +10 gold if the mine is connected to your network by a continuous road path.
- Rail bonus: +20 gold if the mine is connected by a continuous rail path (all tiles on the path must be intact rails).
- Bases and towers count as rail tiles for connectivity.

## Neutral Monsters

- Camps spawn neutral archers.
- Dragons use two attack modes per neutral step:
  - Fire: ranged attack within range 3, hitting one target or two adjacent targets.
  - Cleave: melee attack within range 1, hitting up to three adjacent targets.
- Neutrals do not move.
- Neutrals attack after player actions resolve.
- If no targets are in range, neutrals heal instead.

### Target Selection
Targets are weighted by distance and health:
- weight = (1 + 3 * (1 - hp_ratio)) * (1 / (distance + 1))
- Lower health and closer distance increase the chance of being targeted.
- Dragons choose melee targets first, then fire targets with a reduced chance to repeat melee targets.

### Respawns and Rewards
- Camp respawn: 6 to 10 turns after cleared.
- Dragon respawn: 12 to 20 turns after cleared.
- Respawn countdown starts only when the tile is empty.
- If a unit steps on a camp or dragon tile before respawn, the timer resets.
- Camp rewards: random gold from 150 to 300.
- Dragon rewards: predetermined per spawn (gold, melee bonus, or ranged bonus).
- Respawn timers are only shown when close to respawn (3 turns for camps, 5 for dragons) unless dev override is enabled.

## Multiplayer

- The host validates all orders and advances execution.
- Clients receive authoritative snapshots each step.
- Execution pauses between steps so both players stay in sync.

## License

See `LICENSE`.
