------------------------------------------------------------------------
-- OneGuild - GuildTab.lua
-- Hooks into the Blizzard Communities Frame (J key) to add a custom
-- "OneGuild" tab. Gold/bronze theme matching guild logo.
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r GuildTab.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local tabButton    = nil
local tabContent   = nil
local isHooked     = false
local TAB_NAME     = "OneGuild"

------------------------------------------------------------------------
-- Build the tab content panel (inside CommunitiesFrame)
------------------------------------------------------------------------
local function BuildTabContent(parent)
    if tabContent then return tabContent end

    local f = CreateFrame("Frame", "OneGuildCommunityTab", parent, "BackdropTemplate")
    f:SetAllPoints(parent.CommunitiesFrame and parent.CommunitiesFrame.MemberList
        or parent)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(50)

    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
    f:SetBackdropBorderColor(0.6, 0.45, 0.1, 0.5)

    -- Top accent line (gold)
    local accent = f:CreateTexture(nil, "ARTWORK", nil, 2)
    accent:SetHeight(2)
    accent:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
    accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    accent:SetColorTexture(0.7, 0.5, 0.1, 0.6)

    -- Guild icon
    local icon = f:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", f, "TOP", 0, -25)
    icon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    title:SetPoint("TOP", icon, "BOTTOM", 0, -10)
    title:SetText("|cFFFFB800OneGuild|r")

    -- Guild name
    local guildText = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    guildText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    guildText:SetText("|cFFFFD700<" .. OneGuild.REQUIRED_GUILD .. ">|r")

    -- Version
    local version = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    version:SetPoint("TOP", guildText, "BOTTOM", 0, -4)
    version:SetText("|cFF8B7355v" .. OneGuild.VERSION .. "|r")

    -- Separator
    local sep = f:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -135)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -135)
    sep:SetColorTexture(0.5, 0.35, 0.1, 0.3)

    -- Status section
    local statusHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    statusHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -150)
    statusHeader:SetText("|cFFDDB866Status|r")

    local verifiedText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    verifiedText:SetPoint("TOPLEFT", statusHeader, "BOTTOMLEFT", 0, -8)
    f.verifiedText = verifiedText

    local playerInfo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    playerInfo:SetPoint("TOPLEFT", verifiedText, "BOTTOMLEFT", 0, -6)
    f.playerInfo = playerInfo

    local mainInfo = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    mainInfo:SetPoint("TOPLEFT", playerInfo, "BOTTOMLEFT", 0, -6)
    f.mainInfo = mainInfo

    local charCount = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    charCount:SetPoint("TOPLEFT", mainInfo, "BOTTOMLEFT", 0, -6)
    f.charCount = charCount

    -- Separator 2
    local sep2 = f:CreateTexture(nil, "ARTWORK")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -265)
    sep2:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -265)
    sep2:SetColorTexture(0.5, 0.35, 0.1, 0.3)

    -- Quick Actions
    local actionsHeader = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionsHeader:SetPoint("TOPLEFT", f, "TOPLEFT", 30, -280)
    actionsHeader:SetText("|cFFDDB866Schnellzugriff|r")

    -- Open button (gold theme)
    local openBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    openBtn:SetSize(220, 32)
    openBtn:SetPoint("TOPLEFT", actionsHeader, "BOTTOMLEFT", 0, -10)
    openBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    openBtn:SetBackdropColor(0.4, 0.28, 0.05, 0.85)
    openBtn:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
    local openBtnText = openBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    openBtnText:SetPoint("CENTER")
    openBtnText:SetText("|cFFFFFFFFOneGuild Fenster oeffnen|r")
    openBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.55, 0.38, 0.08, 1)
        self:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
    end)
    openBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.4, 0.28, 0.05, 0.85)
        self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
    end)
    openBtn:SetScript("OnClick", function()
        OneGuild:ToggleMainWindow()
    end)

    -- Info box
    local infoBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    infoBox:SetSize(360, 80)
    infoBox:SetPoint("TOPLEFT", openBtn, "BOTTOMLEFT", 0, -16)
    infoBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    infoBox:SetBackdropColor(0.08, 0.04, 0.04, 0.8)
    infoBox:SetBackdropBorderColor(0.35, 0.25, 0.1, 0.4)

    local infoIcon = infoBox:CreateTexture(nil, "ARTWORK")
    infoIcon:SetSize(20, 20)
    infoIcon:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -10)
    infoIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    infoIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local infoTitle = infoBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    infoTitle:SetPoint("TOPLEFT", infoIcon, "TOPRIGHT", 8, -2)
    infoTitle:SetText("|cFFFFCC00Kommt bald...|r")

    local infoDesc = infoBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    infoDesc:SetPoint("TOPLEFT", infoBox, "TOPLEFT", 10, -38)
    infoDesc:SetPoint("TOPRIGHT", infoBox, "TOPRIGHT", -10, -38)
    infoDesc:SetText("|cFF8B7355Hier werden zukuenftig Gilden-Infos, Statistiken, " ..
        "Event-Uebersicht und mehr angezeigt. " ..
        "Dieser Tab wird automatisch mit neuen Features gefuellt.|r")
    infoDesc:SetJustifyH("LEFT")
    infoDesc:SetWordWrap(true)
    infoDesc:SetSpacing(2)

    f:Hide()
    tabContent = f
    return f
end

------------------------------------------------------------------------
-- Update dynamic content
------------------------------------------------------------------------
local function UpdateTabContent()
    if not tabContent then return end

    if OneGuild:IsAuthorized() then
        tabContent.verifiedText:SetText("|cFF66FF66Gilde verifiziert|r  --  " ..
            "|cFFFFD700<" .. (OneGuild.playerGuild or OneGuild.REQUIRED_GUILD) .. ">|r")
    else
        tabContent.verifiedText:SetText("|cFFFF4444Nicht verifiziert|r")
    end

    local name = UnitName("player") or "?"
    local realm = GetRealmName() or "?"
    local _, classFile = UnitClass("player")
    local className = UnitClass("player") or "?"
    local level = UnitLevel("player") or 0
    tabContent.playerInfo:SetText("|cFF8B7355Charakter:|r  " ..
        "|cFFFFFFFF" .. name .. "-" .. realm .. "|r  " ..
        "|cFF8B7355(Lvl " .. level .. " " .. className .. ")|r")

    if OneGuild.GetMainCharacter then
        local mainKey, mainChar = OneGuild:GetMainCharacter()
        if mainChar then
            tabContent.mainInfo:SetText("|cFF8B7355Main:|r  " ..
                "|cFFFFCC00" .. mainChar.name .. "-" .. mainChar.realm .. "|r")
        else
            tabContent.mainInfo:SetText("|cFF8B7355Main:|r  " ..
                "|cFFFFCC00Nicht gesetzt|r")
        end
    else
        tabContent.mainInfo:SetText("")
    end

    if OneGuild.GetCharacterCount then
        local count = OneGuild:GetCharacterCount()
        tabContent.charCount:SetText("|cFF8B7355Bekannte Charaktere:|r  " ..
            "|cFFDDB866" .. count .. "|r")
    else
        tabContent.charCount:SetText("")
    end
end

------------------------------------------------------------------------
-- Hook into CommunitiesFrame
------------------------------------------------------------------------
function OneGuild:HookCommunitiesFrame()
    if isHooked then return end
    isHooked = true

    OneGuild:Debug("Versuche CommunitiesFrame Tab zu erstellen...")

    local function TryHook()
        if not CommunitiesFrame then
            OneGuild:Debug("CommunitiesFrame noch nicht geladen -- warte...")
            return false
        end

        OneGuild:Debug("CommunitiesFrame gefunden! Erstelle Logo-Tab...")

        -- Find the last right-side tab to anchor below it
        local lastTab = nil
        local tabCandidates = {
            CommunitiesFrame.GuildInfoTab,
            CommunitiesFrame.GuildBenefitsTab,
            CommunitiesFrame.RosterTab,
            CommunitiesFrame.ChatTab,
        }
        -- Pick the lowest visible tab on screen
        local lowestY = 99999
        for _, tab in ipairs(tabCandidates) do
            if tab and tab:IsShown() then
                local _, y = tab:GetCenter()
                if y and y < lowestY then
                    lowestY = y
                    lastTab = tab
                end
            end
        end

        -- Fallback: scan children for CommunitiesFrameTab* named buttons
        if not lastTab then
            for _, child in pairs({CommunitiesFrame:GetChildren()}) do
                local cname = child:GetName() or ""
                if cname:find("Tab") and child.GetChecked and child:IsShown() then
                    local _, y = child:GetCenter()
                    if y and y < lowestY then
                        lowestY = y
                        lastTab = child
                    end
                end
            end
        end

        -- Guild logo icon button (below last tab, styled like native WoW tabs)
        local BTN_SIZE = 46
        local btn = CreateFrame("Button", "OneGuildCommunityTabBtn", CommunitiesFrame, "BackdropTemplate")
        btn:SetSize(BTN_SIZE, BTN_SIZE)
        btn:SetFrameLevel(CommunitiesFrame:GetFrameLevel() + 10)

        if lastTab then
            btn:SetPoint("TOP", lastTab, "BOTTOM", 0, -8)
        else
            btn:SetPoint("TOPRIGHT", CommunitiesFrame, "TOPRIGHT", -2, -280)
        end

        -- Dark background with gold border (matching addon theme)
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 12,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        btn:SetBackdropColor(0.06, 0.03, 0.03, 0.95)
        btn:SetBackdropBorderColor(0.6, 0.45, 0.1, 0.8)

        -- Inner icon container with rounded border (icon frame style)
        local iconSize = BTN_SIZE - 12
        local iconBg = btn:CreateTexture(nil, "BACKGROUND", nil, 1)
        iconBg:SetSize(iconSize + 4, iconSize + 4)
        iconBg:SetPoint("CENTER", btn, "CENTER", 0, 0)
        iconBg:SetColorTexture(0.12, 0.08, 0.04, 1)

        -- Logo texture
        local logoTex = btn:CreateTexture(nil, "ARTWORK")
        logoTex:SetSize(iconSize, iconSize)
        logoTex:SetPoint("CENTER", btn, "CENTER", 0, 0)
        logoTex:SetTexture("Interface\\AddOns\\OneGuild\\logo")

        -- Icon border overlay (standard WoW icon border)
        local iconBorder = btn:CreateTexture(nil, "OVERLAY")
        iconBorder:SetSize(iconSize + 6, iconSize + 6)
        iconBorder:SetPoint("CENTER", btn, "CENTER", 0, 0)
        iconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
        iconBorder:SetVertexColor(0.8, 0.6, 0.15, 0.9)

        -- Highlight overlay on hover
        local highlight = btn:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetSize(iconSize, iconSize)
        highlight:SetPoint("CENTER", btn, "CENTER", 0, 0)
        highlight:SetColorTexture(1, 0.72, 0, 0.2)

        -- Gold accent line at top
        local topAccent = btn:CreateTexture(nil, "OVERLAY", nil, 2)
        topAccent:SetHeight(2)
        topAccent:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
        topAccent:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
        topAccent:SetColorTexture(0.8, 0.6, 0.15, 0.7)

        -- Active indicator (gold underline when tab is open)
        local activeLine = btn:CreateTexture(nil, "OVERLAY", nil, 3)
        activeLine:SetSize(BTN_SIZE - 8, 3)
        activeLine:SetPoint("BOTTOM", btn, "BOTTOM", 0, 2)
        activeLine:SetColorTexture(1, 0.72, 0, 0.9)
        activeLine:Hide()
        btn.activeLine = activeLine

        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine("|cFFFFB800OneGuild|r", 1, 1, 1)
            GameTooltip:AddLine("Klicke um OneGuild zu oeffnen", 0.7, 0.7, 0.7)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function(self)
            GameTooltip:Hide()
        end)

        btn:SetScript("OnClick", function()
            OneGuild:Debug("Communities Logo-Button: Oeffne OneGuild Fenster")
            if OneGuild.ToggleMainWindow then
                OneGuild:ToggleMainWindow()
            end
        end)

        CommunitiesFrame:HookScript("OnHide", function()
            -- nothing needed since we now open main window directly
        end)

        tabButton = btn

        -- Re-anchor when CommunitiesFrame is shown (tabs may appear later)
        CommunitiesFrame:HookScript("OnShow", function()
            C_Timer.After(0.1, function()
                if not CommunitiesFrame then return end
                local best = nil
                local bestY = 99999
                local candidates = {
                    CommunitiesFrame.GuildInfoTab,
                    CommunitiesFrame.GuildBenefitsTab,
                    CommunitiesFrame.RosterTab,
                    CommunitiesFrame.ChatTab,
                }
                for _, tab in ipairs(candidates) do
                    if tab and tab:IsShown() then
                        local _, y = tab:GetCenter()
                        if y and y < bestY then
                            bestY = y
                            best = tab
                        end
                    end
                end
                if not best then
                    for _, child in pairs({CommunitiesFrame:GetChildren()}) do
                        local cname = child:GetName() or ""
                        if cname:find("Tab") and child.GetChecked and child:IsShown() then
                            local _, y = child:GetCenter()
                            if y and y < bestY then
                                bestY = y
                                best = child
                            end
                        end
                    end
                end
                if best then
                    btn:ClearAllPoints()
                    btn:SetPoint("TOP", best, "BOTTOM", 0, -8)
                end
            end)
        end)

        OneGuild:Debug("|cFF66FF66Communities Logo-Tab erfolgreich erstellt!|r")
        return true
    end

    if CommunitiesFrame then
        TryHook()
    else
        local hookFrame = CreateFrame("Frame")
        hookFrame:RegisterEvent("ADDON_LOADED")
        hookFrame:SetScript("OnEvent", function(self, event, addonName)
            if addonName == "Blizzard_Communities" then
                OneGuild:Debug("Blizzard_Communities geladen!")
                C_Timer.After(0.1, function()
                    TryHook()
                end)
                self:UnregisterEvent("ADDON_LOADED")
            end
        end)
        OneGuild:Debug("Blizzard_Communities noch nicht geladen -- warte auf Load-on-Demand")
    end
end
