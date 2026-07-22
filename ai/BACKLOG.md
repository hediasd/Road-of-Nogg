# Road of Nogg — Backlog & Suggestions

This file tracks feature ideas, architectural suggestions, and potential improvements identified during development. 
The AI will proactively add suggestions here when observing technical debt, missing systems, or gameplay opportunities.

## Gameplay & Design
- **Directional Facing**: Entities could have a "facing" direction, allowing for backstab damage multipliers or cone-based AoE attacks.
- **Terrain Modifiers**: Expand the `terrainBoard` to include varied terrain types (mud, high ground) that affect movement costs and line-of-sight.

## Engine & Architecture
- **Animation Queueing**: As the visual adapter gets more complex, implement an asynchronous visual action queue so events can play out sequentially in the UI without blocking the headless engine.

## Code Quality & Cleanup
- **Clean Up Factory Preloads**: Ensure all `preload()` references match the actual folder structure strictly, even though Godot's `class_name` currently masks path inaccuracies.
