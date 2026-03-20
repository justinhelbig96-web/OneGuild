------------------------------------------------------------------------
-- OneGuild - UI.lua
-- Main window frame with tab navigation
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r UI.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local FRAME_WIDTH  = 780
local FRAME_HEIGHT = 580
local TAB_HEIGHT   = 32
local HEADER_H     = 80

local TAB_NAMES = { "Mitglieder", "Events", "Raid", "DKP Loot", "Notizen", "Charaktere", "Shop" }

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
OneGuild.mainFrame   = nil
OneGuild.tabFrames   = {}
OneGuild.tabButtons  = {}
OneGuild.currentTab  = 1

------------------------------------------------------------------------
-- Build the main window
------------------------------------------------------------------------
function OneGuild:BuildMainFrame()
    if self.mainFrame then return end

    -- Main frame
    local f = CreateFrame("Frame", "OneGuildMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:SetResizable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(100)

    -- Backdrop
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
    f:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.8)

    -- Top accent glow line
    local accentGlow = f:CreateTexture(nil, "ARTWORK", nil, 3)
    accentGlow:SetHeight(2)
    accentGlow:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    accentGlow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    accentGlow:SetColorTexture(0.9, 0.6, 0.1, 0.8)
    -- Pulse animation for top accent
    local accentPulse = accentGlow:CreateAnimationGroup()
    local fadeOut = accentPulse:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(0.9)
    fadeOut:SetToAlpha(0.3)
    fadeOut:SetDuration(2.0)
    fadeOut:SetOrder(1)
    fadeOut:SetSmoothing("IN_OUT")
    local fadeIn = accentPulse:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0.3)
    fadeIn:SetToAlpha(0.9)
    fadeIn:SetDuration(2.0)
    fadeIn:SetOrder(2)
    fadeIn:SetSmoothing("IN_OUT")
    accentPulse:SetLooping("REPEAT")
    accentPulse:Play()

    -- Title bar drag
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(HEADER_H)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

    -- Guild logo (left side of header)
    local logo = f:CreateTexture(nil, "ARTWORK", nil, 2)
    logo:SetSize(120, 60)
    logo:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    logo:SetTexture("Interface\\AddOns\\OneGuild\\logo")
    -- Subtle breathing glow on logo
    local logoGlow = f:CreateTexture(nil, "ARTWORK", nil, 1)
    logoGlow:SetSize(132, 72)
    logoGlow:SetPoint("CENTER", logo, "CENTER", 0, 0)
    logoGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    logoGlow:SetVertexColor(0.9, 0.6, 0.1, 0.08)
    local logoBreath = logoGlow:CreateAnimationGroup()
    local lbOut = logoBreath:CreateAnimation("Alpha")
    lbOut:SetFromAlpha(0.12)
    lbOut:SetToAlpha(0.02)
    lbOut:SetDuration(3.0)
    lbOut:SetOrder(1)
    lbOut:SetSmoothing("IN_OUT")
    local lbIn = logoBreath:CreateAnimation("Alpha")
    lbIn:SetFromAlpha(0.02)
    lbIn:SetToAlpha(0.12)
    lbIn:SetDuration(3.0)
    lbIn:SetOrder(2)
    lbIn:SetSmoothing("IN_OUT")
    logoBreath:SetLooping("REPEAT")
    logoBreath:Play()

    -- Title text (larger, next to logo)
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    title:SetPoint("TOPLEFT", logo, "TOPRIGHT", 10, -4)
    title:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
        OneGuild.COLORS.MUTED .. "v" .. OneGuild.VERSION .. "|r")
    f.titleText = title

    -- Update button (hidden by default, shown when newer version detected)
    local updateBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    updateBtn:SetSize(130, 20)
    updateBtn:SetPoint("LEFT", title, "RIGHT", 10, 0)
    updateBtn:SetFrameLevel(titleBar:GetFrameLevel() + 5)
    updateBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    updateBtn:SetBackdropColor(0.1, 0.5, 0.1, 0.9)
    updateBtn:SetBackdropBorderColor(0.3, 0.8, 0.3, 0.8)

    local updateIcon = updateBtn:CreateTexture(nil, "ARTWORK")
    updateIcon:SetSize(14, 14)
    updateIcon:SetPoint("LEFT", updateBtn, "LEFT", 5, 0)
    updateIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")

    local updateText = updateBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    updateText:SetPoint("LEFT", updateIcon, "RIGHT", 3, 0)
    updateText:SetText("|cFF66FF66Update!|r")
    f.updateBtnText = updateText

    updateBtn:SetScript("OnClick", function()
        -- Show a popup with the GitHub URL to copy
        StaticPopupDialogs["ONEGUILD_UPDATE"] = {
            text = "|cFFFFB800OneGuild Update|r\n\nNeue Version: |cFF66FF66v" ..
                (OneGuild.newerVersion or "?") .. "|r\nDeine Version: |cFFFF8800v" ..
                OneGuild.VERSION .. "|r\n\nLade die neue Version hier herunter:\n|cFF88BBFF" ..
                OneGuild.GITHUB_URL .. "|r\n\nURL wurde in den Chat geschrieben.",
            button1 = "OK",
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("ONEGUILD_UPDATE")
        -- Print clickable link to chat (players can Shift-click URLs from chat)
        print("|cFFFFB800[OneGuild]|r Neue Version v" .. (OneGuild.newerVersion or "?") ..
            " herunterladen: |cFF88BBFF" .. OneGuild.GITHUB_URL .. "|r")
    end)
    updateBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.6, 0.15, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cFF66FF66Neue Version verfuegbar!|r")
        GameTooltip:AddLine("Klicke fuer den Download-Link", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    updateBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.5, 0.1, 0.9)
        GameTooltip:Hide()
    end)
    updateBtn:Hide()
    f.updateBtn = updateBtn

    -- Function to update version display (called when newer version detected)
    function OneGuild:UpdateVersionDisplay()
        if not f or not f.updateBtn then return end
        if self.newerVersion then
            f.updateBtnText:SetText("|cFF66FF66v" .. self.newerVersion .. " Update!|r")
            f.updateBtn:Show()
            -- Flash the title to draw attention
            f.titleText:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
                "|cFFFF4444v" .. OneGuild.VERSION .. " (veraltet)|r")
        else
            f.updateBtn:Hide()
            f.titleText:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
                OneGuild.COLORS.MUTED .. "v" .. OneGuild.VERSION .. "|r")
        end
    end

    -- Guild name subtitle
    local subtitle = f:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetText(OneGuild.COLORS.GUILD .. "<" .. (OneGuild.playerGuild or OneGuild.REQUIRED_GUILD) .. ">|r")

    -- Creator credit
    local credit = f:CreateFontString(nil, "OVERLAY")
    credit:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    credit:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -1)
    credit:SetTextColor(0.55, 0.45, 0.33, 0.8)
    credit:SetText("Created by Icy_Veins")

    -- ===== SYNC PROGRESS BAR (bottom of header) =====
    local syncBarBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    syncBarBg:SetHeight(6)
    syncBarBg:SetPoint("BOTTOMLEFT", titleBar, "BOTTOMLEFT", 10, 2)
    syncBarBg:SetPoint("BOTTOMRIGHT", titleBar, "BOTTOMRIGHT", -10, 2)
    syncBarBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 4,
        insets   = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    syncBarBg:SetBackdropColor(0.03, 0.02, 0.02, 0.8)
    syncBarBg:SetBackdropBorderColor(0.3, 0.2, 0.05, 0.4)

    local syncBarFill = syncBarBg:CreateTexture(nil, "ARTWORK")
    syncBarFill:SetHeight(4)
    syncBarFill:SetPoint("TOPLEFT", syncBarBg, "TOPLEFT", 1, -1)
    syncBarFill:SetColorTexture(0.4, 0.7, 0.2, 0.9)
    syncBarFill:SetWidth(1)
    f.syncBarFill = syncBarFill
    f.syncBarBg = syncBarBg

    -- Glow effect on the leading edge of progress bar
    local syncBarGlow = syncBarBg:CreateTexture(nil, "OVERLAY")
    syncBarGlow:SetSize(12, 10)
    syncBarGlow:SetPoint("RIGHT", syncBarFill, "RIGHT", 4, 0)
    syncBarGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    syncBarGlow:SetVertexColor(0.5, 1, 0.3, 0.6)
    f.syncBarGlow = syncBarGlow

    -- Sync label (tiny, on the right)
    local syncBarLabel = syncBarBg:CreateFontString(nil, "OVERLAY")
    syncBarLabel:SetFont("Fonts\\FRIZQT__.TTF", 8, "OUTLINE")
    syncBarLabel:SetPoint("RIGHT", syncBarBg, "RIGHT", 0, 8)
    syncBarLabel:SetText("")
    f.syncBarLabel = syncBarLabel

    -- Timer to animate the sync progress bar
    local DKP_SYNC_SEC = 30
    local syncStartTime = GetTime()
    f.syncStartTime = syncStartTime

    local syncTicker = C_Timer.NewTicker(0.05, function()
        if not f or not f:IsShown() then return end
        local elapsed = GetTime() - (f.syncStartTime or syncStartTime)
        local progress = math.min(elapsed / DKP_SYNC_SEC, 1.0)
        local barWidth = math.max(1, (syncBarBg:GetWidth() - 2) * progress)
        syncBarFill:SetWidth(barWidth)

        -- Color transition: green -> gold -> briefly flash on reset
        if progress < 0.7 then
            syncBarFill:SetColorTexture(0.2 + 0.3 * progress, 0.7 - 0.2 * progress, 0.2, 0.9)
            syncBarGlow:SetVertexColor(0.3 + 0.4 * progress, 1 - 0.3 * progress, 0.3, 0.6)
        else
            syncBarFill:SetColorTexture(0.7, 0.5, 0.1, 0.9)
            syncBarGlow:SetVertexColor(1, 0.7, 0.2, 0.8)
        end

        local remaining = math.max(0, math.ceil(DKP_SYNC_SEC - elapsed))
        syncBarLabel:SetText("|cFF666655Sync: " .. remaining .. "s|r")

        if progress >= 1.0 then
            f.syncStartTime = GetTime()
            -- Flash white briefly
            syncBarFill:SetColorTexture(1, 1, 1, 0.8)
            C_Timer.After(0.15, function()
                if syncBarFill then syncBarFill:SetColorTexture(0.4, 0.7, 0.2, 0.9) end
            end)
        end
    end)
    f.syncTicker = syncTicker

    -- Reset bar on manual sync too
    local origSyncOnClick -- will be set after syncBtn is created

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        f:Hide()
    end)
    f.closeBtn = closeBtn

    -- GEAR (Settings) BUTTON next to close
    local gearBtn = CreateFrame("Button", nil, titleBar)
    gearBtn:SetSize(24, 24)
    gearBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    gearBtn:RegisterForClicks("AnyUp")

    local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
    gearIcon:SetAllPoints()
    gearIcon:SetTexture("Interface\\Scenarios\\ScenarioIcon-Interact")
    gearIcon:SetVertexColor(0.85, 0.65, 0.15, 0.9)

    gearBtn:SetScript("OnClick", function()
        if OneGuild.ToggleSettings then
            OneGuild:ToggleSettings()
        end
    end)
    gearBtn:SetScript("OnEnter", function(self)
        gearIcon:SetVertexColor(1, 0.84, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cFFFFB800Einstellungen|r", 1, 1, 1)
        GameTooltip:AddLine("OneGuild-Optionen \195\182ffnen", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    gearBtn:SetScript("OnLeave", function()
        gearIcon:SetVertexColor(0.85, 0.65, 0.15, 0.9)
        GameTooltip:Hide()
    end)
    f.gearBtn = gearBtn

    -- GREEN SYNC BUTTON (visible on all tabs)
    local syncBtn = CreateFrame("Button", nil, titleBar, "BackdropTemplate")
    syncBtn:SetSize(60, 24)
    syncBtn:SetPoint("RIGHT", gearBtn, "LEFT", -4, -1)
    syncBtn:RegisterForClicks("AnyUp")
    syncBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    syncBtn:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
    syncBtn:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)

    local syncIcon = syncBtn:CreateTexture(nil, "ARTWORK")
    syncIcon:SetSize(14, 14)
    syncIcon:SetPoint("LEFT", syncBtn, "LEFT", 6, 0)
    syncIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")

    local syncText = syncBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    syncText:SetPoint("LEFT", syncIcon, "RIGHT", 4, 0)
    syncText:SetText("|cFF66FF66Sync|r")

    -- Spinning animation group for sync icon
    local spinGroup = syncIcon:CreateAnimationGroup()
    local spinAnim = spinGroup:CreateAnimation("Rotation")
    spinAnim:SetDegrees(-360)
    spinAnim:SetDuration(0.8)
    spinGroup:SetLooping("REPEAT")
    local isSyncing = false

    syncBtn:SetScript("OnClick", function()
        if isSyncing then return end
        isSyncing = true

        -- Reset sync progress bar
        if f.syncStartTime then
            f.syncStartTime = GetTime()
        end

        -- Start spinning animation (gear icon)
        syncIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        syncIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        spinGroup:Play()
        syncText:SetText("|cFF66FF66...|r")

        -- Execute actual sync
        if OneGuild.VerifyOnlineViaRoster then
            OneGuild:VerifyOnlineViaRoster()
        end
        if OneGuild.MarkStaleOffline then
            OneGuild:MarkStaleOffline()
        end
        if OneGuild.FullSync then
            OneGuild:FullSync()
            OneGuild:Print(OneGuild.COLORS.SUCCESS ..
                "Vollstaendiger Sync gestartet (Spieler, Charaktere, Raids, Events, DKP).|r")
        end

        -- Refresh current tab
        local idx = OneGuild.currentTab
        if idx == 1 and OneGuild.RefreshMembers then OneGuild:RefreshMembers()
        elseif idx == 2 and OneGuild.RefreshEvents then OneGuild:RefreshEvents()
        elseif idx == 3 and OneGuild.RefreshRaid then OneGuild:RefreshRaid()
        elseif idx == 4 and OneGuild.RefreshDKPLoot then OneGuild:RefreshDKPLoot()
        elseif idx == 5 and OneGuild.RefreshNotes then OneGuild:RefreshNotes()
        elseif idx == 6 and OneGuild.RefreshCharacters then OneGuild:RefreshCharacters()
        end

        -- After 2.5s: stop spinning, show checkmark
        C_Timer.After(2.5, function()
            spinGroup:Stop()
            syncIcon:SetTexture("Interface\\RAIDFRAME\\ReadyCheck-Ready")
            syncIcon:SetTexCoord(0, 1, 0, 1)
            syncText:SetText("|cFF66FF66\226\156\147|r")
            -- After 1.5s: revert to normal
            C_Timer.After(1.5, function()
                syncText:SetText("|cFF66FF66Sync|r")
                isSyncing = false
            end)
        end)
    end)
    syncBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.15, 0.6, 0.15, 1)
        self:SetBackdropBorderColor(0.3, 0.9, 0.3, 0.9)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("|cFF66FF66Vollstaendiger Sync|r", 1, 1, 1)
        GameTooltip:AddLine("Synchronisiert ALLE Daten mit\nonline Gildenmitgliedern:", 0.7, 0.7, 0.7)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("  Spieler & Praesenz", 0.6, 0.8, 0.6)
        GameTooltip:AddLine("  Charaktere & Alts", 0.6, 0.8, 0.6)
        GameTooltip:AddLine("  Raids & Anmeldungen", 0.6, 0.8, 0.6)
        GameTooltip:AddLine("  Events & Anmeldungen", 0.6, 0.8, 0.6)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Automatischer Sync alle 60 Sekunden.", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        self:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        GameTooltip:Hide()
    end)

    -- GUILD BANK GOLD DISPLAY (below title bar, left side)
    local goldFrame = CreateFrame("Frame", nil, titleBar)
    goldFrame:SetSize(220, 16)
    goldFrame:SetPoint("RIGHT", syncBtn, "LEFT", -8, 0)
    f.goldFrame = goldFrame

    local goldText = goldFrame:CreateFontString(nil, "OVERLAY")
    goldText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    goldText:SetPoint("RIGHT", goldFrame, "RIGHT", 0, 0)
    goldText:SetTextColor(0.65, 0.55, 0.35, 0.9)
    goldText:SetText("Gildenbank: ---")
    f.goldText = goldText

    -- Gold icon helper
    local function MakeCoinIcon(parentStr, iconType)
        if iconType == "gold" then
            return "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12|t"
        elseif iconType == "silver" then
            return "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12|t"
        else
            return "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12|t"
        end
    end

    function OneGuild:UpdateGoldDisplay()
        if not self.mainFrame or not self.mainFrame.goldText then return end
        local money = (self.db and self.db.guildBankMoney) or 0
        if money <= 0 then
            self.mainFrame.goldText:SetText("|cFF8B7355Gildenbank: ---|r")
            return
        end
        local gold   = math.floor(money / 10000)
        local silver = math.floor((money % 10000) / 100)
        local copper = money % 100

        local gIcon = MakeCoinIcon(nil, "gold")
        local sIcon = MakeCoinIcon(nil, "silver")
        local cIcon = MakeCoinIcon(nil, "copper")

        local str = "|cFF8B7355Gildenbank:|r  "
            .. "|cFFFFD700" .. gold .. "|r" .. gIcon .. "  "
            .. "|cFFC0C0C0" .. silver .. "|r" .. sIcon .. "  "
            .. "|cFFB87333" .. copper .. "|r" .. cIcon
        self.mainFrame.goldText:SetText(str)
    end

    -- Initial display from saved data
    C_Timer.After(0.5, function()
        if OneGuild.UpdateGoldDisplay then
            OneGuild:UpdateGoldDisplay()
        end
    end)

    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, f)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeBtn:SetScript("OnMouseDown", function()
        f:StartSizing("BOTTOMRIGHT")
    end)
    resizeBtn:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if OneGuild.OnResize then
            OneGuild:OnResize()
        end
    end)
    if f.SetResizeBounds then
        f:SetResizeBounds(500, 400, 1000, 800)
    end

    -- Horizontal line under header
    local headerLine = f:CreateTexture(nil, "ARTWORK")
    headerLine:SetColorTexture(0.7, 0.5, 0.1, 0.5)
    headerLine:SetHeight(1)
    headerLine:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(HEADER_H))
    headerLine:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -(HEADER_H))

    -- Tab buttons
    local tabContainer = CreateFrame("Frame", nil, f)
    tabContainer:SetHeight(TAB_HEIGHT)
    tabContainer:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(HEADER_H + 4))
    tabContainer:SetPoint("TOPRIGHT", f, "TOPRIGHT", -10, -(HEADER_H + 4))

    for i, name in ipairs(TAB_NAMES) do
        local tab = CreateFrame("Button", "OneGuildTab" .. i, tabContainer, "BackdropTemplate")
        tab:SetSize(82, TAB_HEIGHT - 4)
        tab:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })

        if i == 1 then
            tab:SetPoint("LEFT", tabContainer, "LEFT", 0, 0)
        else
            tab:SetPoint("LEFT", self.tabButtons[i - 1], "RIGHT", 6, 0)
        end

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("CENTER")
        tabText:SetText(name)
        tab.text = tabText

        tab:SetScript("OnClick", function()
            OneGuild:ShowTab(i)
        end)

        tab:SetScript("OnEnter", function(self)
            if OneGuild.currentTab ~= i then
                self:SetBackdropColor(0.25, 0.15, 0.05, 0.8)
            end
        end)
        tab:SetScript("OnLeave", function(self)
            if OneGuild.currentTab ~= i then
                self:SetBackdropColor(0.1, 0.06, 0.04, 0.8)
            end
        end)

        self.tabButtons[i] = tab
    end

    -- Tab content frames
    for i = 1, #TAB_NAMES do
        local content = CreateFrame("Frame", "OneGuildContent" .. i, f, "BackdropTemplate")
        content:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -(HEADER_H + TAB_HEIGHT + 8))
        content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
        content:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        content:SetBackdropColor(0.06, 0.03, 0.03, 0.9)
        content:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)
        content:Hide()
        self.tabFrames[i] = content
    end

    -- Start hidden
    f:Hide()
    self.mainFrame = f

    -- Build tab contents
    if self.BuildMembersTab then self:BuildMembersTab() end
    if self.BuildEventsTab then self:BuildEventsTab() end
    if self.BuildRaidTab then self:BuildRaidTab() end
    if self.BuildDKPLootTab then self:BuildDKPLootTab() end
    if self.BuildNotesTab then  self:BuildNotesTab()  end
    if self.BuildCharactersTab then self:BuildCharactersTab() end
    if self.BuildShopTab then self:BuildShopTab() end

    -- Show first tab
    self:ShowTab(1)

    -- Check for update on open
    if self.UpdateVersionDisplay then self:UpdateVersionDisplay() end

    -- ESC to close
    table.insert(UISpecialFrames, "OneGuildMainFrame")
end

------------------------------------------------------------------------
-- Tab switching
------------------------------------------------------------------------
function OneGuild:ShowTab(index)
    self.currentTab = index
    for i, content in ipairs(self.tabFrames) do
        if i == index then
            content:Show()
            self.tabButtons[i]:SetBackdropColor(0.5, 0.35, 0.05, 0.9)
            self.tabButtons[i]:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
            self.tabButtons[i].text:SetTextColor(1, 0.85, 0.3)
        else
            content:Hide()
            self.tabButtons[i]:SetBackdropColor(0.1, 0.06, 0.04, 0.8)
            self.tabButtons[i]:SetBackdropBorderColor(0.3, 0.2, 0.1, 0.5)
            self.tabButtons[i].text:SetTextColor(0.6, 0.5, 0.3)
        end
    end

    -- Refresh data on tab switch
    if index == 1 and self.RefreshMembers then
        self:RefreshMembers()
    elseif index == 2 and self.RefreshEvents then
        self:RefreshEvents()
    elseif index == 3 and self.RefreshRaid then
        self:RefreshRaid()
    elseif index == 4 and self.RefreshDKPLoot then
        self:RefreshDKPLoot()
    elseif index == 5 and self.RefreshNotes then
        self:RefreshNotes()
    elseif index == 6 and self.RefreshCharacters then
        self:RefreshCharacters()
    elseif index == 7 and self.RefreshShop then
        self:RefreshShop()
    end

    -- Update shop badge (hide when viewing shop)
    if index == 7 and self.db then
        self.db.shopLastSeen = time()
        if self.UpdateShopBadge then self:UpdateShopBadge() end
    end
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function OneGuild:ToggleMainWindow()
    if not self:IsAuthorized() then
        self:VerifyGuild()
        return
    end
    if not self.mainFrame then
        self:BuildMainFrame()
    end
    if self.mainFrame:IsShown() then
        self.mainFrame:Hide()
    else
        self.mainFrame:Show()
    end
end

------------------------------------------------------------------------
-- Check if rules have been accepted
------------------------------------------------------------------------
function OneGuild:IsRegistrationComplete()
    if not self.db then return true end
    return self.db.rulesAccepted == true
end

------------------------------------------------------------------------
-- Admin state
------------------------------------------------------------------------
OneGuild.isAdmin = false
local ADMIN_PASSWORD = "OneAdmin"

------------------------------------------------------------------------
-- Admin Login Dialog
------------------------------------------------------------------------
function OneGuild:ShowAdminLoginDialog()
    if self.adminLoginFrame and self.adminLoginFrame:IsShown() then
        self.adminLoginFrame:Hide()
        return
    end

    if not self.adminLoginFrame then
        local f = CreateFrame("Frame", "OneGuildAdminLogin", UIParent, "BackdropTemplate")
        f:SetSize(300, 150)
        f:SetPoint("CENTER")
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

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", f, "TOP", 0, -14)
        title:SetText("|cFFFFAA33Admin Login|r")

        local info = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        info:SetPoint("TOP", title, "BOTTOM", 0, -6)
        info:SetText("|cFF8B7355Passwort eingeben:|r")

        local pwBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
        pwBox:SetSize(200, 28)
        pwBox:SetPoint("TOP", info, "BOTTOM", 0, -8)
        pwBox:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        pwBox:SetBackdropColor(0.12, 0.06, 0.04, 1)
        pwBox:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        pwBox:SetFontObject("GameFontHighlight")
        pwBox:SetAutoFocus(false)
        pwBox:SetMaxLetters(30)
        pwBox:SetTextInsets(6, 6, 0, 0)
        f.pwBox = pwBox

        local errText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        errText:SetPoint("TOP", pwBox, "BOTTOM", 0, -4)
        errText:SetText("")
        f.errText = errText

        local loginBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        loginBtn:SetSize(90, 26)
        loginBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
        loginBtn:RegisterForClicks("AnyUp")
        loginBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        loginBtn:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        loginBtn:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        local loginBtnText = loginBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        loginBtnText:SetPoint("CENTER")
        loginBtnText:SetText("|cFF66FF66Login|r")
        loginBtn:SetScript("OnClick", function()
            local pw = strtrim(pwBox:GetText() or "")
            if pw == ADMIN_PASSWORD then
                OneGuild.isAdmin = true
                OneGuild:Print(OneGuild.COLORS.SUCCESS .. "Admin erfolgreich eingeloggt!|r")
                f:Hide()
                if OneGuild.mainFrame and OneGuild.mainFrame.UpdateAdminBtnVisual then
                    OneGuild.mainFrame.UpdateAdminBtnVisual()
                end
                if OneGuild.RefreshMembers then OneGuild:RefreshMembers() end
            else
                f.errText:SetText("|cFFFF4444Falsches Passwort!|r")
            end
        end)

        local cancelBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        cancelBtn:SetSize(90, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
        cancelBtn:RegisterForClicks("AnyUp")
        cancelBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        cancelBtn:SetBackdropColor(0.4, 0.1, 0.1, 0.9)
        cancelBtn:SetBackdropBorderColor(0.6, 0.2, 0.2, 0.7)
        local cancelBtnText = cancelBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cancelBtnText:SetPoint("CENTER")
        cancelBtnText:SetText("|cFFFF6666Abbrechen|r")
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        pwBox:SetScript("OnEnterPressed", function()
            loginBtn:GetScript("OnClick")(loginBtn)
        end)
        pwBox:SetScript("OnEscapePressed", function()
            f:Hide()
        end)

        self.adminLoginFrame = f
    end

    self.adminLoginFrame.pwBox:SetText("")
    self.adminLoginFrame.errText:SetText("")
    self.adminLoginFrame:Show()
    self.adminLoginFrame.pwBox:SetFocus()
end
