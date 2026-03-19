------------------------------------------------------------------------
-- OneGuild - Raid.lua
-- Raid planner: create raids, sign up with role, track roster
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Raid.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local RAID_ROW_HEIGHT = 80
local MAX_RAID_ROWS   = 5

-- Role icon texture (LFGFrame, 64x64)
local ROLE_TEX    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK   = { 0,        19/64,  22/64, 41/64 },
    HEALER = { 20/64,    39/64,  1/64,  20/64 },
    DD     = { 20/64,    39/64,  22/64, 41/64 },
}
local ROLE_LABELS = {
    TANK   = "Tank",
    HEALER = "Healer",
    DD     = "DD",
}
local ROLE_ORDER = { "TANK", "HEALER", "DD" }

-- Raid difficulty labels
local DIFFICULTY_LABELS = {
    { key = "normal",  label = "Normal",  color = "|cFF66FF66" },
    { key = "heroic",  label = "Heroisch", color = "|cFF0088FF" },
    { key = "mythic",  label = "Mythisch", color = "|cFFFF8800" },
}

------------------------------------------------------------------------
-- Expansion / Raid data  — built dynamically from WoW Encounter Journal
------------------------------------------------------------------------
local EXPANSION_ORDER  = {}   -- { 1, 2, 3, ... } tier indices
local EXPANSION_LABELS = {}   -- { [1] = "Classic", [2] = "Burning Crusade", ... }
local RAID_DATA        = {}   -- { [tierIdx] = { {key,label,icon,art}, ... } }
local EJ_DATA_LOADED   = false
local CURRENT_TIER     = nil  -- highest tier = "Aktuelle Saison" equivalent

local function EnsureEJLoaded()
    if EJ_DATA_LOADED then return true end
    if not EJ_GetNumTiers then return false end

    -- Make sure the EJ data addon is loaded
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_EncounterJournal")
    end

    local numTiers = EJ_GetNumTiers()
    if not numTiers or numTiers == 0 then return false end

    -- Save & restore current tier selection
    for tier = 1, numTiers do
        local tierName = EJ_GetTierInfo(tier)
        if tierName then
            table.insert(EXPANSION_ORDER, tier)
            EXPANSION_LABELS[tier] = tierName
            RAID_DATA[tier] = {}

            EJ_SelectTier(tier)
            local idx = 1
            while true do
                local instanceID, instName, instDesc, bgImage,
                      buttonImage1, loreImage, buttonImage2,
                      dungeonAreaMapID, instLink = EJ_GetInstanceByIndex(idx, true)
                if not instanceID then break end
                table.insert(RAID_DATA[tier], {
                    key        = "ej_" .. instanceID,
                    instanceID = instanceID,
                    label      = instName,
                    icon       = buttonImage1 or bgImage or 0,
                    art        = buttonImage1 or bgImage or 0,
                    bg         = bgImage or buttonImage1 or 0,
                    lore       = loreImage or 0,
                    buttonArt  = buttonImage2 or buttonImage1 or bgImage or 0,
                })
                idx = idx + 1
            end
        end
    end

    CURRENT_TIER = numTiers
    -- Default to highest tier that has raids; fall back to last
    for t = numTiers, 1, -1 do
        if RAID_DATA[t] and #RAID_DATA[t] > 0 then
            CURRENT_TIER = t
            break
        end
    end

    EJ_DATA_LOADED = true
    return true
end

-- Flat lookup for saved data backwards compat
local function GetDungeonInfo(key)
    EnsureEJLoaded()
    for _, tierIdx in ipairs(EXPANSION_ORDER) do
        for _, r in ipairs(RAID_DATA[tierIdx] or {}) do
            if r.key == key then
                return r.label, r.icon, r.art
            end
        end
    end
    return nil, nil, nil
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local raidRows     = {}
local displayRaids = {}
local showPast     = false

------------------------------------------------------------------------
-- Helper: count signups by role
------------------------------------------------------------------------
local function CountRaidSignups(signups)
    local total = 0
    local roles = { TANK = 0, HEALER = 0, DD = 0 }

    if not signups then return total, roles end

    for _, s in pairs(signups) do
        local status, role
        if type(s) == "table" then
            status = s.status
            role   = s.role
        else
            status = s
            role   = nil
        end

        if status == "accepted" then
            total = total + 1
            if role and roles[role] ~= nil then
                roles[role] = roles[role] + 1
            end
        end
    end

    return total, roles
end

------------------------------------------------------------------------
-- Helper: get player signup info
------------------------------------------------------------------------
local function GetPlayerRaidSignup(signups, playerName)
    if not signups or not signups[playerName] then
        return "none", nil
    end
    local s = signups[playerName]
    if type(s) == "table" then
        return s.status or "none", s.role
    end
    return s, nil
end

------------------------------------------------------------------------
-- Helper: create role icon
------------------------------------------------------------------------
local function CreateRoleIcon(parent, role, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexture(ROLE_TEX)
    local c = ROLE_COORDS[role]
    if c then
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    return tex
end

------------------------------------------------------------------------
-- Build Raid Tab (Tab 3)
------------------------------------------------------------------------
function OneGuild:BuildRaidTab()
    local parent = self.tabFrames[3]
    if not parent then return end

    -- Top bar
    local topBar = CreateFrame("Frame", nil, parent)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
    topBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -6)

    -- Raid icon (skull)
    local raidIcon = topBar:CreateTexture(nil, "ARTWORK")
    raidIcon:SetSize(20, 20)
    raidIcon:SetPoint("LEFT", topBar, "LEFT", 4, 0)
    raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

    local titleText = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", raidIcon, "RIGHT", 6, 0)
    titleText:SetText("|cFFFFB800Raid-Planer|r")

    -- Create Raid button
    local createBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    createBtn:SetSize(130, 24)
    createBtn:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
    createBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    createBtn:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    createBtn:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    local createBtnText = createBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    createBtnText:SetPoint("CENTER")
    createBtnText:SetText("|cFFFFD700+ Neuer Raid|r")
    createBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.3, 0.08, 1)
        self:SetBackdropBorderColor(0.8, 0.6, 0.15, 0.8)
    end)
    createBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
        self:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    end)
    createBtn:SetScript("OnClick", function()
        OneGuild:ShowCreateRaidDialog()
    end)

    -- Raid-Gruppen button
    local groupsBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    groupsBtn:SetSize(110, 24)
    groupsBtn:SetPoint("RIGHT", createBtn, "LEFT", -6, 0)
    groupsBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    groupsBtn:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
    groupsBtn:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.6)
    local groupsBtnText = groupsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    groupsBtnText:SetPoint("CENTER")
    groupsBtnText:SetText("|cFF8888FFGruppen|r")
    groupsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.15, 0.4, 1)
        self:SetBackdropBorderColor(0.5, 0.4, 0.7, 0.8)
    end)
    groupsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
        self:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.6)
    end)
    groupsBtn:SetScript("OnClick", function()
        -- Use first visible raid if no specific one selected
        if not OneGuild.currentRaidIdx and OneGuild.db and OneGuild.db.raids then
            for idx, _ in ipairs(OneGuild.db.raids) do
                OneGuild.currentRaidIdx = idx
                break
            end
        end
        if OneGuild.ToggleRaidGroups then
            OneGuild:ToggleRaidGroups()
        end
    end)

    -- Toggle past raids
    local pastCheck = CreateFrame("CheckButton", "OneGuildRaidPastFilter", topBar, "UICheckButtonTemplate")
    pastCheck:SetSize(22, 22)
    pastCheck:SetPoint("RIGHT", groupsBtn, "LEFT", -10, 0)
    pastCheck:SetChecked(false)
    local pastLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pastLabel:SetPoint("RIGHT", pastCheck, "LEFT", -2, 0)
    pastLabel:SetText("|cFF8B7355Vergangene|r")
    pastCheck:SetScript("OnClick", function(self)
        showPast = self:GetChecked()
        OneGuild:RefreshRaid()
    end)

    -- DKP Distribution button (red)
    local dkpBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    dkpBtn:SetSize(70, 24)
    dkpBtn:SetPoint("RIGHT", pastLabel, "LEFT", -14, 0)
    dkpBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    dkpBtn:SetBackdropColor(0.4, 0.08, 0.08, 0.9)
    dkpBtn:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.6)
    local dkpBtnText = dkpBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dkpBtnText:SetPoint("CENTER")
    dkpBtnText:SetText("|cFFFF4444DKP|r")
    dkpBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.55, 0.12, 0.12, 1)
        self:SetBackdropBorderColor(0.9, 0.3, 0.3, 0.8)
    end)
    dkpBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.08, 0.08, 0.9)
        self:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.6)
    end)
    dkpBtn:SetScript("OnClick", function()
        if not OneGuild.CanEditDKP or not OneGuild:CanEditDKP() then
            OneGuild:Print("|cFFFF4444Du hast keine Berechtigung, DKP zu verteilen.|r")
            return
        end
        if OneGuild.ShowDKPDistribution then
            OneGuild:ShowDKPDistribution()
        end
    end)

    -- Raid list container
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    listFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
    parent.listFrame = listFrame

    -- Create raid row frames
    for i = 1, MAX_RAID_ROWS do
        local row = CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
        row:SetHeight(RAID_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -((i - 1) * (RAID_ROW_HEIGHT + 4)))
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, -((i - 1) * (RAID_ROW_HEIGHT + 4)))
        row:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.08, 0.05, 0.03, 0.8)
        row:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)

        -- Raid icon (left side - dungeon specific)
        row.raidIcon = row:CreateTexture(nil, "ARTWORK")
        row.raidIcon:SetSize(32, 32)
        row.raidIcon:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -8)
        row.raidIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
        row.raidIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Dungeon name (below raid title)
        row.dungeonText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.dungeonText:SetPoint("TOPLEFT", row.raidIcon, "TOPRIGHT", 8, -16)
        row.dungeonText:SetTextColor(0.55, 0.45, 0.3)

        -- Raid title
        row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.titleText:SetPoint("TOPLEFT", row.raidIcon, "TOPRIGHT", 8, -2)
        row.titleText:SetJustifyH("LEFT")

        -- Difficulty badge
        row.diffText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.diffText:SetPoint("LEFT", row.titleText, "RIGHT", 8, 0)

        -- Date & Time
        row.dateIcon = row:CreateTexture(nil, "ARTWORK")
        row.dateIcon:SetSize(12, 12)
        row.dateIcon:SetPoint("TOPLEFT", row.raidIcon, "BOTTOMLEFT", 0, -4)
        row.dateIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        row.dateIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.dateText:SetPoint("LEFT", row.dateIcon, "RIGHT", 4, 0)
        row.dateText:SetTextColor(0.7, 0.6, 0.4)

        -- Raid leader
        row.leaderText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.leaderText:SetPoint("LEFT", row.dateText, "RIGHT", 12, 0)
        row.leaderText:SetTextColor(0.5, 0.5, 0.5)

        -- === Role counters (right side, larger) ===
        row.roleFrames = {}
        local roleX = -110
        for _, role in ipairs(ROLE_ORDER) do
            local rf = CreateFrame("Frame", nil, row)
            rf:SetSize(50, 20)
            rf:SetPoint("TOPRIGHT", row, "TOPRIGHT", roleX, -6)

            rf.icon = CreateRoleIcon(rf, role, 18)
            rf.icon:SetPoint("LEFT", rf, "LEFT", 0, 0)

            rf.count = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            rf.count:SetPoint("LEFT", rf.icon, "RIGHT", 3, 0)
            rf.count:SetText("|cFF5555550|r")

            row.roleFrames[role] = rf
            roleX = roleX + 50
        end

        -- Total signup count
        row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.totalText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -30)

        -- Player status
        row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.statusText:SetPoint("TOPRIGHT", row.totalText, "BOTTOMRIGHT", 0, -2)

        -- Lootmeister display (next to leader)
        row.lootmeisterText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.lootmeisterText:SetPoint("LEFT", row.leaderText, "RIGHT", 12, 0)
        row.lootmeisterText:SetTextColor(1, 0.53, 0)

        -- === Signup buttons (bottom row) ===
        local btnY  = -54
        local btnW  = 28
        local btnH  = 20
        local gap   = 4

        -- Role buttons (Tank / Healer / DD)
        row.roleButtons = {}
        local roleBtnX = 48
        for _, role in ipairs(ROLE_ORDER) do
            local rb = CreateFrame("Button", nil, row, "BackdropTemplate")
            rb:SetSize(btnW + 24, btnH)
            rb:SetPoint("TOPLEFT", row, "TOPLEFT", roleBtnX, btnY)
            rb:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets   = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            rb:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
            rb:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)

            rb.icon = CreateRoleIcon(rb, role, 14)
            rb.icon:SetPoint("LEFT", rb, "LEFT", 4, 0)

            rb.label = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rb.label:SetPoint("LEFT", rb.icon, "RIGHT", 2, 0)
            rb.label:SetText("|cFFDDB866" .. ROLE_LABELS[role] .. "|r")

            rb:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.3, 0.2, 0.05, 0.9)
                self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.7)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cFFFFD700Als " .. ROLE_LABELS[role] .. " anmelden|r")
                GameTooltip:Show()
            end)
            rb:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
                self:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
                GameTooltip:Hide()
            end)

            row.roleButtons[role] = rb
            roleBtnX = roleBtnX + btnW + 24 + gap
        end

        -- Absagen button
        row.declineBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.declineBtn:SetSize(btnW + 20, btnH)
        row.declineBtn:SetPoint("TOPLEFT", row, "TOPLEFT", roleBtnX + 8, btnY)
        row.declineBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.declineBtn:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
        row.declineBtn:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.5)
        local decText = row.declineBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        decText:SetPoint("CENTER")
        decText:SetText("|cFFFF4444Absage|r")
        row.declineBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.5, 0.08, 0.08, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFF4444Absagen|r")
            GameTooltip:Show()
        end)
        row.declineBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
            GameTooltip:Hide()
        end)

        -- Delete button
        row.deleteBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.deleteBtn:SetSize(16, 16)
        row.deleteBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 8)
        row.deleteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.deleteBtn:SetBackdropColor(0.3, 0, 0, 0.6)
        row.deleteBtn:SetBackdropBorderColor(0.5, 0.15, 0.15, 0.4)
        local delText = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delText:SetPoint("CENTER")
        delText:SetText("|cFFFF6666x|r")
        row.deleteBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.5, 0, 0, 0.8)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFF6666Raid loeschen|r")
            GameTooltip:Show()
        end)
        row.deleteBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0, 0, 0.6)
            GameTooltip:Hide()
        end)

        -- Gruppen button (opens RaidGroups window)
        row.groupsBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.groupsBtn:SetSize(68, 16)
        row.groupsBtn:SetPoint("RIGHT", row.deleteBtn, "LEFT", -6, 0)
        row.groupsBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.groupsBtn:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
        row.groupsBtn:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.5)
        local grpText = row.groupsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        grpText:SetPoint("CENTER")
        grpText:SetText("|cFF8888FFGruppen|r")
        row.groupsBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.2, 0.15, 0.4, 1)
            self:SetBackdropBorderColor(0.5, 0.4, 0.7, 0.8)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFF8888FFRaid-Gruppen öffnen|r")
            GameTooltip:Show()
        end)
        row.groupsBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
            self:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.5)
            GameTooltip:Hide()
        end)
        row.groupsBtn:SetScript("OnClick", function()
            -- Use first visible raid if no specific one selected
            if not OneGuild.currentRaidIdx and OneGuild.db and OneGuild.db.raids then
                for idx2, _ in ipairs(OneGuild.db.raids) do
                    OneGuild.currentRaidIdx = idx2
                    break
                end
            end
            if OneGuild.ToggleRaidGroups then
                OneGuild:ToggleRaidGroups()
            end
        end)

        -- Hover
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.08, 0.04, 0.9)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.05, 0.03, 0.8)
        end)

        row:Hide()
        raidRows[i] = row
    end
end

------------------------------------------------------------------------
-- Refresh raid display
------------------------------------------------------------------------
function OneGuild:RefreshRaid()
    if not self.db then return end
    if not self.db.raids then self.db.raids = {} end
    if #raidRows == 0 then return end  -- tab not built yet
    EnsureEJLoaded()

    local now = time()
    displayRaids = {}

    for idx, rd in ipairs(self.db.raids) do
        local rdTime = rd.timestamp or 0
        local isPast = rdTime < now

        if showPast or not isPast then
            table.insert(displayRaids, { index = idx, data = rd, isPast = isPast })
        end
    end

    -- Sort: upcoming first, past at bottom
    table.sort(displayRaids, function(a, b)
        if a.isPast ~= b.isPast then return not a.isPast end
        return a.data.timestamp < b.data.timestamp
    end)

    local playerName = self:GetPlayerName()

    for i = 1, MAX_RAID_ROWS do
        local row = raidRows[i]
        if i <= #displayRaids then
            local rd = displayRaids[i]
            local data = rd.data

            -- Title
            local titleColor = rd.isPast and "|cFF8B7355" or "|cFFFFB800"
            row.titleText:SetText(titleColor .. (data.title or "Unbenannt") .. "|r")

            -- Dungeon name and icon
            local dungeonLabel, dungeonIcon = GetDungeonInfo(data.dungeon)
            if dungeonLabel then
                row.dungeonText:SetText("|cFF8B7355" .. dungeonLabel .. "|r")
                row.dungeonText:Show()
                row.raidIcon:SetTexture(dungeonIcon or "Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
            else
                row.dungeonText:SetText("")
                row.dungeonText:Hide()
                row.raidIcon:SetTexture("Interface\\Icons\\Achievement_Dungeon_ClassicDungeonMaster")
            end
            row.raidIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

            -- Difficulty badge
            local diffColor = "|cFF66FF66"
            local diffLabel = "Normal"
            for _, d in ipairs(DIFFICULTY_LABELS) do
                if d.key == data.difficulty then
                    diffColor = d.color
                    diffLabel = d.label
                    break
                end
            end
            row.diffText:SetText(diffColor .. "[" .. diffLabel .. "]|r")

            -- Date & Time
            local dateStr = data.dateStr or "?"
            local timeStr = data.timeStr or ""
            row.dateText:SetText(dateStr .. "  " .. timeStr .. " Uhr")

            -- Raid leader
            row.leaderText:SetText("|cFF8B7355RL:|r |cFFDDB866" .. (data.author or "?") .. "|r")

            -- Signup counts
            local signups = data.signups or {}
            local total, roles = CountRaidSignups(signups)

            -- Update role counters
            for _, role in ipairs(ROLE_ORDER) do
                local cnt = roles[role]
                local color = cnt > 0 and "|cFFFFD700" or "|cFF555555"
                row.roleFrames[role].count:SetText(color .. cnt .. "|r")
            end

            -- Total
            row.totalText:SetText("|cFFDDB866" .. total .. " Anmeldungen|r")

            -- Player status
            local myStatus, myRole = GetPlayerRaidSignup(signups, playerName)
            local statusMap = {
                accepted  = "|cFF66FF66Angemeldet",
                declined  = "|cFFFF4444Abgesagt",
                none      = "|cFF666666Nicht angemeldet",
            }
            local statusStr = statusMap[myStatus] or statusMap.none
            if myStatus == "accepted" and myRole then
                statusStr = statusStr .. " (" .. ROLE_LABELS[myRole] .. ")"
            end
            row.statusText:SetText("|cFF8B7355Du:|r " .. statusStr .. "|r")

            -- Lootmeister
            if data.lootmeister and data.lootmeister ~= "" then
                row.lootmeisterText:SetText("|cFF8B7355LM:|r |cFFFF8800" .. data.lootmeister .. "|r")
                row.lootmeisterText:Show()
            else
                row.lootmeisterText:Hide()
            end

            -- Highlight active role button
            for _, role in ipairs(ROLE_ORDER) do
                local rb = row.roleButtons[role]
                if myStatus == "accepted" and myRole == role then
                    rb:SetBackdropColor(0.3, 0.25, 0.05, 1)
                    rb:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
                else
                    rb:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
                    rb:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
                end
            end

            -- Highlight decline
            if myStatus == "declined" then
                row.declineBtn:SetBackdropColor(0.5, 0.08, 0.08, 1)
                row.declineBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
            else
                row.declineBtn:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
                row.declineBtn:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.5)
            end

            -- Wire up buttons
            local raidIdx = rd.index
            for _, role in ipairs(ROLE_ORDER) do
                row.roleButtons[role]:SetScript("OnClick", function()
                    OneGuild:RaidSignup(raidIdx, "accepted", role)
                end)
            end
            row.declineBtn:SetScript("OnClick", function()
                OneGuild:RaidSignup(raidIdx, "declined", nil)
            end)
            row.deleteBtn:SetScript("OnClick", function()
                OneGuild:DeleteRaid(raidIdx)
            end)
            row.groupsBtn:SetScript("OnClick", function()
                if OneGuild.ToggleRaidGroups then
                    OneGuild:ToggleRaidGroups()
                end
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    -- Empty message
    local parent = self.tabFrames[3]
    if not parent.emptyText then
        parent.emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        parent.emptyText:SetPoint("CENTER", parent, "CENTER", 0, -20)
        parent.emptyText:SetWidth(400)
        parent.emptyText:SetJustifyH("CENTER")
        parent.emptyText:SetWordWrap(true)
    end
    if #displayRaids == 0 then
        parent.emptyText:SetText("|cFF8B7355Keine Raids geplant.\n\n" ..
            "|cFFDDB866Erstelle einen neuen Raid mit dem + Button.|r")
        parent.emptyText:Show()
    else
        parent.emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Raid Signup
------------------------------------------------------------------------
function OneGuild:RaidSignup(raidIdx, status, role)
    if not self.db or not self.db.raids or not self.db.raids[raidIdx] then return end

    local playerName = self:GetPlayerName()
    if not self.db.raids[raidIdx].signups then
        self.db.raids[raidIdx].signups = {}
    end

    local old = self.db.raids[raidIdx].signups[playerName]
    local oldStatus = type(old) == "table" and old.status or old
    local oldRole   = type(old) == "table" and old.role or nil

    -- Toggle off if same
    if oldStatus == status and (status ~= "accepted" or oldRole == role) then
        self.db.raids[raidIdx].signups[playerName] = nil
        self:Print("|cFFDDB866Raid-Anmeldung fuer '|r|cFFFFD700" ..
            (self.db.raids[raidIdx].title or "?") .. "|r|cFFDDB866' zurueckgezogen.|r")
    else
        self.db.raids[raidIdx].signups[playerName] = {
            status   = status,
            role     = role,
            signedAt = time(),
        }
        local statusDE = {
            accepted = "Angemeldet",
            declined = "Abgesagt",
        }
        local msg = (statusDE[status] or status)
        if role then
            msg = msg .. " als " .. ROLE_LABELS[role]
        end
        self:PrintSuccess(msg .. " fuer '" .. (self.db.raids[raidIdx].title or "?") .. "'.")
    end

    self:RefreshRaid()

    -- Broadcast signup to guild
    local rd = self.db.raids[raidIdx]
    if rd and self.SendRaidSignup then
        local signup = rd.signups[playerName]
        if signup then
            self:SendRaidSignup(rd, playerName, signup)
        else
            -- Withdrawal: send a special "withdrawn" signup
            self:SendRaidSignup(rd, playerName, { status = "withdrawn", role = "", signedAt = time() })
        end
    end
end

------------------------------------------------------------------------
-- Delete a raid
------------------------------------------------------------------------
function OneGuild:DeleteRaid(raidIdx)
    if not self.db or not self.db.raids or not self.db.raids[raidIdx] then return end
    local raid = self.db.raids[raidIdx]
    local title = raid.title or "?"

    -- Create tombstone so sync doesn't revive it
    local delKey = tostring(raid.created or 0) .. ":" .. (raid.author or "?")
    if not self.db.deletedRaids then self.db.deletedRaids = {} end
    self.db.deletedRaids[delKey] = true

    -- Broadcast delete to guild
    if self.BroadcastRaidDelete then
        self:BroadcastRaidDelete(raid)
    end

    table.remove(self.db.raids, raidIdx)
    self:Print("|cFFDDB866Raid '|r|cFFFFD700" .. title .. "|r|cFFDDB866' geloescht.|r")
    self:RefreshRaid()
end

------------------------------------------------------------------------
-- Dropdown helpers for date / time selection
------------------------------------------------------------------------
local RD_WOCHENTAGE = {"So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"}

local function RDBuildDateOptions()
    local opts = {}
    local now = time()
    for i = 0, 29 do
        local t = now + i * 86400
        local d = date("*t", t)
        local val = format("%02d.%02d.%04d", d.day, d.month, d.year)
        local disp = RD_WOCHENTAGE[d.wday] .. "  " .. val
        opts[#opts + 1] = { display = disp, value = val }
    end
    return opts
end

local function RDBuildTimeOptions()
    local opts = {}
    for h = 0, 23 do
        for m = 0, 30, 30 do
            local val = format("%02d:%02d", h, m)
            opts[#opts + 1] = { display = val, value = val }
        end
    end
    return opts
end

local function RDCreateDropdownMenu(parent, anchor, options, menuWidth, editBox)
    local itemH = 20
    local visible = math.min(#options, 10)
    local menuH = visible * itemH + 8

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetSize(menuWidth, menuH)
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.6, 0.45, 0.1, 0.7)
    menu:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(menuWidth - 30, #options * itemH)
    scroll:SetScrollChild(content)

    menu._buttons = {}
    menu._editBox = editBox
    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
        btn:SetSize(menuWidth - 30, itemH - 2)
        btn:SetPoint("TOPLEFT", 0, -((i - 1) * itemH))
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(0, 0, 0, 0)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", 6, 0)
        txt:SetText("|cFFDDB866" .. opt.display .. "|r")
        btn._label = txt
        btn._value = opt.value

        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.2, 0.05, 0.7) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
        btn:SetScript("OnClick", function()
            editBox:SetText(opt.value)
            menu:Hide()
        end)

        menu._buttons[i] = btn
    end

    return menu
end

local function RDRefreshDateMenu(menu)
    local opts = RDBuildDateOptions()
    local eb = menu._editBox
    for i, opt in ipairs(opts) do
        local btn = menu._buttons[i]
        if btn then
            btn._label:SetText("|cFFDDB866" .. opt.display .. "|r")
            btn._value = opt.value
            btn:SetScript("OnClick", function()
                eb:SetText(opt.value)
                menu:Hide()
            end)
        end
    end
end

------------------------------------------------------------------------
-- Create Raid Dialog  (WoW "Schlachtzüge" style)
------------------------------------------------------------------------
local CARD_W   = 195
local CARD_H   = 115
local CARD_GAP = 12
local CARDS_PER_ROW = 4
local CARDS_AREA_H = 260   -- room for 2 rows
local DIALOG_W = 850
local DIALOG_H = 630

function OneGuild:ShowCreateRaidDialog()
    if self.createRaidFrame and self.createRaidFrame:IsShown() then
        self.createRaidFrame:Hide()
        return
    end

    if not self.createRaidFrame then
        local f = CreateFrame("Frame", "OneGuildCreateRaid", UIParent, "BackdropTemplate")
        f:SetSize(DIALOG_W, DIALOG_H)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.04, 0.02, 0.02, 0.98)
        f:SetBackdropBorderColor(0.5, 0.35, 0.08, 0.8)

        -- Drag (shorter width so it doesn't overlap dropdown button)
        local dragArea = CreateFrame("Frame", nil, f)
        dragArea:SetHeight(30)
        dragArea:SetPoint("TOPLEFT")
        dragArea:SetPoint("RIGHT", f, "TOPRIGHT", -250, 0)
        dragArea:EnableMouse(true)
        dragArea:RegisterForDrag("LeftButton")
        dragArea:SetScript("OnDragStart", function() f:StartMoving() end)
        dragArea:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        -- Gold accent line
        local accent = f:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetHeight(2)
        accent:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
        accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        accent:SetColorTexture(0.6, 0.4, 0.08, 0.5)

        -- Title "Schlachtzüge"
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
        title:SetText("|cFFFFB800Schlachtzüge|r")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)

        -- ============================================================
        -- Expansion dropdown (top right, WoW-style)
        -- ============================================================
        local expDDBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        expDDBtn:SetSize(200, 24)
        expDDBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -12)
        expDDBtn:SetFrameLevel(f:GetFrameLevel() + 10)
        expDDBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        expDDBtn:SetBackdropColor(0.1, 0.06, 0.03, 0.9)
        expDDBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)

        local expDDText = expDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        expDDText:SetPoint("CENTER", -8, 0)
        f.expDDText = expDDText

        local expArrow = expDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        expArrow:SetPoint("RIGHT", expDDBtn, "RIGHT", -6, 0)
        expArrow:SetText("|cFFDDB866v|r")

        -- Expansion dropdown menu (built dynamically)
        local expMenu = CreateFrame("Frame", "OneGuildExpDropdown", UIParent, "BackdropTemplate")
        expMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        expMenu:SetFrameLevel(500)
        expMenu:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        expMenu:SetBackdropColor(0.04, 0.02, 0.02, 0.98)
        expMenu:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.7)
        expMenu:SetClampedToScreen(true)
        expMenu:Hide()
        f.expMenu = expMenu
        f.expMenuItems = {}

        expDDBtn:SetScript("OnClick", function(self)
            if expMenu:IsShown() then
                expMenu:Hide()
                return
            end
            -- Rebuild menu items dynamically
            EnsureEJLoaded()
            for _, old in ipairs(f.expMenuItems) do old:Hide() end
            wipe(f.expMenuItems)

            local itemH = 22
            local count = #EXPANSION_ORDER
            expMenu:SetSize(210, count * itemH + 8)
            expMenu:ClearAllPoints()
            expMenu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -2)

            for idx, tierIdx in ipairs(EXPANSION_ORDER) do
                local item = CreateFrame("Button", nil, expMenu, "BackdropTemplate")
                item:SetSize(200, itemH - 2)
                item:SetPoint("TOPLEFT", expMenu, "TOPLEFT", 4, -((idx - 1) * itemH) - 4)
                item:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

                -- Highlight current selection with radio-style dot
                local isSelected = (f.selectedExpansion == tierIdx)
                if isSelected then
                    item:SetBackdropColor(0.2, 0.12, 0.04, 0.6)
                else
                    item:SetBackdropColor(0, 0, 0, 0)
                end

                -- Selection indicator (WoW-safe characters)
                local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                label:SetPoint("LEFT", 8, 0)
                if isSelected then
                    label:SetText("|cFFFFD700> " .. (EXPANSION_LABELS[tierIdx] or "?") .. "|r")
                else
                    label:SetText("|cFFDDB866   " .. (EXPANSION_LABELS[tierIdx] or "?") .. "|r")
                end

                item:SetScript("OnEnter", function(s) s:SetBackdropColor(0.3, 0.18, 0.05, 0.8) end)
                item:SetScript("OnLeave", function(s)
                    if f.selectedExpansion == tierIdx then
                        s:SetBackdropColor(0.2, 0.12, 0.04, 0.6)
                    else
                        s:SetBackdropColor(0, 0, 0, 0)
                    end
                end)
                item:SetScript("OnClick", function()
                    f.selectedExpansion = tierIdx
                    f.expDDText:SetText("|cFFFFD700" .. (EXPANSION_LABELS[tierIdx] or "?") .. "|r")
                    expMenu:Hide()
                    f.selectedDungeon = nil
                    f.selText:SetText("|cFF888888Wähle oben einen Schlachtzug...|r")
                    f.selIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                    f.selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    OneGuild:RefreshRaidCards()
                end)
                table.insert(f.expMenuItems, item)
            end
            expMenu:Show()
        end)
        expDDBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.18, 0.1, 0.05, 1)
        end)
        expDDBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.06, 0.03, 0.9)
        end)

        -- ============================================================
        -- Raid cards area (scrollable grid)
        -- ============================================================
        local cardsScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        cardsScroll:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
        cardsScroll:SetPoint("TOPRIGHT", f, "TOPRIGHT", -32, -46)
        cardsScroll:SetHeight(CARDS_AREA_H)

        local cardsArea = CreateFrame("Frame", nil, cardsScroll)
        cardsArea:SetSize(DIALOG_W - 48, CARDS_AREA_H)
        cardsScroll:SetScrollChild(cardsArea)
        f.cardsArea = cardsArea
        f.cardsScroll = cardsScroll
        f.raidCards = {}

        -- Style the scrollbar subtly
        local sb = cardsScroll.ScrollBar
        if sb then sb:SetAlpha(0.5) end

        -- ============================================================
        -- Separator line below cards
        -- ============================================================
        local sep = f:CreateTexture(nil, "ARTWORK", nil, 2)
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", cardsScroll, "BOTTOMLEFT", 0, -8)
        sep:SetPoint("TOPRIGHT", cardsScroll, "BOTTOMRIGHT", 16, -8)
        sep:SetColorTexture(0.35, 0.25, 0.08, 0.4)

        -- ============================================================
        -- Bottom form area (below cards)
        -- ============================================================
        local formY = -CARDS_AREA_H - 64

        -- Selected raid display
        local selIcon = f:CreateTexture(nil, "ARTWORK")
        selIcon:SetSize(28, 28)
        selIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 18, formY)
        selIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.selIcon = selIcon

        local selText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        selText:SetPoint("LEFT", selIcon, "RIGHT", 8, 0)
        selText:SetText("|cFF888888Wähle oben einen Schlachtzug...|r")
        f.selText = selText

        -- Raid Name
        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("TOPLEFT", selIcon, "BOTTOMLEFT", 0, -14)
        nameLabel:SetText("|cFFDDB866Raid-Name:|r")

        local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        nameBox:SetSize(360, 22)
        nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -2)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(60)
        f.nameBox = nameBox

        -- Date
        local dateLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -4, -12)
        dateLabel:SetText("|cFFDDB866Datum (TT.MM.JJJJ):|r")

        local dateBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        dateBox:SetSize(115, 22)
        dateBox:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", 4, -2)
        dateBox:SetAutoFocus(false)
        dateBox:SetMaxLetters(10)
        f.dateBox = dateBox

        -- Date dropdown
        local dateDDBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        dateDDBtn:SetSize(24, 22)
        dateDDBtn:SetPoint("LEFT", dateBox, "RIGHT", 2, 0)
        dateDDBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        dateDDBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        dateDDBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        local ddArr = dateDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ddArr:SetPoint("CENTER"); ddArr:SetText("|cFFDDB866v|r")
        dateDDBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.25, 0.15, 0.05, 0.9) end)
        dateDDBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.15, 0.1, 0.05, 0.8) end)

        local dateMenu = RDCreateDropdownMenu(f, dateBox, RDBuildDateOptions(), 170, dateBox)
        f.dateMenu = dateMenu
        dateDDBtn:SetScript("OnClick", function()
            if f.timeMenu and f.timeMenu:IsShown() then f.timeMenu:Hide() end
            RDRefreshDateMenu(dateMenu)
            if dateMenu:IsShown() then dateMenu:Hide() else dateMenu:Show() end
        end)

        -- Time
        local timeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeLabel:SetPoint("LEFT", dateLabel, "RIGHT", 50, 0)
        timeLabel:SetText("|cFFDDB866Uhrzeit (HH:MM):|r")

        local timeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        timeBox:SetSize(75, 22)
        timeBox:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", 4, -2)
        timeBox:SetAutoFocus(false)
        timeBox:SetMaxLetters(5)
        f.timeBox = timeBox

        local timeDDBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        timeDDBtn:SetSize(24, 22)
        timeDDBtn:SetPoint("LEFT", timeBox, "RIGHT", 2, 0)
        timeDDBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        timeDDBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        timeDDBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        local tArr = timeDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tArr:SetPoint("CENTER"); tArr:SetText("|cFFDDB866v|r")
        timeDDBtn:SetScript("OnEnter", function(s) s:SetBackdropColor(0.25, 0.15, 0.05, 0.9) end)
        timeDDBtn:SetScript("OnLeave", function(s) s:SetBackdropColor(0.15, 0.1, 0.05, 0.8) end)

        local timeMenu = RDCreateDropdownMenu(f, timeBox, RDBuildTimeOptions(), 100, timeBox)
        f.timeMenu = timeMenu
        timeDDBtn:SetScript("OnClick", function()
            if f.dateMenu and f.dateMenu:IsShown() then f.dateMenu:Hide() end
            if timeMenu:IsShown() then timeMenu:Hide() else timeMenu:Show() end
        end)

        -- Difficulty
        local diffLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffLabel:SetPoint("TOPLEFT", dateBox, "BOTTOMLEFT", -4, -12)
        diffLabel:SetText("|cFFDDB866Schwierigkeit:|r")

        f.diffButtons = {}
        f.selectedDiff = "normal"
        local diffX = 4
        for _, d in ipairs(DIFFICULTY_LABELS) do
            local db = CreateFrame("Button", nil, f, "BackdropTemplate")
            db:SetSize(90, 22)
            db:SetPoint("TOPLEFT", diffLabel, "BOTTOMLEFT", diffX, -4)
            db:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8, insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            db:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
            db:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)

            local dbText = db:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dbText:SetPoint("CENTER")
            dbText:SetText(d.color .. d.label .. "|r")

            db.diffKey = d.key
            db:SetScript("OnClick", function()
                f.selectedDiff = d.key
                for _, btn in pairs(f.diffButtons) do
                    if btn.diffKey == d.key then
                        btn:SetBackdropColor(0.35, 0.25, 0.05, 1)
                        btn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
                    else
                        btn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
                        btn:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
                    end
                end
            end)

            f.diffButtons[d.key] = db
            diffX = diffX + 96
        end

        -- Lootmeister (right of difficulty buttons)
        local lmLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lmLabel:SetPoint("LEFT", diffLabel, "LEFT", 310, 0)
        lmLabel:SetText("|cFFFF8800Lootmeister (optional):|r")

        local lmBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        lmBox:SetSize(200, 22)
        lmBox:SetPoint("TOPLEFT", lmLabel, "BOTTOMLEFT", 4, -4)
        lmBox:SetAutoFocus(false)
        lmBox:SetMaxLetters(50)
        f.lmBox = lmBox

        -- Notes
        local descLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLabel:SetPoint("TOPLEFT", diffLabel, "BOTTOMLEFT", 0, -34)
        descLabel:SetText("|cFFDDB866Notizen (optional):|r")

        local descScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        descScroll:SetSize(660, 50)
        descScroll:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 4, -2)

        local descBox = CreateFrame("EditBox", nil, descScroll)
        descBox:SetMultiLine(true)
        descBox:SetFontObject("ChatFontNormal")
        descBox:SetWidth(640)
        descBox:SetAutoFocus(false)
        descBox:SetMaxLetters(500)
        descScroll:SetScrollChild(descBox)
        f.descBox = descBox

        -- Create button
        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(200, 32)
        saveBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
        saveBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10, insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        saveBtn:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
        saveBtn:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
        local saveBtnText = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText("|cFFFFFFFFRaid erstellen|r")
        saveBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.55, 0.38, 0.08, 1)
            self:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
        end)
        saveBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
            self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
        end)
        saveBtn:SetScript("OnClick", function()
            OneGuild:CreateRaidFromDialog()
        end)

        f.selectedExpansion = CURRENT_TIER or 1
        f.selectedDungeon   = nil

        f:Hide()
        self.createRaidFrame = f
        table.insert(UISpecialFrames, "OneGuildCreateRaid")
    end

    -- Reset fields
    local f = self.createRaidFrame
    EnsureEJLoaded()
    f.nameBox:SetText("")
    f.dateBox:SetText(date("%d.%m.%Y"))
    f.timeBox:SetText("20:00")
    f.descBox:SetText("")
    f.lmBox:SetText("")
    f.selectedDiff      = "normal"
    f.selectedDungeon   = nil
    f.selectedExpansion  = CURRENT_TIER or 1
    f.expDDText:SetText("|cFFFFD700" .. (EXPANSION_LABELS[f.selectedExpansion] or "Expansion") .. "|r")
    f.selText:SetText("|cFF888888Wähle oben einen Schlachtzug...|r")
    f.selIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    f.selIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if f.expMenu then f.expMenu:Hide() end

    -- Reset difficulty
    for _, d in ipairs(DIFFICULTY_LABELS) do
        local btn = f.diffButtons[d.key]
        if d.key == "normal" then
            btn:SetBackdropColor(0.35, 0.25, 0.05, 1)
            btn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
        else
            btn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
            btn:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
        end
    end

    f:Show()
    self:RefreshRaidCards()
end

------------------------------------------------------------------------
-- Build / refresh raid cards for the selected expansion
------------------------------------------------------------------------
function OneGuild:RefreshRaidCards()
    local f = self.createRaidFrame
    if not f then return end

    local area = f.cardsArea
    EnsureEJLoaded()
    local expKey = f.selectedExpansion or CURRENT_TIER or 1
    local raids = RAID_DATA[expKey] or {}

    -- Hide old cards
    for _, card in ipairs(f.raidCards) do
        card:Hide()
    end

    -- Grid layout: CARDS_PER_ROW cards per row
    local areaW = area:GetWidth()
    if areaW < 10 then areaW = DIALOG_W - 48 end
    local perRow = CARDS_PER_ROW
    local rowCount = math.ceil(#raids / perRow)

    -- Center cards horizontally in each row
    local function getRowStartX(cardsInRow)
        local rowW = cardsInRow * CARD_W + (cardsInRow - 1) * CARD_GAP
        return math.max(0, math.floor((areaW - rowW) / 2))
    end

    -- Resize scroll child to fit all rows
    local totalH = rowCount * CARD_H + math.max(0, rowCount - 1) * CARD_GAP
    area:SetHeight(math.max(CARDS_AREA_H, totalH))

    for i, raid in ipairs(raids) do
        local card = f.raidCards[i]
        if not card then
            card = CreateFrame("Button", nil, area)
            card:SetSize(CARD_W, CARD_H)

            -- One single artwork texture, fills entire card
            card.art = card:CreateTexture(nil, "ARTWORK")
            card.art:SetAllPoints(card)

            -- Golden border frame around the card (like WoW EJ)
            card.border = CreateFrame("Frame", nil, card, "BackdropTemplate")
            card.border:SetAllPoints()
            card.border:SetBackdrop({
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border",
                edgeSize = 16,
                insets   = { left = 4, right = 4, top = 4, bottom = 4 },
            })
            card.border:SetBackdropBorderColor(0.7, 0.55, 0.2, 0.9)

            -- Dark gradient at bottom for text readability
            card.grad = card:CreateTexture(nil, "ARTWORK", nil, 2)
            card.grad:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT")
            card.grad:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT")
            card.grad:SetHeight(30)
            card.grad:SetColorTexture(0, 0, 0, 0.65)

            -- Raid name overlaid on artwork
            card.label = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            card.label:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 8, 8)
            card.label:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -8, 8)
            card.label:SetJustifyH("CENTER")
            card.label:SetWordWrap(true)
            card.label:SetMaxLines(2)

            -- Selected glow border (highlight texture)
            card.glow = card:CreateTexture(nil, "OVERLAY")
            card.glow:SetPoint("TOPLEFT", 4, -4)
            card.glow:SetPoint("BOTTOMRIGHT", -4, 4)
            card.glow:SetColorTexture(0.8, 0.6, 0.1, 0.2)
            card.glow:Hide()

            card:SetScript("OnEnter", function(self)
                if f.selectedDungeon ~= self.raidKey then
                    self.border:SetBackdropBorderColor(1, 0.82, 0.3, 1)
                end
            end)
            card:SetScript("OnLeave", function(self)
                if f.selectedDungeon ~= self.raidKey then
                    self.border:SetBackdropBorderColor(0.7, 0.55, 0.2, 0.9)
                end
            end)
            card:SetScript("OnClick", function(self)
                f.selectedDungeon = self.raidKey
                -- Update selection display below
                f.selText:SetText("|cFFFFD700" .. self.raidLabel .. "|r")
                f.selIcon:SetTexture(self.raidIcon)
                f.selIcon:SetTexCoord(0, 1, 0, 1)
                -- Auto-fill name
                if f.nameBox:GetText() == "" then
                    f.nameBox:SetText(self.raidLabel)
                end
                -- Highlight selected card
                OneGuild:RefreshRaidCardHighlights()
            end)

            f.raidCards[i] = card
        end

        card.raidKey   = raid.key
        card.raidLabel = raid.label
        card.raidIcon  = raid.icon

        local row = math.floor((i - 1) / perRow)
        local col = (i - 1) % perRow
        local cardsThisRow = math.min(perRow, #raids - row * perRow)
        local sx = getRowStartX(cardsThisRow)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", area, "TOPLEFT", sx + col * (CARD_W + CARD_GAP), -(row * (CARD_H + CARD_GAP)))
        card.border:SetBackdropBorderColor(0.7, 0.55, 0.2, 0.9)

        -- 1:1 artwork from EJ, no filter, no crop
        card.art:SetTexture(raid.art or raid.icon or 0)
        card.art:SetTexCoord(0, 1, 0, 1)
        card.art:SetDesaturated(false)
        card.label:SetText("|cFFFFD700" .. raid.label .. "|r")
        card.glow:Hide()
        card:Show()
    end

    -- Hide extra cards
    for i = #raids + 1, #f.raidCards do
        f.raidCards[i]:Hide()
    end

    self:RefreshRaidCardHighlights()
end

------------------------------------------------------------------------
-- Refresh card selection highlights
------------------------------------------------------------------------
function OneGuild:RefreshRaidCardHighlights()
    local f = self.createRaidFrame
    if not f then return end
    for _, card in ipairs(f.raidCards) do
        if card:IsShown() then
            if f.selectedDungeon == card.raidKey then
                card.border:SetBackdropBorderColor(1, 0.85, 0.2, 1)
                card.glow:Show()
            else
                card.border:SetBackdropBorderColor(0.7, 0.55, 0.2, 0.9)
                card.glow:Hide()
            end
        end
    end
end

------------------------------------------------------------------------
-- Save raid from dialog
------------------------------------------------------------------------
function OneGuild:CreateRaidFromDialog()
    local f = self.createRaidFrame
    if not f then return end

    local title = strtrim(f.nameBox:GetText() or "")
    local dateStr = strtrim(f.dateBox:GetText() or "")
    local timeStr = strtrim(f.timeBox:GetText() or "")
    local desc = strtrim(f.descBox:GetText() or "")
    local diff = f.selectedDiff or "normal"
    local dungeon = f.selectedDungeon
    local lootmeister = strtrim(f.lmBox:GetText() or "")

    if title == "" then
        self:PrintError("Bitte gib einen Raid-Namen ein!")
        return
    end

    if not self.db.raids then self.db.raids = {} end

    -- Parse timestamp
    local day, month, year = dateStr:match("(%d+)%.(%d+)%.(%d+)")
    local hour, minute = timeStr:match("(%d+):(%d+)")

    local timestamp = 0
    if day and month and year then
        timestamp = time({
            year  = tonumber(year),
            month = tonumber(month),
            day   = tonumber(day),
            hour  = tonumber(hour) or 20,
            min   = tonumber(minute) or 0,
            sec   = 0,
        })
    end

    table.insert(self.db.raids, {
        title       = title,
        description = desc,
        dateStr     = dateStr,
        timeStr     = timeStr,
        timestamp   = timestamp,
        difficulty  = diff,
        dungeon     = dungeon,
        lootmeister = lootmeister,
        author      = self:GetPlayerName(),
        created     = time(),
        signups     = {},
    })

    self:PrintSuccess("Raid '" .. title .. "' erstellt!")
    f:Hide()
    self:RefreshRaid()

    -- Broadcast to guild
    local newRaid = self.db.raids[#self.db.raids]
    if self.SendSingleRaid then
        self:SendSingleRaid(newRaid)
    end
end

------------------------------------------------------------------------
-- DKP DISTRIBUTION WINDOW
-- Shows all signed-up + grouped players with checkboxes.
-- Dropdown for bonus type, buttons for +10/+20/custom DKP.
------------------------------------------------------------------------
local dkpDistFrame = nil

-- Bonus types (German labels)
local DKP_BONUS_TYPES = {
    { label = "On Time Bonus",            value = "ontime" },
    { label = "Boss Kill Bonus",          value = "bosskill" },
    { label = "Raid Completion Bonus",    value = "completion" },
    { label = "Progression Bonus",        value = "progression" },
    { label = "Standby Bonus",            value = "standby" },
    { label = "Unentschuldigtes Fehlen",  value = "absence" },
    { label = "Korrektur",                value = "correction" },
    { label = "Manuelle Anpassung",       value = "manual" },
    { label = "Zero-Sum Award",           value = "zerosum" },
}

function OneGuild:ShowDKPDistribution()
    if dkpDistFrame then
        dkpDistFrame:Show()
        self:RefreshDKPDistribution()
        return
    end

    local FRAME_W = 520
    local FRAME_H = 500
    local ROW_H   = 22

    local f = CreateFrame("Frame", "OneGuildDKPDistFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 30)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.03, 0.03, 0.97)
    f:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.8)

    -- Title bar (draggable)
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(32)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
    title:SetText("|cFFFF4444DKP Verteilung|r")

    local closeBtn = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Historie button in title bar
    local histBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    histBtn:SetSize(80, 22)
    histBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    histBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    histBtn:SetBackdropColor(0.12, 0.08, 0.25, 0.9)
    histBtn:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.6)
    local histBtnText = histBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    histBtnText:SetPoint("CENTER")
    histBtnText:SetText("|cFF9999FFHistorie|r")
    histBtn:SetScript("OnClick", function() OneGuild:ShowDKPHistory() end)
    histBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.14, 0.4, 1) end)
    histBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.12, 0.08, 0.25, 0.9) end)

    -- ===== BONUS TYPE DROPDOWN =====
    local bonusLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bonusLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -38)
    bonusLabel:SetText("|cFFDDB866Bonus-Typ:|r")

    local bonusBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    bonusBtn:SetSize(220, 24)
    bonusBtn:SetPoint("LEFT", bonusLabel, "RIGHT", 8, 0)
    bonusBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bonusBtn:SetBackdropColor(0.12, 0.06, 0.04, 0.9)
    bonusBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)

    f.bonusBtnText = bonusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.bonusBtnText:SetPoint("LEFT", bonusBtn, "LEFT", 8, 0)
    f.bonusBtnText:SetText("|cFFFFD700Manuelle Anpassung|r")
    f.selectedBonus = "manual"

    local bonusArrow = bonusBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bonusArrow:SetPoint("RIGHT", bonusBtn, "RIGHT", -6, 0)
    bonusArrow:SetText("|cFFFFD700v|r")

    -- Dropdown menu
    local bonusMenu = CreateFrame("Frame", nil, f, "BackdropTemplate")
    bonusMenu:SetWidth(220)
    bonusMenu:SetFrameStrata("TOOLTIP")
    bonusMenu:SetFrameLevel(300)
    bonusMenu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    bonusMenu:SetBackdropColor(0.08, 0.04, 0.03, 0.98)
    bonusMenu:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.8)
    bonusMenu:Hide()
    f.bonusMenu = bonusMenu

    local itemH = 22
    bonusMenu:SetHeight(#DKP_BONUS_TYPES * itemH + 8)
    for idx, bt in ipairs(DKP_BONUS_TYPES) do
        local item = CreateFrame("Button", nil, bonusMenu, "BackdropTemplate")
        item:SetSize(210, itemH - 2)
        item:SetPoint("TOPLEFT", bonusMenu, "TOPLEFT", 4, -((idx - 1) * itemH) - 4)
        item:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        item:SetBackdropColor(0, 0, 0, 0)

        local label = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetPoint("LEFT", 8, 0)
        label:SetText("|cFFFFD700" .. bt.label .. "|r")

        item:SetScript("OnEnter", function(s) s:SetBackdropColor(0.3, 0.18, 0.05, 0.8) end)
        item:SetScript("OnLeave", function(s) s:SetBackdropColor(0, 0, 0, 0) end)
        item:SetScript("OnClick", function()
            f.selectedBonus = bt.value
            f.bonusBtnText:SetText("|cFFFFD700" .. bt.label .. "|r")
            bonusMenu:Hide()
        end)
    end

    bonusBtn:SetScript("OnClick", function(self)
        if bonusMenu:IsShown() then
            bonusMenu:Hide()
        else
            bonusMenu:ClearAllPoints()
            bonusMenu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
            bonusMenu:Show()
        end
    end)

    -- ===== SELECT ALL / DESELECT ALL =====
    local selectAllBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    selectAllBtn:SetSize(120, 22)
    selectAllBtn:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -66)
    selectAllBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    selectAllBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
    selectAllBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.5)
    local selAllText = selectAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selAllText:SetPoint("CENTER")
    selAllText:SetText("|cFFFFD700Alle markieren|r")
    selectAllBtn:SetScript("OnClick", function()
        if f.playerRows then
            for _, pr in ipairs(f.playerRows) do
                if pr.cb then pr.cb:SetChecked(true) end
            end
        end
    end)

    local deselectAllBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    deselectAllBtn:SetSize(130, 22)
    deselectAllBtn:SetPoint("LEFT", selectAllBtn, "RIGHT", 6, 0)
    deselectAllBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    deselectAllBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
    deselectAllBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.5)
    local deselText = deselectAllBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    deselText:SetPoint("CENTER")
    deselText:SetText("|cFF888888Alle abwählen|r")
    deselectAllBtn:SetScript("OnClick", function()
        if f.playerRows then
            for _, pr in ipairs(f.playerRows) do
                if pr.cb then pr.cb:SetChecked(false) end
            end
        end
    end)

    -- Selected count
    f.selectedCount = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.selectedCount:SetPoint("LEFT", deselectAllBtn, "RIGHT", 12, 0)

    -- ===== PLAYER LIST (scrollable) =====
    local listArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listArea:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -92)
    listArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 60)
    listArea:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listArea:SetBackdropColor(0.04, 0.02, 0.02, 0.8)
    listArea:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.4)
    f.listArea = listArea

    -- Column headers
    local colHeader = CreateFrame("Frame", nil, listArea)
    colHeader:SetHeight(18)
    colHeader:SetPoint("TOPLEFT", listArea, "TOPLEFT", 4, -2)
    colHeader:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", -4, -2)

    local hSel = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSel:SetPoint("LEFT", colHeader, "LEFT", 4, 0)
    hSel:SetText("|cFFDDB866\226\156\148|r")
    local hName = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hName:SetPoint("LEFT", colHeader, "LEFT", 30, 0)
    hName:SetText("|cFFDDB866Spieler|r")
    local hDKP = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hDKP:SetPoint("LEFT", colHeader, "LEFT", 200, 0)
    hDKP:SetText("|cFFDDB866Aktuell|r")
    local hNew = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hNew:SetPoint("LEFT", colHeader, "LEFT", 280, 0)
    hNew:SetText("|cFFDDB866Neu|r")
    local hGrp = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hGrp:SetPoint("LEFT", colHeader, "LEFT", 360, 0)
    hGrp:SetText("|cFFDDB866Gruppe|r")

    -- Scroll content
    local scrollContent = CreateFrame("Frame", nil, listArea)
    scrollContent:SetPoint("TOPLEFT", listArea, "TOPLEFT", 4, -22)
    scrollContent:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -4, 4)
    f.scrollContent = scrollContent
    f.playerRows = {}

    listArea:EnableMouseWheel(true)
    f.scrollOffset = 0
    listArea:SetScript("OnMouseWheel", function(_, delta)
        local maxRows = f.totalPlayers or 0
        local visible = math.floor((scrollContent:GetHeight() or 300) / ROW_H)
        local maxOff = math.max(0, maxRows - visible)
        f.scrollOffset = math.max(0, math.min(f.scrollOffset - delta, maxOff))
        OneGuild:RefreshDKPDistribution()
    end)

    -- ===== BOTTOM: DKP AMOUNT BUTTONS =====
    local bottomBar = CreateFrame("Frame", nil, f)
    bottomBar:SetHeight(50)
    bottomBar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local amountLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    amountLabel:SetPoint("LEFT", bottomBar, "LEFT", 14, 12)
    amountLabel:SetText("|cFFDDB866DKP-Betrag:|r")

    -- Preset buttons
    local presets = { -20, -10, 10, 20, 50 }
    local presetBtns = {}
    local prevAnchor = amountLabel

    for _, val in ipairs(presets) do
        local btn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
        btn:SetSize(42, 24)
        btn:SetPoint("LEFT", prevAnchor, "RIGHT", 4, 0)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })

        local isNeg = val < 0
        btn:SetBackdropColor(isNeg and 0.4 or 0.1, isNeg and 0.1 or 0.35, 0.1, 0.9)
        btn:SetBackdropBorderColor(isNeg and 0.7 or 0.3, isNeg and 0.2 or 0.6, isNeg and 0.2 or 0.3, 0.6)

        local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnText:SetPoint("CENTER")
        local prefix = val > 0 and "+" or ""
        local color = isNeg and "|cFFFF6666" or "|cFF66FF66"
        btnText:SetText(color .. prefix .. tostring(val) .. "|r")

        btn:SetScript("OnClick", function()
            OneGuild:ApplyDKPToSelected(val)
        end)
        btn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(isNeg and 0.55 or 0.15, isNeg and 0.15 or 0.45, 0.15, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(isNeg and 0.4 or 0.1, isNeg and 0.1 or 0.35, 0.1, 0.9)
        end)

        table.insert(presetBtns, btn)
        prevAnchor = btn
    end

    -- Custom amount box
    local customBox = CreateFrame("EditBox", nil, bottomBar, "BackdropTemplate")
    customBox:SetSize(50, 24)
    customBox:SetPoint("LEFT", prevAnchor, "RIGHT", 8, 0)
    customBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    customBox:SetBackdropColor(0.1, 0.06, 0.04, 1)
    customBox:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
    customBox:SetFontObject("GameFontHighlight")
    customBox:SetAutoFocus(false)
    customBox:EnableMouse(true)
    customBox:EnableKeyboard(true)
    customBox:SetMaxLetters(6)
    customBox:SetNumeric(false)
    customBox:SetTextInsets(4, 4, 0, 0)
    customBox:SetJustifyH("CENTER")
    customBox:SetText("0")
    customBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    customBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    customBox:SetScript("OnEnterPressed", function(self)
        local val = tonumber(self:GetText())
        if val and val ~= 0 then
            OneGuild:ApplyDKPToSelected(val)
        end
        self:ClearFocus()
    end)

    -- Apply custom button
    local applyBtn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    applyBtn:SetSize(60, 24)
    applyBtn:SetPoint("LEFT", customBox, "RIGHT", 4, 0)
    applyBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 6,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    applyBtn:SetBackdropColor(0.3, 0.2, 0.05, 0.9)
    applyBtn:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    local applyText = applyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    applyText:SetPoint("CENTER")
    applyText:SetText("|cFFFFD700Anwenden|r")
    applyBtn:SetScript("OnClick", function()
        local val = tonumber(customBox:GetText())
        if val and val ~= 0 then
            OneGuild:ApplyDKPToSelected(val)
        end
    end)

    dkpDistFrame = f
    f:Show()
    C_Timer.After(0.05, function() OneGuild:RefreshDKPDistribution() end)
end

------------------------------------------------------------------------
-- Refresh DKP Distribution player list
------------------------------------------------------------------------
function OneGuild:RefreshDKPDistribution()
    if not dkpDistFrame or not dkpDistFrame:IsShown() then return end
    local f = dkpDistFrame

    -- Collect all players: from global groups + all raid signups
    local players = {}   -- { name = "short", fullName = "Full-Realm", group = g or nil, dkp = n }
    local seen = {}

    -- From global groups
    local rg = (self.db and self.db.raidGroups) or {}
    for g = 1, 8 do
        if rg[g] then
            for s = 1, 5 do
                local pName = rg[g][s]
                if pName and not seen[pName] then
                    seen[pName] = true
                    local short = strsplit("-", pName)
                    seen[short] = true
                    local dkp = (self.db.dkp and (self.db.dkp[pName] or self.db.dkp[short])) or 0
                    table.insert(players, {
                        name     = short,
                        fullName = pName,
                        group    = g,
                        dkp      = dkp,
                    })
                end
            end
        end
    end

    -- From all raid signups (not yet grouped)
    if self.db and self.db.raids then
        for _, rd in ipairs(self.db.raids) do
            if rd.signups then
                for sName, sData in pairs(rd.signups) do
                    local st = type(sData) == "table" and sData.status or sData
                    if st and st ~= "declined" and st ~= "withdrawn" and st ~= "none" then
                        local short = strsplit("-", sName)
                        if not seen[sName] and not seen[short] then
                            seen[sName] = true
                            seen[short] = true
                            local dkp = (self.db.dkp and (self.db.dkp[sName] or self.db.dkp[short])) or 0
                            table.insert(players, {
                                name     = short,
                                fullName = sName,
                                group    = nil,
                                dkp      = dkp,
                            })
                        end
                    end
                end
            end
        end
    end

    -- Sort by group (grouped first), then by name
    table.sort(players, function(a, b)
        if (a.group ~= nil) ~= (b.group ~= nil) then return a.group ~= nil end
        if a.group and b.group and a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)

    f.totalPlayers = #players
    f.playerData = players

    local scroll = f.scrollContent
    local ROW_H = 22
    local visible = math.floor((scroll:GetHeight() or 300) / ROW_H)

    -- Preserve check state
    local checkState = {}
    if f.playerRows then
        for _, pr in ipairs(f.playerRows) do
            if pr.fullName and pr.cb then
                checkState[pr.fullName] = pr.cb:GetChecked()
            end
        end
    end

    -- Create / reuse rows
    for i = 1, math.max(visible, #f.playerRows) do
        local dataIdx = i + (f.scrollOffset or 0)
        local p = players[dataIdx]
        local row = f.playerRows[i]

        if not row then
            row = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -((i - 1) * ROW_H))
            row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -((i - 1) * ROW_H))
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

            row.cb = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
            row.cb:SetSize(18, 18)
            row.cb:SetPoint("LEFT", row, "LEFT", 4, 0)

            row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.nameText:SetPoint("LEFT", row, "LEFT", 30, 0)
            row.nameText:SetWidth(160)
            row.nameText:SetJustifyH("LEFT")

            row.dkpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.dkpText:SetPoint("LEFT", row, "LEFT", 200, 0)
            row.dkpText:SetWidth(70)

            row.newDkpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.newDkpText:SetPoint("LEFT", row, "LEFT", 280, 0)
            row.newDkpText:SetWidth(70)

            row.groupText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            row.groupText:SetPoint("LEFT", row, "LEFT", 360, 0)

            f.playerRows[i] = row
        end

        if p then
            row:Show()
            row.fullName = p.fullName
            row.nameText:SetText(p.name)
            row.dkpText:SetText("|cFFFFD700" .. tostring(p.dkp) .. "|r")
            row.newDkpText:SetText("")
            row.groupText:SetText(p.group and ("|cFF8B7355G" .. p.group .. "|r") or "|cFF555555-|r")

            -- Alternate row colors
            if dataIdx % 2 == 0 then
                row:SetBackdropColor(0.08, 0.04, 0.03, 0.5)
            else
                row:SetBackdropColor(0.05, 0.03, 0.02, 0.3)
            end

            -- Restore check state (default checked for new players)
            if checkState[p.fullName] ~= nil then
                row.cb:SetChecked(checkState[p.fullName])
            else
                row.cb:SetChecked(true)
            end
        else
            row:Hide()
            row.fullName = nil
        end
    end

    -- Update selected count
    local selCount = 0
    for _, pr in ipairs(f.playerRows) do
        if pr:IsShown() and pr.cb:GetChecked() then
            selCount = selCount + 1
        end
    end
    f.selectedCount:SetText("|cFF8B7355" .. selCount .. "/" .. #players .. " ausgewählt|r")
end

------------------------------------------------------------------------
-- Apply DKP to all selected players
------------------------------------------------------------------------
function OneGuild:ApplyDKPToSelected(amount)
    if not dkpDistFrame or not dkpDistFrame.playerRows then return end
    if not self.db then return end
    if not self:CanEditDKP() then
        self:Print("|cFFFF4444Du hast keine Berechtigung, DKP zu verteilen.|r")
        return
    end
    if not self.db.dkp then self.db.dkp = {} end

    local f = dkpDistFrame
    local bonusType = f.selectedBonus or "manual"
    local applied = 0

    for _, row in ipairs(f.playerRows) do
        if row:IsShown() and row.cb and row.cb:GetChecked() and row.fullName then
            local pName = row.fullName
            local short = strsplit("-", pName)

            -- Get current DKP
            local current = self.db.dkp[pName] or self.db.dkp[short] or 0
            local newVal = current + amount

            -- Store locally
            self.db.dkp[pName]  = newVal
            self.db.dkp[short]  = newVal

            -- Broadcast + officer note
            if self.SendDKPUpdate then
                self:SendDKPUpdate(pName, newVal)
            end

            -- Update row display
            row.dkpText:SetText("|cFFFFD700" .. tostring(newVal) .. "|r")
            local diffColor = amount >= 0 and "|cFF66FF66+" or "|cFFFF6666"
            row.newDkpText:SetText(diffColor .. tostring(amount) .. "|r")

            -- Record history
            if self.AddDKPHistory then
                local bonusLabel = bonusType
                for _, bt in ipairs(DKP_BONUS_TYPES) do
                    if bt.value == bonusType then bonusLabel = bt.label; break end
                end
                self:AddDKPHistory(pName, amount, newVal, bonusLabel, UnitName("player") or "?")
            end

            applied = applied + 1
        end
    end

    if applied > 0 then
        local prefix = amount >= 0 and "+" or ""
        local bonusLabel = bonusType
        for _, bt in ipairs(DKP_BONUS_TYPES) do
            if bt.value == bonusType then bonusLabel = bt.label; break end
        end
        self:PrintSuccess(prefix .. tostring(amount) .. " DKP (" .. bonusLabel .. ") an " .. applied .. " Spieler verteilt!")
    end

    -- Refresh members tab
    if self.RefreshMembers then self:RefreshMembers() end
end

------------------------------------------------------------------------
-- DKP HISTORY WINDOW
------------------------------------------------------------------------
local dkpHistFrame = nil

function OneGuild:ShowDKPHistory()
    if dkpHistFrame then
        dkpHistFrame:Show()
        self:RefreshDKPHistory()
        return
    end

    local FRAME_W = 580
    local FRAME_H = 460
    local ROW_H   = 20

    local f = CreateFrame("Frame", "OneGuildDKPHistFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(210)
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.05, 0.03, 0.06, 0.97)
    f:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.8)

    -- Title bar
    local tb = CreateFrame("Frame", nil, f)
    tb:SetHeight(32)
    tb:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    tb:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    tb:EnableMouse(true)
    tb:RegisterForDrag("LeftButton")
    tb:SetScript("OnDragStart", function() f:StartMoving() end)
    tb:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -8)
    title:SetText("|cFF9999FFDKP Historie|r")

    local closeBtn = CreateFrame("Button", nil, tb, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Column headers
    local headerBar = CreateFrame("Frame", nil, f)
    headerBar:SetHeight(20)
    headerBar:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -34)
    headerBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -12, -34)

    local hTime = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTime:SetPoint("LEFT", headerBar, "LEFT", 0, 0)
    hTime:SetText("|cFFDDB866Datum/Zeit|r")
    local hPlayer = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPlayer:SetPoint("LEFT", headerBar, "LEFT", 110, 0)
    hPlayer:SetText("|cFFDDB866Spieler|r")
    local hAmount = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hAmount:SetPoint("LEFT", headerBar, "LEFT", 220, 0)
    hAmount:SetText("|cFFDDB866Betrag|r")
    local hTotal = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTotal:SetPoint("LEFT", headerBar, "LEFT", 290, 0)
    hTotal:SetText("|cFFDDB866Gesamt|r")
    local hType = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hType:SetPoint("LEFT", headerBar, "LEFT", 360, 0)
    hType:SetText("|cFFDDB866Typ|r")
    local hSource = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSource:SetPoint("LEFT", headerBar, "LEFT", 480, 0)
    hSource:SetText("|cFFDDB866Von|r")

    -- Scrollable list
    local listArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listArea:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -56)
    listArea:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    listArea:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    listArea:SetBackdropColor(0.04, 0.02, 0.04, 0.8)
    listArea:SetBackdropBorderColor(0.3, 0.2, 0.4, 0.4)
    f.listArea = listArea

    local scrollContent = CreateFrame("Frame", nil, listArea)
    scrollContent:SetPoint("TOPLEFT", listArea, "TOPLEFT", 4, -4)
    scrollContent:SetPoint("BOTTOMRIGHT", listArea, "BOTTOMRIGHT", -4, 4)
    f.scrollContent = scrollContent
    f.histRows = {}
    f.scrollOffset = 0

    listArea:EnableMouseWheel(true)
    listArea:SetScript("OnMouseWheel", function(_, delta)
        local total = f.totalEntries or 0
        local visible = math.floor((scrollContent:GetHeight() or 300) / ROW_H)
        local maxOff = math.max(0, total - visible)
        f.scrollOffset = math.max(0, math.min(f.scrollOffset - delta * 3, maxOff))
        OneGuild:RefreshDKPHistory()
    end)

    dkpHistFrame = f
    self:RefreshDKPHistory()
end

------------------------------------------------------------------------
-- Refresh DKP History
------------------------------------------------------------------------
function OneGuild:RefreshDKPHistory()
    if not dkpHistFrame then return end
    local f = dkpHistFrame
    local ROW_H = 20
    local scroll = f.scrollContent

    local history = (self.db and self.db.dkpHistory) or {}

    -- Show newest first (reverse)
    local sorted = {}
    for i = #history, 1, -1 do
        table.insert(sorted, history[i])
    end

    f.totalEntries = #sorted
    local visible = math.floor((scroll:GetHeight() or 300) / ROW_H)

    for i = 1, math.max(visible + 1, #f.histRows) do
        local dataIdx = i + (f.scrollOffset or 0)
        local entry = sorted[dataIdx]
        local row = f.histRows[i]

        if not row then
            row = CreateFrame("Frame", nil, scroll, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -((i - 1) * ROW_H))
            row:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", 0, -((i - 1) * ROW_H))
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

            row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.timeText:SetPoint("LEFT", row, "LEFT", 2, 0)
            row.timeText:SetWidth(108)
            row.timeText:SetJustifyH("LEFT")

            row.playerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.playerText:SetPoint("LEFT", row, "LEFT", 110, 0)
            row.playerText:SetWidth(105)
            row.playerText:SetJustifyH("LEFT")

            row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.amountText:SetPoint("LEFT", row, "LEFT", 218, 0)
            row.amountText:SetWidth(65)

            row.totalText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.totalText:SetPoint("LEFT", row, "LEFT", 288, 0)
            row.totalText:SetWidth(65)

            row.typeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.typeText:SetPoint("LEFT", row, "LEFT", 358, 0)
            row.typeText:SetWidth(118)
            row.typeText:SetJustifyH("LEFT")

            row.sourceText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            row.sourceText:SetPoint("LEFT", row, "LEFT", 478, 0)
            row.sourceText:SetWidth(75)
            row.sourceText:SetJustifyH("LEFT")

            f.histRows[i] = row
        end

        if entry then
            row:Show()
            -- Timestamp
            local ts = entry.timestamp or 0
            row.timeText:SetText("|cFF888888" .. date("%d.%m %H:%M", ts) .. "|r")

            -- Player name (short)
            local short = strsplit("-", entry.player or "?")
            row.playerText:SetText(short)

            -- Amount with color
            local amt = entry.amount or 0
            local prefix = amt >= 0 and "+" or ""
            local amtColor = amt >= 0 and "|cFF66FF66" or "|cFFFF6666"
            row.amountText:SetText(amtColor .. prefix .. tostring(amt) .. "|r")

            -- New total
            row.totalText:SetText("|cFFFFD700" .. tostring(entry.newTotal or 0) .. "|r")

            -- Bonus type
            row.typeText:SetText("|cFF8B7355" .. (entry.bonusType or "?") .. "|r")

            -- Source
            local srcShort = strsplit("-", entry.source or "?")
            row.sourceText:SetText("|cFF8888AA" .. srcShort .. "|r")

            -- Alternating rows
            if dataIdx % 2 == 0 then
                row:SetBackdropColor(0.06, 0.03, 0.06, 0.5)
            else
                row:SetBackdropColor(0.04, 0.02, 0.04, 0.3)
            end
        else
            row:Hide()
        end
    end
end
