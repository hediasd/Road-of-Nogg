# TRPG Reference Index: Comprehensive Mechanics & Systems Taxonomy

A feature-driven architectural reference analyzing turn structures, speed mechanics, action economy, damage scaling, luck, core algorithms, elemental systems, shops, and forging/crafting across classic, modern, and obscure Tactical & Turn-Based RPGs. Designed for **Road of Nogg**.

---

## Games Included in This Reference

This study analyzes **28 major & obscure RPG and TRPG titles**:

1. **Fire Emblem Series** (Classic Phase System, Weapon Triangle, Doubling, Forge)
2. **Final Fantasy Tactics (FFT)** (CT 100 System, Brave/Faith, Job Tree, Item Fusion)
3. **Tactics Ogre: Let Us Cling Together / Reborn** (Wait Time WT, Armor Weight, Crafting)
4. **Hoshigami: Ruining Blue Earth** (Ready Action Points RAP, Coin Engraving, Session Attacks)
5. **Triangle Strategy** (Individual Speed Timeline, TP System, Flanking)
6. **Disgaea Series** (Execute System, Multi-Stat Scaling, Item World, Dark Assembly)
7. **Shining Force Series** (Classic Round Agility Queue, Simple Stats)
8. **TearRing Saga & Berwick Saga** (Alternating Unit Ratio Phase, Shield Skills)
9. **Grandia Series & Octopath Traveler** (Timeline COM/ACT Queue, Shield Break)
10. **Into the Breach** (Deterministic Telegraphed Enemy Turns)
11. **Dofus & Wakfu** (Grid MMORPG: AP/MP Pools, Lock/Tackle Dodge, Line of Sight)
12. **Breath of Fire Series (BoF 1–4)** (Agility EX-Turns, Formations, Master Skills)
13. **Treasure of the Rudras (Rudra no Hidou)** (Kotodama Custom Word-Parsing Spells)
14. **Langrisser / Der Langrisser** (Commander Auras, Mercenary Troop Stacks)
15. **Vandal Hearts Series** (Directional Backstabs, Elevation Blood Splatters)
16. **Knights in the Nightmare** (Wisp Real-Time Bullet-Hell, Soul Transmutation)
17. **Phantom Brave / Makai Kingdom** (Free-Form Circle Movement, Object Confine System)
18. **Wild Arms XF** (Hexagonal Grid HEX System, Class Initiative, Body Blocking)
19. **Yggdra Union** (Gender-Based Union Formation Lines, Card Skill Decks, Morale)
20. **Stella Deus: The Gate of Eternity** (AP Turn System, Alchemy Fusion Crafts)
21. **Master of Monsters / Nectaris** (Hex Zone of Control ZOC, Terrain Defense %)
22. **Energy Breaker & Feda: Emblem of Justice** (AP Element Magic, Law/Chaos Morality)
23. **Pokémon Series (Mainline & Mystery Dungeon / Conquest)** (Priority Tiers, 18-Type Matrix, STAB, PP, Abilities)
24. **Chrono Trigger** (Active Time Battle ATB, Dual/Triple Techs, Positioning)
25. **Digimon World 3** (1v1 Turn-Based, Digivolution Trees, Elemental Weaknesses)
26. **Dragon Quest 9** (Turn Queue, Tension System, Vocation Classes, Skill Points)
27. **Ragnarok Online** (Grid MMORPG, Stat/Card Builds, Element/Size Modifiers, ASPD)
28. **MapleStory** (2D MMO, Jump Quests, Mobbing, Flash Jump/Teleport)

---

## Detailed Aspect Reference Modules

The analysis is split into individual focused modules in the `gamerefs/` folder:

- 📜 [01: Turn Flow & Initiative Order](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_01_turn_flow_and_initiative.md)
- ⚡ [02: Speed Stat Behavior & Turn Frequency](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_02_speed_and_turn_frequency.md)
- ⏳ [03: Action Economy & Turn Cost Refunds](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_03_action_economy_and_costs.md)
- ⚔️ [04: Offensive Stat Scaling & Damage Calculation](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_04_offensive_stats_and_damage.md)
- 🎲 [05: Luck & Chance Mechanics](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_05_luck_and_chance_mechanics.md)
- 🛡️ [06: Interactivity, Counter-Attacks & Reactions](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_06_interactivity_and_counters.md)
- 🧠 [07: Secondary Resource Gauges & Mental Stats](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_07_secondary_resources_and_mental_stats.md)
- ⚖️ [08: Equipment Weight & Mobility Penalties](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_08_equipment_weight_and_mobility.md)
- 🧮 [09: Algorithms & Mathematical Models](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_09_algorithms_and_math_models.md)
- 🔥 [10: Elemental Systems & Affinity Matrices](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_10_elemental_systems_and_affinities.md)
- 🛒 [11: Shop, Economy & Merchant Systems](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_11_shop_and_economy_systems.md)
- 🔨 [12: Forging, Crafting & Item Systems](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_12_forging_crafting_and_item_systems.md)

- 🌲 [13: Environment, Terrain & Weather](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_13_environment_and_weather.md)
- 📊 [14: Base Stats, Attributes & Characteristics](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_14_stats_and_attributes.md)
- 👾 [15: TRPG Quirks & Anti-Patterns](file:///c:/Users/Henri/Documents/Road%20of%20Nogg/gamerefs/trpg_15_quirks_and_anti_patterns.md)

---

## Master Comparison Matrix (28 Games + Road of Nogg Baseline)

| Game Title | Turn Paradigm | Speed Effect | Primary Damage Formula | Luck Stat Role | Reaction System | Secondary Gauges | Equipment Penalty | Forging & Crafting | Stats & Attributes | Environment & Weather |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Fire Emblem** | Phase-Based | Combat Doubling | Str/Mag vs Def/Res | Crit, Avoid, Proc % | Auto Range Counter | Weapon Ranks | Weight Penalty | Weapon Forging | Standard (Str/Mag/Skl/Spd) | Terrain Avoid/Def Bonus |
| **FFT** | Dynamic CT (100) | Turn Frequency | PA/MA vs Def/Res | N/A | Reaction Abilities | Brave & Faith | Jump/Move stats | Poaching & Fusion | PA, MA, Speed, Brave/Faith | Weather Element Boosts |
| **Tactics Ogre** | Dynamic WT (0) | Turn Frequency | Multi-stat formula | Crit & Loot Drops | Counterattacks | Loyalty / WT Base | Armor & Weapon Weight | Relic Upgrades | STR/VIT/DEX/AGI/AVD | Dynamic Weather |
| **Hoshigami** | Dynamic RAP % | Turn Frequency | STR & Backstab | Crit & Coin drop | Session Pushes | Elemental Deity RAP | N/A | Coin Engraving | Basic (STR/DEF/AGI) | Terrain Height |
| **Triangle Strategy** | Turn Bar | Turn Frequency | Phys/Mag vs Def/Res | Crit Chance | Flanking Co-op | TP (Tactical Points) | Jump/Move stats | Blacksmith Upgrade | Str/Mag/PhysDef/MagDef | Puddles/Ice/Fire Terrain |
| **Disgaea** | Phase-Based | N/A | Weapon-specific stats | N/A | Multi-Counter Loops | Mana & Counter Count | Throw Range & Jump | Item World Leveling | Massive Inflation (ATK/INT/HIT) | Geo Panels |
| **Shining Force** | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A | Basic | Terrain Defense % |
| **Berwick Saga** | Alternating Ratio | N/A | Weapon Skill Ranks | Lethality Avoid | Shields & Auto Counter | Shield Skills | Weight penalties | N/A | Standard | Hex Terrain Types |
| **Grandia / Octopath** | Timeline Queue | Movement Speed | Multiplicative Stat | Crit Stat | Action Cancel / Break | Shield Break Gauge | N/A | N/A | Standard RPG | None |
| **Into the Breach** | Telegraphed Phase | N/A | Fixed Deterministic | N/A | N/A | Grid Building HP | N/A | N/A | HP/Move Only | Chasm/Water/Acid/Fire |
| **Dofus & Wakfu** | Dynamic Initiative | Tackle / Lock Dodge | Element Stats (Str/Int/Cha/Agi) | Crit % (Agility/Luk) | Lock Penalty / Reaction AP | AP & MP Gauges | Range & LoS Restrictions | Gear Crafting | Element=Stat (e.g. Str=Earth) | Traps & Glyphs |
| **Breath of Fire** | Round Queue | EX Turns (Double Act) | Power vs Defense | Crit & Counter % | Agility-based Counters | AP / Master Skills | Weight / Agility Drag | N/A | Standard | Formations |
| **Treasure of Rudras** | Round Queue | Initiative Order | Kotodama Spell Parse | Crit % | Passive Counters | MP / Kotodama Words | N/A | N/A | Standard | Day/Night Cycle |
| **Langrisser** | Phase-Based | Troop Priority | Commander ATK + Troop Buff | Crit % | Commander Retaliation | Command Range Aura | Terrain Move Cost | N/A | ATK/DEF (Scale 1-10) | Heavy Terrain Modifiers |
| **Vandal Hearts** | Phase-Based | N/A | Physical vs Defense | N/A | Auto Counter | Height / Direction Bonus | N/A | N/A | Standard | Push blocks / Craters |
| **Knights in Nightmare** | Wisp Phase Clock | N/A | Skill Power vs Defense | N/A | N/A | Soul Meter | LoS / Phase Timers | Soul Transmutation | VIT/TEC/AGI | Bullet-hell Grid |
| **Phantom Brave** | Confine Turn Limit | Turn Radius Speed | ATK vs DEF | N/A | N/A | Turn Expire Counter | N/A | Title Fusion | Standard | Slippery/Bouncy Objects |
| **Wild Arms XF** | Dynamic Initiative | Turn Frequency | Class Power vs Def | Crit % | ZOC Body Blocking | Vitality Points (VP) | Elevation / Jump | Class Skill Transfer | Standard | Hex Grid / Traps |
| **Yggdra Union** | Card Movement Phase | N/A | Card Power vs Morale | N/A | Union Chain Strikes | Morale Meter | N/A | N/A | GEN/ATK/TEC/LUK | Terrain Morale Boosts |
| **Stella Deus** | Dynamic AP Queue | Turn Frequency | Phys/Mag vs Def/Res | Crit % | Team Attack Combos | AP Pool | Weight WT Penalties | Alchemy Fusion | Standard | Height Differences |
| **Master of Monsters** | Alternating Turn | Initiative Order | ATK vs DEF * Terrain % | N/A | ZOC Counter Strikes | Unit Evolution Exp | Terrain Cost | N/A | Simple ATK/DEF | Hex Terrain % |
| **Energy Breaker / Feda** | Round Queue / Phase | Initiative Order | Element Power vs Def | Crit % | Auto Counter | Alignment / AP Pool | Terrain Cost | N/A | Standard | Neutral |
| **Pokémon Series** | Priority Bracket Queue | Round Order / Priority | Atk/SpAtk vs Def/SpDef | Crit Stage & Acc/Eva | Counter / Protect / Priority | Move PP / Status / Form | Held Item Weight | TM Machine Crafting | HP/Atk/Def/SpA/SpD/Spe | Deep Weather System |
| **Chrono Trigger** | ATB (Active Time) | ATB Fill Rate | Power vs Defense | Evade / Hit Rate | N/A | Dual/Triple Tech Gauges | N/A | N/A | Power/Stamina/Speed/Magic | Battlefield Positioning |
| **Digimon World 3** | 1v1 Turn-Based | Initiative Order | Str vs Def / Spt vs Wis | Crit / Evade | Counters | Blast Gauge | Weight (Load) | Weapon Upgrades | Str/Def/Spt/Wis/Spd/Cha | None |
| **Dragon Quest 9** | Round Queue | Initiative Range | (Atk/2) - (Def/4) | Deftness (Crit/Steal) | Auto-Counters / Blocks | Tension / Coup de Grâce | Weight (Agility Drop) | Alchemy Pot | Str/Agi/Res/Deft/Charm/Mag | None |
| **Ragnarok Online** | Real-Time MMO | Attack Speed (ASPD) | BaseATK + WpnATK * Size | Perfect Dodge / Crit % | Flee / Block / Reflect | SP / Weight Limit | Weight Limit (50% penalty) | Weapon Forging / Cards | STR/AGI/VIT/INT/DEX/LUK | AoE Spells / Traps |
| **MapleStory** | 2D Action MMO | N/A | Multiplier * (4*MainStat + SubStat) | N/A | Avoidability / Def | MP / Link Skills | N/A | Scroll Forging / Star Force | STR/DEX/INT/LUK | Jump Platforms / Mobbing |
| **Road of Nogg (Current)** | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A | HP/ATK/DEF/SPD/MOVE | Abyss/Trees |

---

*Master Index File: `gamerefs/tactical_rpg_turn_systems.md`*
