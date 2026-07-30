# Critical backlog

Items here need prompt resolution because they leave current gameplay incomplete
or misleading.

## Monster spell kits

- **Blue Crowned Pidgeon:** has no spells at all. Assign at least one Wind set
  using the implemented Level 1 pool.
- **Level 2-4 pool covers one element of ten.** Wood is complete as of
  2026-07-28 (`Gather` → `Thornlash` → `Bramble Crown` → `Roses at Summers End`,
  on `Walker of the Woods`) and is the reference implementation. The other nine
  elements still stop at Level 1, so Resonance cannot exceed one charge for any
  monster that does not own the Wood ladder. Author against the tier contract in
  `docs/GAME_DESIGN.md`, which the reference-catalog check enforces.
- **23 of 25 Level 1 spells are assigned to no monster.** They are implemented
  and tested; they simply have no home. Reported as warnings by the
  reference-catalog check (pass `verbose` to list them).
- **Roster readiness check:** after each kit is authored, run the integration
  tier. Sets may be partial, but each set must stay on one element and hold at
  most one spell per Level.

## Player command UI

- **`PC-1` and `PC-2` are done** (2026-07-29). Turn execution is split into
  order-aware phases and the player state machine lives in
  `src/systems/PlayerTurnController.gd`. BM-0 through BM-2 stabilize the
  command menu, playback pause, surface-accurate picking, and Spell/< Back
  navigation. They await in-window verification; see `implementation_plan.md`.
- **PC-3/BM-3 is implemented but still needs in-window acceptance.** Legal
  occupied targets cycle without free grid roaming, invalid clicks are rejected,
  and area shapes preview from the authoritative resolver query. BM-4 remains
  for camera-relative controls and broader visual accessibility work.
- **Mouse tile picking now uses dedicated rendered-surface hitboxes.** Verify it
  at multiple elevations and camera angles before considering it resolved.
- **The player input surface has never been exercised in a real battle.** PC-2
  was verified headlessly against a stub adapter, which covers the phase
  machine but not mouse ray-casting, keyboard routing, or menu-button wiring.
  The animation confirmation carried over from the `VisualActionQueue`
  extraction is still outstanding too. Both are folded into PC-3's
  verification, since PC-3 rebuilds that surface.

## Content inconsistencies

- **`Purple Dungeon Slime` claims "immune to physical crits"** in its
  description, but no such mechanic exists. Now that Luck is live this is a
  visible inconsistency. Either implement the immunity or reword the
  description.
