# Effects

One page per effect, with every version of that effect on it. What a given
effect *does* — its layers, its constants, its timeline, the measurements
behind its numbers, and the questions it left open — belongs here.

Versions share a page rather than getting one each, because a new version is
usually an argument with the old one: v2's decisions are answers to
measurements v1 recorded, and splitting them puts the question and its answer
in different files.

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

| Page | Profiles | Status |
| --- | --- | --- |
| [Generic spell-cast aura](./spell-cast-aura.md) | `spell_cast_aura` | The default carrier a spell falls back to when it names no other profile |
| [Solar Storm](./solar-storm.md) | `solar_storm` (+ five ladder rungs) | Carried by the Solar Storm spell. A coronagraph panel: occulter, streams, ejection front, melt |
| [Technique charge aura](./technique-charge-aura.md) | `technique_charge_aura_v1`, `technique_charge_aura_v2` | Debug-only, both versions live. v1 rises and settles; v2 spins, churns and disperses |

Effects with no page yet — Ice Storm, Fire Storm, Magenta Reduction, Ice
Target Encasement, Aurora Veil — are documented only by their code and commit
history. Several are described generically in `VFX_DESIGN.md` (the target-bound
volumetric shells section covers the encasement's shape, for instance). Give one
a page when it next changes, rather than backfilling them all at once.

Aurora Veil is the one most worth doing next: Solar Storm is its fork, and its
page repeatedly explains itself by contrast with a veil that has no page of its
own.

## Writing one

- **Name the file after the effect, with the version suffix dropped**:
  `technique_charge_aura_v2` becomes `technique-charge-aura.md`. A reader who
  has an id from a catalog row or a `--effect=` flag should be able to guess the
  filename by stripping `_vN`.
- **Open with what the effect is across all its versions**, a table of them, and
  a link back to `VFX_DESIGN.md`. Then one `##` section per version, newest
  last, so the page reads in the order the decisions were made.
- **Give a version its own section even when it supersedes another.** Do not
  delete the old one: the reason a constant changed is usually only legible
  next to what it changed from.
- **Prefer measured claims to descriptions.** "The mask carries alpha ~253 in
  its edge columns, so panels butt together with no margin" is worth writing
  down; "the mask has hard edges" is not. Numbers a future reader can re-derive
  or check are the point.
- **Record what was rejected and why**, not just what shipped. The reason a
  constant is 0.26 is usually that something at 0.45 was tried and failed.
- **Organise by version where versions are forks, by feature where they are
  not.** Solar Storm's rungs are override sets on one effect rather than
  separate files, so its page carries a ladder table and then reads by feature;
  the technique charge aura's are genuine forks and read version by version.
- **When backfilling, say so and say what from.** A page written from code and
  commit history months later is a different kind of claim than one written
  alongside the work, and a reader deserves to know which they are holding.
- **Keep open questions visible** under their own heading rather than as a TODO
  buried mid-paragraph, and mark them resolved in place when a later version
  answers them.
