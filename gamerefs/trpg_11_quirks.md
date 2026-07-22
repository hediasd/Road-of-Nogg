# Aspect 11: Mechanics Quirks & Systemic Limitations

A comparative architectural analysis of how complex logic loops, AI edge cases, and unexpected emergent behaviors are handled and resolved in Tactical RPGs.

---

## 1. Infinite Loops and Action Stagnation

High-level architecture governing how the battle engine prevents combat from deadlocking when units are incapable of harming one another.

### A. The "Loop Detector" Pattern (e.g. Early Access / Roguelike TRPGs)
* **Architecture:** The battle orchestrator tracks the number of meaningful actions taken each round (e.g., attacks, spells, or movements).
* **Execution:** If a complete round passes (all units cycle their turns) and the aggregate action count is 0, the game detects an infinite loop and forcefully terminates the battle (often declaring a draw or victory to the defending team).
* **Use Case:** Used primarily in fully automated combat (auto-battlers) or AI testing simulations to prevent the engine from freezing.

### B. The Hard Turn Limit (e.g. Fire Emblem Heroes, Langrisser Mobile)
* **Architecture:** Battles have a globally enforced maximum round count (e.g., 15, 30, or 50 rounds).
* **Execution:** If the battle is not resolved before the round counter expires, the match immediately ends. The win condition is typically evaluated based on total remaining HP, number of surviving units, or defaults to a Defender Victory.
* **Use Case:** Ensures PvP and PvE matches do not drag on indefinitely due to overly defensive AI or unreachable terrain.

---

## 2. Pathfinding Deadlocks (The "Traffic Jam")

How pathfinding algorithms handle scenarios where a unit's optimal destination is occupied, or the only path forward is blocked by allies.

### A. Partial Path Execution (e.g. Final Fantasy Tactics)
* **Architecture:** If a unit's absolute target tile is unreachable or occupied, the AI calculates a full path, but truncates it to their maximum movement range and stopping just before the obstacle.
* **Execution:** Even if the destination is completely walled off by allies, the unit will step forward as much as possible to form a tighter formation.
* **Drawback:** Can lead to units clustering uselessly behind chokepoints.

### B. Fallback Idle State (e.g. Disgaea - certain AI)
* **Architecture:** If the pathing fails completely (e.g., target is out of range AND path is blocked), the unit simply defaults to passing its turn to save computing time.
* **Execution:** Results in AI units occasionally appearing "brain dead" when faced with complex terrain they cannot navigate.
