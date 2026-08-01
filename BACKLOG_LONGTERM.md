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
clicks, and it is hidden by SPACEBAR anyway. Whether the thin strip under those
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

- **Frame scale at high resolution.** Global canvas scaling now grows the
  `MenuFull.png` 9-patch border from the 1152 × 648 logical base instead of
  leaving it at a fixed 16 physical pixels. Keep this open until the
  consolidated in-window pass judges the border and pixel font at maximized and
  awkward fractional sizes. If either still reads too thin or blurred, compare
  a pre-scaled 96 × 96 asset with integer stretch scaling before changing the
  frame node independently.
- **Row capacity.** The 8-row window capacity is a guess. If spell lists
  routinely run 9-12 entries, a taller spell window may beat paging for that
  window specifically; measure against real rosters rather than adjusting by
  feel.
- **Window open/close audio.** Dragon Quest window feel is substantially
  audio. No audio system exists yet; noted here so the `open()`/`close()`
  hooks in `NoggWindow` are not designed away before there is something to
  play.
