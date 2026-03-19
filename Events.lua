------------------------------------------------------------------------
-- OneGuild - Events.lua
-- Event/Raid planner with sign-up system and role selection
-- (Tank / Healer / DD icons with counts)
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Events.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local EVENT_ROW_HEIGHT = 82
local MAX_EVENT_ROWS   = 5

-- Role icon texture (LFGFrame, 64x64)
local ROLE_TEX    = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local ROLE_COORDS = {
    TANK   = { 0,        19/64,  22/64, 41/64 },
    HEALER = { 20/64,    39/64,  1/64,  20/64 },
    DD     = { 20/64,    39/64,  22/64, 41/64 },
}
local ROLE_LABELS = {
    TANK   = "Tank",
    HEALER = "Healer",
    DD     = "DD",
}
local ROLE_ORDER = { "TANK", "HEALER", "DD" }

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
local eventRows     = {}
local displayEvents = {}
local showPast      = false

------------------------------------------------------------------------
-- Helper: count signups by status and role
------------------------------------------------------------------------
local function CountSignups(signups)
    local accepted, declined, tentative = 0, 0, 0
    local roles = { TANK = 0, HEALER = 0, DD = 0 }

    if not signups then return accepted, declined, tentative, roles end

    for _, s in pairs(signups) do
        local status, role
        if type(s) == "table" then
            status = s.status
            role   = s.role
        else
            status = s
            role   = nil
        end

        if status == "accepted" then
            accepted = accepted + 1
            if role and roles[role] ~= nil then
                roles[role] = roles[role] + 1
            end
        elseif status == "declined" then
            declined = declined + 1
        elseif status == "tentative" then
            tentative = tentative + 1
        end
    end

    return accepted, declined, tentative, roles
end

------------------------------------------------------------------------
-- Helper: get player signup info
------------------------------------------------------------------------
local function GetPlayerSignup(signups, playerName)
    if not signups or not signups[playerName] then
        return "none", nil
    end
    local s = signups[playerName]
    if type(s) == "table" then
        return s.status or "none", s.role
    end
    return s, nil
end

------------------------------------------------------------------------
-- Helper: create role icon texture on a parent frame
------------------------------------------------------------------------
local function CreateRoleIcon(parent, role, size)
    local tex = parent:CreateTexture(nil, "ARTWORK")
    tex:SetSize(size, size)
    tex:SetTexture(ROLE_TEX)
    local c = ROLE_COORDS[role]
    if c then
        tex:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    return tex
end

------------------------------------------------------------------------
-- Build Events Tab (Tab 2)
------------------------------------------------------------------------
function OneGuild:BuildEventsTab()
    local parent = self.tabFrames[2]
    if not parent then return end

    -- Top bar: title + create button
    local topBar = CreateFrame("Frame", nil, parent)
    topBar:SetHeight(32)
    topBar:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, -6)
    topBar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, -6)

    local titleText = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", topBar, "LEFT", 4, 0)
    titleText:SetText("|cFFFFB800Gilden-Events|r")

    -- Create Event button
    local createBtn = CreateFrame("Button", nil, topBar, "BackdropTemplate")
    createBtn:SetSize(130, 24)
    createBtn:SetPoint("RIGHT", topBar, "RIGHT", -4, 0)
    createBtn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    createBtn:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
    createBtn:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    local createBtnText = createBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    createBtnText:SetPoint("CENTER")
    createBtnText:SetText("|cFFFFD700+ Neues Event|r")
    createBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.45, 0.3, 0.08, 1)
        self:SetBackdropBorderColor(0.8, 0.6, 0.15, 0.8)
    end)
    createBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.3, 0.2, 0.05, 0.8)
        self:SetBackdropBorderColor(0.6, 0.4, 0.1, 0.6)
    end)
    createBtn:SetScript("OnClick", function()
        OneGuild:ShowCreateEventDialog()
    end)

    -- Toggle past events
    local pastCheck = CreateFrame("CheckButton", "OneGuildPastFilter", topBar, "UICheckButtonTemplate")
    pastCheck:SetSize(22, 22)
    pastCheck:SetPoint("RIGHT", createBtn, "LEFT", -10, 0)
    pastCheck:SetChecked(false)
    local pastLabel = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    pastLabel:SetPoint("RIGHT", pastCheck, "LEFT", -2, 0)
    pastLabel:SetText("|cFF8B7355Vergangene|r")
    pastCheck:SetScript("OnClick", function(self)
        showPast = self:GetChecked()
        OneGuild:RefreshEvents()
    end)

    -- Event list container
    local listFrame = CreateFrame("Frame", nil, parent)
    listFrame:SetPoint("TOPLEFT", topBar, "BOTTOMLEFT", 0, -4)
    listFrame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -8, 8)
    parent.listFrame = listFrame

    -- Create event row frames
    for i = 1, MAX_EVENT_ROWS do
        local row = CreateFrame("Frame", nil, listFrame, "BackdropTemplate")
        row:SetHeight(EVENT_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -((i - 1) * (EVENT_ROW_HEIGHT + 4)))
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, -((i - 1) * (EVENT_ROW_HEIGHT + 4)))
        row:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        row:SetBackdropColor(0.08, 0.05, 0.03, 0.8)
        row:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.5)

        -- Event title
        row.titleText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.titleText:SetPoint("TOPLEFT", row, "TOPLEFT", 10, -6)
        row.titleText:SetJustifyH("LEFT")

        -- Date icon (calendar texture instead of emoji)
        row.dateIcon = row:CreateTexture(nil, "ARTWORK")
        row.dateIcon:SetSize(12, 12)
        row.dateIcon:SetPoint("TOPLEFT", row.titleText, "BOTTOMLEFT", 0, -3)
        row.dateIcon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
        row.dateIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        -- Date & Time text
        row.dateText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.dateText:SetPoint("LEFT", row.dateIcon, "RIGHT", 4, 0)
        row.dateText:SetTextColor(0.7, 0.6, 0.4)

        -- Description snippet
        row.descText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.descText:SetPoint("TOPLEFT", row.dateIcon, "BOTTOMLEFT", 0, -2)
        row.descText:SetPoint("RIGHT", row, "RIGHT", -200, 0)
        row.descText:SetTextColor(0.5, 0.5, 0.5)
        row.descText:SetWordWrap(false)

        -- === Role counters on the right side ===
        row.roleFrames = {}
        local roleX = -140
        for _, role in ipairs(ROLE_ORDER) do
            local rf = CreateFrame("Frame", nil, row)
            rf:SetSize(44, 18)
            rf:SetPoint("TOPRIGHT", row, "TOPRIGHT", roleX, -8)

            rf.icon = CreateRoleIcon(rf, role, 16)
            rf.icon:SetPoint("LEFT", rf, "LEFT", 0, 0)

            rf.count = rf:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            rf.count:SetPoint("LEFT", rf.icon, "RIGHT", 3, 0)
            rf.count:SetText("|cFFDDB8660|r")

            row.roleFrames[role] = rf
            roleX = roleX + 46
        end

        -- Signup count text (accepted / tentative / declined)
        row.signupText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.signupText:SetPoint("TOPRIGHT", row, "TOPRIGHT", -10, -28)

        -- Your status display
        row.statusText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.statusText:SetPoint("TOPRIGHT", row.signupText, "BOTTOMRIGHT", 0, -2)

        -- === Signup buttons row (bottom of card) ===
        local btnY  = -54
        local btnW  = 28
        local btnH  = 22
        local gap   = 5

        -- Role selection buttons (Tank / Healer / DD)
        row.roleButtons = {}
        local roleBtnX = 10
        for _, role in ipairs(ROLE_ORDER) do
            local rb = CreateFrame("Button", nil, row, "BackdropTemplate")
            rb:SetSize(btnW + 24, btnH)
            rb:SetPoint("TOPLEFT", row, "TOPLEFT", roleBtnX, btnY)
            rb:SetBackdrop({
                bgFile   = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                edgeSize = 8,
                insets   = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            rb:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
            rb:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)

            rb.icon = CreateRoleIcon(rb, role, 14)
            rb.icon:SetPoint("LEFT", rb, "LEFT", 4, 0)

            rb.label = rb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            rb.label:SetPoint("LEFT", rb.icon, "RIGHT", 2, 0)
            rb.label:SetText("|cFFDDB866" .. ROLE_LABELS[role] .. "|r")

            rb.role = role

            rb:SetScript("OnEnter", function(self)
                self:SetBackdropColor(0.3, 0.2, 0.05, 0.9)
                self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.7)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("|cFFFFD700Als " .. ROLE_LABELS[role] .. " zusagen|r")
                GameTooltip:Show()
            end)
            rb:SetScript("OnLeave", function(self)
                self:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
                self:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
                GameTooltip:Hide()
            end)

            row.roleButtons[role] = rb
            roleBtnX = roleBtnX + btnW + 24 + gap
        end

        -- Tentative button
        row.tentBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.tentBtn:SetSize(btnW + 18, btnH)
        row.tentBtn:SetPoint("TOPLEFT", row, "TOPLEFT", roleBtnX + 8, btnY)
        row.tentBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.tentBtn:SetBackdropColor(0.28, 0.24, 0, 0.8)
        row.tentBtn:SetBackdropBorderColor(0.6, 0.5, 0, 0.5)
        local tentText = row.tentBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        tentText:SetPoint("CENTER")
        tentText:SetText("|cFFFFCC00Vllt.|r")
        row.tentBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.4, 0.35, 0, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFFCC00Vielleicht|r")
            GameTooltip:Show()
        end)
        row.tentBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.28, 0.24, 0, 0.8)
            GameTooltip:Hide()
        end)

        -- Decline button
        row.declineBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.declineBtn:SetSize(btnW + 18, btnH)
        row.declineBtn:SetPoint("LEFT", row.tentBtn, "RIGHT", gap, 0)
        row.declineBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.declineBtn:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
        row.declineBtn:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.5)
        local decText = row.declineBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        decText:SetPoint("CENTER")
        decText:SetText("|cFFFF4444Absage|r")
        row.declineBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.5, 0.08, 0.08, 0.9)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFF4444Absagen|r")
            GameTooltip:Show()
        end)
        row.declineBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
            GameTooltip:Hide()
        end)

        -- Delete button (small X, far right bottom)
        row.deleteBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.deleteBtn:SetSize(16, 16)
        row.deleteBtn:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -8, 8)
        row.deleteBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        row.deleteBtn:SetBackdropColor(0.3, 0, 0, 0.6)
        row.deleteBtn:SetBackdropBorderColor(0.5, 0.15, 0.15, 0.4)
        local delText = row.deleteBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        delText:SetPoint("CENTER")
        delText:SetText("|cFFFF6666x|r")
        row.deleteBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.5, 0, 0, 0.8)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("|cFFFF6666Event loeschen|r")
            GameTooltip:Show()
        end)
        row.deleteBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.3, 0, 0, 0.6)
            GameTooltip:Hide()
        end)

        -- Hover effect on row
        row:EnableMouse(true)
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.08, 0.04, 0.9)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.05, 0.03, 0.8)
        end)

        row:Hide()
        eventRows[i] = row
    end
end

------------------------------------------------------------------------
-- Refresh event display
------------------------------------------------------------------------
function OneGuild:RefreshEvents()
    if not self.db then return end
    if #eventRows == 0 then return end  -- tab not built yet

    local now = time()
    displayEvents = {}

    for idx, ev in ipairs(self.db.events) do
        local evTime = ev.timestamp or 0
        local isPast = evTime < now

        if showPast or not isPast then
            table.insert(displayEvents, { index = idx, data = ev, isPast = isPast })
        end
    end

    -- Sort: upcoming first (soonest at top), past at bottom
    table.sort(displayEvents, function(a, b)
        if a.isPast ~= b.isPast then return not a.isPast end
        return a.data.timestamp < b.data.timestamp
    end)

    local playerName = self:GetPlayerName()

    for i = 1, MAX_EVENT_ROWS do
        local row = eventRows[i]
        if i <= #displayEvents then
            local ev = displayEvents[i]
            local data = ev.data

            -- Title
            local titleColor = ev.isPast and "|cFF8B7355" or "|cFFFFB800"
            row.titleText:SetText(titleColor .. (data.title or "Unbenannt") .. "|r")

            -- Date & Time (no emoji, plain text)
            local dateStr = data.dateStr or "?"
            local timeStr = data.timeStr or ""
            row.dateText:SetText(dateStr .. "  " .. timeStr .. " Uhr")

            -- Description
            local desc = data.description or ""
            if #desc > 50 then desc = desc:sub(1, 50) .. "..." end
            row.descText:SetText("|cFF8B7355" .. desc .. "|r")

            -- Signup counts
            local signups = data.signups or {}
            local accepted, declined, tentative, roles = CountSignups(signups)

            -- Update role counters (right side)
            for _, role in ipairs(ROLE_ORDER) do
                local cnt = roles[role]
                local color = cnt > 0 and "|cFFFFD700" or "|cFF555555"
                row.roleFrames[role].count:SetText(color .. cnt .. "|r")
            end

            -- Signup summary
            row.signupText:SetText(
                "|cFF66FF66" .. accepted .. " Zusagen|r  " ..
                "|cFFFFCC00" .. tentative .. " Vllt.|r  " ..
                "|cFFFF4444" .. declined .. " Absagen|r"
            )

            -- Player's own status
            local myStatus, myRole = GetPlayerSignup(signups, playerName)
            local statusMap = {
                accepted  = "|cFF66FF66Zugesagt",
                declined  = "|cFFFF4444Abgesagt",
                tentative = "|cFFFFCC00Vielleicht",
                none      = "|cFF666666Nicht angemeldet",
            }
            local statusStr = statusMap[myStatus] or statusMap.none
            if myStatus == "accepted" and myRole then
                statusStr = statusStr .. " (" .. ROLE_LABELS[myRole] .. ")"
            end
            row.statusText:SetText("|cFF8B7355Du:|r " .. statusStr .. "|r")

            -- Highlight active role button for player
            for _, role in ipairs(ROLE_ORDER) do
                local rb = row.roleButtons[role]
                if myStatus == "accepted" and myRole == role then
                    rb:SetBackdropColor(0.3, 0.25, 0.05, 1)
                    rb:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
                else
                    rb:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
                    rb:SetBackdropBorderColor(0.4, 0.3, 0.1, 0.4)
                end
            end

            -- Highlight tentative
            if myStatus == "tentative" then
                row.tentBtn:SetBackdropColor(0.4, 0.35, 0, 1)
                row.tentBtn:SetBackdropBorderColor(0.8, 0.7, 0, 0.8)
            else
                row.tentBtn:SetBackdropColor(0.28, 0.24, 0, 0.8)
                row.tentBtn:SetBackdropBorderColor(0.6, 0.5, 0, 0.5)
            end

            -- Highlight decline
            if myStatus == "declined" then
                row.declineBtn:SetBackdropColor(0.5, 0.08, 0.08, 1)
                row.declineBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 0.8)
            else
                row.declineBtn:SetBackdropColor(0.3, 0.05, 0.05, 0.8)
                row.declineBtn:SetBackdropBorderColor(0.6, 0.15, 0.15, 0.5)
            end

            -- Wire up role signup buttons
            local eventIdx = ev.index
            for _, role in ipairs(ROLE_ORDER) do
                row.roleButtons[role]:SetScript("OnClick", function()
                    OneGuild:SignupForEvent(eventIdx, "accepted", role)
                end)
            end
            row.tentBtn:SetScript("OnClick", function()
                OneGuild:SignupForEvent(eventIdx, "tentative", nil)
            end)
            row.declineBtn:SetScript("OnClick", function()
                OneGuild:SignupForEvent(eventIdx, "declined", nil)
            end)
            row.deleteBtn:SetScript("OnClick", function()
                OneGuild:DeleteEvent(eventIdx)
            end)

            row:Show()
        else
            row:Hide()
        end
    end

    -- Empty message
    local parent = self.tabFrames[2]
    if not parent.emptyText then
        parent.emptyText = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        parent.emptyText:SetPoint("CENTER", parent, "CENTER", 0, -20)
        parent.emptyText:SetWidth(400)
        parent.emptyText:SetJustifyH("CENTER")
        parent.emptyText:SetWordWrap(true)
    end
    if #displayEvents == 0 then
        parent.emptyText:SetText("|cFF8B7355Keine Events vorhanden.\n\n" ..
            "|cFFDDB866Erstelle ein neues Event mit dem + Button.|r")
        parent.emptyText:Show()
    else
        parent.emptyText:Hide()
    end
end

------------------------------------------------------------------------
-- Signup for an event (with role)
------------------------------------------------------------------------
function OneGuild:SignupForEvent(eventIdx, status, role)
    if not self.db or not self.db.events[eventIdx] then return end

    local playerName = self:GetPlayerName()
    if not self.db.events[eventIdx].signups then
        self.db.events[eventIdx].signups = {}
    end

    local old = self.db.events[eventIdx].signups[playerName]
    local oldStatus = type(old) == "table" and old.status or old
    local oldRole   = type(old) == "table" and old.role or nil

    -- Toggle off if clicking same status + role
    if oldStatus == status and (status ~= "accepted" or oldRole == role) then
        self.db.events[eventIdx].signups[playerName] = nil
        self:Print("|cFFDDB866Anmeldung fuer '|r|cFFFFD700" ..
            (self.db.events[eventIdx].title or "?") .. "|r|cFFDDB866' zurueckgezogen.|r")
    else
        self.db.events[eventIdx].signups[playerName] = {
            status   = status,
            role     = role,
            signedAt = time(),
        }
        local statusDE = {
            accepted  = "Zugesagt",
            declined  = "Abgesagt",
            tentative = "Vielleicht",
        }
        local msg = (statusDE[status] or status)
        if role then
            msg = msg .. " als " .. ROLE_LABELS[role]
        end
        self:PrintSuccess(msg .. " fuer '" .. (self.db.events[eventIdx].title or "?") .. "'.")
    end

    self:RefreshEvents()

    -- Broadcast signup to guild
    local ev = self.db.events[eventIdx]
    if ev and self.SendEventSignup then
        local signup = ev.signups[playerName]
        if signup then
            self:SendEventSignup(ev, playerName, signup)
        else
            self:SendEventSignup(ev, playerName, { status = "withdrawn", role = "", signedAt = time() })
        end
    end
end

------------------------------------------------------------------------
-- Delete an event
------------------------------------------------------------------------
function OneGuild:DeleteEvent(eventIdx)
    if not self.db or not self.db.events[eventIdx] then return end
    local evt = self.db.events[eventIdx]
    local title = evt.title or "?"

    -- Create tombstone so sync doesn't revive it
    local delKey = tostring(evt.created or 0) .. ":" .. (evt.author or "?")
    if not self.db.deletedEvents then self.db.deletedEvents = {} end
    self.db.deletedEvents[delKey] = true

    -- Broadcast delete to guild
    if self.BroadcastEventDelete then
        self:BroadcastEventDelete(evt)
    end

    table.remove(self.db.events, eventIdx)
    self:Print("|cFFDDB866Event '|r|cFFFFD700" .. title .. "|r|cFFDDB866' geloescht.|r")
    self:RefreshEvents()
end

------------------------------------------------------------------------
-- Dropdown helpers for date / time selection
------------------------------------------------------------------------
local EV_WOCHENTAGE = {"So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"}

local function EVBuildDateOptions()
    local opts = {}
    local now = time()
    for i = 0, 29 do
        local t = now + i * 86400
        local d = date("*t", t)
        local val = format("%02d.%02d.%04d", d.day, d.month, d.year)
        local disp = EV_WOCHENTAGE[d.wday] .. "  " .. val
        opts[#opts + 1] = { display = disp, value = val }
    end
    return opts
end

local function EVBuildTimeOptions()
    local opts = {}
    for h = 0, 23 do
        for m = 0, 30, 30 do
            local val = format("%02d:%02d", h, m)
            opts[#opts + 1] = { display = val, value = val }
        end
    end
    return opts
end

local function EVCreateDropdownMenu(parent, anchor, options, menuWidth, editBox)
    local itemH = 20
    local visible = math.min(#options, 10)
    local menuH = visible * itemH + 8

    local menu = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    menu:SetSize(menuWidth, menuH)
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetFrameLevel(300)
    menu:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    menu:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
    menu:SetBackdropBorderColor(0.6, 0.45, 0.1, 0.7)
    menu:Hide()

    local scroll = CreateFrame("ScrollFrame", nil, menu, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -24, 4)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(menuWidth - 30, #options * itemH)
    scroll:SetScrollChild(content)

    menu._buttons = {}
    menu._editBox = editBox
    for i, opt in ipairs(options) do
        local btn = CreateFrame("Button", nil, content, "BackdropTemplate")
        btn:SetSize(menuWidth - 30, itemH - 2)
        btn:SetPoint("TOPLEFT", 0, -((i - 1) * itemH))
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(0, 0, 0, 0)

        local txt = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        txt:SetPoint("LEFT", 6, 0)
        txt:SetText("|cFFDDB866" .. opt.display .. "|r")
        btn._label = txt
        btn._value = opt.value

        btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.3, 0.2, 0.05, 0.7) end)
        btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0, 0, 0, 0) end)
        btn:SetScript("OnClick", function()
            editBox:SetText(opt.value)
            menu:Hide()
        end)

        menu._buttons[i] = btn
    end

    return menu
end

local function EVRefreshDateMenu(menu)
    local opts = EVBuildDateOptions()
    local eb = menu._editBox
    for i, opt in ipairs(opts) do
        local btn = menu._buttons[i]
        if btn then
            btn._label:SetText("|cFFDDB866" .. opt.display .. "|r")
            btn._value = opt.value
            btn:SetScript("OnClick", function()
                eb:SetText(opt.value)
                menu:Hide()
            end)
        end
    end
end

------------------------------------------------------------------------
-- Create Event Dialog
------------------------------------------------------------------------
function OneGuild:ShowCreateEventDialog()
    if self.createEventFrame and self.createEventFrame:IsShown() then
        self.createEventFrame:Hide()
        return
    end

    if not self.createEventFrame then
        local f = CreateFrame("Frame", "OneGuildCreateEvent", UIParent, "BackdropTemplate")
        f:SetSize(370, 320)
        f:SetPoint("CENTER")
        f:SetMovable(true)
        f:EnableMouse(true)
        f:SetFrameStrata("DIALOG")
        f:SetFrameLevel(200)
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 14,
            insets   = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        f:SetBackdropColor(0.06, 0.03, 0.03, 0.98)
        f:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.7)

        -- Title bar drag
        local dragArea = CreateFrame("Frame", nil, f)
        dragArea:SetHeight(30)
        dragArea:SetPoint("TOPLEFT")
        dragArea:SetPoint("TOPRIGHT")
        dragArea:EnableMouse(true)
        dragArea:RegisterForDrag("LeftButton")
        dragArea:SetScript("OnDragStart", function() f:StartMoving() end)
        dragArea:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

        -- Gold accent
        local accent = f:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetHeight(2)
        accent:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
        accent:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
        accent:SetColorTexture(0.7, 0.5, 0.1, 0.6)

        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOPLEFT", 14, -12)
        title:SetText("|cFFFFB800Neues Event erstellen|r")

        local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        closeBtn:SetPoint("TOPRIGHT", -2, -2)

        -- Input: Event Name
        local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -42)
        nameLabel:SetText("|cFFDDB866Event-Name:|r")

        local nameBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        nameBox:SetSize(320, 22)
        nameBox:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 4, -2)
        nameBox:SetAutoFocus(false)
        nameBox:SetMaxLetters(60)
        f.nameBox = nameBox

        -- Input: Date
        local dateLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateLabel:SetPoint("TOPLEFT", nameBox, "BOTTOMLEFT", -4, -10)
        dateLabel:SetText("|cFFDDB866Datum (TT.MM.JJJJ):|r")

        local dateBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        dateBox:SetSize(115, 22)
        dateBox:SetPoint("TOPLEFT", dateLabel, "BOTTOMLEFT", 4, -2)
        dateBox:SetAutoFocus(false)
        dateBox:SetMaxLetters(10)
        f.dateBox = dateBox

        -- Date dropdown button
        local dateDDBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        dateDDBtn:SetSize(24, 22)
        dateDDBtn:SetPoint("LEFT", dateBox, "RIGHT", 2, 0)
        dateDDBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        dateDDBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        dateDDBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        local dateDDArrow = dateDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateDDArrow:SetPoint("CENTER")
        dateDDArrow:SetText("|cFFDDB866v|r")
        dateDDBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.15, 0.05, 0.9)
        end)
        dateDDBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        end)

        -- Date dropdown menu (scrollable, 30 days)
        local dateMenu = EVCreateDropdownMenu(f, dateBox, EVBuildDateOptions(), 170, dateBox)
        f.dateMenu = dateMenu
        dateDDBtn:SetScript("OnClick", function()
            if f.timeMenu and f.timeMenu:IsShown() then f.timeMenu:Hide() end
            EVRefreshDateMenu(dateMenu)
            if dateMenu:IsShown() then dateMenu:Hide() else dateMenu:Show() end
        end)

        -- Input: Time
        local timeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeLabel:SetPoint("LEFT", dateLabel, "RIGHT", 50, 0)
        timeLabel:SetText("|cFFDDB866Uhrzeit (HH:MM):|r")

        local timeBox = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
        timeBox:SetSize(75, 22)
        timeBox:SetPoint("TOPLEFT", timeLabel, "BOTTOMLEFT", 4, -2)
        timeBox:SetAutoFocus(false)
        timeBox:SetMaxLetters(5)
        f.timeBox = timeBox

        -- Time dropdown button
        local timeDDBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        timeDDBtn:SetSize(24, 22)
        timeDDBtn:SetPoint("LEFT", timeBox, "RIGHT", 2, 0)
        timeDDBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 8,
            insets   = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        timeDDBtn:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        timeDDBtn:SetBackdropBorderColor(0.5, 0.35, 0.1, 0.6)
        local timeDDArrow = timeDDBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeDDArrow:SetPoint("CENTER")
        timeDDArrow:SetText("|cFFDDB866v|r")
        timeDDBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.25, 0.15, 0.05, 0.9)
        end)
        timeDDBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.15, 0.1, 0.05, 0.8)
        end)

        -- Time dropdown menu (scrollable, 30-min steps)
        local timeMenu = EVCreateDropdownMenu(f, timeBox, EVBuildTimeOptions(), 100, timeBox)
        f.timeMenu = timeMenu
        timeDDBtn:SetScript("OnClick", function()
            if f.dateMenu and f.dateMenu:IsShown() then f.dateMenu:Hide() end
            if timeMenu:IsShown() then timeMenu:Hide() else timeMenu:Show() end
        end)

        -- Input: Description
        local descLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        descLabel:SetPoint("TOPLEFT", dateBox, "BOTTOMLEFT", -4, -10)
        descLabel:SetText("|cFFDDB866Beschreibung:|r")

        local descScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        descScroll:SetSize(320, 60)
        descScroll:SetPoint("TOPLEFT", descLabel, "BOTTOMLEFT", 4, -2)

        local descBox = CreateFrame("EditBox", nil, descScroll)
        descBox:SetMultiLine(true)
        descBox:SetFontObject("ChatFontNormal")
        descBox:SetWidth(300)
        descBox:SetAutoFocus(false)
        descBox:SetMaxLetters(500)
        descScroll:SetScrollChild(descBox)
        f.descBox = descBox

        -- Create button
        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(140, 30)
        saveBtn:SetPoint("BOTTOM", f, "BOTTOM", 0, 18)
        saveBtn:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            edgeSize = 10,
            insets   = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        saveBtn:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
        saveBtn:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
        local saveBtnText = saveBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        saveBtnText:SetPoint("CENTER")
        saveBtnText:SetText("|cFFFFFFFFErstellen|r")
        saveBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.55, 0.38, 0.08, 1)
            self:SetBackdropBorderColor(0.9, 0.7, 0.15, 0.9)
        end)
        saveBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.4, 0.28, 0.05, 0.9)
            self:SetBackdropBorderColor(0.7, 0.5, 0.1, 0.6)
        end)
        saveBtn:SetScript("OnClick", function()
            OneGuild:CreateEventFromDialog()
        end)

        f:Hide()
        self.createEventFrame = f
        table.insert(UISpecialFrames, "OneGuildCreateEvent")
    end

    -- Clear fields
    self.createEventFrame.nameBox:SetText("")
    self.createEventFrame.dateBox:SetText(date("%d.%m.%Y"))
    self.createEventFrame.timeBox:SetText("20:00")
    self.createEventFrame.descBox:SetText("")
    self.createEventFrame:Show()
end

------------------------------------------------------------------------
-- Save event from dialog
------------------------------------------------------------------------
function OneGuild:CreateEventFromDialog()
    local f = self.createEventFrame
    if not f then return end

    local title = strtrim(f.nameBox:GetText() or "")
    local dateStr = strtrim(f.dateBox:GetText() or "")
    local timeStr = strtrim(f.timeBox:GetText() or "")
    local desc = strtrim(f.descBox:GetText() or "")

    if title == "" then
        self:PrintError("Bitte gib einen Event-Namen ein!")
        return
    end

    -- Parse date and time to timestamp
    local day, month, year = dateStr:match("(%d+)%.(%d+)%.(%d+)")
    local hour, minute = timeStr:match("(%d+):(%d+)")

    local timestamp = 0
    if day and month and year then
        timestamp = time({
            year  = tonumber(year),
            month = tonumber(month),
            day   = tonumber(day),
            hour  = tonumber(hour) or 20,
            min   = tonumber(minute) or 0,
            sec   = 0,
        })
    end

    table.insert(self.db.events, {
        title       = title,
        description = desc,
        dateStr     = dateStr,
        timeStr     = timeStr,
        timestamp   = timestamp,
        author      = self:GetPlayerName(),
        created     = time(),
        signups     = {},
    })

    self:PrintSuccess("Event '" .. title .. "' erstellt!")
    f:Hide()
    self:RefreshEvents()

    -- Broadcast to guild
    local newEvent = self.db.events[#self.db.events]
    if self.SendSingleEvent then
        self:SendSingleEvent(newEvent)
    end
end
