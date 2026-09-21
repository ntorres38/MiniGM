# The teleport database

`Tele/TeleportDB.lua` — **1,306 locations · 143 zones · 8 groups · 83 distinct map ids · ~100 KB**.

---

## Schema

```lua
MiniGMTeleOrder = { "Eastern Kingdoms", "Kalimdor", … }   -- fixes display order

MiniGMTele = {
  ["Eastern Kingdoms"] = {
    ["Elwynn Forest"] = {
      ["Goldshire"] = ".go xyz -9464.09 62.5605 56.0796 0",
      …
    },
  },
}
```

`MiniGMTele[group][zone][location]` → **the finished GM command**.

The value is not coordinates to be assembled — it is the literal string sent to the server. Nothing is parsed at runtime. Adding a location means adding one line; there is no format to get wrong beyond the command itself.

`MiniGMTeleOrder` exists because Lua's `pairs()` has no defined order, so the group column would shuffle on every login without it.

There is **no orientation field**. Every teleport lands you facing north (`.go xyz` defaults orientation to 0 when omitted). The upstream data never had one.

---

## Contents

| Group | Zones | Locations |
|---|---:|---:|
| Eastern Kingdoms | 29 | 391 |
| Kalimdor | 25 | 337 |
| Outland | 8 | 276 |
| Northrend | 14 | 53 |
| Dungeons & Raids | 57 | 91 |
| Battlegrounds | 2 | 21 |
| Flight Masters | 5 | 87 |
| Other | 3 | 50 |
| **Total** | **143** | **1,306** |

**Flight Masters** holds the Gryphon / Hippogryph / Wind Rider / Bat Handler / Zeppelin routes — 87 locations that would be invisible buried under "Other". **Other** is the leftovers: unfinished regions, jails, and miscellany.

---

## Provenance

Derived from **[AzerothAdmin](https://github.com/superstyro/AzerothAdmin)**'s `Data/TeleportTable.lua` (GPLv3), which derives from TrinityAdmin, which derives from MangAdmin. See [ATTRIBUTION.md](ATTRIBUTION.md) — this is what makes MiniGM a GPLv3 derivative work.

Upstream is not a table but a **function**, `ReturnTeleportLocations(cont)`, with a twelve-branch `if/elseif` returning a fresh table literal per call. MiniGM flattens it to static data.

### Regrouping

AzerothAdmin's twelve branches split Eastern Kingdoms north/south and Northrend by faction — how its author browsed, not how you look a place up. They were merged into eight:

| Upstream | → | MiniGM |
|---|---|---|
| `EK_N`, `EK_S` | → | Eastern Kingdoms |
| `K` | → | Kalimdor |
| `Ou` | → | Outland |
| `N_A`, `N_H` | → | Northrend |
| `I_EK`, `I_K`, `I_O`, `I_N` | → | Dungeons & Raids |
| `BG` | → | Battlegrounds |
| `OT` → the 5 transport lists | → | Flight Masters *(numeric sort prefix stripped)* |
| `OT` → the rest | → | Other |

Merging `N_A` + `N_H` collapses six zones that existed in both faction branches (Borean Tundra, Crystal Song Forest, Dragonblight, Grizzly Hills, Howling Fjord, Storm Peaks). No locations were lost — the location names within them did not collide.

### The one dropped row

1,307 source rows produce 1,306 entries. **Naxxramas** appears in both `I_EK` (line 1321) and `I_N` (line 1479) — the same instance, same map 533, twelve yards apart. Keeping one is correct.

### The nine repairs

Nine coordinate strings in the upstream data are malformed and would have failed on the server. Each was repaired and recorded in the generated file's header:

| Zone | Location | Problem |
|---|---|---|
| Burning Steppes | Ruins of Thaurissan | `133.010.437` — stray period |
| Azshara | The Shattered Strand | z truncated, map id missing → Kalimdor (1) |
| Desolace | Sar'theris Strand | `.go xyz .go xyz …` — command prefix duplicated |
| Durotar | Deadeye Shore | map id missing → Kalimdor (1) |
| The Barrens | Fray Island | `-4325,567383` — comma as decimal point |
| The Barrens | Razorfen Downs Entrance | `-2110/74385` — slash as decimal point |
| Blade's Edge Mountains | Bash'ir Landing | `3751.623751.620117` — x double-pasted |
| Zul'Drak | Dubra'jin | tab inside the coordinate list |
| Other | Ortell's Hideout | doubled space inside the coordinate list |

Every one of the 1,306 strings was then validated in a Lua 5.1 runtime against `^%.go xyz <x> <y> <z> <map>$`. Zero malformed.

---

## Regenerating

The data file is **generated — do not hand-edit it.** Its header says so. Edits are lost the next time it is rebuilt, and hand-edits are how malformed coordinates get in.

To rebuild it from an AzerothAdmin checkout, the generator:

1. Walks `Data/TeleportTable.lua` line by line, tracking the current `cont ==` branch.
2. Treats `["Name"] = {` at **any** indent as a zone header — upstream indents zones with four spaces, two spaces *and* tabs, so a fixed-indent match silently drops ~160 rows.
3. Treats `["Name"] = "…"` as a location.
4. Applies the nine repairs by line number, normalises internal whitespace, and validates the result is exactly `.go xyz` + four numbers.
5. Maps the branch to a group per the table above, sorts zones and locations alphabetically, and writes `MiniGMTeleOrder` then `MiniGMTele`.

If you regenerate against a newer AzerothAdmin, **re-check the repair line numbers** — they are positional and will drift if upstream changes.

---

## Adding your own locations

The cleanest way is a small file of your own loaded after `TeleportDB.lua`, so regenerating never clobbers it:

```lua
-- Tele/MyLocations.lua   (add to the .toc after Tele\TeleportDB.lua)
MiniGMTele["Other"]["My Places"] = {
    ["Secret Base"] = ".go xyz 1234.5 -678.9 42.0 1",
}
```

Stand where you want the location and use `.gps` to read the coordinates and map id.

If you add a **new group**, it also needs an entry in `MiniGMTeleOrder` or it will not appear in the picker.

---

## Zone-name matching

The picker opens on the zone you are standing in by matching `GetRealZoneText()` against the zone keys — exact first, then case-insensitive.

These keys were typed by hand upstream and do not always agree with what the client reports. On a miss, MiniGM says `current zone not in the directory` and opens on the first group. It is cosmetic; everything remains browsable and searchable.

If a zone you use regularly misses, the fix is a normalisation map from client zone text to data key.
