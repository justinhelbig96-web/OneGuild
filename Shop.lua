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

        -- Apply premium effects
        if OneGuild.FX then
            OneGuild.FX:RowHover(row, 0.3, 0.4, 0.6)
            OneGuild.FX:StyleButton(row.buyBtn, "blue")
        end
    end

    -- Style the add button
    if OneGuild.FX then
        OneGuild.FX:StyleButton(addBtn, "green")
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

            -- Price (Gold / Silver / Copper)
            local g = tonumber(listing.goldPrice) or 0
            local s = tonumber(listing.silverPrice) or 0
            local c = tonumber(listing.copperPrice) or 0
            if g == 0 and s == 0 and c == 0 then
                -- Legacy or negotiable
                if listing.price and listing.price ~= "" and listing.price ~= "Verhandelbar" then
                    row.priceText:SetText("|cFFFFD700" .. listing.price .. " " .. (listing.currency or "") .. "|r")
                else
                    row.priceText:SetText("|cFF888888Verhandelbar|r")
                end
            else
                local parts = {}
                local gIcon = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"
                local sIcon = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12|t"
                local cIcon = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12|t"
                if g > 0 then table.insert(parts, "|cFFFFD700" .. g .. "|r" .. gIcon) end
                if s > 0 then table.insert(parts, "|cFFC0C0C0" .. s .. "|r" .. sIcon) end
                if c > 0 then table.insert(parts, "|cFFB87333" .. c .. "|r" .. cIcon) end
                row.priceText:SetText(table.concat(parts, " "))
            end

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
        f:SetSize(380, 380)
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

        -- Item: Drag & Drop slot
        local itemLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
        itemLabel:SetText("|cFFAAAAAAItem (Drag & Drop aus dem Inventar):|r")

        local dropSlot = CreateFrame("Button", "OneGuildShopDropSlot", f, "BackdropTemplate")
        dropSlot:SetSize(52, 52)
        dropSlot:SetPoint("TOPLEFT", itemLabel, "BOTTOMLEFT", 0, -4)
        dropSlot:RegisterForClicks("AnyUp")
        dropSlot:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        dropSlot:SetBackdropColor(0.06, 0.06, 0.12, 0.95)
        dropSlot:SetBackdropBorderColor(0.4, 0.4, 0.6, 0.6)

        local dropIcon = dropSlot:CreateTexture(nil, "ARTWORK")
        dropIcon:SetSize(40, 40)
        dropIcon:SetPoint("CENTER")
        dropIcon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
        f.dropIcon = dropIcon

        local itemNameText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        itemNameText:SetPoint("LEFT", dropSlot, "RIGHT", 10, 0)
        itemNameText:SetWidth(260)
        itemNameText:SetJustifyH("LEFT")
        itemNameText:SetText("|cFF555555Drag & Drop|r")
        f.itemNameText = itemNameText

        local function HandleItemDrop()
            local infoType, itemID, itemLink = GetCursorInfo()
            if infoType == "item" then
                ClearCursor()
                local name, _, quality, ilvl, _, _, _, _, _, icon = C_Item.GetItemInfo(itemLink)
                if not name then name, _, quality, ilvl, _, _, _, _, _, icon = GetItemInfo(itemLink) end
                f.selectedItemLink = itemLink
                f.selectedItemID   = itemID
                f.selectedItemName = name or "Unbekannt"
                f.selectedItemIcon = icon
                f.selectedItemIlvl = ilvl or 0
                f.selectedItemQuality = quality or 1
                if icon then dropIcon:SetTexture(icon) end
                itemNameText:SetText(itemLink or name or "?")
            end
        end

        dropSlot:SetScript("OnReceiveDrag", HandleItemDrop)
        dropSlot:SetScript("OnClick", HandleItemDrop)
        f.dropSlot = dropSlot

        -- Price: Gold / Silver / Copper
        local priceLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        priceLabel:SetPoint("TOPLEFT", dropSlot, "BOTTOMLEFT", 0, -10)
        priceLabel:SetText("|cFFAAAAAAPreis (leer = Verhandelbar):|r")

        local function MakePriceBox(parent, w)
            local eb = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
            eb:SetSize(w, 24)
            eb:SetFontObject("ChatFontNormal")
            eb:SetAutoFocus(false)
            eb:SetMaxLetters(7)
            eb:SetNumeric(true)
            eb:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets   = { left = 4, right = 4, top = 2, bottom = 2 },
            })
            eb:SetBackdropColor(0.02, 0.02, 0.04, 0.9)
            eb:SetBackdropBorderColor(0.3, 0.3, 0.5, 0.5)
            eb:SetTextInsets(6, 6, 0, 0)
            return eb
        end

        local goldBox = MakePriceBox(f, 80)
        goldBox:SetPoint("TOPLEFT", priceLabel, "BOTTOMLEFT", 0, -2)
        f.goldBox = goldBox
        local goldLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        goldLabel:SetPoint("LEFT", goldBox, "RIGHT", 4, 0)
        goldLabel:SetText("|TInterface\\MoneyFrame\\UI-GoldIcon:14:14|t")

        local silverBox = MakePriceBox(f, 60)
        silverBox:SetPoint("LEFT", goldLabel, "RIGHT", 8, 0)
        f.silverBox = silverBox
        local silverLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        silverLabel:SetPoint("LEFT", silverBox, "RIGHT", 4, 0)
        silverLabel:SetText("|TInterface\\MoneyFrame\\UI-SilverIcon:14:14|t")

        local copperBox = MakePriceBox(f, 60)
        copperBox:SetPoint("LEFT", silverLabel, "RIGHT", 8, 0)
        f.copperBox = copperBox
        local copperLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        copperLabel:SetPoint("LEFT", copperBox, "RIGHT", 4, 0)
        copperLabel:SetText("|TInterface\\MoneyFrame\\UI-CopperIcon:14:14|t")

        -- Duration field
        local durLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        durLabel:SetPoint("TOPLEFT", goldBox, "BOTTOMLEFT", 0, -10)
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
    addListingFrame.selectedItemLink = nil
    addListingFrame.selectedItemID = nil
    addListingFrame.selectedItemName = nil
    addListingFrame.selectedItemIcon = nil
    addListingFrame.selectedItemIlvl = nil
    addListingFrame.selectedItemQuality = nil
    if addListingFrame.dropIcon then
        addListingFrame.dropIcon:SetTexture("Interface\\PaperDoll\\UI-Backpack-EmptySlot")
    end
    if addListingFrame.itemNameText then
        addListingFrame.itemNameText:SetText("|cFF555555Drag & Drop|r")
    end
    addListingFrame.goldBox:SetText("")
    addListingFrame.silverBox:SetText("")
    addListingFrame.copperBox:SetText("")
    addListingFrame.durBox:SetText("")
    addListingFrame.noteBox:SetText("")
    addListingFrame:Show()
end

------------------------------------------------------------------------
-- Submit Listing
------------------------------------------------------------------------
function OneGuild:SubmitShopListing()
    local f = addListingFrame
    if not f then return end

    local itemName = f.selectedItemName
    if not itemName or itemName == "" then
        self:PrintError("Bitte ziehe ein Item in das Feld (Drag & Drop)!")
        return
    end

    local gold   = tonumber(f.goldBox:GetText() or "") or 0
    local silver = tonumber(f.silverBox:GetText() or "") or 0
    local copper = tonumber(f.copperBox:GetText() or "") or 0

    local durHours = tonumber(f.durBox:GetText() or "")
    local expires = 0
    if durHours and durHours > 0 then
        expires = time() + (durHours * 3600)
    end

    local note = strtrim(f.noteBox:GetText() or "")
    local myName = self:GetPlayerName() or (UnitName("player") or "?")

    local listingId = ShortName(myName) .. "-" .. time() .. "-" .. math.random(1000, 9999)

    local listing = {
        id           = listingId,
        seller       = myName,
        itemName     = itemName,
        itemLink     = f.selectedItemLink,
        itemIcon     = f.selectedItemIcon,
        goldPrice    = gold,
        silverPrice  = silver,
        copperPrice  = copper,
        itemIlvl     = f.selectedItemIlvl or 0,
        itemQuality  = f.selectedItemQuality or 1,
        note         = note,
        timestamp    = time(),
        expires      = expires,
    }

    if not self.db.shopListings then self.db.shopListings = {} end
    table.insert(self.db.shopListings, listing)

    -- Broadcast to guild
    if self.BroadcastShopListing then
        self:BroadcastShopListing(listing)
    end

    self:PrintSuccess("Angebot eingestellt: " .. (f.selectedItemLink or itemName))
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
