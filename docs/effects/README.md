# Effects

One page per effect profile. What a given effect *does* — its layers, its
constants, its timeline, the measurements behind its numbers, and the questions
it left open — belongs here.

[`../VFX_DESIGN.md`](../VFX_DESIGN.md) is the other half: the contract every
effect implements, the conventions they are all authored under, the debug
harness, and the rules that outlived the effect that taught them. **The split is
"true of this one" versus "true of all of them."** A rule discovered while
building one effect starts on that effect's page as a finding; it moves to
`VFX_DESIGN.md` once a second effect needs it, and the page keeps the worked
example.

Split out of `VFX_DESIGN.md` on 2026-08-29, when per-effect narrative had grown
to 35% of a document that calls itself conventions and authoring workflow.

## Pages

| Page | Profile | Status |
| --- | --- | --- |
| [Generic spell-cast aura](./spell-cast-aura.md) | `spell_cast_aura` | The default carrier a spell falls back to when it names no other profile |
| [Technique charge aura v1](./technique-charge-aura-v1.md) | `technique_charge_aura_v1` | Debug-only. Rises, bounces, settles into a quiet idle |
| [Technique charge aura v2](./technique-charge-aura-v2.md) | `technique_charge_aura_v2` | Debug-only. Forked from v1: spins, churns, disperses outward |

Effects with no page yet — Ice Storm, Fire Storm, Magenta Reduction, Ice Target
Encasement, Aurora Veil, Solar Storm — are documented only by their code and
commit history. Several are described generically in `VFX_DESIGN.md` (the
target-bound volumetric shells section covers the encasement's shape, for
instance). Give one a page when it next changes, rather than backfilling them
all at once.

## Writing one

- **Name the file after the profile id**, hyphenated: `technique_charge_aura_v2`
  becomes `technique-charge-aura-v2.md`. A reader who has the id from a catalog
  row or a `--effect=` flag should be able to guess the filename.
- **Open with the profile id and a one-line statement of what it is**, then link
  back to `VFX_DESIGN.md` and to any sibling version.
- **Prefer measured claims to descriptions.** "The mask carries alpha ~253 in
  its edge columns, so panels butt together with no margin" is worth writing
  down; "the mask has hard edges" is not. Numbers a future reader can re-derive
  or check are the point.
- **Record what was rejected and why**, not just what shipped. The reason a
  constant is 0.26 is usually that something at 0.45 was tried and failed.
- **Keep open questions visible** under their own heading rather than as a TODO
  buried mid-paragraph, and mark them resolved in place when a later version
  answers them.
