------------------------------------------------------------------------
-- OneGuild  -  Map.lua
-- Shows OneGuild addon-member positions on the World Map (M).
-- Only members registered in the addon are displayed.
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r Map.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Constants
------------------------------------------------------------------------
local POS_INTERVAL     = 1        -- broadcast position every 1 s
local WM_UPDATE_HZ     = 0.15     -- world-map refresh interval (seconds)
local POSITION_TIMEOUT = 30       -- drop position after 30 s silence

-- Defaults (overridden by db.settings)
local DEFAULT_PIN_SIZE   = 16
local DEFAULT_LABEL_SIZE = 10

------------------------------------------------------------------------
-- State
------------------------------------------------------------------------
OneGuild.memberPositions = {}      -- [senderKey] = posData
local posTicker   = nil
local mapPinsOn   = true
local isMapInit   = false
local wmPins      = {}             -- [key] = world-map pin frame

------------------------------------------------------------------------
-- Dynamic getters (read from saved settings)
------------------------------------------------------------------------
local function GetPinSize()
    if OneGuild.db and OneGuild.db.settings then
        return OneGuild.db.settings.mapPinSize or DEFAULT_PIN_SIZE
    end
    return DEFAULT_PIN_SIZE
end

local function GetLabelSize()
    if OneGuild.db and OneGuild.db.settings then
        return OneGuild.db.settings.mapLabelSize or DEFAULT_LABEL_SIZE
    end
    return DEFAULT_LABEL_SIZE
end

local function ShowNames()
    if OneGuild.db and OneGuild.db.settings then
        return OneGuild.db.settings.mapShowNames ~= false
    end
    return true
end

local function GetPinAlpha()
    if OneGuild.db and OneGuild.db.settings then
        return OneGuild.db.settings.mapPinAlpha or 0.9
    end
    return 0.9
end

------------------------------------------------------------------------
-- Dynamic pin scale based on current map zoom level
-- mapType: 0=Cosmic, 1=World, 2=Continent, 3=Zone, 4=Dungeon, 5=Micro, 6=Orphan
------------------------------------------------------------------------
local MAP_SCALE_FACTORS = {
    [0] = 3.0,    -- Cosmic (all of Azeroth)
    [1] = 2.8,    -- World (Eastern Kingdoms, Kalimdor, etc.)
    [2] = 2.0,    -- Continent
    [3] = 1.0,    -- Zone (base size)
    [4] = 1.0,    -- Dungeon
    [5] = 0.9,    -- Micro (subzone)
    [6] = 1.0,    -- Orphan
}

local function GetMapScaleFactor(mapID)
    if not mapID then return 1.0 end
    local info = C_Map.GetMapInfo(mapID)
    if not info then return 1.0 end
    return MAP_SCALE_FACTORS[info.mapType] or 1.0
end

------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------
local function MyFullName()
    local n = UnitName("player") or ""
    local r = GetNormalizedRealmName() or GetRealmName() or ""
    return n .. "-" .. r
end

local function ClassRGB(cf)
    if cf and RAID_CLASS_COLORS and RAID_CLASS_COLORS[cf] then
        local c = RAID_CLASS_COLORS[cf]
        return c.r, c.g, c.b
    end
    return 0.8, 0.8, 0.8
end

-- WoW class icon atlas coords (Interface\GLUES\CHARACTERCREATE\UI-CHARACTERCREATE-CLASSES)
local CLASS_ICON_COORDS = {
    WARRIOR     = { 0,       0.25,    0,    0.25   },
    MAGE        = { 0.25,    0.50,    0,    0.25   },
    ROGUE       = { 0.50,    0.75,    0,    0.25   },
    DRUID       = { 0.75,    1.00,    0,    0.25   },
    HUNTER      = { 0,       0.25,    0.25, 0.50   },
    SHAMAN      = { 0.25,    0.50,    0.25, 0.50   },
    PRIEST      = { 0.50,    0.75,    0.25, 0.50   },
    WARLOCK     = { 0.75,    1.00,    0.25, 0.50   },
    PALADIN     = { 0,       0.25,    0.50, 0.75   },
    DEATHKNIGHT = { 0.25,    0.50,    0.50, 0.75   },
    MONK        = { 0.50,    0.75,    0.50, 0.75   },
    DEMONHUNTER = { 0.75,    1.00,    0.50, 0.75   },
    EVOKER      = { 0,       0.25,    0.75, 1.00   },
}

------------------------------------------------------------------------
-- Get the map canvas (where pins are drawn)
------------------------------------------------------------------------
local function GetCanvas()
    if not WorldMapFrame then return nil end
    if WorldMapFrame.GetCanvas then
        return WorldMapFrame:GetCanvas()
    end
    if WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child then
        return WorldMapFrame.ScrollContainer.Child
    end
    return nil
end

------------------------------------------------------------------------
-- Convert member position to the currently viewed map's 0-1 coords.
-- Returns nx, ny  or  nil, nil on failure.
------------------------------------------------------------------------
local function ToViewedMapCoords(viewMapID, memberMapID, mx, my)
    if memberMapID == viewMapID then
        return mx, my
    end

    -- Different map  → convert via world coordinates
    local ok1, contID, worldPos = pcall(C_Map.GetWorldPosFromMapPos,
        memberMapID, CreateVector2D(mx, my))
    if not ok1 or not contID or not worldPos then return nil, nil end

    local ok2, _, mapPos = pcall(C_Map.GetMapPosFromWorldPos,
        contID, worldPos, viewMapID)
    if not ok2 or not mapPos then return nil, nil end

    local nx, ny = mapPos:GetXY()
    if nx == 0 and ny == 0 then return nil, nil end
    return nx, ny
end

------------------------------------------------------------------------
-- Create a world-map pin frame
------------------------------------------------------------------------
local function NewWMPin(key, canvas)
    local sz = GetPinSize()
    local f = CreateFrame("Frame", nil, canvas)
    f:SetSize(sz + 4, sz + 16)
    f:SetFrameStrata("HIGH")
    f:SetFrameLevel(5000)

    -- Dark outline circle (slightly larger, behind the dot)
    f.border = f:CreateTexture(nil, "BACKGROUND")
    f.border:SetSize(sz + 4, sz + 4)
    f.border:SetPoint("CENTER", f, "CENTER", 0, 6)
    f.border:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    f.border:SetVertexColor(0, 0, 0, 1)

    -- Class-colored circle (white circle texture tinted via SetVertexColor)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetSize(sz, sz)
    f.dot:SetPoint("CENTER", f, "CENTER", 0, 6)
    f.dot:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    f.dot:SetVertexColor(1, 1, 1, 1)

    -- Class icon (centered inside the circle)
    local iconSz = math.max(sz - 4, 8)
    f.classIcon = f:CreateTexture(nil, "OVERLAY")
    f.classIcon:SetSize(iconSz, iconSz)
    f.classIcon:SetPoint("CENTER", f.dot, "CENTER", 0, 0)
    f.classIcon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
    f.classIcon:SetTexCoord(0, 0.25, 0, 0.25) -- default warrior, updated in refresh

    f:SetAlpha(GetPinAlpha())

    -- Name label below dot
    f.label = f:CreateFontString(nil, "OVERLAY")
    f.label:SetFont("Fonts\\FRIZQT__.TTF", GetLabelSize(), "OUTLINE")
    f.label:SetPoint("TOP", f.dot, "BOTTOM", 0, -1)
    f.label:SetTextColor(1, 0.84, 0)

    -- Tooltip
    f:EnableMouse(true)
    f:SetScript("OnEnter", function(self)
        local d = self.posData
        if not d then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local r, g, b = ClassRGB(d.classFile)
        GameTooltip:AddLine(d.name or "?", r, g, b)
        GameTooltip:AddLine("Level " .. tostring(d.level or "?"), 1, 1, 1)
        if d.mapID then
            local mi = C_Map.GetMapInfo(d.mapID)
            if mi and mi.name then
                GameTooltip:AddLine(mi.name, 0.7, 0.7, 0.7)
            end
        end
        GameTooltip:AddLine("|cFF8B6914OneGuild Mitglied|r", 0.55, 0.41, 0.08)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)

    wmPins[key] = f
    return f
end

------------------------------------------------------------------------
--                    POSITION  BROADCASTING
------------------------------------------------------------------------
function OneGuild:BroadcastPosition()
    if not self:IsAuthorized() then return end

    local mapID = C_Map.GetBestMapForUnit("player")
    if not mapID then return end
    local pos = C_Map.GetPlayerMapPosition(mapID, "player")
    if not pos then return end

    local x, y = pos:GetXY()
    if x == 0 and y == 0 then return end

    local _, classFile = UnitClass("player")
    local name  = UnitName("player") or "?"
    local level = UnitLevel("player") or 0

    self:SendCommMessage("POS", table.concat({
        tostring(mapID),
        format("%.4f", x),
        format("%.4f", y),
        classFile or "WARRIOR",
        name,
        tostring(level),
    }, "|"))
end

------------------------------------------------------------------------
--                    POSITION  RECEIVING
------------------------------------------------------------------------
function OneGuild:ProcessPosition(sender, data)
    if not data then return end
    if not self.db or not self.db.addonMembers then return end
    if not self.db.addonMembers[sender] then return end
    if sender == MyFullName() then return end

    local ms, xs, ys, cf, nm, ls = strsplit("|", data)
    local mid = tonumber(ms)
    local mx  = tonumber(xs)
    local my  = tonumber(ys)
    if not (mid and mx and my) then return end

    self.memberPositions[sender] = {
        mapID     = mid,
        x         = mx,
        y         = my,
        classFile = cf or "WARRIOR",
        name      = nm or sender,
        level     = tonumber(ls) or 0,
        time      = time(),
        sender    = sender,
    }
end

------------------------------------------------------------------------
-- Purge stale entries
------------------------------------------------------------------------
local function PurgeStale()
    local now = time()
    for k, v in pairs(OneGuild.memberPositions) do
        if (now - (v.time or 0)) > POSITION_TIMEOUT then
            OneGuild.memberPositions[k] = nil
        end
    end
end

------------------------------------------------------------------------
-- Clear a single member position (called on BYE / stale offline)
------------------------------------------------------------------------
function OneGuild:ClearMemberPosition(key)
    self.memberPositions[key] = nil
    if wmPins[key] then wmPins[key]:Hide() end
end

------------------------------------------------------------------------
--                  WORLD-MAP  PIN  UPDATE
------------------------------------------------------------------------
function OneGuild:UpdateWorldMapPins()
    if not mapPinsOn then
        for _, p in pairs(wmPins) do p:Hide() end
        return
    end
    if not WorldMapFrame or not WorldMapFrame:IsShown() then
        for _, p in pairs(wmPins) do p:Hide() end
        return
    end

    local viewMapID = WorldMapFrame:GetMapID()
    if not viewMapID then
        for _, p in pairs(wmPins) do p:Hide() end
        return
    end

    local canvas = GetCanvas()
    if not canvas then return end

    local cw, ch = canvas:GetSize()
    if not cw or cw < 1 or not ch or ch < 1 then return end

    -- Dynamic pin scaling based on map zoom level
    local scale = GetMapScaleFactor(viewMapID)
    local baseSz = GetPinSize()
    local sz = math.floor(baseSz * scale + 0.5)
    local lsz = math.floor(GetLabelSize() * math.max(scale * 0.8, 1) + 0.5)
    local iconSz = math.max(sz - 4, 8)

    local used = {}
    for key, pos in pairs(self.memberPositions) do
        local nx, ny = ToViewedMapCoords(viewMapID, pos.mapID, pos.x, pos.y)

        if nx and ny and nx >= -0.02 and nx <= 1.02 and ny >= -0.02 and ny <= 1.02 then
            used[key] = true

            local pin = wmPins[key]
            if not pin then
                pin = NewWMPin(key, canvas)
            end

            if pin:GetParent() ~= canvas then
                pin:SetParent(canvas)
            end

            -- Apply dynamic size
            pin:SetSize(sz + 4, sz + 16)
            pin.border:SetSize(sz + 4, sz + 4)
            pin.dot:SetSize(sz, sz)
            if pin.classIcon then
                pin.classIcon:SetSize(iconSz, iconSz)
            end
            pin.label:SetFont("Fonts\\FRIZQT__.TTF", lsz, "OUTLINE")

            pin:ClearAllPoints()
            pin:SetPoint("CENTER", canvas, "TOPLEFT", nx * cw, -ny * ch)

            local r, g, b = ClassRGB(pos.classFile)
            pin.dot:SetVertexColor(r, g, b, 1)
            -- Update class icon
            local coords = CLASS_ICON_COORDS[pos.classFile]
            if coords then
                pin.classIcon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
                pin.classIcon:Show()
            else
                pin.classIcon:Hide()
            end
            pin:SetAlpha(GetPinAlpha())
            pin.label:SetText(pos.name or "?")
            if not ShowNames() then pin.label:Hide() end
            pin.posData = pos
            pin:Show()
        end
    end

    for key, p in pairs(wmPins) do
        if not used[key] then p:Hide() end
    end
end

------------------------------------------------------------------------
--                       INITIALISATION
------------------------------------------------------------------------
function OneGuild:InitMap()
    if isMapInit then return end
    if not self:IsAuthorized() then return end
    isMapInit = true

    self:Debug("Map: Positions-Tracking wird initialisiert...")

    -- 1) Periodic position broadcast + stale cleanup
    posTicker = C_Timer.NewTicker(POS_INTERVAL, function()
        if OneGuild:IsAuthorized() then
            OneGuild:BroadcastPosition()
            PurgeStale()
        end
    end)

    -- First broadcast after a short delay
    C_Timer.After(2, function()
        if OneGuild:IsAuthorized() then OneGuild:BroadcastPosition() end
    end)

    -- 2) World-map driver (only ticks while the map is open)
    if WorldMapFrame then
        local wmTimer = CreateFrame("Frame", "OGuildWMTimer", WorldMapFrame)
        wmTimer:SetAllPoints()
        local el = 0
        wmTimer:SetScript("OnUpdate", function(_, dt)
            el = el + dt
            if el >= WM_UPDATE_HZ then
                el = 0
                OneGuild:UpdateWorldMapPins()
            end
        end)

        -- Also update when map zone changes
        hooksecurefunc(WorldMapFrame, "OnMapChanged", function()
            C_Timer.After(0.05, function()
                OneGuild:UpdateWorldMapPins()
            end)
        end)
    end

    self:Debug("Map: Positions-Tracking aktiv (Intervall " .. POS_INTERVAL .. "s)")

    -- Apply saved visibility setting
    if self.db and self.db.settings and self.db.settings.mapShowPins == false then
        mapPinsOn = false
    end

    self:Print("Karten-Tracking " .. self.COLORS.SUCCESS .. "aktiv|r — "
        .. "OneGuild-Mitglieder werden auf der Weltkarte (M) angezeigt.")
end

------------------------------------------------------------------------
-- Toggle
------------------------------------------------------------------------
function OneGuild:ToggleMapPins()
    mapPinsOn = not mapPinsOn
    if self.db and self.db.settings then
        self.db.settings.mapShowPins = mapPinsOn
    end
    if not mapPinsOn then
        for _, p in pairs(wmPins) do p:Hide() end
    end

    local state = mapPinsOn
        and (self.COLORS.SUCCESS .. "aktiviert|r")
        or  (self.COLORS.ERROR   .. "deaktiviert|r")
    self:Print("Weltkarten-Pins " .. state)
end

-- Called by Settings.lua when checkbox changes
function OneGuild:SetMapPinsEnabled(val)
    mapPinsOn = val
    if not mapPinsOn then
        for _, p in pairs(wmPins) do p:Hide() end
    end
end

-- Called by Settings.lua when pin size / label size / show names changes
function OneGuild:RefreshPinAppearance()
    local sz  = GetPinSize()
    local lsz = GetLabelSize()
    local sn  = ShowNames()
    local a   = GetPinAlpha()
    for _, pin in pairs(wmPins) do
        pin:SetSize(sz + 4, sz + 16)
        pin.border:SetSize(sz + 4, sz + 4)
        pin.dot:SetSize(sz, sz)
        if pin.classIcon then
            local iconSz = math.max(sz - 4, 8)
            pin.classIcon:SetSize(iconSz, iconSz)
        end
        pin:SetAlpha(a)
        pin.label:SetFont("Fonts\\FRIZQT__.TTF", lsz, "OUTLINE")
        if sn then
            pin.label:Show()
        else
            pin.label:Hide()
        end
    end
end

function OneGuild:AreMapPinsEnabled() return mapPinsOn end
