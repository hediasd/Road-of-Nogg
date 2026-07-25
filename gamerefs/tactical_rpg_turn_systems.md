# TRPG Reference Index: Comprehensive Mechanics & Systems Taxonomy

A feature-driven reference for Road of Nogg design questions across tactical and
turn-based RPGs. The roster is centralized here; aspect modules cover only the
examples relevant to their subject.

Research entries are comparative notes, not implementation authority. Verify a
specific technical claim against an external source before relying on it in code.

---

## Games Included in This Reference

This study analyzes **42 major & obscure RPG and TRPG titles**:

1. **Master of Monsters / Nectaris** (PC Engine, 1989) (Hex Zone of Control ZOC, Terrain Defense %)
2. **Fire Emblem Series** (Famicom, 1990) (Classic Phase System, Weapon Triangle, Doubling, Forge)
3. **Langrisser / Der Langrisser** (Mega Drive, 1991) (Commander Auras, Mercenary Troop Stacks)
4. **Super Robot Wars Series** (Game Boy, 1991) (Air/Ground/Space Terrain, Morale/Will)
5. **Shining Force Series** (Genesis, 1992) (Classic Round Agility Queue, Simple Stats)
6. **Breath of Fire Series (BoF 1–4)** (SNES, 1993) (Agility EX-Turns, Formations, Master Skills)
7. **Ogre Battle / Ogre Battle 64** (SNES, 1993) (Time of Day Cycles, Alignment, Formations)
8. **Phantasy Star Series (specifically PS IV)** (Genesis, 1993) (Combo Techniques / Fusion Spells, Macro Execution, TP vs Skill Uses)
9. **Energy Breaker & Feda: Emblem of Justice** (SNES, 1994) (AP Element Magic, Law/Chaos Morality)
10. **Chrono Trigger** (SNES, 1995) (Active Time Battle ATB, Dual/Triple Techs, Positioning)
11. **Suikoden Series & Suikoden Tactics** (PS1, 1995) (Unite Attacks, Tiered Rune Charges, Grid Elemental Surfaces)
12. **Tactics Ogre: Let Us Cling Together / Reborn** (SNES, 1995) (Wait Time WT, Armor Weight, Crafting)
13. **Bahamut Lagoon** (SNES, 1996) (Surface Element Modification, Dragon Squads)
14. **Pokémon Series (Mainline & Mystery Dungeon / Conquest)** (Game Boy, 1996) (Priority Tiers, 18-Type Matrix, STAB, PP, Abilities)
15. **Sakura Wars** (Saturn, 1996) (Grid ARMS AP System, Trust/LIPS mental stats, Mecha)
16. **Treasure of the Rudras (Rudra no Hidou)** (SNES, 1996) (Kotodama Custom Word-Parsing Spells)
17. **Vandal Hearts Series** (PS1, 1996) (Directional Backstabs, Elevation Blood Splatters)
18. **Final Fantasy Tactics (FFT)** (PS1, 1997) (CT 100 System, Brave/Faith, Job Tree, Item Fusion)
19. **Grandia Series & Octopath Traveler** (Saturn, 1997) (Timeline COM/ACT Queue, Shield Break)
20. **Panzer Dragoon Saga** (Saturn, 1998) (3D ATB positioning, 3-Gauge action system, weak points)
21. **Threads of Fate (Dewprism)** (PS1, 1999) (Modular Spell Shapes/Elements, Monster Shapeshifting)
22. **Vagrant Story** (PS1, 2000) (Targeted Body Parts, Limb Afflictions, Risk Gauge, Weapon/Elemental Affinities)
23. **Advance Wars Series** (GBA, 2001) (Global Weather, Fog of War, CO Powers)
24. **Hoshigami: Ruining Blue Earth** (PS1, 2001) (Ready Action Points RAP, Coin Engraving, Session Attacks)
25. **TearRing Saga & Berwick Saga** (PS1, 2001) (Alternating Unit Ratio Phase, Shield Skills)
26. **Digimon World 3** (PS1, 2002) (1v1 Turn-Based, Digivolution Trees, Elemental Weaknesses)
27. **Ragnarok Online** (PC, 2002) (Grid MMORPG, Stat/Card Builds, Element/Size Modifiers, ASPD)
28. **Disgaea Series** (PS2, 2003) (Execute System, Multi-Stat Scaling, Item World, Dark Assembly)
29. **Final Fantasy Tactics Advance (FFTA)** (GBA, 2003) (Global Field Laws, Judge System)
30. **MapleStory** (PC, 2003) (2D MMO, Jump Quests, Mobbing, Flash Jump/Teleport)
31. **Dofus & Wakfu** (PC, 2004) (Grid MMORPG: AP/MP Pools, Lock/Tackle Dodge, Line of Sight)
32. **Phantom Brave / Makai Kingdom** (PS2, 2004) (Free-Form Circle Movement, Object Confine System)
33. **Stella Deus: The Gate of Eternity** (PS2, 2004) (AP Turn System, Alchemy Fusion Crafts)
34. **Yggdra Union** (GBA, 2006) (Gender-Based Union Formation Lines, Card Skill Decks, Morale)
35. **Wild Arms XF** (PSP, 2007) (Hexagonal Grid HEX System, Class Initiative, Body Blocking)
36. **Knights in the Nightmare** (NDS, 2008) (Wisp Real-Time Bullet-Hell, Soul Transmutation)
37. **Dragon Quest 9** (NDS, 2009) (Turn Queue, Tension System, Vocation Classes, Skill Points)
38. **Divinity: Original Sin 1 & 2** (PC, 2014) (Deep Surface Chemistry, Environmental Hazards)
39. **Mario + Rabbids Kingdom Battle** (Switch, 2017) (Cover Destruction, Movement Pipes, Team Jump)
40. **Into the Breach** (PC, 2018) (Deterministic Telegraphed Enemy Turns)
41. **Triangle Strategy** (Switch, 2022) (Individual Speed Timeline, TP System, Flanking)
42. **Popolocrois Series** (PS1, 1996) (2x2 Grid Bosses, Tactical Movement)

---

## Detailed Aspect Reference Modules

The analysis is split into individual focused modules in the `gamerefs/` folder:

- 📜 [01: Turn Flow & Initiative Order](./trpg_01_turn_flow_and_initiative.md)
- ⚡ [02: Speed Stat Behavior & Turn Frequency](./trpg_02_speed_and_turn_frequency.md)
- ⏳ [03: Action Economy & Turn Cost Refunds](./trpg_03_action_economy_and_costs.md)
- ⚔️ [04: Offensive Stat Scaling & Damage Calculation](./trpg_04_offensive_stats_and_damage.md)
- 🎲 [05: Luck & Chance Mechanics](./trpg_05_luck_and_chance_mechanics.md)
- 🛡️ [06: Interactivity, Counter-Attacks & Reactions](./trpg_06_interactivity_and_counters.md)
- 🧠 [07: Secondary Resource Gauges & Mental Stats](./trpg_07_secondary_resources_and_mental_stats.md)
- ⚖️ [08: Equipment Weight & Mobility Penalties](./trpg_08_equipment_weight_and_mobility.md)
- 🧮 [09: Algorithms & Mathematical Models](./trpg_09_algorithms_and_math_models.md)
- 🔥 [10: Elemental Systems & Affinity Matrices](./trpg_10_elemental_systems_and_affinities.md)
- 🛒 [11: Shop, Economy & Merchant Systems](./trpg_11_shop_and_economy_systems.md)
- 🔨 [12: Forging, Crafting & Item Systems](./trpg_12_forging_crafting_and_item_systems.md)

- 🌲 [13: Environment, Terrain & Weather](./trpg_13_environment_and_weather.md)
- 📊 [14: Stats & Attributes Progression](./trpg_14_stats_and_attributes.md)
- 👾 [15: Quirks & Anti-Patterns](./trpg_15_quirks_and_anti_patterns.md)
- ⌛ [16: Skill Restrictions & Cooldowns](./trpg_16_skill_restrictions_and_cooldowns.md)
- 🛡️ [17: Defensive Mechanics & Status Effects](./trpg_17_defensive_mechanics_and_status_effects.md)
- ⬛ [18: Grid Mechanics & Large Monsters](./trpg_18_grid_mechanics_and_large_monsters.md)

---

## Master Comparison Matrix

| Game Title | Turn Paradigm | Speed Effect | Primary Damage Formula | Luck Stat Role | Reaction System | Secondary Gauges | Equipment Penalty | Forging & Crafting | Stats & Attributes | Environment & Weather |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Master of Monsters** (PC Engine, 1989) | Alternating Turn | Initiative Order | ATK vs DEF * Terrain % | N/A | ZOC Counter Strikes | Unit Evolution Exp | Terrain Cost | N/A | Simple ATK/DEF | Hex Terrain % |
| **Fire Emblem** (Famicom, 1990) | Phase-Based | Combat Doubling | Str/Mag vs Def/Res | Crit, Avoid, Proc % | Auto Range Counter | Weapon Ranks | Weight Penalty | Weapon Forging | Standard (Str/Mag/Skl/Spd) | Terrain Avoid/Def Bonus |
| **Langrisser** (Mega Drive, 1991) | Phase-Based | Troop Priority | Commander ATK + Troop Buff | Crit % | Commander Retaliation | Command Range Aura | Terrain Move Cost | N/A | ATK/DEF (Scale 1-10) | Heavy Terrain Modifiers |
| **Super Robot Wars** (Game Boy, 1991) | Phase-Based | Evasion / Hit Rate | Weapon ATK vs Armor | N/A | Support Defend / Counter | Morale (Will) / EN / SP | N/A | Mech Tuning / Upgrades | Melee/Rng/Skill/Def/Evd | Air/Ground/Space Evasion |
| **Shining Force** (Genesis, 1992) | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A | Basic | Terrain Defense % |
| **Breath of Fire** (SNES, 1993) | Round Queue | EX Turns (Double Act) | Power vs Defense | Crit & Counter % | Agility-based Counters | AP / Master Skills | Weight / Agility Drag | N/A | Standard | Formations |
| **Ogre Battle 64** (N64, 1999) | Real-Time Auto-Battle | Attack Frequency | ATK vs DEF / Alignment | N/A | Block / Evade | Fatigue / Stamina | Class Weight | Equipment Drop Upgrades | STR/VIT/INT/MEN/AGI/DEX | Day & Night Cycles |
| **Phantasy Star Series** (Genesis, 1993) | Round Queue / Macro Order | Initiative Order | (ATK - DEF) * Tech Multiplier | Crit & Status Resistance | Auto Skill Counter | TP Pool / Skill Charge Uses | Class Restrictions | Weapon Modification | STR/AGI/DEX/MNT/END | Environmental Hazards |
| **Energy Breaker / Feda** (SNES, 1994) | Round Queue / Phase | Initiative Order | Element Power vs Def | Crit % | Auto Counter | Alignment / AP Pool | Terrain Cost | N/A | Standard | Neutral |
| **Chrono Trigger** (SNES, 1995) | ATB (Active Time) | ATB Fill Rate | Power vs Defense | Evade / Hit Rate | N/A | Dual/Triple Tech Gauges | N/A | N/A | Power/Stamina/Speed/Magic | Battlefield Positioning |
| **Suikoden Series** (PS1, 1995) | Round Queue / Grid TRPG | Turn Frequency / Multi-Attacks | ATK * Multiplier - DEF | Crit & Evade % | Counter & Co-op Retaliation | Tiered Rune Charges (L1-L4) | Heavy Armor Speed Drag | Weapon Sharpening / Runes | PWR/SKL/DEF/MAG/MDEF/SPD/LUK | Grid Elemental Surfaces (Tactics) |
| **Tactics Ogre** (SNES, 1995) | Dynamic WT (0) | Turn Frequency | Multi-stat formula | Crit & Loot Drops | Counterattacks | Loyalty / WT Base | Armor & Weapon Weight | Relic Upgrades | STR/VIT/DEX/AGI/AVD | Dynamic Weather |
| **Bahamut Lagoon** (SNES, 1996) | Phase-Based | N/A | ATK vs DEF (Squad Based) | N/A | N/A | SP (Summon Points) | N/A | Dragon Feeding | HP/MP/STR/DEF/AGI/MAG | Surface Element Deformation |
| **Pokémon Series** (Game Boy, 1996) | Priority Bracket Queue | Round Order / Priority | Atk/SpAtk vs Def/SpDef | Crit Stage & Acc/Eva | Counter / Protect / Priority | Move PP / Status / Form | Held Item Weight | TM Machine Crafting | HP/Atk/Def/SpA/SpD/Spe | Deep Weather System |
| **Sakura Wars** (Saturn, 1996) | AP (ARMS) Grid | N/A | ATK vs DEF | N/A | Auto Counter | Spirit / LIPS Trust Meter | N/A | N/A | Standard | Steam / Barriers |
| **Treasure of Rudras** (SNES, 1996) | Round Queue | Initiative Order | Kotodama Spell Parse | Crit % | Passive Counters | MP / Kotodama Words | N/A | N/A | Standard | Day/Night Cycle |
| **Vandal Hearts** (PS1, 1996) | Phase-Based | N/A | Physical vs Defense | N/A | Auto Counter | Height / Direction Bonus | N/A | N/A | Standard | Push blocks / Craters |
| **FFT** (PS1, 1997) | Dynamic CT (100) | Turn Frequency | PA/MA vs Def/Res | N/A | Reaction Abilities | Brave & Faith | Jump/Move stats | Poaching & Fusion | PA, MA, Speed, Brave/Faith | Weather Element Boosts |
| **Grandia / Octopath** (Saturn, 1997) | Timeline Queue | Movement Speed | Multiplicative Stat | Crit Stat | Action Cancel / Break | Shield Break Gauge | N/A | N/A | Standard RPG | None |
| **Panzer Dragoon Saga** (Saturn, 1998) | ATB + Positioning | ATB Charge Rate | Power vs Armor (Position dependent) | N/A | N/A | BP (Berserk Points) | N/A | N/A | Standard | None |
| **Threads of Fate** (PS1, 1999) | Real-Time Action | Movement / Casting | (ATK - DEF) * Spell Shape | Drop Rates | Counter Spells | MP Pool / Shape Costs | Weight Penalties | Conversion Upgrades | HP/MP/ATK/DEF | Hazard Traps |
| **Vagrant Story** (PS1, 2000) | Targeted Sphere ATB | Sphere Radius / Chain Timing | (ATK - DEF) * Limb % * Affinity % | Crit & Evade Rates | Defense & Chain Timing | Risk Gauge (0-100) | Equipment Weight / Class Drag | Blade & Guard Fusion | STR/INT/AGI + Limb HP + Affinities | Room & Material Modifiers |
| **Advance Wars** (GBA, 2001) | Phase-Based | N/A | Base % * HP vs Base % * Def % | Random 0-9% Variance | Counter-Attack | CO Power Meter | N/A | N/A | HP / Ammo / Fuel | Global Weather / Fog of War |
| **Hoshigami** (PS1, 2001) | Dynamic RAP % | Turn Frequency | STR & Backstab | Crit & Coin drop | Session Pushes | Elemental Deity RAP | N/A | Coin Engraving | Basic (STR/DEF/AGI) | Terrain Height |
| **Berwick Saga** (PS1, 2001) | Alternating Ratio | N/A | Weapon Skill Ranks | Lethality Avoid | Shields & Auto Counter | Shield Skills | Weight penalties | N/A | Standard | Hex Terrain Types |
| **Digimon World 3** (PS1, 2002) | 1v1 Turn-Based | Initiative Order | Str vs Def / Spt vs Wis | Crit / Evade | Counters | Blast Gauge | Weight (Load) | Weapon Upgrades | Str/Def/Spt/Wis/Spd/Cha | None |
| **Ragnarok Online** (PC, 2002) | Real-Time MMO | Attack Speed (ASPD) | BaseATK + WpnATK * Size | Perfect Dodge / Crit % | Flee / Block / Reflect | SP / Weight Limit | Weight Limit (50% penalty) | Weapon Forging / Cards | STR/AGI/VIT/INT/DEX/LUK | AoE Spells / Traps |
| **Disgaea** (PS2, 2003) | Phase-Based | N/A | Weapon-specific stats | N/A | Multi-Counter Loops | Mana & Counter Count | Throw Range & Jump | Item World Leveling | Massive Inflation (ATK/INT/HIT) | Geo Panels |
| **FFTA** (GBA, 2003) | Dynamic CT | Turn Frequency | WAtk vs WDef | Critical Hits | Reaction Abilities | Judge Points (JP) / MP | Movement/Jump penalties | Mission Item Crafting | HP/MP/WAtk/WDef/MAtk/MDef/Spd | Global Field Laws |
| **MapleStory** (PC, 2003) | 2D Action MMO | N/A | Multiplier * (4*MainStat + SubStat) | N/A | Avoidability / Def | MP / Link Skills | N/A | Scroll Forging / Star Force | STR/DEX/INT/LUK | Jump Platforms / Mobbing |
| **Dofus & Wakfu** (PC, 2004) | Dynamic Initiative | Tackle / Lock Dodge | Element Stats (Str/Int/Cha/Agi) | Crit % (Agility/Luk) | Lock Penalty / Reaction AP | AP & MP Gauges | Range & LoS Restrictions | Gear Crafting | Element=Stat (e.g. Str=Earth) | Traps & Glyphs |
| **Phantom Brave** (PS2, 2004) | Confine Turn Limit | Turn Radius Speed | ATK vs DEF | N/A | N/A | Turn Expire Counter | N/A | Title Fusion | Standard | Slippery/Bouncy Objects |
| **Stella Deus** (PS2, 2004) | Dynamic AP Queue | Turn Frequency | Phys/Mag vs Def/Res | Crit % | Team Attack Combos | AP Pool | Weight WT Penalties | Alchemy Fusion | Standard | Height Differences |
| **Yggdra Union** (GBA, 2006) | Card Movement Phase | N/A | Card Power vs Morale | N/A | Union Chain Strikes | Morale Meter | N/A | N/A | GEN/ATK/TEC/LUK | Terrain Morale Boosts |
| **Wild Arms XF** (PSP, 2007) | Dynamic Initiative | Turn Frequency | Class Power vs Def | Crit % | ZOC Body Blocking | Vitality Points (VP) | Elevation / Jump | Class Skill Transfer | Standard | Hex Grid / Traps |
| **Knights in Nightmare** (NDS, 2008) | Wisp Phase Clock | N/A | Skill Power vs Defense | N/A | N/A | Soul Meter | LoS / Phase Timers | Soul Transmutation | VIT/TEC/AGI | Bullet-hell Grid |
| **Dragon Quest 9** (NDS, 2009) | Round Queue | Initiative Range | (Atk/2) - (Def/4) | Deftness (Crit/Steal) | Auto-Counters / Blocks | Tension / Coup de Grâce | Weight (Agility Drop) | Alchemy Pot | Str/Agi/Res/Deft/Charm/Mag | None |
| **Divinity: OS 2** (PC, 2014) | Dynamic AP Timeline | Initiative Order / AP | Physical/Magic Armor vs Damage | Crit Chance | Attacks of Opportunity | Source Points | Heavy Armor Move Penalty | Deep Item Crafting | STR/FIN/INT/CON/MEM/WIT | Deep Surface Chemistry |
| **Mario + Rabbids** | Phase-Based | N/A | ATK vs DEF (Cover Mitigation) | Crit / Super Effect % | Hero Sight (Overwatch) | N/A | N/A | Weapon Purchasing | HP / Move / Pipe Range | Destructible Cover / Pipes |
| **Into the Breach** | Telegraphed Phase | N/A | Fixed Deterministic | N/A | N/A | Grid Building HP | N/A | N/A | HP/Move Only | Chasm/Water/Acid/Fire |
| **Triangle Strategy** | Turn Bar | Turn Frequency | Phys/Mag vs Def/Res | Crit Chance | Flanking Co-op | TP (Tactical Points) | Jump/Move stats | Blacksmith Upgrade | Str/Mag/PhysDef/MagDef | Puddles/Ice/Fire Terrain |
| **Popolocrois Series** | Round Queue | N/A | ATK vs DEF | N/A | N/A | N/A | N/A | N/A | Standard | None |
| **Road of Nogg (Current)** | Round Queue | Initiative Order | ATK - DEF | N/A | N/A | None | N/A | N/A | HP/ATK/DEF/SPD/MOVE | Abyss/Trees |

---

*Master Index File: `gamerefs/tactical_rpg_turn_systems.md`*
