# Long-term backlog

## Fixed HUD panels occlude board tiles

Found 2026-07-30 while building `TD-1`'s headless input driver; the serious
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

## Battle UI knobs deferred from UI-1..UI-8

Recorded 2026-07-30 alongside `docs/UI_DESIGN.md` section 11. None of these
block the restyle; revisit after the first playable pass.

- **Frame scale at high resolution.** The `MenuFull.png` 9-patch border is 16
  physical px and reads thin above 1440p. Options are a pre-scaled 96x96 asset
  or an integer `Control` scale on the frame node. Do not decide before the
  new layout has been seen on screen at target resolution.
- **Row capacity.** The 8-row window capacity is a guess. If spell lists
  routinely run 9-12 entries, a taller spell window may beat paging for that
  window specifically; measure against real rosters rather than adjusting by
  feel.
- **Window open/close audio.** Dragon Quest window feel is substantially
  audio. No audio system exists yet; noted here so the `open()`/`close()`
  hooks in `NoggWindow` are not designed away before there is something to
  play.
