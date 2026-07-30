# Long-term backlog

## Empty-tile spell targeting

- Area spells currently center on an occupied target identified by `target_id`.
  Supporting casts centered on an empty tile requires a controller-neutral
  `target_pos` command field, replay-schema migration, validation and resolution
  changes, CPU target enumeration/scoring, area forecasts, and an explicit rule
  for casts whose area contains no units. Treat this as an Opus 5 architectural
  item; do not encode a fake monster target or implement it only in the player
  presentation.

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
