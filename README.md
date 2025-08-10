# Fortress Frontiers

## Overview

**Fortress Frontiers** is a two‑player, networked, turn‑based strategy game built in Godot. Each match takes place on a hex‑grid map where players deploy and command units to capture special tiles and towers, earn gold, and ultimately destroy the opponent’s base. The game uses simultaneous orders: both players submit their actions in secret, after which the game engine resolves the turn in a deterministic sequence.

## Turn Structure

Every turn follows a three‑phase cycle governed by the TurnManager class:

1. **Upkeep phase** – gold income is awarded and unit statuses reset. The host broadcasts the phase to all clients and updates the fog of war. During this phase, each player receives a base income and additional income for controlled towers, mines and miners[\[1\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L120-L138). Units that were set to heal during the previous turn regain health up to their maximum[\[2\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L141-L155).
2. **Orders phase** – both players secretly queue orders for each unit. Valid orders include moving, ranged attack, melee attack, healing, defending and spawning new units. After a player submits their orders via the UI, the turn manager waits until both players have submitted before proceeding[\[3\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L161-L171).
3. **Execution phase** – the orders are resolved in a deterministic sequence. Spawn orders are processed first, followed by ranged attacks, melee combats and finally movements[\[4\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L250-L307). Each execution step pauses briefly so that both clients stay in sync.

### Upkeep and Economy

The economy determines how many units a player can purchase. At the start of each turn, gold is awarded according to these rules (from TurnManager.gd):

- **Base income (10 gold)** – earned if a player still controls their base tile[\[5\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L125-L138).
- **Tower income (5 gold)** – each tower controlled awards five gold per turn[\[6\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L36).
- **Mines (10 gold)** – capturing mines grants ten gold each turn. Once a mine is captured, it will generate gold for that player, regardless of whether or not they have a unit on the mine, until the other player captures it for themselves.[\[6\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L36).
- **Miner bonus (15 gold)** – when a miner unit occupies a mine, an additional 15 gold is earned[\[6\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L36).

After income is tallied, unit statuses are reset: orders are cleared, defending/healing flags are reset, and units healing from the previous turn regain health[\[2\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L141-L155).

### Orders Phase

During the orders phase, players decide how each unit will act. Orders are collected per unit using a dictionary keyed by the unit’s network ID[\[8\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L171-L190). Units which have not received an order yet are highlighted. Available actions are:

- **Move** – select a path up to the unit’s move range. Units can move through friendly units but may clash with enemies during execution.
- **Ranged attack** – available only to ranged units (archers). Requires a target within the unit’s ranged range.
- **Melee attack** – adjacent attack; all units with can_melee = true may perform melee attacks[\[9\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/unit.gd#L9-L20).
- **Defend** – unit assumes a defensive stance, increasing its melee defence. Phalanx units gain an extra bonus when defending[\[10\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L334-L349).
- **Heal** – unit forfeits other actions to regenerate health equal to its regeneration stat during the upkeep of the next turn[\[2\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L141-L155).
- **Spawn** – purchase and place a new unit adjacent to your base. Spawn orders are executed before other orders during the execution phase[\[11\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L212-L227).
- **Undo Buy** - if a unit was purchased during this turn, it can be fully refunded

Players can purchase units as long as they have enough gold. Unit costs are shown in the unit summary table below.

### Execution Phase

Once both players have submitted their orders, the game resolves actions in this order:

1. **Spawns** – new units are added to the board.[\[11\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L212-L227).
2. **Ranged attacks** – archers fire at targets within range. Damage is calculated using an exponential formula based on the attacker’s ranged strength and the defender’s melee strength; damage is modified by the current health of both attacker and defender[\[12\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L250-L277). Defending phalanxes use their melee strength plus a bonus when calculating defence[\[13\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L268-L274).
3. **Melee combats** – simultaneous melee fights are grouped per target. Attack priorities determine which attacker strikes first. When multiple attackers gang up on a defender, the defender’s effective melee strength is reduced by its multi_def_penalty for each additional attacker[\[14\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L331-L338). Damage is calculated similarly to ranged combat, and units may retaliate if defending[\[15\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L345-L356).
4. **Movement** – units move one tile along their planned paths. If a unit enters a tile with an enemy, a quick melee skirmish occurs. Multiple units entering the same tile are processed in the order in which those units recieved orders, and units that survive may occupy the tile[\[16\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L395-L512). If there are still units which have further to move, this phase is repeated.

## Units

All units inherit default properties from scripts/unit.gd. Default stats include melee strength 1, ranged strength 0, move range 2, sight range 2, maximum health 100 and regeneration 10 per turn[\[17\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/unit.gd#L9-L18). Each scene overrides these values to create unique unit types. The table below summarises all playable units and their key statistics (values not shown inherit the default):

| Unit | Cost (gold) | Key traits and overrides |
| --- | --- | --- |
| **Archer** | 100 | Ranged unit; melee 10; ranged 30; ranged range 2[\[18\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Archer.tscn#L16-L22). |
| **Soldier** | 75  | Melee strength 20[\[19\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Soldier.tscn#L16-L19); no ranged attack. |
| **Scout** | 50  | Melee strength 4; move range 3; sight range 3; regeneration 15[\[20\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Scout.tscn#L16-L21). |
| **Miner** | 75  | Regeneration 15; provides +15 income bonus when starting a turn on a mine. |
| **Phalanx** | 100 | Melee strength 10; multi_def_penalty = 0[\[22\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tank.tscn#L16-L21); receives a +20 defense bonus when defending[\[7\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L39). |
| **Cavalry** | 125  | Move range 3; melee strength 20|
| **Tower** | –   | Static structure; melee strength 20; cannot move[\[23\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tower.tscn#L16-L19). Generates 5 gold per turn when controlled[\[6\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L36).; Player can spawn units adjacent to Tower |
| **Base** | –   | Player’s headquarters; melee strength 20; cannot move; maximum health 500[\[24\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Base.tscn#L16-L20);Player can spawn units adjacent to Tower; Generates 10 gold per turn; Losing your base means losing the game. |

### Combat Formula

Damage is computed using a symmetric exponential formula. Attack and Defense strength is scaled based on current unit health. Full health has full strength down to 50% strength at 0 health. For an attack with strength atk against a defender with strength def, the damage inflicted is 30 × 1.041^(atk − def)[\[25\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L274-L275). 

## Hosting and Network Setup

Fortress Frontiers uses Godot’s ENet networking. One player hosts the game while the other connects as a client. To host a match:

1. **Choose a port** – in the main menu, enter a port number (for example, 8910) in the PortLineEdit field, then click **Host**. The UI calls NetworkManager.host_game(port), which creates an ENet server on the chosen port[\[26\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/NetworkManager.gd#L28-L34).
2. **Configure your router** – to allow an external client to connect, forward the chosen UDP port on your router to the internal IP address of the host computer. Consult your router’s manual for port‑forwarding instructions. When forwarding, specify both UDP and TCP protocols if possible.
3. **Share your public IP and port** – tell the client your public IP address and the port you opened. The host’s game will start when a client connects.

To join a game as a client:

1. Enter the host’s IP address and port in the IPLineEdit and PortLineEdit fields and click **Join**. This calls NetworkManager.join_game(ip, port)[\[27\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/NetworkManager.gd#L28-L40).
2. Ensure that your own firewall permits outbound connections to that port.

If you are hosting on a local network (LAN), port forwarding may not be required. For internet matches, port forwarding and firewall configuration are critical.

## Getting Started

1. Download the most recent version from the releases.
2. Run the project. On the title screen, enter your desired port and click **Host** to create a game, or enter the host’s IP/port and click **Join** to connect.
3. During the game, use the unit buttons on the left panel to purchase units. Click a unit on the map to select it, then choose an action from the contextual menu.
4. When you have finished planning your turn, click **Done**. Wait for your opponent to submit orders; the game will then resolve the turn.

## License

This codebase is provided as‑is under the repository’s license. See LICENSE for details.

[\[1\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L120-L138) [\[2\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L141-L155) [\[3\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L161-L171) [\[4\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L250-L307) [\[5\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L125-L138) [\[6\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L36) [\[7\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L32-L39) [\[8\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L171-L190) [\[10\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L334-L349) [\[11\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L212-L227) [\[12\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L250-L277) [\[13\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L268-L274) [\[14\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L331-L338) [\[15\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L345-L356) [\[16\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L395-L512) [\[25\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd#L274-L275) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/TurnManager.gd>

[\[9\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/unit.gd#L9-L20) [\[17\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/unit.gd#L9-L18) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/unit.gd>

[\[18\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Archer.tscn#L16-L22) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Archer.tscn>

[\[19\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Soldier.tscn#L16-L19) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Soldier.tscn>

[\[20\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Scout.tscn#L16-L21) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Scout.tscn>

[\[21\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Miner.tscn#L16-L20) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Miner.tscn>

[\[22\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tank.tscn#L16-L21) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tank.tscn>

[\[23\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tower.tscn#L16-L19) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Tower.tscn>

[\[24\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Base.tscn#L16-L20) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scenes/Base.tscn>

[\[26\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/NetworkManager.gd#L28-L34) [\[27\]](https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/NetworkManager.gd#L28-L40) GitHub

<https://github.com/mrclimberdude/fortress-frontiers/blob/64710fdc74c26bad2a6e1691e0df1491cd5508b8/scripts/NetworkManager.gd>