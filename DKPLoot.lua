------------------------------------------------------------------------
-- OneGuild - DKPLoot.lua
-- DKP Loot Auction System
-- Drag & drop items from inventory, broadcast to group, collect bids
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r DKPLoot.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Auction State
------------------------------------------------------------------------
OneGuild.activeAuction = nil  -- { itemLink, itemID, itemName, itemIcon, itemIlvl, itemQuality, auctioneer, startTime, duration, bids = {}, highBid = { player, amount } }
OneGuild.bidWindowFrame = nil
OneGuild.auctionTimerTicker = nil

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function ShortName(name)
    if not name then return "" end
    return name:match("^([^%-]+)") or name
end

local function IsPlayerInMyGroup(name)
    if not IsInGroup() then return false end
    local short = ShortName(name)
    -- Check raid roster
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local rName = GetRaidRosterInfo(i)
            if rName then
                local rs = ShortName(rName)
                if rs == short then return true end
            end
        end
    else
        -- Party check
        for i = 1, GetNumGroupMembers() - 1 do
            local unit = "party" .. i
            local uName = UnitName(unit)
            if uName and ShortName(uName) == short then return true end
        end
        -- Also check self
        local myName = UnitName("player")
        if myName and ShortName(myName) == short then return true end
    end
    return false
end

local function CanStartAuction()
    -- Same permission as DKP editing
    if OneGuild.CanEditDKP then
        return OneGuild:CanEditDKP()
    end
    return false
end

local function FormatTimeLeft(seconds)
    if seconds <= 0 then return "0s" end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    if m > 0 then
        return string.format("%d:%02d", m, s)
    end
    return string.format("%ds", s)
end

------------------------------------------------------------------------
-- Get item quality color
------------------------------------------------------------------------
local function GetQualityColor(quality)
    if not quality then return 1, 1, 1 end
    local colors = {
        [0] = { 0.62, 0.62, 0.62 },  -- Poor (grey)
        [1] = { 1.00, 1.00, 1.00 },  -- Common (white)
        [2] = { 0.12, 1.00, 0.00 },  -- Uncommon (green)
        [3] = { 0.00, 0.44, 0.87 },  -- Rare (blue)
        [4] = { 0.64, 0.21, 0.93 },  -- Epic (purple)
        [5] = { 1.00, 0.50, 0.00 },  -- Legendary (orange)
        [6] = { 0.90, 0.80, 0.50 },  -- Artifact (light gold)
        [7] = { 0.00, 0.80, 1.00 },  -- Heirloom (light blue)
    }
    local c = colors[quality] or { 1, 1, 1 }
    return c[1], c[2], c[3]
end

------------------------------------------------------------------------
-- BuildDKPLootTab  (called from UI.lua)
------------------------------------------------------------------------
function OneGuild:BuildDKPLootTab()
    local parent = self.tabFrames and self.tabFrames[4]  -- "DKP Loot" is tab 4
    if not parent then return end

    -- Title
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", parent, "TOP", 0, -12)
    title:SetText("|cFFFFB800DKP Loot Auktion|r")

    -- "Neue Auktion" Button (permission-checked)
    local newAucBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    newAucBtn:SetSize(160, 32)
    newAucBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -42)
    newAucBtn:RegisterForClicks("AnyUp")
    newAucBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    newAucBtn:SetBackdropColor(0.6, 0.15, 0.05, 0.9)
    newAucBtn:SetBackdropBorderColor(0.9, 0.3, 0.1, 0.8)
    local newAucText = newAucBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    newAucText:SetPoint("CENTER")
    newAucText:SetText("|cFFFFCC00+ Neue Auktion|r")
    newAucBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.8, 0.2, 0.08, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Neue DKP Auktion starten")
        GameTooltip:AddLine("Item aus dem Inventar per Drag & Drop einfuegen.", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    newAucBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.6, 0.15, 0.05, 0.9)
        GameTooltip:Hide()
    end)
    newAucBtn:SetScript("OnClick", function()
        if not CanStartAuction() then
            OneGuild:Print(OneGuild.COLORS.ERROR .. "Keine Berechtigung fuer DKP Auktionen!|r")
            return
        end
        if not IsInGroup() then
            OneGuild:Print(OneGuild.COLORS.ERROR .. "Du musst in einer Gruppe oder einem Raid sein!|r")
            return
        end
        if OneGuild.activeAuction then
            OneGuild:Print(OneGuild.COLORS.WARNING .. "Es laeuft bereits eine Auktion!|r")
            return
        end
        OneGuild:ShowNewAuctionDialog()
    end)

    -- Active Auction Display Area
    local activePanel = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    activePanel:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -82)
    activePanel:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -16, -82)
    activePanel:SetHeight(120)
    activePanel:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    activePanel:SetBackdropColor(0.08, 0.04, 0.04, 0.95)
    activePanel:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
    parent.activePanel = activePanel

    local activeTitleText = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeTitleText:SetPoint("TOPLEFT", activePanel, "TOPLEFT", 12, -10)
    activeTitleText:SetText("|cFF8B7355Aktive Auktion|r")
    activePanel.titleText = activeTitleText

    local noAuctionText = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    noAuctionText:SetPoint("CENTER", activePanel, "CENTER", 0, 0)
    noAuctionText:SetText("|cFF555555Keine aktive Auktion|r")
    activePanel.noAuctionText = noAuctionText

    -- Item icon in active panel
    local activeItemIcon = activePanel:CreateTexture(nil, "ARTWORK")
    activeItemIcon:SetSize(40, 40)
    activeItemIcon:SetPoint("TOPLEFT", activePanel, "TOPLEFT", 14, -30)
    activeItemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    activeItemIcon:Hide()
    activePanel.itemIcon = activeItemIcon

    -- Item icon border (quality colored)
    local activeIconBorder = activePanel:CreateTexture(nil, "OVERLAY")
    activeIconBorder:SetSize(44, 44)
    activeIconBorder:SetPoint("CENTER", activeItemIcon, "CENTER", 0, 0)
    activeIconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    activeIconBorder:SetBlendMode("ADD")
    activeIconBorder:Hide()
    activePanel.iconBorder = activeIconBorder

    local activeItemName = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeItemName:SetPoint("LEFT", activeItemIcon, "RIGHT", 10, 8)
    activeItemName:SetText("")
    activePanel.itemName = activeItemName

    local activeItemIlvl = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeItemIlvl:SetPoint("LEFT", activeItemIcon, "RIGHT", 10, -8)
    activeItemIlvl:SetText("")
    activePanel.itemIlvl = activeItemIlvl

    -- Timer text
    local activeTimer = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    activeTimer:SetPoint("TOPRIGHT", activePanel, "TOPRIGHT", -14, -10)
    activeTimer:SetText("")
    activePanel.timerText = activeTimer

    -- Highest bid display
    local highBidText = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    highBidText:SetPoint("TOPRIGHT", activePanel, "TOPRIGHT", -14, -35)
    highBidText:SetText("")
    activePanel.highBidText = highBidText

    -- Bid list text (scrollable area below item)
    local bidListText = activePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    bidListText:SetPoint("TOPLEFT", activeItemIcon, "BOTTOMLEFT", 0, -6)
    bidListText:SetPoint("RIGHT", activePanel, "RIGHT", -14, 0)
    bidListText:SetJustifyH("LEFT")
    bidListText:SetText("")
    activePanel.bidListText = bidListText

    -- End Auction button (only visible to auctioneer)
    local endAucBtn = CreateFrame("Button", nil, activePanel, "BackdropTemplate")
    endAucBtn:SetSize(130, 26)
    endAucBtn:SetPoint("BOTTOMRIGHT", activePanel, "BOTTOMRIGHT", -10, 8)
    endAucBtn:RegisterForClicks("AnyUp")
    endAucBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    endAucBtn:SetBackdropColor(0.5, 0.1, 0.1, 0.9)
    endAucBtn:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.8)
    local endBtnText = endAucBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    endBtnText:SetPoint("CENTER")
    endBtnText:SetText("|cFFFF6666Auktion beenden|r")
    endAucBtn:SetScript("OnClick", function()
        if OneGuild.activeAuction then
            OneGuild:EndAuction()
        end
    end)
    endAucBtn:Hide()
    activePanel.endBtn = endAucBtn

    -- Cancel Auction button
    local cancelAucBtn = CreateFrame("Button", nil, activePanel, "BackdropTemplate")
    cancelAucBtn:SetSize(130, 26)
    cancelAucBtn:SetPoint("RIGHT", endAucBtn, "LEFT", -6, 0)
    cancelAucBtn:RegisterForClicks("AnyUp")
    cancelAucBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    cancelAucBtn:SetBackdropColor(0.3, 0.3, 0.1, 0.9)
    cancelAucBtn:SetBackdropBorderColor(0.5, 0.5, 0.2, 0.8)
    local cancelBtnText = cancelAucBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelBtnText:SetPoint("CENTER")
    cancelBtnText:SetText("|cFFFFCC00Abbrechen|r")
    cancelAucBtn:SetScript("OnClick", function()
        if OneGuild.activeAuction then
            OneGuild:CancelAuction()
        end
    end)
    cancelAucBtn:Hide()
    activePanel.cancelBtn = cancelAucBtn

    -- Separator line
    local sepLine = parent:CreateTexture(nil, "ARTWORK")
    sepLine:SetColorTexture(0.5, 0.35, 0.1, 0.4)
    sepLine:SetHeight(1)
    sepLine:SetPoint("TOPLEFT", activePanel, "BOTTOMLEFT", 0, -8)
    sepLine:SetPoint("TOPRIGHT", activePanel, "BOTTOMRIGHT", 0, -8)

    -- Auction History Header
    local histHeader = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    histHeader:SetPoint("TOPLEFT", activePanel, "BOTTOMLEFT", 0, -18)
    histHeader:SetText("|cFF8B7355Letzte Auktionen|r")

    -- History Scroll Frame
    local histScroll = CreateFrame("ScrollFrame", "OneGuildAuctionHistScroll", parent, "UIPanelScrollFrameTemplate")
    histScroll:SetPoint("TOPLEFT", activePanel, "BOTTOMLEFT", 0, -36)
    histScroll:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)

    local histContent = CreateFrame("Frame", nil, histScroll)
    histContent:SetSize(1, 1)
    histScroll:SetScrollChild(histContent)
    parent.histScroll = histScroll
    parent.histContent = histContent
    parent.histRows = {}

    -- Store reference for refresh
    self.dkpLootTab = parent
end

------------------------------------------------------------------------
-- Refresh DKP Loot Tab (active auction + history)
------------------------------------------------------------------------
function OneGuild:RefreshDKPLoot()
    local parent = self.dkpLootTab
    if not parent then return end

    local panel = parent.activePanel
    if not panel then return end

    local auction = self.activeAuction

    if auction then
        panel.noAuctionText:Hide()
        panel.itemIcon:SetTexture(auction.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        panel.itemIcon:Show()

        local r, g, b = GetQualityColor(auction.itemQuality)
        panel.iconBorder:SetVertexColor(r, g, b, 0.6)
        panel.iconBorder:Show()

        panel.itemName:SetText((auction.itemLink or auction.itemName or "Unbekannt"))
        panel.itemIlvl:SetText("|cFF8B7355iLvl " .. (auction.itemIlvl or "?") .. "|r")

        -- Timer
        local elapsed = time() - (auction.startTime or time())
        local remaining = math.max(0, (auction.duration or 60) - elapsed)
        if remaining > 0 then
            panel.timerText:SetText("|cFFFFCC00" .. FormatTimeLeft(remaining) .. "|r")
        else
            panel.timerText:SetText("|cFFFF4444Beendet|r")
        end

        -- High bid
        if auction.highBid and auction.highBid.player then
            panel.highBidText:SetText("|cFF66FF66Hoechstgebot: " .. auction.highBid.amount .. " DKP|r\n|cFFAAAAAA" .. ShortName(auction.highBid.player) .. "|r")
        else
            panel.highBidText:SetText("|cFF888888Noch kein Gebot|r")
        end

        -- Bid list
        local bidLines = {}
        if auction.bids then
            -- Sort bids by amount descending
            local sorted = {}
            for player, amount in pairs(auction.bids) do
                table.insert(sorted, { player = player, amount = amount })
            end
            table.sort(sorted, function(a, b) return a.amount > b.amount end)
            for i, entry in ipairs(sorted) do
                if i <= 8 then
                    table.insert(bidLines, "|cFFDDB866" .. ShortName(entry.player) .. "|r: |cFFFFFFFF" .. entry.amount .. " DKP|r")
                end
            end
        end
        panel.bidListText:SetText(table.concat(bidLines, "   "))

        -- Show end/cancel buttons only for auctioneer
        local myName = ShortName(UnitName("player"))
        local auctioneerShort = ShortName(auction.auctioneer or "")
        if myName == auctioneerShort or OneGuild:IsOnWhitelist(myName) then
            panel.endBtn:Show()
            panel.cancelBtn:Show()
        else
            panel.endBtn:Hide()
            panel.cancelBtn:Hide()
        end
    else
        panel.noAuctionText:Show()
        panel.itemIcon:Hide()
        panel.iconBorder:Hide()
        panel.itemName:SetText("")
        panel.itemIlvl:SetText("")
        panel.timerText:SetText("")
        panel.highBidText:SetText("")
        panel.bidListText:SetText("")
        panel.endBtn:Hide()
        panel.cancelBtn:Hide()
    end

    -- Refresh history list
    self:RefreshAuctionHistory()
end

------------------------------------------------------------------------
-- Refresh Auction History
------------------------------------------------------------------------
function OneGuild:RefreshAuctionHistory()
    local parent = self.dkpLootTab
    if not parent or not parent.histContent then return end

    local content = parent.histContent
    -- Clear old rows
    for _, row in ipairs(parent.histRows or {}) do
        row:Hide()
    end
    parent.histRows = {}

    local history = (self.db and self.db.auctionHistory) or {}
    local yOffset = 0
    local rowHeight = 24

    -- Show newest first
    for i = #history, 1, -1 do
        local entry = history[i]
        if entry then
            local row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetSize(content:GetParent():GetWidth() - 20, rowHeight)
            row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -yOffset)
            row:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
            })
            local bgAlpha = ((#history - i) % 2 == 0) and 0.04 or 0.08
            row:SetBackdropColor(0.2, 0.15, 0.05, bgAlpha)

            -- Date
            local dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dateText:SetPoint("LEFT", row, "LEFT", 6, 0)
            dateText:SetWidth(90)
            dateText:SetJustifyH("LEFT")
            local dateStr = entry.timestamp and date("%d.%m. %H:%M", entry.timestamp) or "?"
            dateText:SetText("|cFF8B7355" .. dateStr .. "|r")

            -- Item
            local itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            itemText:SetPoint("LEFT", dateText, "RIGHT", 6, 0)
            itemText:SetWidth(200)
            itemText:SetJustifyH("LEFT")
            itemText:SetText(entry.itemLink or entry.itemName or "?")

            -- Winner
            local winnerText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            winnerText:SetPoint("LEFT", itemText, "RIGHT", 6, 0)
            winnerText:SetWidth(120)
            winnerText:SetJustifyH("LEFT")
            if entry.winner then
                winnerText:SetText("|cFF66FF66" .. ShortName(entry.winner) .. "|r")
            else
                winnerText:SetText("|cFFFF4444Abgebrochen|r")
            end

            -- Amount
            local amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            amountText:SetPoint("LEFT", winnerText, "RIGHT", 6, 0)
            amountText:SetWidth(80)
            amountText:SetJustifyH("RIGHT")
            if entry.winAmount and entry.winAmount > 0 then
                amountText:SetText("|cFFFFCC00" .. entry.winAmount .. " DKP|r")
            else
                amountText:SetText("")
            end

            table.insert(parent.histRows, row)
            yOffset = yOffset + rowHeight
        end
    end

    local totalHeight = math.max(yOffset, 100)
    content:SetSize(content:GetParent():GetWidth() - 20, totalHeight)
end

------------------------------------------------------------------------
-- New Auction Dialog (drag & drop item)
------------------------------------------------------------------------
function OneGuild:ShowNewAuctionDialog()
    if self.newAuctionFrame and self.newAuctionFrame:IsShown() then
        self.newAuctionFrame:Hide()
        return
    end

    if not self.newAuctionFrame then
        local f = CreateFrame("Frame", "OneGuildNewAuction", UIParent, "BackdropTemplate")
        f:SetSize(340, 260)
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.08, 0.04, 0.04, 0.97)
        f:SetBackdropBorderColor(0.8, 0.5, 0.1, 0.9)

        -- Title
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -14)
        title:SetText("|cFFFFAA33Neue DKP Auktion|r")

        -- Close button
        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- Instructions
        local infoText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        infoText:SetPoint("TOP", title, "BOTTOM", 0, -8)
        infoText:SetText("|cFF8B7355Item aus dem Inventar hierher ziehen:|r")

        -- Item drop slot
        local dropSlot = CreateFrame("Button", "OneGuildAuctionDropSlot", f, "BackdropTemplate")
        dropSlot:SetSize(52, 52)
        dropSlot:SetPoint("TOP", infoText, "BOTTOM", 0, -12)
        dropSlot:RegisterForClicks("AnyUp")
        dropSlot:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        dropSlot:SetBackdropColor(0.15, 0.08, 0.04, 1)
        dropSlot:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.8)

        local dropIcon = dropSlot:CreateTexture(nil, "ARTWORK")
        dropIcon:SetSize(40, 40)
        dropIcon:SetPoint("CENTER")
        dropIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        dropIcon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        f.dropIcon = dropIcon

        local dropHint = dropSlot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dropHint:SetPoint("TOP", dropSlot, "BOTTOM", 0, -2)
        dropHint:SetText("|cFF555555Drag & Drop|r")
        f.dropHint = dropHint

        -- Item name display
        local itemNameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemNameText:SetPoint("TOP", dropHint, "BOTTOM", 0, -6)
        itemNameText:SetText("")
        f.itemNameText = itemNameText

        -- Stored item data
        f.selectedItemLink = nil
        f.selectedItemID = nil
        f.selectedItemName = nil
        f.selectedItemIcon = nil
        f.selectedItemIlvl = nil
        f.selectedItemQuality = nil

        -- Drag & Drop handler: receive item from cursor
        dropSlot:SetScript("OnReceiveDrag", function(self)
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                ClearCursor()
                local name, link, quality, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink)
                f.selectedItemLink = link or itemLink
                f.selectedItemID = itemID
                f.selectedItemName = name or "Unbekannt"
                f.selectedItemIcon = texture
                f.selectedItemIlvl = iLevel or 0
                f.selectedItemQuality = quality or 1
                dropIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                f.dropHint:SetText("")
                f.itemNameText:SetText(link or itemLink)
            end
        end)

        -- Also handle click when cursor has an item
        dropSlot:SetScript("OnClick", function(self, button)
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" and itemLink then
                ClearCursor()
                local name, link, quality, iLevel, _, _, _, _, _, texture = GetItemInfo(itemLink)
                f.selectedItemLink = link or itemLink
                f.selectedItemID = itemID
                f.selectedItemName = name or "Unbekannt"
                f.selectedItemIcon = texture
                f.selectedItemIlvl = iLevel or 0
                f.selectedItemQuality = quality or 1
                dropIcon:SetTexture(texture or "Interface\\Icons\\INV_Misc_QuestionMark")
                f.dropHint:SetText("")
                f.itemNameText:SetText(link or itemLink)
            end
        end)

        -- Duration dropdown label
        local durLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 40, -180)
        durLabel:SetText("|cFF8B7355Dauer:|r")

        -- Duration buttons (30s, 60s, 120s)
        local durations = { { 30, "30s" }, { 60, "60s" }, { 120, "2min" } }
        f.selectedDuration = 60
        f.durationBtns = {}

        for idx, dur in ipairs(durations) do
            local dBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
            dBtn:SetSize(55, 24)
            if idx == 1 then
                dBtn:SetPoint("LEFT", durLabel, "RIGHT", 10, 0)
            else
                dBtn:SetPoint("LEFT", f.durationBtns[idx - 1], "RIGHT", 4, 0)
            end
            dBtn:RegisterForClicks("AnyUp")
            dBtn:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets   = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            local dBtnText = dBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            dBtnText:SetPoint("CENTER")
            dBtnText:SetText(dur[2])
            dBtn.text = dBtnText

            -- Default selection: 60s
            if dur[1] == 60 then
                dBtn:SetBackdropColor(0.4, 0.25, 0.05, 0.9)
                dBtn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
                dBtnText:SetTextColor(1, 0.85, 0.3)
            else
                dBtn:SetBackdropColor(0.12, 0.06, 0.04, 0.8)
                dBtn:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.5)
                dBtnText:SetTextColor(0.6, 0.5, 0.3)
            end

            dBtn:SetScript("OnClick", function()
                f.selectedDuration = dur[1]
                -- Update visuals
                for _, b in ipairs(f.durationBtns) do
                    b:SetBackdropColor(0.12, 0.06, 0.04, 0.8)
                    b:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.5)
                    b.text:SetTextColor(0.6, 0.5, 0.3)
                end
                dBtn:SetBackdropColor(0.4, 0.25, 0.05, 0.9)
                dBtn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
                dBtnText:SetTextColor(1, 0.85, 0.3)
            end)

            f.durationBtns[idx] = dBtn
        end

        -- Start button
        local startBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        startBtn:SetSize(160, 30)
        startBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 16)
        startBtn:RegisterForClicks("AnyUp")
        startBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        startBtn:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        startBtn:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        local startBtnText = startBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        startBtnText:SetPoint("CENTER")
        startBtnText:SetText("|cFF66FF66Auktion starten!|r")
        startBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.55, 0.15, 1)
        end)
        startBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        end)
        startBtn:SetScript("OnClick", function()
            if not f.selectedItemLink then
                OneGuild:Print(OneGuild.COLORS.ERROR .. "Kein Item ausgewaehlt! Ziehe ein Item auf den Slot.|r")
                return
            end
            OneGuild:StartAuction(f.selectedItemLink, f.selectedItemID, f.selectedItemName,
                f.selectedItemIcon, f.selectedItemIlvl, f.selectedItemQuality, f.selectedDuration)
            f:Hide()
        end)

        self.newAuctionFrame = f
    end

    -- Reset state on show
    local f = self.newAuctionFrame
    f.selectedItemLink = nil
    f.selectedItemID = nil
    f.selectedItemName = nil
    f.selectedItemIcon = nil
    f.selectedItemIlvl = nil
    f.selectedItemQuality = nil
    f.dropIcon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    f.dropHint:SetText("|cFF555555Drag & Drop|r")
    f.itemNameText:SetText("")
    f.selectedDuration = 60
    -- Reset duration buttons visual
    if f.durationBtns then
        for idx, btn in ipairs(f.durationBtns) do
            if idx == 2 then  -- 60s is default
                btn:SetBackdropColor(0.4, 0.25, 0.05, 0.9)
                btn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
                btn.text:SetTextColor(1, 0.85, 0.3)
            else
                btn:SetBackdropColor(0.12, 0.06, 0.04, 0.8)
                btn:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.5)
                btn.text:SetTextColor(0.6, 0.5, 0.3)
            end
        end
    end

    f:Show()
end

------------------------------------------------------------------------
-- Start Auction (local + broadcast)
------------------------------------------------------------------------
function OneGuild:StartAuction(itemLink, itemID, itemName, itemIcon, itemIlvl, itemQuality, duration)
    if self.activeAuction then
        self:Print(self.COLORS.WARNING .. "Es laeuft bereits eine Auktion!|r")
        return
    end

    local myName = UnitName("player")
    local myRealm = GetNormalizedRealmName() or GetRealmName() or ""
    local myFull = myName .. "-" .. myRealm

    self.activeAuction = {
        itemLink    = itemLink,
        itemID      = itemID or 0,
        itemName    = itemName or "Unbekannt",
        itemIcon    = itemIcon or "",
        itemIlvl    = itemIlvl or 0,
        itemQuality = itemQuality or 1,
        auctioneer  = myFull,
        startTime   = time(),
        duration    = duration or 60,
        bids        = {},
        highBid     = nil,
    }

    -- Broadcast auction start to guild
    -- Format: itemID~itemName~itemIcon~itemIlvl~itemQuality~duration~itemLink
    local payload = table.concat({
        tostring(itemID or 0),
        itemName or "?",
        tostring(itemIcon or ""),
        tostring(itemIlvl or 0),
        tostring(itemQuality or 1),
        tostring(duration or 60),
        itemLink or "",
    }, "~")
    self:SendAuctionMessage("ACS", payload)

    -- Play alert sound locally too
    self:PlayAuctionAlert()

    -- Start timer
    self:StartAuctionTimer()

    -- Refresh tab
    self:RefreshDKPLoot()

    self:Print(self.COLORS.SUCCESS .. "Auktion gestartet fuer: " .. (itemLink or itemName) .. " (" .. duration .. "s)|r")
end

------------------------------------------------------------------------
-- Auction Timer
------------------------------------------------------------------------
function OneGuild:StartAuctionTimer()
    -- Cancel existing timer
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end

    self.auctionTimerTicker = C_Timer.NewTicker(1, function()
        if not OneGuild.activeAuction then
            if OneGuild.auctionTimerTicker then
                OneGuild.auctionTimerTicker:Cancel()
                OneGuild.auctionTimerTicker = nil
            end
            return
        end

        local elapsed = time() - (OneGuild.activeAuction.startTime or time())
        local remaining = math.max(0, (OneGuild.activeAuction.duration or 60) - elapsed)

        -- Update timer display in tab
        if OneGuild.dkpLootTab and OneGuild.dkpLootTab.activePanel and OneGuild.dkpLootTab.activePanel.timerText then
            if remaining > 0 then
                local color = remaining <= 10 and "|cFFFF4444" or "|cFFFFCC00"
                OneGuild.dkpLootTab.activePanel.timerText:SetText(color .. FormatTimeLeft(remaining) .. "|r")
            else
                OneGuild.dkpLootTab.activePanel.timerText:SetText("|cFFFF4444Beendet|r")
            end
        end

        -- Update bid window timer
        if OneGuild.bidWindowFrame and OneGuild.bidWindowFrame:IsShown() and OneGuild.bidWindowFrame.timerText then
            if remaining > 0 then
                local color = remaining <= 10 and "|cFFFF4444" or "|cFFFFCC00"
                OneGuild.bidWindowFrame.timerText:SetText(color .. FormatTimeLeft(remaining) .. "|r")
            else
                OneGuild.bidWindowFrame.timerText:SetText("|cFFFF4444Beendet|r")
            end
        end

        -- Auto-end when time runs out (only auctioneer ends it)
        if remaining <= 0 then
            local myName = ShortName(UnitName("player"))
            local auctioneerShort = ShortName(OneGuild.activeAuction.auctioneer or "")
            if myName == auctioneerShort then
                OneGuild:EndAuction()
            end
            if OneGuild.auctionTimerTicker then
                OneGuild.auctionTimerTicker:Cancel()
                OneGuild.auctionTimerTicker = nil
            end
        end
    end)
end

------------------------------------------------------------------------
-- Place a Bid
------------------------------------------------------------------------
function OneGuild:PlaceBid(amount)
    if not self.activeAuction then
        self:Print(self.COLORS.ERROR .. "Keine aktive Auktion!|r")
        return
    end

    amount = tonumber(amount) or 0
    if amount <= 0 then
        self:Print(self.COLORS.ERROR .. "Ungueltige DKP Menge!|r")
        return
    end

    -- Check if player has enough DKP
    local myName = UnitName("player")
    local myDKP = self:GetDKPForPlayer(myName)
    if amount > myDKP then
        self:Print(self.COLORS.ERROR .. "Nicht genug DKP! Du hast " .. myDKP .. " DKP.|r")
        return
    end

    -- Check minimum bid (must be higher than current high bid)
    if self.activeAuction.highBid and amount <= self.activeAuction.highBid.amount then
        self:Print(self.COLORS.WARNING .. "Gebot muss hoeher als " .. self.activeAuction.highBid.amount .. " DKP sein!|r")
        return
    end

    -- Send bid via comm (RAID/PARTY channel for reliability)
    self:SendAuctionMessage("ACB", tostring(amount))

    -- Also record locally
    local myFull = myName .. "-" .. (GetNormalizedRealmName() or GetRealmName() or "")
    self:RecordBid(myFull, amount)

    self:Print(self.COLORS.SUCCESS .. "Gebot abgegeben: " .. amount .. " DKP|r")
end

------------------------------------------------------------------------
-- Record a bid (from local or comm)
------------------------------------------------------------------------
function OneGuild:RecordBid(player, amount)
    if not self.activeAuction then return end

    amount = tonumber(amount) or 0
    if amount <= 0 then return end

    self.activeAuction.bids[player] = amount

    -- Update high bid
    if not self.activeAuction.highBid or amount > self.activeAuction.highBid.amount then
        self.activeAuction.highBid = { player = player, amount = amount }
    end

    -- Refresh displays
    self:RefreshDKPLoot()
    self:UpdateBidWindow()
end

------------------------------------------------------------------------
-- End Auction (declare winner)
------------------------------------------------------------------------
function OneGuild:EndAuction()
    if not self.activeAuction then return end

    local auction = self.activeAuction
    local winner = nil
    local winAmount = 0

    if auction.highBid and auction.highBid.player then
        winner = auction.highBid.player
        winAmount = auction.highBid.amount

        -- Deduct DKP from winner (SendDKPUpdate stores locally + triple-sends)
        local currentDKP = self:GetDKPForPlayer(winner)
        local newDKP = currentDKP - winAmount

        -- Broadcast DKP update (triple-send for reliability)
        if self.SendDKPUpdate then
            self:SendDKPUpdate(winner, newDKP)
        else
            self:SetDKPForPlayer(winner, newDKP)
        end

        -- Add to DKP history
        if self.AddDKPHistory then
            self:AddDKPHistory(ShortName(winner), -winAmount, newDKP, "DKP Auktion", ShortName(auction.auctioneer or "System"))
        end

        self:Print(self.COLORS.SUCCESS .. "Auktion beendet! Gewinner: " .. ShortName(winner) .. " mit " .. winAmount .. " DKP fuer " .. (auction.itemLink or auction.itemName) .. "|r")
    else
        self:Print(self.COLORS.WARNING .. "Auktion beendet ohne Gebote.|r")
    end

    -- Save to auction history
    if not self.db.auctionHistory then self.db.auctionHistory = {} end
    table.insert(self.db.auctionHistory, {
        itemLink   = auction.itemLink,
        itemName   = auction.itemName,
        itemIcon   = auction.itemIcon,
        itemIlvl   = auction.itemIlvl,
        auctioneer = auction.auctioneer,
        winner     = winner,
        winAmount  = winAmount,
        timestamp  = time(),
    })
    -- Keep max 100 entries
    while #self.db.auctionHistory > 100 do
        table.remove(self.db.auctionHistory, 1)
    end

    -- Broadcast auction end
    local endPayload = table.concat({
        winner and ShortName(winner) or "NONE",
        tostring(winAmount),
        auction.itemName or "?",
        auction.itemLink or "",
    }, "~")
    self:SendAuctionMessage("ACE", endPayload)

    -- Clean up
    self.activeAuction = nil
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end

    -- Hide bid window
    if self.bidWindowFrame and self.bidWindowFrame:IsShown() then
        self.bidWindowFrame:Hide()
    end

    self:RefreshDKPLoot()
end

------------------------------------------------------------------------
-- Cancel Auction
------------------------------------------------------------------------
function OneGuild:CancelAuction()
    if not self.activeAuction then return end

    self:Print(self.COLORS.WARNING .. "Auktion abgebrochen fuer: " .. (self.activeAuction.itemLink or self.activeAuction.itemName or "?") .. "|r")

    -- Save as cancelled in history
    if not self.db.auctionHistory then self.db.auctionHistory = {} end
    table.insert(self.db.auctionHistory, {
        itemLink   = self.activeAuction.itemLink,
        itemName   = self.activeAuction.itemName,
        itemIcon   = self.activeAuction.itemIcon,
        itemIlvl   = self.activeAuction.itemIlvl,
        auctioneer = self.activeAuction.auctioneer,
        winner     = nil,
        winAmount  = 0,
        timestamp  = time(),
    })

    -- Broadcast cancel FIRST, while activeAuction still has data
    self:SendAuctionMessage("ACC", "CANCEL")

    -- Clean up
    self.activeAuction = nil
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end

    -- Hide bid window
    if self.bidWindowFrame then
        self.bidWindowFrame:Hide()
    end

    self:RefreshDKPLoot()
end

------------------------------------------------------------------------
-- Play Auction Alert Sound (RareScanner-like)
------------------------------------------------------------------------
function OneGuild:PlayAuctionAlert()
    -- Play the vignette/rare-mob alert sound (3 times for emphasis)
    if SOUNDKIT and SOUNDKIT.UI_RARE_LOOT_TOAST then
        PlaySound(SOUNDKIT.UI_RARE_LOOT_TOAST, "Master")
    else
        -- Fallback: raid warning sound
        PlaySound(8959, "Master")
    end
end

------------------------------------------------------------------------
-- Show Bid Window (left side of screen, for all group members)
------------------------------------------------------------------------
function OneGuild:ShowBidWindow()
    if not self.activeAuction then return end
    local auction = self.activeAuction

    -- Don't show bid window for the auctioneer (they use the tab)
    local myName = ShortName(UnitName("player"))
    local auctioneerShort = ShortName(auction.auctioneer or "")
    -- Actually, show it for everyone including the auctioneer
    -- (auctioneer can also bid if they want)

    if self.bidWindowFrame then
        self.bidWindowFrame:Hide()
    end

    local f = self.bidWindowFrame
    if not f then
        f = CreateFrame("Frame", "OneGuildBidWindow", UIParent, "BackdropTemplate")
        f:SetSize(240, 220)
        f:SetPoint("LEFT", UIParent, "LEFT", 20, 0)
        f:SetFrameStrata("HIGH")
        f:SetFrameLevel(150)
        f:SetMovable(true)
        f:EnableMouse(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.03, 0.02, 0.97)
        f:SetBackdropBorderColor(0.8, 0.5, 0.1, 0.9)

        -- Title
        local bidTitle = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        bidTitle:SetPoint("TOP", f, "TOP", 0, -10)
        bidTitle:SetText("|cFFFFAA33DKP Auktion|r")
        f.titleText = bidTitle

        -- Timer
        local timerText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        timerText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -12)
        f.timerText = timerText

        -- Close button
        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(16, 16)
        closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() f:Hide() end)

        -- Item icon
        local itemIcon = f:CreateTexture(nil, "ARTWORK")
        itemIcon:SetSize(40, 40)
        itemIcon:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -34)
        itemIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.itemIcon = itemIcon

        -- Item icon border
        local iconBorder = f:CreateTexture(nil, "OVERLAY")
        iconBorder:SetSize(44, 44)
        iconBorder:SetPoint("CENTER", itemIcon, "CENTER", 0, 0)
        iconBorder:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        iconBorder:SetBlendMode("ADD")
        f.iconBorder = iconBorder

        -- Item name
        local itemName = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemName:SetPoint("LEFT", itemIcon, "RIGHT", 10, 6)
        itemName:SetPoint("RIGHT", f, "RIGHT", -10, 0)
        itemName:SetJustifyH("LEFT")
        itemName:SetWordWrap(true)
        f.itemNameText = itemName

        -- Item ilvl
        local itemIlvl = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemIlvl:SetPoint("LEFT", itemIcon, "RIGHT", 10, -10)
        f.itemIlvl = itemIlvl

        -- Auctioneer
        local aucText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        aucText:SetPoint("TOPLEFT", itemIcon, "BOTTOMLEFT", 0, -8)
        f.aucText = aucText

        -- High bid display
        local highBid = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        highBid:SetPoint("TOPLEFT", aucText, "BOTTOMLEFT", 0, -8)
        highBid:SetPoint("RIGHT", f, "RIGHT", -10, 0)
        highBid:SetJustifyH("LEFT")
        f.highBidText = highBid

        -- Your DKP display
        local myDKPText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        myDKPText:SetPoint("TOPLEFT", highBid, "BOTTOMLEFT", 0, -6)
        f.myDKPText = myDKPText

        -- Bid input
        local bidInput = CreateFrame("EditBox", "OneGuildBidInput", f, "BackdropTemplate")
        bidInput:SetSize(100, 28)
        bidInput:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 14)
        bidInput:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        bidInput:SetBackdropColor(0.12, 0.06, 0.04, 1)
        bidInput:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        bidInput:SetFontObject("GameFontHighlight")
        bidInput:SetAutoFocus(false)
        bidInput:SetMaxLetters(6)
        bidInput:SetTextInsets(6, 6, 0, 0)
        bidInput:SetNumeric(true)
        bidInput:EnableMouse(true)
        bidInput:EnableKeyboard(true)
        bidInput:SetScript("OnMouseDown", function(self) self:SetFocus() end)
        f.bidInput = bidInput

        local dkpLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dkpLabel:SetPoint("LEFT", bidInput, "RIGHT", 4, 0)
        dkpLabel:SetText("|cFF8B7355DKP|r")

        -- Bid button
        local bidBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        bidBtn:SetSize(80, 28)
        bidBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 14)
        bidBtn:RegisterForClicks("AnyUp")
        bidBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        bidBtn:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        bidBtn:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        local bidBtnText = bidBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        bidBtnText:SetPoint("CENTER")
        bidBtnText:SetText("|cFF66FF66Bieten|r")
        bidBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.15, 0.55, 0.15, 1)
        end)
        bidBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        end)
        bidBtn:SetScript("OnClick", function()
            local amount = tonumber(f.bidInput:GetText() or "")
            if amount then
                OneGuild:PlaceBid(amount)
                f.bidInput:SetText("")
                f.bidInput:ClearFocus()
            else
                OneGuild:Print(OneGuild.COLORS.ERROR .. "Bitte eine gueltige Zahl eingeben!|r")
            end
        end)
        f.bidBtn = bidBtn

        -- Enter to bid
        bidInput:SetScript("OnEnterPressed", function()
            bidBtn:GetScript("OnClick")(bidBtn)
        end)
        bidInput:SetScript("OnEscapePressed", function(self)
            self:ClearFocus()
        end)

        self.bidWindowFrame = f
    end

    -- Populate with current auction data
    f.itemIcon:SetTexture(auction.itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
    local r, g, b = GetQualityColor(auction.itemQuality)
    f.iconBorder:SetVertexColor(r, g, b, 0.6)
    f.itemNameText:SetText(auction.itemLink or auction.itemName or "?")
    f.itemIlvl:SetText("|cFF8B7355iLvl " .. (auction.itemIlvl or "?") .. "|r")
    f.aucText:SetText("|cFF8B7355von: " .. ShortName(auction.auctioneer or "?") .. "|r")

    -- Show your DKP
    local myDKP = self:GetDKPForPlayer(UnitName("player"))
    f.myDKPText:SetText("|cFFDDB866Deine DKP: " .. myDKP .. "|r")

    -- Reset bid input
    f.bidInput:SetText("")

    self:UpdateBidWindow()

    f:Show()
end

------------------------------------------------------------------------
-- Update Bid Window display
------------------------------------------------------------------------
function OneGuild:UpdateBidWindow()
    local f = self.bidWindowFrame
    if not f or not f:IsShown() then return end
    if not self.activeAuction then
        f:Hide()
        return
    end

    local auction = self.activeAuction

    if auction.highBid and auction.highBid.player then
        f.highBidText:SetText("|cFF66FF66Hoechstgebot: " .. auction.highBid.amount .. " DKP\n|cFFAAAAAA" .. ShortName(auction.highBid.player) .. "|r")
    else
        f.highBidText:SetText("|cFF888888Noch kein Gebot|r")
    end

    -- Timer update is handled by the ticker
end

------------------------------------------------------------------------
-- Process incoming auction messages (called from Comm.lua)
------------------------------------------------------------------------
function OneGuild:ProcessAuctionStart(sender, data)
    if not data then return end

    local itemID, itemName, itemIcon, itemIlvl, itemQuality, duration, itemLink =
        strsplit("~", data, 7)

    -- No group-member check needed: auction msgs are sent via RAID/PARTY channel
    -- so only group members receive them

    -- Clean up any stale previous auction
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end
    self.activeAuction = nil

    self.activeAuction = {
        itemLink    = itemLink or "",
        itemID      = tonumber(itemID) or 0,
        itemName    = itemName or "Unbekannt",
        itemIcon    = tonumber(itemIcon) or itemIcon or "",
        itemIlvl    = tonumber(itemIlvl) or 0,
        itemQuality = tonumber(itemQuality) or 1,
        auctioneer  = sender,
        startTime   = time(),
        duration    = tonumber(duration) or 60,
        bids        = {},
        highBid     = nil,
    }

    -- Play alert sound!
    self:PlayAuctionAlert()

    -- Start local timer
    self:StartAuctionTimer()

    -- Show bid window
    C_Timer.After(0.1, function()
        OneGuild:ShowBidWindow()
    end)

    -- Refresh tab if visible
    self:RefreshDKPLoot()

    self:Print(self.COLORS.TITLE .. "DKP Auktion gestartet von " .. ShortName(sender) .. ": " .. (itemLink or itemName or "?") .. "|r")
end

function OneGuild:ProcessAuctionBid(sender, data)
    if not data or not self.activeAuction then return end

    local amount = tonumber(data)
    if not amount or amount <= 0 then return end

    self:RecordBid(sender, amount)

    if ShortName(sender) ~= ShortName(UnitName("player")) then
        self:Print(self.COLORS.INFO .. ShortName(sender) .. " bietet " .. amount .. " DKP|r")
    end
end

function OneGuild:ProcessAuctionEnd(sender, data)
    if not data then return end

    local winner, winAmount, itemName, itemLink = strsplit("~", data, 4)
    winAmount = tonumber(winAmount) or 0

    if winner and winner ~= "NONE" then
        self:Print(self.COLORS.SUCCESS .. "Auktion beendet! Gewinner: " .. winner .. " mit " .. winAmount .. " DKP fuer " .. (itemLink or itemName or "?") .. "|r")
    else
        self:Print(self.COLORS.WARNING .. "Auktion beendet ohne Gebote fuer " .. (itemLink or itemName or "?") .. "|r")
    end

    -- Save to local history
    if self.activeAuction and self.db then
        if not self.db.auctionHistory then self.db.auctionHistory = {} end
        table.insert(self.db.auctionHistory, {
            itemLink   = itemLink or (self.activeAuction and self.activeAuction.itemLink),
            itemName   = itemName or (self.activeAuction and self.activeAuction.itemName),
            itemIcon   = self.activeAuction and self.activeAuction.itemIcon,
            itemIlvl   = self.activeAuction and self.activeAuction.itemIlvl,
            auctioneer = sender,
            winner     = (winner ~= "NONE") and winner or nil,
            winAmount  = winAmount,
            timestamp  = time(),
        })
        while #self.db.auctionHistory > 100 do
            table.remove(self.db.auctionHistory, 1)
        end
    end

    -- Clean up
    self.activeAuction = nil
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end

    -- Hide bid window robustly
    if self.bidWindowFrame then
        self.bidWindowFrame:Hide()
    end
    C_Timer.After(0.15, function()
        if OneGuild.bidWindowFrame and OneGuild.bidWindowFrame:IsShown() then
            OneGuild.bidWindowFrame:Hide()
        end
    end)

    self:RefreshDKPLoot()
end

function OneGuild:ProcessAuctionCancel(sender, data)
    self:Print((self.COLORS and self.COLORS.WARNING or "|cFFFFCC00") .. "Auktion abgebrochen von " .. ShortName(sender) .. "|r")

    -- Clean up auction state FIRST
    self.activeAuction = nil
    if self.auctionTimerTicker then
        self.auctionTimerTicker:Cancel()
        self.auctionTimerTicker = nil
    end

    -- Force hide bid window immediately + with fallback timers
    local function HideBidWindow()
        if OneGuild.bidWindowFrame then
            OneGuild.bidWindowFrame:Hide()
            OneGuild.bidWindowFrame:SetAlpha(0)
        end
    end

    HideBidWindow()
    C_Timer.After(0.05, HideBidWindow)
    C_Timer.After(0.2, function()
        HideBidWindow()
        if OneGuild.bidWindowFrame then
            OneGuild.bidWindowFrame:SetAlpha(1) -- restore for next auction
        end
    end)

    -- Also close new auction dialog if open
    if self.newAuctionFrame and self.newAuctionFrame:IsShown() then
        self.newAuctionFrame:Hide()
    end

    self:RefreshDKPLoot()
    C_Timer.After(0.3, function()
        OneGuild:RefreshDKPLoot()
    end)
end
