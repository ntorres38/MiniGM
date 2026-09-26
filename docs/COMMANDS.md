# Every command MiniGM can send

MiniGM is client-only. It has no privileges of its own — it types commands into chat and the server decides. This page exists so you can audit exactly what it is capable of saying on your behalf before you trust it on a realm.

**Two channels are used:**

- **GM commands** (`.something`) go to `SAY`. They are visible to anyone standing near you.
- **Playerbot commands** (no leading dot) go to `PARTY`, `RAID` or `WHISPER`. They are ordinary chat that mod-playerbots parses.

Everything is queued at **one message per 0.4 seconds**. The 3.3.5a client silently drops multiple `SendChatMessage` calls made in the same frame.

---

## GM commands

gmlevel columns are the AzerothCore defaults; the authority on your realm is the world DB `command` table, and in game `.commands` and `.help <command>`.

| Command | Sent by | Acts on | gmlevel | Risk |
|---|---|---|---|---|
| `.go xyz <x> <y> <z> <map>` | Tele — any of the four | **you only** | 2 | low |
| `.gm fly on` / `off` | Fly ON / Fly OFF | selected player, else you | 2 | low |
| `.dismount` | Fly OFF | you | 2 | low |
| `.modify speed all <n>` | Speed *n*× / Speed normal | selected player, else you | 2 | low |
| `.modify mount <displayID> <speed>` | Fly ON | you | 2 | **see below** |
| `.modify hp <n>` | Full heal | selected player | 2 | **sets MAX hp** |
| `.modify mana <n>` | Full heal (mana users) | selected player | 2 | sets max mana |
| `.modify money <copper>` | Modify Char → Add | selected player | 2 | **adds gold** |
| `.cheat god on` / `off` | God ON / God OFF | always you | 2 | low |
| `.cheat status` | Cheat status | you | 2 | none, read-only |
| `.revive <name>` | Revive target | named player | 2 | low |
| `.revive` | Revive all (macro) | you | 2 | low |
| `.die` | Kill target | selected unit | 2 | **kills** |
| `.summon <name>` | Tele → Target | named player | 2 | moves a player |
| `.character level <name> <n>` | Modify Char → Set | named character | **3** | **changes level** |
| `.playerbots bot add <name>` | Add alt | your alt | varies | low |
| `.playerbots bot addclass <class>` | Add bot | new bot | varies | low |
| `.playerbots bot remove <name>` | Remove bot | that bot | varies | low |

### Notes on the risky ones

**`.modify mount 28082`** — 🔴 the flying carpet displayID **crashed a worldserver** the moment it was applied during testing. systemd restarted it 15 seconds later; roughly 15 minutes of unsaved play was lost across the realm. The same speed value with `28652` is fine, so the model was the trigger. MiniGM defaults to `28652`; `/mgm flymount` will accept any id, including that one. Do not.

**`.modify hp <n>`** calls `SetMaxHealth(n)`. It sets your maximum, it does not heal. MiniGM always sends your real `UnitHealthMax`, so the net effect is a full heal with no lasting change — but anyone copying this command by hand should know what it does.

**`.modify money`** *adds* rather than sets, and acts on your **selected player**, not you. MiniGM caps it at 100,000 gold per click and requires a positive number.

**`.character level`** lowers as readily as it raises. MiniGM refuses any value below the target's current level, refuses values under 1, and caps at 80. It is the only command here that needs gmlevel 3 by default.

**`.die`** refuses on no target, on yourself, and on friendly players and bots. It will still kill a hostile player.

### What MiniGM never sends

Worth stating explicitly, because these are the neighbouring commands that do real damage:

- `autogear reset` — destroys all of a bot's worn gear (`DestroyEquippedGear`). MiniGM only ever sends bare `autogear`, which stores replaced items to bags.
- `.character deleted restore` — MiniGM has no account or character-recovery commands at all.
- `.ban`, `.unban`, `.kick`, `.mute` — no moderation commands.
- `.npc …`, `.gobject …` — no world editing.
- `.reload`, `.server …` — no server control.
- `.account …` — no account management, and nothing that could put a password in chat.

---

## Playerbot chat commands

These are not GM commands. They are plain chat that mod-playerbots interprets, so they work at gmlevel 0 and only affect bots **you** own.

| Text | Channel | Sent by | Does |
|---|---|---|---|
| `summon` | PARTY / RAID | Tele → Party / Raid | every bot in the group teleports to you |
| `summon` | WHISPER | Tele → Target | that one bot teleports to you |
| `revive` | PARTY | Revive all (macro) | group's bots revive |
| `maintenance` | PARTY / RAID | Maint / Gear | **permanent:** learns weapon skills (set to max), professions/secondary skills, all class + available + special spells, spends all talent points, glyphs, enchants + gems, riding + mounts, dungeon-key reps (70+), attunement quests, pet + pet talents; fills bags/ammo/food/reagents/consumables/potions/keyring; repairs. Source: `MaintenanceAction::Execute` |
| `autogear` | PARTY / RAID | Maint / Gear | equips **generated** gear up to `AutoGearQualityLimit` (Rare by default) where it scores ≥ 1.2× the worn item; old item goes to bags, full bags skip the slot. Nothing destroyed. `autogear reset` and `bis` are blocked — they destroy worn gear |
| `nc -loot` | PARTY / RAID | Maint / Gear | disables the bots' non-combat looting strategy |

**Self-bot:** `.playerbots bot self` gives *your* character bot AI, and then it obeys `maintenance`/`autogear` in party chat like any bot. MiniGM watches for the server lines `Enable player botAI` / `Disable player botAI`; while self-bot is on, Maint/Gear shows the full list above and sends nothing until you type your character name. `/mgm selfbot` shows the state, `/mgm selfbot off` clears MiniGM's flag. A command you type into chat yourself is not covered — the server setting `AiPlayerbot.SelfBotLevel = 0` blocks self-bot entirely.

**Bots ignore `.summon`; humans ignore chat `summon`.** That asymmetry is why Target sends both forms and why Party/Raid cannot move a human group member.

---

## Secure macro buttons

Four buttons are `SecureActionButtonTemplate` macros rather than ordinary buttons, because they must act on **you** when nothing is targeted:

| Button | Macro text |
|---|---|
| Speed *n*× | `/target [noexists] player` + `/say .modify speed all <n>` |
| Speed normal | `/target [noexists] player` + `/say .modify speed all 1` |
| Full heal | `/target [noexists] player` + `/w <you> .modify hp <max>` (+ `.modify mana <max>`) — whispered to yourself so it works while dead |
| Revive all | `/tar player` + `/w <you> .revive` + `/p revive` — whispered to yourself so it works while dead |

`[noexists]` means *only target yourself if nothing is targeted* — with a bot selected, Speed and Full heal apply to the bot.

**Blizzard blocks `/target` from a macro during combat.** All four are inert in combat; MiniGM detects this in `PostClick` and tells you rather than failing silently.

Because macro text cannot be changed during combat either, the Full heal and Speed macros are rebuilt on `PLAYER_LOGIN`, `PLAYER_LEVEL_UP`, `UNIT_MAXHEALTH` and `PLAYER_REGEN_ENABLED`, each guarded by `InCombatLockdown()`.

---

## Privacy

While you are alive, every GM command goes out in `/say`, and on a public realm anyone within earshot can read what you are doing. While you are dead, the client refuses `/say` from a ghost, so MiniGM sends the command as a whisper to yourself instead; the server parses `.` commands out of a whisper exactly as it does out of `/say`. The Full heal and Revive all macros always whisper yourself, alive or dead, because their text is fixed when the button is built.
