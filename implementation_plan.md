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

- every living unit carries a persistent readout of team, level, health, active
  resonance and status, drawn at native resolution so it survives every retro
  preset down to `480x360`;
- hovering any unit fills the docked status window and paints that unit's
  movement and strike reach, in every phase including move and target select;
- a pending action's damage is previewed on the target's own health bar, so the
  forecast is read where the player is already looking;
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

- **Every monster is level 1 today.** Nothing in production spawns above it and
  every authored growth value is `0`, so the level readout specified in LEG-4
  will show `1` on every unit until the monster level and growth work in
  `BACKLOG_CRITICAL.md` lands. That is expected. The readout is being built
  ahead of the mechanic deliberately, at the user's direction; do not remove it,
  and do not substitute a different value.
- **Catalog damage is small.** Shipped stats are base stats: HP `28-60`, ATK
  `2-8`, DEF `2-8`, spell `DAMAGE` `1-7`. Against
  `max(1, atk + power - def)` most exchanges land at `2-8` damage, so a unit
  takes roughly five to twenty hits to remove. This is why the health bar is
  notched rather than smoothly filled — a continuous bar moves too little per
  exchange to register. Whether that pace is intended is a balance question
  outside this cycle; see "Deliberately excluded".
- **The colour vocabulary is nearly full.** Movement blue, reach purple, target
  yellow, affected red/green and threat magenta are all assigned. Yellow in
  particular is taken twice, by the hovered path in `show_movement_options` and
  by legal targets in `show_target_options`. New surfaces derive from the
  existing set rather than adding to it.

## Items

### LEG-1 — Settle the board-space readout contract in the UI design document

**Model:** Opus 5 / GPT Sol

**Depends on:** nothing.

**Blocking:** yes. `docs/POLICIES.md` requires user approval before inventing a
visual theme, and this item authors one. Obtain approval of the plate layout and
its colour tokens before any of LEG-4 onward is executed. The remaining items
are unblocked once this item's contract is approved.

**End state:** `docs/UI_DESIGN.md` describes the board-space unit plate as a
named surface alongside the §10a model treatments, with its anchor, composition,
sizing in design units, colour tokens, and the rule that it is drawn as a
projected `Control` at native resolution rather than in the battle
`SubViewport`. The §6 input table gains a hover row. `NoggTheme` gains the
tokens the plate needs and no colour literal is introduced outside it.

**Implementation:** Add a §10c covering the plate. Specify, left to right: a
**team-coloured unfilled circle carrying the unit's level number**, then the
notched health bar, then resonance pips; the status row sits beneath. Author the
circle as a stroked ring with a transparent interior, its stroke taking the team
colour and the numeral taking `TEXT_PRIMARY` — the ring reads as team identity
and the numeral as level, and neither has to fight a fill for contrast. Size
every element in design units multiplied by `ui_scale`, per §3's token rule; do
not write device-pixel literals at a call site. Set the health notch interval at
10 HP against the catalog range above, so a typical unit shows three to six
segments. Derive the health, ghost-damage and lethal tokens from the existing
palette. Record in the §6 table that hover moves the cursor *and* fills the
docked readout, and that it does so in every phase. State explicitly that the
plate never resizes with content, matching trait 6's reasoning for the docked
windows.

**Risk:** A contract authored without rendering it can specify a plate that is
unreadable at `480x360` or that collides with the status badges already anchored
above each model. Measure the specified sizes against the smallest preset before
recording them, and state where the plate sits relative to the existing badge
row.

**Adds to final validation:** The document is the acceptance reference for every
later item; validation checks the shipped HUD against it rather than against
this plan.

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

### LEG-4 — Build the unit plate

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-1.

**End state:** Every living unit carries a plate matching the LEG-1 contract:
team-coloured level ring, notched health bar, resonance pips. It is drawn as a
projected `Control` on a dedicated `CanvasLayer` at native resolution, tracks
its unit through movement tweens and camera motion, disappears on defeat, and
survives every render preset. The whole plate desaturates once its unit has
spent its turn.

**Implementation:** Follow the projection path `_spawn_damage_number` already
establishes in `src/presentation/GodotVisualAdapter.gd`:
`camera.unproject_position()`, then `retro_renderer.world_to_screen()`, with
`get_display_rect()` as the cull test and `is_position_behind()` as the reject.
That path is the reason this is not a `Label3D` or a world-space quad — the
battle viewport can be `480x360`, and anything drawn inside it is downsampled
while a projected Control is not.

Anchor from `get_monster_world_position`, which already prefers the live visual
over the authoritative tile position and is therefore correct mid-tween. Update
per frame while any unit is moving or the camera is in motion; a one-shot read
will desync. Extend the existing `dim_amount` convention to the spent state
rather than inventing a second visual language for the same idea.

Give the plate a declutter rule from the start: an isometric camera puts two
units at nearly the same projected point regularly, and a plate that overlaps
another is worse than no plate. Depth-sort and nudge, or fade the rear plate —
decide it here rather than discovering it on a crowded board.

**Risk:** This is the largest item in the cycle and adds a presentation surface
that does not exist today. Per-frame projection for eight units plus a
re-layout is the main performance exposure. Node lifecycle is the main
correctness exposure: a plate that outlives its unit, or leaks on battle exit,
feeds directly into the `Battle25D` shutdown access violation already in
`BACKLOG_CRITICAL.md`. Adapter symmetry is the third: `ConsoleVisualAdapter`
implements the same interface as `GodotVisualAdapter` and must stay in sync if
the interface grows.

**Adds to final validation:** Plate presence and accuracy for every living unit;
tracking through movement, defeat, camera yaw and pitch; every render preset
including the smallest; overlapping-unit declutter; spent-state desaturation;
teardown with no leaked nodes; headless adapter parity.

### LEG-5 — Preview pending damage on the target's health bar

**Model:** Sonnet 5 / GPT Terra

**Depends on:** LEG-4.

**End state:** While aiming or confirming, the portion of the target's health
the pending action would remove is drawn as a distinct ghost segment on its
plate, and an action that would defeat the target tints the whole bar. Ticking
burn and poison damage is drawn as a separate hatched segment. Cancelling
restores the bar.

**Implementation:** The numbers already exist. `PlayerTurnController` computes a
forecast from the same `CombatResolver` math real resolution uses, and renders
it as text into the forecast window; this item routes that same result to the
plate rather than recomputing it. Do not add a second damage calculation — a
forecast that disagrees with the bar is worse than either alone. Read status
tick damage from the active effects already available to the status icon path.

**Risk:** The forecast covers a whole affected set for area spells, so the plate
must show each affected unit's own share rather than the total. Buff, debuff and
pure-status spells produce no damage line at all — the forecast's existing blind
spot for those is recorded separately in `BACKLOG_CRITICAL.md`, and this item
must render nothing rather than zero for them.

**Adds to final validation:** Single-target and area forecasts against the
resolved damage; lethal tint accuracy; heals; buffs and status-only spells;
cancel restoration; multi-target area casts.

### LEG-6 — Give each status effect a distinct silhouette at native resolution

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-1.

**End state:** Each of the eleven catalog effects is distinguishable by shape
alone, without relying on colour. The badges are drawn at native resolution
alongside the plate rather than as world-space sprites, so they survive every
preset. Duration remains legible.

**Implementation:** `src/presentation/StatusEffectIcons.gd` currently maps
`burn`, `poison`, `petrify` and `chill` to one down-arrow, and uses the shield
shape for `guard`, `def_buff` and `def_debuff` alike — four effects with
entirely different consequences render identically, and colour separates only
buff from debuff. Author distinct silhouettes for the five negative effects and
keep the buff/debuff colour split as a redundant channel, not the primary one.
Verify each shape is readable at the size the LEG-1 contract specifies before
adopting it.

Move the badges onto the plate's canvas. Today they are 16x16 textures at
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

Match the portrait camera to the board camera's orthogonal angle. A portrait
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

### LEG-10 — Consolidated legibility and regression validation

**Model:** Opus 5 / GPT Sol

**Depends on:** LEG-1 through LEG-9.

This is the only item that launches the full manual gameplay pass. Validate the
union of the prior items' coverage in one integrated Player vs CPU battle
wherever they overlap, rather than replaying each item separately:

1. Play a complete 4v4 battle at the default native preset. Confirm plate
   accuracy for every unit across the whole battle, hover readout and reach in
   every phase, damage preview against resolved damage, status silhouettes,
   turn-order rollover including at least one double turn, threat attribution,
   and the deep card.
2. Repeat the decisive portions at the harshest retro preset and under the CRT
   pass, both with and without `ui_through_crt`. The plate, badges and numerals
   are the elements at risk here; confirm each is legible at `480x360`.
3. Exercise `ui_scale` at its shipping value and at 3. Every new surface is
   authored in design units and must scale with the rest of the HUD.
4. Exercise pause, both speed sliders, CPU turns, defeat, battle end and return
   to setup. Confirm no plate, overlay or window outlives its unit or the
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
under the camera, or on a crowded board. Judge the plate while units are moving
and the camera is turning, not from stills.

**Completion:** Record observations and captures. If defects appear, fix them in
this session and rerun the affected consolidated flow. Once acceptance passes,
grep for this cycle's item identifiers outside this file, rewrite any persistent
hits as durable descriptions, move any genuinely open work to the appropriate
backlog and name it to the user, then clear this plan file in the same session
per the plan lifecycle policy.

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
