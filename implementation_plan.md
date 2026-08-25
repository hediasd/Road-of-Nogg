# Battle Legibility Cycle

**Opened 2026-08-15.** The previous plan held the spell-cast aura
source-convergence cycle. Its first seven items are committed and recorded as
implemented pending end-of-plan validation; the longer-lifecycle authoring item
was never started and the consolidated validation never ran, because work moved
to the solar storm cycle on 2026-08-14. Both genuinely open pieces are now
described in `BACKLOG_CRITICAL.md` under the generic spell-cast aura entry, and
the committed contents remain recoverable with
`git show 6fdfb90:implementation_plan.md`. A repository search found that
cycle's item identifiers only inside the plan file itself, so no persistent
reference needed rewriting.

This cycle addresses a legibility review of `Battle25D` conducted 2026-08-15.
The finding that drives it: the battle computes health, reach, status and threat
correctly, but shows health for at most two units out of eight and disables free
inspection during the one phase where the player is actually deciding. The
review's evidence is reproduced in each item rather than cited, because it is a
conversation artifact and not a persistent file.

## Outcome

A player can read the state of the whole battlefield without changing what is
selected, and can interrogate any unit at any time:

- hovering any unit fills the docked status window and paints that unit's
  movement and strike reach, in every phase including move and target select;
- the turn order becomes a predictive rail: deep enough to cross the round
  boundary where a fast unit's back-to-back double turn becomes visible, linked
  bidirectionally with the board, and showing how a pending SPD change will
  reorder the next round before the player commits to it;
- the danger zone can be attributed to a single enemy rather than read as an
  undifferentiated union;
- deeper reference material — spell lists, cooldowns, passives, race elemental
  matchups — is reachable on a held key without resizing any docked window.

Ordering is by legibility gained per unit of risk. The cycle is designed to stop
cleanly after any item: each one leaves the HUD in a shippable state.

## Present-state facts an executing agent must not "fix"

- **Catalog damage is small.** Shipped stats are base stats: HP `28-60`, ATK
  `2-8`, DEF `2-8`, spell `DAMAGE` `1-7`. Against
  `max(1, atk + power - def)` most exchanges land at `2-8` damage, so a unit
  takes roughly five to twenty hits to remove. Whether that pace is intended is
  a balance question outside this cycle; see "Deliberately excluded".
- **The colour vocabulary is nearly full.** Movement blue, reach purple, target
  yellow, affected red/green and threat magenta are all assigned. Yellow in
  particular is taken twice, by the hovered path in `show_movement_options` and
  by legal targets in `show_target_options`. New surfaces derive from the
  existing set rather than adding to it.

## Items

### LEG-1 — Settle the board-space readout contract in the UI design document

**WITHDRAWN 2026-08-15, by user decision.** The contract and its tokens were
written and committed (`66913b1`), the plate was built against them (`f7cc18f`),
redrawn at Fire Emblem weight on the Aurora/Solar ramps (`1cce3ac`), and the
user then rejected the feature itself: *"Remove the healthbar and the level next
to it, I dont like it."* Not a defect in the execution — the board-space readout
is simply not wanted.

`docs/UI_DESIGN.md` §10c, every `PLATE_*` token, and `src/presentation/UnitPlate.gd`
are removed. **`NoggTheme.team_color()` is kept**: it was extracted from a pair
of colour literals in `GodotVisualAdapter._on_monster_spawned` that broke this
project's no-literals-outside-NoggTheme rule, and that fix stands on its own.

Finding worth keeping, because it outlives the feature: **health is still
visible for at most two units out of eight.** F1 in the review is unaddressed and
no longer has a planned owner. If it is ever taken up again it should not be
through a plate under each unit.

### LEG-2 — Fill the docked status window from hover, in every phase

**Model:** Sonnet 5 / GPT Terra

**Depends on:** nothing. Independent of LEG-1, and safe to execute first if the
contract approval is still outstanding.

**End state:** Moving the pointer over any unit renders that unit into a docked
status window immediately, during move select and target select as well as
outside a player turn. The existing ally-to-actor-window and
enemy-to-target-window routing is preserved. No dwell delays the readout, and
the dither restore keeps its own dwell unchanged.

**Implementation:** `src/systems/BattlePresentationController.gd` already
resolves the hovered unit on mouse motion and passes it to
`_update_hovered_monster`, which sets model solidity only. Add the readout push
alongside that call, reusing the team-relative routing that
`_handle_click_selection` already implements — extract that routing rather than
duplicating it, so the two entry points cannot drift. Leave
`DITHER_HOVER_DWELL_SECONDS` governing solidity only; the readout is immediate.
Restore the previous readout when the pointer leaves every unit, rather than
clearing to an empty frame, so sweeping across the board does not blank the
window the player was reading.

This closes the inspection hole without touching click handling: the click path
stays exactly as it is, because hover cannot conflict with grid selection the
way a click does.

**Risk:** Mouse motion fires per frame; re-rendering a window's rows on every
motion event will churn. Guard on the hovered id actually changing. A second
risk is fighting the live attacker/target push from `GodotVisualAdapter` during
combat playback — hover must not overwrite a readout that combat is currently
driving.

**Adds to final validation:** Hover readout during move select, target select,
confirm, CPU turns and battle end; last-write-wins behaviour against combat
playback; no per-frame rebuild.

**Resolution (2026-08-15):** Implemented. **Validated 2026-08-25.**

The readout is now composed rather than written directly. `_actorPanelMonsterID`
and `_targetPanelMonsterID` hold committed state — written by the click
inspector and by the combat push — and `_refreshStatusWindows` renders those,
then overlays the hovered unit into whichever window it routes to. That is what
lets combat keep updating underneath a hover: when the pointer leaves, the
window shows what the battle has moved on to rather than the snapshot from
before the hover began, which a simple save-and-restore would have produced.

Hover tracking moved out of the `acceptsGridInput()` gate; only the cursor
update and the dither dwell stay inside it. Hover cannot conflict with grid
selection the way a click does, which is what makes ungating it safe rather than
merely convenient. `_mouse_to_battle_coord` and `_unhandled_input` already guard
for a null adapter, simulator and non-battle lifecycle, so no new guard was
needed.

Two smaller things worth recording. `_readoutWindowFor` was extracted from
`_handle_click_selection` rather than copied, so the click and hover paths cannot
drift about where a unit is shown. And hover deliberately does not call
`highlight_monster`: inspecting a unit must not disturb selection state, which is
the same distinction `show_target_status` already draws.

Known cost: the board raycast now runs on mouse motion in every phase rather
than only the aiming ones. The row rebuild is guarded on the hovered id actually
changing, but the pick itself is not, since the pick is what produces the id.
The board carries a handful of collision bodies and the previous code already
did this during the most common interactive phases, so this was accepted rather
than cached; revisit if profiling during final validation shows it.

Probe: `--check-only` reports no parse errors. The exit code remains the
pre-existing teardown access violation recorded in `BACKLOG_CRITICAL.md`.

### LEG-3 — Paint movement and strike reach from hover

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-2.

**End state:** Hovering any unit paints its reachable tiles in the existing
movement blue and the tiles it could strike from that reach in the existing
purple. Releasing hover restores exactly the overlay the player had. A stated
precedence rule governs what happens when the acting unit's own move overlay is
already on the board.

**Implementation:** The queries exist — `getReachablePositions` and the threat
map already serve the AI and the held-`T` overlay. The design decision is
precedence, and it is the reason this item is not mechanical: during move select
the acting unit's reachable tiles are already painted, and hovering an enemy
must not silently destroy them. Choose and record one rule — hovering an enemy
suppresses the actor overlay for the duration of the hover, or the two are drawn
together with the hovered unit's set on top. Additive drawing is the safer
default because it never removes information the player was mid-decision on, but
it can produce four tinted sets at once on a crowded board; settle it by looking
at a real battle, not in the abstract.

Reuse `show_movement_options`' existing colours. Do not introduce yellow — it is
already the hovered path and the legal-target tint, and a third meaning would
collide with both.

**Risk:** Recomputing a flood fill on every hover change will cost more than the
overlay is worth on a large board; cache per unit and invalidate on movement.
The threat overlay and this one can now paint simultaneously, which the tactical
overlay clear paths were not written to expect.

**Adds to final validation:** Hover reach for ally, enemy and the acting unit
itself, in every phase; interaction with held `T`; overlay restoration on
release; no leaked overlay nodes across turns.

**Resolution (2026-08-15):** Implemented. **Validated 2026-08-25.**

**Precedence is additive**, decided by the user. Hover reach draws on a third
overlay layer, `HoverReachOverlays`, added for exactly the reason the threat
layer is a second one: `clear_tactical_overlays()` must not destroy it and
clearing it must not destroy the player's aim. It lifts slightly higher than
both existing layers so an inspection reads as sitting on top of the aim rather
than z-fighting with it, and both tints are drawn at lower alpha than the acting
unit's own overlay so aim and inspection stay distinguishable when both are on
the board. No new colour: movement blue and reach purple are reused, and yellow
is left alone because it already means the hovered path in one overlay and a
legal target in another.

The reach computation was **extracted rather than duplicated**.
`PlayerTurnController._getAttackableTiles` was a private loop bound to
`activeMonsterID`, and hover needs the same answer for an arbitrary unit at
times when there is no active player turn. It is now
`src/battle_sim/ReachQuery.gd`, a headless static composition over
`MovementResolver` and `CombatResolver` that both callers use, so the player's
own move preview and the hover overlay cannot drift. Semantics are preserved
exactly, including appending the unit's current tile to the reachable set.

Reach is recomputed on hover change rather than cached: a cache would need
invalidating on every move, defeat, and move buff, and that bookkeeping is a
likelier source of a stale overlay than the recompute is of a frame drop. It is
also re-derived on turn start, because the board has changed while the pointer
has not moved and nothing else would refresh it. Accepted gap: a reach painted
mid-animation can go briefly stale as units move during playback; any pointer
movement corrects it, and the overlay is an inspection aid rather than a
commitment surface.

`hover_overlay_node` was added to the adapter's teardown list. That list is the
leak guard, and the exit access violation in `BACKLOG_CRITICAL.md` is a
retained-resource failure, so a new persistent node had to join it.

Probe caught a real defect: `ReachQuery` referenced by bare `class_name` failed
to parse in both consumers, because a newly added global class is not in the
script class cache until the project is rescanned. Switched both to a preloaded
script const, which is the dominant pattern in these files anyway and does not
depend on cache state. All five touched scripts now parse clean.

### LEG-4 — Build the unit plate

**WITHDRAWN 2026-08-15, by user decision.** See LEG-1. Implementation reverted;
the adapter's plate layer, per-frame update, declutter pass and teardown entry
are removed, along with the controller's `_process` driver.

Two things learned here are worth not re-deriving:

- **Size UI against a capture, never in the abstract.** The first plate was
  sized from the bitmap face's 12-device-pixel floor, which forced a large ring
  and, through it, a plate wider than the unit it described. Every step was
  locally correct.
- **A greedy "hop past the blocker" declutter does not converge.** Clearing
  blocker A moves onto B, whose nearest free side moves back onto A. Searching
  outward in fixed slots is monotonic in distance and terminates. Any future
  screen-space label layout in this project will hit the same problem.

### LEG-5 — Preview pending damage on the target's health bar

**WITHDRAWN 2026-08-15.** Never started. It depended entirely on LEG-4's bar as
its drawing surface, and there is no longer one.

F9 of the review stands and is now unowned: the forecast is computed and parked
in a bottom-left window, never near the unit being aimed at. Re-siting it does
not require a health bar, so this could return in another form.

### LEG-6 — Give each status effect a distinct silhouette at native resolution

**Model:** Opus 5 / GPT Sol

**Depends on:** nothing. Formerly depended on LEG-1 for the plate's canvas and
sizing; with LEG-1 withdrawn this item owns both. Its native-resolution layer is
now its own, built on the projection path `_spawn_damage_number` established
(`camera.unproject_position` then `RetroRenderController.world_to_screen`).

**End state:** Each of the eleven catalog effects is distinguishable by shape
alone, without relying on colour. The badges are drawn at native resolution
above each unit rather than as world-space sprites, so they survive every
preset. Duration remains legible.

**Implementation:** `src/presentation/StatusEffectIcons.gd` currently maps
`burn`, `poison`, `petrify` and `chill` to one down-arrow, and uses the shield
shape for `guard`, `def_buff` and `def_debuff` alike — four effects with
entirely different consequences render identically, and colour separates only
buff from debuff. Author distinct silhouettes for the five negative effects and
keep the buff/debuff colour split as a redundant channel, not the primary one.
Verify each shape against a capture at the smallest preset before adopting it —
not against reasoning about its size. LEG-4 was lost to sizing a readout in the
abstract, and a 16-pixel badge has far less room for that mistake than a plate
did.

Move the badges onto their own native-resolution canvas. Today they are 16x16 textures at
`pixel_size 0.019` inside the battle viewport, with a duration `Label3D` at
`pixel_size 0.0038` that is smaller than one device pixel under the smallest
preset. Reconsider the overflow arithmetic while there: at five active effects
the current rule shows three icons plus a `+2` badge, so the fifth effect costs
a slot rather than only adding a counter.

**Risk:** This changes a shared presentation surface. Every caller of the status
icon path must be re-rendered, not only the effects being redrawn. Moving the
badges off the world layer changes their anchoring, which the model-bounds
calculation currently supplies.

**Adds to final validation:** All eleven effects rendered and distinguishable;
five-plus stacked effects; permanent-duration display; every render preset;
caller coverage across the status icon path.

**Scope change 2026-08-15, at the user's direction:** badges become plain
squares that **grow on hover**, and are sized ahead of authored art the user
will supply. Distinct silhouettes stay in scope as the placeholder until that
art lands.

**Resolution (2026-08-15):** Implemented. **Validated 2026-08-25.**

**Sizing, which is the part built for the art rather than for today.** Icons are
authored at `StatusIconRegistry.SOURCE_PX` (32) square. A badge rests at half
that and `STATUS_BADGE_HOVER_SCALE` doubles it, so a hovered badge lands at
exactly 1:1 with its source — the art is seen at native resolution at the moment
the player looks closely. The two constants are chosen against each other;
changing one alone gives that property up.

`StatusIconRegistry.ICON_PATHS` is an empty table, deliberately, exactly like
`MonsterVisualRegistry.VISUAL_PATHS`. Dropping the art in later is a table edit,
not a code change, and every name absent from it falls back to a drawn
placeholder — so an empty table is a working game rather than a blank row.

**Split of responsibility.** `StatusEffectIcons` is now a texture source and
nothing else; `StatusBadgeRow` owns layout, hover and drawing;
`GodotVisualAdapter` owns projection and lifecycle. Content stays event-driven
through `_refresh_status_icons`; only placement and the pointer test are
per-frame, so a row following its unit does not cost a rebuild.

**Shape collisions fixed.** `burn`, `poison`, `petrify` and `chill` now draw a
flame, a droplet, a cracked block and a snowflake instead of four identical down
arrows, and `def_buff`/`def_debuff` take up/down arrows so the shield means
`guard` alone. Shape is the primary channel and the buff/debuff colour split is
redundant, which is the correct way round — colour alone fails a colour-blind
player and fails again over a bright board. Textures are cached per
shape/colour, so a row rebuild does not re-rasterise.

**Overflow arithmetic.** `STATUS_BADGE_MAX_VISIBLE` is 5 rather than 4, and the
counter now reports everything it displaced including the effect whose slot it
took.

**Row declutter was added, unprompted but necessary.** The first capture showed
four clustered rows overlapping into the same mess the withdrawn plate produced.
Reuses the algorithm debugged there: outward search in fixed slots (hopping past
blockers does not converge), off-screen counts as blocked, vertical only, and
**upward first** since these rows sit above their units and pushing down walks
them into the model.

**Resting size revised 2026-08-15, at the user's direction:** a badge rests as a
plain colour chip at 4 design units (8 device px) and grows x4 on hover. The
earlier 16-pixel resting badge tried to show a silhouette at a size where none
is legible; it now does not pretend to. At rest the row answers "how many
effects, and roughly what kind" through flat per-effect colour, and hover
answers "which one" by growing to `StatusIconRegistry.SOURCE_PX` and crossfading
the art in over the chip. `4.0 units * 2 ui_scale * 4.0 hover = 32` keeps the
grown badge exactly 1:1 with the source; the three numbers are chosen together.

Chip colour is per effect rather than merely buff/debuff. At eight pixels colour
is the only channel available, and three distinguishable colours tell the player
more than three identical red squares at no extra cost. Duration is drawn only
on the grown badge — there is no room for a numeral at the resting size.

Verified by capture at the default preset and at `tactics_classic` (480x360):
eight rows, one to six effects each, no overlaps, silhouettes distinguishable,
durations legible, overflow counter correct. `StatusEffectBillboard.gd` is
deleted — nothing billboards in world space now.

### LEG-7 — Rework the turn order into a top portrait rail

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-2.

**Blocking:** yes, on one placement decision. See "Where it docks" below — the
top band is already spoken for and the resolution moves a second window.

**End state:** The turn order becomes a horizontal rail of portrait tiles across
the top of the screen. Each tile carries a rendered miniature of that unit's
model, a team-coloured frame, its position in the queue, and a health hint. The
rail runs deep enough to cross the round boundary with an explicit divider, the
active unit reads as detached rather than merely leftmost, hovering a tile
highlights that unit on the board and hovering a unit highlights its tile, and a
pending SPD-changing action previews its effect on the next round's order before
the player commits.

**The tile.** Square, authored in design units and scaled by `ui_scale` like
every other geometry token. Composition follows one rule: **the model and the
overlays never share a quadrant.** The miniature is offset down and to the
right, so the head sits centre-to-right of the frame and the base bleeds off the
bottom-right corner — the standard bust crop, and the reason the user's
off-centre instinct is correct rather than merely stylistic. That leaves the
top-left clear for the queue number, and the bottom edge clear for a health
strip inside the frame. The frame border carries the team colour, because at
tile size a team-tinted model is not a reliable signal on its own.

**The queue number.** A number that only restates left-to-right position is
redundant. It earns its place by being **round-relative** — numbering restarts
after the divider, so the rollover reads `… 5, 6 | 1, 2 …` and a unit that
appears twice carries `6` and then `1`. That makes the double turn self-evident
from the tiles themselves rather than inferred from the divider. Keep SPD off
the tile; it belongs on hover or in the deep card, or the tile stops being
glanceable.

**Where it docks — the blocking decision.** The top band is already occupied
twice over. The prompt window docks top-centre at `PROMPT_TOP` (12 design units)
and is `PROMPT_WIDTH` 470 units wide, and the developer bar sits at the top on
`DEV_LAYER` above everything. `BACKLOG_CRITICAL.md` already records the prompt
losing to the dev bar. Adding a third occupant without deciding the band's
ownership will produce a three-way collision.

The recommended resolution is that **the rail owns the top band and the prompt
docks beneath it**: the rail is persistent and the prompt is transient, so the
persistent element should hold the stable position. That costs a `PROMPT_TOP`
change and a `docs/UI_DESIGN.md` §8 amendment covering both windows. Confirm
before building, and settle the dev-bar overlap in the same decision rather than
inheriting it.

**Rendering the miniatures.** One `SubViewport` per distinct monster name, team
and ascension tier — not per unit, so duplicates share a portrait. Each viewport
holds a body built through the same path the board uses, the team-coloured
`ModelBase` from `BattleMeshFactory`, **and its own light and environment**: the
battle `DirectionalLight3D` lives under `retro_renderer.world_root` and does not
reach a separate viewport, so a portrait viewport without its own lighting
renders black. Set `render_target_update_mode` to update once and cache the
texture; re-render only when the model changes, since eight continuously
updating viewports would cost real frame time while eight one-shot renders cost
almost nothing.

~~Match the portrait camera to the board camera's orthogonal angle.~~
**Superseded during execution.** The board camera looks down at close to 62
degrees, and at portrait size that yields the top of a head and a plinth with
almost no silhouette. Portraits use a three-quarter view at roughly 25 degrees
of elevation instead, which is not merely more flattering but more
*recognisable*, since silhouette is what the eye identifies a unit by. The
original reasoning below still holds for why the angle matters at all — it was
the chosen angle that was wrong. A portrait
shot from a different angle than the board view reads as a different object and
defeats the recognition the rail exists to provide. Render at native tile
resolution rather than through the retro downsample, consistent with the rest of
the HUD, and explicitly neutralise the `dim_amount` and `dither_amount` uniforms
on the portrait instance so a spent or dithered board unit does not carry that
treatment into its tile.

**The identity problem, which is real today.**
`MonsterVisualRegistry.VISUAL_PATHS` is an empty dictionary, so
`instantiateVisual()` returns null for every monster and every unit on the board
falls back to `_buildPlaceholderBody` — a bulb, ring and stem coin stack tinted
by element on a team-coloured plinth. Eight portraits rendered from that today
are eight near-identical silhouettes separated only by hue, which is precisely
the identification the rail exists to provide.

This does not invalidate the design: the pipeline is the right architecture and
the rail improves on its own as real models land. It does mean the tile needs a
bridge that carries identity while the placeholder does. Add a short name label
— two or three characters — as a permanent tile layer rather than a temporary
one; it also disambiguates the duplicate monsters the design baseline explicitly
allows, which no model snapshot ever can. Give the element colour a visible
notch on the tile for the same reason.

**Genre grounding.** `gamerefs/trpg_01_turn_flow_and_initiative.md` already
classifies this game's model as round-based speed sort with deterministic ID
tie-breaking, the Shining Force family, and records that queue refunds, CT delay
and mid-turn interruption are outside the first playable slice. This item is
therefore a **display** rework and adds no turn-manipulation mechanic. Four
conventions from the genre are worth adopting and one is worth refusing:

- **Predictive re-sort, from Final Fantasy X.** Its turn list re-sorts live as
  you hover an action, so the cost of a slow choice is visible before commit.
  It is the strongest idea in the genre for a speed-ordered system, and it
  applies directly here because `spd_buff` and `spd_debuff` both exist with
  four-turn durations and both change the next round's sort. A rail that does
  not preview that change hides the entire point of casting them.
- **Bidirectional linking, from Triangle Strategy and Baldur's Gate 3.** A rail
  entry and a board unit are the same thing; hovering either should light both.
  Without it the player has to match names, which is exactly the work the rail
  exists to remove.
- **The round break drawn as an object, from Battle Brothers and XCOM.** A
  divider is not decoration here: it is the boundary across which a fast unit
  takes two turns in a row.
- **Per-entry state, from XCOM and Battle Brothers.** Team colour and a health
  hint turn the rail into a roster summary readable without looking at the
  board at all.
- **Refused: the continuous time ruler** of Grandia and Sea of Stars, and the
  CT projection of Final Fantasy Tactics. Both encode *distance* between turns,
  which is meaningful only when turns arrive at uneven intervals. This game
  gives every living unit exactly one turn per round, so a ruler would imply a
  granularity the simulation does not have.

**Implementation:** The data is already available and the current display simply
discards most of it. `round_started` carries the full round order as an array,
which `_on_turn_order_round_started` duplicates into `_turn_order_ids` before
`TURN_ORDER_CAPACITY` in `src/presentation/BattleUIBuilder.gd` truncates the
render to three. Raising the capacity carries the layout with it, because the
window height derives from it through `NoggTheme.window_height`.

The next round's entries need a speed re-sort of the living set, derived from a
copy and never mutating state; the sort is deterministic, ties broken by entity
id, so the projection is exact rather than heuristic. The SPD preview is the
same sort run against the stat the pending action would produce.

Note the existing display trick before changing it: `_on_turn_order_started`
erases the acting unit and pushes it to the front, so the array is a display
order rather than the simulator's queue. Preserve that or replace it
deliberately — do not leave two conflicting notions of position.

Reconsider defeat and skip handling while here. Both currently erase an entry
outright, so the rail silently reflows and the player never sees that the order
changed. The genre convention is to show the removal.

**Risk:** The projection assumes the living set survives to next round and will
mispredict on every kill — re-derive each turn rather than caching across one.
A SPD preview that disagrees with the resolved order after commit is worse than
no preview, so it must run the same sort the simulator will, not a
presentation-side approximation. The rail must remain a pure observer:
`round_started` is an event, and nothing here may call back into the simulator
to ask it to sort.

The portrait pipeline carries its own exposure, and it is the larger half of
this item. Live `SubViewport`s are a new node class in the HUD and a new way to
leak: `BACKLOG_CRITICAL.md` already records an exit access violation with
retained resources, and viewport textures held past battle end would feed it
directly. Portrait instantiation also duplicates the board's model construction,
so any divergence between the two paths shows up as a portrait that does not
match its unit — build both from one shared factory call rather than two similar
ones.

**Adds to final validation:** Rollover display and an observed double turn;
round-relative numbering across the divider; the projection changing when a unit
dies mid-round; equal-SPD ties; SPD buff and debuff previews matching the order
that actually resolves; bidirectional highlight in both directions; defeat and
skip removal; portrait fidelity against the board model for every monster, team
and ascension tier, including duplicates; portrait lighting; rail sizing and the
resolved prompt docking at every `ui_scale`; no leaked viewports or textures at
battle end and application exit; no simulator mutation from the display path.

**Resolution (2026-08-15):** Implemented, with one sub-feature deferred and
named below. **Validated 2026-08-25.**

**The blocking docking decision was taken rather than deferred**, on the
recommendation this item already carried: the rail owns the top band and the
prompt docks beneath it, `PROMPT_TOP` moving from 12 to 34 design units. The
rail is persistent and the prompt transient, so the persistent element holds the
stable position. `docs/UI_DESIGN.md` §8 records both windows and the reasoning.
The developer-bar overlap is unchanged and still open in `BACKLOG_CRITICAL.md`;
it is a dev-layer concern and the dev bar is off in a release build.

Two extractions, both following the pattern LEG-3 and LEG-8 established of
sharing one definition rather than reimplementing:

- `TurnManager.speedSortedIDs()` and `effectiveSpeed()` are now static and side
  effect free, and `sortBySpeed()` delegates to them. The rail projects the next
  round by running the same function the simulator will run at rollover, so the
  forecast cannot disagree with the order that resolves.
- Portraits are built through the same `BattleMeshFactory` calls the board uses,
  so a tile cannot drift from the unit it depicts. **This was claimed before it
  was true.** The first implementation assembled its own body and used a single
  colour from the first element, so a two-element unit rendered split on the
  board and mono in its tile; the same copy also left the head sphere at
  `createMesh`'s 0.4 default instead of the 0.2 the board sets, so portrait
  figures were all head and no body. Both were caught by a user looking at a
  capture, not by any check here. Fixed by extracting
  `src/presentation/MonsterModelFactory.gd` and routing *both* callers through
  it, which is what the claim required in the first place.

`PortraitRenderer` keys viewports by name, team and tier rather than by unit, so
duplicates share one portrait. **Each viewport carries its own light and
environment** — the battle `DirectionalLight3D` lives under the retro renderer's
world root and does not reach a separate `SubViewport`, so a portrait viewport
without lighting of its own renders black. Rendered with `UPDATE_ONCE`, which
reverts itself, so it costs one render for the life of the battle.

Defect found by capture: `draw_texture_rect` has no scissor, so every portrait
spilled its plinth across neighbouring tiles. Clipping is now done by
intersecting the destination with the tile body and mapping that rectangle back
to a source region.

Also caught, and the same root cause as LEG-3 and LEG-4: newly added
`class_name` types are absent from the script class cache until the project is
rescanned, so `TurnOrderRail` and `PortraitRenderer` failed as type annotations
in three files. Preloaded script consts again.

**Deferred sub-feature resolved 2026-08-25; validated the same day.**
`PlayerTurnController` now publishes the declared effects and affected unit IDs
for the spell under the player's cursor. `BattlePresentationController` applies
those only to the projected next-round sort, and `TurnManager` merges them with
the same public, side-effect-free value rule `BattleState.addEffect()` uses.
Target changes reorder the projection immediately; cancel clears it; commit
rebuilds from authoritative state. The current-round queue is never changed.
Intermediate smoke: a waited Godot 4.4 editor-load probe exited 0 with no
parser or resource-load errors. It emitted only the documented editor-quit
progress-dialog shutdown noise; this is not acceptance evidence.

### LEG-8 — Attribute the danger zone to a single enemy

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-3.

**End state:** While `T` is held, hovering an enemy isolates that enemy's
contribution to the danger zone and drops every other threatened tile to a faint
tint. Releasing hover restores the full union. The key remains inert outside an
active player turn.

**Implementation:** `show_threat_options` paints one flat union today, computed
once on key press. Attribution needs the union to retain its source, which is a
change to what the threat computation returns rather than only to how it is
drawn — `src/algorithms/ThreatMap.gd` is headless and must stay that way, so the
per-source breakdown belongs in its return value, not in a presentation-side
recomputation.

**Risk:** Widening a headless algorithm's return shape touches the AI callers
that consume it today. Enumerate them and confirm their behaviour is unchanged;
the threat map informs command evaluation, and a change in its output that
altered a CPU decision would be a gameplay regression disguised as a UI change.

**Adds to final validation:** Per-enemy isolation; restoration on release;
additivity with the movement and reach overlays; unchanged CPU decisions against
a fixed seed.

**Resolution (2026-08-15):** Implemented. **Validated 2026-08-25.**

**The plan's suggested approach was not taken, and the deviation is the point.**
It proposed widening `ThreatMap.generate()`'s return shape to carry a per-source
breakdown. `accumulateEnemy` turned out to already compute exactly that
breakdown privately and then fold it away, so the attribution was extracted into
a new `ThreatMap.threatFor()` instead and `generate()`'s shape is untouched.
That removes the item's stated risk rather than managing it: the threat map
feeds command evaluation, and a change in its output that shifted a CPU decision
would have been a gameplay regression arriving inside a UI change.

`accumulateEnemy` now calls `threatFor` and performs the same fold it always
did, so there is one implementation rather than two that could disagree.
`threatFor` reads its `bounds` dictionary for membership only and never writes
to it, which is what makes the delegation identity-preserving.

Verified rather than argued: `scripts/demo_battle.gd` on its fixed seed produces
a **byte-identical 1569-line transcript** before and after, compared by file
hash against a stashed baseline.

Presentation side: `show_threat_options` gained an `emphasised` subset. When it
is non-empty those tiles hold full strength and the rest of the union drops to a
faint tint; when empty the union paints evenly, as before. The controller holds
the union and the walkable bounds while `T` is down, so hovering re-tints
without recomputing every enemy. Hovering an ally leaves the union even —
attribution is only meaningful for a unit hostile to the acting player.

### LEG-9 — Add the deep card on a held key

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-2.

**End state:** A held key opens a separate `NoggWindow` for the unit under the
pointer, carrying the full spell list with range and live cooldowns, passives,
JUMP, LUCK with its derived critical percentage, the race elemental matchup, and
hits-to-kill against the currently active unit. Releasing closes it. No docked
window changes size.

**Implementation:** A new window, not a taller docked one — trait 6 of the UI
contract fixes docked readouts at six rows precisely so their values cannot
jitter the layout, and that rule is worth more than the rows it costs. Page
rather than scroll, per trait 5.

The race elemental matchup is the reason this item matters beyond convenience:
it swings damage by ±20%, is documented as fully live, and appears nowhere in
the UI at all today, so a player watching a spell land for noticeably more or
less than expected has no surface anywhere that explains why.

**Risk:** Hits-to-kill is a derived number and will be read as a promise. Derive
it from the same `CombatResolver` math the forecast uses, and state what it
assumes — a basic attack from the active unit at current position and elevation
— rather than presenting a bare integer.

**Adds to final validation:** Card contents against catalog data for several
monsters; cooldowns updating live; paging; open and close under every phase;
no docked window resize.

**Resolution (2026-08-25):** Implemented. **Validated the same day.**

The key is held `C`, and `_handle_deep_card_input` is deliberately the same
shape as the threat overlay's handler — press opens, release closes, echo
ignored — with one difference that is the point: it is **not gated on an active
player turn**. The threat overlay is computed relative to whoever is acting and
means nothing without one. The card is the free-look inspector's deep page, and
the phases where a player has time to read it are CPU playback and after the
battle ends. `_clear_deep_card()` exists because of that ungating: a release
only reaches `_unhandled_input` while the lifecycle is BATTLE, so a card still
held when the battle finishes would otherwise never be told to close.

Two extractions, following the pattern the earlier items set of sharing one
definition rather than reimplementing. `PlayerTurnController.spellEntriesFor()`
is now static and takes a monster, with `spellEntries()` delegating for the
active one — the entries were always a pure function of the monster, and the
card lists them for a unit whose turn it is not.
`PlayerCommandMenu.spell_value()` became public and static for the same reason,
so a cooldown cannot read one way in the spell window and another on the card.

**The card repeats nothing the docked windows already show.** HP, ATK/DEF,
SPD/MOV, elements and Resonance are all on screen while it is up, so it carries
only what has no surface anywhere else. That is what let the whole readout fit
in 16 rows at its worst case rather than needing a second screen.

**Hits-to-kill states its assumption in the row itself, not in prose beside the
card.** The count comes from the same `calculateBasicDamage()` the aiming
forecast uses with the same `is_simulation` flag, and the value carries the
elevation modifier it was computed under in the forecast's own `%d%% elevation`
vocabulary — elevation being precisely the term that changes when either unit
moves. The dim row beneath names the attacker. When the question has no answer
(nothing acting, the hovered unit *is* the actor, or it is that actor's ally)
the row says which rather than showing a bare dash. The forecast is gathered in
`BattlePresentationController`, not in `DeepCard`: nothing under
`src/presentation/` reaches into `src/systems/` or into a resolver, and this
item was not the place to start.

**The width is measured output, and measuring caught a real over-run.** The
first wording, `basic attack from <Name>, here`, needed 380 units against the
340 the card had been given — the same class of defect §8 already records for
`PROMPT_WIDTH` and `FORECAST_WIDTH`. Moving the attacker into the value column
where every other value on the card sits brought the worst case to 308, and
`DEEP_CARD_WIDTH_UNITS` is 310. `debug/measure_deep_card.gd` (gitignored)
builds the card's real rows for every monster in the shipping catalog, reports
the widest, prints one rendered card for review, and checks the vertical fit:
the card spans 63..244 design units, the prompt ends at 59, and the docked
status windows begin at 286. Because a design-unit screen is ~360 tall at every
`ui_scale`, that one check covers all four scales.

Live cooldowns are driven off `_refreshStatusWindows()` rather than `_process`:
a cooldown only moves when a cast resolves, and a cast already pushes a readout
refresh, so the card stays current without the per-frame row rebuild LEG-2
specifically guarded the docked windows against.

**The wheel pages the card while it is open.** It has no cursor, so §7a's "walk
past the last row" rule cannot apply, and its footer arrows are a click the
player would have to take their hand off the board to make. Claimed only while
the card is open, so camera zoom is untouched otherwise. Only the deepest unit
in the shipping catalog (16 rows against a capacity of 12) pages at all.

**Found while reviewing a rendered card, and deliberately not fixed here:** a
spell blocked by anything other than a cooldown still reads `CD 0`, because
`spell_value()` has only a boolean to work from while `can_cast()` refuses for
three different reasons. `Roses at Summers End` reads `CD 0` all battle. That is
pre-existing behaviour of the spell window, which this item is required to match
rather than diverge from, so it is recorded in `BACKLOG_CRITICAL.md` instead.

Probe: `--check-only` reports no parse errors on any of the seven changed
scripts, and the measurement script loads `DeepCard`, `NoggWindow`,
`PlayerCommandMenu` and `PlayerTurnController` and runs clean. A headless
editor import registered `DeepCard` in the script class cache and generated its
`.gd.uid`, since a newly added `class_name` is absent from that cache until the
project is rescanned — the same trap LEG-3, LEG-4 and LEG-7 each hit. It emitted
only the documented editor-quit progress-dialog shutdown noise. None of this is
acceptance evidence.

### LEG-10 — Consolidated legibility and regression validation

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-2, LEG-3, LEG-6, LEG-7, LEG-8, LEG-9. LEG-1, LEG-4 and
LEG-5 are withdrawn and contribute nothing to validate.

This is the only item that launches the full manual gameplay pass. Validate the
union of the prior items' coverage in one integrated Player vs CPU battle
wherever they overlap, rather than replaying each item separately:

1. Play a complete 4v4 battle at the default native preset. Confirm hover
   readout and reach in every phase, status silhouettes,
   turn-order rollover including at least one double turn, threat attribution,
   and the deep card.
2. Repeat the decisive portions at the harshest retro preset and under the CRT
   pass, both with and without `ui_through_crt`. The badges and numerals
   are the elements at risk here; confirm each is legible at `480x360`.
3. Exercise `ui_scale` at its shipping value and at 3. Every new surface is
   authored in design units and must scale with the rest of the HUD.
4. Exercise pause, both speed sliders, CPU turns, defeat, battle end and return
   to setup. Confirm no badge, overlay or window outlives its unit or the
   battle.
5. Search every caller of each changed shared surface — the status icon path,
   the tactical overlay path, the threat map — and exercise all of them, not
   only the ones this cycle touched. Confirm CPU decisions are unchanged against
   a fixed seed.
6. Confirm `ConsoleVisualAdapter` still satisfies the adapter interface and the
   headless path runs.
7. Verify the shipped HUD against `docs/UI_DESIGN.md` as amended by LEG-1, run
   `git diff --check`, and inspect the focused diff.

**Risk:** A HUD that reads well in a static frame can still fail in motion,
under the camera, or on a crowded board. Judge the badges while units are moving
and the camera is turning, not from stills.

**Completion:** Record observations and captures. If defects appear, fix them in
this session and rerun the affected consolidated flow. Once acceptance passes,
grep for this cycle's item identifiers outside this file, rewrite any persistent
hits as durable descriptions, move any genuinely open work to the appropriate
backlog and name it to the user, then clear this plan file in the same session
per the plan lifecycle policy.

**Resolution (2026-08-25):** Validation passed. Every covered item is now done.

**The manual pass was replaced by two harnesses, and that substitution is the
main thing to know about this run.** `debug/verify_leg_final.gd` drives the real
`Battle25D` scene through one seeded Player vs CPU battle with synthetic input,
asserting the union of the cycle's behaviour; `debug/capture_leg_final.gd` runs
the same battle windowed and photographs it, because whether a badge reads at a
downsampled preset is a judgement from a frame and not something an assertion
can make. Both are gitignored scratch, matching the existing `debug/verify_*.gd`
pattern. Marker: `LEG FINAL: all checks passed`.

Asserted, in one battle rather than one flow per feature: hover fills the docked
readout and routes ally left / enemy right in MENU, MOVE_SELECT and
TARGET_SELECT; leaving hover restores the *committed* readout rather than a
stale snapshot; hover reach paints and clears without destroying the acting
unit's own overlay; every status effect resolves to a distinct silhouette *and*
a distinct resting chip colour; the rail carries exactly one divider with
round-relative numbering on both sides, its projection matches the canonical
speed sort, and a pending SPD buff reorders that projection without touching the
live queue; the danger zone attributes to a hovered enemy, stays even for a
hovered ally, and clears on release; the deep card opens, matches the catalog,
picks up a cooldown applied while it is open, pages under the wheel, resizes no
docked window, and closes on release; a defeated unit loses its badge row and
its rail tile; the card and its key do not survive the battle ending or the
return to setup; and `ConsoleVisualAdapter` still declares every method
`IBattleVisualAdapter` does.

**CPU decisions are unchanged, proved rather than argued.**
`scripts/demo_battle.gd` on its fixed seed produces a 1556-line transcript
hashing to `518dbc77a4932a2f6fe9d831c2b55572e311445a47d4f836e0ee9a0f293158f0`
both at `db64708^` — the commit before this cycle opened — and at HEAD. The
baseline was run from a `git worktree` at that ref rather than by disturbing the
working tree. This matters because the cycle really did change simulation-layer
files: `ThreatMap`, `TurnManager`, `BattleState`, and a new `ReachQuery`.

**Caller sweep.** Every caller of every changed shared surface was enumerated and
exercised: `spell_value()` (spell window and deep card — a dedicated check
asserts the two format identically), `spellEntriesFor()` (spell window and
card), `ThreatMap.generate`/`accumulateEnemy`/`beginMap`/`threateningEnemies`
(four AI brains plus `CommandDeliberation`, all covered by the byte-identical
transcript) and `threatFor` (the overlay), `speedSortedIDs`/`effectiveSpeed`
(the simulator's own sort via the transcript, the rail via the rail check),
`ReachQuery.forMonster` (both the hover overlay and move select, simultaneously),
`show_threat_options`/`show_hover_reach` (the Godot adapter and the no-op
player-turn stubs), and `set_full_rows` (spell, confirm, and card windows).

**Two defects were found and fixed here.**

The first is the reason this item insists on captures. The deep card rendered
`HITS TO KILL 45` — arithmetically right, since `Envoy of Lightning` at ATK 3
against DEF 3 lands the `max(1, atk - def)` floor — but a bare `45` reads as a
bug rather than as the fact it is. The value now carries the per-hit figure it
was divided from, `45 (1 dmg)`, plus the elevation modifier when there is one.
Re-measured: the widest row is unchanged at 308 units, because the kill row was
never the row setting the width.

The second was in the harness rather than the product, and is recorded because
it made a check silently pass: the spell-window agreement check indexed the
window's page bounds into the entry list, and the window's rows are the spells
*plus a trailing `< Back`*, so the last index threw and aborted the function
before its assertions ran. A green run with a `SCRIPT ERROR` in stderr is not a
green run.

**Multi-scale and preset coverage is by capture, and the finding is that the
render ladder cannot reach these surfaces at all.** 24 frames at `ui_scale` 2
(1152x648) and 3 (1920x1080), each at the default preset, the harshest 480x360
retro rung, and the CRT pass with and without `ui_through_crt`. The card, the
docked windows, the prompt and the rail are native-resolution `CanvasLayer` UI,
so the downsample never touches them; only `ui_through_crt` can, and at the
shipping CRT parameters the text stays legible. What the retro rung does affect
is the board-space work — reach, the attributed danger zone, and the badges —
and those read at 480x360. Frames are in `debug/leg_shots/`.

**Known limits of this run, stated rather than glossed.** Headless letterboxes
the battle viewport to roughly 64x48, which puts the docked windows off-screen
and leaves only a handful of tiles with a clickable screen point; the verifier
therefore places the units it needs onto tiles that resolve, and re-derives every
screen point after each phase change because the camera director pans and a
point captured before a pan means a different tile after it. Vertical fit against
the docked windows is asserted against a design-unit screen in
`_check_ui_scale_geometry` and in `debug/measure_deep_card.gd`, not against those
off-screen positions. The verifier still exits with the pre-existing
`Battle25D` teardown access violation recorded in `BACKLOG_CRITICAL.md`, which
is why the printed marker and not the exit code is the evidence. And judging the
HUD *in motion* — badges while units move and the camera turns — remains
genuinely outside what a still frame or an assertion can establish.

## Deliberately excluded

- **Balance.** The five-to-twenty hits per kill the current catalog produces is
  a tuning question, not a presentation one. This cycle makes that pace more
  visible rather than changing it; whether it is intended is the user's call and
  belongs in its own cycle.
- **Monster level and growth.** The level readout is built here; making level
  vary remains the separate `BACKLOG_CRITICAL.md` item.
- **The `Battle25D` shutdown access violation.** Pre-existing and tracked
  separately. LEG-4 must not make it worse, but fixing it is not in scope.
- **The forecast's silence on buff and debuff spells.** Tracked separately in
  `BACKLOG_CRITICAL.md`. LEG-5 must not render a misleading zero for those
  spells, but authoring their forecast text is that item's work.
- **Camera-relative cursor movement** and the broader accessibility work already
  recorded under the player command UI backlog entry.
- **Any change to simulation, resolvers, or command validation.** Every item
  here reads existing queries. The single exception is LEG-8's widening of the
  threat map's return shape, which must leave its resolved values identical.
