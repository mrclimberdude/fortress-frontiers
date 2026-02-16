# Fortress Frontiers Rulebook

## Introduction

Fortress Frontiers is a competitive, turn-based strategy game where each player expands from a base and towers, secures mines for income, and fights for map control. You issue orders in secret, then watch the host resolve them step-by-step so positioning, timing, and risk management matter as much as raw strength.

The map mixes open ground, forests, rivers, lakes, and mountains. Terrain changes movement costs and combat outcomes, while fog of war means information is partial and last-known. Neutral camps and dragons add pressure and rewards, and players can build roads, railroads, fortifications, traps, spawn towers, and magical infrastructure to shape the battlefield.

Victory comes from destroying the enemy base, but the path there can involve economic play (mines, roads/rails), tactical fights (ranged vs melee, towers, buffs), and spell-driven swings. The rules below cover the core systems and their interactions in detail.

## Overview

Fortress Frontiers is a two-player, host-authoritative, turn-based strategy game on a hex grid. Both players submit orders simultaneously. The host resolves those orders step-by-step and broadcasts authoritative snapshots to clients.

## Core Loop

Each turn has three phases:

1) Upkeep
- Award gold and mana.
- Apply healing from the previous turn.
- Reset unit flags and orders.
- Apply auto-orders (always heal/defend/lookout/build/ward vision, build queues, move queues).
- Tick neutral respawn timers.
- Update fog.

2) Orders
- Each unit can receive exactly one order.
- Orders are hidden from the opponent until execution.
- Units purchased during Orders are visible and interactable only to the purchasing player until the Spawn step.

3) Execution (step-by-step)
- Spawns (including ward vision)
- Spells (heal/buff)
- Attacks (melee/ranged + fireball/lightning)
- Engineering (sabotage, repair, build)
- Movement (step-by-step)
- Neutral attacks

## Orders and Restrictions

Available orders:
- Move
- Move To (queued move)
- Ranged attack (ranged units only)
- Melee attack (units with can_melee)
- Heal
- Heal until full (repeats each turn until full)
- Defend
- Always defend (repeats each turn until changed)
- Lookout (scouts only)
- Always lookout (repeats each turn until changed)
- Build (builders only)
- Build Road To (builders only, queued)
- Build Railroad To (builders only, queued)
- Repair (builders only)
- Sabotage (any unit, same tile)
- Cast Spell (wizards, bases, towers)
- Ward Vision / Always Vision / Stop Vision (wards only, see Wards)
- Spawn (purchase during Orders)
- Undo Buy (for units purchased this turn)

Queued and repeating orders:
- Build repeats automatically while a structure is under construction unless the builder lacks gold for a step.
- Build Road To queues move + build steps until complete, a step fails, or a new order is issued.
- Build Railroad To upgrades roads; if a step lands on a non-road tile when executed, the queue ends.
- Move To queues a path; each turn the unit moves as far as it can along that path.
- Move To cancels if the unit ends a turn on a different tile than expected or a new order is issued.

## Visibility and Fog of War

- Each unit reveals tiles within sight range.
- Forests and mountains block line of sight.
- A blocking tile is still visible, but tiles beyond it are not.
- Scouts using Lookout (or Always Lookout) gain +1 sight and can see over forests until the next Execution phase.
- Intact traps are hidden from enemies.
- Wards are hidden from enemies except wizards (disabled wards are visible to all).
- Explored (light) fog shows the last known structure and last known dragon on a tile, but not respawn countdowns.
- Dragon color reflects its current reward type and is preserved in last-known fog memory.

## Resources

### Gold
Gold is gained during Upkeep:
- Base: +10 if you control your base tile.
- Starting towers: +5 each (spawn towers do not provide income).
- Mines: +10 if controlled, plus miner bonuses and road/rail bonuses (see Mines).

### Mana
Mana is gained during Upkeep:
- Crystal Miner on a controlled mine: +10 mana.
- Mana Pump: +5 mana if its paired mine or base is controlled and its mana pool is intact.
- Dragon mana reward: +10 mana per turn and +100 max mana.

Mana is capped. Base cap is 0; each intact mana pool adds +100 to the cap. Dragon mana rewards add +100 max mana. If the cap drops below current mana (e.g., a pool is sabotaged), excess mana is lost.

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

- You can spawn units on your base tile and any tower tile you control.
- You can also spawn on tiles adjacent to those spawn points.
- Spawn towers only count if they are connected to your road or rail network (bases, towers, and mines count as road/rail endpoints).
- For connectivity, roads must be intact; rails under construction count as roads.
- Spawn orders resolve first during Execution.
- Spawn towers have the same combat stats as starting towers but do not provide additional income.
- If a spawn tower is connected only by road, you may spawn: Scout, Builder, Miner, Crystal Miner, Soldier.
- If connected by rail, you may spawn any unit.

## Movement and Pathing

### Movement Costs
- Base movement cost is determined by terrain.
- Roads and rails modify terrain costs:
  - Road (intact): base_cost * 0.5
  - Rail (building): base_cost * 0.5
  - Rail (intact): base_cost * 0.25
- Scouts treat forest tiles as cost 1 instead of 2.
- Unexplored tiles are treated as cost 1 during Orders; the real cost is enforced at Execution and may trim the move.
- Cavalry may move one extra tile if it continues in a straight line and the extra tile's cost fits within a +1 budget.

### Movement Rules
- Mountains are impassable.
- Enemy bases and towers can be entered as a destination, but you cannot path through them.
- Roads and rails can be built across forest and river.
- Road or rail built on a river tile takes +1 turn to complete.
- Friendly units can hop over a stationary friendly builder/miner/crystal miner if:
  - The landing tile is free.
  - The unit has enough movement remaining.
  - The origin, blocker, and landing tiles count as road/rail (owned mines, bases, and towers also count).
  - The blocker is not moving.
  - Only a single hop is allowed.

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

7) Movement cap
- If the movement phase exceeds 20 ticks, remaining movement orders are skipped and neutral attacks proceed.

## Combat

### Targeting
- Ranged attacks require line of sight and range.
- Melee attacks require adjacency.
- If a unit and a structure share a tile, the structure is the primary attack target.

### Retaliation
- A defending unit retaliates when attacked.
- For ranged attacks, the defender retaliates if they are ranged OR the attacker is adjacent.
- Towers and bases never retaliate directly. If a defending garrison unit is on that tile, the unit retaliates instead.
- Neutral units do not retaliate when attacked; they only deal damage during neutral attacks and last-breath attacks.

### Damage Formula

Damage is symmetric and exponential:

- Damage = 30 * 1.041^(attack_strength - defense_strength)
- For non-neutral, non-structure units, strength scales with current health:
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
- Spell buff: +0.1 melee and +0.1 ranged per mana spent for one turn.
- Scouts on forest tiles: +5 melee strength vs incoming ranged attacks.

## Spells

Spell rules:
- Spells require vision but do not require line of sight.
- Range is 3 (wizards in a friendly tower gain +1 range).
- Only one spell order per caster per turn.
- Wizards, bases, and towers can cast spells.
- Heal and Combat Buff resolve in the Spells step.
- Fireball and Lightning resolve in the Attacks step.

Spells:
- Heal: 15 mana, heal 25 on a friendly unit.
- Combat Buff: 5-100 mana, +0.1 melee/+0.1 ranged per mana for 1 turn on a friendly unit.
- Fireball: 40 mana, 50 damage to units, 10 to bases/towers, 15 to dragons.
- Lightning: 50 mana, 32 damage to the primary target, then chains to adjacent enemy units with damage halving each hop (each unit hit once).

## Units

Default stats (unless overridden by a unit scene):
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
| Archer | 100 | 15 | 30 | 2 | 2 | 2 | 10 | Ranged unit. |
| Soldier | 85 | 28 | 0 | 2 | 0 | 2 | 10 | Melee unit. |
| Scout | 50 | 4 | 0 | 3 | 0 | 3 | 15 | Lookout; forest move cost 1; +5 melee vs ranged in forest. |
| Miner | 75 | 1 | 0 | 2 | 0 | 2 | 15 | +15 gold/turn on controlled mine. |
| Crystal Miner | 50 | 1 | 0 | 2 | 0 | 2 | 15 | +10 mana/turn on controlled mine. |
| Builder | 50 | 3 | 0 | 2 | 0 | 2 | 10 | Builds, repairs, sabotages; queues roads/rails. |
| Phalanx | 100 | 15 | 0 | 2 | 0 | 2 | 10 | Defend bonus; no multi-def penalty; adjacent ally +2. |
| Cavalry | 125 | 25 | 0 | 3 | 0 | 3 | 10 | Straight-line bonus: +1 move if extra tile cost fits within +1 budget. |
| Wizard | 150 | 4 | 0 | 2 | 0 | 2 | 10 | Spellcaster. |
| Tower | - | 40 | 0 | 0 | 0 | 2 | 0 | Structure; no passive regen. |
| Base | - | 45 | 0 | 0 | 0 | 2 | 0 | Structure; losing it ends the game. |

### Neutral Units

| Unit | Melee | Ranged | Range | Sight | Move | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| Camp Archer | 20 | 40 | 2 | 2 | 0 | Ranged attacker. |
| Dragon | 40 | 40 | 3 | 3 | 0 | Ranged fire + melee cleave. |

## Structures and Engineering

Builders construct structures over multiple turns. Costs are paid per build step.

| Structure | Turns | Cost per Step | Rules | Effect |
| --- | --- | --- | --- | --- |
| Fortification | 2 | 15 | Open terrain only | +3 melee, +3 ranged on tile. |
| Road | 2 | 5 | Can cross forest and river | Movement cost x0.5. |
| Railroad | 2 | 5 | Must upgrade an intact road | Movement cost x0.25. |
| Spawn Tower | 6 | 20 | Open terrain only; requires road/rail connection to start building | Adds a new spawn point (no extra gold). |
| Trap | 2 | 15 | Open terrain or forest | Hidden; triggers on entry. |
| Ward | 2 | 10 | Open terrain, forest, or lake | Hidden (except to wizards); can spend mana for vision. |
| Mana Pool | 3 | 10 | Open terrain or forest; adjacent to mine or base | +100 mana cap; one per mine/base. |
| Mana Pump | 3 | 10 | Open/forest/river/lake; triangle with mine/base and pool | +5 mana/turn if mine/base controlled & pool intact. |

Roads and rails built on river tiles take +1 additional turn.

### Structure States
- Building: under construction, no benefits (except rail under construction counts as a road).
- Intact: full benefits.
- Disabled: no benefits, can be repaired or destroyed.

### Engineering Phase
The Engineering step resolves after Attacks and before Movement:

- Sabotage (any unit, same tile):
  - Intact -> Disabled
  - Disabled -> Destroyed
  - Building -> Canceled
- Repair (builder only):
  - Disabled structure on the same tile -> Intact in one step.
  - Base or tower on the same tile or adjacent -> +30 health (capped).
- Build (builder only, same tile):
  - Deducts gold per step. If insufficient gold, the step does not progress.
- Sabotage can target your own structures (except completed spawn towers).
- Spawn towers under construction can be sabotaged.

### Traps
- Intact traps are hidden from enemies.
- When an enemy enters the tile, the trap deals 30 damage and ends their movement.
- After triggering, the trap becomes disabled (visible to enemies).

### Wards
- Hidden from enemies except wizards (disabled wards are visible to all).
- Ward Vision costs 5 mana and reveals tiles within radius 2.
- Ward vision resolves in the Spawns step and lasts until the next Execution phase.
- Wards see through forests like scouts.
- Always Vision requeues each turn until mana runs out; Stop Vision cancels it.

## Mines

- Mines are captured by occupying their tile.
- The owner retains control until the other player occupies the mine.
- Mine income is granted each Upkeep if the owner controls the tile.
- A miner on a controlled mine adds +15 income.
- A crystal miner on a controlled mine adds +10 mana.
- Road bonus: +10 gold if the mine is controlled and connected by a continuous road path.
- Rail bonus: +20 gold if the mine is controlled and connected by a continuous rail path (all tiles on the path must be intact rails).
- Bases, towers, and mines count as road/rail tiles for connectivity.

## Neutral Monsters

- Camps spawn neutral archers.
- Dragons use two attack modes per neutral step:
  - Fire (ranged): range 3, hits one target or two adjacent targets.
  - Cleave (melee): range 1, hits up to three adjacent targets.
- Neutrals do not move.
- Neutrals attack after player actions resolve.
- If no targets are in range, neutrals heal instead.
- If a camp archer or dragon is killed by attacks or movement, it performs a last-breath attack using the same targeting rules.

### Target Selection
Targets are weighted by distance and health:
- weight = (1 + 3 * (1 - hp_ratio)) * (1 / (distance + 1))
- Lower health and closer distance increase the chance of being targeted.
- Dragons choose melee targets first, then fire targets with a reduced chance to repeat melee targets.

### Respawns and Rewards
- Camp respawn: 8 to 12 turns after cleared.
- Dragon respawn: 14 to 20 turns after cleared.
- Respawn countdown starts when the tile is empty and resets when a unit enters the tile.
- Camp rewards: random gold from 150 to 250 (in multiples of 5).
- Dragon rewards: predetermined per spawn:
  - Gold +1000
  - Melee +3 (stacking)
  - Ranged +3 (stacking)
  - Mana +10 per turn +100 max mana
- Respawn timers are only shown when close to respawn (3 turns for camps, 5 for dragons) unless dev override is enabled.

## Multiplayer

- The host validates all orders and advances execution.
- Clients receive authoritative snapshots each step.
- Execution pauses between steps so both players stay in sync.

## License

See `LICENSE`.
