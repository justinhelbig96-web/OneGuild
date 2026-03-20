------------------------------------------------------------------------
-- OneGuild  -  Settings.lua
-- Options window with tabbed categories (gear icon in title bar)
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Settings.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local SETTINGS_W   = 470
local SETTINGS_H   = 510
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
--                     TAB: Berechtigungen (Permissions)
------------------------------------------------------------------------
local DKP_PERM_OPTIONS = {
    { value = "leader",   label = "Nur Gildenleitung",        desc = "Nur Rang 0 (Gildenmeister) + Whitelist" },
    { value = "officer",  label = "Offiziere",                desc = "Rang 0 + 1 (Offiziere) + Whitelist" },
    { value = "raidlead", label = "Offiziere + Raidleiter",   desc = "Offiziere + RL/Assist im Raid + Whitelist" },
    { value = "all",      label = "Alle Gildenmitglieder",    desc = "Jedes Gildenmitglied kann DKP bearbeiten" },
}

local permRadioButtons = {}

local function BuildPermissionsTab(content)
    Label(content, 0, 0, "Berechtigungen", 14, 1, 0.72, 0)
    HLine(content, -20)

    local currentPerm = (OneGuild.db and OneGuild.db.settings and OneGuild.db.settings.dkpPermission) or "officer"
    local canEdit = OneGuild.CanEditPermissions and OneGuild:CanEditPermissions() or false

    -- Warning if not allowed (compact, one line)
    local yStart = -30
    if not canEdit then
        local warningText = content:CreateFontString(nil, "OVERLAY")
        warningText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        warningText:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -28)
        warningText:SetWidth(290)
        warningText:SetJustifyH("LEFT")
        warningText:SetTextColor(1, 0.3, 0.3)
        warningText:SetText("Keine Berechtigung \226\128\147 nur Rang 0/1 und Whitelist.")
        yStart = -44
    end

    Label(content, 0, yStart, "Wer darf DKP bearbeiten / verteilen?", 11, 0.87, 0.78, 0.55)

    permRadioButtons = {}
    for i, opt in ipairs(DKP_PERM_OPTIONS) do
        local yOff = (yStart - 20) - ((i - 1) * 42)

        local radioBtn = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
        radioBtn:SetPoint("TOPLEFT", content, "TOPLEFT", 4, yOff)
        radioBtn:SetSize(22, 22)
        radioBtn:SetChecked(currentPerm == opt.value)

        local radioLabel = radioBtn:CreateFontString(nil, "OVERLAY")
        radioLabel:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        radioLabel:SetPoint("LEFT", radioBtn, "RIGHT", 4, 0)

        local descLabel = content:CreateFontString(nil, "OVERLAY")
        descLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        descLabel:SetPoint("TOPLEFT", radioBtn, "BOTTOMLEFT", 26, -1)

        if not canEdit then
            radioBtn:Disable()
            radioBtn:SetAlpha(0.4)
            radioLabel:SetTextColor(0.4, 0.35, 0.2)
            descLabel:SetTextColor(0.3, 0.25, 0.15)
        else
            radioLabel:SetTextColor(1, 0.84, 0)
            descLabel:SetTextColor(0.6, 0.5, 0.35)
        end
        radioLabel:SetText(opt.label)
        descLabel:SetText(opt.desc)

        radioBtn:SetScript("OnClick", function()
            if not OneGuild:CanEditPermissions() then
                radioBtn:SetChecked(currentPerm == opt.value)
                OneGuild:Print("|cFFFF4444Du hast keine Berechtigung, dies zu \195\164ndern.|r")
                return
            end
            for _, rb in ipairs(permRadioButtons) do
                rb.btn:SetChecked(false)
            end
            radioBtn:SetChecked(true)
            OneGuild.db.settings.dkpPermission = opt.value
            currentPerm = opt.value
            OneGuild:PrintSuccess("DKP-Berechtigung ge\195\164ndert: " .. opt.label)
        end)

        table.insert(permRadioButtons, { btn = radioBtn, value = opt.value })
    end

    -- ================================================================
    -- WHITELIST SECTION
    -- ================================================================
    local wlTop = (yStart - 20) - (4 * 42) - 10  -- after 4 radio buttons + gap
    HLine(content, wlTop)
    Label(content, 0, wlTop - 8, "Admin-Whitelist", 13, 1, 0.72, 0)

    local canEditWL = OneGuild.CanEditWhitelist and OneGuild:CanEditWhitelist() or false

    local wlInfoText = content:CreateFontString(nil, "OVERLAY")
    wlInfoText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    wlInfoText:SetPoint("TOPLEFT", content, "TOPLEFT", 4, wlTop - 26)
    wlInfoText:SetWidth(290)
    wlInfoText:SetJustifyH("LEFT")
    if canEditWL then
        wlInfoText:SetTextColor(0.6, 0.5, 0.35)
        wlInfoText:SetText("Whitelist = immer Admin-Rechte. Nur Gildenmeister kann bearbeiten.")
    else
        wlInfoText:SetTextColor(0.4, 0.35, 0.2)
        wlInfoText:SetText("Whitelist = immer Admin-Rechte. |cFFFF4444Nur Gildenmeister.|r")
    end

    -- Current whitelist display
    local wlListText = content:CreateFontString(nil, "OVERLAY")
    wlListText:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    wlListText:SetPoint("TOPLEFT", content, "TOPLEFT", 4, wlTop - 42)
    wlListText:SetWidth(290)
    wlListText:SetJustifyH("LEFT")
    wlListText:SetTextColor(0.87, 0.73, 0.4)

    local function RefreshWhitelistDisplay()
        local wl = (OneGuild.db and OneGuild.db.settings and OneGuild.db.settings.whitelist) or {}
        if #wl == 0 then
            wlListText:SetText("|cFF555555(Keine Spieler auf der Whitelist)|r")
        else
            wlListText:SetText("|cFFDDB866" .. table.concat(wl, ", ") .. "|r")
        end
    end
    RefreshWhitelistDisplay()

    -- Add player input
    local addBox = CreateFrame("EditBox", nil, content, "BackdropTemplate")
    addBox:SetSize(160, 24)
    addBox:SetPoint("TOPLEFT", content, "TOPLEFT", 4, wlTop - 62)
    addBox:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    addBox:SetBackdropColor(0.12, 0.06, 0.04, 1)
    addBox:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
    addBox:SetFontObject("GameFontHighlightSmall")
    addBox:SetAutoFocus(false)
    addBox:SetMaxLetters(30)
    addBox:SetTextInsets(6, 6, 0, 0)
    addBox:EnableMouse(true)
    addBox:EnableKeyboard(true)
    addBox:SetScript("OnMouseDown", function(self) self:SetFocus() end)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    if not canEditWL then
        addBox:Disable()
        addBox:SetAlpha(0.4)
    end

    -- Add button
    local addBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    addBtn:SetSize(70, 24)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    addBtn:RegisterForClicks("AnyUp")
    addBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local addBtnText = addBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    addBtnText:SetPoint("CENTER")

    if canEditWL then
        addBtn:SetBackdropColor(0.1, 0.45, 0.1, 0.9)
        addBtn:SetBackdropBorderColor(0.2, 0.7, 0.2, 0.7)
        addBtnText:SetText("|cFF66FF66+ Hinzu|r")
    else
        addBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
        addBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4)
        addBtnText:SetText("|cFF666666+ Hinzu|r")
        addBtn:Disable()
    end

    addBtn:SetScript("OnClick", function()
        if not OneGuild:CanEditWhitelist() then
            OneGuild:Print("|cFFFF4444Nur der Gildenmeister kann die Whitelist bearbeiten.|r")
            return
        end
        local name = strtrim(addBox:GetText() or "")
        if name == "" then return end
        -- Capitalize first letter
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        if not OneGuild.db.settings.whitelist then OneGuild.db.settings.whitelist = {} end
        -- Check duplicate
        for _, wn in ipairs(OneGuild.db.settings.whitelist) do
            if wn == name then
                OneGuild:Print("|cFFFFCC00" .. name .. " ist bereits auf der Whitelist.|r")
                addBox:SetText("")
                return
            end
        end
        table.insert(OneGuild.db.settings.whitelist, name)
        OneGuild:LoadWhitelistFromDB()
        if OneGuild.SendWhitelistSync then OneGuild:SendWhitelistSync() end
        addBox:SetText("")
        addBox:ClearFocus()
        RefreshWhitelistDisplay()
        OneGuild:PrintSuccess(name .. " zur Whitelist hinzugef\195\188gt.")
    end)

    addBox:SetScript("OnEnterPressed", function()
        addBtn:GetScript("OnClick")(addBtn)
    end)

    -- Remove button
    local removeBtn = CreateFrame("Button", nil, content, "BackdropTemplate")
    removeBtn:SetSize(80, 24)
    removeBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    removeBtn:RegisterForClicks("AnyUp")
    removeBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    local removeBtnText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    removeBtnText:SetPoint("CENTER")

    if canEditWL then
        removeBtn:SetBackdropColor(0.5, 0.1, 0.1, 0.9)
        removeBtn:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.7)
        removeBtnText:SetText("|cFFFF6666- Entfernen|r")
    else
        removeBtn:SetBackdropColor(0.15, 0.15, 0.15, 0.5)
        removeBtn:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.4)
        removeBtnText:SetText("|cFF666666- Entfernen|r")
        removeBtn:Disable()
    end

    removeBtn:SetScript("OnClick", function()
        if not OneGuild:CanEditWhitelist() then
            OneGuild:Print("|cFFFF4444Nur der Gildenmeister kann die Whitelist bearbeiten.|r")
            return
        end
        local name = strtrim(addBox:GetText() or "")
        if name == "" then return end
        name = name:sub(1,1):upper() .. name:sub(2):lower()
        if not OneGuild.db.settings.whitelist then return end
        local found = false
        for idx, wn in ipairs(OneGuild.db.settings.whitelist) do
            if wn == name then
                table.remove(OneGuild.db.settings.whitelist, idx)
                found = true
                break
            end
        end
        if found then
            OneGuild:LoadWhitelistFromDB()
            if OneGuild.SendWhitelistSync then OneGuild:SendWhitelistSync() end
            addBox:SetText("")
            addBox:ClearFocus()
            RefreshWhitelistDisplay()
            OneGuild:PrintSuccess(name .. " von der Whitelist entfernt.")
        else
            OneGuild:Print("|cFFFF4444" .. name .. " ist nicht auf der Whitelist.|r")
        end
    end)
end

------------------------------------------------------------------------
--                     TAB: Design (FX-Effekte)
------------------------------------------------------------------------
local function BuildDesignTab(content)
    Label(content, 0, 0, "Design & Effekte", 14, 1, 0.72, 0)
    HLine(content, -22)

    local function S() return OneGuild.db.settings end

    -- Master toggle
    MakeCheckbox(content, 0, -34,
        "Effekte aktiviert",
        "Schaltet alle visuellen Premium-Effekte ein/aus.\n(/reload noetig)",
        function() return S().fxEnabled ~= false end,
        function(val) S().fxEnabled = val end
    )

    -- Border glow
    MakeCheckbox(content, 0, -68,
        "Border-Glow (pulsierender Rand)",
        "Goldener pulsierender Glow am Fensterrand.",
        function() return S().fxBorderGlow ~= false end,
        function(val) S().fxBorderGlow = val end
    )

    -- Shimmer
    MakeCheckbox(content, 0, -102,
        "Border-Shimmer (wandernder Lichtpunkt)",
        "Lichtpunkt der am Rand entlanggleitet.",
        function() return S().fxShimmer ~= false end,
        function(val) S().fxShimmer = val end
    )

    -- Header Shine
    MakeCheckbox(content, 0, -136,
        "Header-Shine (pulsierende Balken)",
        "Dekorative leuchtende Balken unter dem Titel.",
        function() return S().fxHeaderShine ~= false end,
        function(val) S().fxHeaderShine = val end
    )

    -- Particle count slider
    MakeSlider(content, 0, -186,
        "Partikel-Anzahl:", 0, 64, 1,
        function() return S().fxParticleCount or 35 end,
        function(val) S().fxParticleCount = val end
    )

    -- === Glow color picker ===
    Label(content, 0, -240, "Glow-Farbe:", 12, 0.87, 0.78, 0.55)

    local presets = {
        { name = "Gold",    c = { 0.9, 0.65, 0.15 } },
        { name = "Blau",    c = { 0.2, 0.5,  1.0  } },
        { name = "Gruen",   c = { 0.2, 0.8,  0.3  } },
        { name = "Rot",     c = { 0.9, 0.2,  0.1  } },
        { name = "Lila",    c = { 0.6, 0.2,  0.9  } },
        { name = "Weiss",   c = { 1.0, 1.0,  1.0  } },
    }

    -- Preview swatch
    local swatch = content:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(22, 22)
    swatch:SetPoint("TOPLEFT", content, "TOPLEFT", 100, -237)
    swatch:SetTexture("Interface\\Buttons\\WHITE8x8")
    local gc = S().fxGlowColor or { 0.9, 0.65, 0.15 }
    swatch:SetVertexColor(gc[1], gc[2], gc[3], 1)

    local btnX = 0
    for i, preset in ipairs(presets) do
        local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
        btn:SetSize(50, 22)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", btnX, -264)
        btn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        btn:SetBackdropColor(preset.c[1] * 0.4, preset.c[2] * 0.4, preset.c[3] * 0.4, 0.9)
        btn:SetBackdropBorderColor(preset.c[1], preset.c[2], preset.c[3], 0.8)

        local txt = btn:CreateFontString(nil, "OVERLAY")
        txt:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        txt:SetPoint("CENTER")
        txt:SetTextColor(preset.c[1], preset.c[2], preset.c[3])
        txt:SetText(preset.name)

        btn:SetScript("OnClick", function()
            S().fxGlowColor = { preset.c[1], preset.c[2], preset.c[3] }
            swatch:SetVertexColor(preset.c[1], preset.c[2], preset.c[3], 1)
            OneGuild:Print("|cFFFFD700Glow-Farbe:|r " .. preset.name .. " (nach /reload aktiv)")
        end)

        btn:SetScript("OnEnter", function(self)
            self:SetBackdropBorderColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self:SetBackdropBorderColor(preset.c[1], preset.c[2], preset.c[3], 0.8)
        end)

        btnX = btnX + 54
    end

    -- Info hint
    local hint = content:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -300)
    hint:SetTextColor(0.6, 0.55, 0.45)
    hint:SetText("Aenderungen werden nach /reload aktiv.")
end

------------------------------------------------------------------------
-- TAB DEFINITIONS — add new tabs here
------------------------------------------------------------------------
local TAB_DEFS = {
    { name = "Allgemein",       builder = BuildGeneralTab },
    { name = "Design",          builder = BuildDesignTab },
    { name = "GuildMap",        builder = BuildGuildMapTab },
    { name = "Loot",            builder = BuildLootTab },
    { name = "Berechtigungen",  builder = BuildPermissionsTab },
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
