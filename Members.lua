------------------------------------------------------------------------
-- OneGuild - Members.lua
-- Shows ALL known addon members (online + offline) with their mains.
-- Click a member to expand and see their alts (Twinks) with details.
-- Admin mode allows editing DKP inline.
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Members.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ROW_HEIGHT    = 28
local ALT_ROW_H    = 26
local DKP_ROW_H    = 32
local HEADER_HEIGHT = 26
local MAX_ROW_POOL  = 20

------------------------------------------------------------------------
-- Class Colors
------------------------------------------------------------------------
local CLASS_COLORS_FALLBACK = {
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

local function GetClassColor(classFile)
    if not classFile then return 0.7, 0.7, 0.7 end
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile] then
        local c = RAID_CLASS_COLORS[classFile]
        return c.r, c.g, c.b
    end
    local c = CLASS_COLORS_FALLBACK[classFile]
    if c then return c.r, c.g, c.b end
    return 0.7, 0.7, 0.7
end

------------------------------------------------------------------------
-- Helper: get DKP for a member (uses centralized getter)
------------------------------------------------------------------------
local function GetDKP(member)
    -- Use centralized function (resolves via short name)
    if OneGuild.GetDKPForPlayer then
        return OneGuild:GetDKPForPlayer(member.sender)
    end
    return 0
end

local function GetDKPKey(member)
    return member.sender
end

local function SetDKP(member, val)
    -- SendDKPUpdate stores locally with timestamp AND broadcasts to guild
    if OneGuild.SendDKPUpdate then
        OneGuild:SendDKPUpdate(member.sender, val)
    end
end

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local rowPool        = {}
local scrollOffset   = 0
local membersParent  = nil
local expandedKeys   = {}   -- [member.sender] = true  when expanded
local displayList    = {}   -- flat list built each refresh

------------------------------------------------------------------------
-- Right-click context menu (standard WoW player dropdown)
------------------------------------------------------------------------
local memberDropdown = CreateFrame("Frame", "OneGuildMemberDropdown", UIParent, "UIDropDownMenuTemplate")

local function ShowMemberContextMenu(anchor, memberName, memberRealm)
    -- Build full name for WoW API
    local fullName = memberName
    if memberRealm and memberRealm ~= "" then
        if not string.find(fullName, "-") then
            fullName = memberName .. "-" .. memberRealm
        end
    end

    UIDropDownMenu_Initialize(memberDropdown, function(self, level)
        if not level or level == 1 then
            -- Header
            local header = UIDropDownMenu_CreateInfo()
            header.text = fullName
            header.isTitle = true
            header.notCheckable = true
            UIDropDownMenu_AddButton(header, level)

            -- Flüstern (Whisper)
            local whisper = UIDropDownMenu_CreateInfo()
            whisper.text = "Flüstern"
            whisper.notCheckable = true
            whisper.func = function()
                ChatFrame_SendTell(fullName)
            end
            UIDropDownMenu_AddButton(whisper, level)

            -- Einladen (Invite)
            local invite = UIDropDownMenu_CreateInfo()
            invite.text = "Einladen"
            invite.notCheckable = true
            invite.func = function()
                C_PartyInfo.InviteUnit(fullName)
            end
            UIDropDownMenu_AddButton(invite, level)

            -- Kontakt hinzufügen (Add friend)
            local friend = UIDropDownMenu_CreateInfo()
            friend.text = "+ Kontakt"
            friend.notCheckable = true
            friend.func = function()
                AddFriend(fullName)
            end
            UIDropDownMenu_AddButton(friend, level)

            -- Ignorieren (Ignore)
            local ignore = UIDropDownMenu_CreateInfo()
            ignore.text = "Ignorieren"
            ignore.notCheckable = true
            ignore.func = function()
                AddIgnore(fullName)
            end
            UIDropDownMenu_AddButton(ignore, level)

            -- Separator
            local sep = UIDropDownMenu_CreateInfo()
            sep.text = ""
            sep.isTitle = true
            sep.notCheckable = true
            sep.iconOnly = true
            UIDropDownMenu_AddButton(sep, level)

            -- Charakternamen kopieren (copy name to chat input)
            local copy = UIDropDownMenu_CreateInfo()
            copy.text = "Charakternamen kopieren"
            copy.notCheckable = true
            copy.func = function()
                local editBox = ChatFrame1EditBox
                if editBox then
                    editBox:Show()
                    editBox:SetFocus()
                    editBox:SetText(fullName)
                    editBox:HighlightText()
                end
            end
            UIDropDownMenu_AddButton(copy, level)

            -- Abbrechen (Cancel)
            local cancel = UIDropDownMenu_CreateInfo()
            cancel.text = CANCEL or "Abbrechen"
            cancel.notCheckable = true
            cancel.func = function() CloseDropDownMenus() end
            UIDropDownMenu_AddButton(cancel, level)
        end
    end, "MENU")

    ToggleDropDownMenu(1, nil, memberDropdown, anchor, 0, 0)
end

------------------------------------------------------------------------
-- Get ALL known addon members (online + offline)
-- Merges entries that share the same Main (mainName-mainRealm)
-- so a player switching chars only shows once.
------------------------------------------------------------------------
function OneGuild:GetAllAddonMembers()
    local list = {}
    if not self.db or not self.db.addonMembers then return list end

    -- Group by main identity  (mainName-mainRealm)
    local byMain = {}   -- [mainKey] = merged entry
    local order  = {}    -- keep insertion order for determinism

    for senderKey, member in pairs(self.db.addonMembers) do
        local mainKey
        if member.mainName and member.mainRealm then
            mainKey = member.mainName .. "-" .. member.mainRealm
        elseif member.mainName then
            mainKey = member.mainName
        else
            mainKey = senderKey   -- no main → treat as unique
        end

        local existing = byMain[mainKey]
        if not existing then
            -- First entry for this main → deep-copy into merged entry
            local merged = {
                sender        = member.sender,
                mainName      = member.mainName,
                mainRealm     = member.mainRealm,
                mainClass     = member.mainClass,
                mainLevel     = member.mainLevel,
                mainClassName = member.mainClassName,
                version       = member.version,
                online        = member.online,
                lastSeen      = member.lastSeen,
                hasMain       = member.hasMain,
                characters    = {},
                _senderKeys   = { senderKey },   -- track all sender keys for DKP
            }
            -- Copy characters
            if member.characters then
                for ck, cv in pairs(member.characters) do
                    merged.characters[ck] = cv
                end
            end
            byMain[mainKey] = merged
            table.insert(order, mainKey)
        else
            -- Merge into existing
            table.insert(existing._senderKeys, senderKey)

            -- Use the MOST RECENTLY SEEN entry's online status
            -- (fixes stale online=true from old sessions)
            local memberLast = member.lastSeen or 0
            local existLast  = existing.lastSeen or 0
            if memberLast >= existLast then
                existing.online   = member.online
                existing.lastSeen = member.lastSeen
                existing.sender   = member.sender
            end

            -- Prefer higher level / newer version
            if (member.mainLevel or 0) > (existing.mainLevel or 0) then
                existing.mainLevel = member.mainLevel
            end
            if member.version and member.version ~= "?" then
                existing.version = member.version
            end

            -- Merge characters
            if member.characters then
                for ck, cv in pairs(member.characters) do
                    existing.characters[ck] = cv
                end
            end
        end
    end

    -- Flatten to list
    for _, mainKey in ipairs(order) do
        table.insert(list, byMain[mainKey])
    end

    table.sort(list, function(a, b)
        if a.online ~= b.online then return a.online end
        local aName = a.mainName or a.sender or ""
        local bName = b.mainName or b.sender or ""
        return aName < bName
    end)

    return list
end

------------------------------------------------------------------------
-- Build flat display list (member rows + expanded alt/dkp rows)
------------------------------------------------------------------------
local function BuildDisplayList(members)
    local list = {}
    for _, member in ipairs(members) do
        table.insert(list, { type = "member", data = member })

        if expandedKeys[member.sender] then
            -- If admin, show DKP editor row first
            if OneGuild.isAdmin then
                table.insert(list, { type = "dkp_edit", data = member })
            end

            local chars = member.characters or {}
            local sorted = {}
            for ck, ch in pairs(chars) do
                ch._key = ck
                table.insert(sorted, ch)
            end
            table.sort(sorted, function(a, b)
                if (a.isMain and not b.isMain) then return true end
                if (b.isMain and not a.isMain) then return false end
                return (a.name or "") < (b.name or "")
            end)

            if #sorted == 0 then
                table.insert(list, { type = "no_chars", parent = member })
            else
                for _, ch in ipairs(sorted) do
                    table.insert(list, { type = "alt", data = ch, parent = member })
                end
            end
        end
    end
    return list
end

------------------------------------------------------------------------
-- Build Members Tab (Tab 2)
------------------------------------------------------------------------
function OneGuild:BuildMembersTab()
    local parent = self.tabFrames[1]
    if not parent then return end
    membersParent = parent

    -- Header bar
    local headerBar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    headerBar:SetHeight(36)
    headerBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 6, -6)
    headerBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, -6)
    headerBar:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    headerBar:SetBackdropColor(0.1, 0.05, 0.03, 0.8)
    headerBar:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.4)

    -- Title
    local titleText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", headerBar, "LEFT", 10, 0)
    titleText:SetText("|cFFFFD700Alle Mitglieder|r")
    parent.titleText = titleText

    -- Info text
    local infoText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    infoText:SetPoint("LEFT", titleText, "RIGHT", 10, 0)
    infoText:SetText("|cFF8B7355(Klicke auf ein Mitglied um Details zu sehen)|r")

    -- Member count
    local countText = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", headerBar, "RIGHT", -100, 0)
    countText:SetText("|cFF8B73550 Mitglieder|r")
    parent.countText = countText

    -- DKP Export button (right side of header)
    local exportBtn = CreateFrame("Button", nil, headerBar, "BackdropTemplate")
    exportBtn:SetSize(80, 24)
    exportBtn:SetPoint("RIGHT", headerBar, "RIGHT", -10, 0)
    exportBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    exportBtn:SetBackdropColor(0.15, 0.3, 0.15, 0.9)
    exportBtn:SetBackdropBorderColor(0.3, 0.6, 0.3, 0.6)
    local expText = exportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    expText:SetPoint("CENTER")
    expText:SetText("|cFF66FF66Export|r")
    exportBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.2, 0.4, 0.2, 1) end)
    exportBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.15, 0.3, 0.15, 0.9) end)
    exportBtn:SetScript("OnClick", function()
        OneGuild:ShowDKPExport()
    end)

    -- Column headers
    local colHeader = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    colHeader:SetHeight(HEADER_HEIGHT)
    colHeader:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -4)
    colHeader:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, -4)
    colHeader:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    colHeader:SetBackdropColor(0.15, 0.08, 0.04, 0.6)

    local headers = {
        { label = "",        x = 4   },
        { label = "Status",  x = 20  },
        { label = "Main",    x = 70  },
        { label = "Klasse",  x = 220 },
        { label = "Level",   x = 310 },
        { label = "DKP",     x = 360 },
        { label = "Eingeloggt als",   x = 420 },
        { label = "Zuletzt gesehen",  x = 560 },
    }

    for _, h in ipairs(headers) do
        local ht = colHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("LEFT", colHeader, "LEFT", h.x, 0)
        ht:SetText("|cFFDDB866" .. h.label .. "|r")
    end

    -- Scroll area
    local scrollParent = CreateFrame("Frame", nil, parent)
    scrollParent:SetPoint("TOPLEFT", colHeader, "BOTTOMLEFT", 0, -2)
    scrollParent:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -6, 8)
    parent.scrollParent = scrollParent

    --------------------------------------------------------------------
    -- Create row pool
    --------------------------------------------------------------------
    for i = 1, MAX_ROW_POOL do
        local row = CreateFrame("Frame", nil, scrollParent, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", 0, -((i - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", scrollParent, "TOPRIGHT", 0, -((i - 1) * ROW_HEIGHT))
        row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row:SetBackdropColor(0.05, 0.025, 0.02, 0.3)
        row:EnableMouse(true)

        ----------------------------------------------------------------
        -- MEMBER elements
        ----------------------------------------------------------------
        row.expandIcon = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.expandIcon:SetPoint("LEFT", row, "LEFT", 6, 0)

        row.statusDot = row:CreateTexture(nil, "ARTWORK")
        row.statusDot:SetSize(10, 10)
        row.statusDot:SetPoint("LEFT", row, "LEFT", 26, 0)
        row.statusDot:SetTexture("Interface\\Buttons\\WHITE8x8")

        row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.statusText:SetPoint("LEFT", row.statusDot, "RIGHT", 4, 0)

        row.mainText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.mainText:SetPoint("LEFT", row, "LEFT", 70, 0)

        row.classText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.classText:SetPoint("LEFT", row, "LEFT", 220, 0)

        row.levelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.levelText:SetPoint("LEFT", row, "LEFT", 310, 0)

        row.dkpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.dkpText:SetPoint("LEFT", row, "LEFT", 360, 0)

        row.senderText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.senderText:SetPoint("LEFT", row, "LEFT", 420, 0)

        row.lastSeenText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.lastSeenText:SetPoint("LEFT", row, "LEFT", 560, 0)

        ----------------------------------------------------------------
        -- ALT elements
        ----------------------------------------------------------------
        row.leftBar = row:CreateTexture(nil, "ARTWORK")
        row.leftBar:SetSize(2, ROW_HEIGHT - 4)
        row.leftBar:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.leftBar:SetColorTexture(0.55, 0.35, 0.1, 0.5)

        row.altTypeIcon = row:CreateTexture(nil, "OVERLAY")
        row.altTypeIcon:SetSize(14, 14)
        row.altTypeIcon:SetPoint("LEFT", row, "LEFT", 28, 0)

        row.altTypeLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.altTypeLabel:SetPoint("LEFT", row, "LEFT", 46, 0)

        row.altNameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.altNameText:SetPoint("LEFT", row, "LEFT", 110, 0)

        row.altRealmText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.altRealmText:SetPoint("LEFT", row, "LEFT", 260, 0)

        row.altClassText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.altClassText:SetPoint("LEFT", row, "LEFT", 370, 0)

        row.altLevelText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.altLevelText:SetPoint("LEFT", row, "LEFT", 460, 0)

        row.altGsText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.altGsText:SetPoint("LEFT", row, "LEFT", 530, 0)

        -- "no chars" text
        row.noCharsText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.noCharsText:SetPoint("LEFT", row, "LEFT", 46, 0)
        row.noCharsText:SetText("|cFF555555Keine Charaktere bekannt|r")

        ----------------------------------------------------------------
        -- DKP EDIT elements (admin only)
        ----------------------------------------------------------------
        row.dkpEditLabel = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.dkpEditLabel:SetPoint("LEFT", row, "LEFT", 28, 0)
        row.dkpEditLabel:SetText("|cFFFFAA33DKP:|r")

        -- Minus 10 button
        row.dkpMinus = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.dkpMinus:SetSize(28, 22)
        row.dkpMinus:SetPoint("LEFT", row, "LEFT", 70, 0)
        row.dkpMinus:RegisterForClicks("AnyUp")
        row.dkpMinus:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.dkpMinus:SetBackdropColor(0.5, 0.1, 0.1, 0.8)
        row.dkpMinus:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.6)
        local minusText = row.dkpMinus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        minusText:SetPoint("CENTER")
        minusText:SetText("|cFFFF6666-10|r")

        -- EditBox
        row.dkpBox = CreateFrame("EditBox", nil, row, "BackdropTemplate")
        row.dkpBox:SetSize(60, 22)
        row.dkpBox:SetPoint("LEFT", row.dkpMinus, "RIGHT", 4, 0)
        row.dkpBox:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        row.dkpBox:SetBackdropColor(0.1, 0.06, 0.04, 1)
        row.dkpBox:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        row.dkpBox:SetFontObject("GameFontHighlight")
        row.dkpBox:SetAutoFocus(false)
        row.dkpBox:SetMaxLetters(8)
        row.dkpBox:SetNumeric(false)
        row.dkpBox:SetTextInsets(4, 4, 0, 0)
        row.dkpBox:SetJustifyH("CENTER")

        -- Plus 10 button
        row.dkpPlus = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.dkpPlus:SetSize(28, 22)
        row.dkpPlus:SetPoint("LEFT", row.dkpBox, "RIGHT", 4, 0)
        row.dkpPlus:RegisterForClicks("AnyUp")
        row.dkpPlus:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.dkpPlus:SetBackdropColor(0.1, 0.4, 0.1, 0.8)
        row.dkpPlus:SetBackdropBorderColor(0.2, 0.6, 0.2, 0.6)
        local plusText = row.dkpPlus:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        plusText:SetPoint("CENTER")
        plusText:SetText("|cFF66FF66+10|r")

        -- Confirm button
        row.dkpConfirm = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.dkpConfirm:SetSize(40, 22)
        row.dkpConfirm:SetPoint("LEFT", row.dkpPlus, "RIGHT", 8, 0)
        row.dkpConfirm:RegisterForClicks("AnyUp")
        row.dkpConfirm:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 6,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.dkpConfirm:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        row.dkpConfirm:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        local confirmText = row.dkpConfirm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        confirmText:SetPoint("CENTER")
        confirmText:SetText("|cFF66FF66OK|r")

        -- DKP current display in edit row
        row.dkpCurrentText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.dkpCurrentText:SetPoint("LEFT", row.dkpConfirm, "RIGHT", 12, 0)

        row:Hide()
        rowPool[i] = row
    end

    -- Scroll with mouse wheel
    scrollParent:EnableMouseWheel(true)
    scrollParent:SetScript("OnMouseWheel", function(_, delta)
        local maxOff = math.max(0, #displayList - MAX_ROW_POOL)
        scrollOffset = math.max(0, math.min(scrollOffset - delta, maxOff))
        OneGuild:UpdateMemberRows()
    end)

    -- Empty text
    local emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    emptyText:SetPoint("CENTER", scrollParent, "CENTER", 0, 0)
    emptyText:SetWidth(400)
    emptyText:SetJustifyH("CENTER")
    emptyText:SetWordWrap(true)
    emptyText:SetText("|cFF8B7355Noch keine Mitglieder mit OneGuild entdeckt.\n\n" ..
        "Mitglieder werden gespeichert sobald sie online waren\n" ..
        "und das Addon installiert haben.\n\n" ..
        "|cFFDDB866Auch offline Mitglieder werden hier angezeigt.|r")
    parent.emptyText = emptyText
end

------------------------------------------------------------------------
-- DKP Export popup (copyable text)
------------------------------------------------------------------------
function OneGuild:ShowDKPExport()
    -- Build export text
    local lines = {}
    table.insert(lines, "OneGuild DKP Export - " .. date("%Y-%m-%d %H:%M:%S"))
    table.insert(lines, "==================================================")
    table.insert(lines, "")

    local members = self:GetAllAddonMembers()
    if members and #members > 0 then
        -- Sort by DKP descending
        table.sort(members, function(a, b)
            return GetDKP(a) > GetDKP(b)
        end)
        for _, m in ipairs(members) do
            local name = m.mainName or m.sender or "?"
            local dkp = GetDKP(m)
            table.insert(lines, name .. "\t" .. tostring(dkp) .. " DKP")
        end
    else
        table.insert(lines, "Keine Mitglieder gefunden.")
    end

    local exportStr = table.concat(lines, "\n")

    -- Create or reuse export frame
    if not self.dkpExportFrame then
        local ef = CreateFrame("Frame", "OneGuildDKPExport", UIParent, "BackdropTemplate")
        ef:SetSize(450, 350)
        ef:SetPoint("CENTER")
        ef:SetFrameStrata("DIALOG")
        ef:SetFrameLevel(200)
        ef:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        ef:SetBackdropColor(0.05, 0.03, 0.02, 0.95)
        ef:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.8)
        ef:SetMovable(true)
        ef:EnableMouse(true)
        ef:RegisterForDrag("LeftButton")
        ef:SetScript("OnDragStart", ef.StartMoving)
        ef:SetScript("OnDragStop", ef.StopMovingOrSizing)

        local title = ef:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", ef, "TOP", 0, -10)
        title:SetText("|cFFFFD700DKP Export|r")

        local hint = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        hint:SetPoint("TOP", title, "BOTTOM", 0, -4)
        hint:SetText("|cFF888888Strg+A zum Markieren, Strg+C zum Kopieren|r")

        -- ScrollFrame + EditBox for copyable text
        local sf = CreateFrame("ScrollFrame", "OneGuildDKPExportScroll", ef, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", ef, "TOPLEFT", 12, -48)
        sf:SetPoint("BOTTOMRIGHT", ef, "BOTTOMRIGHT", -30, 40)

        local editBox = CreateFrame("EditBox", nil, sf)
        editBox:SetMultiLine(true)
        editBox:SetFontObject("GameFontHighlightSmall")
        editBox:SetWidth(sf:GetWidth() or 400)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        sf:SetScrollChild(editBox)

        ef.editBox = editBox

        -- Close button
        local closeBtn = CreateFrame("Button", nil, ef, "BackdropTemplate")
        closeBtn:SetSize(100, 26)
        closeBtn:SetPoint("BOTTOM", ef, "BOTTOM", 0, 8)
        closeBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        closeBtn:SetBackdropColor(0.3, 0.15, 0.05, 0.9)
        closeBtn:SetBackdropBorderColor(0.6, 0.35, 0.1, 0.6)
        local clText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        clText:SetPoint("CENTER")
        clText:SetText("|cFFFFD700Schliessen|r")
        closeBtn:SetScript("OnClick", function() ef:Hide() end)

        ef:Hide()
        self.dkpExportFrame = ef
    end

    local ef = self.dkpExportFrame
    ef.editBox:SetText(exportStr)
    ef.editBox:HighlightText()
    ef:Show()
end

------------------------------------------------------------------------
-- Helper: hide all elements on a row
------------------------------------------------------------------------
local function HideAllElements(row)
    row.expandIcon:Hide()
    row.statusDot:Hide()
    row.statusText:Hide()
    row.mainText:Hide()
    row.classText:Hide()
    row.levelText:Hide()
    row.dkpText:Hide()
    row.senderText:Hide()
    row.lastSeenText:Hide()
    row.leftBar:Hide()
    row.altTypeIcon:Hide()
    row.altTypeLabel:Hide()
    row.altNameText:Hide()
    row.altRealmText:Hide()
    row.altClassText:Hide()
    row.altLevelText:Hide()
    row.altGsText:Hide()
    row.noCharsText:Hide()
    -- dkp edit elements
    row.dkpEditLabel:Hide()
    row.dkpMinus:Hide()
    row.dkpBox:Hide()
    row.dkpBox:ClearFocus()
    row.dkpPlus:Hide()
    row.dkpConfirm:Hide()
    row.dkpCurrentText:Hide()
end

------------------------------------------------------------------------
-- Render a member row
------------------------------------------------------------------------
local function RenderMemberRow(row, member, visualIdx)
    HideAllElements(row)

    if visualIdx % 2 == 0 then
        row:SetBackdropColor(0.08, 0.04, 0.03, 0.4)
    else
        row:SetBackdropColor(0.05, 0.025, 0.02, 0.3)
    end
    row:SetHeight(ROW_HEIGHT)

    -- Expand indicator
    local isExpanded = expandedKeys[member.sender] or false
    row.expandIcon:SetText(isExpanded and "|cFFDDB866-|r" or "|cFFDDB866+|r")
    row.expandIcon:Show()

    -- Status
    if member.online then
        row.statusDot:SetColorTexture(0.2, 0.9, 0.2, 1)
        row.statusText:SetText("|cFF66FF66On|r")
    else
        row.statusDot:SetColorTexture(0.5, 0.5, 0.5, 0.6)
        row.statusText:SetText("|cFF888888Off|r")
    end
    row.statusDot:Show()
    row.statusText:Show()

    -- Main name
    local r, g, b = GetClassColor(member.mainClass)
    local colorHex = string.format("|cFF%02x%02x%02x", r * 255, g * 255, b * 255)

    if member.hasMain and member.mainName then
        row.mainText:SetText(colorHex .. member.mainName .. "|r")
    else
        row.mainText:SetText("|cFF555555Kein Main|r")
    end
    row.mainText:Show()

    -- Class
    if member.mainClassName then
        row.classText:SetText(colorHex .. member.mainClassName .. "|r")
    else
        row.classText:SetText("|cFF555555-|r")
    end
    row.classText:Show()

    -- Level
    if member.mainLevel and member.mainLevel > 0 then
        row.levelText:SetText("|cFFDDB866" .. member.mainLevel .. "|r")
    else
        row.levelText:SetText("|cFF555555-|r")
    end
    row.levelText:Show()

    -- DKP
    local dkp = GetDKP(member)
    local dkpColor
    if dkp > 0 then
        dkpColor = "|cFF66FF66"
    elseif dkp < 0 then
        dkpColor = "|cFFFF4444"
    else
        dkpColor = "|cFF888888"
    end
    row.dkpText:SetText(dkpColor .. tostring(dkp) .. "|r")
    row.dkpText:Show()

    -- Sender
    row.senderText:SetText("|cFF8B7355" .. (member.sender or "?") .. "|r")
    row.senderText:Show()

    -- Last seen
    if member.lastSeen then
        row.lastSeenText:SetText("|cFF8B7355" .. date("%d.%m %H:%M", member.lastSeen) .. "|r")
    else
        row.lastSeenText:SetText("|cFF555555-|r")
    end
    row.lastSeenText:Show()

    -- Hover
    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.12, 0.05, 0.6)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if member.hasMain and member.mainName then
            GameTooltip:AddLine(colorHex .. member.mainName .. "|r", 1, 1, 1)
            if member.mainRealm then
                GameTooltip:AddLine("Realm: " .. member.mainRealm, 0.7, 0.7, 0.7)
            end
            if member.mainClassName then
                GameTooltip:AddLine("Klasse: " .. member.mainClassName, r, g, b)
            end
            if member.mainLevel and member.mainLevel > 0 then
                GameTooltip:AddLine("Level: " .. member.mainLevel, 0.8, 0.7, 0.4)
            end
        else
            GameTooltip:AddLine("|cFF888888Kein Main gesetzt|r", 0.5, 0.5, 0.5)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("DKP: " .. dkpColor .. tostring(dkp) .. "|r", 1, 1, 1)
        GameTooltip:AddLine("Eingeloggt als: " .. (member.sender or "?"), 0.6, 0.6, 0.6)
        GameTooltip:AddLine("Status: " .. (member.online and "|cFF66FF66Online|r" or "|cFF888888Offline|r"), 0.7, 0.7, 0.7)
        GameTooltip:AddLine("Addon v" .. (member.version or "?"), 0.5, 0.5, 0.5)
        local charCount = 0
        if member.characters then
            for _ in pairs(member.characters) do charCount = charCount + 1 end
        end
        GameTooltip:AddLine("Charaktere: " .. charCount, 0.5, 0.5, 0.5)
        if member.lastSeen then
            GameTooltip:AddLine("Zuletzt gesehen: " ..
                date("%d.%m.%Y %H:%M", member.lastSeen), 0.4, 0.4, 0.4)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cFFDDB866Links-Klick zum " ..
            (isExpanded and "Einklappen" or "Aufklappen") .. "|r",
            0.87, 0.72, 0.4)
        GameTooltip:AddLine("|cFF8B7355Rechts-Klick fuer Optionen|r",
            0.55, 0.45, 0.33)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        if visualIdx % 2 == 0 then
            self:SetBackdropColor(0.08, 0.04, 0.03, 0.4)
        else
            self:SetBackdropColor(0.05, 0.025, 0.02, 0.3)
        end
        GameTooltip:Hide()
    end)

    -- Click: left = toggle expansion, right = context menu
    row:SetScript("OnMouseDown", function(self, button)
        if button == "RightButton" then
            GameTooltip:Hide()
            local mName = member.mainName or member.sender or "?"
            local mRealm = member.mainRealm or ""
            ShowMemberContextMenu(self, mName, mRealm)
        else
            if expandedKeys[member.sender] then
                expandedKeys[member.sender] = nil
            else
                expandedKeys[member.sender] = true
            end
            OneGuild:UpdateMemberRows()
        end
    end)
end

------------------------------------------------------------------------
-- Render a DKP edit row (admin only)
------------------------------------------------------------------------
local function RenderDKPEditRow(row, member)
    HideAllElements(row)

    row:SetBackdropColor(0.12, 0.06, 0.02, 0.7)
    row:SetHeight(DKP_ROW_H)

    row.leftBar:Show()

    row.dkpEditLabel:Show()
    row.dkpMinus:Show()
    row.dkpBox:Show()
    row.dkpPlus:Show()
    row.dkpConfirm:Show()
    row.dkpCurrentText:Show()

    local currentDKP = GetDKP(member)
    row.dkpBox:SetText("0")
    row.dkpCurrentText:SetText("|cFF8B7355Aktuell: |r|cFFFFD700" .. tostring(currentDKP) .. " DKP|r")

    -- Minus 10
    row.dkpMinus:SetScript("OnClick", function()
        local val = tonumber(row.dkpBox:GetText()) or 0
        val = val - 10
        row.dkpBox:SetText(tostring(val))
    end)
    local memberDisplayName = member.mainName or member.sender or "?"
    row.dkpMinus:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.6, 0.15, 0.15, 1)
    end)
    row.dkpMinus:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.1, 0.1, 0.8)
    end)

    -- Plus 10
    row.dkpPlus:SetScript("OnClick", function()
        local val = tonumber(row.dkpBox:GetText()) or 0
        val = val + 10
        row.dkpBox:SetText(tostring(val))
    end)
    row.dkpPlus:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.5, 0.15, 1)
    end)
    row.dkpPlus:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.4, 0.1, 0.8)
    end)

    -- Confirm (OK) — ADDS entered amount to current DKP
    row.dkpConfirm:SetScript("OnClick", function()
        local inputVal = tonumber(row.dkpBox:GetText()) or 0
        if inputVal == 0 then return end
        local oldDKP = GetDKP(member)
        local newTotal = oldDKP + inputVal
        SetDKP(member, newTotal)
        row.dkpCurrentText:SetText("|cFF8B7355Aktuell: |r|cFF66FF66" .. tostring(newTotal) .. " DKP|r")
        row.dkpBox:SetText("0")
        local prefix = inputVal >= 0 and "+" or ""
        OneGuild:Print(OneGuild.COLORS.SUCCESS .. prefix .. tostring(inputVal) .. " DKP fuer " .. memberDisplayName .. " (Neu: " .. newTotal .. ")|r")
        -- Record history
        if OneGuild.AddDKPHistory then
            OneGuild:AddDKPHistory(member.sender, inputVal, newTotal, "manual", UnitName("player") or "?")
        end
        -- Refresh to update DKP in the member row too
        C_Timer.After(0.1, function()
            OneGuild:UpdateMemberRows()
        end)
    end)
    row.dkpConfirm:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.55, 0.15, 1)
    end)
    row.dkpConfirm:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
    end)

    -- Enter key confirms
    row.dkpBox:SetScript("OnEnterPressed", function(self)
        row.dkpConfirm:GetScript("OnClick")(row.dkpConfirm)
        self:ClearFocus()
    end)
    row.dkpBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(currentDKP))
        self:ClearFocus()
    end)

    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnMouseDown", nil)
end

------------------------------------------------------------------------
-- Render an alt (character) row
------------------------------------------------------------------------
local function RenderAltRow(row, charData, parentMember)
    HideAllElements(row)

    row:SetBackdropColor(0.06, 0.03, 0.02, 0.55)
    row:SetHeight(ALT_ROW_H)

    row.leftBar:Show()

    if charData.isMain then
        row.altTypeIcon:SetTexture("Interface\\GROUPFRAME\\UI-Group-LeaderIcon")
        row.altTypeIcon:Show()
        row.altTypeLabel:SetText("|cFFFFD700Main|r")
    else
        row.altTypeIcon:Hide()
        row.altTypeLabel:SetText("|cFF8B7355Twink|r")
    end
    row.altTypeLabel:Show()

    local r, g, b = GetClassColor(charData.classFile)
    local colorHex = string.format("|cFF%02x%02x%02x", r * 255, g * 255, b * 255)
    row.altNameText:SetText(colorHex .. (charData.name or "?") .. "|r")
    row.altNameText:Show()

    row.altRealmText:SetText("|cFF8B7355" .. (charData.realm or "?") .. "|r")
    row.altRealmText:Show()

    if charData.className then
        row.altClassText:SetText(colorHex .. charData.className .. "|r")
    else
        row.altClassText:SetText("|cFF555555-|r")
    end
    row.altClassText:Show()

    if charData.level and charData.level > 0 then
        row.altLevelText:SetText("|cFFDDB866Lv " .. charData.level .. "|r")
    else
        row.altLevelText:SetText("|cFF555555-|r")
    end
    row.altLevelText:Show()

    if charData.itemLevel and charData.itemLevel > 0 then
        row.altGsText:SetText("|cFF66BBFF" .. charData.itemLevel .. " GS|r")
    else
        row.altGsText:SetText("|cFF555555-|r")
    end
    row.altGsText:Show()

    row:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.06, 0.04, 0.7)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(colorHex .. (charData.name or "?") .. "|r", 1, 1, 1)
        if charData.realm then
            GameTooltip:AddLine("Realm: " .. charData.realm, 0.7, 0.7, 0.7)
        end
        if charData.className then
            GameTooltip:AddLine("Klasse: " .. charData.className, r, g, b)
        end
        if charData.level and charData.level > 0 then
            GameTooltip:AddLine("Level: " .. charData.level, 0.8, 0.7, 0.4)
        end
        if charData.itemLevel and charData.itemLevel > 0 then
            GameTooltip:AddLine("Gearscore: " .. charData.itemLevel, 0.4, 0.73, 1)
        end
        GameTooltip:AddLine(" ")
        if charData.isMain then
            GameTooltip:AddLine("|cFFFFD700Main-Charakter|r", 1, 0.84, 0)
        else
            GameTooltip:AddLine("|cFF8B7355Twink|r", 0.55, 0.45, 0.33)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.06, 0.03, 0.02, 0.55)
        GameTooltip:Hide()
    end)
    row:SetScript("OnMouseDown", nil)
end

------------------------------------------------------------------------
-- Render a "no characters known" placeholder row
------------------------------------------------------------------------
local function RenderNoCharsRow(row)
    HideAllElements(row)
    row:SetBackdropColor(0.06, 0.03, 0.02, 0.45)
    row:SetHeight(ALT_ROW_H)
    row.leftBar:Show()
    row.noCharsText:Show()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    row:SetScript("OnMouseDown", nil)
end

------------------------------------------------------------------------
-- Update member rows (main refresh function)
------------------------------------------------------------------------
function OneGuild:UpdateMemberRows()
    if not membersParent then return end

    local members = self:GetAllAddonMembers()
    displayList = BuildDisplayList(members)

    local parent = membersParent
    local yOff = 0
    local memberIdx = 0

    for i = 1, MAX_ROW_POOL do
        local row = rowPool[i]
        local idx = i + scrollOffset
        local item = displayList[idx]

        if item then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", parent.scrollParent, "TOPLEFT", 0, -yOff)
            row:SetPoint("TOPRIGHT", parent.scrollParent, "TOPRIGHT", 0, -yOff)

            if item.type == "member" then
                memberIdx = memberIdx + 1
                RenderMemberRow(row, item.data, memberIdx)
                yOff = yOff + ROW_HEIGHT
            elseif item.type == "dkp_edit" then
                RenderDKPEditRow(row, item.data)
                yOff = yOff + DKP_ROW_H
            elseif item.type == "alt" then
                RenderAltRow(row, item.data, item.parent)
                yOff = yOff + ALT_ROW_H
            elseif item.type == "no_chars" then
                RenderNoCharsRow(row)
                yOff = yOff + ALT_ROW_H
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Update count
    if parent.countText then
        local total = #members
        local online = 0
        for _, m in ipairs(members) do
            if m.online then online = online + 1 end
        end
        parent.countText:SetText("|cFF8B7355" .. online .. " online / " .. total .. " gesamt|r")
    end

    -- Show/hide empty text
    if parent.emptyText then
        parent.emptyText:SetShown(#members == 0)
    end
end

------------------------------------------------------------------------
-- Refresh Members
------------------------------------------------------------------------
function OneGuild:RefreshMembers()
    scrollOffset = 0
    self:UpdateMemberRows()
end
