# Changelog

WoW 3.3.5a (Interface 30300), AzerothCore.

---

## 1.2.0 — self-bot guard

- ADD **Self-bot guard on Maint / Gear.** With `.playerbots bot self` on, your own character obeys `maintenance` and `autogear` said in party chat, exactly like a bot. `maintenance` permanently learns weapon skills, professions and secondary skills (First Aid, Fishing, Cooking), every available spell, spends all talent points, adds glyphs, enchants and gems gear, and fills your bags. MiniGM now watches for the server's `Enable player botAI` / `Disable player botAI` lines, and while self-bot is on the button opens a warning that lists every change and sends nothing until you type your character name. The list was checked line by line against `MaintenanceAction::Execute` on mod-playerbots `b6696bd`.
- ADD `/mgm selfbot` (show the state) and `/mgm selfbot off` (clear MiniGM's flag if it is stale).
- ADD Hard block: MiniGM refuses to send `autogear reset` or `bis`. Both destroy every equipped item before regearing.
- FIX docs/COMMANDS.md described `maintenance` as "repair, refill reagents, re-buff" and `autogear` as "upgrade gear from bags". Both were wrong. Rewritten from the source.
- ADD CHANGELOG link in the README Install section.

---

## 1.1.0 — alts remembered on join

- ADD A name typed into "Type a name..." is remembered as an alt the moment that character joins your party. Random bots arrive through `addclass` and never pass through that path, so they are never remembered; a typo never joins, so it is never remembered either. Works for characters on linked accounts and for the opposite faction (needs `AllowTwoSide.Interaction.Group = 1` on the server).
- CHANGE The pending name expires after two minutes if nobody joins.
- FIX Every button was dead while you were dead. The client refuses `/say` from a ghost, and every command went out on `/say`. Commands now go out as a whisper to yourself when you are dead (the server parses `.` commands from a whisper the same way); the Full heal and Revive all macros always whisper yourself, alive or dead.

---

## 1.0.0 — first release

Everything in 1.0.0-rc, plus the documentation and packaging work that came out of actually publishing it.

- ADD A "First, some context" opener — what World of Warcraft was, why patch 3.3.5a matters, where private servers came from, and what AzerothCore is. Figures sourced to Guinness and Blizzard's 2010 investor release.
- ADD An explicit statement that this project does not link to, host or help anyone obtain a game client.
- ADD `MiniGM-Addon-<version>.zip` as the release download, containing a correctly named `MiniGM` folder. The `-Addon-` is there because the naive filename collides exactly with the "Source code (zip)" GitHub attaches to every release.
- CHANGE Install on the front page is five steps: download, open, drag the folder into AddOns, restart, `/mgm`. The caveats moved to `docs/INSTALL.md`.
- FIX Restored the Commands section to the README. An earlier rewrite dropped it, leaving `/mgm runspeed` as the only slash command mentioned anywhere — and it sat in a table of buttons, so it read as though there were a control for it.
- FIX Teleport picker was 640px wide and its own three columns needed 642. The Search label was anchored off-frame entirely. Now 668×372.
- FIX Corrected the mount-aura claim in four places. The docs said the aura "gets stripped indoors and in instances" as fact; it does not do that reliably — flying inside the Stormwind auction house held fine.
- CHANGE The panel always opens on the HUD tab. Remembering the last tab meant logging in to a near-empty Tele panel and wondering what broke.
- CHANGE Screenshots moved next to the features they show.
- CHANGE Prose rewritten throughout for a plainer voice.

---

## 1.0.0-rc — first public release candidate

First public build. Everything below this entry is unreleased private development, kept because the *reasons* are worth reading — several entries document server behaviour that is not written down anywhere else.

- ADD Full documentation set — install, user guide, complete command inventory, architecture, teleport data provenance, attribution, and a single-file master guide written to be given to an LLM.
- ADD GPLv3 licence and attribution, with the AzerothAdmin → TrinityAdmin → MangAdmin lineage recorded.
- CHANGE Slash commands are `/mgm` and `/minigm`.
- FIX Teleport picker layout. At 640px it could not contain its own three
  columns - `26 + 196x3 + 14x2 = 642` overflowed the frame before the 12px
  border inset was counted - and the Search label was anchored to the left of
  its box at x=26, so it rendered off-frame entirely. Now 668x372 with
  symmetrical 26px margins and the label anchored to the frame.
- ADD Screenshots.
- ADD A packaged release zip, `MiniGM-Addon-<version>.zip`, containing a
  correctly named `MiniGM` folder so installing is "drag it into AddOns".
  GitHub's own source zips do not work for this: **Download ZIP** gives
  `MiniGM-main` and a release's "Source code (zip)" gives `MiniGM-1.0.0-rc`,
  neither of which WoW will load. The `-Addon-` in the filename exists
  because the naive name collides exactly with GitHub's auto-attached one.
  The zip carries LICENSE too - a release is distribution, and GPLv3 asks
  for the licence to travel with the work. Packaging steps in CONTRIBUTING.md.
- ADD A "First, some context" opener for readers who have never heard of any
  of this: what World of Warcraft was, why patch 3.3.5a matters, where
  private servers came from, and what AzerothCore is - its lineage, its
  licence, and why modules like mod-playerbots make a small realm workable
  at all. Figures cited are sourced.
- ADD An explicit statement that this project does not link to, host or help
  anyone obtain a game client. MiniGM is an interface addon; the client is a
  separate matter.
- ADD A Commands section to the README. An earlier draft had one and it was
  lost in a rewrite, leaving `/mgm runspeed` as the only slash command
  mentioned anywhere - sitting in a table of buttons, where it read as if
  there were a control for it. All 13 are listed now, under a heading that
  says plainly they are typed.
- FIX Docs overstated the mount-aura failsafe. They said the aura "gets
  stripped indoors and in instances" as a flat fact; it is not that
  predictable - flying inside the Stormwind auction house held fine. The
  watchdog is there because the aura can drop silently, not because any
  particular place always drops it.
- CHANGE The panel always opens on the **HUD** tab. Remembering the last tab
  saved one click and cost a confusing login every session - you are never
  mid-task at login, so landing on a near-empty Tele tab just reads as broken.

---

## Pre-release development history

Unreleased. Version numbers here are internal build numbers, not public releases.

### 3.4 Beta
- CHANGE The panel and the teleport picker now scale **independently**. 3.3 made the picker follow the panel; each now owns its scale, position and grip.
- ADD Size grip on the teleport picker.
- ADD `/mgm telescale <0.5-2>`.
- CHANGE `/mgm reset` resets both scales and both positions.

### 3.3 Beta
- ADD **Size grip** on the bottom-right corner. It scales rather than resizes: every button sits at a fixed pixel offset, so a real resize would leave gaps instead of reflowing. Clamped 0.5–2.0, top-left stays pinned, size remembered.
- FIX Minimap tooltip opened over the minimap itself. Now drops down-left.
- FIX The Minimap icon checkbox is centred under the title, measured as a checkbox+label pair after the first draw.

### 3.2 Beta
- FIX **Party/Raid/Target teleport did not move bots.** 3.1 sent one `.summon <name>` per member. That is a GM command aimed at *players*: the server accepts it and prints "You are summoning [X]", and the playerbot never acts on it. Bots obey the module's own `summon` in party or raid chat, which also moves the **whole group in one message**. Party/Raid now send `summon` to group chat; Target sends it whispered (bots) plus `.summon` (humans).
- NOTE Human party members do not obey the chat `summon`. Bring a human with Target.
- ADD **Minimap icon**, toggled from the title strip. Left-click opens/closes, shift-drag moves it, shift-right-click hides it. Position and state remembered. No LibDBIcon.
- ADD `/mgm minimap`.
- CHANGE The send queue carries a whisper recipient.

### 3.1 Beta
- ADD **Tele tab.** Who first — Self / Target / Party / Raid — then a centre-screen three-column picker opening on the zone you are standing in. Continent → Zone → Location, every column clickable.
- ADD Search box filtering all 1,306 locations by name across every zone.
- ADD `Tele\TeleportDB.lua` — **1,306 locations, 143 zones, 8 groups, 83 maps**, derived from AzerothAdmin's `Data/TeleportTable.lua` (GPLv3) and regrouped from its 12 branches. 9 corrupt coordinate strings repaired, all listed in the file header.
- ADD The picker is its own frame on UIParent: centred, separately draggable, Esc closes it.

### 3.0.1 Beta
- FIX Title still overflowed the header brackets. 3.0 padded the header by a fixed +72px, which for a ~160px title produced a *narrower* header than the 240px it replaced. The art's end-caps scale with the texture, so the width must be a multiple of the title width.
- ADD `/mgm titlefit <1.0-4.0>` to tune that multiplier live.
- FIX The Tele tab reported a successful empty load as "database loaded, empty", which reads as a failure. Success now says "loaded OK" in green.

### 3.0 Beta
- ADD Tab bar (HUD · Tele) below the window, in the existing button style. Tabs drag and scale with the window and stay usable while collapsed.
- ADD `Tele\TeleportDB.lua`, loaded before the main file. Empty in 3.0; the Tele tab reports what it found so a failed install is visible immediately.
- ADD Active tab remembered.
- FIX Title ran past the header brackets.
- CHANGE Every HUD widget moved into its own page frame. No behavioural change.
- ADD GPLv3 LICENSE, README and this changelog.

### 2.1 Beta
- ADD Flight failsafe: a watchdog checks `IsMounted()` every 3s, re-applies the mount aura if stripped, waits out combat, and falls back to plain GM fly after three attempts.

### 2.0 Beta
- ADD Mount-aura flight. `.gm fly` alone ignores all speed rates; flight speed only applies while a mount aura is active, so Fly ON also sends `.modify mount <displayID> <speed>`.
- ADD `/mgm flyspeed`, `/mgm flymount`.

### 1.9 Beta
- ADD `/mgm runspeed <n>`; default reverted to 1.5.

### 1.8 Beta
- Testing and configuration only; no source snapshot kept.

### 1.7 Beta
- FIX Chat throttle silently dropped bursts — three `SendChatMessage` calls in one frame delivered only two. Everything outgoing now goes through a queue at one message per 0.4 s.

### 1.6 Beta
- ADD Fly speed control.

### 1.5 Beta
- ADD Esc closes pop-out panels.
- ADD `/mgm addalt a,b,c` accepts a comma-separated list.

### 1.4 Beta
- FIX Level can only go up. `.character level` de-levels as happily as it raises; that is now refused.

### 1.3 Beta
- ADD Modify Char panel — set level, add gold. Refuses with no target, and demands typing `Accept` when the target is you.

### 1.2 Beta
- CHANGE Only characters you have logged into are remembered as alts.
- ADD Right-click an alt to forget it.
- FIX Enter accepts popups (`EditBoxOnEnterPressed`).

### 1.1 Beta
- CHANGE Capitalised class labels.
- ADD `/mgm reset` also resets scale.

### 1.0 Beta
- First build. Red/gold dialog, draggable, collapsible, `/mgm` to toggle, no minimap icon by design.
