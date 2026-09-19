# Battle damage number arc

2026-09-19. Replace the damage number's stationary pump-and-fade with the
ballistic arc and flash-out idiom measured from a reference capture. Opening
this cycle writes only this file; it does not execute the implementation items.

## Outcome

A hit number is thrown upward from the struck unit, decelerates under a
constant downward acceleration, crests, and begins to fall; at the crest it
loses its outline, flashes to a pale tint and fades out over a short tail. The
number reads as struck out of the unit rather than stamped over it. Total
lifetime, and therefore the action queue's hold, is unchanged within 0.02 s.

Our palette, font and outline rule are kept. Only the motion and the exit
treatment are adopted. No new art, no new font, no change to `NoggTheme`.

## Evidence

Measured from frames of a public gameplay capture, extracted to
`C:\Users\Henri\Documents\video-frames\creseki-2101073389620511155\`. 374
frames survive (the first 6.3 s at 58.94 fps). The measurement is one attack
that lands two hits, tracked by background-subtraction against a temporal
median, with the camera verified static across the window.

The reference renders at roughly 164 native pixels of screen height; its digit
glyph is 8.4 native pixels tall. Figures below are given in **glyph heights
(G)** so they transfer to our `FONT_SIZE_BODY` regardless of `ui_scale`.

| Property | Measured | In glyph heights |
|---|---|---|
| Spawn | full size, 1 frame after the impact flash; no scale-in | - |
| Initial vertical speed | 3.2 native px/frame (194 px/s at 60 fps) | 23.1 G/s |
| Downward acceleration | 0.129 native px/frame^2 (465 px/s^2) | 55.4 G/s^2 |
| Crest | 25 frames (0.42 s) after spawn, 40 native px up | 4.76 G |
| Lateral drift | 0.59 native px/frame, constant, no easing | 4.2 G/s |
| Outlined phase | 27 frames | 0.46 s |
| Flash and fade | 7 frames | 0.12 s |
| Total life | 34 frames | 0.58 s |
| Gap between the two hits | 20 frames | 0.34 s |

The vertical curve fits `h(t) = v0*t - 0.5*g*t*t` to within 1 native pixel at
every sampled frame; it is a plain parabola, not an eased tween. The lateral
term is linear with no ease at either end. The exit is not an alpha fade of the
drawn form: the outline disappears entirely and the fill becomes *brighter*
than the background before fading, which a correlation against the opaque
glyph reports as negative alpha.

### What this evidence does not cover

Do not let an item silently assume any of these. Each is a judgement call for
the implementer, to be made on our own terms and recorded in the commit body.

- Every observed number is a single digit. Whether a multi-digit value travels
  as one rigid object or per-digit is unmeasured.
- Lateral drift was leftward in both samples. Whether that is fixed, relative
  to the attacker, or randomised per number cannot be told from two hits that
  share an attacker.
- No critical hit, heal, miss or elemental variant appears in the surviving
  frames. Our `TEXT_HEAL` path has no reference behaviour to match.
- The 0.34 s gap is one sample of one attack's cadence.

## Current state

`src/presentation/effects/DamageNumberBillboard.gd` holds the number at a fixed
projected screen position for its whole life: a per-digit scale pump up
(`PUMP_UP_DURATION`) and down (`PUMP_DOWN_DURATION`) with a `DIGIT_STAGGER`
wave, a `HOLD_DURATION`, then a linear alpha fade (`DISAPPEAR_DURATION`). There
is no translation at all. The five-pass draw (four black cardinal offsets plus
one fill) already matches the reference's 1 px outline and needs no change.

The existing constants sum to 0.56 s against the reference's 0.58 s, so the
queue pacing in `HexBattleCombatFeedback._startNumber` and `_startStrike`
survives this cycle intact.

## Conventions this cycle is bound by

`docs/VFX_DESIGN.md` section 4: author the timeline's parts and let the total
fall out of them; evaluate motion from the effect's own clock in closed form
rather than accumulating it; every figure above becomes a named constant. The
parabola and the linear drift are already closed-form - write them as `f(t)`,
never as a position advanced by `delta`.

## Items

### DN-1 - Ballistic travel and flash-out

**Route: Sonnet 5 / GPT Terra.** The constants, the curve and the exit
treatment are all fixed by the table above; this is a specification with no
open design question.

**Touches:** `src/presentation/effects/DamageNumberBillboard.gd`

**Wave 1.**

Replace `PUMP_*`, `HOLD_DURATION` and `DISAPPEAR_DURATION` with constants
naming the beats: `RISE_SPEED` (23.1 glyph heights/s), `FALL_ACCELERATION`
(55.4 G/s^2), `DRIFT_SPEED` (4.2 G/s), `OUTLINED_DURATION` (0.46 s) and
`FLASH_DURATION` (0.12 s). Derive `DAMAGE_VISIBLE_DURATION` as
`OUTLINED_DURATION + FLASH_DURATION`, not the other way round.

Convert glyph heights to pixels once, from `NoggTheme.FONT_SIZE_BODY`, so the
arc scales with `ui_scale` exactly as the glyph does.

Offset the billboard each frame from its spawn anchor by
`Vector2(DRIFT_SPEED * t, -RISE_SPEED * t + 0.5 * FALL_ACCELERATION * t * t)`,
evaluated from the effect's clock. Round the result to whole device pixels
before assigning `position`, so the number steps in pixels the way the
reference does rather than sliding through subpixels against a pixel-art scene.

At `OUTLINED_DURATION`, stop drawing the four outline passes and draw the fill
in a pale flash tint, then fade alpha to zero over `FLASH_DURATION`. Keep
travelling through the flash - the reference is past its crest and descending
by then. Derive the flash tint from `NoggTheme.TEXT_PRIMARY`; do not hardcode
the reference's colour.

Drop the scale pump and `DIGIT_STAGGER` entirely. A pump at spawn and a throw
at spawn are the same beat competing for the same moment, and the reference
spends it on the throw. Removing the stagger also removes the only reason the
digits animate independently; leave them rigid, and say so in the commit body
as the multi-digit judgement called above.

### DN-2 - Motion probe

**Route: Sonnet 5 / GPT Terra.** Follows the existing probe convention in
`scripts/hex_battle/`; mechanical once DN-1's constants exist.

**Touches:** `scripts/hex_battle/side_turn/probe_damage_number.gd` (new)

**Wave 2.**

Assert the crest lands at `RISE_SPEED / FALL_ACCELERATION` (0.42 s) at
4.76 glyph heights above spawn, that the outline is gone for every sample after
`OUTLINED_DURATION`, and that alpha reaches zero exactly at the summed total.

Run the three-route seek check `docs/VFX_DESIGN.md` section 3 requires - seek
direct, seek past and back, and play frame by frame then seek - and
byte-compare the rendered result. This is the check that catches an
accumulator, and DN-1's whole motion is a closed form that must survive it.

### DN-3 - Spawn anchor and impact frame

**Route: Sonnet 5 / GPT Terra.** A small, fully specified change at one call
site.

**Touches:** `src/presentation/battle/HexBattleCombatFeedback.gd`

**Wave 2.**

The reference spawns the number one frame *after* the impact flash begins, not
on the same frame. Delay `_spawnNumber` by one frame within `_startStrike` so
the flash reads first and the number answers it.

Re-check `SPAWN_HEIGHT` (0.85) now that the number climbs 4.76 glyph heights on
its own: the reference throws from close to the unit and lets the arc do the
work, so a high spawn anchor plus a full arc will overshoot the unit's head.
Lower it if the number clears the sprite before the eye finds it.

### DN-4 - Multi-hit cadence

**Route: Opus 5 / GPT Sol.** Needs a judgement about whether our visual action
queue models a multi-hit attack at all, and how a per-number stagger would
interact with an action's hold; that shape is not knowable from the file alone.

**Touches:** `src/presentation/battle/HexBattleCombatFeedback.gd`,
`src/presentation/VisualAction.gd`

**Wave 3.**

The reference overlaps two numbers from one attack, 0.34 s apart, each running
its own full 0.58 s arc - so two numbers share the screen for most of their
lives, on the same path, reading as a rhythm rather than a collision.

Decide whether our queue can express that, or whether a multi-hit attack today
collapses into one number. If it can, the gap is a constant on the feedback
layer, not on the billboard. If it cannot, say so and close the item without
inventing a queue feature; the single-hit arc from DN-1 stands on its own.
