# Fortress Frontiers

## Table of Contents
- [Game Overview](#game-overview)
- [Components & Terminology](#components--terminology)
- [Setup](#setup)
- [Turn Sequence](#turn-sequence)
- [Units](#units)
- [Structures & Territories](#structures--territories)
- [Actions](#actions)
- [Execution Phase](#execution-phase)
- [Combat & Conflict Resolution](#combat--conflict-resolution)
- [Victory Condition](#victory-condition)
- [Future Features](#future-features)

---

## Game Overview
Fortress Frontiers is a simultaneous-orders, turn-based strategy game on a hex grid. Each player commands units to capture mines, generate gold, and ultimately **destroy the opponent's base**.

---

## Setup
1. **LAN**  
   - Host enters a port number and clicks host game
   - Client enters port number and IP address of host

2. **Internet**
    - Host sets up port forwarding on router
    - Same setup as LAN from there

---

## Components & Terminology
- **Hex Grid**: 18×15 horizontal-offset layout  
- **Bases**: Each player's home structure  
- **Mines**: Resource hexes that grant gold  
- **Units**: Scout, Soldier, Archer, Miner and Tank
- **Gold**: Currency to purchase units (5 base + 2 per mine each Upkeep)  
- **Order**: A single action assigned to a unit during the Orders Phase  

---

## Turn Sequence
Each turn proceeds through three phases:

### 1. Upkeep Phase
- Add **25 gold** base + **10 gold** per mine owned  
- Apply **Heal** orders from last turn: units gain HP equal to their **Regen** stat  
  - Scouts: +15 HP  
  - Soldiers & Archers: +10 HP  

### 2. Orders Phase (hidden, simultaneous)
- Assign **one** action per unit:  
  - Move  
  - Ranged Attack (Archers only)  
  - Melee Attack  
  - Heal  
  - Defend  
- **Newly purchased units may not act** this turn, except:  
  - Scouts may only Move (and can move-into melee)  
- Both players confirm with **Done** before proceeding  

### 3. Execution Phase (simultaneous resolution)
1. **Ranged Attacks**  
2. **Melee Attacks**  
3. **Movement** (resolved one tile per tick)

---

## Units

| Type    | Cost | Max HP | Move Range | Melee Str | Ranged Str | Range | Regen | Special                                  |
|---------|------|--------|------------|-----------|------------|-------|-------|------------------------------------------|
| Scout   | 25   | 100    | 2          | 3         | —          | —     | 15    | Can **Move** on purchase turn; cannot issue Melee orders (move-into only) |
| Soldier | 60   | 100    | 2          | 10        | —          | —     | 10    | —                                        |
| Archer  | 75   | 100    | 2          | 5         | 18         | 2     | 10    | —                                        |
| Miner   | 50   | 100    | 2          | 1         | —          | —     | 10    | Extra 15 gold per turn when on a mine    |
| Tank    | 100  | 100    | 1          | 5         | —          | —     | 10    | Extra 13 melee strength when defending, no multi defending penalty |
---

## Structures & Territories
- **Mines**:  
  - Capture by moving a unit into the hex  
  - Flip ownership immediately; grant +10 gold/turn; indestructible  
- **Bases**:  
  - 100 HP; passive structure (no counterattack)  
  - Melee Str 10 used when calculating incoming damage  

---

## Actions
- **Move**: Relocate up to 2 tiles (resolved in two ticks). Moving into an enemy triggers a **move-into melee**.  
- **Ranged Attack**: Archer only; Range 2; no unit-blocking LOS yet; cannot target friendly units; wasted if target dies.  
- **Melee Attack**: Attack an adjacent enemy; cannot target friendly units; wasted if target dies.  
- **Heal**: Skip actions; queue HP gain next Upkeep equal to **Regen**.  
- **Defend**: No damage reduction; retaliates with:  
  - **Melee Str** vs. melee attacks  
  - **Ranged Str** vs. ranged attacks  
  Suffering −2 Str penalty per additional simultaneous attacker.  

---

## Execution Phase

### A. Ranged Attacks
All Archer ranged orders resolve simultaneously. Apply damage; remove dead units immediately.

### B. Melee Attacks
All Melee orders resolve simultaneously. Apply damage; remove dead units immediately.

### C. Movement Resolution
1. **Tick 1**: First step of Move orders in submission-priority.  
2. **Tick 2**: Second step for units with remaining Move.  
- Empty hex: move in  
- Enemy-occupied: **move-into melee**  
- Friendly-occupied: swap if friendly also moves, else follow enemy conflict rules  

---

## Combat & Conflict Resolution
1. **Move-Into Melee**  
   - Immediate melee attack when entering enemy hex  
   - Movement ends after dealing damage  
   - If defender dies: mover occupies hex  
   - If both survive: both stay in original hexes; mover bounces back  
2. **Movement Conflicts**  
   - Simultaneous movers resolve in submission priority  
   - Friendly units may swap; enemies bounce based on priority  
3. **Wasted Attacks**  
   - Attacks targeting units that die earlier in the same phase are lost  

---

## Victory Condition
A player immediately wins when the opponent’s base reaches 0 HP.

---

## Future Features
- **Terrain**: Will affect movement cost, block LOS, and grant combat modifiers  
- **Fog of War**: Hidden movement and limited vision  
- **Structures**: Additional buildable structures with unique effects  
