--[[--------------------------------------------------------------------
  MiniGM - by Parriah
  A small GM panel for AzerothCore 3.3.5a (WotLK) realms.
  Every button sends an ordinary GM chat command; the server enforces
  your gmlevel exactly as if you had typed it. No server component.
  Toggle with /mgm, or with the optional minimap icon.

  Written with AI assistance (Claude). Design, testing and bug reports by
  the author; the Lua itself was machine-generated. Read it before you
  trust it - the LICENSE below disclaims warranty, and that is not
  boilerplate here.

  Copyright (C) 2026 Parriah
  License GPLv3+: GNU GPL version 3 or later
  <https://www.gnu.org/licenses/gpl-3.0.en.html>
  This program comes with ABSOLUTELY NO WARRANTY. This is free software,
  and you are welcome to redistribute it under certain conditions; see the
  LICENSE file distributed with this addon.

  Original code, but not built in a vacuum. The teleport location data
  is derived from AzerothAdmin's Data/TeleportTable.lua:
    AzerothAdmin  - SuperStyro Dev team + Manground Dev Team (GPLv3)
                    https://github.com/superstyro/AzerothAdmin
    which derives from TrinityAdmin, which derives from MangAdmin.
  See README.md for full credits.
----------------------------------------------------------------------]]

local ADDON   = "MiniGM"
local VERSION = "1.2.0"
local FRAME_H = 378

local GOLD  = "|cffffd100"
local GREEN = "|cff40ff40"
local RED  = "|cffff2020"
local R    = "|r"

MiniGMDB = MiniGMDB or {}

-- label shown on the button  /  value sent to the server
local classes = {
    { "Warrior", "warrior" }, { "Paladin", "paladin" }, { "Hunter", "hunter" },
    { "Rogue",   "rogue"   }, { "Priest",  "priest"  }, { "DK",     "dk"     },
    { "Shaman",  "shaman"  }, { "Mage",    "mage"    }, { "Warlock","warlock"},
    { "Druid",   "druid"   },
}

----------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------
local function say(msg)
    DEFAULT_CHAT_FRAME:AddMessage(GOLD .. "MiniGM:" .. R .. " " .. msg)
end

-- The client's chat throttle silently drops messages sent in the same frame
-- (seen Sep 20: maintenance/autogear/nc -loot -> only 2 of 3 arrived).
-- Everything outgoing goes through this queue: one message per 0.4s.
local sendQueue = {}
local sender = CreateFrame("Frame")
sender.elapsed = 0
sender:SetScript("OnUpdate", function(self, delta)
    if table.getn(sendQueue) == 0 then return end
    self.elapsed = self.elapsed + (delta or 0)
    if self.elapsed < 0.4 then return end
    self.elapsed = 0
    local item = table.remove(sendQueue, 1)
    SendChatMessage(item.text, item.channel, nil, item.to)
    say(GOLD .. item.text .. R)
end)

local function queueSend(text, channel, to)
    -- HARD BLOCK: "autogear reset" and the BiS fallback destroy every equipped
    -- item before regearing (TrainerAction.cpp). MiniGM never sends them.
    local low = string.lower(text or "")
    if string.find(low, "^%s*autogear%s+reset") or string.find(low, "^%s*bis") then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020MiniGM: refused '" .. text ..
            "' - it destroys all equipped gear.|r")
        return
    end
    -- always queue: two cmd() calls in the same click must not race each other
    if table.getn(sendQueue) == 0 then
        sender.elapsed = 0.4    -- first message goes out on the next frame
    end
    table.insert(sendQueue, { text = text, channel = channel, to = to })
end

-- /say is blocked by the client while you are dead. A whisper to yourself
-- is not, and the server parses "." commands out of a whisper exactly as it
-- does out of /say. So: alive -> /say, dead -> whisper self.
local function cmd(text)
    if UnitIsDeadOrGhost("player") then
        queueSend(text, "WHISPER", UnitName("player"))
    else
        queueSend(text, "SAY")
    end
end

-- same idea for the secure macro buttons, whose text is fixed at click time:
-- always whisper yourself, which works alive or dead
local function selfChat()
    local me = UnitName("player")
    if me and me ~= "" and me ~= "Unknown" then return "/w " .. me .. " " end
    return "/say "
end

-- party/raid chat (bots listen there); warns if solo
local function groupSay(text)
    local inRaid  = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    local inParty = (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
    if not inRaid and not inParty then
        say(RED .. "Not in a party or raid - bots would not hear that." .. R)
        return false
    end
    queueSend(text, inRaid and "RAID" or "PARTY")
    return true
end

local function trim(s)
    return (string.gsub(string.gsub(s or "", "^%s+", ""), "%s+$", ""))
end

----------------------------------------------------------------------
-- SELF-BOT GUARD (1.2.0)
-- ".playerbots bot self" gives YOUR character bot AI. While it is on, your
-- own character obeys "maintenance"/"autogear" said in party/raid chat, the
-- same as a bot. The server announces the toggle with the exact system lines
-- "Enable player botAI" / "Disable player botAI" (PlayerbotMgr.cpp).
-- State is kept per character in MiniGMDB.selfBot and survives /reload.
-- Fail-safe: if MiniGM last saw it ON, it stays ON until the server says
-- "Disable player botAI" (or /mgm selfbot off). Worst case = an extra popup.
----------------------------------------------------------------------
local function selfBotOn()
    MiniGMDB.selfBot = MiniGMDB.selfBot or {}
    return MiniGMDB.selfBot[UnitName("player") or ""] and true or false
end

local function setSelfBot(on)
    MiniGMDB.selfBot = MiniGMDB.selfBot or {}
    MiniGMDB.selfBot[UnitName("player") or ""] = on and true or nil
end

-- What each command does to the character that receives it.
-- Source: mod-playerbots MaintenanceAction::Execute / PlayerbotFactory,
-- AutoGearAction::Execute (TrainerAction.cpp). Keep in step with the server.
local SELFBOT_WARNING =
    "|cffff2020STOP - self-bot is ON.|r\n" ..
    "This targets YOUR character: |cffffd100%s|r\n\n" ..
    "MAINTENANCE will, permanently:\n" ..
    "- Learn weapon skills and set them to max\n  (Swords, Daggers, Maces, Staves, etc. for your class)\n" ..
    "- Learn professions / secondary skills\n  (First Aid, Fishing, Cooking, gathering/crafting)\n" ..
    "- Learn every class spell available at your level\n" ..
    "- Learn all other available spells + special spells\n" ..
    "- Spend ALL talent points (picks its own spec)\n" ..
    "- Insert glyphs\n" ..
    "- Enchant and gem your equipped gear (level-gated)\n" ..
    "- Learn riding skill + mounts\n" ..
    "- Set dungeon-key reputations to Honored (level 70+)\n" ..
    "- Complete attunement quests\n" ..
    "- Fill bags: bags, ammo, food, drink, reagents,\n  consumables, potions, keyring\n" ..
    "- Create/train a pet + pet talents (hunter/warlock)\n" ..
    "- Repair all gear\n\n" ..
    "AUTOGEAR will:\n" ..
    "- Replace equipped items with generated Rare-or-lower gear\n  (old items go to bags; if bags are full, that slot is skipped)\n\n" ..
    "None of this can be undone in game.\n" ..
    "Type |cffffd100%s|r to continue:"

local pendingSelfBotAction = nil

local function selfBotAnswer(typed)
    local me = UnitName("player") or ""
    if string.lower(trim(typed)) == string.lower(me) and me ~= "" then
        if pendingSelfBotAction then pendingSelfBotAction() end
    else
        say(RED .. "Cancelled - nothing was sent. You must type " .. me .. R)
    end
    pendingSelfBotAction = nil
end

StaticPopupDialogs["MINIGM_SELFBOT_WARN"] = {
    text = SELFBOT_WARNING,
    button1 = "Send", button2 = "Cancel",
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    showAlert = 1,
    OnShow = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        selfBotAnswer(eb and eb:GetText() or "")
    end,
    OnCancel = function()
        if pendingSelfBotAction then
            say("Cancelled - nothing was sent.")
        end
        pendingSelfBotAction = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local typed = self:GetText() or ""
        self:GetParent():Hide()
        selfBotAnswer(typed)
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

-- run fn now, or - if self-bot is on - only after the name is typed
local function guardSelfBot(fn)
    if not selfBotOn() then fn() return end
    pendingSelfBotAction = fn
    local me = UnitName("player") or "?"
    StaticPopup_Show("MINIGM_SELFBOT_WARN", me, me)
end

local function playerTargetName()
    if UnitExists("target") and UnitIsPlayer("target") then
        return UnitName("target")
    end
    return nil
end

-- remember every character we log in on: that IS the alt list
local function rememberAlt(name)
    if not name or name == "" then return end
    MiniGMDB.alts = MiniGMDB.alts or {}
    for _, existing in ipairs(MiniGMDB.alts) do
        if existing == name then return end
    end
    table.insert(MiniGMDB.alts, name)
end

local function forgetAlt(name)
    if not MiniGMDB.alts then return false end
    for i, existing in ipairs(MiniGMDB.alts) do
        if string.lower(existing) == string.lower(name) then
            table.remove(MiniGMDB.alts, i)
            return true
        end
    end
    return false
end

-- a name typed into "Type a name..." becomes an alt only once that character
-- actually joins the party. Random bots arrive via addclass and never pass
-- through here, so they are never remembered. A typo never joins, so it is
-- never remembered either. Works across accounts and factions.
local pendingAlt, pendingAt

----------------------------------------------------------------------
-- main frame (Blizzard red/gold dialog look)
----------------------------------------------------------------------
local f = CreateFrame("Frame", "MiniGMFrame", UIParent)
f:SetWidth(300)
f:SetHeight(FRAME_H)
f:SetPoint("CENTER")
f:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
f:SetMovable(true)
f:EnableMouse(true)
f:SetClampedToScreen(true)
f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", function() f:StartMoving() end)
f:SetScript("OnDragStop", function()
    f:StopMovingOrSizing()
    local point, _, rel, x, y = f:GetPoint()
    MiniGMDB.pos = { point = point, rel = rel, x = x, y = y }
end)
f:Hide()

local header = f:CreateTexture(nil, "ARTWORK")
header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
header:SetHeight(64)
header:SetPoint("TOP", f, "TOP", 0, 12)

local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("TOP", f, "TOP", 0, -2)
title:SetText("MiniGM " .. GOLD .. "by Parriah" .. R)

-- Blizzard's header art is a fixed 240px and the title ran past the brackets.
-- The art's decorative end-caps scale WITH the texture, so the usable span
-- between them is only ~55% of its width - additive padding shrinks the gap
-- as fast as it widens the art. The width has to be a MULTIPLE of the text.
-- /mgm titlefit <n> tunes the multiplier live; both are children of f, so
-- /mgm scale still scales them together.
local function fitHeader()
    local w = title:GetStringWidth() or 0
    if w <= 0 then return end          -- 0 before the first draw; retried at login
    local k = tonumber(MiniGMDB.titleFit) or 1.9
    header:SetWidth(math.max(160, math.floor(w * k + 16)))
end
fitHeader()

local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
close:SetScript("OnClick", function() f:Hide() end)

local collapse = CreateFrame("Button", "MiniGMCollapse", f, "UIPanelButtonTemplate")
collapse:SetWidth(22)
collapse:SetHeight(20)
collapse:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -12)
collapse:SetText("-")

local body = CreateFrame("Frame", nil, f)
body:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)

-- Each tab's widgets live in its own page frame inside body. Both are
-- descendants of f, so they inherit dragging and /mgm scale for free.
local hudPage = CreateFrame("Frame", nil, body)
hudPage:SetAllPoints(body)

local telePage = CreateFrame("Frame", nil, body)
telePage:SetAllPoints(body)
telePage:Hide()

-- per-tab frame height; collapse and tab switching both read this
local TAB_H = { hud = FRAME_H, tele = 232 }
local activeTab = "hud"
local function currentHeight()
    return TAB_H[activeTab] or FRAME_H
end

collapse:SetScript("OnClick", function()
    if body:IsShown() then
        body:Hide()
        f:SetHeight(44)
        collapse:SetText("+")
    else
        body:Show()
        f:SetHeight(currentHeight())
        collapse:SetText("-")
    end
end)

----------------------------------------------------------------------
-- layout: 2 columns
----------------------------------------------------------------------
local COL_W, BTN_H, ROW_H = 130, 22, 25
local cursorY, col = 0, 0
local page = hudPage          -- what section()/place()/button() build into

local function beginPage(p)
    page, cursorY, col = p, 0, 0
end

local function section(text)
    if col == 1 then cursorY = cursorY - ROW_H; col = 0 end
    local fs = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", 2, cursorY - 3)
    fs:SetText(GOLD .. text .. R)
    cursorY = cursorY - 17
end

local function place(b)
    b:SetWidth(COL_W)
    b:SetHeight(BTN_H)
    b:SetPoint("TOPLEFT", page, "TOPLEFT", col * (COL_W + 8), cursorY)
    if col == 1 then cursorY = cursorY - ROW_H; col = 0 else col = 1 end
end

local function tip(b, text, anchor)
    if not text then return end
    b:SetScript("OnEnter", function()
        GameTooltip:SetOwner(b, anchor or "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function button(label, onClick, tooltip)
    local b = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    b:SetText(label)
    b:SetScript("OnClick", onClick)
    tip(b, tooltip)
    place(b)
    return b
end

-- secure macro button: needed when the command must hit ME if nothing is
-- targeted (/target [noexists] player). Blizzard blocks targeting in combat.
local function macroButton(name, label, macrotext, tooltip)
    local b = CreateFrame("Button", name, page, "SecureActionButtonTemplate,UIPanelButtonTemplate")
    b:SetText(label)
    b:SetAttribute("type", "macro")
    b:SetAttribute("macrotext", macrotext)
    tip(b, tooltip)
    b:HookScript("PostClick", function()
        if InCombatLockdown() then
            say(RED .. "In combat: self-targeting is blocked. Target yourself first." .. R)
        end
    end)
    place(b)
    return b
end

----------------------------------------------------------------------
-- MOVEMENT
----------------------------------------------------------------------
section("Movement")

local function runSpeed()
    return MiniGMDB.runSpeed or 1.5
end

local speedFast = macroButton("MiniGMSpeedFast", "Speed " .. runSpeed() .. "x",
    "/target [noexists] player\n/say .modify speed all " .. runSpeed(),
    "Run/swim/fly speed multiplier (1.0 = normal, 1.6 = 60% mount, 2.0 = epic mount).\n/mgm runspeed <n> to change.\nApplies to your target if a player/bot is selected, otherwise to you.\nResets on relog.")

local function updateSpeedButton()
    if InCombatLockdown() then return end
    speedFast:SetText("Speed " .. runSpeed() .. "x")
    speedFast:SetAttribute("macrotext",
        "/target [noexists] player\n/say .modify speed all " .. runSpeed())
end

macroButton("MiniGMSpeedNorm", "Speed normal",
    "/target [noexists] player\n/say .modify speed all 1",
    "Back to normal run speed.")

-- TESTED Sep 20: .gm fly alone ignores EVERY speed rate (fly/all/swim) - the
-- client only honours flight speed while a MOUNT AURA is active. So Fly ON
-- also applies a mount model via .modify mount <displayID> <speed>.
-- rate 1.0 = base flight 7.0 y/s: 1.5 = slow mount, 2.8 = epic (280%),
-- 3.1 = fastest WotLK mount (310%), 4.65 = 1.5x that.
local function flySpeed()
    return MiniGMDB.flySpeed or 4.65
end

local function flyMount()
    return MiniGMDB.flyMount or 28652      -- Armored Ebon Gryphon
end

-- Failsafe: the mount aura (which is what makes flight speed apply) can be
-- dropped. Not reliably reproducible - flying inside the Stormwind auction
-- house held fine - but when it goes you lose speed silently. The watchdog
-- re-applies it a few times, then falls back to plain GM fly and says so.
local flyActive, flyTries, flyNextCheck = false, 0, 0

local function applyFlyMount()
    cmd(".modify mount " .. flyMount() .. " " .. flySpeed())
end

local flyWatch = CreateFrame("Frame")
flyWatch:SetScript("OnUpdate", function(self, delta)
    if not flyActive then return end
    flyNextCheck = flyNextCheck - (delta or 0)
    if flyNextCheck > 0 then return end
    flyNextCheck = 3

    if IsMounted() then
        flyTries = 0
        return
    end

    if UnitAffectingCombat("player") then
        return                       -- combat blocks it; wait it out, don't spam
    end

    flyTries = flyTries + 1
    if flyTries <= 3 then
        say(RED .. "Mount aura not active (indoors/instance/combat?) - reapplying speed." .. R)
        applyFlyMount()
    else
        flyActive = false
        say(RED .. "Giving up on the speed mount - plain GM fly is still ON at normal speed." .. R)
        cmd(".gm fly on")            -- guarantee fly itself is on
    end
end)

button("Fly ON", function()
    local t = playerTargetName()
    if t and not UnitIsUnit("target", "player") then
        say(RED .. "Clear your target first - this would be applied to " .. t .. "." .. R)
        return
    end
    cmd(".gm fly on")
    applyFlyMount()
    flyActive, flyTries, flyNextCheck = true, 0, 4
end, "GM fly + mount aura at 1.5x the fastest WotLK mount (4.65).\nThe mount aura is what makes flight speed apply at all.\n/mgm flyspeed <n> · /mgm flymount <displayID>\nClear your target first.")

button("Fly OFF", function()
    local t = playerTargetName()
    if t and not UnitIsUnit("target", "player") then
        say(RED .. "Clear your target first - this would be applied to " .. t .. "." .. R)
        return
    end
    flyActive = false
    cmd(".dismount")
    cmd(".gm fly off")
end, "Dismounts, then turns GM fly off. Also stops the speed-mount watchdog.")

----------------------------------------------------------------------
-- SURVIVAL
----------------------------------------------------------------------
section("Survival")

button("God ON",  function() cmd(".cheat god on")  end, "Always applies to you. Resets on relog.")
button("God OFF", function() cmd(".cheat god off") end, "Always applies to you.")

local heal = macroButton("MiniGMHeal", "Full heal",
    "/target [noexists] player\n/say .modify hp 100",
    "Restores health (and mana) without changing your maximum.")

local function updateHealMacro()
    if InCombatLockdown() then return end
    local maxHP = UnitHealthMax("player") or 100
    local w = selfChat()
    local text = "/target [noexists] player\n" .. w .. ".modify hp " .. maxHP
    if UnitPowerType("player") == 0 then
        local maxMana = UnitPowerMax("player", 0) or 0
        if maxMana > 0 then
            text = text .. "\n" .. w .. ".modify mana " .. maxMana
        end
    end
    heal:SetAttribute("macrotext", text)
end

button("Revive target", function()
    local name = playerTargetName()
    if not name then
        say(RED .. "Select the dead player or bot first." .. R)
        return
    end
    cmd(".revive " .. name)
end, "Revives the selected player/bot.")

----------------------------------------------------------------------
-- GROUP (owner's macros)
----------------------------------------------------------------------
section("Group")

local reviveAll = macroButton("MiniGMReviveAll", "Revive all",
    "/tar player\n/s .revive\n/p revive",
    "Revives you (.revive on yourself) and tells the group's bots to revive.\nWorks while dead.")

local function updateReviveMacro()
    if InCombatLockdown() then return end
    reviveAll:SetAttribute("macrotext",
        "/tar player\n" .. selfChat() .. ".revive\n/p revive")
end

button("Maint / Gear", function()
    local inRaid  = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
    local inParty = (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
    if not inRaid and not inParty then
        say(RED .. "Not in a party or raid - bots would not hear that." .. R)
        return
    end
    local channel = inRaid and "RAID" or "PARTY"
    guardSelfBot(function()
        for _, line in ipairs({ "maintenance", "autogear", "nc -loot" }) do
            table.insert(sendQueue, { text = line, channel = channel })
        end
        sender.elapsed = 0.4   -- first one goes out on the next frame
    end)
end, "maintenance + autogear + nc -loot to party/raid.\nautogear never sends 'reset', so worn gear is kept.\nIf self-bot is ON this also hits YOU - MiniGM stops and\nmakes you type your character name first.")

----------------------------------------------------------------------
-- COMBAT
----------------------------------------------------------------------
section("Combat")

button("Kill target", function()
    if not UnitExists("target") then
        say(RED .. "Nothing targeted." .. R)
        return
    end
    if UnitIsUnit("target", "player") then
        say(RED .. "Refusing: that is you." .. R)
        return
    end
    if UnitIsPlayer("target") and not UnitCanAttack("player", "target") then
        say(RED .. "Refusing: " .. (UnitName("target") or "target") ..
            " is a friendly player/bot." .. R)
        return
    end
    cmd(".die")
end, "Kills the selected unit.\nRefuses on you or a friendly player/bot.")

button("Cheat status", function() cmd(".cheat status") end,
    "Shows what the SERVER thinks is on (god/fly/speed reset on relog).")

----------------------------------------------------------------------
-- CHARACTER (Modify Char)
----------------------------------------------------------------------
section("Character")

-- run an action, but if it would hit ME, demand the word Accept first
local pendingAction = nil

StaticPopupDialogs["MINIGM_CONFIRM_SELF"] = {
    text = "This will modify YOUR OWN character.\nType  Accept  (case sensitive) to continue:",
    button1 = "Confirm", button2 = "Cancel",
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    enterClicksFirstButton = 1,
    OnShow = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        local typed = eb and eb:GetText() or ""
        if typed == "Accept" then
            if pendingAction then pendingAction() end
        else
            say(RED .. "Cancelled: you must type exactly  Accept" .. R)
        end
        pendingAction = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        local typed = self:GetText() or ""
        if typed == "Accept" then
            if pendingAction then pendingAction() end
        else
            say(RED .. "Cancelled: you must type exactly  Accept" .. R)
        end
        pendingAction = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) pendingAction = nil self:GetParent():Hide() end,
    OnCancel = function() pendingAction = nil end,
}

-- guard: nothing targeted -> refuse; targeting myself -> Accept prompt
local function runOnTarget(action)
    if not UnitExists("target") or not UnitIsPlayer("target") then
        say(RED .. "Target a character first (target yourself to modify yourself)." .. R)
        return
    end
    if UnitIsUnit("target", "player") then
        pendingAction = action
        StaticPopup_Show("MINIGM_CONFIRM_SELF")
        return
    end
    action()
end

local modFly = nil   -- created below, after the flyout helper exists

local modifyBtn = button("Modify Char", function()
    if modFly:IsShown() then
        modFly:Hide()
    else
        modFly.refresh()
        modFly:Show()
    end
end, "Set a new level or add gold on the targeted character.\nTargeting yourself requires typing Accept.")

----------------------------------------------------------------------
-- BOTS
----------------------------------------------------------------------
section("Bots")

local function makeFlyout(name, width, height)
    local fly = CreateFrame("Frame", name, f)
    fly:SetWidth(width)
    fly:SetHeight(height)
    fly:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 8, right = 8, top = 8, bottom = 8 },
    })
    fly:SetFrameStrata("DIALOG")
    fly:Hide()
    table.insert(UISpecialFrames, name)   -- Esc closes it
    return fly
end

-- class flyout (appears only when Add bot is clicked)
local classFly = makeFlyout("MiniGMClassMenu", 180, 24 * 5 + 30)
local classTitle = classFly:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
classTitle:SetPoint("TOP", classFly, "TOP", 0, -10)
classTitle:SetText(GOLD .. "Bot class" .. R)

for i, entry in ipairs(classes) do
    local b = CreateFrame("Button", nil, classFly, "UIPanelButtonTemplate")
    b:SetWidth(76)
    b:SetHeight(20)
    local cl  = (i <= 5) and 0 or 1
    local row = (i <= 5) and (i - 1) or (i - 6)
    b:SetPoint("TOPLEFT", classFly, "TOPLEFT", 10 + cl * 82, -26 - row * 22)
    b:SetText(entry[1])
    b:SetScript("OnClick", function()
        classFly:Hide()
        cmd(".playerbots bot addclass " .. entry[2])
    end)
end

-- Modify Char panel
modFly = makeFlyout("MiniGMModifyMenu", 210, 136)
modFly:SetPoint("TOPLEFT", modifyBtn, "BOTTOMLEFT", 0, -2)
modFly:SetClampedToScreen(true)

local modTitle = modFly:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
modTitle:SetPoint("TOP", modFly, "TOP", 0, -10)

local function editBox(parent, label, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    fs:SetText(label)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetWidth(60)
    eb:SetHeight(18)
    eb:SetPoint("TOPLEFT", parent, "TOPLEFT", 100, y + 3)
    eb:SetAutoFocus(false)
    eb:SetNumeric(false)
    eb:SetMaxLetters(9)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return eb
end

local levelBox = editBox(modFly, "New level", -30)
local goldBox  = editBox(modFly, "Add gold",  -74)

local function doLevel()
    local name = playerTargetName()
    local n = tonumber(trim(levelBox:GetText() or ""))
    if not name then
        say(RED .. "No character targeted." .. R)
        return
    end
    if not n or n < 1 or n ~= math.floor(n) then
        say(RED .. "Level must be a whole number of 1 or more." .. R)
        return
    end
    if n > 80 then
        say(RED .. "Level capped at 80 by the server; sending 80." .. R)
        n = 80
    end

    -- never de-level: .character level lowers as happily as it raises
    local current = UnitLevel("target") or 0
    if current > 0 then
        if n == current then
            say(RED .. name .. " is already level " .. current .. "." .. R)
            return
        end
        if n < current then
            say(RED .. "Refusing: " .. name .. " is level " .. current ..
                " - that would DE-LEVEL to " .. n .. ". Levelling down is not allowed here." .. R)
            return
        end
    end

    cmd(".character level " .. name .. " " .. n)
end

local function doGold()
    local name = playerTargetName()
    local g = tonumber(trim(goldBox:GetText() or ""))
    if not name then
        say(RED .. "No character targeted." .. R)
        return
    end
    if not g or g <= 0 then
        say(RED .. "Gold must be a positive number (1.5 = 1g 50s)." .. R)
        return
    end
    if g > 100000 then
        say(RED .. "Refusing: more than 100,000 gold in one click." .. R)
        return
    end
    local copper = math.floor(g * 10000 + 0.5)
    local gold   = math.floor(copper / 10000)
    local silver = math.floor((copper - gold * 10000) / 100)
    local cop    = copper - gold * 10000 - silver * 100
    say(string.format("adding %dg %ds %dc to %s", gold, silver, cop, name))
    cmd(".modify money " .. copper)     -- .modify money ADDS, and acts on your target
end

local levelGo = CreateFrame("Button", nil, modFly, "UIPanelButtonTemplate")
levelGo:SetWidth(40) levelGo:SetHeight(20)
levelGo:SetPoint("TOPLEFT", modFly, "TOPLEFT", 164, -27)
levelGo:SetText("Set")
levelGo:SetScript("OnClick", function() runOnTarget(doLevel) end)

local goldGo = CreateFrame("Button", nil, modFly, "UIPanelButtonTemplate")
goldGo:SetWidth(40) goldGo:SetHeight(20)
goldGo:SetPoint("TOPLEFT", modFly, "TOPLEFT", 164, -71)
goldGo:SetText("Add")
goldGo:SetScript("OnClick", function() runOnTarget(doGold) end)

levelBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() runOnTarget(doLevel) end)
goldBox:SetScript("OnEnterPressed",  function(self) self:ClearFocus() runOnTarget(doGold) end)

local modHint = modFly:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
modHint:SetPoint("BOTTOM", modFly, "BOTTOM", 0, 12)
modHint:SetText("gold: 1.5 = 1g 50s  |  level: up only")

function modFly.refresh()
    local name = playerTargetName()
    if name then
        local lvl = UnitLevel("target") or 0
        local suffix = (lvl > 0) and ("  |cfffffffflvl " .. lvl .. "|r") or ""
        if UnitIsUnit("target", "player") then
            modTitle:SetText(GOLD .. name .. R .. " |cffff2020(you)|r" .. suffix)
        else
            modTitle:SetText(GOLD .. name .. R .. suffix)
        end
    else
        modTitle:SetText(RED .. "no character targeted" .. R)
    end
end

-- alt flyout, rebuilt from the remembered character list
local altFly = makeFlyout("MiniGMAltMenu", 160, 40)
local altTitle = altFly:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
altTitle:SetPoint("TOP", altFly, "TOP", 0, -10)
altTitle:SetText(GOLD .. "Your alts" .. R)
altFly.buttons = {}

-- name typed into a popup; NOT remembered (only characters you log into are)
local function popupName(dialog)
    local eb = dialog and _G[dialog:GetName() .. "EditBox"]
    return trim(eb and eb:GetText() or "")
end

local function acceptAddAlt(dialog)
    local name = popupName(dialog)
    if name == "" then return end
    MiniGMDB.lastAlt = name
    cmd(".playerbots bot add " .. name)
    pendingAlt, pendingAt = name, GetTime()
end

local function acceptRemoveBot(dialog)
    local name = popupName(dialog)
    if name == "" then return end
    cmd(".playerbots bot remove " .. name)
end

StaticPopupDialogs["MINIGM_ADDALT"] = {
    text = "Alt character name to log in as a bot:",
    button1 = "Add", button2 = "Cancel",
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    enterClicksFirstButton = 1,
    OnShow = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        if eb then eb:SetText(MiniGMDB.lastAlt or "") eb:HighlightText() eb:SetFocus() end
    end,
    OnAccept = function(self) acceptAddAlt(self) end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        acceptAddAlt(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["MINIGM_REMOVEBOT"] = {
    text = "Bot/alt name to log out:",
    button1 = "Remove", button2 = "Cancel",
    hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
    enterClicksFirstButton = 1,
    OnShow = function(self)
        local eb = _G[self:GetName() .. "EditBox"]
        if eb then
            eb:SetText(playerTargetName() or MiniGMDB.lastAlt or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self) acceptRemoveBot(self) end,
    EditBoxOnEnterPressed = function(self)
        local dialog = self:GetParent()
        acceptRemoveBot(dialog)
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local refreshAltFlyout
function refreshAltFlyout()
    local me = UnitName("player")
    local names = {}
    for _, n in ipairs(MiniGMDB.alts or {}) do
        if n ~= me then table.insert(names, n) end
    end

    for _, b in ipairs(altFly.buttons) do b:Hide() end

    local index = 0
    for _, n in ipairs(names) do
        index = index + 1
        local b = altFly.buttons[index]
        if not b then
            b = CreateFrame("Button", nil, altFly, "UIPanelButtonTemplate")
            b:SetWidth(140)
            b:SetHeight(20)
            altFly.buttons[index] = b
        end
        b:SetPoint("TOPLEFT", altFly, "TOPLEFT", 10, -26 - (index - 1) * 22)
        b:SetText(n)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(self, mouseButton)
            if mouseButton == "RightButton" then
                forgetAlt(n)
                say("forgot alt " .. n)
                refreshAltFlyout()
                return
            end
            altFly:Hide()
            MiniGMDB.lastAlt = n
            cmd(".playerbots bot add " .. n)
        end)
        tip(b, "Left-click: log " .. n .. " in as a bot.\nRight-click: forget this name.")
        b:Show()
    end

    index = index + 1
    local other = altFly.buttons[index]
    if not other then
        other = CreateFrame("Button", nil, altFly, "UIPanelButtonTemplate")
        other:SetWidth(140)
        other:SetHeight(20)
        altFly.buttons[index] = other
    end
    other:SetPoint("TOPLEFT", altFly, "TOPLEFT", 10, -26 - (index - 1) * 22)
    other:SetText("Type a name...")
    other:RegisterForClicks("LeftButtonUp")
    other:SetScript("OnClick", function()
        altFly:Hide()
        StaticPopup_Show("MINIGM_ADDALT")
    end)
    other:Show()

    altFly:SetHeight(30 + index * 22 + 6)
end

local addBot = button("Add bot", function()
    altFly:Hide()
    if modFly then modFly:Hide() end
    if classFly:IsShown() then classFly:Hide() else classFly:Show() end
end, "Adds a bot of the chosen class at your level.")
classFly:SetPoint("TOPLEFT", addBot, "BOTTOMLEFT", 0, -2)

local addAlt = button("Add alt", function()
    classFly:Hide()
    if modFly then modFly:Hide() end
    if altFly:IsShown() then
        altFly:Hide()
    else
        refreshAltFlyout()
        altFly:Show()
    end
end, "Your alts are remembered as you log into them.\n/mgm forgetalt <name> removes one.")
altFly:SetPoint("TOPLEFT", addAlt, "BOTTOMLEFT", 0, -2)

button("Remove bot", function() StaticPopup_Show("MINIGM_REMOVEBOT") end,
    "Logs a bot/alt out. Pre-filled with your target.")

----------------------------------------------------------------------
-- TELE tab  -  who first, then the three-column picker
----------------------------------------------------------------------
beginPage(telePage)

local WHO_LABEL = { self = "Self", target = "Target", party = "Party", raid = "Raid" }
local teleWho   = "self"
local openPicker                      -- forward; defined with the picker below

section("Teleport")
button("Self",   function() openPicker("self")   end, "Teleport yourself.\nGoes straight there, no confirmation.")
button("Target", function() openPicker("target") end, "You teleport, then your target follows.\nSends 'summon' whispered (bots) and .summon (humans).\nAsks to confirm.")
button("Party",  function() openPicker("party")  end, "You teleport, then 'summon' goes to party chat -\none message moves every bot. Humans ignore it.\nAsks to confirm.")
button("Raid",   function() openPicker("raid")   end, "You teleport, then 'summon' goes to raid chat -\none message moves every bot. Humans ignore it.\nAsks to confirm.")

local teleStatus = telePage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
teleStatus:SetPoint("TOPLEFT", telePage, "TOPLEFT", 2, cursorY - 10)

local teleHint = telePage:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
teleHint:SetPoint("TOPLEFT", teleStatus, "BOTTOMLEFT", 0, -8)
teleHint:SetWidth(270)
teleHint:SetJustifyH("LEFT")
teleHint:SetText("The picker opens on the zone you are standing in. Every column stays clickable, so you can browse anywhere. Esc closes it.")

local function teleCount()
    local zones, locs = 0, 0
    if type(MiniGMTele) == "table" then
        for _, cont in pairs(MiniGMTele) do
            if type(cont) == "table" then
                for _, zone in pairs(cont) do
                    zones = zones + 1
                    if type(zone) == "table" then
                        for _ in pairs(zone) do locs = locs + 1 end
                    end
                end
            end
        end
    end
    return zones, locs
end

local function refreshTeleStatus()
    if type(MiniGMTele) ~= "table" or type(MiniGMTeleOrder) ~= "table" then
        teleStatus:SetText(RED .. "FAILED: Tele\\TeleportDB.lua did not load" .. R)
        return
    end
    local zones, locs = teleCount()
    if locs == 0 then
        teleStatus:SetText(RED .. "database is empty" .. R)
    else
        teleStatus:SetText(GREEN .. "loaded" .. R .. "  -  " .. GOLD .. locs .. R ..
                           " locations in " .. GOLD .. zones .. R .. " zones")
    end
end

beginPage(hudPage)

----------------------------------------------------------------------
-- teleport picker  -  its own frame on UIParent, so it stays centred and
-- ignores the HUD's position and scale entirely
----------------------------------------------------------------------
local PICK_W, PICK_H = 668, 372
local COLW, ROWH, VISROWS = 196, 15, 16

local pick = CreateFrame("Frame", "MiniGMTelePicker", UIParent)
pick:SetWidth(PICK_W)
pick:SetHeight(PICK_H)
pick:SetPoint("CENTER")
pick:SetFrameStrata("DIALOG")
pick:SetBackdrop({
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
})
pick:SetMovable(true)
pick:EnableMouse(true)
pick:SetClampedToScreen(true)
pick:RegisterForDrag("LeftButton")
pick:SetScript("OnDragStart", function() pick:StartMoving() end)
pick:SetScript("OnDragStop", function()
    pick:StopMovingOrSizing()
    local point, _, rel, x, y = pick:GetPoint()
    MiniGMDB.pickPos = { point = point, rel = rel, x = x, y = y }
end)
pick:Hide()
table.insert(UISpecialFrames, "MiniGMTelePicker")

local pickHeader = pick:CreateTexture(nil, "ARTWORK")
pickHeader:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
pickHeader:SetWidth(320)
pickHeader:SetHeight(64)
pickHeader:SetPoint("TOP", pick, "TOP", 0, 12)

local pickTitle = pick:CreateFontString(nil, "OVERLAY", "GameFontNormal")
pickTitle:SetPoint("TOP", pick, "TOP", 0, -2)

local pickClose = CreateFrame("Button", nil, pick, "UIPanelCloseButton")
pickClose:SetPoint("TOPRIGHT", pick, "TOPRIGHT", -8, -8)
pickClose:SetScript("OnClick", function() pick:Hide() end)

-- search box
local searchText = ""

-- Anchor the LABEL to the frame and hang the box off it. Anchoring the box
-- at x=26 and the label to its left put the label off the frame entirely.
local searchLabel = pick:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
searchLabel:SetPoint("TOPLEFT", pick, "TOPLEFT", 26, -40)
searchLabel:SetText("Search")

local searchBox = CreateFrame("EditBox", "MiniGMTeleSearch", pick, "InputBoxTemplate")
searchBox:SetWidth(220)
searchBox:SetHeight(18)
searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 12, 0)
searchBox:SetAutoFocus(false)
searchBox:SetMaxLetters(40)

local searchInfo = pick:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchInfo:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
searchInfo:SetText("filters every location in every zone")

----------------------------------------------------------------------
-- scrolling list widget (FauxScrollFrame, rows recycled by index)
----------------------------------------------------------------------
local function makeList(name, x, headerText)
    local L = {}
    L.items, L.onClick, L.selected = {}, nil, nil

    local head = pick:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    head:SetPoint("TOPLEFT", pick, "TOPLEFT", x, -64)
    head:SetText(GOLD .. headerText .. R)
    L.head = head

    local panel = CreateFrame("Frame", nil, pick)
    panel:SetWidth(COLW)
    panel:SetHeight(VISROWS * ROWH + 8)
    panel:SetPoint("TOPLEFT", pick, "TOPLEFT", x, -80)
    panel:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    panel:SetBackdropColor(0, 0, 0, 0.55)
    panel:SetBackdropBorderColor(0.45, 0.35, 0.15, 1)   -- muted gold edge

    local sf = CreateFrame("ScrollFrame", name, panel, "FauxScrollFrameTemplate")
    sf:SetWidth(COLW - 30)
    sf:SetHeight(VISROWS * ROWH)
    sf:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4)
    L.sf = sf

    L.rows = {}
    for i = 1, VISROWS do
        local b = CreateFrame("Button", nil, panel)
        b:SetWidth(COLW - 26)
        b:SetHeight(ROWH)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -4 - (i - 1) * ROWH)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("LEFT", b, "LEFT", 4, 0)
        fs:SetPoint("RIGHT", b, "RIGHT", -2, 0)
        fs:SetJustifyH("LEFT")
        b.label = fs
        b:Hide()
        L.rows[i] = b
    end

    function L:Update()
        local n = table.getn(self.items)
        FauxScrollFrame_Update(self.sf, n, VISROWS, ROWH)
        local off = FauxScrollFrame_GetOffset(self.sf)
        for i = 1, VISROWS do
            local idx = i + off
            local b = self.rows[i]
            if idx <= n then
                local it = self.items[idx]
                if it.key == self.selected then
                    b.label:SetText(RED .. it.text .. R)
                else
                    b.label:SetText(it.text)
                end
                b:SetScript("OnClick", function()
                    if self.onClick then self.onClick(it) end
                end)
                b:Show()
            else
                b:Hide()
            end
        end
    end

    sf:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROWH, function() L:Update() end)
    end)

    function L:SetItems(items, selected)
        self.items = items or {}
        self.selected = selected
        FauxScrollFrame_SetOffset(self.sf, 0)
        _G[name .. "ScrollBar"]:SetValue(0)
        self:Update()
    end

    return L
end

local listGroup = makeList("MiniGMTeleListGroup", 26,  "Continent Selection")
local listZone  = makeList("MiniGMTeleListZone",  236, "Zone Selection")
local listLoc   = makeList("MiniGMTeleListLoc",   446, "Locations")

----------------------------------------------------------------------
-- state + rendering
----------------------------------------------------------------------
local selGroup, selZone = nil, nil

local function sortedZones(g)
    local out = {}
    for z in pairs((MiniGMTele or {})[g] or {}) do table.insert(out, z) end
    table.sort(out)
    return out
end

local function sortedLocs(g, z)
    local out = {}
    local t = ((MiniGMTele or {})[g] or {})[z]
    if t then for n in pairs(t) do table.insert(out, n) end end
    table.sort(out)
    return out
end

local renderLocs, renderZones, renderGroups, doTeleport

-- where am I? used to preselect on open
local function findCurrentZone()
    if type(MiniGMTele) ~= "table" then return nil, nil end
    local zt = GetRealZoneText and GetRealZoneText() or ""
    if zt == "" then return nil, nil end
    for _, g in ipairs(MiniGMTeleOrder or {}) do
        if (MiniGMTele[g] or {})[zt] then return g, zt end
    end
    local lz = string.lower(zt)
    for _, g in ipairs(MiniGMTeleOrder or {}) do
        for z in pairs(MiniGMTele[g] or {}) do
            if string.lower(z) == lz then return g, z end
        end
    end
    return nil, nil
end

function renderLocs()
    local items = {}
    if searchText ~= "" then
        local needle = string.lower(searchText)
        for _, g in ipairs(MiniGMTeleOrder or {}) do
            for _, z in ipairs(sortedZones(g)) do
                for _, n in ipairs(sortedLocs(g, z)) do
                    if string.find(string.lower(n), needle, 1, true) then
                        table.insert(items, {
                            key = g .. "|" .. z .. "|" .. n,
                            text = n .. " |cff808080" .. z .. "|r",
                            cmd = MiniGMTele[g][z][n], name = n, zone = z,
                        })
                    end
                end
            end
        end
        listLoc.head:SetText(GOLD .. "Search: " .. R .. table.getn(items) .. " match(es)")
    else
        if selGroup and selZone then
            for _, n in ipairs(sortedLocs(selGroup, selZone)) do
                table.insert(items, {
                    key = selGroup .. "|" .. selZone .. "|" .. n,
                    text = n, cmd = MiniGMTele[selGroup][selZone][n],
                    name = n, zone = selZone,
                })
            end
            listLoc.head:SetText(GOLD .. "Zone: " .. R .. selZone)
        else
            listLoc.head:SetText(GOLD .. "Locations" .. R)
        end
    end
    listLoc.onClick = function(it) doTeleport(it.cmd, it.name, it.zone) end
    listLoc:SetItems(items, nil)
end

function renderZones()
    local items = {}
    if selGroup then
        for _, z in ipairs(sortedZones(selGroup)) do
            local c = 0
            for _ in pairs(MiniGMTele[selGroup][z]) do c = c + 1 end
            table.insert(items, { key = z, text = z .. " |cff808080" .. c .. "|r" })
        end
    end
    listZone.onClick = function(it)
        selZone = it.key
        searchText = ""
        searchBox:SetText("")
        -- repaint in place; SetItems would reset the scroll offset and yank
        -- the list back to the top when you pick a zone from far down
        listZone.selected = selZone
        listZone:Update()
        renderLocs()
    end
    listZone:SetItems(items, selZone)
end

function renderGroups()
    local items = {}
    for _, g in ipairs(MiniGMTeleOrder or {}) do
        local c = 0
        for _, z in pairs(MiniGMTele[g] or {}) do
            for _ in pairs(z) do c = c + 1 end
        end
        table.insert(items, { key = g, text = g .. " |cff808080" .. c .. "|r" })
    end
    listGroup.onClick = function(it)
        selGroup = it.key
        selZone = sortedZones(selGroup)[1]
        searchText = ""
        searchBox:SetText("")
        renderGroups()
        renderZones()
        renderLocs()
    end
    listGroup:SetItems(items, selGroup)
end

searchBox:SetScript("OnTextChanged", function(self)
    searchText = trim(self:GetText() or "")
    renderLocs()
end)
searchBox:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
end)

----------------------------------------------------------------------
-- execution:  .go xyz moves YOU only, so everyone else is summoned after
----------------------------------------------------------------------
-- How many are coming along - used for the confirmation text only.
local function rosterCount()
    local me = UnitName("player")
    local n = 0
    if teleWho == "raid" then
        local nr = (GetNumRaidMembers and GetNumRaidMembers() or 0)
        if nr == 0 then return nil, "You are not in a raid." end
        for i = 1, nr do
            local nm = UnitName("raid" .. i)
            if nm and nm ~= me then n = n + 1 end
        end
    else
        n = (GetNumPartyMembers and GetNumPartyMembers() or 0)
        if n == 0 then return nil, "You are not in a party." end
    end
    if n == 0 then return nil, "Nobody in the group but you." end
    return n, nil
end

local pendingTele = nil

StaticPopupDialogs["MINIGM_TELE_CONFIRM"] = {
    text = "%s",
    button1 = "Teleport", button2 = "Cancel",
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function()
        if pendingTele then pendingTele() end
        pendingTele = nil
    end,
    OnCancel = function() pendingTele = nil end,
}

-- VERIFIED Sep 21: `.summon <bot>` is a GM command aimed at PLAYERS. The
-- server accepts it and prints "You are summoning [X]" - and the bot does
-- not move. Playerbots obey the module's own `summon` command in party or
-- raid chat (or whispered), which also moves the WHOLE group in one message
-- instead of one .summon per member.
function doTeleport(goCmd, locName, zoneName)
    local where = locName .. " (" .. (zoneName or "?") .. ")"

    if teleWho == "self" then
        pick:Hide()
        cmd(goCmd)
        return
    end

    if teleWho == "target" then
        local t = playerTargetName()
        if not t then
            say(RED .. "No player targeted - target someone first." .. R)
            return
        end
        pendingTele = function()
            pick:Hide()
            cmd(goCmd)
            queueSend("summon", "WHISPER", t)   -- playerbots obey this
            cmd(".summon " .. t)                -- humans obey this
        end
        StaticPopup_Show("MINIGM_TELE_CONFIRM",
            "Teleport to " .. where .. "\nand bring " .. t .. "?")
        return
    end

    local n, err = rosterCount()
    if not n then
        say(RED .. err .. R)
        return
    end
    local channel = (teleWho == "raid") and "RAID" or "PARTY"
    pendingTele = function()
        pick:Hide()
        cmd(goCmd)
        queueSend("summon", channel)
        say("sent " .. GOLD .. "summon" .. R .. " to " .. string.lower(channel) ..
            " chat - human members do not obey it, summon them with Target.")
    end
    StaticPopup_Show("MINIGM_TELE_CONFIRM",
        "Teleport to " .. where .. "\nand summon your " ..
        string.lower(WHO_LABEL[teleWho]) .. " (" .. n .. ")?")
end

----------------------------------------------------------------------
function openPicker(who)
    if type(MiniGMTele) ~= "table" or type(MiniGMTeleOrder) ~= "table" then
        say(RED .. "Teleport database is not loaded - check Tele\\TeleportDB.lua." .. R)
        return
    end
    teleWho = who or "self"
    pickTitle:SetText("Teleport " .. GOLD .. WHO_LABEL[teleWho] .. R)
    pick:SetScale(MiniGMDB.pickScale or 1)   -- its own size, not the HUD's

    if MiniGMDB.pickPos then
        pick:ClearAllPoints()
        pick:SetPoint(MiniGMDB.pickPos.point, UIParent, MiniGMDB.pickPos.rel,
                      MiniGMDB.pickPos.x, MiniGMDB.pickPos.y)
    end

    -- open on where I'm standing; fall back to the first group
    local g, z = findCurrentZone()
    selGroup = g or (MiniGMTeleOrder or {})[1]
    selZone  = z or sortedZones(selGroup)[1]
    searchText = ""
    searchBox:SetText("")

    renderGroups()
    renderZones()
    renderLocs()

    if not g then
        say("current zone not in the directory - opened on " .. tostring(selGroup))
    end
    pick:Show()
end

----------------------------------------------------------------------
-- tab bar (hangs below the frame, same button style as everything else)
----------------------------------------------------------------------
local TAB_W, TAB_BH = 74, 22
local tabs, tabOrder = {}, {}

local function showTab(id)
    if not tabs[id] then id = "hud" end
    activeTab = id
    for _, tid in ipairs(tabOrder) do
        local b = tabs[tid]
        if tid == id then
            b:SetAlpha(1.0)
            b:LockHighlight()
        else
            b:SetAlpha(0.72)       -- inactive tabs sit back a little
            b:UnlockHighlight()
        end
    end
    if id == "tele" then
        hudPage:Hide()
        telePage:Show()
        refreshTeleStatus()
    else
        telePage:Hide()
        hudPage:Show()
    end
    if body:IsShown() then
        f:SetHeight(currentHeight())
    end
end

local function makeTab(id, label)
    local b = CreateFrame("Button", "MiniGMTab" .. id, f, "UIPanelButtonTemplate")
    b:SetWidth(TAB_W)
    b:SetHeight(TAB_BH)
    b:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 16 + table.getn(tabOrder) * (TAB_W + 4), 6)
    b:SetText(label)
    b:SetScript("OnClick", function() showTab(id) end)
    tabs[id] = b
    table.insert(tabOrder, id)
    return b
end

makeTab("hud",  "HUD")
makeTab("tele", "Tele")

----------------------------------------------------------------------
-- minimap icon (hand-rolled - this addon has no libraries by design)
----------------------------------------------------------------------
local MM_RADIUS = 80
local mmCheck                      -- forward; the toggle lives in the title strip

local mmBtn = CreateFrame("Button", "MiniGMMinimapButton", Minimap)
mmBtn:SetWidth(31)
mmBtn:SetHeight(31)
mmBtn:SetFrameStrata("MEDIUM")
mmBtn:SetFrameLevel(8)
mmBtn:SetMovable(true)
mmBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mmBtn:RegisterForDrag("LeftButton")
mmBtn:Hide()

local mmIcon = mmBtn:CreateTexture(nil, "BACKGROUND")
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
mmIcon:SetWidth(20)
mmIcon:SetHeight(20)
mmIcon:SetPoint("CENTER", mmBtn, "CENTER", 0, 1)
mmIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

local mmRing = mmBtn:CreateTexture(nil, "OVERLAY")
mmRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmRing:SetWidth(53)
mmRing:SetHeight(53)
mmRing:SetPoint("TOPLEFT", mmBtn, "TOPLEFT", 0, 0)

local function mmPlace()
    local a = math.rad(MiniGMDB.minimapAngle or 200)
    mmBtn:ClearAllPoints()
    mmBtn:SetPoint("CENTER", Minimap, "CENTER",
                   MM_RADIUS * math.cos(a), MM_RADIUS * math.sin(a))
end

local function mmApply()
    if MiniGMDB.minimapShow then
        mmPlace()
        mmBtn:Show()
    else
        mmBtn:Hide()
    end
    if mmCheck then mmCheck:SetChecked(MiniGMDB.minimapShow and true or false) end
end

-- shift-drag: follow the cursor's angle around the minimap centre
mmBtn:SetScript("OnDragStart", function(self)
    if not IsShiftKeyDown() then return end
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local sc = Minimap:GetEffectiveScale()
        if not (mx and my and sc and sc > 0) then return end
        MiniGMDB.minimapAngle = math.deg(math.atan2(py / sc - my, px / sc - mx))
        mmPlace()
    end)
end)
mmBtn:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)

mmBtn:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        if IsShiftKeyDown() then
            MiniGMDB.minimapShow = false
            mmApply()
            say("minimap icon hidden - the " .. GOLD .. "Minimap icon" .. R ..
                " box on the panel or " .. GOLD .. "/mgm minimap" .. R .. " brings it back.")
        end
        return
    end
    if f:IsShown() then f:Hide() else f:Show() end
end)

-- ANCHOR_RIGHT put the tooltip straight over the minimap; drop it down-left
tip(mmBtn, "MiniGM\nLeft-click: show / hide the panel\nShift-drag: move around the minimap\nShift-right-click: hide this icon",
    "ANCHOR_BOTTOMLEFT")

-- the toggle, in the strip under the title bar
mmCheck = CreateFrame("CheckButton", "MiniGMMinimapCheck", f, "OptionsCheckButtonTemplate")
mmCheck:SetWidth(20)
mmCheck:SetHeight(20)
mmCheck:SetPoint("TOP", f, "TOP", 0, -13)   -- recentred once the label measures
mmCheck:SetScript("OnClick", function(self)
    MiniGMDB.minimapShow = self:GetChecked() and true or false
    mmApply()
end)

local mmLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
mmLabel:SetPoint("LEFT", mmCheck, "RIGHT", 2, 0)
mmLabel:SetText("Minimap icon")

-- centre the checkbox+label PAIR on the frame, not just the box
local function centreMmToggle()
    local lw = mmLabel:GetStringWidth() or 0
    if lw <= 0 then return end                 -- 0 before the first draw
    local total = 20 + 2 + lw
    mmCheck:ClearAllPoints()
    mmCheck:SetPoint("TOP", f, "TOP", 10 - total / 2, -13)
end
centreMmToggle()
tip(mmCheck, "Show a MiniGM button on the minimap.\nLeft-click it to open and close this panel,\nshift-drag to move it, shift-right-click to hide it.")

----------------------------------------------------------------------
-- size grip (bottom-right)
-- This SCALES rather than resizes. Every button sits at a fixed pixel
-- offset, so a real SetResizable would just leave gaps instead of
-- reflowing. Scaling keeps the aspect ratio by definition, and the tele
-- picker is given the same scale so the two match.
----------------------------------------------------------------------
local SCALE_MIN, SCALE_MAX = 0.5, 2.0

local function clampScale(n)
    n = tonumber(n) or 1
    if n < SCALE_MIN then return SCALE_MIN end
    if n > SCALE_MAX then return SCALE_MAX end
    return n
end

-- The panel and the picker scale INDEPENDENTLY: each owns its size, its
-- position and its own grip.
local function applyScale(n)
    n = clampScale(n)
    MiniGMDB.scale = n
    f:SetScale(n)
    return n
end

local function applyPickScale(n)
    n = clampScale(n)
    MiniGMDB.pickScale = n
    pick:SetScale(n)
    return n
end

-- Scales rather than resizes: every widget sits at a fixed pixel offset, so
-- SetResizable would stretch the frame and leave the contents clustered in
-- the corner. Scaling keeps the proportions by definition.
local function attachGrip(frame, name, setScale, savePos, tipText)
    local g = CreateFrame("Button", name, frame)
    g:SetWidth(16)
    g:SetHeight(16)
    g:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -5, 5)
    g:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    g:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    g:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    tip(g, tipText)

    local L0, T0 = 0, 0

    local function onUpdate()
        local ui = UIParent:GetEffectiveScale()
        if not ui or ui <= 0 then return end
        local cx = GetCursorPosition() / ui         -- cursor in UIParent units
        local wanted = cx - L0                      -- on-screen width dragged to
        if wanted < 40 then return end
        local ns = clampScale(wanted / frame:GetWidth())   -- GetWidth() unscaled
        setScale(ns)
        -- keep the top-left pinned: SetPoint offsets are in the frame's own
        -- (now rescaled) units, so divide the captured position by ns
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", L0 / ns, T0 / ns)
    end

    g:SetScript("OnMouseDown", function(self)
        local sc = frame:GetScale()
        L0 = frame:GetLeft() * sc                   -- frame space -> UIParent units
        T0 = frame:GetTop()  * sc
        self:SetScript("OnUpdate", onUpdate)
    end)
    g:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        savePos()
    end)
    return g
end

attachGrip(f, "MiniGMSizeGrip", applyScale,
    function()
        local point, _, rel, x, y = f:GetPoint()
        MiniGMDB.pos = { point = point, rel = rel, x = x, y = y }
    end,
    "Drag to resize the panel.\nScales the whole panel, so the layout keeps its\nproportions. Sized independently of the picker.\n/mgm scale <0.5-2> sets it exactly.")

attachGrip(pick, "MiniGMTeleSizeGrip", applyPickScale,
    function()
        local point, _, rel, x, y = pick:GetPoint()
        MiniGMDB.pickPos = { point = point, rel = rel, x = x, y = y }
    end,
    "Drag to resize the teleport picker.\nSized independently of the panel.\n/mgm telescale <0.5-2> sets it exactly.")

----------------------------------------------------------------------
-- events, saved position, slash command
----------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("UNIT_MAXHEALTH")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("PLAYER_TARGET_CHANGED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
ev:RegisterEvent("RAID_ROSTER_UPDATE")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:SetScript("OnEvent", function(self, event, unit)
    if event == "CHAT_MSG_SYSTEM" then
        local msg = unit or ""
        if string.find(msg, "Enable player botAI", 1, true) then
            setSelfBot(true)
            say(RED .. "Self-bot is ON for " .. (UnitName("player") or "?") ..
                " - Maint/Gear will ask for your name first." .. R)
        elseif string.find(msg, "Disable player botAI", 1, true)
            or string.find(msg, "Self-bot is disabled", 1, true)
            or string.find(msg, "do not have permission to enable player botAI", 1, true) then
            if selfBotOn() then say("Self-bot is off.") end
            setSelfBot(false)
        end
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        flyActive = false            -- zoning/relog clears GM fly server-side
        return
    end

    if event == "PLAYER_LOGIN" then
        if MiniGMDB.pos then
            f:ClearAllPoints()
            f:SetPoint(MiniGMDB.pos.point, UIParent, MiniGMDB.pos.rel,
                       MiniGMDB.pos.x, MiniGMDB.pos.y)
        end
        applyScale(MiniGMDB.scale or 1)
        applyPickScale(MiniGMDB.pickScale or 1)
        fitHeader()                       -- string width is only real after a draw
        centreMmToggle()
        showTab("hud")                    -- always open on the HUD; Tele is a
                                          -- task you go to, never where you start
        mmApply()
        rememberAlt(UnitName("player"))
        updateSpeedButton()
        say("v" .. VERSION .. " loaded. " .. GOLD .. "/mgm" .. R .. " to show/hide.")
        updateHealMacro()
        updateReviveMacro()
    elseif event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        if pendingAlt then
            if GetTime() - (pendingAt or 0) > 120 then
                pendingAlt = nil                  -- never showed up; forget the request
            else
                local want = string.lower(pendingAlt)
                local prefix, count = "raid", GetNumRaidMembers()
                if count == 0 then prefix, count = "party", GetNumPartyMembers() end
                for i = 1, count do
                    local nm = UnitName(prefix .. i)
                    if nm and string.lower(nm) == want then
                        rememberAlt(nm)
                        pendingAlt = nil
                        refreshAltFlyout()
                        say("remembered " .. GOLD .. nm .. R .. " as an alt.")
                        break
                    end
                end
            end
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        if modFly and modFly:IsShown() then modFly.refresh() end
    elseif event == "UNIT_MAXHEALTH" then
        if unit == "player" then updateHealMacro() end
    else
        updateHealMacro()
    end
end)

SLASH_MINIGM1 = "/mgm"
SLASH_MINIGM2 = "/minigm"
SlashCmdList["MINIGM"] = function(msg)
    msg = trim(msg or "")
    local lower = string.lower(msg)

    if lower == "selfbot" then
        say("self-bot for " .. (UnitName("player") or "?") .. ": " ..
            (selfBotOn() and (RED .. "ON (Maint/Gear will ask for your name)" .. R) or "off"))
        return
    end
    if lower == "selfbot off" then
        setSelfBot(false)
        say("self-bot flag cleared for " .. (UnitName("player") or "?") ..
            ". This only resets MiniGM's memory - it does not change the server.")
        return
    end

    local run = string.match(lower, "^runspeed%s+([%d%.]+)$")
    if run then
        local n = tonumber(run)
        if n and n >= 0.1 and n <= 50 then
            if InCombatLockdown() then
                say(RED .. "Can't change the speed button in combat." .. R)
                return
            end
            MiniGMDB.runSpeed = n
            updateSpeedButton()
            say("run speed " .. n .. "  (1.0 normal, 1.6 = 60% mount, 2.0 = epic mount)")
        else
            say(RED .. "runspeed must be between 0.1 and 50 (server limit)" .. R)
        end
        return
    end

    local fly = string.match(lower, "^flyspeed%s+([%d%.]+)$")
    if fly then
        local n = tonumber(fly)
        if n and n >= 0.1 and n <= 50 then
            MiniGMDB.flySpeed = n
            say("fly speed " .. n .. "  (2.8 = epic 280%, 3.1 = fastest 310%, 4.65 = 1.5x fastest)")
        else
            say(RED .. "flyspeed must be between 0.1 and 50 (server limit)" .. R)
        end
        return
    end

    local mount = string.match(lower, "^flymount%s+(%d+)$")
    if mount then
        MiniGMDB.flyMount = tonumber(mount)
        say("fly mount displayID " .. mount .. "  (28652 = Armored Ebon Gryphon; 28082 the flying carpet CRASHED the server - do not use)")
        return
    end

    if lower == "minimap" then
        MiniGMDB.minimapShow = not MiniGMDB.minimapShow
        mmApply()
        say("minimap icon " .. (MiniGMDB.minimapShow and "on" or "off"))
        return
    end

    local tfit = string.match(lower, "^titlefit%s+([%d%.]+)$")
    if tfit then
        local n = tonumber(tfit)
        if n and n >= 1.0 and n <= 4.0 then
            MiniGMDB.titleFit = n
            fitHeader()
            say("title fit " .. n .. "  (header width = title width x " .. n .. " + 16)")
        else
            say(RED .. "titlefit must be between 1.0 and 4.0" .. R)
        end
        return
    end

    local tscale = string.match(lower, "^telescale%s+([%d%.]+)$")
    if tscale then
        local n = tonumber(tscale)
        if n and n >= 0.5 and n <= 2 then
            applyPickScale(n)
            say("teleport picker scale " .. n)
        else
            say(RED .. "telescale must be between 0.5 and 2" .. R)
        end
        return
    end

    local scale = string.match(lower, "^scale%s+([%d%.]+)$")
    if scale then
        local n = tonumber(scale)
        if n and n >= 0.5 and n <= 2 then
            applyScale(n)
            say("scale " .. n)
        else
            say(RED .. "scale must be between 0.5 and 2" .. R)
        end
        return
    end

    local add = string.match(msg, "^[Aa]ddalt%s+(.+)$")
    if add then
        local added = {}
        for part in string.gmatch(add, "[^,]+") do
            local name = trim(part)
            if name ~= "" then
                rememberAlt(name)
                table.insert(added, name)
            end
        end
        if table.getn(added) > 0 then
            say("added to the alt list: " .. table.concat(added, ", "))
        end
        return
    end

    local forget = string.match(msg, "^[Ff]orgetalt%s+(.+)$")
    if forget then
        if forgetAlt(trim(forget)) then
            say("forgot alt " .. trim(forget))
        else
            say(RED .. "not in the alt list: " .. trim(forget) .. R)
        end
        return
    end

    if lower == "alts" then
        say("remembered alts: " .. table.concat(MiniGMDB.alts or {}, ", "))
        return
    end

    if lower == "reset" then
        MiniGMDB.pos = nil
        MiniGMDB.pickPos = nil
        applyScale(1)
        applyPickScale(1)
        f:ClearAllPoints()
        f:SetPoint("CENTER")
        pick:ClearAllPoints()
        pick:SetPoint("CENTER")
        say("position and scale reset (panel and picker)")
        return
    end

    if lower == "help" then
        say("/mgm - show/hide  |  /mgm scale <0.5-2>  |  /mgm reset")
        say("/mgm telescale <0.5-2>  - teleport picker size, current " ..
            (MiniGMDB.pickScale or 1) .. "  (or drag its bottom-right corner)")
        say("/mgm titlefit <1.0-4.0>  - header width vs title width, current " ..
            (MiniGMDB.titleFit or 1.9))
        say("/mgm minimap  - toggle the minimap icon (currently " ..
            (MiniGMDB.minimapShow and "on" or "off") .. ")")
        say("/mgm alts  |  /mgm addalt <Name>  |  /mgm forgetalt <Name>  (or right-click a name in the Add alt list)")
        say("/mgm runspeed <0.1-50>  - current " .. (MiniGMDB.runSpeed or 1.5) ..
            "  (1.0 normal, 1.6 = 60% mount, 2.0 = epic mount)")
        say("/mgm flyspeed <0.1-50>  - current " .. (MiniGMDB.flySpeed or 4.65) ..
            "  (2.8 epic, 3.1 fastest, 4.65 = 1.5x fastest)")
        say("/mgm flymount <displayID>  - current " .. (MiniGMDB.flyMount or 28652))
        say("/mgm selfbot  - is self-bot on for this character?  |  /mgm selfbot off  - clear MiniGM's flag")
        return
    end

    if f:IsShown() then f:Hide() else f:Show() end
end
