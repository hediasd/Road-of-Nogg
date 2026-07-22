# TRPG Reference Index: Comprehensive Mechanics & Systems Taxonomy

A feature-driven architectural reference analyzing turn structures, speed mechanics, action economy, damage scaling, luck, core algorithms, elemental systems, shops, and forging/crafting across classic, modern, and obscure Tactical & Turn-Based RPGs. Designed for **Road of Nogg**.

---

## Games Included in This Reference

This study analyzes **26 major & obscure RPG and TRPG titles**:

1. **Fire Emblem Series** (Classic Phase System, Weapon Triangle, Doubling, Forge)
2. **Final Fantasy Tactics (FFT)** (CT 100 System, Brave/Faith, Job Tree, Item Fusion)
3. **Tactics Ogre: Let Us Cling Together / Reborn** (Wait Time WT, Armor Weight, Crafting)
4. **Hoshigami: Ruining Blue Earth** (Ready Action Points RAP, Coin Engraving, Session Attacks)
5. **Triangle Strategy** (Individual Speed Timeline, TP System, Flanking)
6. **Disgaea Series** (Execute System, Multi-Stat Scaling, Item World, Dark Assembly)
7. **Shining Force Series** (Classic Round Agility Queue, Simple Stats)
8. **TearRing Saga & Berwick Saga** (Alternating Unit Ratio Phase, Shield Skills)
9. **Grandia Series & Octopath Traveler** (Timeline COM/ACT Queue, Shield Break)
10. **Vanguard Bandits** (AP Pool, Fatigue/FP Heat Gauge, Reaction Choices)
11. **Into the Breach** (Deterministic Telegraphed Enemy Turns)
12. **Dofus & Wakfu** (Grid MMORPG: AP/MP Pools, Lock/Tackle Dodge, Line of Sight)
13. **Breath of Fire Series (BoF 1–4)** (Agility EX-Turns, Formations, Master Skills)
14. **Treasure of the Rudras (Rudra no Hidou)** (Kotodama Custom Word-Parsing Spells)
15. **Langrisser / Der Langrisser** (Commander Auras, Mercenary Troop Stacks)
16. **Vandal Hearts Series** (Directional Backstabs, Elevation Blood Splatters)
17. **Knights in the Nightmare** (Wisp Real-Time Bullet-Hell, Soul Transmutation)
18. **Phantom Brave / Makai Kingdom** (Free-Form Circle Movement, Object Confine System)
19. **Front Mission Series (FM 1–5)** (Wanzer Limb Targeting, Part Assembly Shop, AP)
20. **Wild Arms XF** (Hexagonal Grid HEX System, Class Initiative, Body Blocking)
21. **Yggdra Union** (Gender-Based Union Formation Lines, Card Skill Decks, Morale)
22. **Stella Deus: The Gate of Eternity** (AP Turn System, Alchemy Fusion Crafts)
23. **Resonance of Fate** (Tri-Attack Bezier Hero Actions, Scratch vs Direct Damage)
24. **Master of Monsters / Nectaris** (Hex Zone of Control ZOC, Terrain Defense %)
25. **Energy Breaker & Feda: Emblem of Justice** (AP Element Magic, Law/Chaos Morality)
26. **Pokémon Series (Mainline & Mystery Dungeon / Conquest)** (Priority Tiers, 18-Type Matrix, STAB, PP, Abilities)

---

## Detailed Aspect Reference Modules

The analysis is split into individual focused modules in the `docs/` folder:

- 📜 [01: Turn Flow & Initiative Order](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_01_turn_flow_and_initiative.md)
- ⚡ [02: Speed Stat Behavior & Turn Frequency](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_02_speed_and_turn_frequency.md)
- ⏳ [03: Action Economy & Turn Cost Refunds](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_03_action_economy_and_costs.md)
- ⚔️ [04: Offensive Stat Scaling & Damage Calculation](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_04_offensive_stats_and_damage.md)
- 🎲 [05: Luck & Chance Mechanics](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_05_luck_and_chance_mechanics.md)
- 🛡️ [06: Interactivity, Counter-Attacks & Reactions](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_06_interactivity_and_counters.md)
- 🧠 [07: Secondary Resource Gauges & Mental Stats](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_07_secondary_resources_and_mental_stats.md)
- ⚖️ [08: Equipment Weight & Mobility Penalties](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_08_equipment_weight_and_mobility.md)
- 🧮 [09: Algorithms & Mathematical Models](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_09_algorithms_and_math_models.md)
- 🔥 [10: Elemental Systems & Affinity Matrices](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_10_elemental_systems_and_affinities.md)
- 🛒 [11: Shop, Economy & Merchant Systems](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_11_shop_and_economy_systems.md)
- 🔨 [12: Forging, Crafting & Item Systems](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/docs/trpg_12_forging_crafting_and_item_systems.md)

---

## Master Comparison Matrix (26 Games + Road of Nogg Baseline)

| Game Title | Turn Paradigm | Speed Effect | Primary Damage Formula | Luck Stat Role | Reaction System | Secondary Gauges | Equipment Penalty | Forging & Crafting |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Fire Emblem** | Phase-Based | Combat Doubling | Str/Mag vs Def/Res | Crit, Avoid, Proc % | Auto Range Counter | Weapon Ranks | Weight Penalty | Weapon Forging |
| **FFT** | Dynamic CT (100) | Turn Frequency | PA/MA vs Def/Res | N/A | Reaction Abilities | Brave & Faith | Jump/Move stats | Poaching & Fusion |
| **Tactics Ogre** | Dynamic WT (0) | Turn Frequency | Multi-stat formula | Crit & Loot Drops | Counterattacks | Loyalty / WT Base | Armor & Weapon Weight | Relic Upgrades |
| **Hoshigami** | Dynamic RAP % | Turn Frequency | STR & Backstab | Crit & Coin drop | Session Pushes | Elemental Deity RAP | N/A | Coin Engraving |
| **Triangle Strategy** | Turn Bar | Turn Frequency | Phys/Mag vs Def/Res | Crit Chance | Flanking Co-op | TP (Tactical Points) | Jump/Move stats | Blacksmith Upgrade |
| **Disgaea** | Phase-Based | N/A | Weapon-specific stats | N/A | Multi-Counter Loops | Mana & Counter Count | Throw Range & Jump | Item World Leveling |
| **Shining Force** | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A |
| **Berwick Saga** | Alternating Ratio | N/A | Weapon Skill Ranks | Lethality Avoid | Shields & Auto Counter | Shield Skills | Weight penalties | N/A |
| **Grandia / Octopath** | Timeline Queue | Movement Speed | Multiplicative Stat | Crit Stat | Action Cancel / Break | Shield Break Gauge | N/A | N/A |
| **Vanguard Bandits** | Dynamic AP | AP Recovery Rate | Mech ATK + Height | N/A | AP Counter/Defend/Avoid | Fatigue Points (FP) | Height bonus | N/A |
| **Into the Breach** | Telegraphed Phase | N/A | Fixed Deterministic | N/A | N/A | Grid Building HP | N/A | N/A |
| **Dofus & Wakfu** | Dynamic Initiative | Tackle / Lock Dodge | Element Stats (Str/Int/Cha/Agi) | Crit % (Agility/Luk) | Lock Penalty / Reaction AP | AP & MP Gauges | Range & LoS Restrictions | Gear Crafting |
| **Breath of Fire** | Round Queue | EX Turns (Double Act) | Power vs Defense | Crit & Counter % | Agility-based Counters | AP / Master Skills | Weight / Agility Drag | N/A |
| **Treasure of Rudras** | Round Queue | Initiative Order | Kotodama Spell Parse | Crit % | Passive Counters | MP / Kotodama Words | N/A | N/A |
| **Langrisser** | Phase-Based | Troop Priority | Commander ATK + Troop Buff | Crit % | Commander Retaliation | Command Range Aura | Terrain Move Cost | N/A |
| **Vandal Hearts** | Phase-Based | N/A | Physical vs Defense | N/A | Auto Counter | Height / Direction Bonus | N/A | N/A |
| **Knights in Nightmare** | Wisp Phase Clock | N/A | Skill Power vs Defense | N/A | N/A | Soul Meter | LoS / Phase Timers | Soul Transmutation |
| **Phantom Brave** | Confine Turn Limit | Turn Radius Speed | ATK vs DEF | N/A | N/A | Turn Expire Counter | N/A | Title Fusion |
| **Front Mission** | Phase-Based | AP Generation | Body/Arm/Leg HP | N/A | Intercept Overwatch | Pilot Skill AP | Leg Type Weight | Wanzer Assembly |
| **Wild Arms XF** | Dynamic Initiative | Turn Frequency | Class Power vs Def | Crit % | ZOC Body Blocking | Vitality Points (VP) | Elevation / Jump | Class Skill Transfer |
| **Yggdra Union** | Card Movement Phase | N/A | Card Power vs Morale | N/A | Union Chain Strikes | Morale Meter | N/A | N/A |
| **Stella Deus** | Dynamic AP Queue | Turn Frequency | Phys/Mag vs Def/Res | Crit % | Team Attack Combos | AP Pool | Weight WT Penalties | Alchemy Fusion |
| **Resonance of Fate** | Real-Time Hero Runs | Running Speed | Scratch (Blue) vs Direct (Red) | N/A | Sightline Interruption | Bezel Points | Weight Drag | Gun Modification |
| **Master of Monsters** | Alternating Turn | Initiative Order | ATK vs DEF * Terrain % | N/A | ZOC Counter Strikes | Unit Evolution Exp | Terrain Cost | N/A |
| **Energy Breaker / Feda** | Round Queue / Phase | Initiative Order | Element Power vs Def | Crit % | Auto Counter | Alignment / AP Pool | Terrain Cost | N/A |
| **Pokémon Series** | Priority Bracket Queue | Round Order / Priority | Atk/SpAtk vs Def/SpDef | Crit Stage & Acc/Eva | Counter / Protect / Priority | Move PP / Status / Form | Held Item Weight | TM Machine Crafting |
| **Road of Nogg (Current)** | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A |

---

*Master Index File: `docs/tactical_rpg_turn_systems.md`*
