# MiniGM — Master Guide

**Everything about MiniGM in one self-contained file.**

This document is written to be given to a large language model. Upload it to Claude, ChatGPT or similar and ask your question in plain English — *"how do I get my bots to follow me into Karazhan"*, *"why is my flight speed being ignored"*, *"what does the Kill button actually send"*, *"how do I add my own teleport locations"*. It contains enough context to answer without guessing, including the parts that are counter-intuitive.

It is also perfectly readable by a human. Nothing here assumes you write Lua.

- **Addon:** MiniGM by Parriah
- **Version:** 1.2.0
- **Target:** World of Warcraft 3.3.5a (WotLK, build 12340), Interface 30300
- **Server:** AzerothCore
- **Licence:** GPLv3
- **Dependencies:** none
- **Built with:** AI assistance (Claude). The design, testing and bug reports are the author's; the Lua and these docs were machine-generated.

---

## Table of contents

1. [What MiniGM is and is not](#1-what-minigm-is-and-is-not)
2. [How it works — the one thing to understand](#2-how-it-works--the-one-thing-to-understand)
3. [Requirements](#3-requirements)
4. [Installing](#4-installing)
5. [The panel](#5-the-panel)
6. [HUD tab — every button](#6-hud-tab--every-button)
7. [Tele tab — teleporting](#7-tele-tab--teleporting)
8. [The minimap icon](#8-the-minimap-icon)
9. [Slash commands](#9-slash-commands)
10. [Complete command inventory](#10-complete-command-inventory)
11. [The teleport database](#11-the-teleport-database)
12. [What gets remembered](#12-what-gets-remembered)
13. [Troubleshooting](#13-troubleshooting)
14. [Known traps and gotchas](#14-known-traps-and-gotchas)
15. [How the addon is built](#15-how-the-addon-is-built)
16. [Modifying it](#16-modifying-it)
17. [FAQ](#17-faq)
18. [Glossary](#18-glossary)
19. [Credits and licence](#19-credits-and-licence)

---

## 1. What MiniGM is and is not

**MiniGM is a GM's player companion.** It is for someone who runs a small private AzerothCore realm *and plays on it* — who is a player most of the time and a Game Master occasionally.

It is **not** a full admin suite. It deliberately has no NPC spawning, no gameobject editing, no ticket handling, no item/spell lookup browser, no account management and no server control. If you need those, use [AzerothAdmin](https://github.com/superstyro/AzerothAdmin), which is excellent and which MiniGM's teleport data comes from.

What MiniGM has instead is the dozen things a playing GM reaches for every session — flight, speed, healing, reviving, killing a stuck mob, fixing an alt's level, managing a bot party, and getting somewhere — in a small window that stays out of the way and remembers everything.

### Design principles, stated so you can predict its behaviour

1. **Client-only.** No server module, no addon-message protocol, nothing to install on the realm.
2. **No libraries.** Two Lua files and a `.toc`. No Ace3, no LibStub, no LibDBIcon.
3. **No chat scraping.** MiniGM never hooks `AddMessage` or filters chat, so it cannot read the server's replies. This is why there is no lookup browser. It is deliberate — hooking chat frames is how addons end up swallowing other addons' messages.
4. **Guard before sending, not after.** Destructive actions refuse up front rather than asking afterwards.
5. **Everything is remembered.** Positions, sizes, tab, minimap, alts, speeds.

---

## 2. How it works — the one thing to understand

**Every button sends an ordinary chat command, exactly as if you had typed it yourself.**

Clicking "God ON" puts `.cheat god on` into `/say`. The server parses it, checks your gmlevel, and acts. MiniGM has no privileges of its own and grants you nothing you did not already have.

Three consequences that explain almost every question people have:

- **If a button appears to do nothing, your gmlevel is too low for that command.** Type `.commands` in game to list what your account may use, and `.help <command>` for one. This is a server permission, not an addon fault.
- **Everything goes out in `/say`.** Anyone standing near you can read your GM commands. There is no hidden channel for this in 3.3.5a.
- **MiniGM cannot see the result.** It sends and moves on. It does not know whether the command worked. That is why "Cheat status" exists — it asks the *server* what it believes is enabled.

Outgoing messages are queued at **one per 0.4 seconds** (see §14). Every one is echoed to your chat frame in gold, so you can always see exactly what was sent.

---

## 3. Requirements

| | |
|---|---|
| **Client** | WoW **3.3.5a** (build 12340). The `.toc` declares Interface **30300**. Do not change it. This project does not link to, host or help you obtain a game client — that is yours to sort out. |
| **Server** | **AzerothCore.** Other WotLK cores (TrinityCore, MaNGOS forks) use different command syntax and are untested. |
| **gmlevel** | **2** for almost everything. **3** for `.character level` only. |
| **Dependencies** | None. |
| **Optional** | [mod-playerbots](https://github.com/liyunfan1223/mod-playerbots) for the Bots section and Party/Raid teleport. Everything else works without it. |

### Recommended realm hardware

MiniGM costs nothing itself. These are specs for the server it assumes you run, from a live 3.3.5a + mod-playerbots + AH-bot realm:

| | Minimum | Comfortable |
|---|---|---|
| CPU | 2 cores | 4 cores (i5/i7 7th gen or better). Worldserver is largely single-threaded — clock beats cores. |
| RAM | 8 GB | **16 GB. Memory is the limit, not CPU.** Worldserver peaked ~6 GB during mass bot login alongside MySQL's 4 GB pool. |
| Disk | 40 GB SSD | 256 GB SSD. Databases plus dated backup sets add up. |
| OS | any modern Linux | Ubuntu Server LTS |

Random-bot count drives memory. 50–200 is comfortable on 16 GB. Raise `MaxRandomBots` in steps of ~50, watching `free -h` under load and the log for *"World update time exceeded"*.

You do not need to port-forward a private realm. A mesh VPN (Tailscale, WireGuard) with a subnet router advertising the realm's `/32` gives you remote play with no inbound ports and no client changes.

---

## 4. Installing

**Easiest:** download the zip from the repository's Releases page and extract it into `<World of Warcraft>\Interface\AddOns\`. It is already packaged with the right folder name.

From source, the folder must be named exactly `MiniGM` and sit directly inside `Interface\AddOns\`:

```
<World of Warcraft>\Interface\AddOns\MiniGM\
    MiniGM.toc
    MiniGM.lua
    Tele\
        TeleportDB.lua
```

The `Tele` subfolder is **not optional** — it holds the teleport directory and the `.toc` loads it before the main file.

A common mistake is ending up with `AddOns\MiniGM\MiniGM\MiniGM.toc` after unzipping. WoW will not find that.

```powershell
$src = "<path to the MiniGM folder you downloaded>"
$dst = "C:\Games\<YourClient>\Interface\AddOns\MiniGM"
New-Item -ItemType Directory -Force -Path "$dst\Tele" | Out-Null
Copy-Item -Force "$src\MiniGM.lua","$src\MiniGM.toc" $dst
Copy-Item -Force "$src\Tele\TeleportDB.lua" "$dst\Tele"
```

`LICENSE`, `README.md`, `CHANGELOG.md` and `docs\` do not need copying — WoW ignores them.

**Restart the client fully.** A new addon is not found by `/reload`. At character select, check **AddOns** and confirm MiniGM is listed and ticked.

**Verify.** On login you should see `MiniGM: v1.2.0 loaded. /mgm to show/hide.` Type `/mgm`, click **Tele**, and it should report `loaded - 1306 locations in 143 zones`. If it says `FAILED: Tele\TeleportDB.lua did not load` in red, the subfolder did not copy.

**Updating.** A `.lua`-only change needs `/reload`. A `.toc` change, or adding/removing a file, needs a full client restart. Settings live in `WTF\Account\<ACCOUNT>\SavedVariables\MiniGM.lua` and survive updates.

**Uninstalling.** Delete `Interface\AddOns\MiniGM\`. To remove settings too, also delete the SavedVariables file above and its `.bak`, with the game closed.

---

## 5. The panel

`/mgm` shows and hides it. There is no minimap icon until you enable one (§8).

| Control | Where | Does |
|---|---|---|
| Drag | anywhere on the frame | move it; position saved |
| `-` / `+` | top-left | collapse to the title bar and back |
| **Minimap icon** checkbox | centred under the title | show/hide the minimap button |
| `X` | top-right | hide the panel |
| **Size grip** | bottom-right corner | drag to resize |
| Tabs | below the bottom border | **HUD** · **Tele** |

**Resizing scales rather than resizes.** Every widget sits at a fixed pixel offset, so stretching the frame would leave contents clustered in a corner. Dragging the grip changes the frame's *scale*, keeping proportions by definition. Clamped 0.5–2.0; the top-left stays pinned while you drag.

**The panel and the teleport picker are independent.** Separate size, separate position, separate grip. Resizing one does not touch the other. `/mgm scale <n>` and `/mgm telescale <n>` set them exactly.

The tabs anchor to the frame's bottom edge, so they move up with it when collapsed and stay usable.

---

## 6. HUD tab — every button

### Movement

#### Speed *n*× · Speed normal

Sends `.modify speed all <n>` (or `1`) via a **secure macro**:

```
/target [noexists] player
/say .modify speed all 1.5
```

`[noexists]` means *target yourself only if nothing is targeted*. So with no target it speeds **you** up; with a player or bot selected it speeds **them** up. That is deliberate — it is how you hand a bot a speed boost.

- Default **1.5**. Change with `/mgm runspeed <n>` (0.1–50, the server's own limit). Button text updates.
- `all` covers run, swim and fly rates. **The fly rate is ignored in the air** — see Fly ON.
- Resets on relog.
- **Blocked in combat** (see §14).

Useful values: `1.0` normal · `1.6` ≈ 60% mount · `2.0` ≈ epic mount.

#### Fly ON

Sends two commands:

```
.gm fly on
.modify mount 28652 4.65
```

**Why two.** `.gm fly on` only calls `SetCanFly()`. Every flight speed rate is accepted by the server and then **ignored in the air**. The client only honours flight speed while a **mount aura** is active, which is what `.modify mount <displayID> <speed>` applies. There is no server config for this.

`.modify mount` is temporary — an aura and a model, not a learned mount. Riding progression is untouched.

- `4.65` = 1.5× the fastest WotLK mount (310%). `/mgm flyspeed <n>` changes it.
- `28652` = Armored Ebon Gryphon. `/mgm flymount <displayID>` changes it.
- **Refuses if you have someone else targeted**, because `.modify mount` would land on them.

Rate reference: `1.0` base flight (7.0 y/s) · `1.5` slow mount · `2.8` epic (280%) · `3.1` fastest WotLK (310%) · `4.65` 1.5× that.

> 🔴 **Never use displayID `28082`** (flying carpet). It crashed a worldserver the instant it was applied; systemd restarted it 15 seconds later and ~15 minutes of unsaved play was lost. The same speed with `28652` is fine — the model was the trigger.

**The watchdog.** The mount aura can be dropped, though not predictably — flying inside the Stormwind auction house held fine. Every 3 seconds MiniGM checks `IsMounted()`. If the aura is gone it waits out combat, re-applies up to 3 times, then gives up, tells you, and guarantees plain `.gm fly on` so you do not fall. Zoning or relogging clears GM fly server-side, so the watchdog stands down on `PLAYER_ENTERING_WORLD`.

#### Fly OFF

`.dismount` then `.gm fly off`, and stops the watchdog. Also refuses if someone else is targeted.

### Survival

#### God ON / God OFF

`.cheat god on` / `off`. **Always applies to you** regardless of target — that is the server's behaviour. Resets on relog.

#### Full heal

A secure macro sending your **actual** maximum:

```
/target [noexists] player
/say .modify hp 43210
/say .modify mana 12345      (mana users only)
```

> **`.modify hp <n>` calls `SetMaxHealth(n)`. It sets maximum health — it does not heal.** The `.modify hp 999999` in old macro guides is a max-HP hack. Sending your real `UnitHealthMax` restores you and changes nothing.

The macro is rebuilt on `UNIT_MAXHEALTH` and `PLAYER_LEVEL_UP` so the number stays correct as you level. Mana is added only for `UnitPowerType("player") == 0`.

#### Revive target

`.revive <name>` on the selected player or bot. Refuses with nothing targeted.

### Group

#### Revive all

A secure macro:

```
/tar player
/s .revive
/p revive
```

Revives **you** with the GM command and tells the group's **bots** to revive with the playerbot command. Two mechanisms in one click, because bots and players respond to different things.

#### Maint / Gear

Sends three playerbot commands to party or raid chat, 0.4 s apart:

```
maintenance
autogear
nc -loot
```

Refuses if you are not grouped. `maintenance` repairs, refills reagents and re-buffs. `autogear` upgrades from bags. `nc -loot` disables the bots' non-combat looting strategy.

> **`autogear` never sends `reset`.** Plain `autogear` swaps a slot only when the new item scores ≥ 1.2× the old, and stores the replaced item to bags — nothing is destroyed. **`autogear reset` calls `DestroyEquippedGear` and destroys all worn gear.** MiniGM never sends it. Free bag slots on the bot first, or slots get skipped.

### Combat

#### Kill target

`.die`, with three guards in order:

1. Refuses with nothing targeted.
2. Refuses if the target is **you**.
3. Refuses if the target is a **friendly player or bot**.

It will still kill a hostile player.

#### Cheat status

`.cheat status`. Prints what the **server** believes is enabled. Worth using after a relog, since god, fly and speed all reset and the buttons cannot know that.

### Character

#### Modify Char

Opens a panel with two fields, acting on your **selected character**. The title shows the target's name and level live.

**New level → `.character level <name> <n>`**
- Whole number ≥ 1.
- **Will not de-level.** `.character level` lowers as happily as it raises; MiniGM refuses anything below the target's current level.
- Capped at 80 (the server caps silently; MiniGM caps and tells you).
- The only command here needing **gmlevel 3** by default.

**Add gold → `.modify money <copper>`**
- `.modify money` **adds**, it does not set, and acts on your selected player.
- Decimals accepted: `1.5` = 1g 50s. Echoed as a g/s/c breakdown before sending.
- Positive only, capped at 100,000 gold per click.

**Targeting yourself requires typing `Accept`** — case-sensitive. That is the guard against levelling or paying yourself by a misclick.

### Bots

Requires mod-playerbots.

#### Add bot
Class list → `.playerbots bot addclass <class>`. A disposable bot at **your** level. Classes: warrior, paladin, hunter, rogue, priest, dk, shaman, mage, warlock, druid.

#### Add alt
Lists every character you have logged into on this account → `.playerbots bot add <name>`.

- **The list builds itself.** MiniGM records each character's name on login. You never type them.
- **Right-click** a name to forget it.
- **Type a name…** at the bottom prompts for one you have not logged into.
- `/mgm addalt A,B,C` seeds the list by hand; `/mgm forgetalt <Name>` removes one.

Altbots are your real characters — they keep XP, gold and loot earned while grouped with you.

#### Remove bot
`.playerbots bot remove <name>`, pre-filled with your target. Works for altbots and addclass bots. Leaving the group does **not** log a bot out; this does.

---

## 7. Tele tab — teleporting

### Step 1 — choose who

| Button | Sends |
|---|---|
| **Self** | `.go xyz …` — immediately, no confirmation |
| **Target** | `.go xyz …`, then `summon` whispered to the target **and** `.summon <name>`. Confirms first. |
| **Party** | `.go xyz …`, then `summon` to **party chat**. Confirms first. |
| **Raid** | `.go xyz …`, then `summon` to **raid chat**. Confirms first. |

**Why it works this way — this is the most important thing in this section.**

`.go xyz #x #y [#z [#mapid [#orientation]]]` teleports **you and nobody else.** AzerothCore has no target or group form of it. The commands that *can* move someone else — `.tele name <player> <location>` and `.tele group <location>` — take a **named location from the server's `game_tele` table**, not coordinates, so they cannot be driven from a coordinate list. MiniGM therefore teleports you first and then summons.

**And bots ignore `.summon`.** It is a GM command aimed at players: the server accepts it, prints *"You are summoning [X]"*, and the bot stays exactly where it was. Playerbots obey mod-playerbots' own `summon` command in party or raid chat — which has the bonus of moving the **entire group in one message** instead of one command per member.

**The reverse is also true.** A **human** in your party will not follow the chat `summon`. Target sends both forms because it cannot know whether you targeted a bot or a human. Party and Raid cannot move a human — bring humans individually with **Target**.

### Step 2 — pick a location

The picker opens centred, on the zone you are standing in.

| Column | Contents |
|---|---|
| **Continent Selection** | 8 groups, with a location count each |
| **Zone Selection** | zones in the selected group, with a count each |
| **Zone: *name*** | locations in the selected zone |

Every column stays clickable — the current-zone preselection is a starting point, not a restriction. The selected row in each column is **red**.

**Search** filters all 1,306 locations by name across every zone at once, showing the owning zone in grey beside each match. Clearing the box returns to browsing.

Clicking a location fires the teleport and the picker closes. **Esc** also closes it.

The picker is a separate window with its own position, size grip and scale.

If your current zone is not in the directory, MiniGM says so and opens on the first group. Zone names in the data were typed by hand and do not always match what the client reports. It is cosmetic — everything stays browsable and searchable.

---

## 8. The minimap icon

Off by default. Tick **Minimap icon** under the panel's title, or `/mgm minimap`.

| Action | Does |
|---|---|
| Left-click | show / hide the panel |
| Shift-drag | move it around the minimap |
| Shift-right-click | hide the icon |

Angle and on/off state are saved. If you shift-right-click it away, `/mgm minimap` or the checkbox brings it back.

Hand-rolled trigonometry against the minimap centre — no LibDBIcon, so the addon stays dependency-free. Positioned by angle at radius 80.

---

## 9. Slash commands

`/mgm` and `/minigm` are the same command.

| Command | Range | Default | Does |
|---|---|---|---|
| `/mgm` | | | show / hide |
| `/mgm help` | | | print everything with current values |
| `/mgm minimap` | | off | toggle the minimap icon |
| `/mgm scale <n>` | 0.5–2.0 | 1.0 | panel size |
| `/mgm telescale <n>` | 0.5–2.0 | 1.0 | picker size |
| `/mgm titlefit <n>` | 1.0–4.0 | 1.9 | header art width ÷ title width |
| `/mgm reset` | | | both windows back to centre at 1.0 |
| `/mgm alts` | | | list remembered alts |
| `/mgm addalt <A[,B]>` | | | add names to the alt list |
| `/mgm forgetalt <Name>` | | | remove one |
| `/mgm runspeed <n>` | 0.1–50 | 1.5 | ground speed multiplier |
| `/mgm flyspeed <n>` | 0.1–50 | 4.65 | flight speed multiplier |
| `/mgm flymount <id>` | | 28652 | mount displayID for fast flight |

`titlefit` exists because Blizzard's `UI-DialogBox-Header` art has decorative end-caps that scale *with* the texture, so the usable span between them is only about 55% of its width. The header is sized as `titleWidth × n + 16`. Additive padding cannot work — it shrinks the gap as fast as it widens the art.

---

## 10. Complete command inventory

Audit this before trusting the addon on a realm.

### GM commands (sent to `SAY`)

| Command | Sent by | Acts on | gmlevel | Risk |
|---|---|---|---|---|
| `.go xyz <x> <y> <z> <map>` | Tele — any | **you only** | 2 | low |
| `.gm fly on` / `off` | Fly ON / OFF | selected player, else you | 2 | low |
| `.dismount` | Fly OFF | you | 2 | low |
| `.modify speed all <n>` | Speed buttons | selected player, else you | 2 | low |
| `.modify mount <id> <speed>` | Fly ON | you | 2 | **see 28082** |
| `.modify hp <n>` | Full heal | selected player | 2 | **sets MAX hp** |
| `.modify mana <n>` | Full heal | selected player | 2 | sets max mana |
| `.modify money <copper>` | Modify Char → Add | selected player | 2 | **adds gold** |
| `.cheat god on` / `off` | God ON / OFF | always you | 2 | low |
| `.cheat status` | Cheat status | you | 2 | none, read-only |
| `.revive <name>` | Revive target | named player | 2 | low |
| `.revive` | Revive all macro | you | 2 | low |
| `.die` | Kill target | selected unit | 2 | **kills** |
| `.summon <name>` | Tele → Target | named player | 2 | moves a player |
| `.character level <name> <n>` | Modify Char → Set | named character | **3** | **changes level** |
| `.playerbots bot add <name>` | Add alt | your alt | varies | low |
| `.playerbots bot addclass <class>` | Add bot | new bot | varies | low |
| `.playerbots bot remove <name>` | Remove bot | that bot | varies | low |

### Playerbot chat commands

Not GM commands — plain chat that mod-playerbots parses. Work at gmlevel 0 and only affect bots **you** own.

| Text | Channel | Sent by | Does |
|---|---|---|---|
| `summon` | PARTY / RAID | Tele → Party / Raid | every bot in the group teleports to you |
| `summon` | WHISPER | Tele → Target | that one bot teleports to you |
| `revive` | PARTY | Revive all macro | group's bots revive |
| `maintenance` | PARTY / RAID | Maint / Gear | bots repair, refill, re-buff |
| `autogear` | PARTY / RAID | Maint / Gear | bots upgrade gear from bags |
| `nc -loot` | PARTY / RAID | Maint / Gear | disables non-combat looting |

### What MiniGM never sends

Stated explicitly, because these are the neighbouring commands that do real damage:

- `autogear reset` — destroys all of a bot's worn gear
- `.character deleted restore` — no character-recovery commands at all
- `.ban`, `.unban`, `.kick`, `.mute` — no moderation
- `.npc …`, `.gobject …` — no world editing
- `.reload`, `.server …` — no server control
- `.account …` — no account management, and nothing that could put a password in chat

### Secure macro buttons

Four buttons are `SecureActionButtonTemplate` macros because they must act on **you** when nothing is targeted:

| Button | Macro text |
|---|---|
| Speed *n*× | `/target [noexists] player` + `/say .modify speed all <n>` |
| Speed normal | `/target [noexists] player` + `/say .modify speed all 1` |
| Full heal | `/target [noexists] player` + `/say .modify hp <max>` (+ mana) |
| Revive all | `/tar player` + `/s .revive` + `/p revive` |

---

## 11. The teleport database

`Tele/TeleportDB.lua` — **1,306 locations · 143 zones · 8 groups · 83 map ids · ~100 KB**.

### Schema

```lua
MiniGMTeleOrder = { "Eastern Kingdoms", "Kalimdor", … }   -- fixes display order

MiniGMTele = {
  ["Eastern Kingdoms"] = {
    ["Elwynn Forest"] = {
      ["Goldshire"] = ".go xyz -9464.09 62.5605 56.0796 0",
    },
  },
}
```

`MiniGMTele[group][zone][location]` → **the finished GM command.** The value is not coordinates to assemble; it is the literal string sent to the server. Nothing is parsed at runtime.

`MiniGMTeleOrder` exists because Lua's `pairs()` has no defined order — the group column would shuffle every login without it.

There is **no orientation field**. Every teleport lands you facing north. The upstream data never had one.

### Contents

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

### Adding your own locations

Use a separate file loaded after `TeleportDB.lua`, so regenerating never clobbers it:

```lua
-- Tele/MyLocations.lua   (add to the .toc after Tele\TeleportDB.lua)
MiniGMTele["Other"]["My Places"] = {
    ["Secret Base"] = ".go xyz 1234.5 -678.9 42.0 1",
}
```

Stand where you want it and use `.gps` to read the coordinates and map id. A **new group** also needs an entry in `MiniGMTeleOrder` or it will not appear.

**Do not hand-edit `TeleportDB.lua`.** It is generated, its header says so, and edits are lost on the next rebuild.

### Provenance

Derived from AzerothAdmin's `Data/TeleportTable.lua` (GPLv3), regrouped from its 12 branches into 8. Nine corrupt coordinate strings were repaired (stray periods, a comma and a slash used as decimal points, two missing map ids, one double-pasted X, two whitespace faults), all recorded in the generated file's header. One duplicate was dropped — Naxxramas appeared in two branches, same map, twelve yards apart. Every remaining string was validated in a Lua 5.1 runtime against `^%.go xyz <x> <y> <z> <map>$`.

---

## 12. What gets remembered

Stored in `MiniGMDB`, written to `WTF\Account\<ACCOUNT>\SavedVariables\MiniGM.lua`.

| Key | Holds |
|---|---|
| `pos`, `scale` | panel position and size |
| `pickPos`, `pickScale` | picker position and size |
| `minimapShow`, `minimapAngle` | icon state and position |
| `alts`, `lastAlt` | the alt list |
| `runSpeed`, `flySpeed`, `flyMount` | speed settings |
| `titleFit` | header width multiplier |

Two WoW behaviours worth knowing:

- **Saved variables are written on logout or `/reload`, not on change.** A hard client crash loses whatever changed since the last write.
- It is `SavedVariables`, not `SavedVariablesPerCharacter` — **settings are shared across every character on the account.** Changing that is a one-word `.toc` edit.

`/mgm reset` clears position and size for both windows. Nothing else clears itself.

---

## 13. Troubleshooting

**The addon does not appear in the AddOns list.** The folder is named something other than `MiniGM`, is nested one level too deep, or `MiniGM.toc` is missing/renamed. The `.toc` filename must match the folder name exactly.

**"FAILED: Tele\TeleportDB.lua did not load".** The `Tele` subfolder did not copy. WoW loads it because of the `Tele\TeleportDB.lua` line in the `.toc` — note the **backslash**, which WoW requires in `.toc` load lists.

**Buttons do nothing and there is no error.** Your gmlevel is below that command's gate. `.commands` lists what you may use. This is a server permission, not an addon fault.

**"In combat: self-targeting is blocked."** Expected. See §14.

**Nothing happens for a second or two.** Everything is queued at one message per 0.4 s. If you clicked several buttons quickly, they are still draining.

**My bots didn't teleport.** Use **Party** or **Raid**, not Target, for a group of bots. If you used Target on a bot it should still work — it sends both forms. If a *human* is in the party, they will not follow; bring them with Target.

**The picker opened on the wrong continent.** Your current zone name did not match the data. MiniGM says `current zone not in the directory` and opens on the first group. Cosmetic — browse or search normally.

**A Lua error on login.** Report it with the full error text and your client build. If you are modifying the addon, syntax-check first: `luac5.1 -p MiniGM.lua`.

**My layout reset.** Saved variables are written on logout or `/reload`, not as you change things — a hard client crash loses anything since the last write. `/mgm reset` also clears both windows deliberately.

---

## 14. Known traps and gotchas

Each of these cost real debugging time.

| Trap | Reality |
|---|---|
| **Flight speed** | `.gm fly` alone ignores every speed rate. Only a **mount aura** makes flight speed apply. |
| **`.modify mount 28082`** | 🔴 Crashed a worldserver. Never use the flying carpet displayID. |
| **`.modify hp <n>`** | Sets **maximum** health. It does not heal. |
| **Bots and `.summon`** | Bots ignore it entirely. Use `summon` in party/raid chat. |
| **Humans and chat `summon`** | Humans ignore it. Use `.summon` via Target. |
| **`.go xyz`** | Moves **you only**. There is no target or group form. |
| **`autogear reset`** | Destroys all worn gear. Plain `autogear` is safe. |
| **`.character level`** | De-levels as happily as it raises. MiniGM refuses downward. |
| **`.modify money`** | **Adds**, does not set, and hits your **target**. |
| **Chat throttle** | Multiple `SendChatMessage` calls in one frame are silently dropped. Hence the 0.4 s queue. |
| **Combat lockdown** | Blizzard blocks `/target` from a macro in combat, and blocks changing macro text. The four secure buttons are inert in combat. |
| **Header art** | `UI-DialogBox-Header`'s end-caps scale with the texture — padding must be multiplicative. Hence `/mgm titlefit`. |

### 3.3.5a API differences

If you are modifying the addon, these are the ones that bite:

| Trap | Reality |
|---|---|
| `SetShown` | Does not exist. Use `Show()` / `Hide()`. |
| `UnitManaMax` | Does not exist. Use `UnitPowerMax(unit, 0)`. |
| `this`, `arg1` globals | Gone. Handlers receive `self` as the first argument; StaticPopup handlers receive the dialog. |
| Enter in a popup edit box | Needs `EditBoxOnEnterPressed`; `enterClicksFirstButton` alone is not enough. |
| Esc closing a frame | Only via `table.insert(UISpecialFrames, frameName)` — the frame must be **named**. |
| `GetStringWidth()` | Returns 0 before the first draw. Anything sizing from it must re-run at login. |
| `#` on a hash table | Undefined. Count with `for _ in pairs(t)`. Use `table.getn` on arrays. |

---

## 15. How the addon is built

```
MiniGM/
  MiniGM.toc            load order: Tele\TeleportDB.lua, then MiniGM.lua
  MiniGM.lua            the entire addon, ~1,700 lines
  Tele/TeleportDB.lua   generated data: MiniGMTele, MiniGMTeleOrder
```

Three globals are created deliberately — `MiniGMDB` and the two data tables. Everything else is file-local.

### Frame hierarchy

```
UIParent
├── MiniGMFrame ................ the panel (300 × 378)
│   ├── MiniGMCollapse, MiniGMMinimapCheck, MiniGMSizeGrip
│   ├── MiniGMTabhud / MiniGMTabtele   hang below the bottom border
│   ├── body
│   │   ├── hudPage             every HUD widget
│   │   └── telePage            the four who-buttons + status
│   └── MiniGMClassMenu / ModifyMenu / AltMenu   flyouts
├── MiniGMTelePicker ........... the picker (640 × 436) — a sibling, not a
│   ├── MiniGMTeleSearch        child, so it keeps its own position and scale
│   ├── MiniGMTeleListGroup / ListZone / ListLoc
│   └── MiniGMTeleSizeGrip
└── Minimap
    └── MiniGMMinimapButton
```

Flyouts are children of the panel on purpose — they should follow its drag and scale. The picker is a child of `UIParent` on purpose — it is a separate window.

### The outgoing queue

```lua
local function queueSend(text, channel, to)   -- appends to sendQueue
local function cmd(text) queueSend(text, "SAY") end
-- an OnUpdate drains one item per 0.4s via SendChatMessage(text, channel, nil, to)
```

Ordering is FIFO and guaranteed, so `.go xyz` always lands before the `summon` that follows it. Latency is real — three queued commands take 1.2 s to drain.

### Layout helpers

The HUD is a two-column flow, not absolute positioning: `section()`, `place()`, `button()`, `macroButton()`, `tip()`, with a `page` upvalue switched by `beginPage()`. Tabs are pages inside `body`; `showTab()` shows one and hides the rest.

### Scaling

`attachGrip(frame, name, setScale, savePos, tipText)` — one helper used twice, once per window. The drag converts the cursor position to UIParent units, derives a scale from the distance to the captured top-left, and re-anchors so the top-left stays pinned.

### Events

| Event | Does |
|---|---|
| `PLAYER_LOGIN` | adopt old settings → restore position → apply both scales → fit header → centre the minimap toggle → restore tab → apply minimap → remember this character → rebuild macros |
| `PLAYER_ENTERING_WORLD` | clear the fly watchdog |
| `PLAYER_TARGET_CHANGED` | refresh the Modify Char panel if open |
| `UNIT_MAXHEALTH`, `PLAYER_LEVEL_UP`, `PLAYER_REGEN_ENABLED` | rebuild macros |

---

## 16. Modifying it

**Ground rules.** Keep it dependency-free. Keep it client-only. Guard before you send. Never hook chat. If you add clickable chat links, use a private `|Hminigm:…|h` prefix and match only that — matching bare `spell:` hijacks links other people post.

**Adding a button:**

```lua
button("My thing", function()
    if not UnitExists("target") then
        say(RED .. "Nothing targeted." .. R)
        return
    end
    cmd(".whatever")
end, "Tooltip text.\nSecond line.")
```

Guard first, `cmd()` last. If it must act on you when nothing is targeted, it has to be a `macroButton`.

**Adding a tab:** create a page frame inside `body`, add its height to `TAB_H`, wrap the build in `beginPage(myPage)` / `beginPage(hudPage)`, add a branch to `showTab`, call `makeTab("mine", "Mine")`.

**Always syntax-check before loading** — a Lua error on login can lock you out of the UI:

```
luac5.1 -p MiniGM.lua
luac5.1 -p Tele/TeleportDB.lua
```

**Testing is manual, in game.** There is no harness. At minimum after any change: log in clean, check for errors, open both tabs, resize both windows, `/reload`, confirm everything returned.

**Update `CHANGELOG.md` in the same commit,** and bump both `## Version:` in the `.toc` and `local VERSION` in the `.lua` — they must match.

---

## 17. FAQ

**Is this safe to use on a realm other people play on?**
It sends only the commands in §10, all in `/say`, all gated by your gmlevel. It has no moderation, world-editing or account commands at all. But everything you do is visible to anyone nearby, and `.die` will kill a hostile player.

**Do I need mod-playerbots?**
No. The Bots section and Party/Raid teleport need it. Everything else works without it.

**Will it work on TrinityCore?**
Untested. The GM command syntax differs. The teleport data is coordinate-based so it would likely survive; the command layer would need review.

**Why is there no item or spell lookup?**
Because reading the server's replies means hooking every chat frame, which is how addons end up swallowing other addons' messages. It is a deliberate omission. AzerothAdmin does this and does it well.

**Why no minimap library?**
LibDBIcon does it properly and handles square minimaps; it is ~400 lines. This is ~40. Staying dependency-free was judged worth the trade.

**Can I use this to cheat on someone else's server?**
No — every command requires GM permissions the server grants. If you do not have them, nothing happens.

**Can I fork/modify/redistribute it?**
Yes. GPLv3. Keep it GPLv3, ship the licence, make the source available, and say what you changed. No cost, no permission needed.

**My teleport picker doesn't open on my current zone.**
Zone names were typed by hand upstream and do not always match `GetRealZoneText()`. Cosmetic; browse or search. If a zone you use often misses, that is a normalisation map worth adding.

**Why did version go from 3.4 Beta to 1.0.0?**
Everything before this was unreleased private development. 1.0.0-rc was the first public build and 1.0.0 followed it; the development history is in `CHANGELOG.md`.

---

## 18. Glossary

| Term | Meaning |
|---|---|
| **AzerothCore** | Open-source WotLK 3.3.5a server emulator |
| **gmlevel** | Account permission rank 0–3. 0 player, 1 moderator, 2 GM, 3 administrator |
| **displayID** | Numeric id of a 3D model. `.modify mount <displayID>` applies its appearance |
| **map id** | Numeric id of a map/continent/instance. 0 Eastern Kingdoms, 1 Kalimdor, 530 Outland, 571 Northrend |
| **mod-playerbots** | AzerothCore module adding AI-controlled player characters |
| **altbot** | One of your own characters logged in as a bot — keeps its gear and XP |
| **addclass bot** | A disposable generated bot at your level |
| **mount aura** | The buff a mount applies. Required for flight speed to take effect |
| **secure macro button** | A button using `SecureActionButtonTemplate`, able to target — but blocked in combat |
| **SavedVariables** | The per-account file WoW writes an addon's settings to on logout |
| **FauxScrollFrame** | The 3.3.5a scrolling-list idiom: a fixed set of rows redrawn from an offset |
| **`.toc`** | The addon manifest — interface version, saved variables, file load order |

---

## 19. Credits and licence

**MiniGM by Parriah.** GPLv3.

| Source | Contribution |
|---|---|
| [**AzerothAdmin**](https://github.com/superstyro/AzerothAdmin) — SuperStyro Dev team + Manground Dev Team | **The 1,306 teleport coordinates.** Someone stood in 1,307 places across Azeroth and wrote down where they were. The data is theirs; errors in MiniGM's handling of it are not. |
| **TrinityAdmin** and **MangAdmin** | AzerothAdmin's own ancestry, with GPLv3 notices back to the FSF, 2007 |
| [**AzerothCore**](https://www.azerothcore.org/) | The server, and the [GM command reference](https://www.azerothcore.org/wiki/gm-commands) documenting everything MiniGM sends |
| [**mod-playerbots**](https://github.com/liyunfan1223/mod-playerbots) | Every bot command, including the `summon` that makes group teleport work |

### The licence, plainly

MiniGM is GPLv3 **because it has to be**, not because it was chosen. Reusing AzerothAdmin's GPLv3 data makes MiniGM a derivative work, and derivatives carry the same licence with source available.

If you redistribute it, modified or not: keep it GPLv3, ship the full `LICENSE` text, make the source available, state that you modified it and what changed, and keep the existing notices including the header block in `MiniGM.lua`. If you only use it yourself, none of this applies — GPLv3 obligations attach to distribution, not use.

**Nothing costs money and nothing requires anyone's permission.**

Not affiliated with or endorsed by Blizzard Entertainment, AzerothCore, mod-playerbots or AzerothAdmin. World of Warcraft is a trademark of Blizzard Entertainment, Inc.
