# Long-term backlog

## Fixed HUD panels occlude board tiles at small window sizes

Found 2026-07-30 while building `TD-1`'s headless input driver
(`debug/drive_battle.gd`, see `implementation_plan.md`). `BattleUIBuilder`'s
HUD panels (top strip: Play/Pause, Speed, New Battle; bottom-left: unit info)
are positioned with fixed pixel offsets sized for a normal desktop window and
carry Godot's default `MOUSE_FILTER_STOP`. A click or hover landing inside
their rect is consumed by Godot's GUI layer before
`BattlePresentationController._unhandled_input()` ever sees it — confirmed by
temporarily tracing `_unhandled_input()`'s mouse-motion branch and observing
it never fires for an occluded point, then walking the `battle_ui["canvas"]`
Control tree to find the panels whose `get_global_rect()` covered it.

This is real and structural, not a headless artifact: the top and bottom
screen strips are permanently under the HUD at *any* window size, since the
offsets are fixed pixels, not proportional to viewport size. It only became
load-bearing enough to trip a test because headless's default viewport
(~64x64) is a tiny fraction of any real window, so the HUD strips cover most
of the visible board there. At a normal desktop resolution the clear board
area dwarfs the HUD strips and this is unremarkable, ordinary HUD-over-3D-
scene occlusion — a player would rarely need to click precisely under it,
since the camera orbits and pans freely.

**Not acted on, because it's a product call, not a bug fix:** whether this is
worth addressing (excluding HUD rects from tile-picking somehow, warning when
a reachable tile has no clickable area, or simply accepting it as expected HUD
behavior) depends on how small a window the game is meant to support, which
nobody has decided. Revisit if a resizable/small-window use case is ever
prioritized, or if real play at a normal resolution ever turns up an actual
report of a tile being unclickable near the HUD edges.

## Empty-tile spell targeting

- **POS-1 implemented 2026-07-31:** commands, validation, resolution, events,
  and replay v5 now use canonical tile positions. Remaining work is POS-2 AI
  enumeration/scoring and POS-3 forecasts/presentation.
- Every non-self spell exposes tile choices in the player UI. Each spell owns an
  explicit data flag controlling whether confirmation is legal when the chosen
  tile is empty; a false flag disables confirmation but does not hide the tile
  options.
- A legal empty-tile cast that affects zero units still consumes the action,
  cooldown, and Resonance. AI must score that outcome consistently rather than
  receiving a separate execution rule.
- Treat this as an Opus 5 / GPT Sol architectural item. Do not encode a fake
  monster target or implement player-only behavior.

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
