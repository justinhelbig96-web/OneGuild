------------------------------------------------------------------------
-- OneGuild - Shop.lua
-- Intern Shop: Guild members can list items for sale
-- Synced via addon messages to all online members
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Shop.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local ROW_HEIGHT = 52
local MAX_ROWS   = 20

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local shopRows = {}
local addListingFrame = nil

------------------------------------------------------------------------
-- Utility
------------------------------------------------------------------------
local function ShortName(fullName)
    if not fullName then return "?" end
    local short = strsplit("-", fullName)
    return short
end

------------------------------------------------------------------------
-- Build Shop Tab
------------------------------------------------------------------------
function OneGuild:BuildShopTab()
    local parent = self.tabFrames[7]
    if not parent then return end

    -- Header
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -10)
    header:SetText("|cFF88DDFFGilden-Shop|r  |cFF666666Kaufe & verkaufe Items an Gildenmitglieder|r")

    -- Add Listing button
    local addBtn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    addBtn:SetSize(130, 24)
    addBtn:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -8)
    addBtn:RegisterForClicks("AnyUp")
    addBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    addBtn:SetBackdropColor(0.05, 0.25, 0.15, 0.9)
    addBtn:SetBackdropBorderColor(0.1, 0.6, 0.3, 0.7)
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtnText:SetPoint("CENTER")
    addBtnText:SetText("|cFF66FF66+ Angebot erstellen|r")
    addBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.08, 0.35, 0.2, 1) end)
    addBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.05, 0.25, 0.15, 0.9) end)
    addBtn:SetScript("OnClick", function()
        OneGuild:ShowAddListingDialog()
    end)

    -- Listing count
    local countText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("RIGHT", addBtn, "LEFT", -10, 0)
    countText:SetTextColor(0.5, 0.5, 0.5)
    parent.shopCountText = countText

    -- Column headers
    local headerBar = CreateFrame("Frame", nil, parent)
    headerBar:SetHeight(18)
    headerBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -36)
    headerBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -12, -36)

    local hItem = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hItem:SetPoint("LEFT", headerBar, "LEFT", 0, 0)
    hItem:SetText("|cFFDDB866Item|r")
    local hPrice = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hPrice:SetPoint("LEFT", headerBar, "LEFT", 320, 0)
    hPrice:SetText("|cFFDDB866Preis|r")
    local hSeller = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hSeller:SetPoint("LEFT", headerBar, "LEFT", 430, 0)
    hSeller:SetText("|cFFDDB866Verkaeufer|r")
    local hTime = headerBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hTime:SetPoint("LEFT", headerBar, "LEFT", 550, 0)
    hTime:SetText("|cFFDDB866Zeit|r")

    -- Separator
    local sep = parent:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(0.3, 0.3, 0.4, 0.3)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -2)
    sep:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, -2)

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", "OneGuildShopScroll", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", sep, "BOTTOMLEFT", 0, -4)
    scrollFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -28, 8)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(scrollFrame:GetWidth() or 700)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    parent.shopScrollChild = scrollChild
    parent.shopScrollFrame = scrollFrame

    -- Empty state
    parent.emptyShopText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    parent.emptyShopText:SetPoint("CENTER", scrollFrame, "CENTER", 0, 0)
    parent.emptyShopText:SetText("|cFF666666Keine Angebote vorhanden.\nErstelle ein Angebot mit dem Button oben rechts.|r")
    parent.emptyShopText:SetJustifyH("CENTER")
    parent.emptyShopText:Hide()

    -- Pre-create rows
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -((i - 1) * (ROW_HEIGHT + 2)))
        row:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", 0, -((i - 1) * (ROW_HEIGHT + 2)))
        row:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.06, 0.06, 0.1, 0.7)
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.4)

        -- Item icon
        row.itemIcon = row:CreateTexture(nil, "ARTWORK")
        row.itemIcon:SetSize(32, 32)
        row.itemIcon:SetPoint("LEFT", row, "LEFT", 8, 0)
        row.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

        -- Item name
        row.itemText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.itemText:SetPoint("LEFT", row.itemIcon, "RIGHT", 8, 6)
        row.itemText:SetWidth(250)
        row.itemText:SetJustifyH("LEFT")

        -- Item note
        row.noteText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.noteText:SetPoint("LEFT", row.itemIcon, "RIGHT", 8, -8)
        row.noteText:SetWidth(250)
        row.noteText:SetJustifyH("LEFT")
        row.noteText:SetTextColor(0.5, 0.5, 0.5)

        -- Price
        row.priceText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.priceText:SetPoint("LEFT", row, "LEFT", 320, 0)
        row.priceText:SetWidth(100)
        row.priceText:SetJustifyH("LEFT")

        -- Seller
        row.sellerText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.sellerText:SetPoint("LEFT", row, "LEFT", 430, 0)
        row.sellerText:SetWidth(110)
        row.sellerText:SetJustifyH("LEFT")

        -- Time remaining
        row.timeText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.timeText:SetPoint("LEFT", row, "LEFT", 550, 0)
        row.timeText:SetWidth(70)
        row.timeText:SetJustifyH("LEFT")

        -- Buy / Whisper button
        row.buyBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.buyBtn:SetSize(70, 22)
        row.buyBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.buyBtn:RegisterForClicks("AnyUp")
        row.buyBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row.buyBtn:SetBackdropColor(0.1, 0.3, 0.5, 0.9)
        row.buyBtn:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.7)
        local buyText = row.buyBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        buyText:SetPoint("CENTER")
        buyText:SetText("|cFF88DDFFAnfragen|r")
        row.buyBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.15, 0.4, 0.6, 1) end)
        row.buyBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1, 0.3, 0.5, 0.9) end)

        -- Delete button (only own listings)
        row.deleteBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.deleteBtn:SetSize(18, 18)
        row.deleteBtn:SetPoint("TOPRIGHT", row, "TOPRIGHT", -6, -4)
        row.deleteBtn:RegisterForClicks("AnyUp")
        row.deleteBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        row.deleteBtn:SetBackdropColor(0.4, 0, 0, 0.5)
        local delT = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delT:SetPoint("CENTER")
        delT:SetText("|cFFFF6666x|r")
        row.deleteBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.7, 0, 0, 0.8) end)
        row.deleteBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.4, 0, 0, 0.5) end)

        row:Hide()
        shopRows[i] = row
    end

    -- Fix scroll width after layout
    C_Timer.After(0.1, function()
        if scrollFrame:GetWidth() > 10 then
            scrollChild:SetWidth(scrollFrame:GetWidth())
        end
    end)
end

------------------------------------------------------------------------
-- Refresh Shop Tab
------------------------------------------------------------------------
function OneGuild:RefreshShop()
    if not self.db then return end
    if not self.db.shopListings then self.db.shopListings = {} end

    local parent = self.tabFrames[7]
    if not parent then return end

    local listings = self.db.shopListings
    local myName = ShortName(UnitName("player") or "")
    local now = time()

    -- Remove expired listings
    for i = #listings, 1, -1 do
        if listings[i].expires and listings[i].expires > 0 and listings[i].expires < now then
            table.remove(listings, i)
        end
    end

    -- Sort: newest first
    local sorted = {}
    for i, l in ipairs(listings) do
        table.insert(sorted, { index = i, data = l })
    end
    table.sort(sorted, function(a, b)
        return (a.data.timestamp or 0) > (b.data.timestamp or 0)
    end)

    -- Update count
    if parent.shopCountText then
        parent.shopCountText:SetText("|cFF888888(" .. #sorted .. " Angebote)|r")
    end

    -- Empty state
    if parent.emptyShopText then
        if #sorted == 0 then
            parent.emptyShopText:Show()
        else
            parent.emptyShopText:Hide()
        end
    end

    -- Populate rows
    for i = 1, MAX_ROWS do
        local row = shopRows[i]
        if i <= #sorted then
            local listing = sorted[i].data
            local listIdx = sorted[i].index

            -- Icon
            if listing.itemIcon then
                row.itemIcon:SetTexture(listing.itemIcon)
            else
                row.itemIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end

            -- Item name
            row.itemText:SetText(listing.itemLink or listing.itemName or "Unbekannt")

            -- Note
            if listing.note and listing.note ~= "" then
                row.noteText:SetText("|cFF888888" .. listing.note .. "|r")
                row.noteText:Show()
            else
                row.noteText:Hide()
            end

            -- Price
            local priceStr = listing.price or "Verhandelbar"
            local curStr = listing.currency or ""
            row.priceText:SetText("|cFFFFD700" .. priceStr .. " " .. curStr .. "|r")

            -- Seller
            row.sellerText:SetText("|cFF88AADD" .. ShortName(listing.seller or "?") .. "|r")

            -- Time
            if listing.expires and listing.expires > 0 then
                local remaining = listing.expires - now
                if remaining > 86400 then
                    row.timeText:SetText("|cFF888888" .. math.floor(remaining / 86400) .. " Tage|r")
                elseif remaining > 3600 then
                    row.timeText:SetText("|cFFFFCC00" .. math.floor(remaining / 3600) .. " Std|r")
                elseif remaining > 0 then
                    row.timeText:SetText("|cFFFF6666" .. math.floor(remaining / 60) .. " Min|r")
                else
                    row.timeText:SetText("|cFFFF4444Abgelaufen|r")
                end
            else
                row.timeText:SetText("|cFF888888Unbegrenzt|r")
            end

            -- Buy button: whisper the seller
            local sellerName = listing.seller or ""
            local itemDesc = listing.itemLink or listing.itemName or "Item"
            row.buyBtn:SetScript("OnClick", function()
                local short = ShortName(sellerName)
                if short == myName then
                    OneGuild:Print("|cFFFF6666Du kannst dein eigenes Angebot nicht kaufen!|r")
                    return
                end
                -- Open whisper to seller
                ChatFrame_OpenChat("/w " .. short .. " Hi! Ich moechte gerne kaufen: " .. itemDesc)
            end)

            -- Show delete only for own listings
            if ShortName(listing.seller or "") == myName then
                row.deleteBtn:Show()
                row.deleteBtn:SetScript("OnClick", function()
                    OneGuild:RemoveShopListing(listIdx)
                end)
            else
                row.deleteBtn:Hide()
            end

            -- Alternating row colors
            if i % 2 == 0 then
                row:SetBackdropColor(0.06, 0.06, 0.1, 0.7)
            else
                row:SetBackdropColor(0.04, 0.04, 0.08, 0.5)
            end

            row:Show()
        else
            row:Hide()
        end
    end

    -- Scroll child height
    if parent.shopScrollChild then
        local count = math.min(#sorted, MAX_ROWS)
        parent.shopScrollChild:SetHeight(count * (ROW_HEIGHT + 2) + 10)
    end
end

------------------------------------------------------------------------
-- Remove a shop listing
------------------------------------------------------------------------
function OneGuild:RemoveShopListing(index)
    if not self.db or not self.db.shopListings then return end
    local listing = self.db.shopListings[index]
    if not listing then return end

    local listingId = listing.id
    table.remove(self.db.shopListings, index)

    -- Broadcast deletion
    if listingId and self.BroadcastShopDel then
        self:BroadcastShopDel(listingId)
    end

    self:Print("|cFFFF6666Angebot entfernt.|r")
    self:RefreshShop()
end

------------------------------------------------------------------------
-- Add Listing Dialog
------------------------------------------------------------------------
function OneGuild:ShowAddListingDialog()
    if addListingFrame and addListingFrame:IsShown() then
        addListingFrame:Hide()
        return
    end

    if not addListingFrame then
        local f = CreateFrame("Frame", "OneGuildAddListing", UIParent, "BackdropTemplate")
        f:SetSize(380, 280)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetClampedToScreen(true)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.05, 0.05, 0.1, 0.98)
        f:SetBackdropBorderColor(0.2, 0.5, 0.8, 0.7)

        -- Drag
        local drag = CreateFrame("Frame", nil, f)
        drag:SetHeight(30)
        drag:SetPoint("TOPLEFT")
        drag:SetPoint("TOPRIGHT")
        drag:EnableMouse(true)
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", function() f:StartMoving() end)
        drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -10)
        title:SetText("|cFF88DDFFNeues Angebot|r")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)

        -- Item Name field
        local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
        itemLabel:SetText("|cFFAAAAAAItem Name:|r")

        local itemBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        itemBox:SetSize(340, 24)
        itemBox:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 0, -2)
        itemBox:SetFontObject("ChatFontNormal")
        itemBox:SetAutoFocus(false)
        itemBox:SetMaxLetters(100)
        itemBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 2, bottom = 2 },
        })
        itemBox:SetBackdropColor(0.02, 0.02, 0.04, 0.9)
        itemBox:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.5)
        itemBox:SetTextInsets(6, 6, 0, 0)
        f.itemBox = itemBox

        -- Price field
        local priceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        priceLabel:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", 0, -10)
        priceLabel:SetText("|cFFAAAAAAPreis:|r")

        local priceBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        priceBox:SetSize(160, 24)
        priceBox:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 0, -2)
        priceBox:SetFontObject("ChatFontNormal")
        priceBox:SetAutoFocus(false)
        priceBox:SetMaxLetters(30)
        priceBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 2, bottom = 2 },
        })
        priceBox:SetBackdropColor(0.02, 0.02, 0.04, 0.9)
        priceBox:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.5)
        priceBox:SetTextInsets(6, 6, 0, 0)
        f.priceBox = priceBox

        -- Currency dropdown-like label
        local currLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        currLabel:SetPoint("LEFT", priceBox, "RIGHT", 10, 0)
        currLabel:SetText("|cFFFFD700Gold|r")
        f.currLabel = currLabel

        -- Duration field
        local durLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durLabel:SetPoint("TOPLEFT", priceBox, "BOTTOMLEFT", 0, -10)
        durLabel:SetText("|cFFAAAAAADauer (Stunden, leer = unbegrenzt):|r")

        local durBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        durBox:SetSize(100, 24)
        durBox:SetPoint("TOPLEFT", durLabel, "BOTTOMLEFT", 0, -2)
        durBox:SetFontObject("ChatFontNormal")
        durBox:SetAutoFocus(false)
        durBox:SetMaxLetters(10)
        durBox:SetNumeric(true)
        durBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 2, bottom = 2 },
        })
        durBox:SetBackdropColor(0.02, 0.02, 0.04, 0.9)
        durBox:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.5)
        durBox:SetTextInsets(6, 6, 0, 0)
        f.durBox = durBox

        -- Note field
        local noteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        noteLabel:SetPoint("TOPLEFT", durBox, "BOTTOMLEFT", 0, -10)
        noteLabel:SetText("|cFFAAAAAANotiz (optional):|r")

        local noteBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        noteBox:SetSize(340, 24)
        noteBox:SetPoint("TOPLEFT", noteLabel, "BOTTOMLEFT", 0, -2)
        noteBox:SetFontObject("ChatFontNormal")
        noteBox:SetAutoFocus(false)
        noteBox:SetMaxLetters(100)
        noteBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 2, bottom = 2 },
        })
        noteBox:SetBackdropColor(0.02, 0.02, 0.04, 0.9)
        noteBox:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.5)
        noteBox:SetTextInsets(6, 6, 0, 0)
        f.noteBox = noteBox

        -- Submit button
        local submitBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        submitBtn:SetSize(120, 28)
        submitBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 14)
        submitBtn:RegisterForClicks("AnyUp")
        submitBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        submitBtn:SetBackdropColor(0.05, 0.3, 0.15, 0.9)
        submitBtn:SetBackdropBorderColor(0.1, 0.6, 0.3, 0.7)
        local submitText = submitBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        submitText:SetPoint("CENTER")
        submitText:SetText("|cFF66FF66Einstellen|r")
        submitBtn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.08, 0.4, 0.2, 1) end)
        submitBtn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.05, 0.3, 0.15, 0.9) end)
        submitBtn:SetScript("OnClick", function()
            OneGuild:SubmitShopListing()
        end)

        -- Escape closes
        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        f:Hide()
        addListingFrame = f
        table.insert(UISpecialFrames, "OneGuildAddListing")
    end

    -- Reset fields
    addListingFrame.itemBox:SetText("")
    addListingFrame.priceBox:SetText("")
    addListingFrame.durBox:SetText("")
    addListingFrame.noteBox:SetText("")
    addListingFrame:Show()
    addListingFrame.itemBox:SetFocus()
end

------------------------------------------------------------------------
-- Submit Listing
------------------------------------------------------------------------
function OneGuild:SubmitShopListing()
    local f = addListingFrame
    if not f then return end

    local itemName = strtrim(f.itemBox:GetText() or "")
    if itemName == "" then
        self:PrintError("Bitte gib einen Item-Namen ein!")
        return
    end

    local price = strtrim(f.priceBox:GetText() or "")
    if price == "" then price = "Verhandelbar" end

    local durHours = tonumber(f.durBox:GetText() or "")
    local expires = 0
    if durHours and durHours > 0 then
        expires = time() + (durHours * 3600)
    end

    local note = strtrim(f.noteBox:GetText() or "")
    local myName = self:GetPlayerName() or (UnitName("player") or "?")

    local listingId = ShortName(myName) .. "-" .. time() .. "-" .. math.random(1000, 9999)

    local listing = {
        id        = listingId,
        seller    = myName,
        itemName  = itemName,
        itemLink  = nil,  -- could be enhanced to support shift-click item links
        itemIcon  = nil,  -- could try to look up
        price     = price,
        currency  = "Gold",
        note      = note,
        timestamp = time(),
        expires   = expires,
    }

    if not self.db.shopListings then self.db.shopListings = {} end
    table.insert(self.db.shopListings, listing)

    -- Broadcast to guild
    if self.BroadcastShopListing then
        self:BroadcastShopListing(listing)
    end

    self:PrintSuccess("Angebot eingestellt: " .. itemName)
    f:Hide()
    self:RefreshShop()
    self:UpdateShopBadge()
end

------------------------------------------------------------------------
-- Shop Badge (unread notification count)
------------------------------------------------------------------------
function OneGuild:UpdateShopBadge()
    if not self.tabButtons or not self.tabButtons[7] then return end
    local btn = self.tabButtons[7]

    if not btn.badge then
        -- Create badge circle
        local badge = CreateFrame("Frame", nil, btn)
        badge:SetSize(18, 18)
        badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
        badge:SetFrameLevel(btn:GetFrameLevel() + 5)

        local bg = badge:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.9, 0.7, 0.1, 0.9)
        bg:SetTexture("Interface\\COMMON\\SpellChainGlow")
        -- Fallback: just use a colored solid
        bg:SetColorTexture(0.9, 0.7, 0.1, 0.9)

        local text = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER", 0, 0)
        text:SetTextColor(0, 0, 0)
        badge.text = text
        btn.badge = badge
    end

    -- Count new listings since last viewed
    local lastSeen = (self.db and self.db.shopLastSeen) or 0
    local listings = (self.db and self.db.shopListings) or {}
    local newCount = 0
    for _, l in ipairs(listings) do
        if (l.timestamp or 0) > lastSeen then
            newCount = newCount + 1
        end
    end

    if newCount > 0 and self.currentTab ~= 7 then
        btn.badge.text:SetText(tostring(newCount))
        btn.badge:Show()
    else
        btn.badge:Hide()
    end
end
