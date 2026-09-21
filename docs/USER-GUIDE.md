# MiniGM — User Guide

Every control, what it sends, and what stops it.

**Contents**
1. [The panel](#1-the-panel)
2. [HUD tab — Movement](#2-hud-tab--movement)
3. [HUD tab — Survival](#3-hud-tab--survival)
4. [HUD tab — Group](#4-hud-tab--group)
5. [HUD tab — Combat](#5-hud-tab--combat)
6. [HUD tab — Character](#6-hud-tab--character)
7. [HUD tab — Bots](#7-hud-tab--bots)
8. [Tele tab](#8-tele-tab)
9. [The minimap icon](#9-the-minimap-icon)
10. [Slash commands](#10-slash-commands)
11. [What is remembered](#11-what-is-remembered)

---

## 1. The panel

`/mgm` shows and hides it. There is no minimap icon until you enable one (§9).

| Control | Where | Does |
|---|---|---|
| Drag | anywhere on the frame | move it; position is saved |
| `-` / `+` | top-left | collapse to the title bar and back |
| Minimap icon | checkbox under the title | show/hide the minimap button |
| `X` | top-right | hide the panel |
| Size grip | bottom-right corner | drag to resize |
| Tabs | below the bottom border | HUD · Tele |

**Resizing scales rather than resizes.** Every widget sits at a fixed pixel offset, so stretching the frame would leave the contents clustered in one corner. Dragging the grip changes the frame's scale, which keeps the proportions by definition. Clamped to 0.5–2.0; the top-left stays pinned while you drag.

The panel and the teleport picker have **separate** sizes and positions. Resizing one does not touch the other.

---

## 2. HUD tab — Movement

### Speed *n*×  ·  Speed normal

Sends `.modify speed all <n>` (and `1` for normal) via a **secure macro**:

```
/target [noexists] player
/say .modify speed all 1.5
```

The `/target [noexists] player` means *if nothing is targeted, target yourself* — so with no target it speeds you up, and with a player or bot selected it speeds **them** up instead. That is deliberate: it is how you hand a bot a speed boost.

- Default multiplier is **1.5**. Change it with `/mgm runspeed <n>` (0.1–50, the server's own limit). The button text updates.
- `all` covers run, swim and fly rates. **The fly rate is ignored in the air** — see Fly ON.
- Resets on relog.
- **Blocked in combat.** Blizzard forbids `/target` from a macro during combat; the addon says so when you click.

### Fly ON

Sends two commands:

```
.gm fly on
.modify mount 28652 4.65
```

**Why the second one.** `.gm fly on` only calls `SetCanFly()`. Every flight speed rate — `fly`, `all`, `swim` — is accepted by the server and then *ignored in the air*. The client only honours flight speed while a **mount aura** is active, which is what `.modify mount <displayID> <speed>` applies. This was established by elimination during testing; there is no server config for it.

`.modify mount` is temporary — an aura and a model, not a learned mount. Your riding progression is untouched.

- `4.65` = 1.5× the fastest WotLK mount (310%). `/mgm flyspeed <n>` changes it.
- `28652` = Armored Ebon Gryphon. `/mgm flymount <displayID>` changes it.
- **Refuses if you have someone else targeted**, because `.modify mount` would land on them.

> **🔴 Never use displayID `28082`** (flying carpet). It crashed a worldserver at the moment it was applied. The server was restarted by systemd 15 seconds later and roughly 15 minutes of unsaved play was lost. The same speed value with `28652` works fine, so the model was the trigger, not the number.

**The watchdog.** The mount aura can be stripped — indoors, in instances, sometimes in combat. Every 3 seconds MiniGM checks `IsMounted()`. If the aura is gone it waits out combat, re-applies up to 3 times, then gives up, tells you, and guarantees plain `.gm fly on` so you at least do not fall. Zoning or relogging clears GM fly server-side, so the watchdog stands down on `PLAYER_ENTERING_WORLD`.

### Fly OFF

`.dismount` then `.gm fly off`, and stops the watchdog. Also refuses if you have someone else targeted.

---

## 3. HUD tab — Survival

### God ON / God OFF

`.cheat god on` / `.cheat god off`. **Always applies to you** regardless of target — that is the server's behaviour, not the addon's. Resets on relog.

### Full heal

A secure macro that self-targets and sends your **actual** maximum health:

```
/target [noexists] player
/say .modify hp 43210
/say .modify mana 12345      (only if you are a mana user)
```

> **`.modify hp <n>` calls `SetMaxHealth(n)` — it sets maximum health, it does not heal you.** A naive `.modify hp 999999` is a max-HP hack, not a heal. Sending your real `UnitHealthMax` restores you without changing anything. The macro is rebuilt on `UNIT_MAXHEALTH` and `PLAYER_LEVEL_UP` so the number stays correct as you level.

Mana is only added for `UnitPowerType("player") == 0`. Note `UnitManaMax` does not exist in 3.3.5a; this uses `UnitPowerMax(unit, 0)`.

Blocked in combat, like all secure macro buttons.

### Revive target

`.revive <name>` on the selected player or bot. Refuses with nothing targeted.

---

## 4. HUD tab — Group

### Revive all

A secure macro:

```
/tar player
/s .revive
/p revive
```

Revives **you** with the GM command and tells the group's bots to revive with the playerbot command. Two different mechanisms in one click, because bots and players respond to different things.

### Maint / Gear

Sends three playerbot commands to party or raid chat, 0.4 s apart:

```
maintenance
autogear
nc -loot
```

Refuses if you are not grouped, since nothing would hear it.

> **`autogear` never sends `reset`.** Plain `autogear` swaps a slot only when the new item scores ≥ 1.2× the old one, and the replaced item is stored to the bot's bags — nothing is destroyed. `autogear reset` calls `DestroyEquippedGear` and **destroys all worn gear**. MiniGM never sends it. Free up bag slots on the bot first, or slots get skipped.

---

## 5. HUD tab — Combat

### Kill target

`.die`. Three guards, in order:

1. Refuses with nothing targeted.
2. Refuses if the target is **you**.
3. Refuses if the target is a **friendly player or bot**.

So it kills hostile NPCs and hostile players, and nothing else by accident.

### Cheat status

`.cheat status`. Prints what the **server** believes is enabled. Worth using after a relog, since god, fly and speed all reset and the buttons cannot know that.

---

## 6. HUD tab — Character

### Modify Char

Opens a small panel with two fields, acting on your **selected character**.

**New level → `.character level <name> <n>`**

- Requires a whole number ≥ 1.
- **Will not de-level.** `.character level` lowers as happily as it raises; MiniGM refuses if the new level is below the target's current level, and says so.
- Silently capped at 80 by the server; MiniGM caps at 80 itself and tells you.

**Add gold → `.modify money <copper>`**

- `.modify money` **adds** — it does not set. It acts on your selected player.
- Accepts decimals: `1.5` = 1g 50s. Converted to copper and echoed as a `g/s/c` breakdown before sending.
- Positive only, capped at 100,000 gold per click.

**Targeting yourself requires typing `Accept`** — case-sensitive — in a confirmation box. That is the guard against levelling or paying yourself by a misclick.

The panel's title shows the target's name and level live, and updates on `PLAYER_TARGET_CHANGED`.

---

## 7. HUD tab — Bots

Requires **mod-playerbots**.

### Add bot

Opens a class list. Clicking one sends `.playerbots bot addclass <class>` — a disposable bot at **your** level.

### Add alt

Lists every character you have logged into on this account. Clicking one sends `.playerbots bot add <name>`.

- The list builds itself: MiniGM records each character's name on login. You never type them.
- **Right-click** a name to forget it.
- **Type a name…** at the bottom opens a prompt for a name you have not logged into.
- `/mgm addalt A,B,C` seeds the list by hand; `/mgm forgetalt <Name>` removes one.

Altbots are your real characters — they keep XP, gold and loot earned while grouped with you.

### Remove bot

`.playerbots bot remove <name>`, pre-filled with your current target. Works for both altbots and addclass bots. Leaving the group does **not** log a bot out; this does.

---

## 8. Tele tab

### Step 1 — choose who

| Button | What happens |
|---|---|
| **Self** | `.go xyz …`. Goes immediately, no confirmation. |
| **Target** | `.go xyz …`, then `summon` whispered to the target **and** `.summon <name>`. Confirms first. |
| **Party** | `.go xyz …`, then `summon` to **party chat**. Confirms first. |
| **Raid** | `.go xyz …`, then `summon` to **raid chat**. Confirms first. |

> **Why it works this way.** `.go xyz #x #y [#z [#mapid [#orientation]]]` teleports **you and nobody else** — AzerothCore has no target or group form of it. The commands that *can* move someone else (`.tele name`, `.tele group`) take a named location from the server's `game_tele` table, not coordinates, so they cannot be driven from a coordinate list. MiniGM therefore teleports you first and then summons.
>
> **And bots ignore `.summon`.** It is a GM command aimed at players: the server accepts it and prints "You are summoning [X]" while the bot stays exactly where it was. Playerbots obey mod-playerbots' own `summon` command in party or raid chat — which has the bonus of moving the **entire group in one message** instead of one command per member. Target sends both forms because it cannot know whether you targeted a bot or a human.
>
> **A human in your party will not follow the chat `summon`.** Bring humans individually with **Target**.

### Step 2 — pick a location

The picker opens centred, on the zone you are standing in.

| Column | Contents |
|---|---|
| **Continent Selection** | 8 groups, with a location count each |
| **Zone Selection** | zones in the selected group, with a count each |
| **Zone: *name*** | locations in the selected zone |

Every column stays clickable — the current-zone preselection is a starting point, not a restriction. The selected row in each column is shown in **red**.

**Search** filters all 1,306 locations by name across every zone at once, showing the owning zone in grey beside each match. Clearing the box returns to browsing.

Clicking a location fires the teleport. The picker closes.

The picker is a separate window: its own position, its own size grip, its own scale. **Esc** closes it.

If your current zone is not in the directory, MiniGM says so and opens on the first group. Zone names in the data were typed by hand and do not always match `GetRealZoneText()` exactly.

The 8 groups: Eastern Kingdoms (391) · Kalimdor (337) · Outland (276) · Northrend (53) · Dungeons & Raids (91) · Battlegrounds (21) · Flight Masters (87) · Other (50). See [TELEPORT-DATA.md](TELEPORT-DATA.md).

---

## 9. The minimap icon

Off by default. Tick **Minimap icon** under the panel's title, or `/mgm minimap`.

| Action | Does |
|---|---|
| Left-click | show / hide the panel |
| Shift-drag | move it around the minimap |
| Shift-right-click | hide the icon |

Angle and on/off state are saved. If you shift-right-click it away, `/mgm minimap` or the checkbox brings it back.

Hand-rolled trigonometry against the minimap centre — no LibDBIcon, so the addon stays dependency-free.

---

## 10. Slash commands

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

`titlefit` exists because Blizzard's header art has decorative end-caps that scale *with* the texture, so the usable span between them is only about 55% of its width. The header is sized as `titleWidth × n + 16`. If you change the title text and it overflows the brackets, raise `n`.

---

## 11. What is remembered

Stored in `MiniGMDB`, saved to `WTF\Account\<ACCOUNT>\SavedVariables\MiniGM.lua`.

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
- It is `SavedVariables`, not `SavedVariablesPerCharacter`, so **settings are shared across every character on the account**. Changing that is a one-word `.toc` edit.

`/mgm reset` clears position and size for both windows. Nothing else clears itself.
