------------------------------------------------------------------------
-- OneGuild - UIEffects.lua
-- Premium visual effects: glows, shimmers, animated buttons, particles
-- Makes the UI look like no other addon
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r UIEffects.lua wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Effect Library (reusable everywhere)
------------------------------------------------------------------------
OneGuild.FX = {}

------------------------------------------------------------------------
-- 1) BREATHING GLOW: soft pulsing glow around any frame
--    Usage: OneGuild.FX:BreathingGlow(frame, r, g, b, size, speed)
------------------------------------------------------------------------
function OneGuild.FX:BreathingGlow(frame, r, g, b, size, speed)
    if not frame then return end
    r = r or 0.9; g = g or 0.6; b = b or 0.1
    size = size or 6; speed = speed or 2.5

    local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
    glow:SetPoint("TOPLEFT", frame, "TOPLEFT", -size, size)
    glow:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", size, -size)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetVertexColor(r, g, b, 0.15)

    local ag = glow:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.18)
    a1:SetToAlpha(0.04)
    a1:SetDuration(speed)
    a1:SetOrder(1)
    a1:SetSmoothing("IN_OUT")
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.04)
    a2:SetToAlpha(0.18)
    a2:SetDuration(speed)
    a2:SetOrder(2)
    a2:SetSmoothing("IN_OUT")
    ag:SetLooping("REPEAT")
    ag:Play()

    frame._breathGlow = glow
    return glow
end

------------------------------------------------------------------------
-- 2) BORDER SHIMMER: a moving highlight that travels along borders
--    Creates a cinematic "light sweep" effect
------------------------------------------------------------------------
function OneGuild.FX:BorderShimmer(frame, speed, color)
    if not frame then return end
    speed = speed or 3.0
    color = color or { 1, 0.85, 0.3, 0.6 }

    -- Top shimmer line
    local shimmer = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    shimmer:SetSize(60, 2)
    shimmer:SetTexture("Interface\\Buttons\\WHITE8x8")
    shimmer:SetVertexColor(color[1], color[2], color[3], 0)

    local elapsed = 0
    local direction = 1  -- 0=top, 1=right, 2=bottom, 3=left
    local phase = 0

    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        if not frame or not frame:IsVisible() then return end
        elapsed = elapsed + 0.016
        phase = (elapsed / speed) % 1.0

        local w = frame:GetWidth() or 200
        local h = frame:GetHeight() or 200
        local totalPerimeter = 2 * (w + h)
        local pos = phase * totalPerimeter

        shimmer:ClearAllPoints()
        local alpha = 0.5 + 0.3 * math.sin(elapsed * 4)

        if pos < w then
            -- Top edge: left to right
            shimmer:SetSize(40, 2)
            shimmer:SetPoint("TOPLEFT", frame, "TOPLEFT", pos - 20, 0)
            shimmer:SetVertexColor(color[1], color[2], color[3], alpha)
        elseif pos < w + h then
            -- Right edge: top to bottom
            local p = pos - w
            shimmer:SetSize(2, 40)
            shimmer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -p + 20)
            shimmer:SetVertexColor(color[1], color[2], color[3], alpha)
        elseif pos < 2 * w + h then
            -- Bottom edge: right to left
            local p = pos - w - h
            shimmer:SetSize(40, 2)
            shimmer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -p + 20, 0)
            shimmer:SetVertexColor(color[1], color[2], color[3], alpha)
        else
            -- Left edge: bottom to top
            local p = pos - 2 * w - h
            shimmer:SetSize(2, 40)
            shimmer:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, p - 20)
            shimmer:SetVertexColor(color[1], color[2], color[3], alpha)
        end
    end)

    frame._shimmerTicker = ticker
    return shimmer
end

------------------------------------------------------------------------
-- 3) HOVER GLOW: smooth glow that fades in on hover, out on leave
------------------------------------------------------------------------
function OneGuild.FX:HoverGlow(button, r, g, b)
    if not button then return end
    r = r or 1; g = g or 0.8; b = b or 0.2

    local hoverGlow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    hoverGlow:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    hoverGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
    hoverGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    hoverGlow:SetVertexColor(r, g, b, 0)

    local targetAlpha = 0
    local currentAlpha = 0

    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        if not button or not button:IsVisible() then return end
        local diff = targetAlpha - currentAlpha
        if math.abs(diff) < 0.005 then
            currentAlpha = targetAlpha
        else
            currentAlpha = currentAlpha + diff * 0.12
        end
        hoverGlow:SetVertexColor(r, g, b, currentAlpha)
    end)

    button:HookScript("OnEnter", function()
        targetAlpha = 0.25
    end)
    button:HookScript("OnLeave", function()
        targetAlpha = 0
    end)

    button._hoverGlow = hoverGlow
    return hoverGlow
end

------------------------------------------------------------------------
-- 4) MODERN BUTTON STYLE: apply premium look to any button
--    Adds inner highlight, hover animation, click flash
------------------------------------------------------------------------
function OneGuild.FX:StyleButton(btn, theme)
    if not btn then return end
    theme = theme or "gold"

    local colors = {
        gold   = { bg = {0.18, 0.12, 0.04}, border = {0.7, 0.5, 0.15}, hover = {0.35, 0.25, 0.08}, text = {1, 0.85, 0.3}, glow = {0.9, 0.7, 0.1} },
        green  = { bg = {0.04, 0.15, 0.06}, border = {0.15, 0.6, 0.2},  hover = {0.08, 0.3, 0.12},  text = {0.4, 1, 0.5},   glow = {0.2, 0.8, 0.3} },
        blue   = { bg = {0.04, 0.08, 0.18}, border = {0.15, 0.35, 0.7}, hover = {0.08, 0.15, 0.35},  text = {0.5, 0.8, 1},   glow = {0.2, 0.5, 1} },
        red    = { bg = {0.18, 0.04, 0.04}, border = {0.6, 0.15, 0.1},  hover = {0.35, 0.08, 0.06},  text = {1, 0.4, 0.3},   glow = {0.9, 0.2, 0.1} },
        purple = { bg = {0.12, 0.04, 0.18}, border = {0.5, 0.15, 0.7},  hover = {0.25, 0.08, 0.35},  text = {0.8, 0.5, 1},   glow = {0.6, 0.2, 0.9} },
    }
    local c = colors[theme] or colors.gold

    btn:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    btn:SetBackdropColor(c.bg[1], c.bg[2], c.bg[3], 0.95)
    btn:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 0.8)

    -- Inner top highlight for depth
    local highlight = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    highlight:SetHeight(1)
    highlight:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    highlight:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    highlight:SetTexture("Interface\\Buttons\\WHITE8x8")
    highlight:SetVertexColor(1, 1, 1, 0.08)

    -- Bottom shadow line
    local shadow = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    shadow:SetHeight(1)
    shadow:SetPoint("BOTTOMLEFT", btn, "BOTTOMLEFT", 3, 3)
    shadow:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -3, 3)
    shadow:SetTexture("Interface\\Buttons\\WHITE8x8")
    shadow:SetVertexColor(0, 0, 0, 0.2)

    -- Hover glow
    OneGuild.FX:HoverGlow(btn, c.glow[1], c.glow[2], c.glow[3])

    -- Smooth hover color transition
    local isHovering = false
    local bgR, bgG, bgB = c.bg[1], c.bg[2], c.bg[3]
    local tR, tG, tB = bgR, bgG, bgB

    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        if not btn or not btn:IsVisible() then return end
        bgR = bgR + (tR - bgR) * 0.1
        bgG = bgG + (tG - bgG) * 0.1
        bgB = bgB + (tB - bgB) * 0.1
        btn:SetBackdropColor(bgR, bgG, bgB, 0.95)
    end)

    btn:HookScript("OnEnter", function()
        tR, tG, tB = c.hover[1], c.hover[2], c.hover[3]
        btn:SetBackdropBorderColor(c.border[1] * 1.3, c.border[2] * 1.3, c.border[3] * 1.3, 1)
        highlight:SetVertexColor(1, 1, 1, 0.15)
    end)
    btn:HookScript("OnLeave", function()
        tR, tG, tB = c.bg[1], c.bg[2], c.bg[3]
        btn:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 0.8)
        highlight:SetVertexColor(1, 1, 1, 0.08)
    end)

    -- Click flash
    btn:HookScript("OnClick", function()
        btn:SetBackdropColor(1, 1, 1, 0.3)
        C_Timer.After(0.08, function()
            if btn then btn:SetBackdropColor(c.hover[1], c.hover[2], c.hover[3], 0.95) end
        end)
    end)

    btn._styledTheme = theme
end

------------------------------------------------------------------------
-- 5) ACTIVE TAB INDICATOR: animated underline for active tab
------------------------------------------------------------------------
function OneGuild.FX:TabIndicator(tabContainer, tabs)
    if not tabContainer then return end

    -- Create the sliding indicator bar
    local indicator = tabContainer:CreateTexture(nil, "OVERLAY", nil, 5)
    indicator:SetHeight(2)
    indicator:SetTexture("Interface\\Buttons\\WHITE8x8")
    indicator:SetVertexColor(1, 0.85, 0.3, 0.9)
    indicator._targetLeft = 0
    indicator._targetWidth = 80
    indicator._currentLeft = 0
    indicator._currentWidth = 80

    -- Glow under indicator
    local indicatorGlow = tabContainer:CreateTexture(nil, "OVERLAY", nil, 4)
    indicatorGlow:SetHeight(6)
    indicatorGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    indicatorGlow:SetVertexColor(1, 0.7, 0.1, 0.15)

    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        if not tabContainer or not tabContainer:IsVisible() then return end
        indicator._currentLeft = indicator._currentLeft + (indicator._targetLeft - indicator._currentLeft) * 0.15
        indicator._currentWidth = indicator._currentWidth + (indicator._targetWidth - indicator._currentWidth) * 0.15

        indicator:ClearAllPoints()
        indicator:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMLEFT", indicator._currentLeft, -1)
        indicator:SetWidth(math.max(1, indicator._currentWidth))

        indicatorGlow:ClearAllPoints()
        indicatorGlow:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMLEFT", indicator._currentLeft - 4, -4)
        indicatorGlow:SetWidth(math.max(1, indicator._currentWidth + 8))
    end)

    tabContainer._indicator = indicator
    tabContainer._indicatorGlow = indicatorGlow
    return indicator
end

function OneGuild.FX:MoveTabIndicator(tabContainer, tabButton)
    if not tabContainer or not tabContainer._indicator or not tabButton then return end
    local ind = tabContainer._indicator
    local left = tabButton:GetLeft() - tabContainer:GetLeft()
    ind._targetLeft = left
    ind._targetWidth = tabButton:GetWidth()
end

------------------------------------------------------------------------
-- 6) ROW HOVER HIGHLIGHT: smooth highlight for list rows
------------------------------------------------------------------------
function OneGuild.FX:RowHover(row, r, g, b)
    if not row then return end
    r = r or 0.4; g = g or 0.3; b = b or 0.1
    row:EnableMouse(true)

    -- Left accent bar
    local accent = row:CreateTexture(nil, "OVERLAY", nil, 3)
    accent:SetWidth(2)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    accent:SetVertexColor(r * 2, g * 2, b * 2, 0)

    local tAlpha = 0
    local cAlpha = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        if not row:IsVisible() then return end
        cAlpha = cAlpha + (tAlpha - cAlpha) * 0.15
        accent:SetVertexColor(r * 2, g * 2, b * 2, cAlpha)
    end)

    row:HookScript("OnEnter", function()
        tAlpha = 0.9
        row:SetBackdropBorderColor(r * 1.5, g * 1.5, b * 1.5, 0.7)
    end)
    row:HookScript("OnLeave", function()
        tAlpha = 0
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.4)
    end)

    row._rowAccent = accent
end

------------------------------------------------------------------------
-- 7) FLOATING PARTICLES: ambient sparkle particles (for special frames)
------------------------------------------------------------------------
function OneGuild.FX:SparkleParticles(frame, count, r, g, b)
    if not frame then return end
    count = count or 8
    r = r or 1; g = g or 0.85; b = b or 0.3

    local particles = {}
    for i = 1, count do
        local p = frame:CreateTexture(nil, "OVERLAY", nil, 6)
        p:SetSize(2, 2)
        p:SetTexture("Interface\\Buttons\\WHITE8x8")
        p:SetVertexColor(r, g, b, 0)
        p._x = math.random() * (frame:GetWidth() or 200)
        p._y = -math.random() * (frame:GetHeight() or 100)
        p._speed = 8 + math.random() * 15
        p._phase = math.random() * 6.28
        p._size = 1 + math.random() * 2
        p:SetSize(p._size, p._size)
        particles[i] = p
    end

    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.032, function()
        if not frame or not frame:IsVisible() then return end
        elapsed = elapsed + 0.032
        local fw = frame:GetWidth() or 200
        local fh = frame:GetHeight() or 100

        for _, p in ipairs(particles) do
            p._y = p._y + p._speed * 0.032
            if p._y > 0 then
                p._y = -fh
                p._x = math.random() * fw
                p._phase = math.random() * 6.28
            end
            local alpha = 0.15 + 0.25 * math.sin(elapsed * 2 + p._phase)
            alpha = alpha * math.min(1, (fh + p._y) / (fh * 0.3))  -- fade near top
            p:SetVertexColor(r, g, b, math.max(0, alpha))
            p:ClearAllPoints()
            p:SetPoint("TOPLEFT", frame, "TOPLEFT", p._x, p._y)
        end
    end)

    frame._particleTicker = ticker
end

------------------------------------------------------------------------
-- 8) TEXT SHIMMER: golden shimmer sweep across text font strings
------------------------------------------------------------------------
function OneGuild.FX:TextGlow(fontString, r, g, b, speed)
    if not fontString then return end
    r = r or 1; g = g or 0.85; b = b or 0.4
    speed = speed or 3.0

    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.032, function()
        if not fontString or not fontString:IsVisible() then return end
        elapsed = elapsed + 0.032
        local pulse = 0.7 + 0.3 * math.sin(elapsed / speed * 6.28)
        fontString:SetTextColor(r * pulse, g * pulse, b * pulse, 1)
    end)

    fontString._textGlowTicker = ticker
end

------------------------------------------------------------------------
-- 9) ICON QUALITY GLOW: colored glow ring matching WoW item quality
------------------------------------------------------------------------
function OneGuild.FX:QualityGlow(iconFrame, quality)
    if not iconFrame then return end
    local qualityColors = {
        [0] = { 0.6, 0.6, 0.6 },   -- Poor (grey)
        [1] = { 1, 1, 1 },           -- Common (white)
        [2] = { 0.12, 1, 0 },        -- Uncommon (green)
        [3] = { 0, 0.44, 0.87 },     -- Rare (blue)
        [4] = { 0.64, 0.21, 0.93 },  -- Epic (purple)
        [5] = { 1, 0.5, 0 },         -- Legendary (orange)
        [6] = { 0.9, 0.8, 0.5 },     -- Artifact (gold)
        [7] = { 0, 0.8, 1 },         -- Heirloom (cyan)
    }
    local c = qualityColors[quality or 1] or qualityColors[1]

    local ring = iconFrame:GetParent():CreateTexture(nil, "OVERLAY", nil, 3)
    ring:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 2, -2)
    ring:SetTexture("Interface\\Buttons\\WHITE8x8")
    ring:SetVertexColor(c[1], c[2], c[3], 0.35)

    -- Inner clear
    local inner = iconFrame:GetParent():CreateTexture(nil, "OVERLAY", nil, 4)
    inner:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", 0, 0)
    inner:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 0, 0)
    inner:SetTexture("Interface\\Buttons\\WHITE8x8")
    inner:SetVertexColor(0, 0, 0, 0)  -- transparent, just covers the ring's center

    -- Pulse
    local ag = ring:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.4)
    a1:SetToAlpha(0.15)
    a1:SetDuration(1.5)
    a1:SetOrder(1)
    a1:SetSmoothing("IN_OUT")
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.15)
    a2:SetToAlpha(0.4)
    a2:SetDuration(1.5)
    a2:SetOrder(2)
    a2:SetSmoothing("IN_OUT")
    ag:SetLooping("REPEAT")
    ag:Play()

    return ring
end

------------------------------------------------------------------------
-- 10) NOTIFICATION FLASH: brief attention-grabbing flash on a frame
------------------------------------------------------------------------
function OneGuild.FX:Flash(frame, r, g, b, duration)
    if not frame then return end
    r = r or 1; g = g or 1; b = b or 1
    duration = duration or 0.4

    local flash = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints(frame)
    flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    flash:SetVertexColor(r, g, b, 0.4)

    local elapsed = 0
    local ticker
    ticker = C_Timer.NewTicker(0.016, function()
        elapsed = elapsed + 0.016
        local progress = elapsed / duration
        if progress >= 1 then
            flash:SetVertexColor(r, g, b, 0)
            flash:Hide()
            ticker:Cancel()
            return
        end
        flash:SetVertexColor(r, g, b, 0.4 * (1 - progress))
    end)
end

------------------------------------------------------------------------
-- Apply effects after main UI is built
------------------------------------------------------------------------
function OneGuild.FX:ApplyToMainUI()
    local f = OneGuild.mainFrame
    if not f then return end

    -- Border shimmer on main frame
    self:BorderShimmer(f, 5.0, { 1, 0.75, 0.2, 0.5 })

    -- Sparkle particles on main frame (ambient)
    self:SparkleParticles(f, 12, 1, 0.8, 0.3)

    -- Tab indicator (sliding animated underline)
    local tabContainer = nil
    for i, btn in ipairs(OneGuild.tabButtons) do
        if btn:GetParent() then
            tabContainer = btn:GetParent()
            break
        end
    end

    if tabContainer then
        self:TabIndicator(tabContainer, OneGuild.tabButtons)

        -- Hook ShowTab to animate the indicator
        local origShowTab = OneGuild.ShowTab
        OneGuild.ShowTab = function(self2, index)
            origShowTab(self2, index)
            if tabContainer and OneGuild.tabButtons[index] then
                C_Timer.After(0.02, function()
                    OneGuild.FX:MoveTabIndicator(tabContainer, OneGuild.tabButtons[index])
                end)
            end
        end

        -- Initialize indicator to current tab
        C_Timer.After(0.1, function()
            local idx = OneGuild.currentTab or 1
            if OneGuild.tabButtons[idx] then
                OneGuild.FX:MoveTabIndicator(tabContainer, OneGuild.tabButtons[idx])
            end
        end)
    end

    -- Style all tab buttons with hover glow
    for i, tab in ipairs(OneGuild.tabButtons) do
        self:HoverGlow(tab, 0.9, 0.7, 0.1)
    end

    -- Title text golden shimmer pulse
    if f.titleText then
        self:TextGlow(f.titleText, 1, 0.85, 0.4, 4.0)
    end

    -- Breathing glow on the header/logo area
    self:BreathingGlow(f, 0.7, 0.5, 0.1, 8, 3.5)
end

------------------------------------------------------------------------
-- Style all child BackdropTemplate buttons within a frame by theme
-- Recursively finds buttons and applies StyleButton
------------------------------------------------------------------------
function OneGuild.FX:StyleChildButtons(parent, theme, maxDepth)
    if not parent then return end
    maxDepth = maxDepth or 2
    if maxDepth <= 0 then return end

    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsObjectType("Button") and child.SetBackdrop and not child._styledTheme then
            -- Skip very small buttons (close buttons etc)
            local w = child:GetWidth() or 0
            if w >= 50 then
                self:StyleButton(child, theme)
            end
        end
        -- Recurse
        self:StyleChildButtons(child, theme, maxDepth - 1)
    end
end

------------------------------------------------------------------------
-- Style a dialog frame: shimmer border + style buttons inside
------------------------------------------------------------------------
function OneGuild.FX:StyleDialog(dialog, theme)
    if not dialog or dialog._fxStyled then return end
    dialog._fxStyled = true
    theme = theme or "gold"

    -- Border shimmer (slower, more subtle)
    self:BorderShimmer(dialog, 4.0, { 0.6, 0.8, 1, 0.4 })

    -- Breathing glow
    self:BreathingGlow(dialog, 0.3, 0.5, 0.8, 8, 3.0)

    -- Style buttons inside
    C_Timer.After(0.05, function()
        if dialog then
            OneGuild.FX:StyleChildButtons(dialog, theme, 3)
        end
    end)
end

------------------------------------------------------------------------
-- Hook common dialog frames to auto-style when shown
------------------------------------------------------------------------
function OneGuild.FX:HookDialogs()
    local dialogNames = {
        "OneGuildAddListing",
        "OneGuildAddNote",
        "OneGuildCreateRaid",
        "OneGuildCreateEvent",
        "OneGuildAuctionFrame",
        "OneGuildDKPPanel",
        "OneGuildDKPHistoryFrame",
        "OneGuildAuctionBidFrame",
        "OneGuildAdminLogin",
    }

    local hooked = {}
    C_Timer.NewTicker(1.0, function()
        for _, name in ipairs(dialogNames) do
            local frame = _G[name]
            if frame and not hooked[name] then
                hooked[name] = true
                frame:HookScript("OnShow", function(self)
                    if not self._fxStyled then
                        OneGuild.FX:StyleDialog(self, "gold")
                    end
                end)
                -- Style immediately if already visible
                if frame:IsVisible() and not frame._fxStyled then
                    OneGuild.FX:StyleDialog(frame, "gold")
                end
            end
        end

        -- Stop once all are hooked (or after 30 seconds)
        local allHooked = true
        for _, name in ipairs(dialogNames) do
            if _G[name] and not hooked[name] then allHooked = false break end
        end
        -- Keep running - dialogs may be created later
    end)
end

------------------------------------------------------------------------
-- Auto-apply when addon loads (after UI is built)
------------------------------------------------------------------------
local applyFrame = CreateFrame("Frame")
applyFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
applyFrame:SetScript("OnEvent", function()
    -- Wait for UI to be fully built
    C_Timer.After(2.0, function()
        if OneGuild.mainFrame and OneGuild.FX then
            OneGuild.FX:ApplyToMainUI()
            OneGuild.FX:HookDialogs()
        end
    end)
end)
