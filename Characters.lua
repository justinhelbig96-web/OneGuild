------------------------------------------------------------------------
-- OneGuild - Characters.lua
-- Auto-detect characters on login, main character selection,
-- and first-time setup wizard
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Characters.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local CHAR_ROW_HEIGHT  = 32
local MAX_CHAR_ROWS    = 16

-- Class icon atlas names (Retail)
local CLASS_ICONS = {
    WARRIOR     = "classicon-warrior",
    PALADIN     = "classicon-paladin",
    HUNTER      = "classicon-hunter",
    ROGUE       = "classicon-rogue",
    PRIEST      = "classicon-priest",
    DEATHKNIGHT = "classicon-deathknight",
    SHAMAN      = "classicon-shaman",
    MAGE        = "classicon-mage",
    WARLOCK     = "classicon-warlock",
    MONK        = "classicon-monk",
    DRUID       = "classicon-druid",
    DEMONHUNTER = "classicon-demonhunter",
    EVOKER      = "classicon-evoker",
}

-- Fallback class icon textures (if atlas not available)
local CLASS_ICON_TEXTURES = {
    WARRIOR     = "Interface\\Icons\\ClassIcon_Warrior",
    PALADIN     = "Interface\\Icons\\ClassIcon_Paladin",
    HUNTER      = "Interface\\Icons\\ClassIcon_Hunter",
    ROGUE       = "Interface\\Icons\\ClassIcon_Rogue",
    PRIEST      = "Interface\\Icons\\ClassIcon_Priest",
    DEATHKNIGHT = "Interface\\Icons\\ClassIcon_DeathKnight",
    SHAMAN      = "Interface\\Icons\\ClassIcon_Shaman",
    MAGE        = "Interface\\Icons\\ClassIcon_Mage",
    WARLOCK     = "Interface\\Icons\\ClassIcon_Warlock",
    MONK        = "Interface\\Icons\\ClassIcon_Monk",
    DRUID       = "Interface\\Icons\\ClassIcon_Druid",
    DEMONHUNTER = "Interface\\Icons\\ClassIcon_DemonHunter",
    EVOKER      = "Interface\\Icons\\ClassIcon_Evoker",
}

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local charRows      = {}
local setupShown    = false

------------------------------------------------------------------------
-- Class color helper
------------------------------------------------------------------------
local function GetClassColor(classFile)
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    return 0.6, 0.6, 0.6
end

------------------------------------------------------------------------
-- Register current character (called every login)
------------------------------------------------------------------------
function OneGuild:RegisterCurrentCharacter()
    if not self.db then return end
    if not self.db.characters then
        self.db.characters = {}
    end

    local name   = UnitName("player")
    local realm  = GetRealmName()
    local key    = name .. "-" .. realm  -- unique key

    local _, classFile = UnitClass("player")
    local className    = UnitClass("player")
    local level        = UnitLevel("player")
    local race         = UnitRace("player")
    local sex          = UnitSex("player")  -- 1=unknown, 2=male, 3=female
    local faction      = UnitFactionGroup("player")

    -- Guild info
    local guildName, guildRank, guildRankIndex = GetGuildInfo("player")

    -- Specialization (Retail)
    local specName = ""
    local specIcon = ""
    if GetSpecialization then
        local specIdx = GetSpecialization()
        if specIdx then
            local _, sName, _, sIcon = GetSpecializationInfo(specIdx)
            specName = sName or ""
            specIcon = sIcon or ""
        end
    end

    -- Item level (Retail)
    local avgItemLevel = 0
    local avgItemLevelEquipped = 0
    if GetAverageItemLevel then
        avgItemLevel, avgItemLevelEquipped = GetAverageItemLevel()
        avgItemLevel = math.floor(avgItemLevel or 0)
        avgItemLevelEquipped = math.floor(avgItemLevelEquipped or 0)
    end

    -- Money
    local money = GetMoney() or 0

    -- Preserve main status if already set
    local isMain = false
    if self.db.characters[key] then
        isMain = self.db.characters[key].isMain or false
    end

    self.db.characters[key] = {
        name        = name,
        realm       = realm,
        classFile   = classFile or "",
        className   = className or "",
        level       = level or 0,
        race        = race or "",
        sex         = sex or 1,
        faction     = faction or "",
        guildName   = guildName or "",
        guildRank   = guildRank or "",
        guildRankIdx = guildRankIndex or 99,
        specName    = specName,
        specIcon    = specIcon,
        itemLevel   = avgItemLevel,
        itemLevelEq = avgItemLevelEquipped,
        money       = money,
        lastLogin   = time(),
        isMain      = isMain,
        inGuild     = (guildName == self.REQUIRED_GUILD),
    }

    self:Print(OneGuild.COLORS.INFO .. name .. "|r (" .. realm .. ") registriert. " ..
        OneGuild.COLORS.MUTED .. "Insgesamt " .. self:GetCharacterCount() ..
        " Charaktere bekannt.|r")
end

------------------------------------------------------------------------
-- Count characters
------------------------------------------------------------------------
function OneGuild:GetCharacterCount()
    local count = 0
    if self.db and self.db.characters then
        for _ in pairs(self.db.characters) do
            count = count + 1
        end
    end
    return count
end

------------------------------------------------------------------------
-- Get the main character
------------------------------------------------------------------------
function OneGuild:GetMainCharacter()
    if not self.db or not self.db.characters then return nil end
    for key, char in pairs(self.db.characters) do
        if char.isMain then
            return key, char
        end
    end
    return nil
end

------------------------------------------------------------------------
-- Set a character as main (unsets all others)
------------------------------------------------------------------------
function OneGuild:SetMainCharacter(charKey)
    if not self.db or not self.db.characters then return end

    for key, char in pairs(self.db.characters) do
        char.isMain = (key == charKey)
    end

    local char = self.db.characters[charKey]
    if char then
        self:PrintSuccess(char.name .. "-" .. char.realm ..
            " ist jetzt dein " .. OneGuild.COLORS.WARNING .. "Main-Charakter|r!")
    end
end

------------------------------------------------------------------------
-- Check if this is first login (rules not accepted yet) → show rules
------------------------------------------------------------------------
function OneGuild:CheckRulesAccepted()
    if not self.db then return end

    if not self.db.rulesAccepted then
        -- Show after a slight delay so UI is ready
        C_Timer.After(1, function()
            OneGuild:ShowRulesDialog()
        end)
    end
end

------------------------------------------------------------------------
-- Get sorted character list
------------------------------------------------------------------------
function OneGuild:GetSortedCharacters()
    local list = {}
    if not self.db or not self.db.characters then return list end

    for key, char in pairs(self.db.characters) do
        table.insert(list, { key = key, data = char })
    end

    -- Sort: main first, then by level desc, then name
    table.sort(list, function(a, b)
        if a.data.isMain ~= b.data.isMain then return a.data.isMain end
        if a.data.level ~= b.data.level then return a.data.level > b.data.level end
        return a.data.name < b.data.name
    end)

    return list
end

------------------------------------------------------------------------
-- Build Characters Tab (Tab 5)
------------------------------------------------------------------------
function OneGuild:BuildCharactersTab()
    local parent = self.tabFrames[6]
    if not parent then return end

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10)
    header:SetText(OneGuild.COLORS.INFO .. "🎭 Meine Charaktere|r")

    -- Main character display
    local mainBg = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    mainBg:SetHeight(48)
    mainBg:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    mainBg:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, 0)
    mainBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    mainBg:SetBackdropColor(0.05, 0.12, 0.05, 0.8)
    mainBg:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.5)

    local mainLabel = mainBg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mainLabel:SetPoint("TOPLEFT", mainBg, "TOPLEFT", 10, -6)
    mainLabel:SetText(OneGuild.COLORS.WARNING .. "Main-Charakter|r")

    local mainText = mainBg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainText:SetPoint("TOPLEFT", mainLabel, "BOTTOMLEFT", 0, -2)
    mainText:SetText(OneGuild.COLORS.MUTED .. "Nicht gesetzt — wähle unten deinen Main!|r")
    parent.mainText = mainText

    -- Info text
    local infoText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("TOPLEFT", mainBg, "BOTTOMLEFT", 0, -6)
    infoText:SetTextColor(0.5, 0.5, 0.5)
    infoText:SetText("Klicke auf den Stern um einen Charakter als Main zu setzen. " ..
        "Jeder Charakter wird beim Einloggen automatisch registriert.")
    infoText:SetWordWrap(true)
    infoText:SetWidth(580)
    parent.infoText = infoText

    -- Separator
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.3)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", infoText, "BOTTOMLEFT", 0, -6)
    sep:SetPoint("TOPRIGHT", mainBg, "BOTTOMRIGHT", 0, -6)

    -- Column headers
    local colHeader = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colHeader:SetHeight(22)
    colHeader:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -2)
    colHeader:SetPoint("TOPRIGHT", sep, "BOTTOMRIGHT", 0, -2)
    colHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    colHeader:SetBackdropColor(0.12, 0.12, 0.18, 0.9)

    local colTexts = {
        { "Main",     30 },
        { "Name",     140 },
        { "Realm",    120 },
        { "Lvl",      40 },
        { "Klasse",   100 },
        { "iLvl",     50 },
        { "Gilde",    100 },
        { "Zuletzt",  90 },
    }
    local xOff = 6
    for _, col in ipairs(colTexts) do
        local t = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        t:SetPoint("LEFT", colHeader, "LEFT", xOff, 0)
        t:SetTextColor(0.6, 0.8, 1)
        t:SetText(col[1])
        xOff = xOff + col[2]
    end

    -- Scrollable character list
    local listArea = CreateFrame("Frame", nil, parent)
    listArea:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
    listArea:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 8)

    for i = 1, MAX_CHAR_ROWS do
        local row = CreateFrame("Frame", nil, listArea, "BackdropTemplate")
        row:SetHeight(CHAR_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", listArea, "TOPLEFT", 0, -((i - 1) * CHAR_ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", listArea, "TOPRIGHT", 0, -((i - 1) * CHAR_ROW_HEIGHT))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })

        if i % 2 == 0 then
            row:SetBackdropColor(0.07, 0.07, 0.1, 0.5)
        else
            row:SetBackdropColor(0, 0, 0, 0)
        end

        -- Star button (set as main)
        row.starBtn = CreateFrame("Button", nil, row)
        row.starBtn:SetSize(22, 22)
        row.starBtn:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.crownIcon = row.starBtn:CreateTexture(nil, "OVERLAY")
        row.crownIcon:SetSize(16, 16)
        row.crownIcon:SetPoint("CENTER")
        row.crownIcon:SetTexture("Interface\\GROUPFRAME\\UI-Group-LeaderIcon")
        row.crownIcon:Hide()

        row.starText = row.starBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.starText:SetPoint("CENTER")
        row.starText:SetText("|cFF555555-|r")
        row.starBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Als Main setzen", 1, 0.8, 0)
            GameTooltip:Show()
        end)
        row.starBtn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        -- Class icon
        row.classIcon = row:CreateTexture(nil, "ARTWORK")
        row.classIcon:SetSize(20, 20)
        row.classIcon:SetPoint("LEFT", row, "LEFT", 36, 0)

        -- Name
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.nameText:SetPoint("LEFT", row, "LEFT", 60, 0)
        row.nameText:SetWidth(110)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)

        -- Realm
        row.realmText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.realmText:SetPoint("LEFT", row, "LEFT", 170, 0)
        row.realmText:SetWidth(110)
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetTextColor(0.6, 0.6, 0.6)

        -- Level
        row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.levelText:SetPoint("LEFT", row, "LEFT", 290, 0)
        row.levelText:SetWidth(35)
        row.levelText:SetJustifyH("CENTER")

        -- Class name
        row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.classText:SetPoint("LEFT", row, "LEFT", 330, 0)
        row.classText:SetWidth(90)
        row.classText:SetJustifyH("LEFT")
        row.classText:SetWordWrap(false)

        -- Item Level
        row.ilvlText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.ilvlText:SetPoint("LEFT", row, "LEFT", 430, 0)
        row.ilvlText:SetWidth(45)
        row.ilvlText:SetJustifyH("CENTER")

        -- Guild status
        row.guildText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.guildText:SetPoint("LEFT", row, "LEFT", 480, 0)
        row.guildText:SetWidth(90)
        row.guildText:SetJustifyH("LEFT")
        row.guildText:SetWordWrap(false)

        -- Last login
        row.lastText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.lastText:SetPoint("LEFT", row, "LEFT", 580, 0)
        row.lastText:SetWidth(80)
        row.lastText:SetJustifyH("LEFT")
        row.lastText:SetTextColor(0.5, 0.5, 0.5)

        -- Hover
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.25, 0.4, 0.6)
            if self.charData then
                GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                local d = self.charData
                local r, g, b = GetClassColor(d.classFile)
                GameTooltip:AddLine(d.name .. "-" .. d.realm, r, g, b)
                GameTooltip:AddLine(d.race .. " " .. d.className, 0.8, 0.8, 0.8)
                if d.specName ~= "" then
                    GameTooltip:AddLine("Spec: " .. d.specName, 0.7, 0.7, 1)
                end
                if d.itemLevel > 0 then
                    GameTooltip:AddLine("Item Level: " .. d.itemLevelEq .. " (avg " .. d.itemLevel .. ")", 0.6, 0.9, 0.6)
                end
                if d.guildName ~= "" then
                    GameTooltip:AddLine("Gilde: <" .. d.guildName .. "> " .. d.guildRank, 0.4, 1, 0.4)
                end
                if d.money > 0 then
                    GameTooltip:AddLine("Gold: " .. GetCoinTextureString(d.money), 1, 1, 1)
                end
                if d.isMain then
                    GameTooltip:AddLine("MAIN CHARAKTER", 1, 0.8, 0)
                end
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Letzter Login: " .. OneGuild:FormatTime(d.lastLogin), 0.5, 0.5, 0.5)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if i % 2 == 0 then
                self:SetBackdropColor(0.07, 0.07, 0.1, 0.5)
            else
                self:SetBackdropColor(0, 0, 0, 0)
            end
            GameTooltip:Hide()
        end)

        row:Hide()
        charRows[i] = row
    end

    -- Mouse wheel scroll
    parent:EnableMouseWheel(true)
    parent.scrollOffset = 0
    parent:SetScript("OnMouseWheel", function(self, delta)
        local maxOffset = math.max(0, OneGuild:GetCharacterCount() - MAX_CHAR_ROWS)
        self.scrollOffset = math.max(0, math.min(maxOffset, (self.scrollOffset or 0) - delta * 2))
        OneGuild:RefreshCharacters()
    end)

    -- Empty state
    parent.emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    parent.emptyText:SetPoint("CENTER", listArea, "CENTER", 0, 0)
    parent.emptyText:SetText(OneGuild.COLORS.MUTED ..
        "Noch keine Charaktere registriert.\nLogge dich mit deinen Chars ein!|r")
    parent.emptyText:Hide()
end

------------------------------------------------------------------------
-- Refresh Characters Tab
------------------------------------------------------------------------
function OneGuild:RefreshCharacters()
    if not self.db or not self.db.characters then return end

    local parent = self.tabFrames[6]
    if not parent then return end

    local sorted = self:GetSortedCharacters()
    local offset = parent.scrollOffset or 0

    -- Update main display
    local mainKey, mainChar = self:GetMainCharacter()
    if mainChar then
        local r, g, b = GetClassColor(mainChar.classFile)
        local colorHex = string.format("|cFF%02x%02x%02x", r * 255, g * 255, b * 255)
        parent.mainText:SetText(
            colorHex .. mainChar.name .. "|r" ..
            OneGuild.COLORS.MUTED .. " - " .. mainChar.realm .. "  |r" ..
            OneGuild.COLORS.INFO .. "Lvl " .. mainChar.level .. "|r  " ..
            colorHex .. mainChar.className .. "|r" ..
            (mainChar.specName ~= "" and ("  (" .. mainChar.specName .. ")") or "") ..
            (mainChar.itemLevel > 0 and ("  " .. OneGuild.COLORS.SUCCESS .. "iLvl " .. mainChar.itemLevelEq .. "|r") or "")
        )
    else
        parent.mainText:SetText(OneGuild.COLORS.WARNING ..
            "Kein Main gesetzt! Klicke auf den Stern bei einem Charakter.|r")
    end

    -- Update rows
    for i = 1, MAX_CHAR_ROWS do
        local row = charRows[i]
        local idx = i + offset
        if idx <= #sorted then
            local entry = sorted[idx]
            local char = entry.data
            row.charKey  = entry.key
            row.charData = char

            local r, g, b = GetClassColor(char.classFile)

            -- Main crown / dash
            if char.isMain then
                row.crownIcon:Show()
                row.starText:SetText("")
            else
                row.crownIcon:Hide()
                row.starText:SetText("|cFF555555-|r")
            end
            row.starBtn:SetScript("OnClick", function()
                OneGuild:SetMainCharacter(entry.key)
                OneGuild:RefreshCharacters()
            end)

            -- Class icon
            local iconTex = CLASS_ICON_TEXTURES[char.classFile]
            if iconTex then
                row.classIcon:SetTexture(iconTex)
                row.classIcon:Show()
            else
                row.classIcon:Hide()
            end

            -- Name (class-colored)
            row.nameText:SetText(char.name)
            row.nameText:SetTextColor(r, g, b)

            -- Realm
            row.realmText:SetText(char.realm)

            -- Level
            row.levelText:SetText(tostring(char.level))
            if char.level >= 80 then
                row.levelText:SetTextColor(1, 0.8, 0)
            else
                row.levelText:SetTextColor(0.8, 0.8, 0.8)
            end

            -- Class
            row.classText:SetText(char.className)
            row.classText:SetTextColor(r, g, b)

            -- iLvl
            if char.itemLevel > 0 then
                row.ilvlText:SetText(tostring(char.itemLevelEq))
                row.ilvlText:SetTextColor(0.6, 0.9, 0.6)
            else
                row.ilvlText:SetText("-")
                row.ilvlText:SetTextColor(0.4, 0.4, 0.4)
            end

            -- Guild
            if char.inGuild then
                row.guildText:SetText("|cFF40FF40<" .. OneGuild.REQUIRED_GUILD .. ">|r")
            elseif char.guildName ~= "" then
                row.guildText:SetText(OneGuild.COLORS.MUTED .. "<" .. char.guildName .. ">|r")
            else
                row.guildText:SetText(OneGuild.COLORS.MUTED .. "Keine|r")
            end

            -- Last login
            local elapsed = time() - (char.lastLogin or 0)
            local lastStr
            if elapsed < 60 then
                lastStr = "Gerade eben"
            elseif elapsed < 3600 then
                lastStr = math.floor(elapsed / 60) .. " Min"
            elseif elapsed < 86400 then
                lastStr = math.floor(elapsed / 3600) .. " Std"
            else
                lastStr = math.floor(elapsed / 86400) .. " Tage"
            end
            row.lastText:SetText(lastStr)

            -- Highlight current character
            local currentKey = OneGuild:GetPlayerName() .. "-" .. GetRealmName()
            if entry.key == currentKey then
                row:SetBackdropColor(0.05, 0.15, 0.05, 0.6)
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Empty state
    if parent.emptyText then
        if #sorted == 0 then
            parent.emptyText:Show()
        else
            parent.emptyText:Hide()
        end
    end
end

------------------------------------------------------------------------
-- Rules Acceptance Dialog (First-Time Setup)
------------------------------------------------------------------------
function OneGuild:ShowRulesDialog()
    if self.rulesFrame and self.rulesFrame:IsShown() then
        return
    end

    if not self.rulesFrame then
        local f = CreateFrame("Frame", "OneGuildRulesDialog", UIParent, "BackdropTemplate")
        f:SetSize(480, 420)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(250)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
        f:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)

        -- Drag
        local drag = CreateFrame("Frame", nil, f)
        drag:SetHeight(40)
        drag:SetPoint("TOPLEFT")
        drag:SetPoint("TOPRIGHT")
        drag:EnableMouse(true)
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() f:StartMoving() end)
        drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        -- Gold top accent
        local accent = f:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetHeight(2)
        accent:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
        accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        accent:SetColorTexture(0.7, 0.5, 0.1, 0.6)

        -- Guild logo
        local logo = f:CreateTexture(nil, "ARTWORK")
        logo:SetSize(64, 32)
        logo:SetPoint("TOP", f, "TOP", 0, -16)
        logo:SetTexture("Interface\\AddOns\\OneGuild\\logo")

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY")
        title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
        title:SetPoint("TOP", logo, "BOTTOM", 0, -8)
        title:SetText("|cFFFFB800Gildenregeln|r")

        -- Subtitle
        local sub = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        sub:SetPoint("TOP", title, "BOTTOM", 0, -4)
        sub:SetText("|cFFDDB866<" .. OneGuild.REQUIRED_GUILD .. ">|r")

        -- Separator
        local sep = f:CreateTexture(nil, "ARTWORK")
        sep:SetColorTexture(0.5, 0.35, 0.1, 0.4)
        sep:SetHeight(1)
        sep:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -100)
        sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -100)

        -- Rules scrollable area
        local rulesArea = CreateFrame("Frame", nil, f, "BackdropTemplate")
        rulesArea:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -108)
        rulesArea:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -108)
        rulesArea:SetHeight(200)
        rulesArea:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        rulesArea:SetBackdropColor(0.04, 0.02, 0.02, 0.9)
        rulesArea:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.5)

        -- Rules text (placeholder)
        local rulesText = rulesArea:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        rulesText:SetPoint("TOPLEFT", rulesArea, "TOPLEFT", 14, -14)
        rulesText:SetPoint("TOPRIGHT", rulesArea, "TOPRIGHT", -14, -14)
        rulesText:SetJustifyH("LEFT")
        rulesText:SetWordWrap(true)
        rulesText:SetSpacing(3)
        rulesText:SetText("|cFFFFFFFF Du hast einen großen Pimmel|r")

        -- Separator 2
        local sep2 = f:CreateTexture(nil, "ARTWORK")
        sep2:SetColorTexture(0.5, 0.35, 0.1, 0.4)
        sep2:SetHeight(1)
        sep2:SetPoint("TOPLEFT", rulesArea, "BOTTOMLEFT", 0, -8)
        sep2:SetPoint("TOPRIGHT", rulesArea, "BOTTOMRIGHT", 0, -8)

        -- Instruction text
        local instrText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        instrText:SetPoint("TOP", sep2, "BOTTOM", 0, -8)
        instrText:SetText("|cFFDDB866Tippe|r |cFFFFCC00VERSTANDEN|r |cFFDDB866ein um zu bestätigen:|r")

        -- Input box
        local inputBox = CreateFrame("EditBox", "OneGuildRulesInput", f, "BackdropTemplate")
        inputBox:SetSize(300, 32)
        inputBox:SetPoint("TOP", instrText, "BOTTOM", 0, -8)
        inputBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        inputBox:SetBackdropColor(0.1, 0.06, 0.04, 0.9)
        inputBox:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)
        inputBox:SetFontObject("GameFontHighlightLarge")
        inputBox:SetJustifyH("CENTER")
        inputBox:SetAutoFocus(false)
        inputBox:SetMaxLetters(20)
        inputBox:SetTextInsets(8, 8, 0, 0)
        f.inputBox = inputBox

        -- Confirm button (starts disabled)
        local confirmBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        confirmBtn:SetSize(240, 36)
        confirmBtn:SetPoint("TOP", inputBox, "BOTTOM", 0, -12)
        confirmBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        confirmBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.6)
        confirmBtn:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.3)

        local confirmText = confirmBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        confirmText:SetPoint("CENTER")
        confirmText:SetText("|cFF555555Regeln akzeptieren|r")
        confirmBtn.text = confirmText
        confirmBtn:Disable()
        f.confirmBtn = confirmBtn

        -- Function to update button state based on input
        local function UpdateConfirmState()
            local text = inputBox:GetText() or ""
            text = text:upper():gsub("^%s+", ""):gsub("%s+$", "")
            if text == "VERSTANDEN" then
                confirmBtn:Enable()
                confirmBtn:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
                confirmBtn:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
                confirmBtn.text:SetText("|cFFFFFFFFRegeln akzeptieren|r")
            else
                confirmBtn:Disable()
                confirmBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.6)
                confirmBtn:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.3)
                confirmBtn.text:SetText("|cFF555555Regeln akzeptieren|r")
            end
        end

        inputBox:SetScript("OnTextChanged", function()
            UpdateConfirmState()
        end)
        inputBox:SetScript("OnEnterPressed", function(self)
            local text = self:GetText() or ""
            text = text:upper():gsub("^%s+", ""):gsub("%s+$", "")
            if text == "VERSTANDEN" then
                confirmBtn:Click()
            end
            self:ClearFocus()
        end)
        inputBox:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        confirmBtn:SetScript("OnClick", function()
            OneGuild.db.rulesAccepted = true
            f:Hide()
            OneGuild:PrintSuccess("Regeln akzeptiert! Willkommen bei " ..
                OneGuild.COLORS.GUILD .. "<" .. OneGuild.REQUIRED_GUILD .. ">|r!")
        end)
        confirmBtn:SetScript("OnEnter", function(self)
            if self:IsEnabled() then
                self:SetBackdropColor(0.55, 0.38, 0.08, 1)
                self:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
            end
        end)
        confirmBtn:SetScript("OnLeave", function(self)
            if self:IsEnabled() then
                self:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
                self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
            end
        end)

        -- Block ESC and closing
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)
        f:EnableKeyboard(true)

        f:Hide()
        self.rulesFrame = f
        -- Do NOT add to UISpecialFrames — dialog must not be closable via ESC
    end

    -- Reset input on each show
    local f = self.rulesFrame
    f.inputBox:SetText("")
    f.confirmBtn:Disable()
    f.confirmBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.6)
    f.confirmBtn:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.3)
    f.confirmBtn.text:SetText("|cFF555555Regeln akzeptieren|r")
    f:Show()
end
