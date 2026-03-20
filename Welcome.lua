------------------------------------------------------------------------
-- OneGuild - Welcome.lua
-- Modern animated welcome screen with guild logo (gold/bronze theme)
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Welcome.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local welcomeFrame = nil

------------------------------------------------------------------------
-- Helper: Smooth fade-in
------------------------------------------------------------------------
local function FadeIn(frame, delay, duration)
    frame:SetAlpha(0)
    C_Timer.After(delay, function()
        if not frame or not frame.SetAlpha then return end
        local elapsed = 0
        local ticker
        ticker = C_Timer.NewTicker(0.016, function()
            elapsed = elapsed + 0.016
            local progress = math.min(elapsed / duration, 1)
            local alpha = 1 - (1 - progress) ^ 3
            if frame and frame.SetAlpha then
                frame:SetAlpha(alpha)
            end
            if progress >= 1 and ticker then
                ticker:Cancel()
            end
        end)
    end)
end

------------------------------------------------------------------------
-- Helper: Animated slide-in from bottom
------------------------------------------------------------------------
local function SlideIn(frame, delay, duration, distance)
    local startY = -(distance or 20)
    frame:SetAlpha(0)
    C_Timer.After(delay, function()
        if not frame or not frame.SetAlpha then return end
        local elapsed = 0
        local ticker
        ticker = C_Timer.NewTicker(0.016, function()
            elapsed = elapsed + 0.016
            local progress = math.min(elapsed / duration, 1)
            local alpha = 1 - (1 - progress) ^ 3
            local yOff = startY * (1 - alpha)
            if frame and frame.SetAlpha then
                frame:SetAlpha(alpha)
                if frame._slideAnchor then
                    frame:ClearAllPoints()
                    frame:SetPoint(
                        frame._slideAnchor.point,
                        frame._slideAnchor.relativeTo,
                        frame._slideAnchor.relativePoint,
                        frame._slideAnchor.x,
                        frame._slideAnchor.y + yOff
                    )
                end
            end
            if progress >= 1 and ticker then
                ticker:Cancel()
            end
        end)
    end)
end

------------------------------------------------------------------------
-- Helper: Create a feature card (gold/bronze theme)
------------------------------------------------------------------------
local function CreateFeatureCard(parent, icon, title, desc, xOff, yOff, delay)
    local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    card:SetSize(180, 110)
    card:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropColor(0.12, 0.06, 0.04, 0.85)
    card:SetBackdropBorderColor(0.5, 0.35, 0.08, 0.4)

    card:EnableMouse(true)
    card:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.18, 0.10, 0.04, 0.95)
        self:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
    end)
    card:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.12, 0.06, 0.04, 0.85)
        self:SetBackdropBorderColor(0.5, 0.35, 0.08, 0.4)
    end)

    -- Icon
    local iconTex = card:CreateTexture(nil, "ARTWORK")
    iconTex:SetSize(28, 28)
    iconTex:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -10)
    iconTex:SetTexture(icon)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Title
    local titleText = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, -2)
    titleText:SetText("|cFFFFD700" .. title .. "|r")

    -- Desc
    local descText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    descText:SetPoint("TOPLEFT", card, "TOPLEFT", 12, -46)
    descText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -46)
    descText:SetText("|cFFBBA050" .. desc .. "|r")
    descText:SetJustifyH("LEFT")
    descText:SetWordWrap(true)
    descText:SetSpacing(2)

    card:SetPoint("TOPLEFT", parent, "TOPLEFT", xOff, yOff)

    card._slideAnchor = {
        point = "TOPLEFT",
        relativeTo = parent,
        relativePoint = "TOPLEFT",
        x = xOff,
        y = yOff,
    }

    SlideIn(card, delay, 0.5, 30)
    return card
end

------------------------------------------------------------------------
-- Show Welcome Screen
------------------------------------------------------------------------
function OneGuild:ShowWelcomeScreen()
    if welcomeFrame then
        welcomeFrame:Show()
        return
    end

    -- Full-screen overlay
    local overlay = CreateFrame("Frame", "OneGuildWelcome", UIParent, "BackdropTemplate")
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(500)
    overlay:EnableMouse(true)

    -- Dark background
    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.02, 0.01, 0.01, 0.88)

    -- Main content container
    local container = CreateFrame("Frame", nil, overlay, "BackdropTemplate")
    container:SetSize(640, 680)
    container:SetPoint("CENTER", overlay, "CENTER", 0, 10)
    container:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    container:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
    container:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.7)

    -- Top accent line (gold)
    local accentTop = container:CreateTexture(nil, "ARTWORK", nil, 2)
    accentTop:SetHeight(2)
    accentTop:SetPoint("TOPLEFT", container, "TOPLEFT", 4, -4)
    accentTop:SetPoint("TOPRIGHT", container, "TOPRIGHT", -4, -4)
    accentTop:SetColorTexture(0.8, 0.6, 0.1, 0.8)

    -- ===== GUILD LOGO =====
    local logo = container:CreateTexture(nil, "ARTWORK")
    logo:SetSize(256, 128)
    logo:SetPoint("TOP", container, "TOP", 0, -14)
    logo:SetTexture("Interface\\AddOns\\OneGuild\\logo")
    FadeIn(logo, 0.2, 0.8)

    -- Title: "OneGuild"
    local title = container:CreateFontString(nil, "OVERLAY")
    title:SetPoint("TOP", logo, "BOTTOM", 0, -4)
    title:SetFont("Fonts\\FRIZQT__.TTF", 26, "OUTLINE")
    title:SetText("|cFFFFB800O|r|cFFFFCC33n|r|cFFFFDD55e|r|cFFFFD700Guild|r")
    FadeIn(title, 0.5, 0.5)

    -- Subtitle
    local subtitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -2)
    subtitle:SetText("|cFFFFD700<" .. OneGuild.REQUIRED_GUILD .. ">|r  |cFF8B7355Guild Management Suite|r")
    FadeIn(subtitle, 0.7, 0.5)

    -- Version badge
    local versionBadge = CreateFrame("Frame", nil, container, "BackdropTemplate")
    versionBadge:SetSize(70, 20)
    versionBadge:SetPoint("TOP", subtitle, "BOTTOM", 0, -4)
    versionBadge:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    versionBadge:SetBackdropColor(0.3, 0.2, 0.05, 0.6)
    versionBadge:SetBackdropBorderColor(0.6, 0.45, 0.1, 0.4)
    local versionText = versionBadge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    versionText:SetPoint("CENTER")
    versionText:SetText("|cFFDDB866v" .. OneGuild.VERSION .. "|r")
    FadeIn(versionBadge, 0.8, 0.4)

    -- Separator line
    local sep = container:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", container, "TOPLEFT", 30, -230)
    sep:SetPoint("TOPRIGHT", container, "TOPRIGHT", -30, -230)
    sep:SetColorTexture(0.5, 0.35, 0.1, 0.3)

    -- Feature cards area
    local cardsArea = CreateFrame("Frame", nil, container)
    cardsArea:SetPoint("TOPLEFT", container, "TOPLEFT", 15, -245)
    cardsArea:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", -15, 80)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\INV_Misc_GroupLooking",
        "Mitglieder",
        "Alle Mitglieder auf einen Blick mit DKP & Details.",
        0, 0, 0.9)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\INV_Misc_Note_01",
        "Event-Planer",
        "Raids & Events planen mit Zu- und Absage-System.",
        195, 0, 1.1)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\INV_Letter_15",
        "Notizen & MOTD",
        "Gilden-Notizen erstellen und MOTD im Blick behalten.",
        390, 0, 1.3)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\Achievement_Character_Human_Male",
        "Meine Chars",
        "Alle Charaktere automatisch erfassen & Main festlegen.",
        0, -125, 1.5)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc",
        "Gilde & Communitys",
        "Eigener Tab im Gilden-Fenster (J) fuer schnellen Zugriff.",
        195, -125, 1.7)

    CreateFeatureCard(cardsArea,
        "Interface\\Icons\\Spell_Holy_ChampionsBond",
        "Exklusiv <" .. OneGuild.REQUIRED_GUILD .. ">",
        "Guild-Lock: Nur fuer Mitglieder deiner Gilde.",
        390, -125, 1.9)

    -- ===== CHANGELOG WITH TABS =====
    local changelogSep = container:CreateTexture(nil, "ARTWORK")
    changelogSep:SetHeight(1)
    changelogSep:SetPoint("TOPLEFT", container, "TOPLEFT", 30, -500)
    changelogSep:SetPoint("TOPRIGHT", container, "TOPRIGHT", -30, -500)
    changelogSep:SetColorTexture(0.5, 0.35, 0.1, 0.3)

    local changelogTitle = container:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    changelogTitle:SetPoint("TOP", changelogSep, "BOTTOM", 0, -8)
    changelogTitle:SetText("|cFFFFD700Changelog|r")
    FadeIn(changelogTitle, 2.0, 0.5)

    -- Changelog data per version
    local changelogData = {
        { version = "v1.4.2", entries = {
            "Shop: Gold/Silber/Kupfer Icons statt g/s/c",
            "NEU: Design-Tab in Einstellungen",
            "Effekte an/aus schaltbar",
            "Partikel-Anzahl einstellbar (0-64)",
            "Glow-Farbe waehlbar (6 Presets)",
        }},
        { version = "v1.4.1", entries = {
            "FIX: Effekte werden jetzt beim Oeffnen angewendet",
            "NEU: Diagonaler Shine-Sweep ueber das Fenster",
            "NEU: Animierte Progress-Bar unter dem Header",
            "NEU: Pulsierende Header-Shine-Balken",
            "Border-Shimmer & Partikel deutlich sichtbarer",
            "Goldene Partikel groesser & heller",
        }},
        { version = "v1.4.0", entries = {
            "Premium UI Effekte: Animierte Border-Shimmer",
            "Gleitender Tab-Indikator mit Glow",
            "Button Hover-Glow & Click-Flash Animationen",
            "Goldene Partikel-Effekte im Hintergrund",
            "Automatisches Dialog-Styling",
        }},
        { version = "v1.3.1", entries = {
            "Shop: Drag & Drop Items aus dem Inventar",
            "Shop: Preis in Gold / Silber / Kupfer",
            "Shop: Item-Icon & Link in Angeboten",
        }},
        { version = "v1.3.0", entries = {
            "Gilden-Shop: Items an Gildenmitglieder verkaufen",
            "Versteckte Auktions-Gebote (nur Auktionator sieht Details)",
            "Gilden-Notizen Sync an alle Online-Mitglieder",
            "DKP History: Loeschen & Export Buttons",
        }},
        { version = "v1.2.9", entries = {
            "Gilden-Notizen: Echtzeit-Broadcast an alle Online-Mitglieder",
        }},
        { version = "v1.2.x", entries = {
            "DKP Bestaetigungsdialog vor jeder Aenderung",
            "Dual-Channel DKP Sync (GUILD + RAID/PARTY)",
            "Triple-Send & Batch-Nachrichten",
            "Farb-codiertes DKP Log im Chat",
            "30s Auto-Sync fuer DKP Daten",
        }},
    }

    -- Tab buttons container
    local tabBar = CreateFrame("Frame", nil, container)
    tabBar:SetHeight(22)
    tabBar:SetPoint("TOPLEFT", changelogTitle, "BOTTOMLEFT", -60, -8)
    tabBar:SetPoint("TOPRIGHT", changelogTitle, "BOTTOMRIGHT", 60, -8)
    FadeIn(tabBar, 2.05, 0.5)

    -- Body text
    local changelogBody = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    changelogBody:SetPoint("TOP", tabBar, "BOTTOM", 0, -8)
    changelogBody:SetPoint("LEFT", container, "LEFT", 60, 0)
    changelogBody:SetPoint("RIGHT", container, "RIGHT", -60, 0)
    changelogBody:SetJustifyH("LEFT")
    changelogBody:SetWordWrap(true)
    changelogBody:SetSpacing(3)
    FadeIn(changelogBody, 2.1, 0.5)

    -- Create version tabs
    local clTabs = {}
    local tabWidth = 70
    local tabGap = 4
    local totalWidth = #changelogData * tabWidth + (#changelogData - 1) * tabGap
    local startX = -totalWidth / 2

    local function ShowChangelogVersion(idx)
        local data = changelogData[idx]
        if not data then return end
        local lines = {}
        for _, e in ipairs(data.entries) do
            table.insert(lines, "|cFF66FF66+|r " .. e)
        end
        changelogBody:SetText(table.concat(lines, "\n"))
        -- Update tab highlights
        for i, t in ipairs(clTabs) do
            if i == idx then
                t:SetBackdropColor(0.5, 0.35, 0.05, 0.9)
                t:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
                t.text:SetText("|cFFFFFFFF" .. changelogData[i].version .. "|r")
            else
                t:SetBackdropColor(0.12, 0.12, 0.18, 0.8)
                t:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.5)
                t.text:SetText("|cFF888888" .. changelogData[i].version .. "|r")
            end
        end
    end

    for i, vData in ipairs(changelogData) do
        local tab = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
        tab:SetSize(tabWidth, 20)
        tab:SetPoint("LEFT", tabBar, "CENTER", startX + (i - 1) * (tabWidth + tabGap), 0)
        tab:RegisterForClicks("AnyUp")
        tab:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        tab:SetBackdropColor(0.12, 0.12, 0.18, 0.8)
        tab:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.5)
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tabText:SetPoint("CENTER")
        tabText:SetText("|cFF888888" .. vData.version .. "|r")
        tab.text = tabText
        tab:SetScript("OnEnter", function(self)
            if self.active then return end
            self:SetBackdropColor(0.25, 0.2, 0.08, 0.9)
        end)
        tab:SetScript("OnLeave", function(self)
            if self.active then return end
            self:SetBackdropColor(0.12, 0.12, 0.18, 0.8)
        end)
        local idx = i
        tab:SetScript("OnClick", function()
            for _, t in ipairs(clTabs) do t.active = false end
            tab.active = true
            ShowChangelogVersion(idx)
        end)
        clTabs[i] = tab
    end

    -- Show first tab (latest) by default
    clTabs[1].active = true
    ShowChangelogVersion(1)

    -- Bottom area
    local bottomBar = CreateFrame("Frame", nil, container)
    bottomBar:SetHeight(70)
    bottomBar:SetPoint("BOTTOMLEFT", container, "BOTTOMLEFT", 0, 0)
    bottomBar:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

    -- "Los geht's" button (gold)
    local startBtn = CreateFrame("Button", nil, bottomBar, "BackdropTemplate")
    startBtn:SetSize(180, 36)
    startBtn:SetPoint("TOP", bottomBar, "TOP", 0, -4)
    startBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    startBtn:SetBackdropColor(0.5, 0.35, 0.05, 0.95)
    startBtn:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)

    local btnText = startBtn:CreateFontString(nil, "OVERLAY")
    btnText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    btnText:SetPoint("CENTER")
    btnText:SetText("|cFFFFFFFFLos geht's!|r")

    startBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.65, 0.45, 0.08, 1)
        self:SetBackdropBorderColor(1, 0.8, 0.2, 1)
    end)
    startBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.35, 0.05, 0.95)
        self:SetBackdropBorderColor(0.8, 0.6, 0.1, 0.8)
    end)
    startBtn:SetScript("OnClick", function()
        OneGuild:DismissWelcome()
    end)
    FadeIn(startBtn, 2.2, 0.6)

    -- "Nicht mehr anzeigen" checkbox
    local dontShow = CreateFrame("CheckButton", "OneGuildWelcomeDontShow", bottomBar, "UICheckButtonTemplate")
    dontShow:SetSize(20, 20)
    dontShow:SetPoint("BOTTOM", bottomBar, "BOTTOM", -50, 2)
    dontShow:SetChecked(true)
    local dontShowLabel = bottomBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    dontShowLabel:SetPoint("LEFT", dontShow, "RIGHT", 2, 0)
    dontShowLabel:SetText("|cFF8B7355Nicht mehr anzeigen|r")
    FadeIn(dontShow, 2.4, 0.4)
    FadeIn(dontShowLabel, 2.4, 0.4)

    dontShow.isChecked = true
    dontShow:SetScript("OnClick", function(self)
        self.isChecked = self:GetChecked()
    end)
    overlay.dontShowCheck = dontShow

    FadeIn(overlay, 0, 0.4)

    welcomeFrame = overlay
    table.insert(UISpecialFrames, "OneGuildWelcome")
end

------------------------------------------------------------------------
-- Dismiss welcome screen
------------------------------------------------------------------------
function OneGuild:DismissWelcome()
    if welcomeFrame then
        local elapsed = 0
        local ticker
        ticker = C_Timer.NewTicker(0.016, function()
            elapsed = elapsed + 0.016
            local progress = math.min(elapsed / 0.3, 1)
            if welcomeFrame and welcomeFrame.SetAlpha then
                welcomeFrame:SetAlpha(1 - progress)
            end
            if progress >= 1 then
                if ticker then ticker:Cancel() end
                if welcomeFrame then
                    welcomeFrame:Hide()
                end
            end
        end)

        if self.db and welcomeFrame.dontShowCheck and welcomeFrame.dontShowCheck.isChecked then
            self.db.welcomeDismissedVersion = self.VERSION
        end
    end
end

------------------------------------------------------------------------
-- Check if welcome should be shown
------------------------------------------------------------------------
function OneGuild:ShouldShowWelcome()
    if not self.db then return false end
    local dismissed = self.db.welcomeDismissedVersion or ""
    return dismissed ~= self.VERSION
end
