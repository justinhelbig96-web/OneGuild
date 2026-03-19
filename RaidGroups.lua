------------------------------------------------------------------------
-- OneGuild - RaidGroups.lua
-- MRT-style raid group manager with drag & drop roster panel.
-- Allows RL/Assist to drag players from the roster into groups 1-8.
-- Shows addon-check status (✔/✘) behind each player name.
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r RaidGroups.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local MAX_GROUPS     = 8
local MAX_PER_GROUP  = 5
local CELL_W         = 130
local CELL_H         = 18
local GROUP_PAD      = 6
local GROUP_W        = CELL_W + 14
local GROUP_H        = (CELL_H * MAX_PER_GROUP) + 36
local ROSTER_W       = 170
local FRAME_W        = (GROUP_W * 4) + (GROUP_PAD * 3) + ROSTER_W + 44
local FRAME_H        = (GROUP_H * 2) + (GROUP_PAD) + 86

------------------------------------------------------------------------
-- Class colors
------------------------------------------------------------------------
local CLASS_COLORS_FB = {
    WARRIOR     = { r = 0.78, g = 0.61, b = 0.43 },
    PALADIN     = { r = 0.96, g = 0.55, b = 0.73 },
    HUNTER      = { r = 0.67, g = 0.83, b = 0.45 },
    ROGUE       = { r = 1.00, g = 0.96, b = 0.41 },
    PRIEST      = { r = 1.00, g = 1.00, b = 1.00 },
    DEATHKNIGHT = { r = 0.77, g = 0.12, b = 0.23 },
    SHAMAN      = { r = 0.00, g = 0.44, b = 0.87 },
    MAGE        = { r = 0.25, g = 0.78, b = 0.92 },
    WARLOCK     = { r = 0.53, g = 0.53, b = 0.93 },
    MONK        = { r = 0.00, g = 1.00, b = 0.60 },
    DRUID       = { r = 1.00, g = 0.49, b = 0.04 },
    DEMONHUNTER = { r = 0.64, g = 0.19, b = 0.79 },
    EVOKER      = { r = 0.20, g = 0.58, b = 0.50 },
}

-- Role icon texture (for signup display)
local ROLE_TEX    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK   = { 0,        19/64,  22/64, 41/64 },
    HEALER = { 20/64,    39/64,  1/64,  20/64 },
    DD     = { 20/64,    39/64,  22/64, 41/64 },
}
local ROLE_LABELS_SHORT = { TANK = "Tank", HEALER = "Healer", DD = "DD" }

local function GetCC(cf)
    if not cf then return 0.7, 0.7, 0.7 end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf] then
        local c = RAID_CLASS_COLORS[cf]
        return c.r, c.g, c.b
    end
    local c = CLASS_COLORS_FB[cf]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

local function ClassHex(cf)
    local r, g, b = GetCC(cf)
    return string.format("|cFF%02x%02x%02x", r * 255, g * 255, b * 255)
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local groupsFrame     = nil
local groupPanels     = {}   -- [1..8]
local rosterCells     = {}   -- right-side roster list cells
local dragFrame       = nil  -- floating drag indicator
local dragPlayerName  = nil  -- name being dragged
local dragPlayerClass = nil  -- class of player being dragged

-- Forward declarations
local MoveToGroup
local RemoveFromGroup

-- Permission check: RL, Assist, or Whitelist can edit groups
local function CanEditGroups()
    local myName = UnitName("player") or ""
    -- Whitelist always allowed
    if OneGuild:IsOnWhitelist(myName) then
        return true
    end
    -- In raid: RL or Assist
    if IsInRaid() then
        if UnitIsGroupLeader("player") or UnitIsGroupAssistant("player") then
            return true
        end
    end
    -- Addon-admin (guild leader)
    if OneGuild.isAdmin then return true end
    return false
end

------------------------------------------------------------------------
-- Get current raid roster grouped
------------------------------------------------------------------------
local function GetRaidGroups()
    local groups = {}
    for g = 1, MAX_GROUPS do groups[g] = {} end
    if not IsInRaid() then return groups, {} end

    local numRaid = GetNumGroupMembers() or 0
    local allMembers = {}
    for i = 1, numRaid do
        local name, rank, subgroup, level, classLoc, classFile,
              zone, online, isDead, role, isML, combatRole = GetRaidRosterInfo(i)
        if name then
            local member = {
                index     = i,
                name      = name,
                rank      = rank,
                level     = level or 0,
                classFile = classFile or "",
                online    = online,
                role      = combatRole or "NONE",
                group     = subgroup or 1,
            }
            local g = subgroup or 1
            if g >= 1 and g <= MAX_GROUPS then
                table.insert(groups[g], member)
            end
            table.insert(allMembers, member)
        end
    end
    return groups, allMembers
end

------------------------------------------------------------------------
-- Addon-check status for a player name
-- Returns: "ok", "wrong", "missing", "unknown"
------------------------------------------------------------------------
local function GetAddonStatus(playerName)
    if not OneGuild.GetLootCheckResults then return "unknown" end
    local results = OneGuild:GetLootCheckResults()
    if not results or not next(results) then return "unknown" end

    local shortPlayer = strsplit("-", playerName)
    for memberName, info in pairs(results) do
        local shortMember = strsplit("-", memberName)
        if memberName == playerName or shortMember == shortPlayer then
            if info.responded then
                if info.version == OneGuild.VERSION then
                    return "ok"
                else
                    return "wrong"
                end
            else
                return "missing"
            end
        end
    end
    return "unknown"
end

local function AddonStatusIcon(status)
    if status == "ok"      then return " |cFF66FF66\226\156\148|r"
    elseif status == "wrong"   then return " |cFFFF8800\226\154\160|r"
    elseif status == "missing" then return " |cFFFF4444\226\156\152|r"
    else return ""
    end
end

------------------------------------------------------------------------
-- Drag & Drop helpers
------------------------------------------------------------------------
local function CreateDragFrame()
    if dragFrame then return dragFrame end
    local f = CreateFrame("Frame", "OneGuildDragFrame", UIParent)
    f:SetSize(CELL_W, CELL_H)
    f:SetFrameStrata("TOOLTIP")
    f:SetFrameLevel(500)

    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.bg:SetColorTexture(0.3, 0.2, 0.05, 0.85)

    f.text = f:CreateFontString(nil, "OVERLAY")
    f.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    f.text:SetPoint("CENTER")

    f:Hide()
    dragFrame = f
    return f
end

local function StartDrag(playerName, classFile)
    if not CanEditGroups() then return end
    dragPlayerName  = playerName
    dragPlayerClass = classFile
    local df = CreateDragFrame()
    local shortName = strsplit("-", playerName)
    df.text:SetText(ClassHex(classFile) .. shortName .. "|r")
    df:Show()
end

local function StopDrag()
    if dragPlayerName then
        -- Check individual cells first for slot-specific placement
        for g = 1, MAX_GROUPS do
            local panel = groupPanels[g]
            if panel then
                for s = 1, MAX_PER_GROUP do
                    local cell = panel.cells[s]
                    if cell and cell:IsMouseOver() then
                        MoveToGroup(dragPlayerName, g, s)
                        dragPlayerName  = nil
                        dragPlayerClass = nil
                        if dragFrame then dragFrame:Hide() end
                        return
                    end
                end
                -- Fallback: dropped on group panel header/border area
                if panel:IsMouseOver() then
                    MoveToGroup(dragPlayerName, g)
                    dragPlayerName  = nil
                    dragPlayerClass = nil
                    if dragFrame then dragFrame:Hide() end
                    return
                end
            end
        end
        -- Check if dropped on roster panel (remove from group)
        if groupsFrame and groupsFrame.rosterPanel and groupsFrame.rosterPanel:IsMouseOver() then
            RemoveFromGroup(dragPlayerName)
        end
    end
    dragPlayerName  = nil
    dragPlayerClass = nil
    if dragFrame then dragFrame:Hide() end
end

local function UpdateDragPosition()
    if not dragFrame or not dragFrame:IsShown() then return end
    local x, y = GetCursorPosition()
    local scale = UIParent:GetEffectiveScale()
    dragFrame:ClearAllPoints()
    dragFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
end

------------------------------------------------------------------------
-- Move player to group (addon-managed)
------------------------------------------------------------------------
MoveToGroup = function(playerName, targetGroup, targetSlot)
    if not CanEditGroups() then
        OneGuild:Print("|cFFFF4444Nur Raidleader, Assistenten oder Admins können Gruppen bearbeiten.|r")
        return
    end
    if not OneGuild.db then return end
    if not OneGuild.db.raidGroups then OneGuild.db.raidGroups = {} end
    local rg = OneGuild.db.raidGroups

    -- Remove from any existing group/slot first
    for g = 1, MAX_GROUPS do
        if rg[g] then
            for s = 1, MAX_PER_GROUP do
                if rg[g][s] == playerName then
                    rg[g][s] = nil
                end
            end
        end
    end

    -- Ensure target group table exists
    if not rg[targetGroup] then rg[targetGroup] = {} end

    -- If a specific slot was given and it's free, use it
    if targetSlot and targetSlot >= 1 and targetSlot <= MAX_PER_GROUP then
        if not rg[targetGroup][targetSlot] then
            rg[targetGroup][targetSlot] = playerName
        else
            -- Slot occupied: find first free slot
            local placed = false
            for s = 1, MAX_PER_GROUP do
                if not rg[targetGroup][s] then
                    rg[targetGroup][s] = playerName
                    placed = true
                    break
                end
            end
            if not placed then return end  -- group full
        end
    else
        -- No slot given: find first free slot
        local placed = false
        for s = 1, MAX_PER_GROUP do
            if not rg[targetGroup][s] then
                rg[targetGroup][s] = playerName
                placed = true
                break
            end
        end
        if not placed then return end  -- group full
    end

    -- Move in actual WoW raid via SetRaidSubgroup
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        local short = strsplit("-", playerName)
        for i = 1, MAX_RAID_MEMBERS do
            local name = GetRaidRosterInfo(i)
            if name then
                local nameShort = strsplit("-", name)
                if nameShort == short or name == playerName then
                    SetRaidSubgroup(i, targetGroup)
                    break
                end
            end
        end
    end

    -- Broadcast to guild
    OneGuild:BroadcastGlobalGroups()
    OneGuild:RefreshRaidGroups()
end

------------------------------------------------------------------------
-- Remove player from all groups (back to roster)
------------------------------------------------------------------------
RemoveFromGroup = function(playerName)
    if not CanEditGroups() then
        OneGuild:Print("|cFFFF4444Nur Raidleader, Assistenten oder Admins können Gruppen bearbeiten.|r")
        return
    end
    if not OneGuild.db then return end
    local rg = OneGuild.db.raidGroups
    if not rg then return end

    for g = 1, MAX_GROUPS do
        if rg[g] then
            for s = 1, MAX_PER_GROUP do
                if rg[g][s] == playerName then
                    rg[g][s] = nil
                end
            end
        end
    end

    -- Broadcast to guild
    OneGuild:BroadcastGlobalGroups()
    OneGuild:RefreshRaidGroups()
end

------------------------------------------------------------------------
-- BUILD MAIN FRAME
------------------------------------------------------------------------
function OneGuild:BuildRaidGroupsFrame()
    if groupsFrame then return groupsFrame end

    local f = CreateFrame("Frame", "OneGuildRaidGroupsFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(220)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.08, 0.04, 0.04, 0.97)
    f:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.8)

    -- Title bar (draggable)
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(32)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
    title:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
        OneGuild.COLORS.MUTED .. "Raid Gruppen|r")

    local closeBtn = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -1)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Loot status
    f.lootStatus = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lootStatus:SetPoint("LEFT", title, "RIGHT", 16, 0)

    -- Lootmeister label + dropdown button
    local lmLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lmLabel:SetPoint("LEFT", f.lootStatus, "RIGHT", 16, 0)
    lmLabel:SetText("|cFFFF8800LM:|r")

    local lmBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    lmBtn:SetSize(140, 20)
    lmBtn:SetPoint("LEFT", lmLabel, "RIGHT", 4, 0)
    lmBtn:SetFrameLevel(tb:GetFrameLevel() + 5)
    lmBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    lmBtn:SetBackdropColor(0.12, 0.08, 0.04, 0.9)
    lmBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
    f.lmBtnText = lmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.lmBtnText:SetPoint("LEFT", lmBtn, "LEFT", 6, 0)
    f.lmBtnText:SetText("|cFF888888-- keiner --|r")
    local lmArrow = lmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lmArrow:SetPoint("RIGHT", lmBtn, "RIGHT", -4, 0)
    lmArrow:SetText("|cFFDDB866v|r")
    f.lmBtn = lmBtn

    -- Lootmeister dropdown menu
    local lmMenu = CreateFrame("Frame", "OneGuildLMDropdown", UIParent, "BackdropTemplate")
    lmMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    lmMenu:SetFrameLevel(500)
    lmMenu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    lmMenu:SetBackdropColor(0.04, 0.02, 0.02, 0.98)
    lmMenu:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.7)
    lmMenu:SetClampedToScreen(true)
    lmMenu:Hide()
    f.lmMenu = lmMenu
    f.lmMenuItems = {}

    lmBtn:SetScript("OnClick", function(self)
        if lmMenu:IsShown() then
            lmMenu:Hide()
            return
        end
        -- Rebuild menu from signups across ALL raids
        for _, old in ipairs(f.lmMenuItems) do old:Hide() end
        wipe(f.lmMenuItems)

        local entries = {}
        local seen = {}
        -- "None" option
        table.insert(entries, { name = "", display = "|cFF888888-- keiner --|r" })

        if OneGuild.db and OneGuild.db.raids then
            for _, rd in ipairs(OneGuild.db.raids) do
                if rd.signups then
                    for sName, sData in pairs(rd.signups) do
                        local st = type(sData) == "table" and sData.status or sData
                        if st and st ~= "declined" and st ~= "withdrawn" and st ~= "none" then
                            local short = strsplit("-", sName)
                            if not seen[short] then
                                seen[short] = true
                                table.insert(entries, { name = short, display = "|cFFFFD700" .. short .. "|r" })
                            end
                        end
                    end
                end
            end
        end

        local itemH = 20
        lmMenu:SetSize(160, #entries * itemH + 8)
        lmMenu:ClearAllPoints()
        lmMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)

        for idx, e in ipairs(entries) do
            local item = CreateFrame("Button", nil, lmMenu, "BackdropTemplate")
            item:SetSize(150, itemH - 2)
            item:SetPoint("TOPLEFT", lmMenu, "TOPLEFT", 4, -((idx - 1) * itemH) - 4)
            item:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            item:SetBackdropColor(0, 0, 0, 0)

            local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 6, 0)
            label:SetText(e.display)

            item:SetScript("OnEnter", function(s) s:SetBackdropColor(0.3, 0.18, 0.05, 0.8) end)
            item:SetScript("OnLeave", function(s) s:SetBackdropColor(0, 0, 0, 0) end)
            item:SetScript("OnClick", function()
                if OneGuild.db then
                    OneGuild.db.lootmeister = (e.name ~= "") and e.name or nil
                end
                lmMenu:Hide()
                -- Broadcast LM to guild
                OneGuild:BroadcastGlobalLM()
                OneGuild:RefreshRaidGroups()
            end)
            table.insert(f.lmMenuItems, item)
        end
        lmMenu:Show()
    end)
    lmBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.12, 0.06, 1)
    end)
    lmBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.08, 0.04, 0.9)
    end)

    -- =================================================================
    -- LEFT SIDE: 8 Group panels (4 x 2 grid)
    -- =================================================================
    local groupArea = CreateFrame("Frame", nil, f)
    groupArea:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -34)
    groupArea:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 42)
    groupArea:SetWidth((GROUP_W + GROUP_PAD) * 4)

    groupPanels = {}
    for g = 1, MAX_GROUPS do
        local col = ((g - 1) % 4)
        local row = math.floor((g - 1) / 4)
        local xOff = col * (GROUP_W + GROUP_PAD)
        local yOff = -(row * (GROUP_H + GROUP_PAD))

        local gf = CreateFrame("Frame", nil, groupArea, "BackdropTemplate")
        gf:SetSize(GROUP_W, GROUP_H)
        gf:SetPoint("TOPLEFT", groupArea, "TOPLEFT", xOff, yOff)
        gf:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        gf:SetBackdropColor(0.06, 0.03, 0.03, 0.85)
        gf:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)

        -- Header
        gf.header = gf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        gf.header:SetPoint("TOP", gf, "TOP", 0, -4)
        gf.header:SetText("|cFFFFB800Gruppe " .. g .. "|r")

        -- Drop target: whole group panel
        gf:EnableMouse(true)
        gf.groupIndex = g
        gf:SetScript("OnMouseUp", function(self, btn)
            if btn == "LeftButton" and dragPlayerName then
                MoveToGroup(dragPlayerName, self.groupIndex)
                StopDrag()
            end
        end)

        -- Highlight on drag-over
        gf:SetScript("OnEnter", function(self)
            if dragPlayerName then
                self:SetBackdropBorderColor(0.8, 0.6, 0.1, 1)
            end
        end)
        gf:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)
        end)

        -- Player cells
        gf.cells = {}
        for s = 1, MAX_PER_GROUP do
            local cell = CreateFrame("Button", nil, gf)
            cell:SetSize(CELL_W, CELL_H)
            cell:SetPoint("TOPLEFT", gf, "TOPLEFT", 7, -18 - ((s - 1) * (CELL_H + 1)))
            cell:EnableMouse(true)
            cell:RegisterForDrag("LeftButton")

            cell.bg = cell:CreateTexture(nil, "BACKGROUND")
            cell.bg:SetAllPoints()
            cell.bg:SetColorTexture(0.1, 0.06, 0.03, 0.4)

            -- Slot number label (visible when empty)
            cell.slotLabel = cell:CreateFontString(nil, "ARTWORK")
            cell.slotLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
            cell.slotLabel:SetPoint("LEFT", cell, "LEFT", 3, 0)
            cell.slotLabel:SetText("|cFF444430" .. s .. ".|r")

            cell.text = cell:CreateFontString(nil, "OVERLAY")
            cell.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            cell.text:SetPoint("LEFT", cell, "LEFT", 3, 0)
            cell.text:SetJustifyH("LEFT")
            cell.text:SetWidth(CELL_W - 6)
            cell.text:SetWordWrap(false)

            cell.playerName  = nil
            cell.playerClass = nil

            -- Drag start from group cell
            cell:SetScript("OnDragStart", function(self)
                if self.playerName then
                    StartDrag(self.playerName, self.playerClass)
                end
            end)
            cell:SetScript("OnDragStop", function()
                StopDrag()
            end)

            -- Drop on cell = move to this group at this slot
            cell.slotIndex = s
            cell:SetScript("OnMouseUp", function(self, btn)
                if btn == "LeftButton" and dragPlayerName then
                    MoveToGroup(dragPlayerName, g, self.slotIndex)
                    StopDrag()
                end
            end)

            cell:SetScript("OnEnter", function(self)
                if self.playerName then
                    self.bg:SetColorTexture(0.2, 0.12, 0.06, 0.7)
                end
            end)
            cell:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(0.1, 0.06, 0.03, 0.4)
            end)

            gf.cells[s] = cell
        end

        groupPanels[g] = gf
    end

    -- =================================================================
    -- RIGHT SIDE: Roster panel (all raid members for drag & drop)
    -- =================================================================
    local rosterPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    rosterPanel:SetWidth(ROSTER_W)
    rosterPanel:SetPoint("TOPLEFT", groupArea, "TOPRIGHT", 8, 0)
    rosterPanel:SetPoint("BOTTOMLEFT", groupArea, "BOTTOMRIGHT", 8, 0)
    rosterPanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    rosterPanel:SetBackdropColor(0.06, 0.03, 0.03, 0.85)
    rosterPanel:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)
    f.rosterPanel = rosterPanel

    -- Drop on roster panel = remove from group
    rosterPanel:EnableMouse(true)
    rosterPanel:SetScript("OnMouseUp", function(self, btn)
        if btn == "LeftButton" and dragPlayerName then
            RemoveFromGroup(dragPlayerName)
            StopDrag()
        end
    end)
    rosterPanel:SetScript("OnEnter", function(self)
        if dragPlayerName then
            self:SetBackdropBorderColor(0.3, 0.8, 0.3, 1)
        end
    end)
    rosterPanel:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)
    end)

    f.rosterTitle = rosterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.rosterTitle:SetPoint("TOP", rosterPanel, "TOP", 0, -4)
    f.rosterTitle:SetText("|cFFFFB800Spieler|r")

    -- Scrollable roster area
    local rosterScroll = CreateFrame("Frame", nil, rosterPanel)
    rosterScroll:SetPoint("TOPLEFT", rosterPanel, "TOPLEFT", 4, -18)
    rosterScroll:SetPoint("BOTTOMRIGHT", rosterPanel, "BOTTOMRIGHT", -4, 4)
    f.rosterScroll = rosterScroll
    rosterCells = {}

    -- =================================================================
    -- BOTTOM BUTTONS
    -- =================================================================
    -- Addon-Check button
    local checkBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    checkBtn:SetSize(140, 26)
    checkBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 10)
    checkBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    checkBtn:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
    checkBtn:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.6)
    local checkText = checkBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    checkText:SetPoint("CENTER")
    checkText:SetText("|cFF8888FFAddon-Check|r")
    checkBtn:SetScript("OnClick", function()
        if OneGuild.StartAddonCheck then
            OneGuild:StartAddonCheck()
        end
        -- Refresh after check timeout
        C_Timer.After(9, function() OneGuild:RefreshRaidGroups() end)
    end)
    checkBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.15, 0.4, 1)
    end)
    checkBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
    end)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    refreshBtn:SetSize(140, 26)
    refreshBtn:SetPoint("LEFT", checkBtn, "RIGHT", 8, 0)
    refreshBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    refreshBtn:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    refreshBtn:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    local refText = refreshBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    refText:SetPoint("CENTER")
    refText:SetText("|cFFFFD700Aktualisieren|r")
    refreshBtn:SetScript("OnClick", function()
        OneGuild:RefreshRaidGroups()
    end)
    refreshBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.3, 0.08, 1)
    end)
    refreshBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    end)

    -- Create the drag indicator frame
    CreateDragFrame()

    -- Update drag position on every frame
    f:SetScript("OnUpdate", function()
        UpdateDragPosition()
    end)

    f:Hide()
    groupsFrame = f
    return f
end

------------------------------------------------------------------------
-- Refresh display
------------------------------------------------------------------------
function OneGuild:RefreshRaidGroups()
    if not groupsFrame or not groupsFrame:IsShown() then return end
    local f = groupsFrame

    local _, allMembers = GetRaidGroups()

    -- Build class lookup from guild + raid
    local classLookup = {}
    local numGuild = GetNumGuildMembers() or 0
    for gi = 1, numGuild do
        local gName, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(gi)
        if gName then
            local gShort = strsplit("-", gName)
            classLookup[gShort] = classFile
            classLookup[gName] = classFile
        end
    end
    for _, m in ipairs(allMembers) do
        local mShort = strsplit("-", m.name)
        classLookup[mShort] = m.classFile
        classLookup[m.name] = m.classFile
    end

    -- Get global raidGroups + gather signups from ALL raids
    local raidGroups = (self.db and self.db.raidGroups) or {}

    -- Collect signups from ALL raids (global groups = global roster)
    local signups = {}
    if self.db and self.db.raids then
        for _, rd in ipairs(self.db.raids) do
            if rd.signups then
                for sName, sData in pairs(rd.signups) do
                    if not signups[sName] then
                        signups[sName] = sData
                    end
                end
            end
        end
    end

    -- Build set of all grouped player names (short names)
    local groupedNames = {}

    -- ===== Update group panels from addon data =====
    for g = 1, MAX_GROUPS do
        local panel = groupPanels[g]
        local members = raidGroups[g] or {}
        local memberCount = 0
        for s = 1, MAX_PER_GROUP do if members[s] then memberCount = memberCount + 1 end end
        panel.header:SetText("|cFFFFB800Gruppe " .. g .. "|r |cFF8B7355(" .. memberCount .. ")|r")

        for s = 1, MAX_PER_GROUP do
            local cell  = panel.cells[s]
            local pName = members[s]

            if pName then
                cell.playerName  = pName
                local short = strsplit("-", pName)
                local cf = classLookup[pName] or classLookup[short]
                cell.playerClass = cf
                groupedNames[pName] = true
                groupedNames[short] = true

                -- Role icon prefix from signup
                local roleStr = ""
                local sig = signups[pName]
                if type(sig) == "table" and sig.role and ROLE_COORDS[sig.role] then
                    roleStr = "|cFFDDB866" .. (ROLE_LABELS_SHORT[sig.role] or "") .. "|r "
                end

                local display = roleStr .. ClassHex(cf) .. short .. "|r"
                display = display .. AddonStatusIcon(GetAddonStatus(pName))

                cell.text:SetText(display)
                cell.bg:SetColorTexture(0.1, 0.06, 0.03, 0.4)
                if cell.slotLabel then cell.slotLabel:Hide() end
                cell:SetAlpha(1)
            else
                cell.playerName  = nil
                cell.playerClass = nil
                cell.text:SetText("")
                cell.bg:SetColorTexture(0.08, 0.05, 0.03, 0.35)
                if cell.slotLabel then cell.slotLabel:Show() end
                cell:SetAlpha(1)
            end
        end
    end

    -- ===== Update roster panel =====
    -- Build roster from signups + raid members, excluding already grouped
    local rosterEntries = {}
    local signupNames = {}

    -- Get signups from all raids (exclude grouped)
    for name, s in pairs(signups) do
        local st = type(s) == "table" and s.status or s
        if st and st ~= "declined" and st ~= "withdrawn" and st ~= "none" then
            local short = strsplit("-", name)
            if not groupedNames[name] and not groupedNames[short] then
                table.insert(rosterEntries, {
                    name      = name,
                    shortName = short,
                    role      = (type(s) == "table" and s.role) or "DD",
                    classFile = classLookup[name] or classLookup[short],
                    isSignup  = true,
                })
            end
            signupNames[name] = true
            signupNames[short] = true
        end
    end

    -- Add actual raid members not already in signups or grouped
    for _, m in ipairs(allMembers) do
        local short = strsplit("-", m.name)
        if not signupNames[m.name] and not signupNames[short]
           and not groupedNames[m.name] and not groupedNames[short] then
            table.insert(rosterEntries, {
                name      = m.name,
                shortName = short,
                role      = nil,
                classFile = m.classFile,
                group     = m.group,
                online    = m.online,
                isSignup  = false,
            })
        end
    end

    -- Sort: signups first (by role), then raid members (by class)
    local roleSort = { TANK = 1, HEALER = 2, DD = 3 }
    table.sort(rosterEntries, function(a, b)
        if a.isSignup ~= b.isSignup then return a.isSignup end
        if a.isSignup and b.isSignup then
            local ra = roleSort[a.role] or 9
            local rb = roleSort[b.role] or 9
            if ra ~= rb then return ra < rb end
        end
        return a.name < b.name
    end)

    -- Update roster title
    if raidIdx and self.db and self.db.raids and self.db.raids[raidIdx] then
        f.rosterTitle:SetText("|cFFFFB800Spieler|r |cFF8B7355(" .. (self.db.raids[raidIdx].title or "Raid") .. ")|r")
    else
        f.rosterTitle:SetText("|cFFFFB800Spieler|r")
    end

    local scroll = f.rosterScroll
    -- Reuse or create cells
    for i, entry in ipairs(rosterEntries) do
        local cell = rosterCells[i]
        if not cell then
            cell = CreateFrame("Button", nil, scroll)
            cell:SetSize(ROSTER_W - 12, CELL_H)
            cell:EnableMouse(true)
            cell:RegisterForDrag("LeftButton")

            cell.bg = cell:CreateTexture(nil, "BACKGROUND")
            cell.bg:SetAllPoints()
            cell.bg:SetColorTexture(0.08, 0.05, 0.03, 0.4)

            cell.roleIcon = cell:CreateTexture(nil, "ARTWORK")
            cell.roleIcon:SetSize(14, 14)
            cell.roleIcon:SetPoint("LEFT", cell, "LEFT", 2, 0)
            cell.roleIcon:SetTexture(ROLE_TEX)

            cell.text = cell:CreateFontString(nil, "OVERLAY")
            cell.text:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
            cell.text:SetPoint("LEFT", cell.roleIcon, "RIGHT", 2, 0)
            cell.text:SetJustifyH("LEFT")
            cell.text:SetWidth(ROSTER_W - 36)
            cell.text:SetWordWrap(false)

            cell:SetScript("OnDragStart", function(self)
                if self.playerName then
                    StartDrag(self.playerName, self.playerClass)
                end
            end)
            cell:SetScript("OnDragStop", function()
                StopDrag()
            end)
            cell:SetScript("OnEnter", function(self)
                self.bg:SetColorTexture(0.18, 0.1, 0.05, 0.7)
                if self.playerName then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine(self.playerName)
                    if self.signupRole then
                        GameTooltip:AddLine("|cFFDDB866Rolle: " .. (ROLE_LABELS_SHORT[self.signupRole] or "?") .. "|r")
                    end
                    local st = GetAddonStatus(self.playerName)
                    if st == "ok" then
                        GameTooltip:AddLine("|cFF66FF66Addon aktiv (v" .. (OneGuild.VERSION or "?") .. ")|r")
                    elseif st == "wrong" then
                        GameTooltip:AddLine("|cFFFF8800Falsche Version!|r")
                    elseif st == "missing" then
                        GameTooltip:AddLine("|cFFFF4444Kein Addon!|r")
                    else
                        GameTooltip:AddLine("|cFF888888Nicht geprüft|r")
                    end
                    GameTooltip:AddLine("|cFF666666Ziehe in eine Gruppe|r")
                    GameTooltip:Show()
                end
            end)
            cell:SetScript("OnLeave", function(self)
                self.bg:SetColorTexture(0.08, 0.05, 0.03, 0.4)
                GameTooltip:Hide()
            end)

            rosterCells[i] = cell
        end

        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -((i - 1) * (CELL_H + 1)))

        cell.playerName  = entry.name
        cell.playerClass = entry.classFile
        cell.signupRole  = entry.role

        -- Role icon
        if entry.role and ROLE_COORDS[entry.role] then
            local c = ROLE_COORDS[entry.role]
            cell.roleIcon:SetTexCoord(c[1], c[2], c[3], c[4])
            cell.roleIcon:Show()
        else
            cell.roleIcon:Hide()
        end

        local display = ClassHex(entry.classFile) .. entry.shortName .. "|r"
        display = display .. AddonStatusIcon(GetAddonStatus(entry.name))
        if entry.group then
            display = display .. " |cFF555555[" .. entry.group .. "]|r"
        end

        cell.text:SetText(display)
        cell:SetAlpha((entry.online == false) and 0.4 or 1)
        cell:Show()
    end

    -- Hide unused cells
    for i = #rosterEntries + 1, #rosterCells do
        rosterCells[i]:Hide()
    end

    -- Loot status
    if f.lootStatus then
        if OneGuild.IsLootSystemActive and OneGuild:IsLootSystemActive() then
            f.lootStatus:SetText("|cFF66FF66\226\151\143 Loot: AKTIV|r")
        else
            f.lootStatus:SetText("|cFFFF4444\226\151\143 Loot: INAKTIV|r")
        end
    end

    -- Lootmeister button text (global)
    if f.lmBtnText then
        local lm = self.db and self.db.lootmeister
        if lm and lm ~= "" then
            f.lmBtnText:SetText("|cFFFF8800" .. lm .. "|r")
        else
            f.lmBtnText:SetText("|cFF888888-- keiner --|r")
        end
    end
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function OneGuild:ToggleRaidGroups()
    local f = self:BuildRaidGroupsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:RefreshRaidGroups()
    end
end

------------------------------------------------------------------------
-- Broadcast raid groups (for display sync)
------------------------------------------------------------------------
function OneGuild:BroadcastRaidGroups()
    if not IsInRaid() then return end
    local numRaid = GetNumGroupMembers() or 0
    local parts = {}
    for i = 1, numRaid do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            table.insert(parts, name .. "|" .. (subgroup or 1))
        end
    end
    if #parts > 0 then
        self:SendCommMessage("RGS", table.concat(parts, ","))
    end
end
