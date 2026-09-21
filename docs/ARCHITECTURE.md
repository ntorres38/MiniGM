# MiniGM — Architecture

For anyone modifying the addon. Written against **v1.0**.

**Contents**
1. [Shape](#1-shape)
2. [The outgoing queue](#2-the-outgoing-queue)
3. [Layout helpers](#3-layout-helpers)
4. [Tabs and pages](#4-tabs-and-pages)
5. [Scaling](#5-scaling)
6. [The teleport picker](#6-the-teleport-picker)
7. [The minimap icon](#7-the-minimap-icon)
8. [Events](#8-events)
9. [Saved variables](#9-saved-variables)
10. [3.3.5a API constraints](#10-335a-api-constraints)
11. [Design decisions](#11-design-decisions)

---

## 1. Shape

```
MiniGM/
  MiniGM.toc            load order: Tele\TeleportDB.lua, then MiniGM.lua
  MiniGM.lua            the entire addon, ~1,700 lines
  Tele/TeleportDB.lua   generated data: MiniGMTele, MiniGMTeleOrder
```

No libraries. No Ace3, no LibStub, no LibDBIcon. Two globals are created deliberately — `MiniGMDB` (saved variables) and the two from the data file. Everything else is file-local.

`TeleportDB.lua` loads **first** so `MiniGMTele` exists when the Tele tab builds.

### Frame hierarchy

```
UIParent
├── MiniGMFrame ................ the panel (300 × 378)
│   ├── header texture + title  auto-sized (§10)
│   ├── MiniGMCollapse          the - / + button
│   ├── MiniGMMinimapCheck      + its label, centred as a pair
│   ├── MiniGMSizeGrip          bottom-right
│   ├── MiniGMTabhud / …tele    hang below the bottom border
│   ├── body ................... TOPLEFT 14,-34 → BOTTOMRIGHT -14,12
│   │   ├── hudPage             every HUD widget
│   │   └── telePage            the four who-buttons + status
│   ├── MiniGMClassMenu         flyouts, parented to the panel so they
│   ├── MiniGMModifyMenu        follow its drag and scale
│   └── MiniGMAltMenu
├── MiniGMTelePicker ........... the picker (640 × 436) — NOT a child of
│   ├── MiniGMTeleSearch        the panel, so it keeps its own position
│   ├── MiniGMTeleListGroup     and scale
│   ├── MiniGMTeleListZone
│   ├── MiniGMTeleListLoc
│   └── MiniGMTeleSizeGrip
└── Minimap
    └── MiniGMMinimapButton
```

Flyouts are children of the panel **on purpose** — they should move and scale with it. The picker is a child of `UIParent` **on purpose** — it is a separate window.

---

## 2. The outgoing queue

Everything outbound goes through one path:

```lua
local sendQueue = {}
local sender = CreateFrame("Frame")
sender:SetScript("OnUpdate", function(self, delta)
    if table.getn(sendQueue) == 0 then return end
    self.elapsed = self.elapsed + (delta or 0)
    if self.elapsed < 0.4 then return end
    self.elapsed = 0
    local item = table.remove(sendQueue, 1)
    SendChatMessage(item.text, item.channel, nil, item.to)
    say(GOLD .. item.text .. R)
end)

local function queueSend(text, channel, to) … end
local function cmd(text) queueSend(text, "SAY") end
```

**Why.** The 3.3.5a client silently drops multiple `SendChatMessage` calls issued in the same frame. Observed directly: three calls in one click delivered two, and the Maint/Gear button had to be pressed twice. One message per 0.4 s fixes it.

Two consequences worth knowing when adding features:

- **Ordering is guaranteed.** FIFO, so `.go xyz` always lands before the `summon` that follows it. Nothing needs to wait on anything.
- **Latency is real.** Three queued commands take 1.2 s to drain. If a click should feel instant, it needs to be one message.

Every queued message is echoed to the chat frame in gold, so the user always sees exactly what was sent.

---

## 3. Layout helpers

The HUD is a two-column flow, not absolute positioning:

```lua
local COL_W, BTN_H, ROW_H = 130, 22, 25
local cursorY, col = 0, 0
local page = hudPage

local function beginPage(p) page, cursorY, col = p, 0, 0 end
local function section(text)  -- gold heading, forces a new row
local function place(b)       -- next slot in the 2-column flow
local function button(label, onClick, tooltip)
local function macroButton(name, label, macrotext, tooltip)
local function tip(b, text, anchor)
```

`button()` and `macroButton()` call `place()`, which reads the `page`, `cursorY` and `col` upvalues at call time. To build a different tab, call `beginPage(thatPage)` first and `beginPage(hudPage)` after.

`tip(b, text, anchor)` — the anchor defaults to `ANCHOR_RIGHT`; the minimap button passes `ANCHOR_BOTTOMLEFT` so its tooltip does not cover the minimap.

### Adding a button

```lua
button("My thing", function()
    if not UnitExists("target") then
        say(RED .. "Nothing targeted." .. R)
        return
    end
    cmd(".whatever")
end, "Tooltip text.\nSecond line.")
```

Guard first, `cmd()` last. If it must act on you when nothing is targeted, it has to be a `macroButton` (§10).

---

## 4. Tabs and pages

Each tab is a frame filling `body`; switching shows one and hides the others.

```lua
local TAB_H = { hud = FRAME_H, tele = 232 }
local activeTab = "hud"
local function currentHeight() return TAB_H[activeTab] or FRAME_H end

local function showTab(id)
    activeTab = id
    -- active tab: alpha 1.0 + LockHighlight; others 0.72 + UnlockHighlight
    -- show its page, hide the rest
    if body:IsShown() then f:SetHeight(currentHeight()) end
end
```

Tabs anchor to the panel's `BOTTOMLEFT` with a positive Y offset, so they hang below the border and **follow the frame up when it collapses** — they stay usable in collapsed state.

### Adding a tab

1. `local myPage = CreateFrame("Frame", nil, body)` + `SetAllPoints(body)` + `Hide()`
2. Add its height to `TAB_H`
3. `beginPage(myPage)` … build … `beginPage(hudPage)`
4. Add a branch to `showTab`
5. `makeTab("mine", "Mine")`

---

## 5. Scaling

The grip **scales**; it does not resize. Every widget sits at a fixed pixel offset, so `SetResizable` would stretch the frame and leave the contents in one corner.

```lua
local function attachGrip(frame, name, setScale, savePos, tipText)
```

One helper, used twice — once for the panel, once for the picker, each with its own setter so the two are independent.

The drag maths, which is the fiddly part:

```lua
-- on mouse down: capture the frame's top-left in UIParent units
local sc = frame:GetScale()
L0, T0 = frame:GetLeft() * sc, frame:GetTop() * sc

-- each frame while dragging:
local cx = GetCursorPosition() / UIParent:GetEffectiveScale()
local ns = clampScale((cx - L0) / frame:GetWidth())   -- GetWidth() is unscaled
setScale(ns)
frame:ClearAllPoints()
frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", L0 / ns, T0 / ns)
```

Two things to keep straight:

- `GetLeft()` returns the frame's **own** coordinate space; multiplying by its scale converts to UIParent units.
- `SetPoint` offsets are interpreted in the frame's **own** (now rescaled) space, which is why the captured position is divided by the new scale to keep the top-left pinned.

Because offsets are stored in the frame's own space, saving a position at scale *N* and restoring it at scale *N* is correct regardless of whether `SetPoint` or `SetScale` runs first at login.

---

## 6. The teleport picker

### Data

`MiniGMTele[group][zone][location] = ".go xyz X Y Z MapID"`

The value **is** the finished command. Nothing is parsed at runtime — the string is handed straight to `cmd()`. `MiniGMTeleOrder` fixes the group order, because `pairs()` is unordered. See [TELEPORT-DATA.md](TELEPORT-DATA.md).

### List widget

`makeList(name, x, headerText)` builds a `FauxScrollFrameTemplate` with 16 recycled 15px rows and returns an object with `:SetItems(items, selected)` and `:Update()`. Items are `{ key, text, … }`; the row whose `key` matches `selected` renders red.

`SetItems` resets the scroll offset; `Update` does not. Picking a zone from far down the list uses `list.selected = z; list:Update()` so the list does not jump back to the top.

### Render chain

`renderGroups()` → `renderZones()` → `renderLocs()`. Each reads `selGroup` / `selZone` / `searchText` and rebuilds its column. With a search active, `renderLocs` ignores the selection and walks every group and zone.

### Execution

`doTeleport(goCmd, locName, zoneName)` branches on `teleWho`:

| `teleWho` | Sends |
|---|---|
| `self` | `cmd(goCmd)` |
| `target` | `cmd(goCmd)` · `queueSend("summon","WHISPER",t)` · `cmd(".summon "..t)` |
| `party` | `cmd(goCmd)` · `queueSend("summon","PARTY")` |
| `raid` | `cmd(goCmd)` · `queueSend("summon","RAID")` |

Everything but `self` goes through `MINIGM_TELE_CONFIRM`, a `StaticPopupDialogs` entry using `text = "%s"` so the destination can be filled in per call. The pending action is held in an upvalue and cleared on both accept and cancel.

**Do not "optimise" this back to `.summon` per member.** That was v3.1's design and it did not work: bots ignore `.summon` entirely. See [COMMANDS.md](COMMANDS.md).

---

## 7. The minimap icon

31×31 button parented to `Minimap`, `INV_Misc_Gear_01` cropped to `SetTexCoord(0.07, 0.93, 0.07, 0.93)` under `MiniMap-TrackingBorder`.

Position is an angle, not a point:

```lua
local a = math.rad(MiniGMDB.minimapAngle or 200)
mmBtn:SetPoint("CENTER", Minimap, "CENTER", 80 * math.cos(a), 80 * math.sin(a))
```

Shift-drag installs an `OnUpdate` that converts the cursor position to an angle about the minimap centre and re-places the button; `OnDragStop` removes it. `OnDragStart` returns immediately unless shift is held, so a plain left-drag does nothing and a plain left-click still toggles the panel.

LibDBIcon does this properly and handles square minimaps. It is ~400 lines; this is ~40, and keeping the addon dependency-free was judged worth the trade.

---

## 8. Events

One frame handles everything:

| Event | Does |
|---|---|
| `PLAYER_LOGIN` | restore position → apply both scales → `fitHeader()` → centre the minimap toggle → open the HUD tab → apply minimap → remember this character as an alt → rebuild macros |
| `PLAYER_ENTERING_WORLD` | clear the fly watchdog (zoning clears GM fly server-side) |
| `PLAYER_TARGET_CHANGED` | refresh the Modify Char panel if it is open |
| `UNIT_MAXHEALTH` | rebuild the Full heal macro (player only) |
| `PLAYER_LEVEL_UP`, `PLAYER_REGEN_ENABLED` | rebuild macros |

`fitHeader()` and `centreMmToggle()` both run at login because `GetStringWidth()` returns 0 before the first draw. Both are no-ops when the width is still 0, so calling them early is harmless.

---

## 9. Saved variables

`MiniGMDB`, declared in the `.toc`. A flat table — no AceDB, no profiles, no per-character scope.

| Key | Written by | Read at |
|---|---|---|
| `pos`, `scale` | drag / grip / `/mgm scale` | login |
| `pickPos`, `pickScale` | drag / grip / `/mgm telescale` | login, and every `openPicker` |
| `minimapShow`, `minimapAngle` | checkbox / shift-drag / `/mgm minimap` | login |
| `alts`, `lastAlt` | login, popups, `/mgm addalt` | flyout build |
| `runSpeed`, `flySpeed`, `flyMount` | slash commands | macro/command build |
| `titleFit` | `/mgm titlefit` | `fitHeader` |

Every key has both a writer and a reader; there are no orphans.

---

## 10. 3.3.5a API constraints

Things that do not exist, or behave differently, on this client. Most cost real debugging time.

| Trap | Reality |
|---|---|
| `SetShown` | Does not exist. Use `Show()` / `Hide()`. |
| `UnitManaMax` | Does not exist. `UnitPowerMax(unit, 0)`. |
| `this`, `arg1` globals | Gone. Handlers receive `self` as the first argument; StaticPopup handlers receive the dialog. |
| Enter in a popup edit box | Needs `EditBoxOnEnterPressed`; `enterClicksFirstButton` alone is not enough. |
| Esc closing a frame | Only via `table.insert(UISpecialFrames, frameName)` — the frame must be **named**. |
| `/target` in a macro | Blocked in combat. Any button that self-targets is inert in combat. |
| Macro text | Cannot be changed during combat. Guard every rebuild with `InCombatLockdown()`. |
| `GetStringWidth()` | Returns 0 before the first draw. Anything sizing from it must re-run at login. |
| `#` on a hash table | Undefined. Count with `for _ in pairs(t)`. `table.getn` on arrays. |
| Chat throttle | Multiple `SendChatMessage` calls in one frame are silently dropped. Hence §2. |
| Header art | `UI-DialogBox-Header`'s end-caps scale with the texture, so the usable span is ~55% of its width. Padding must be multiplicative, not additive — hence `/mgm titlefit`. |

### Testing

There is no test harness; testing is manual, in game. Always syntax-check before loading:

```
luac5.1 -p MiniGM.lua
luac5.1 -p Tele/TeleportDB.lua
```

A `.lua` change needs `/reload`. A `.toc` change, or adding or removing a file, needs a **full client restart**.

---

## 11. Design decisions

**No libraries.** Ace3, LibStub and LibDBIcon would each save some code. The addon is two files that you can read end to end in an hour, and it has no version-skew surface with other addons. That was judged worth more than the saved lines.

**No chat scraping.** MiniGM never hooks `AddMessage` or filters chat, so it cannot see the server's replies — no lookup browser, no GPS readout, no player info panes. That is the single biggest functional gap versus AzerothAdmin, and it is deliberate: hooking every chat frame is how an addon ends up swallowing other addons' messages.

**No clickable chat links.** AzerothAdmin's Linkifier intercepts bare `spell:` link prefixes, so clicking any spell link *anyone* posts fires `.learn <id>` unconfirmed. If MiniGM ever adds links they will use a private `|Hminigm:…|h` prefix matched exclusively.

**Guard, then send.** Every destructive button refuses before it sends rather than asking afterwards. Acting on yourself requires typing `Accept`. The cost is occasional friction; the benefit is that a misclick cannot level, pay or kill the wrong character.

**Generated data is never hand-edited.** `Tele/TeleportDB.lua` carries a "do not hand-edit" header and a record of every repair made during generation. Regenerate it instead — see [TELEPORT-DATA.md](TELEPORT-DATA.md).
