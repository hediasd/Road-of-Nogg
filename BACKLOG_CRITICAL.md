# Critical backlog

Items here need prompt resolution because they leave current gameplay incomplete
or misleading.

## Battle25D crashes while releasing script resources at application exit

Loading `scenes/Battle25D.tscn` and closing it returns Windows access-violation
code `-1073741819`. Godot reports `ObjectDB instances leaked at exit` and 46
GDScript/shader resources still in use. The failure occurs on the untouched
setup screen before a simulator, visual adapter, or spell aura exists, under
both headless Compatibility and normal windowed Vulkan rendering. A detached
comparison at pre-aura commit `b678bf2` reproduces the identical exit code and
46-resource count, so this is not an aura regression.

Run the setup screen with `--verbose --quit-after 2` to enumerate the retained
resource graph. The retained roots include the battle setup/state/factory
scripts, `NoggTheme`, `NoggWindow`, `BattleMeshFactory`, `DamageNumberBillboard`,
and the two retro-surface shaders. Identify and break the script/resource
ownership cycle, then prove setup-screen exit and a completed live battle both
return code 0 with no ObjectDB, RID, shader, font, or resource leak report. Do
not treat the battle-complete marker as sufficient: the access violation occurs
after that marker during engine cleanup.

## Finish battle-window restyle validation

The shared XenoText, translucent body, thin pale rim, and exterior halo are
implemented, but the preview harness was not updated and the consolidated
normal-window visual pass did not run before the user redirected work to the
ice-storm cycle. Update debug/preview_theme.gd so it exercises the shipping
NoggWindow renderer over hostile bright/dark backgrounds, active/inactive
focus states, paging, docked status boxes, and a viewport edge. Then run the
integrated 1152x648 Player vs CPU pass in normal and UI-through-CRT modes,
covering every battle window, click-through/clickable behavior, damage numbers,
interruption, and teardown. Obtain user approval of the resulting reference
match before treating the restyle as complete.

## The action forecast says nothing about a buff or debuff spell

`PlayerTurnController._forecastText()` branches on `spell.heals`, then on
`spell.damage_lines`. A spell that is neither — every pure buff, debuff, and
status spell in the catalogue — matches no branch and falls through to
`"Expected: N unit(s) affected"`. `Empower` is the clearest case: it grants
`BUFFS_ATK: 3` for `BUFF_DURATION: 2`, and the one window whose entire job is
to tell the player what an action will do reports only that one unit is
affected. The confirm step is therefore blind for a whole class of spells: the
player is asked to commit to an effect the UI never states. The authored fields
are already on `Spell` and the affected-target list is already computed, so
this is a presentation gap, not a missing mechanic.

## Health is readable for at most two units out of eight

The docked actor and target windows are the only surfaces carrying HP, and they
show one unit each. In a 4v4 the other six are unreadable without moving the
pointer to each in turn. The turn rail's tiles carry a health strip, but only
for the handful of units the rail is currently showing, and only as a bar with
no numbers.

This was going to be answered by a health-and-level plate under every unit. That
plate was built, redrawn, and then rejected outright by the user -- "Remove the
healthbar and the level next to it, I dont like it" -- and reverted in `2d0bb81`.
The finding outlived the feature: it is still true, and it now has no planned
owner. Whatever takes it up should not be a plate under each unit.

The deep card narrowed it rather than closing it: holding `C` over a unit gives
that unit's full readout, including how many basic attacks the acting unit needs
to remove it. That still answers one unit at a time.

## A spell blocked by anything except a cooldown still reads `CD 0`

`PlayerCommandMenu.spell_value()` shows a range for a ready spell and
`CD <remaining>` for every spell that is not, but `Monster.can_cast()` refuses a
spell for three separate reasons: an unexpired cooldown, an element the caster
does not carry, and a sequence-level-4 spell whose Resonance bar is not full.
Only the first has a remaining count, so the other two render as `CD 0` -- a
spell that is greyed out, claims zero turns of cooldown, and still cannot be
cast. `Roses at Summers End` on `Walker of the Woods` is the shipping example:
it is a level-4 Resonance finisher, so it reads `CD 0` for the entire battle
until the wood bar fills.

**The surface that would explain it is on the other side of the screen.** A
level-4 finisher's real gate is a Resonance bar, and that bar is drawn as a
three-cell graphic in the third column of the docked status window -- correct,
live, and with nothing anywhere connecting it to the greyed row in the spell
list. So the player is told "cooldown", shown a zero, and left to discover
Resonance somewhere else entirely. That makes this a legibility defect as much
as a formatting one: the row names the wrong mechanic.

The fix belongs in `spell_value()`, which is the single shared formatter for
both the spell window and the deep card, so correcting it corrects both at
once. It needs `can_cast()`'s reason rather than its boolean, which means
widening what `PlayerTurnController.spellEntriesFor()` reports -- the entry
already carries `cooldown_remaining` and `ready`, and the missing piece is why.

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

## Monster level and growth

- **Battle setup cannot choose monster level.** The runtime already derives
  HP, ATK, and DEF from a monster's level, and battle-state serialization
  records that level, but every setup still constructs every roster slot at
  level 1. Add a per-slot level to the setup contract and UI, preserve it
  through replay reconstruction, and default older setup snapshots to level 1.
- **All authored growth values are zero.** After level can vary through setup,
  choose a bounded level range and author role-shaped HP/ATK/DEF growth for all
  monsters. Level 1 must remain unchanged; mixed-level construction, replay,
  and the visible setup-to-status-window path need integrated validation.

## Player command UI

- **The command UI rework is done** (2026-07-29 through 2026-07-31). Turn
  execution is split into order-aware phases, the player state machine lives in
  `src/systems/PlayerTurnController.gd`, the play/pause toggle gates visual
  playback while the simulation runs ahead under `RUN_AHEAD_LIMIT`, and
  `CONFIRM_ACTION` shows a damage/heal/elevation forecast sourced from the same
  `CombatResolver` math real resolution uses. The command menu, playback pause,
  surface-accurate picking, and Spell/`< BACK` navigation are stabilized.
- **Positional targeting has passed headless in-window acceptance**
  (2026-07-31). The pass drove the real `Battle25D` scene through synthetic
  input for legal empty and occupied centers, target cycling with no free grid
  roaming, blocked-empty confirmation, a zero-hit `Dark Nova` cast, mouse
  picking across two elevations and two rotated camera yaws, and both phase
  orders.
- **Camera-relative controls are resolved.**
  `BattlePresentationController._board_direction_for()` rotates an arrow key
  into the board direction it points at under the current camera, quantised to
  quadrants (the board is a square grid, so each key must resolve to exactly
  one axis; a continuous rotation is ambiguous at 45 degrees). It became
  load-bearing rather than cosmetic when `BattleCameraDirector` started
  rotating the camera on its own during CPU turns — the director settles to an
  exact quadrant before a player turn opens, so the mapping is exact rather
  than an approximation. Broader visual accessibility remains open.
- **`debug/drive_battle.gd` now covers ten checks, up from five.** Its
  occupied-only target assertions were replaced with positional ones, and it
  gained typed reference/lifecycle coverage, animation-flow and pause/resume
  coverage, and the empty-center targeting flow.
- **What headless input still cannot establish:** appearance, animation feel,
  and camera-angle usability. A human pass at a normal window remains the only
  way to judge those, and no such pass has been done.
- **`activeActionKind()` cannot observe `focus` or `message` actions.** They
  resolve inside the start handler and never become the active action, so any
  future animation harness must cover that path indirectly (the battle log
  growing) rather than by polling the queue.

## Content inconsistencies

- **`Purple Dungeon Slime` claims "immune to physical crits"** in its
  `DESCRIPTION`, but no such mechanic exists. **Decided 2026-08-01: reword it**,
  do not build the immunity — physical attacks cannot crit at all
  (`_rollCritical()` is only reached from the spell path), so the immunity
  would guard a code path that does not exist.
- **No monster `DESCRIPTION` is read by any production code.** 11 of 28
  monsters carry one and no player has ever seen them, which is how the Slime's
  claim drifted from the implementation unnoticed. The other 10 have never been
  checked against actual mechanics; worth a sweep when descriptions are
  surfaced in the UI.

## Fire Storm has never been validated in a real battle

Fire Storm is implemented, registered, and renders correctly in the VFX debug
harness, with baseline goldens recorded in `debug/vfx_golden/`. Its final
validation pass was never completed, and the effect shipped anyway. What is
still unexercised:

- **Battle integration.** `Smoke Tower` has never been cast in `Battle25D` — no
  terrain, no units, no queue pacing, no CRT compositing in an actual battle.
  This is the significant gap; everything else below is narrower.
- **Adapter lifecycle:** overlap/cap, skip, pause, and speed paths, plus the
  leak check. The harness can spawn overlaps but cannot exercise the adapter's
  own cap and skip logic, so these need a battle or an interactive session.
- **Radius sweep** covered radii 1 and 2 only; its live radius 3 and larger
  modifier cases remain unverified.
- **Four motion-dependent qualities — winding, taper, shrink, lean.** These are
  the spiral's whole premise and have only ever been judged from stills at
  0.2-second spacing, which is far too coarse to read rotation. A tight capture
  series (0.40 / 0.42 / 0.44) settles it and now costs one command.

Worth knowing before re-tuning: the column's particle count (80 + 24) and ember
alpha (0.34) sit far below their ice-derived starting points deliberately. A
vortex concentrates particles into a fraction of a flat field's volume, so
per-pixel additive overlap is much higher at equal counts — density here is a
readability constraint, not a performance one, and "restoring" it toward the
budget would destroy the legible spiral.

## Ice Statue encasement has never been validated in a real battle

The full target-bound ice encasement is implemented and committed: generic
source/target cast context, the debug harness that supplies it, the
transparent-cyan 11-piece shell, formation and hold, the terrain-grown spike
wave, the ground-driven cocoon eruption, analytic ballistic fracture, the
subordinate trail and contact accents, and the `Ice Statue` carrier on
Snowzilla. Every one of those was recorded as *implemented; pending
end-of-plan validation*, and the consolidated validation pass never ran before
the user redirected work to the generic spell-cast aura rework on 2026-08-12.
The effect therefore ships on nothing but debug-harness captures.

What is still unexercised:

- **Battle integration.** Snowzilla has never cast `Ice Statue` in `Battle25D`.
  Needed: at least two visibly different target bodies, short and long legal
  range, an elevated terrain case, event-time placement, transparent-cyan
  readability through CRT, damage-number separation, queue pacing, defeat
  interaction, and unchanged gameplay results.
- **Adapter lifecycle.** Overlap to the live cap, oldest-effect disposal,
  skip, pause, 0.5x/2x speed, retrigger, and battle/app exit with no target
  presentation state surviving. The harness cannot exercise the adapter's own
  cap and skip logic.
- **Cross-effect regression is now covered.** Ice Storm, Fire Storm, Magenta
  Reduction, Ice Target Encasement, and the generic aura were re-captured
  together at 320x240 through the retro path on 2026-08-13. A completed live
  battle also exercised 28 generic multi-target area casts without changing
  their resolved gameplay targets. Keep the target-bound battle cases above
  open; this closes only the shared-resource regression concern.
- **Asserted ceilings under live conditions.** Node, instance, draw-call, and
  overlap figures were confirmed in the harness only.

The per-item resolution evidence is recoverable from `git log` for the commits
between the encasement plan's opening and 2026-08-12.

## The generic spell-cast aura ships on debug-harness evidence only

The source-convergence rework of the generic spell-cast aura is implemented and
committed: the frozen convergence baseline, the zero-to-rise emission
choreography that replaced the global fade-in, the world-space carrier that
removed the striped terraces, the project-owned mask and material stack, the
eleven-state motion/spin/oscillation and final grading match, the user-previewed
ghastly fog vocabulary, and that fog's integration across every aura component.
Each was recorded as implemented, pending end-of-plan validation, and that
consolidated validation never ran before work moved to the solar storm cycle on
2026-08-14. Per-item evidence is recoverable from `git log` for the commits
between 2026-08-12 and 2026-08-13.

Two pieces remain open:

- **The longer lifecycle was never authored.** The aura still runs at roughly
  `1.15` seconds. The intended shape is invisibility at true time zero, a single
  ground-aperture ignition, a visible bottom-to-top emission front, a modest
  `1.08–1.15` height crest with restrained spin and asynchronous tip drift, then
  a staggered recession that dissolves density rather than scaling a finished
  shape back into the ground. Initial target range was `1.8–2.2` seconds, to be
  settled by preview evidence rather than treated as acceptance. The adapter hold
  fraction needs retuning alongside it so a longer visual tail outlives command
  resolution without materially increasing action-queue hold time.
- **Consolidated validation never ran.** Still unexercised: the exact-zero proof
  and dense emergence contact sheet; native and retro modes; light and dark
  terrain; battle-camera yaw and pitch movement; several deterministic seeds;
  ice/fire/thunder/darkness/neutral tinting; pause, speed scale, forward and
  backward seek, skip-to-settle, overlap, replay, disposal and scene exit;
  measured real-time visual and action-hold duration; identical frames for
  identical normalized time and seed; a caller search across every changed shared
  primitive with every returned effect rendered; and a real cast in `Battle25D`
  through the adapter and event path. The `Battle25D` shutdown access violation
  above is a prerequisite for that last one.

