# InterruptTracker

A World of Warcraft addon for **Midnight (12.0)** that tracks interrupt cooldowns for Mythic+ groups.

## What it does

- Displays all party members with their interrupt spell icon and a countdown timer
- Pre-populates on login — no need to wait for someone to kick before they appear
- Class-coloured names for quick visual identification
- Spec-aware: automatically shows the correct interrupt for spec-dependent classes (e.g. Demo Warlock gets Axe Toss, Balance Druid gets Solar Beam)
- Players are added when they join the group and removed when they leave
- Draggable frame — position it wherever you like

## Compatibility

Built specifically for **WoW Midnight (patch 12.0+)**. It does not use `COMBAT_LOG_EVENT_UNFILTERED`, which was removed in 12.0. Instead it uses `UNIT_SPELLCAST_SUCCEEDED` and addon messaging to detect and share interrupt events within the restrictions of the Midnight API.

## Installation

1. Download or clone this repo
2. Place the `InterruptTracker` folder in:
   ```
   World of Warcraft/_retail_/Interface/AddOns/
   ```
3. Enable the addon from the AddOns menu on the character select screen

## Known limitations

- **Requires the addon on each client** for full coverage. `UNIT_SPELLCAST_SUCCEEDED` may catch party member interrupts directly, but addon messaging ensures reliability for all group members who have it installed.
- Spell IDs may change with future patches. If a class isn't tracking correctly, the spell ID likely needs updating in `Data.lua`.
- Spec detection for party members relies on cached inspect data — if a party member's spec isn't cached yet, it defaults to the class primary interrupt and corrects itself on their first kick.

## Tracked interrupts

| Class | Spell | Cooldown |
|---|---|---|
| Death Knight | Mind Freeze | 15s |
| Demon Hunter | Disrupt | 15s |
| Druid (Balance) | Solar Beam | 60s |
| Druid (other) | Skull Bash | 15s |
| Evoker | Quell | 20s |
| Hunter (BM/MM) | Counter Shot | 24s |
| Hunter (Survival) | Muzzle | 15s |
| Mage | Counterspell | 24s |
| Monk | Spear Hand Strike | 15s |
| Paladin | Rebuke | 15s |
| Priest | Silence | 45s |
| Rogue | Kick | 15s |
| Shaman | Wind Shear | 12s |
| Warlock (Demo) | Axe Toss | 30s |
| Warlock (other) | Spell Lock | 24s |
| Warrior | Pummel | 15s |

## Contributing

Spell IDs and cooldowns can change between patches. If you notice something out of date, `Data.lua` is the only file that needs editing for most fixes.
