------------------------------------------------------------------------
-- OneGuild - Loot.lua
-- Auto-Pass loot system for guild raids.
-- When active, all members automatically pass on loot rolls so only
-- the Raid Leader receives items.  The RL then distributes via DKP.
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Loot.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local LOOT_CHECK_TIMEOUT = 8       -- seconds to wait for addon-check replies
local ROLL_PASS          = 0       -- WoW API: 0 = pass

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local lootSystemActive    = false   -- is auto-pass currently enabled?
local lootCheckResults    = {}      -- { ["Name-Realm"] = { version, responded } }
local lootCheckInProgress = false
local lootCheckFrame      = nil     -- UI frame for check results
local autoPassHooked      = false   -- whether the START_LOOT_ROLL hook is installed

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function IsInGuildRaid()
    if not IsInRaid() then return false end
    if not IsInGuild() then return false end

    -- Build a set of guild member names (short names)
    local guildMembers = {}
    local numGuild = GetNumGuildMembers() or 0
    for i = 1, numGuild do
        local gName = GetGuildRosterInfo(i)
        if gName then
            local short = strsplit("-", gName)
            guildMembers[short] = true
            guildMembers[gName] = true
        end
    end

    -- Check all raid members are in our guild
    local numRaid = GetNumGroupMembers() or 0
    if numRaid == 0 then return false end

    for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
            local short = strsplit("-", name)
            if not guildMembers[name] and not guildMembers[short] then
                return false
            end
        end
    end

    return true
end

local function IsRaidLeader()
    return UnitIsGroupLeader("player") == true
end

local function IsRaidAssist()
    return UnitIsGroupAssistant("player") == true
end

local function GetMyFullName()
    local name  = UnitName("player") or ""
    local realm = GetNormalizedRealmName() or GetRealmName() or ""
    return name .. "-" .. realm
end

--- Get current Lootmeister name (global setting)
local function GetCurrentLootmeister()
    if not OneGuild.db then return nil end
    local lm = OneGuild.db.lootmeister
    if lm and lm ~= "" then return lm end
    return nil
end

--- Check if the local player IS the Lootmeister
local function IsLootmeister()
    local lm = GetCurrentLootmeister()
    if not lm then return false end
    local myName = UnitName("player") or ""
    return myName == lm
end

------------------------------------------------------------------------
-- Get all current raid member names
------------------------------------------------------------------------
local function GetRaidMemberList()
    local list = {}
    local numRaid = GetNumGroupMembers() or 0
    for i = 1, numRaid do
        local name = GetRaidRosterInfo(i)
        if name then
            -- Ensure full name with realm
            if not name:find("-") then
                local realm = GetNormalizedRealmName() or GetRealmName() or ""
                name = name .. "-" .. realm
            end
            list[name] = true
        end
    end
    return list
end

------------------------------------------------------------------------
-- AUTO-PASS SYSTEM
------------------------------------------------------------------------

--- Hook into WoW's loot roll system
local function OnStartLootRoll(rollID, rollTime, ...)
    if not lootSystemActive then return end
    if not OneGuild.db then return end
    if not OneGuild.db.settings.lootAutoPass then return end

    -- Only in guild raids
    if not IsInGuildRaid() then return end

    local lm = GetCurrentLootmeister()

    -- If no Lootmeister is set, fall back to Raid Leader behavior
    if not lm then
        if IsRaidLeader() then
            OneGuild:Debug("Loot: Kein LM gesetzt, ich bin RL — KEIN Auto-Pass")
            return
        end
    else
        -- Lootmeister does NOT auto-pass — they collect the loot
        if IsLootmeister() then
            OneGuild:Debug("Loot: Ich bin der Lootmeister (" .. lm .. ") — KEIN Auto-Pass")
            return
        end
    end

    -- Auto-pass on everything
    C_Timer.After(0.1, function()
        ConfirmLootRoll(rollID, ROLL_PASS)
        OneGuild:Debug("Loot: Auto-Pass auf Roll #" .. tostring(rollID))
    end)

    -- Notify in chat
    local target = lm or "Raid Leader"
    OneGuild:Print(OneGuild.COLORS.INFO .. "Auto-Pass aktiv — Loot geht an den Lootmeister (" .. target .. ")|r")
end

--- Install the loot hook
function OneGuild:EnableAutoPass()
    if autoPassHooked then return end
    autoPassHooked = true

    local lootFrame = CreateFrame("Frame", "OneGuildLootFrame", UIParent)
    lootFrame:RegisterEvent("START_LOOT_ROLL")
    lootFrame:SetScript("OnEvent", function(self, event, ...)
        if event == "START_LOOT_ROLL" then
            OnStartLootRoll(...)
        end
    end)

    OneGuild:Debug("Loot: Auto-Pass Hook installiert")
end

--- Activate loot system (called when entering a guild raid)
function OneGuild:ActivateLootSystem()
    if lootSystemActive then return end
    if not self.db or not self.db.settings.lootAutoPass then return end

    lootSystemActive = true
    self:EnableAutoPass()
    local lm = GetCurrentLootmeister()
    local target = lm and ("Lootmeister (" .. lm .. ")") or "Raid Leader"
    self:Print(OneGuild.COLORS.SUCCESS ..
        "Loot-System aktiviert! Alle Items gehen automatisch an den " .. target .. ".|r")
    -- Real-time UI update
    if self.RefreshRaidGroups then self:RefreshRaidGroups() end
    if self.RefreshAddonCheckWindow then self:RefreshAddonCheckWindow() end
end

--- Deactivate loot system
function OneGuild:DeactivateLootSystem()
    if not lootSystemActive then return end
    lootSystemActive = false
    self:Print(OneGuild.COLORS.WARNING .. "Loot-System deaktiviert.|r")
    -- Real-time UI update
    if self.RefreshRaidGroups then self:RefreshRaidGroups() end
    if self.RefreshAddonCheckWindow then self:RefreshAddonCheckWindow() end
end

--- Check if loot system is currently active
function OneGuild:IsLootSystemActive()
    return lootSystemActive
end

--- Get loot check results (for RaidGroups display)
function OneGuild:GetLootCheckResults()
    return lootCheckResults
end

--- Check if a loot check is currently running
function OneGuild:IsLootCheckInProgress()
    return lootCheckInProgress
end

------------------------------------------------------------------------
-- ADDON CHECK SYSTEM
-- RL sends LCK → all members with addon reply LCR with their version
------------------------------------------------------------------------

--- Start addon check (RL/Assist only)
function OneGuild:StartAddonCheck()
    if not IsInRaid() then
        self:PrintError("Du bist nicht in einem Raid!")
        return
    end

    -- Allow RL, Assist, or Whitelist users
    local myName = UnitName("player") or ""
    local allowed = IsRaidLeader() or IsRaidAssist()
    if not allowed and self.ADMIN_WHITELIST and self.ADMIN_WHITELIST[myName] then
        allowed = true
    end
    if not allowed then
        self:PrintError("Nur der Raid Leader, Assistent oder Admin kann den Addon-Check starten!")
        return
    end

    lootCheckResults = {}
    lootCheckInProgress = true

    -- Build list of all raid members
    local raidMembers = GetRaidMemberList()
    for name, _ in pairs(raidMembers) do
        lootCheckResults[name] = {
            version   = nil,
            responded = false,
        }
    end

    -- Mark ourselves as responded
    local myFull = GetMyFullName()
    if lootCheckResults[myFull] then
        lootCheckResults[myFull].version   = OneGuild.VERSION
        lootCheckResults[myFull].responded = true
    end

    -- Send check request
    self:SendCommMessage("LCK", OneGuild.VERSION)

    -- Show results window
    self:ShowAddonCheckWindow()

    -- Timeout: finalize after LOOT_CHECK_TIMEOUT seconds
    C_Timer.After(LOOT_CHECK_TIMEOUT, function()
        lootCheckInProgress = false
        OneGuild:RefreshAddonCheckWindow()
    end)

    self:Print(OneGuild.COLORS.INFO ..
        "Addon-Check gestartet... Warte " .. LOOT_CHECK_TIMEOUT .. " Sekunden auf Antworten.|r")
end

--- Handle incoming LCK (check request)
function OneGuild:HandleLootCheckRequest(sender, data)
    if not IsInRaid() then return end
    -- Reply with our version
    self:SendCommMessage("LCR", OneGuild.VERSION)
    self:Debug("Loot-Check: Anfrage von " .. sender .. " beantwortet (v" .. OneGuild.VERSION .. ")")
end

--- Handle incoming LCR (check response)
function OneGuild:HandleLootCheckResponse(sender, data)
    if not lootCheckInProgress then return end
    local version = data or "?"

    -- Find this sender in our results (match with/without realm)
    for memberName, info in pairs(lootCheckResults) do
        -- Match full name or short name
        local shortMember = strsplit("-", memberName)
        local shortSender = strsplit("-", sender)
        if memberName == sender or shortMember == shortSender then
            info.version   = version
            info.responded = true
            break
        end
    end

    self:RefreshAddonCheckWindow()
end

------------------------------------------------------------------------
-- ADDON CHECK UI
------------------------------------------------------------------------
function OneGuild:ShowAddonCheckWindow()
    if lootCheckFrame then
        lootCheckFrame:Show()
        self:RefreshAddonCheckWindow()
        return
    end

    local f = CreateFrame("Frame", "OneGuildAddonCheckFrame", UIParent, "BackdropTemplate")
    f:SetSize(380, 420)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(250)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.04, 0.04, 0.97)
    f:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.8)

    -- Title bar
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(36)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
        OneGuild.COLORS.MUTED .. "Addon-Check|r")

    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Status text
    f.statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.statusText:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)

    -- Scroll area for results
    local scrollParent = CreateFrame("Frame", nil, f)
    scrollParent:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -65)
    scrollParent:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 50)
    f.scrollParent = scrollParent

    f.rows = {}

    -- Bottom buttons
    -- "Alle bereit" button (activates loot system)
    local activateBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    activateBtn:SetSize(160, 28)
    activateBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 12)
    activateBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    activateBtn:SetBackdropColor(0.1, 0.35, 0.1, 0.9)
    activateBtn:SetBackdropBorderColor(0.3, 0.7, 0.3, 0.6)

    local activateBtnText = activateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activateBtnText:SetPoint("CENTER")
    activateBtnText:SetText("|cFF66FF66Loot-System aktivieren|r")
    f.activateBtn = activateBtn
    f.activateBtnText = activateBtnText

    activateBtn:SetScript("OnClick", function()
        -- Check if all responded with correct version
        local allReady = true
        for _, info in pairs(lootCheckResults) do
            if not info.responded or info.version ~= OneGuild.VERSION then
                allReady = false
                break
            end
        end

        if allReady then
            OneGuild:ActivateLootSystem()
            -- Notify everyone to activate
            OneGuild:SendCommMessage("LAP", "1")
            OneGuild:PrintSuccess("Loot-System für alle aktiviert!")
        else
            OneGuild:PrintError("Nicht alle Spieler haben das aktuelle Addon! Kann nicht aktivieren.")
        end
    end)

    activateBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.45, 0.15, 1)
    end)
    activateBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.35, 0.1, 0.9)
    end)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    refreshBtn:SetSize(160, 28)
    refreshBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 12)
    refreshBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    refreshBtn:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    refreshBtn:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)

    local refreshBtnText = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refreshBtnText:SetPoint("CENTER")
    refreshBtnText:SetText("|cFFFFD700Erneut prüfen|r")

    refreshBtn:SetScript("OnClick", function()
        OneGuild:StartAddonCheck()
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.3, 0.08, 1)
    end)
    refreshBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    end)

    -- Deactivate button (shown when loot system is active)
    local deactivateBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    deactivateBtn:SetSize(340, 28)
    deactivateBtn:SetPoint("BOTTOM", activateBtn, "TOP", 80, 6)
    deactivateBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    deactivateBtn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    deactivateBtn:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.6)

    local deactivateBtnText = deactivateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deactivateBtnText:SetPoint("CENTER")
    deactivateBtnText:SetText("|cFFFF6666Loot-System deaktivieren|r")
    f.deactivateBtn = deactivateBtn

    deactivateBtn:SetScript("OnClick", function()
        OneGuild:DeactivateLootSystem()
        -- Notify everyone to deactivate
        OneGuild:SendCommMessage("LAP", "0")
        OneGuild:PrintSuccess("Loot-System für alle deaktiviert!")
    end)
    deactivateBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.55, 0.15, 0.15, 1)
    end)
    deactivateBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
    end)

    lootCheckFrame = f
    self:RefreshAddonCheckWindow()
end

function OneGuild:RefreshAddonCheckWindow()
    if not lootCheckFrame or not lootCheckFrame:IsShown() then return end
    local f = lootCheckFrame

    -- Count stats
    local total     = 0
    local responded = 0
    local current   = 0 -- correct version
    local missing   = 0

    for name, info in pairs(lootCheckResults) do
        total = total + 1
        if info.responded then
            responded = responded + 1
            if info.version == OneGuild.VERSION then
                current = current + 1
            end
        end
    end
    missing = total - responded

    -- Status text
    local statusColor = "|cFFFFCC00"
    if not lootCheckInProgress and current == total then
        statusColor = "|cFF66FF66"
    elseif not lootCheckInProgress and missing > 0 then
        statusColor = "|cFFFF4444"
    end

    local statusStr
    if lootCheckInProgress then
        statusStr = "|cFFFFCC00Prüfe... |r" ..
            responded .. "/" .. total .. " Antworten"
    else
        statusStr = statusColor .. responded .. "/" .. total .. " bereit|r"
        if missing > 0 then
            statusStr = statusStr .. "  |cFFFF4444(" .. missing .. " fehlen!)|r"
        end
    end
    f.statusText:SetText(statusStr)

    -- Hide old rows
    for _, row in ipairs(f.rows) do
        row:Hide()
    end

    -- Build sorted list
    local sorted = {}
    for name, info in pairs(lootCheckResults) do
        table.insert(sorted, { name = name, info = info })
    end
    table.sort(sorted, function(a, b)
        -- Responded first, then by name
        if a.info.responded ~= b.info.responded then
            return a.info.responded
        end
        return a.name < b.name
    end)

    -- Create/update rows
    local ROW_H = 24
    for i, entry in ipairs(sorted) do
        local row = f.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, f.scrollParent, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", f.scrollParent, "TOPLEFT", 0, -((i - 1) * (ROW_H + 2)))
            row:SetPoint("TOPRIGHT", f.scrollParent, "TOPRIGHT", 0, -((i - 1) * (ROW_H + 2)))
            row:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets   = { left = 2, right = 2, top = 2, bottom = 2 },
            })

            row.statusIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.statusIcon:SetPoint("LEFT", row, "LEFT", 8, 0)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.nameText:SetPoint("LEFT", row.statusIcon, "RIGHT", 6, 0)

            row.versionText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.versionText:SetPoint("RIGHT", row, "RIGHT", -8, 0)

            f.rows[i] = row
        end

        row:Show()

        -- Display name (short, without realm)
        local shortName = strsplit("-", entry.name)
        row.nameText:SetText(shortName or entry.name)

        if entry.info.responded then
            if entry.info.version == OneGuild.VERSION then
                -- Correct version
                row:SetBackdropColor(0.05, 0.15, 0.05, 0.8)
                row:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.5)
                row.statusIcon:SetText("|cFF66FF66✔|r")
                row.nameText:SetTextColor(0.6, 1, 0.6)
                row.versionText:SetText("|cFF66FF66v" .. entry.info.version .. "|r")
            else
                -- Wrong version
                row:SetBackdropColor(0.2, 0.1, 0.02, 0.8)
                row:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.5)
                row.statusIcon:SetText("|cFFFF8800⚠|r")
                row.nameText:SetTextColor(1, 0.7, 0.3)
                row.versionText:SetText("|cFFFF8800v" .. (entry.info.version or "?") ..
                    " (braucht v" .. OneGuild.VERSION .. ")|r")
            end
        else
            -- Not responded
            if lootCheckInProgress then
                row:SetBackdropColor(0.1, 0.08, 0.04, 0.8)
                row:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.3)
                row.statusIcon:SetText("|cFFFFCC00...|r")
                row.nameText:SetTextColor(0.7, 0.6, 0.4)
                row.versionText:SetText("|cFFFFCC00Warte...|r")
            else
                row:SetBackdropColor(0.15, 0.05, 0.05, 0.8)
                row:SetBackdropBorderColor(0.5, 0.15, 0.15, 0.5)
                row.statusIcon:SetText("|cFFFF4444✘|r")
                row.nameText:SetTextColor(1, 0.4, 0.4)
                row.versionText:SetText("|cFFFF4444Kein Addon|r")
            end
        end
    end

    -- Enable/disable activate button based on check results + loot state
    local allReady = (current == total and total > 0 and not lootCheckInProgress)
    if lootSystemActive then
        -- Loot system already active — show deactivate, disable activate
        f.activateBtn:Disable()
        f.activateBtn:SetBackdropColor(0.05, 0.15, 0.05, 0.4)
        f.activateBtnText:SetText("|cFF66FF66\226\156\148 Loot: AKTIV|r")
        if f.deactivateBtn then f.deactivateBtn:Show() end
    elseif allReady then
        f.activateBtn:Enable()
        f.activateBtn:SetBackdropColor(0.1, 0.35, 0.1, 0.9)
        f.activateBtnText:SetText("|cFF66FF66Loot-System aktivieren|r")
        if f.deactivateBtn then f.deactivateBtn:Hide() end
    else
        f.activateBtn:Disable()
        f.activateBtn:SetBackdropColor(0.15, 0.1, 0.1, 0.6)
        f.activateBtnText:SetText("|cFF666666Loot-System aktivieren|r")
        if f.deactivateBtn then f.deactivateBtn:Hide() end
    end
end

------------------------------------------------------------------------
-- Handle LAP (Loot Auto-Pass activation from RL)
------------------------------------------------------------------------
function OneGuild:HandleLootActivate(sender, data)
    if not IsInRaid() then return end
    if data == "1" then
        self:ActivateLootSystem()
    elseif data == "0" then
        self:DeactivateLootSystem()
    end
    -- Real-time UI refresh
    if self.RefreshRaidGroups then self:RefreshRaidGroups() end
end

------------------------------------------------------------------------
-- Auto-detect raid join/leave to manage loot system
------------------------------------------------------------------------
function OneGuild:InitLoot()
    if not self.db then return end

    -- Always install the hook (it checks lootSystemActive internally)
    self:EnableAutoPass()

    -- Monitor raid status changes
    local raidFrame = CreateFrame("Frame", "OneGuildRaidStatusFrame", UIParent)
    raidFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    raidFrame:RegisterEvent("GROUP_LEFT")
    raidFrame:SetScript("OnEvent", function(self, event)
        if event == "GROUP_LEFT" then
            -- Left the group — deactivate
            if lootSystemActive then
                OneGuild:DeactivateLootSystem()
            end
        elseif event == "GROUP_ROSTER_UPDATE" then
            -- If loot system is active but we're no longer in a guild raid, deactivate
            if lootSystemActive and not IsInGuildRaid() then
                OneGuild:DeactivateLootSystem()
            end
        end
    end)

    self:Debug("Loot: System initialisiert")
end
