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

## Complete spell-radius scalability beyond Ice Storm

The cast event now transports the ordered resolved target IDs plus the radius
and shape resolved from the live `Spell`, and Ice Storm scales its geometry and
bounded populations through radius 8. Target IDs support target-bound effects;
they do not replace the exact affected-tile data still needed to clip area
footprints at board edges. The rest of the feature is deliberately deferred:

- define modifier ownership and stacking for buffs/debuffs instead of mutating
  `Spell.radius` ad hoc, including whether `radius` and `self_radius` can change
  independently;
- serialize resolved spell modifiers in battle snapshots/replay continuation;
  `Monster.serialize()` currently records spell names, not runtime spell fields;
- make the generic `SpellCastAura` implement `setFootprint()` rather than stay
  fixed-size, then validate Fire Storm and Magenta Reduction at base, +2, and a
  declared maximum radius with stable density and effect budgets;
- carry exact clipped affected positions—or equivalent board-edge data—when a
  cast near a map edge should not depict the theoretical off-board half of its
  footprint; carry cast direction before claiming exact `line` VFX coverage.

Keep the transport general. Do not add spell-name branches to the adapter while
closing these gaps.

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

## Extract a shared `SpellVfxProfile` resource — deferred at the third effect

`docs/VFX_DESIGN.md` §4 names **the third elemental effect** as the trigger to
stop forking and extract a `SpellVfxProfile` resource, after which a new element
would be a `.tres` rather than a forked file. `MagentaReductionEffect` was that
third effect, built 2026-08-08, and the extraction was **deliberately declined**
at that point with the user's agreement.

The reason is that the trigger counted files, not shapes. The shared structure
proven by the first two is the structure of a *storm*: a ground wash, a particle
field that pushes outward and upward, a canopy or crown above it, and one
continuous motion from onset to settle. Magenta Reduction is not one. It pulls
inward, it has a four-beat timeline with a charge beat that holds before
anything is released, and it carries a core and a discharge layer that neither
storm has and drops the crown that both do. A resource abstracted from three
files where the third only barely fits would have been abstracted from the wrong
thing, and every later effect would have inherited that shape.

**Restated trigger: the next effect that is structurally a storm.** At that
point there are three genuine instances of one shape — outward particle field,
crown, wash, single-arc timeline — and the abstraction has something real to be
drawn from. `IceStormProfile` and `FireStormProfile` are the two to generalize
over; `MagentaReductionProfile` should be checked against the result rather than
allowed to define it, and it is an acceptable outcome for the implosion to stay
a forked file.

Worth knowing before starting: `IceStormProfile` carries `MEASURED` constants
from reference-footage decomposition, and §4 is explicit that those labels mean
something. Any migration has to carry the provenance labels across, not flatten
them into an untyped resource.

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

## Nogg Terminal is adopted; two follow-ups remain

**Adopted 2026-08-10** as the battle UI face, together with the warm `WINDOW_FILL`
the face's drop shadow needs to read against. All three constraints this entry
previously tracked are resolved: widths were re-measured against the wider face
(`PROMPT_WIDTH`, `FORECAST_WIDTH` and `TURN_ORDER_WIDTH` grew), `FONT_SIZE_FOOTER`
moved from 20 to 24 so every game size is a whole multiple of 12, and the
cache-clear failure mode was removed outright by the display cycle's move to
`window/stretch/mode = "disabled"` — oversampling can no longer change at
runtime, so the glyphs cannot be cleared.

Two things are genuinely still open:

- **`FONT_SIZE_FOOTER` no longer distinguishes the pager footer from body text.**
  20 was not a whole multiple of 12 and would have rendered at 12 inside a
  window sized for 20, so it became 24 — the same size as the body. The
  distinction has to come from colour or spacing instead. Nothing in the
  shipping catalog pages today, so no live screen currently shows a footer at
  all; this needs deciding before one does.
- **The halo is now unused by default.** `OUTLINE_SIZE` still selects a baked
  outline variant and the atlas still carries widths 1 and 2, but game text
  ships with `outline_size = 0` and the drop shadow instead. If board-space
  text is ever themed (rather than drawing its own halo the way
  `DamageNumberBillboard` does), it will want the halo rather than the shadow,
  since a shadow only defends one side.

## Finish exposing effect tunables in the VFX authoring panel

The debug scene's descriptor-driven tuning panel and CLI overrides are complete,
and `SpellCastAura` exposes its full parameter roster. Four older effects still
use the safe empty-roster fallback: `IceStormEffect`, `FireStormEffect`,
`MagentaReductionEffect`, and `IceTargetEncasementEffect`.

Review each effect separately and expose only parameters whose update path is
actually wired. Their constants are spread across build-time and per-frame code,
so copying a roster mechanically can create controls that appear to work but do
nothing. Validate rebuild-class parameters at a pinned seed and normalized time,
then run the existing VFX golden comparison to prove defaults did not change.
