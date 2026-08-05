# Long-term backlog

## Fixed HUD panels occlude board tiles

Found 2026-07-30 while building the headless input driver; the serious
half was **fixed on 2026-08-01** after a player report that clicking some
models did not light their selection aura.

Godot's GUI layer resolves a click against any visible `Control` whose
`mouse_filter` is not `IGNORE` *before* `_unhandled_input()` runs, so a HUD
panel over the board does not merely cover it — it makes it unclickable. A
`Control` defaults to `MOUSE_FILTER_STOP`, so this is the behaviour a readout
gets for free without anyone choosing it.

The original note guessed this was only a small-window problem and
"unremarkable at a normal desktop resolution". That was wrong. At the project's
own default 1152x648, `ActorWindow` (20, 428, 540x200) and `TargetWindow`
(592, 428, 540x200) together covered the bottom third of the viewport,
including the near edge of the board where team 1 deploys. Measured on a fresh
CPU vs CPU battle: two of the eight starting monsters had **zero** clickable
screen points, and every point that resolved to their tile was under a status
window.

Both windows are pure readouts, so `NoggWindow.set_input_transparent(true)`
now marks them and `BattleUIBuilder` applies it. All eight monsters are
clickable at every resolvable point afterwards. `PlayerCommandMenu` keeps the
default filter — its rows *are* the input surface.

**Still open, and genuinely minor:** the dev bar across the top is an
`HBoxContainer` at `MOUSE_FILTER_PASS`, so only its actual buttons consume
clicks, and it is hidden by F1 anyway. Whether the thin strip under those
buttons is worth reclaiming is a product call nobody needs to make yet.

**The general rule worth remembering:** any new `Control` laid over the 3D
board must be `MOUSE_FILTER_IGNORE` unless it is meant to be clicked. Testing
this by eye does not work — the panel looks correct and the board underneath
looks reachable; only a click proves otherwise.

## Baseline frame cost outside deliberation

Found 2026-08-01 while gating the frame-pacing check that validated
frame-budgeted deliberation. With CPU deliberation
fully off the frame, roughly 3-4% of frames at 8 turns/sec still exceed the
16.7 ms 60fps budget, and *idle* frames — ones carrying no turn start and no
deliberation — reach ~21 ms on their own. So the residue is ordinary scene
cost: the visual queue, tweens, physics, and per-frame presentation work.

Nothing here is a hitch: no frame in a 900-frame run reaches the 33.3 ms 30fps
floor, which is why that check gates on the 30fps floor and reports the 60fps
figure without asserting on it. But it is the next thing standing between the game and a solid
60fps, and it is unrelated to AI, so it will not improve as deliberation gets
smarter.

Measured headless, which has no rendering at all — a real window adds its own
cost on top, so treat these as a floor rather than an estimate. Anyone picking
this up should start by re-measuring in a window with
`debug/verify_frame_pacing.gd` and attributing the idle-frame cost before
changing anything.

## Weather system


## Rename legacy debug harness filenames

Several ignored `debug/verify_*.gd` and driver filenames still encode obsolete
planning labels. Their comments and result labels now describe behaviour, but
renaming the files would churn local commands and any external invocations.
When a maintainer elects to do that path cleanup, rename each harness after the
behaviour it verifies and update every caller in the same change.

- Design a competitive catalog of 5-10 weather states. Eligible monsters
  establish them according to their element and/or race; each weather needs a
  clear duration, owner, replacement rule, and visible battle-state
  representation.
- Give weather specialists meaningful control over timing: weather spells can
  establish, clear, overwrite, or make a limited compatible transformation of
  the active weather. Use shared tags and rules rather than isolated buffs.
- Keep individual effects tactical and globally legible: movement, visibility,
  healing, status duration, terrain interaction, and elemental interaction are
  preferable to universal raw-damage multipliers. Serialize active weather and
  validate its source through the reference catalog.

## Element catalog visual palette

Element abbreviations now come from `elements.json`, but
`BattleMeshFactory.elementColor()` still owns the visual palette. A newly
authored element can therefore display its catalog code while its model, aura,
and future Resonance bar fall back to grey. Move the colour into the element
catalog only as a deliberate 3D/presentation migration, with every current
material consumer updated in the same change.

## In-world Resonance and critical-hit feedback

The docked status windows are the selected-monster home for Resonance charge,
but the board still has no transient feedback when charge changes during an
animation, and critical or weakness hits look like ordinary hits. If play shows
that selection-only visibility is insufficient, extend the existing
`StatusEffectBillboard` badge row with the highest charged element and its 0-3
charge, then give critical/weakness events a distinct presentation cue. Keep
this presentation-only; the simulation and event data already exist.

## Battle UI knobs deferred from the battle UI restyle

Recorded 2026-07-30 alongside `docs/UI_DESIGN.md` section 11. None of these
block the restyle; revisit after the first playable pass.

- **Thin rim and halo at high resolution.** The shared smooth rim and exterior
  halo scale from the 1152 x 648 logical base. Keep this open until the
  consolidated in-window pass judges their weight and softness at maximized and
  awkward fractional sizes. Tune only centralized `NoggTheme` tokens; do not
  add a resolution-specific frame asset or a local panel style.`n`n- **Row capacity.** The 8-row window capacity is a guess. If spell lists
  routinely run 9-12 entries, a taller spell window may beat paging for that
  window specifically; measure against real rosters rather than adjusting by
  feel.
- **Window open/close audio.** Dragon Quest window feel is substantially
  audio. No audio system exists yet; noted here so the `open()`/`close()`
  hooks in `NoggWindow` are not designed away before there is something to
  play.

## `Think` / `Thought` look like placeholder spells shipped on a real monster

Found while implementing self-cast presentation fixes. `data/spells.json`
carries two spells named `Think` and `Thought` — zero damage, `ELEMENT: "none"`,
no `TARGET_TYPE` (so it defaults to `"single"`) — and `Mage Dragon` in
`data/monsters.json` has one as the first entry in each of its two spell sets.
Both have `RANGE: 0`, so despite not being `targetType: "self"` they can only
ever legally target the caster's own tile — the same reachable set as a self
spell, without being tagged as one. The names read like debug fixtures (compare
`Spell.gd`'s own placeholder default, `var name: String = "Dump"`, which is
also a cataloged spell nothing references as a kit entry the same way). Confirm
with the content owner whether `Mage Dragon`'s kit is missing its intended
first spells, or whether `Think`/`Thought` are meant to do something and are
simply unfinished.

## Turn rewind is an open design decision, not scheduled work

Surveyed alongside the battle-UI legibility pass and deliberately left
unbuilt. Fire Emblem's Mila's Turnwheel / Divine Pulse give the player a
charge-limited rewind of whole turns, and the genre's own stated reason is
that new players will make mistakes and letting them experiment without
permanent loss is what keeps them playing. Movement `Undo` already covers the
common case here — a misjudged destination, undoable until an action is spent.
Anything beyond that changes what a mistake *costs*, which is a difficulty
decision rather than a legibility one, and it should be made deliberately
rather than arrived at by adding one more convenience. `BattleStateSerializer`
and `BattleReplayRunner` already snapshot enough state that the mechanism
would be cheap to build, which is exactly why it is worth deciding on purpose.

## Visual playback can no longer keep up with an unpaced simulation

Found while validating the animation-hold work. A player turn only opens once
the visual queue is completely empty
(`BattlePresentationController._presentation_ready_for_player_turn()`), and
actions now occupy the queue substantially longer than they used to, because
each one is held until its spawned effects are mostly through rather than
until its own tween ends. In the real game this self-regulates: `turn_timer`
paces CPU turns and stops entirely once a player turn is pending. But any
caller that drives `_advance_battle()` in a loop without that pacing enqueues
faster than playback drains, and the pending player turn never gets its
opening. Every headless harness under `debug/` that drives battles had to be
taught the same two rules — stop advancing while a turn is pending, and yield
a frame per tick. Worth revisiting if the run-ahead limit or the hold fraction
is ever tuned, and worth remembering before writing a new driver.

## Area VFX particle fields still ignore non-diamond footprint shapes

Ground washes now carry every area shape correctly: `VfxTextures.groundWash()`
masks to a Manhattan diamond, a plus/cross, or a neutral disc, chosen by
`groundWashShapeFor()` from the spell's `AREA_SHAPE`. **The particle layers do
not.** For a `cross` carrier the ice storm's flurry still fills an
axis-aligned square, and the fire storm's vortex falls back to the circle
inscribed in the footprint's bounding diamond. The vortex under-claims (safe,
just conservative); the flurry over-claims, painting snow across the four
quadrants a cross-shaped spell never touches.

`Smoke Tower` is a live `cross` carrier today, so this is now observable in
play rather than hypothetical — though it is the fire vortex, the
under-claiming case, that carries it. A `cross`-shaped ice or wind area spell
would expose the over-claiming one.

Fixing it means giving the particle shaders a shape parameter rather than
today's diamond-or-not boolean, and deriving a per-shape spawn region:
tractable for `cross` (sample the two bars), genuinely awkward for `line`,
whose footprint depends on the cast direction that presentation never
receives. `line` also has no ground-wash mask for the same reason and falls
back to the disc.

Separately: `IceStormEffect._configureSeed()`'s hero-shard spawn positions
(`start`) are still sampled uniformly across the full square bounding box, not
masked to the diamond. Left alone deliberately — shards are sparse (8 per
storm), already fade in from height rather than reading as ground coverage,
and the dominant claim about the footprint's shape comes from the ground wash
and the dense flurry field. Worth revisiting only if a shard is ever seen
landing visibly outside the footprint in play.

## Generic spell-cast aura throws on dispose during app quit

Found 2026-08-04 while smoke-checking `VFXDebugScene` after an unrelated fix.
Quitting the process (or the debug scene's `_exit_tree()` disposing its active
playback) while a `SpellCastAura` instance is the live playback prints
`ERROR: Object is locked and can't be freed.` /
`SCRIPT ERROR: Attempted to free a locked object (calling or emitting).` at
`SpellCastAura.dispose` (`src/presentation/effects/SpellCastAura.gd:117`).
Reproduces the same way against the pre-existing committed code, so it is not
a regression from any recent change — likely a tween or particle system still
mid-signal-emission when `dispose()` calls `queue_free`/`free` on it. Does not
reproduce with `IceStormEffect` as the active playback. Only observed at
process/scene teardown, never during normal play, so it has not visibly broken
anything — worth a proper fix (defer the free with `call_deferred`, or wait for
the lock to clear) next time `SpellCastAura.gd` is touched.

## Defeat animation's child-index assumptions are still fragile

`GodotVisualAdapter._start_defeat_animation()` reaches into the monster
container by index: child 0 for the base, child 1 for the body. Child 0 stopped
being a mesh when the base became a stacked `Node3D` for ascension tiers, and
the resulting `as MeshInstance3D` cast silently produced null — the whole
defeat animation threw the first time one actually played, and went unnoticed
because no harness reached a defeat until now. Fixed, but the underlying
pattern remains: the container's layout is an unwritten contract between
`_spawn_monster_visual()` and everything that later picks it apart by index.
Named children, or a small typed accessor, would make the next layout change
fail loudly instead of silently.
