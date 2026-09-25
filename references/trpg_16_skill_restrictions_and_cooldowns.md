# Aspect 16: Skill Restrictions & Cooldowns

A comparative breakdown of how TRPGs restrict the frequency of powerful skills and spells, balancing action economy against explosive output.

---

## 1. Skill Restriction Paradigms

Core architecture defining how a unit is prevented from spamming their most powerful abilities every turn.

### Approach 1.1: Hard Cooldown Turns
After a skill is used, it goes on a "cooldown" for a set number of turns. It cannot be used again until the cooldown reaches 0.
* **Games Following This Approach:** *World of Warcraft, Divinity: Original Sin 2, XCOM (some abilities), Mario + Rabbids Kingdom Battle, World of Warcraft (MMO)*
* **Detailed Variations:**
  - *Divinity: Original Sin 2:* Skills have hard cooldowns (e.g., 4 turns), but certain abilities can reduce cooldowns globally.
  - *Mario + Rabbids:* Movement and attack abilities (like Hero Sight or Dash) have turn-based cooldowns to encourage cycling tactics.

### Approach 1.2: Resource Depletion (MP/SP Caps)
Skills have no hard turn cooldowns, but their resource costs (MP, SP, Energy) are so high relative to the unit's max pool that they naturally limit usage.
* **Games Following This Approach:** *Final Fantasy Tactics, Fire Emblem (Engage/Three Houses uses durability/charges, others use HP/MP), Shining Force Series, Tactics Ogre: Let Us Cling Together, Disgaea Series, Breath of Fire Series, Treasure of the Rudras, Vandal Hearts Series, Chrono Trigger, Digimon World 3, Dragon Quest 9, Ragnarok Online, MapleStory, Pokemon Series (PP)*
* **Detailed Variations:**
  - *Final Fantasy Tactics:* Spells cost MP. A Mage might only have enough MP to cast "Ultima" twice per battle without items.
  - *Pokemon Series:* Uses "PP" (Power Points). A strong move like Fire Blast only has 5 PP.

### Approach 1.3: Charge Times / Delay Penalties
Using a powerful skill incurs a severe penalty to the unit's action economy, either taking multiple turns to cast or heavily delaying their next turn.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre: Let Us Cling Together, Wakfu, Dofus, Hoshigami: Ruining Blue Earth, Panzer Dragoon Saga, Sakura Wars, Stella Deus: The Gate of Eternity, Energy Breaker*
* **Detailed Variations:**
  - *Final Fantasy Tactics:* "Charge Time" (CT). A strong spell might take 5 clock ticks to resolve, giving enemies time to move out of the AoE.
  - *Panzer Dragoon Saga:* Powerful attacks require 3 full ATB gauges instead of 1, severely reducing action frequency.

### Approach 1.4: Usage Limits / Limited Charges
The skill can only be used a hard-capped number of times per battle, regardless of cooldowns or MP.
* **Games Following This Approach:** *Fire Emblem Series (Weapon Durability), XCOM (Consumables), TearRing Saga & Berwick Saga, Triangle Strategy, Feda: Emblem of Justice*
* **Detailed Variations:**
  - *Fire Emblem:* Powerful weapons/staves (like "Rescue" or "Bolting") have 3-5 uses before they break permanently.
  - *XCOM:* Medkits or rockets have 1-2 charges per mission.

---

## 2. Environmental & Status Interactions with Restrictions

### Approach 2.1: Silence / Amnesia Debuffs
Status effects that temporarily lock a unit out of casting spells or using skills entirely, bypassing cooldowns.
* **Games Following This Approach:** *Final Fantasy Tactics, Tactics Ogre, Divinity: Original Sin 2, Ragnarok Online, Dragon Quest 9*

### Not Applicable / Absent
* *Road of Nogg (Current)*: Has no Silence status effect natively implemented yet.

---

## Implementation Takeaways for Road of Nogg

- Per-spell turn cooldowns already exist and tick at turn end.
- Player UI must show remaining cooldown and target validity before command confirmation.

[Back to Master Index](./tactical_rpg_turn_systems.md)
