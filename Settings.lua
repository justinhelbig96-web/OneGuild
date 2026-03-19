------------------------------------------------------------------------
-- OneGuild  -  Settings.lua
-- Options window with tabbed categories (gear icon in title bar)
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Settings.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SETTINGS_W   = 460
local SETTINGS_H   = 380
local TAB_BTN_W    = 120
local TAB_BTN_H    = 28
local CONTENT_PAD  = 14

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local settingsFrame  = nil
local settingsTabs   = {}       -- { [index] = { btn, content } }
local currentSettTab = 1

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function Label(parent, x, y, text, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", size or 12, "")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(r or 1, g or 0.84, b or 0)
    fs:SetText(text)
    return fs
end

local function HLine(parent, y)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, y)
    t:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, y)
    t:SetColorTexture(0.55, 0.41, 0.08, 0.5)
    return t
end

------------------------------------------------------------------------
-- Generic checkbox builder
------------------------------------------------------------------------
local function MakeCheckbox(parent, x, y, labelText, tooltip, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    cb:SetSize(26, 26)
    cb:SetChecked(getter())

    local fs = cb:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetTextColor(0.87, 0.78, 0.55)
    fs:SetText(labelText)

    cb:SetScript("OnClick", function(self)
        local val = self:GetChecked()
        setter(val)
    end)

    if tooltip then
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    return cb
end

------------------------------------------------------------------------
-- Generic slider builder
------------------------------------------------------------------------
local function MakeSlider(parent, x, y, labelText, minVal, maxVal, step, getter, setter)
    -- Label
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetTextColor(0.87, 0.78, 0.55)
    fs:SetText(labelText)

    -- Current value text
    local valText = parent:CreateFontString(nil, "OVERLAY")
    valText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    valText:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    valText:SetTextColor(1, 0.72, 0)

    -- Slider
    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y - 20)
    slider:SetSize(260, 16)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetValue(getter())
    slider.Low:SetText(tostring(minVal))
    slider.High:SetText(tostring(maxVal))

    valText:SetText(tostring(math.floor(getter())))

    slider:SetScript("OnValueChanged", function(self, val)
        val = math.floor(val + 0.5)
        valText:SetText(tostring(val))
        setter(val)
    end)

    return slider
end

------------------------------------------------------------------------
--                     TAB: GuildMap
------------------------------------------------------------------------
local function BuildGuildMapTab(content)
    Label(content, 0, 0, "GuildMap Einstellungen", 14, 1, 0.72, 0)
    HLine(content, -22)

    -- Pins anzeigen (sichtbarkeit)
    MakeCheckbox(content, 0, -34,
        "Mitglieder-Pins auf Weltkarte anzeigen",
        "Deine Position wird weiter geteilt — du siehst\n"
            .. "aber keine Pins anderer Spieler auf der Karte.",
        function()
            return OneGuild.db.settings.mapShowPins ~= false
        end,
        function(val)
            OneGuild.db.settings.mapShowPins = val
            if OneGuild.SetMapPinsEnabled then
                OneGuild:SetMapPinsEnabled(val)
            end
        end
    )

    -- Namen anzeigen
    MakeCheckbox(content, 0, -68,
        "Spielernamen unter Pins anzeigen",
        "Blendet die Namens-Labels unter den Pins ein/aus.",
        function()
            return OneGuild.db.settings.mapShowNames ~= false
        end,
        function(val)
            OneGuild.db.settings.mapShowNames = val
            if OneGuild.RefreshPinAppearance then
                OneGuild:RefreshPinAppearance()
            end
        end
    )

    -- Pin-Größe
    MakeSlider(content, 0, -110,
        "Pin-Größe:",
        8, 32, 2,
        function()
            return OneGuild.db.settings.mapPinSize or 16
        end,
        function(val)
            OneGuild.db.settings.mapPinSize = val
            if OneGuild.RefreshPinAppearance then
                OneGuild:RefreshPinAppearance()
            end
        end
    )

    -- Label-Größe
    MakeSlider(content, 0, -180,
        "Label-Größe:",
        8, 16, 1,
        function()
            return OneGuild.db.settings.mapLabelSize or 10
        end,
        function(val)
            OneGuild.db.settings.mapLabelSize = val
            if OneGuild.RefreshPinAppearance then
                OneGuild:RefreshPinAppearance()
            end
        end
    )

    -- Pin-Transparenz
    MakeSlider(content, 0, -250,
        "Pin-Deckkraft:",
        0.2, 1.0, 0.1,
        function()
            return OneGuild.db.settings.mapPinAlpha or 0.9
        end,
        function(val)
            OneGuild.db.settings.mapPinAlpha = val
            if OneGuild.RefreshPinAppearance then
                OneGuild:RefreshPinAppearance()
            end
        end
    )
end

------------------------------------------------------------------------
--                     TAB: Allgemein (placeholder for future)
------------------------------------------------------------------------
local function BuildGeneralTab(content)
    Label(content, 0, 0, "Allgemeine Einstellungen", 14, 1, 0.72, 0)
    HLine(content, -22)

    -- Sound Alerts
    MakeCheckbox(content, 0, -34,
        "Sound-Benachrichtigungen",
        "Spielt Sounds bei wichtigen Ereignissen ab.",
        function()
            return OneGuild.db.settings.soundAlerts ~= false
        end,
        function(val)
            OneGuild.db.settings.soundAlerts = val
        end
    )

    -- Open on login
    MakeCheckbox(content, 0, -68,
        "Fenster beim Login öffnen",
        "Öffnet das OneGuild-Fenster automatisch beim Einloggen.",
        function()
            return OneGuild.db.settings.openOnLogin == true
        end,
        function(val)
            OneGuild.db.settings.openOnLogin = val
        end
    )
end

------------------------------------------------------------------------
-- TAB DEFINITIONS — add new tabs here
------------------------------------------------------------------------
------------------------------------------------------------------------
--                     TAB: Loot-System
------------------------------------------------------------------------
local function BuildLootTab(content)
    Label(content, 0, 0, "Loot-System Einstellungen", 14, 1, 0.72, 0)
    HLine(content, -22)

    -- Auto-Pass checkbox
    MakeCheckbox(content, 0, -34,
        "Auto-Pass im Gilden-Raid",
        "Wenn aktiviert, wird bei Loot-Drops automatisch\n"
            .. "'Passen' gewählt. Nur der Raid Leader erhält Items\n"
            .. "und verteilt sie per DKP-Auktion.",
        function()
            return OneGuild.db.settings.lootAutoPass ~= false
        end,
        function(val)
            OneGuild.db.settings.lootAutoPass = val
            if not val and OneGuild.DeactivateLootSystem then
                OneGuild:DeactivateLootSystem()
            end
        end
    )

    -- Info text
    local info1 = content:CreateFontString(nil, "OVERLAY")
    info1:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    info1:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -80)
    info1:SetWidth(280)
    info1:SetJustifyH("LEFT")
    info1:SetTextColor(0.6, 0.5, 0.35)
    info1:SetText(
        "So funktioniert das Loot-System:\n\n" ..
        "|cFFDDB8661.|r Der Raid Leader startet den |cFFFFD700Addon-Check|r\n" ..
        "    um sicherzustellen, dass alle das Addon haben.\n\n" ..
        "|cFFDDB8662.|r Nach erfolgreichem Check wird das\n" ..
        "    |cFFFFD700Loot-System aktiviert|r.\n\n" ..
        "|cFFDDB8663.|r Bei jedem Loot-Drop: Alle passen automatisch,\n" ..
        "    nur der RL bekommt das Item.\n\n" ..
        "|cFFDDB8664.|r Der RL verteilt Items per DKP-Auktion."
    )

    -- Raid Groups button
    local raidGroupsBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    raidGroupsBtn:SetSize(200, 28)
    raidGroupsBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -280)
    raidGroupsBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    raidGroupsBtn:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
    raidGroupsBtn:SetBackdropBorderColor(0.4, 0.3, 0.6, 0.6)

    local raidGroupsBtnText = raidGroupsBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    raidGroupsBtnText:SetPoint("CENTER")
    raidGroupsBtnText:SetText("|cFF8888FFRaid Gruppen öffnen|r")

    raidGroupsBtn:SetScript("OnClick", function()
        if OneGuild.ToggleRaidGroups then
            OneGuild:ToggleRaidGroups()
        end
    end)
    raidGroupsBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.2, 0.15, 0.4, 1)
    end)
    raidGroupsBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.15, 0.1, 0.3, 0.8)
    end)
end

------------------------------------------------------------------------
-- TAB DEFINITIONS — add new tabs here
------------------------------------------------------------------------
local TAB_DEFS = {
    { name = "Allgemein",  builder = BuildGeneralTab },
    { name = "GuildMap",   builder = BuildGuildMapTab },
    { name = "Loot",       builder = BuildLootTab },
}

------------------------------------------------------------------------
-- Show / switch tabs within the settings window
------------------------------------------------------------------------
local function ShowSettingsTab(index)
    currentSettTab = index
    for i, tab in ipairs(settingsTabs) do
        if i == index then
            tab.content:Show()
            tab.btn:SetBackdropColor(0.55, 0.35, 0.05, 1)
            tab.btn:SetBackdropBorderColor(0.9, 0.6, 0.1, 0.9)
        else
            tab.content:Hide()
            tab.btn:SetBackdropColor(0.18, 0.10, 0.04, 0.9)
            tab.btn:SetBackdropBorderColor(0.5, 0.3, 0.1, 0.5)
        end
    end
end

------------------------------------------------------------------------
--                 BUILD THE SETTINGS WINDOW
------------------------------------------------------------------------
function OneGuild:BuildSettingsFrame()
    if settingsFrame then return settingsFrame end

    local f = CreateFrame("Frame", "OneGuildSettingsFrame", UIParent, "BackdropTemplate")
    f:SetSize(SETTINGS_W, SETTINGS_H)
    f:SetPoint("CENTER", UIParent, "CENTER", 200, 0)
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
    f:SetBackdropColor(0.08, 0.04, 0.04, 0.97)
    f:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.8)

    -- Title bar (draggable)
    local titleBar = CreateFrame("Frame", nil, f)
    titleBar:SetHeight(36)
    titleBar:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() f:StartMoving() end)
    titleBar:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    -- Title text
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -10)
    title:SetText(OneGuild.COLORS.TITLE .. "OneGuild|r  " ..
        OneGuild.COLORS.MUTED .. "Einstellungen|r")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, titleBar, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Tab button strip (left side)
    local tabStrip = CreateFrame("Frame", nil, f)
    tabStrip:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -40)
    tabStrip:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    tabStrip:SetWidth(TAB_BTN_W)

    -- Content area
    local contentBg = CreateFrame("Frame", nil, f, "BackdropTemplate")
    contentBg:SetPoint("TOPLEFT", tabStrip, "TOPRIGHT", 6, 0)
    contentBg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 10)
    contentBg:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    contentBg:SetBackdropColor(0.06, 0.03, 0.03, 0.8)
    contentBg:SetBackdropBorderColor(0.5, 0.35, 0.08, 0.6)

    -- Create tabs
    settingsTabs = {}
    for i, def in ipairs(TAB_DEFS) do
        -- Tab button
        local btn = CreateFrame("Button", nil, tabStrip, "BackdropTemplate")
        btn:SetSize(TAB_BTN_W, TAB_BTN_H)
        btn:SetPoint("TOPLEFT", tabStrip, "TOPLEFT", 0, -((i - 1) * (TAB_BTN_H + 4)))
        btn:RegisterForClicks("AnyUp")
        btn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })

        local btnLabel = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        btnLabel:SetPoint("CENTER")
        btnLabel:SetText("|cFFDDB866" .. def.name .. "|r")

        btn:SetScript("OnClick", function() ShowSettingsTab(i) end)
        btn:SetScript("OnEnter", function(self)
            if currentSettTab ~= i then
                self:SetBackdropColor(0.30, 0.18, 0.06, 1)
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if currentSettTab ~= i then
                self:SetBackdropColor(0.18, 0.10, 0.04, 0.9)
                self:SetBackdropBorderColor(0.5, 0.3, 0.1, 0.5)
            end
        end)

        -- Content pane
        local content = CreateFrame("Frame", nil, contentBg)
        content:SetPoint("TOPLEFT", contentBg, "TOPLEFT", CONTENT_PAD, -CONTENT_PAD)
        content:SetPoint("BOTTOMRIGHT", contentBg, "BOTTOMRIGHT", -CONTENT_PAD, CONTENT_PAD)

        -- Build tab content
        def.builder(content)

        settingsTabs[i] = { btn = btn, content = content }
    end

    ShowSettingsTab(1)

    f:Hide()
    settingsFrame = f
    return f
end

------------------------------------------------------------------------
-- Toggle settings window
------------------------------------------------------------------------
function OneGuild:ToggleSettings()
    local f = self:BuildSettingsFrame()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
    end
end
