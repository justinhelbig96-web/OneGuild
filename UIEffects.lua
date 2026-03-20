------------------------------------------------------------------------
-- OneGuild - UIEffects.lua  v1.4.2
-- Premium visual effects: shines, glows, animated progress, particles
-- Makes the UI look like no other addon
------------------------------------------------------------------------
print("|cFFFFB800[OneGuild]|r UIEffects.lua v1.4.2 wird geladen...")

local _, OneGuild = ...

------------------------------------------------------------------------
-- Effect Library
------------------------------------------------------------------------
OneGuild.FX = {}
local FX = OneGuild.FX
local appliedToMain = false

-- Track all created tickers and textures for live cleanup
FX._tickers  = {}   -- { ticker1, ticker2, ... }
FX._textures = {}   -- { tex1, tex2, ... }
FX._frames   = {}   -- { frame1, ... } (e.g. AnimatedBar track frames)

local function TrackTicker(t)
    if t then table.insert(FX._tickers, t) end
    return t
end

local function TrackTexture(tex)
    if tex then table.insert(FX._textures, tex) end
    return tex
end

local function TrackFrame(f)
    if f then table.insert(FX._frames, f) end
    return f
end

------------------------------------------------------------------------
-- 1) SHINE SWEEP: a diagonal light beam sweeps across a frame
--    Very visible, like a card game shine effect
------------------------------------------------------------------------
function FX:ShineSweep(frame, speed, color)
    if not frame or frame._shineSweep then return end
    speed = speed or 4.0
    color = color or { 1, 0.85, 0.3 }

    -- Create a tall narrow "beam" texture
    local shine = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    shine:SetTexture("Interface\\Buttons\\WHITE8x8")
    shine:SetHeight(400)
    shine:SetWidth(18)
    shine:SetVertexColor(color[1], color[2], color[3], 0)
    shine:SetBlendMode("ADD")
    frame._shineSweep = shine

    local elapsed = 0
    C_Timer.NewTicker(0.016, function()
        if not frame or not frame:IsVisible() then return end
        elapsed = elapsed + 0.016
        local progress = (elapsed / speed) % 1.0
        local fw = frame:GetWidth()
        if not fw or fw < 10 then return end

        local fh = frame:GetHeight() or 400
        shine:SetHeight(fh + 40)

        -- Move from left to right
        local x = -40 + (fw + 80) * progress

        shine:ClearAllPoints()
        shine:SetPoint("TOP", frame, "TOPLEFT", x, 20)

        -- Fade in center, out at edges
        local centerDist = math.abs(progress - 0.5) * 2
        local alpha = 0.4 * (1 - centerDist * centerDist)
        shine:SetVertexColor(color[1], color[2], color[3], math.max(0, alpha))
    end)
end

------------------------------------------------------------------------
-- 2) BORDER GLOW PULSE: glowing edges that pulse visibly
------------------------------------------------------------------------
function FX:BorderGlowPulse(frame, r, g, b, speed)
    if not frame or frame._borderGlowPulse then return end
    r = r or 0.9; g = g or 0.7; b = b or 0.2
    speed = speed or 3.0

    local top = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    top:SetTexture("Interface\\Buttons\\WHITE8x8")
    top:SetBlendMode("ADD")
    top:SetHeight(2)
    top:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    top:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)

    local bottom = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    bottom:SetTexture("Interface\\Buttons\\WHITE8x8")
    bottom:SetBlendMode("ADD")
    bottom:SetHeight(2)
    bottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)
    bottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    local left = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    left:SetTexture("Interface\\Buttons\\WHITE8x8")
    left:SetBlendMode("ADD")
    left:SetWidth(2)
    left:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    left:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 2)

    local right = frame:CreateTexture(nil, "OVERLAY", nil, 2)
    right:SetTexture("Interface\\Buttons\\WHITE8x8")
    right:SetBlendMode("ADD")
    right:SetWidth(2)
    right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    right:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)

    local edges = { top, bottom, left, right }
    frame._borderGlowPulse = edges

    local elapsed = 0
    C_Timer.NewTicker(0.02, function()
        if not frame or not frame:IsVisible() then return end
        elapsed = elapsed + 0.02
        local alpha = 0.15 + 0.25 * math.sin(elapsed / speed * 6.28)
        for _, e in ipairs(edges) do
            e:SetVertexColor(r, g, b, alpha)
        end
    end)
end

------------------------------------------------------------------------
-- 3) BORDER SHIMMER: traveling light point along frame border
------------------------------------------------------------------------
function FX:BorderShimmer(frame, speed, color)
    if not frame or frame._shimmerTicker then return end
    speed = speed or 3.0
    color = color or { 1, 0.85, 0.3, 0.7 }

    local shimmer = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    shimmer:SetTexture("Interface\\Buttons\\WHITE8x8")
    shimmer:SetBlendMode("ADD")
    shimmer:SetSize(10, 10)
    shimmer:SetVertexColor(color[1], color[2], color[3], 0)

    -- Trailing glow (larger, softer) for a comet-tail look
    local trail = frame:CreateTexture(nil, "OVERLAY", nil, 6)
    trail:SetTexture("Interface\\Buttons\\WHITE8x8")
    trail:SetBlendMode("ADD")
    trail:SetSize(6, 6)
    trail:SetVertexColor(color[1], color[2], color[3], 0)

    local elapsed = 0
    local prevX, prevY = 0, 0

    -- Convert perimeter position to x,y offset from TOPLEFT
    local function PosToXY(pos, w, h)
        local perim = 2 * (w + h)
        pos = pos % perim
        if pos < w then
            return pos, 0                      -- top edge
        elseif pos < w + h then
            return w, -(pos - w)               -- right edge
        elseif pos < 2 * w + h then
            return w - (pos - w - h), -h       -- bottom edge
        else
            return 0, -(h - (pos - 2 * w - h)) -- left edge
        end
    end

    local ticker = C_Timer.NewTicker(0.016, function()
        if not frame or not frame:IsVisible() then return end
        elapsed = elapsed + 0.016
        local phase = (elapsed / speed) % 1.0

        local w = frame:GetWidth() or 0
        local h = frame:GetHeight() or 0
        if w < 10 or h < 10 then return end

        local totalPerimeter = 2 * (w + h)
        local pos = phase * totalPerimeter
        local alpha = 0.5 + 0.4 * math.sin(elapsed * 5)

        local x, y = PosToXY(pos, w, h)

        -- Main shimmer dot (always square, no flip)
        shimmer:ClearAllPoints()
        shimmer:SetPoint("CENTER", frame, "TOPLEFT", x, y)
        shimmer:SetVertexColor(color[1], color[2], color[3], alpha)

        -- Trailing dot follows slightly behind
        local trailPos = pos - 18
        local tx, ty = PosToXY(trailPos, w, h)
        trail:ClearAllPoints()
        trail:SetPoint("CENTER", frame, "TOPLEFT", tx, ty)
        trail:SetVertexColor(color[1], color[2], color[3], alpha * 0.5)
    end)

    frame._shimmerTicker = ticker
    return shimmer
end

------------------------------------------------------------------------
-- 4) GOLDEN PARTICLES: visible sparkles floating upward
------------------------------------------------------------------------
function FX:GoldParticles(frame, count)
    if not frame or frame._goldParticles then return end
    count = count or 15

    local particles = {}
    frame._goldParticles = particles

    for i = 1, count do
        local p = frame:CreateTexture(nil, "ARTWORK", nil, 7)
        p:SetTexture("Interface\\Buttons\\WHITE8x8")
        p:SetBlendMode("ADD")
        local s = 2 + math.random() * 3
        p:SetSize(s, s)
        p._vx = -5 + math.random() * 10
        p._vy = 15 + math.random() * 25
        p._phase = math.random() * 6.28
        p._lifetime = 3 + math.random() * 4
        p._age = math.random() * p._lifetime   -- stagger starts
        p._startX = 0
        p._startY = 0
        p:SetVertexColor(1, 0.8, 0.2, 0)
        particles[i] = p
    end

    local function ResetParticle(p, fw, fh)
        p._startX = 20 + math.random() * math.max(10, fw - 40)
        p._startY = -(fh * 0.4 + math.random() * fh * 0.5)
        p._age = 0
        p._vx = -5 + math.random() * 10
        p._vy = 15 + math.random() * 25
        p._lifetime = 3 + math.random() * 4
        p._phase = math.random() * 6.28
        local s = 2 + math.random() * 3
        p:SetSize(s, s)
    end

    C_Timer.NewTicker(0.025, function()
        if not frame or not frame:IsVisible() then return end
        local fw = frame:GetWidth()
        local fh = frame:GetHeight()
        if not fw or fw < 20 or not fh or fh < 20 then return end

        for _, p in ipairs(particles) do
            p._age = p._age + 0.025
            if p._age >= p._lifetime or p._startX == 0 then
                ResetParticle(p, fw, fh)
            end

            local progress = p._age / p._lifetime
            local x = p._startX + p._vx * p._age + 3 * math.sin(p._age * 2 + p._phase)
            local y = p._startY + p._vy * p._age

            -- Fade: in first 20%, full center, out last 20%
            local alpha = 1
            if progress < 0.2 then
                alpha = progress / 0.2
            elseif progress > 0.8 then
                alpha = (1 - progress) / 0.2
            end
            alpha = alpha * (0.25 + 0.35 * math.sin(p._age * 3 + p._phase))

            p:ClearAllPoints()
            p:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", x, -y)
            p:SetVertexColor(1, 0.75 + 0.25 * math.sin(p._age), 0.15, math.max(0, alpha))
        end
    end)
end

------------------------------------------------------------------------
-- 5) ANIMATED PROGRESS BAR: decorative animated bar with glow edge
------------------------------------------------------------------------
function FX:AnimatedBar(parent, anchorFrame, anchorPoint, offsetX, offsetY, width, height, speed, color)
    if not parent then return end
    color = color or { 0.9, 0.7, 0.1 }
    speed = speed or 2.0
    width = width or 200
    height = height or 3

    -- Background track
    local track = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    track:SetSize(width, height + 2)
    track:SetPoint(anchorPoint or "TOPLEFT", anchorFrame or parent, anchorPoint or "TOPLEFT", offsetX or 0, offsetY or 0)
    track:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    track:SetBackdropColor(0.05, 0.05, 0.08, 0.6)

    -- Fill bar
    local fill = track:CreateTexture(nil, "ARTWORK", nil, 1)
    fill:SetHeight(height)
    fill:SetPoint("LEFT", track, "LEFT", 1, 0)
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetWidth(1)

    -- Leading glow
    local glow = track:CreateTexture(nil, "ARTWORK", nil, 2)
    glow:SetSize(12, height + 6)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetBlendMode("ADD")

    local elapsed = 0
    C_Timer.NewTicker(0.016, function()
        if not parent or not parent:IsVisible() then return end
        elapsed = elapsed + 0.016
        local progress = (elapsed / speed) % 1.0
        local barWidth = math.max(1, (width - 2) * progress)

        fill:SetWidth(barWidth)

        local r = color[1] * (0.6 + 0.4 * progress)
        local g = color[2] * (1 - 0.3 * progress)
        local b = color[3] * (1 - 0.5 * progress)
        fill:SetVertexColor(r, g, b, 0.85)

        glow:ClearAllPoints()
        glow:SetPoint("RIGHT", fill, "RIGHT", 4, 0)
        local glowAlpha = 0.4 + 0.3 * math.sin(elapsed * 5)
        glow:SetVertexColor(r * 1.2, g * 1.2, b * 1.2, glowAlpha)

        -- Flash on reset
        if progress < 0.02 then
            fill:SetVertexColor(1, 1, 1, 0.7)
        end
    end)

    return track
end

------------------------------------------------------------------------
-- 6) HOVER GLOW: smooth glow on button hover
------------------------------------------------------------------------
function FX:HoverGlow(button, r, g, b)
    if not button or button._hoverGlow then return end
    r = r or 1; g = g or 0.8; b = b or 0.2

    local hoverGlow = button:CreateTexture(nil, "BACKGROUND", nil, -1)
    hoverGlow:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
    hoverGlow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 4, -4)
    hoverGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
    hoverGlow:SetBlendMode("ADD")
    hoverGlow:SetVertexColor(r, g, b, 0)

    local targetAlpha = 0
    local currentAlpha = 0

    C_Timer.NewTicker(0.016, function()
        if not button or not button:IsVisible() then return end
        local diff = targetAlpha - currentAlpha
        if math.abs(diff) < 0.005 then
            currentAlpha = targetAlpha
        else
            currentAlpha = currentAlpha + diff * 0.15
        end
        hoverGlow:SetVertexColor(r, g, b, currentAlpha)
    end)

    button:HookScript("OnEnter", function() targetAlpha = 0.3 end)
    button:HookScript("OnLeave", function() targetAlpha = 0 end)

    button._hoverGlow = hoverGlow
    return hoverGlow
end

------------------------------------------------------------------------
-- 7) MODERN BUTTON STYLE: premium styling with animations
------------------------------------------------------------------------
function FX:StyleButton(btn, theme)
    if not btn or btn._styledTheme then return end
    theme = theme or "gold"

    local colors = {
        gold   = { bg = {0.18, 0.12, 0.04}, border = {0.7, 0.5, 0.15}, hover = {0.35, 0.25, 0.08}, glow = {0.9, 0.7, 0.1} },
        green  = { bg = {0.04, 0.15, 0.06}, border = {0.15, 0.6, 0.2},  hover = {0.08, 0.3, 0.12},  glow = {0.2, 0.8, 0.3} },
        blue   = { bg = {0.04, 0.08, 0.18}, border = {0.15, 0.35, 0.7}, hover = {0.08, 0.15, 0.35},  glow = {0.2, 0.5, 1} },
        red    = { bg = {0.18, 0.04, 0.04}, border = {0.6, 0.15, 0.1},  hover = {0.35, 0.08, 0.06},  glow = {0.9, 0.2, 0.1} },
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

    -- Top highlight line
    local hl = btn:CreateTexture(nil, "ARTWORK", nil, 2)
    hl:SetHeight(1)
    hl:SetPoint("TOPLEFT", btn, "TOPLEFT", 3, -3)
    hl:SetPoint("TOPRIGHT", btn, "TOPRIGHT", -3, -3)
    hl:SetTexture("Interface\\Buttons\\WHITE8x8")
    hl:SetVertexColor(1, 1, 1, 0.1)

    FX:HoverGlow(btn, c.glow[1], c.glow[2], c.glow[3])

    -- Smooth hover BG transition
    local bgR, bgG, bgB = c.bg[1], c.bg[2], c.bg[3]
    local tR, tG, tB = bgR, bgG, bgB

    C_Timer.NewTicker(0.02, function()
        if not btn or not btn:IsVisible() then return end
        bgR = bgR + (tR - bgR) * 0.12
        bgG = bgG + (tG - bgG) * 0.12
        bgB = bgB + (tB - bgB) * 0.12
        btn:SetBackdropColor(bgR, bgG, bgB, 0.95)
    end)

    btn:HookScript("OnEnter", function()
        tR, tG, tB = c.hover[1], c.hover[2], c.hover[3]
        btn:SetBackdropBorderColor(c.border[1] * 1.4, c.border[2] * 1.4, c.border[3] * 1.4, 1)
        hl:SetVertexColor(1, 1, 1, 0.2)
    end)
    btn:HookScript("OnLeave", function()
        tR, tG, tB = c.bg[1], c.bg[2], c.bg[3]
        btn:SetBackdropBorderColor(c.border[1], c.border[2], c.border[3], 0.8)
        hl:SetVertexColor(1, 1, 1, 0.1)
    end)

    -- Click flash
    btn:HookScript("OnClick", function()
        btn:SetBackdropColor(1, 1, 1, 0.3)
        C_Timer.After(0.1, function()
            if btn then tR, tG, tB = c.bg[1], c.bg[2], c.bg[3] end
        end)
    end)

    btn._styledTheme = theme
end

------------------------------------------------------------------------
-- 8) TAB INDICATOR: animated sliding underline
------------------------------------------------------------------------
function FX:TabIndicator(tabContainer, tabs)
    if not tabContainer or tabContainer._indicator then return end

    local indicator = tabContainer:CreateTexture(nil, "OVERLAY", nil, 5)
    indicator:SetHeight(3)
    indicator:SetTexture("Interface\\Buttons\\WHITE8x8")
    indicator:SetBlendMode("ADD")
    indicator:SetVertexColor(1, 0.85, 0.3, 0.9)
    indicator._targetLeft = 0
    indicator._targetWidth = 80
    indicator._currentLeft = 0
    indicator._currentWidth = 80

    -- Wider glow under indicator
    local glow = tabContainer:CreateTexture(nil, "OVERLAY", nil, 4)
    glow:SetHeight(8)
    glow:SetTexture("Interface\\Buttons\\WHITE8x8")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.7, 0.1, 0.2)

    C_Timer.NewTicker(0.016, function()
        if not tabContainer or not tabContainer:IsVisible() then return end
        indicator._currentLeft = indicator._currentLeft + (indicator._targetLeft - indicator._currentLeft) * 0.12
        indicator._currentWidth = indicator._currentWidth + (indicator._targetWidth - indicator._currentWidth) * 0.12

        indicator:ClearAllPoints()
        indicator:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMLEFT", indicator._currentLeft, -2)
        indicator:SetWidth(math.max(1, indicator._currentWidth))

        glow:ClearAllPoints()
        glow:SetPoint("BOTTOMLEFT", tabContainer, "BOTTOMLEFT", indicator._currentLeft - 6, -6)
        glow:SetWidth(math.max(1, indicator._currentWidth + 12))
    end)

    tabContainer._indicator = indicator
    tabContainer._indicatorGlow = glow
    return indicator
end

function FX:MoveTabIndicator(tabContainer, tabButton)
    if not tabContainer or not tabContainer._indicator or not tabButton then return end
    local ind = tabContainer._indicator
    local left = tabButton:GetLeft() - tabContainer:GetLeft()
    ind._targetLeft = left
    ind._targetWidth = tabButton:GetWidth()
end

------------------------------------------------------------------------
-- 9) ROW HOVER: accent bar + background highlight on hover
------------------------------------------------------------------------
function FX:RowHover(row, r, g, b)
    if not row or row._rowAccent then return end
    r = r or 0.4; g = g or 0.3; b = b or 0.1
    row:EnableMouse(true)

    local accent = row:CreateTexture(nil, "OVERLAY", nil, 3)
    accent:SetWidth(3)
    accent:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
    accent:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 2, 2)
    accent:SetTexture("Interface\\Buttons\\WHITE8x8")
    accent:SetBlendMode("ADD")
    accent:SetVertexColor(r * 2, g * 2, b * 2, 0)

    local tAlpha = 0
    local cAlpha = 0
    C_Timer.NewTicker(0.02, function()
        if not row or not row:IsVisible() then return end
        cAlpha = cAlpha + (tAlpha - cAlpha) * 0.15
        accent:SetVertexColor(r * 2, g * 2, b * 2, cAlpha)
    end)

    row:HookScript("OnEnter", function()
        tAlpha = 1
        row:SetBackdropBorderColor(r * 1.5, g * 1.5, b * 1.5, 0.7)
    end)
    row:HookScript("OnLeave", function()
        tAlpha = 0
        row:SetBackdropBorderColor(0.25, 0.25, 0.3, 0.4)
    end)

    row._rowAccent = accent
end

------------------------------------------------------------------------
-- 10) TEXT GLOW: pulsing text color
------------------------------------------------------------------------
function FX:TextGlow(fontString, r, g, b, speed)
    if not fontString or fontString._textGlowTicker then return end
    r = r or 1; g = g or 0.85; b = b or 0.4
    speed = speed or 3.0

    C_Timer.NewTicker(0.04, function()
        if not fontString or not fontString:IsVisible() then return end
        local t = GetTime()
        local pulse = 0.75 + 0.25 * math.sin(t / speed * 6.28)
        fontString:SetTextColor(r * pulse, g * pulse, b * pulse, 1)
    end)
    fontString._textGlowTicker = true
end

------------------------------------------------------------------------
-- 11) HEADER SHINE BARS: animated decorative bars under title
------------------------------------------------------------------------
function FX:HeaderShine(frame, yOffset)
    if not frame or frame._headerShine then return end
    yOffset = yOffset or -78
    frame._headerShine = true

    local lBar = frame:CreateTexture(nil, "ARTWORK", nil, 3)
    lBar:SetSize(120, 2)
    lBar:SetPoint("LEFT", frame, "TOPLEFT", 12, yOffset)
    lBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    lBar:SetBlendMode("ADD")

    local rBar = frame:CreateTexture(nil, "ARTWORK", nil, 3)
    rBar:SetSize(120, 2)
    rBar:SetPoint("RIGHT", frame, "TOPRIGHT", -12, yOffset)
    rBar:SetTexture("Interface\\Buttons\\WHITE8x8")
    rBar:SetBlendMode("ADD")

    C_Timer.NewTicker(0.03, function()
        if not frame or not frame:IsVisible() then return end
        local t = GetTime()
        local alpha = 0.2 + 0.15 * math.sin(t * 1.5)
        lBar:SetVertexColor(0.9, 0.7, 0.2, alpha)
        rBar:SetVertexColor(0.9, 0.7, 0.2, alpha)
        local w = 100 + 40 * math.sin(t * 0.8)
        lBar:SetWidth(w)
        rBar:SetWidth(w)
    end)
end

------------------------------------------------------------------------
-- 12) ICON QUALITY GLOW: colored glow ring matching item quality
------------------------------------------------------------------------
function FX:QualityGlow(iconFrame, quality)
    if not iconFrame then return end
    local qualityColors = {
        [0] = { 0.6, 0.6, 0.6 },
        [1] = { 1, 1, 1 },
        [2] = { 0.12, 1, 0 },
        [3] = { 0, 0.44, 0.87 },
        [4] = { 0.64, 0.21, 0.93 },
        [5] = { 1, 0.5, 0 },
        [6] = { 0.9, 0.8, 0.5 },
        [7] = { 0, 0.8, 1 },
    }
    local c = qualityColors[quality or 1] or qualityColors[1]

    local ring = iconFrame:GetParent():CreateTexture(nil, "OVERLAY", nil, 3)
    ring:SetPoint("TOPLEFT", iconFrame, "TOPLEFT", -2, 2)
    ring:SetPoint("BOTTOMRIGHT", iconFrame, "BOTTOMRIGHT", 2, -2)
    ring:SetTexture("Interface\\Buttons\\WHITE8x8")
    ring:SetVertexColor(c[1], c[2], c[3], 0.35)

    local inner = iconFrame:GetParent():CreateTexture(nil, "OVERLAY", nil, 4)
    inner:SetAllPoints(iconFrame)
    inner:SetTexture("Interface\\Buttons\\WHITE8x8")
    inner:SetVertexColor(0, 0, 0, 0)

    local ag = ring:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(0.4); a1:SetToAlpha(0.15); a1:SetDuration(1.5); a1:SetOrder(1); a1:SetSmoothing("IN_OUT")
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.15); a2:SetToAlpha(0.4); a2:SetDuration(1.5); a2:SetOrder(2); a2:SetSmoothing("IN_OUT")
    ag:SetLooping("REPEAT")
    ag:Play()
    return ring
end

------------------------------------------------------------------------
-- 13) NOTIFICATION FLASH
------------------------------------------------------------------------
function FX:Flash(frame, r, g, b, duration)
    if not frame then return end
    r = r or 1; g = g or 1; b = b or 1
    duration = duration or 0.4

    local flash = frame:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints(frame)
    flash:SetTexture("Interface\\Buttons\\WHITE8x8")
    flash:SetBlendMode("ADD")
    flash:SetVertexColor(r, g, b, 0.5)

    local el = 0
    C_Timer.NewTicker(0.016, function()
        el = el + 0.016
        if el >= duration then flash:Hide() return end
        flash:SetVertexColor(r, g, b, 0.5 * (1 - el / duration))
    end)
end

------------------------------------------------------------------------
-- Style buttons recursively
------------------------------------------------------------------------
function FX:StyleChildButtons(parent, theme, maxDepth)
    if not parent then return end
    maxDepth = maxDepth or 2
    if maxDepth <= 0 then return end

    local children = { parent:GetChildren() }
    for _, child in ipairs(children) do
        if child:IsObjectType("Button") and child.SetBackdrop and not child._styledTheme then
            local w = child:GetWidth() or 0
            if w >= 50 then
                FX:StyleButton(child, theme)
            end
        end
        FX:StyleChildButtons(child, theme, maxDepth - 1)
    end
end

------------------------------------------------------------------------
-- Style dialog frames
------------------------------------------------------------------------
function FX:StyleDialog(dialog, theme)
    if not dialog or dialog._fxStyled then return end
    dialog._fxStyled = true
    theme = theme or "gold"

    FX:BorderGlowPulse(dialog, 0.5, 0.7, 1.0, 2.5)
    FX:ShineSweep(dialog, 5.0, { 0.5, 0.7, 1.0 })

    C_Timer.After(0.05, function()
        if dialog then FX:StyleChildButtons(dialog, theme, 3) end
    end)
end

------------------------------------------------------------------------
-- Hook dialog frames to auto-style
------------------------------------------------------------------------
function FX:HookDialogs()
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
    C_Timer.NewTicker(1.5, function()
        for _, name in ipairs(dialogNames) do
            local frame = _G[name]
            if frame and not hooked[name] then
                hooked[name] = true
                frame:HookScript("OnShow", function(self)
                    if not self._fxStyled then
                        FX:StyleDialog(self, "gold")
                    end
                end)
                if frame:IsVisible() and not frame._fxStyled then
                    FX:StyleDialog(frame, "gold")
                end
            end
        end
    end)
end

------------------------------------------------------------------------
-- CLEANUP: Remove all effects from main UI for live refresh
------------------------------------------------------------------------
function FX:CleanupMainUI()
    local f = OneGuild.mainFrame
    if not f then return end

    -- Cancel all tracked tickers
    for _, t in ipairs(FX._tickers) do
        if t and t.Cancel then pcall(t.Cancel, t) end
    end
    FX._tickers = {}

    -- Hide all tracked textures
    for _, tex in ipairs(FX._textures) do
        if tex and tex.Hide then pcall(tex.Hide, tex) end
    end
    FX._textures = {}

    -- Hide tracked sub-frames
    for _, fr in ipairs(FX._frames) do
        if fr and fr.Hide then pcall(fr.Hide, fr) end
    end
    FX._frames = {}

    -- Reset guard flags on mainFrame
    f._borderGlowPulse = nil
    f._shimmerTicker = nil
    f._goldParticles = nil
    f._headerShine = nil
    f._shineSweep = nil

    -- Reset text glow
    if f.titleText then f.titleText._textGlowTicker = nil end

    -- Reset tab indicator
    if OneGuild.tabButtons then
        for _, btn in ipairs(OneGuild.tabButtons) do
            if btn:GetParent() then
                local tc = btn:GetParent()
                if tc._indicator then tc._indicator:Hide() end
                if tc._indicatorGlow then tc._indicatorGlow:Hide() end
                tc._indicator = nil
                tc._indicatorGlow = nil
                break
            end
        end
    end

    appliedToMain = false
end

------------------------------------------------------------------------
-- REFRESH: Live-update effects with current settings (no /reload)
------------------------------------------------------------------------
function FX:Refresh()
    FX:CleanupMainUI()
    if OneGuild.mainFrame and OneGuild.mainFrame:IsShown() then
        FX:ApplyToMainUI()
    end
end

------------------------------------------------------------------------
-- APPLY TO MAIN UI  (called once mainFrame exists AND is shown)
------------------------------------------------------------------------
function FX:ApplyToMainUI()
    local f = OneGuild.mainFrame
    if not f or appliedToMain then return end
    appliedToMain = true

    -- Read settings
    local s = OneGuild.db and OneGuild.db.settings or {}
    if s.fxEnabled == false then
        print("|cFFFFB800[OneGuild FX]|r Effekte deaktiviert (Einstellungen).")
        return
    end

    local gc = s.fxGlowColor or { 0.9, 0.65, 0.15 }
    local particleCount = s.fxParticleCount or 35

    print("|cFFFFB800[OneGuild FX]|r Effekte werden angewendet...")

    -- 1) Pulsing border glow
    if s.fxBorderGlow ~= false then
        FX:BorderGlowPulse(f, gc[1], gc[2], gc[3], 3.0)
    end

    -- 2) Traveling border shimmer
    if s.fxShimmer ~= false then
        FX:BorderShimmer(f, 5.0, { gc[1], gc[2], gc[3], 0.7 })
    end

    -- 3) Golden floating particles
    if particleCount > 0 then
        FX:GoldParticles(f, particleCount)
    end

    -- 4) Decorative pulsing header bars
    if s.fxHeaderShine ~= false then
        FX:HeaderShine(f, -78)
    end

    -- 7) Title text glow pulse
    if f.titleText then
        FX:TextGlow(f.titleText, 1, 0.85, 0.4, 4.0)
    end

    -- 8) Tab indicator (animated sliding underline)
    local tabContainer = nil
    if OneGuild.tabButtons then
        for _, btn in ipairs(OneGuild.tabButtons) do
            if btn:GetParent() then
                tabContainer = btn:GetParent()
                break
            end
        end
    end

    if tabContainer then
        FX:TabIndicator(tabContainer, OneGuild.tabButtons)

        local origShowTab = OneGuild.ShowTab
        if origShowTab then
            OneGuild.ShowTab = function(self2, index)
                origShowTab(self2, index)
                if tabContainer and OneGuild.tabButtons[index] then
                    C_Timer.After(0.02, function()
                        FX:MoveTabIndicator(tabContainer, OneGuild.tabButtons[index])
                    end)
                end
            end
        end

        C_Timer.After(0.3, function()
            local idx = OneGuild.currentTab or 1
            if OneGuild.tabButtons and OneGuild.tabButtons[idx] then
                FX:MoveTabIndicator(tabContainer, OneGuild.tabButtons[idx])
            end
        end)
    end

    -- 9) Tab button hover glow
    if OneGuild.tabButtons then
        for _, tab in ipairs(OneGuild.tabButtons) do
            FX:HoverGlow(tab, 0.9, 0.7, 0.1)
        end
    end

    -- 10) Style all tab content buttons
    C_Timer.After(0.3, function()
        if OneGuild.tabFrames then
            for _, tabFrame in ipairs(OneGuild.tabFrames) do
                if tabFrame then FX:StyleChildButtons(tabFrame, "gold", 3) end
            end
        end
    end)

    -- 11) Hook dialogs
    FX:HookDialogs()

    print("|cFF00FF00[OneGuild FX]|r Alle Effekte aktiv!")
end

------------------------------------------------------------------------
-- HOOK: Poll for mainFrame, apply when it's built AND shown
-- mainFrame is lazy-built in ToggleMainWindow() so we can't
-- apply at PLAYER_ENTERING_WORLD (it doesn't exist yet!)
------------------------------------------------------------------------
local hookFrame = CreateFrame("Frame")
hookFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
hookFrame:SetScript("OnEvent", function()
    -- Poll every 0.5s for mainFrame to appear
    local pollTicker
    pollTicker = C_Timer.NewTicker(0.5, function()
        if appliedToMain then
            if pollTicker then pollTicker:Cancel() end
            return
        end
        local mf = OneGuild.mainFrame
        if mf then
            -- Frame exists! Hook OnShow so effects apply when it's visible
            mf:HookScript("OnShow", function()
                -- Small delay to let layout finish
                C_Timer.After(0.2, function()
                    FX:ApplyToMainUI()
                end)
            end)
            -- If it's already visible right now, apply immediately
            if mf:IsShown() then
                C_Timer.After(0.2, function()
                    FX:ApplyToMainUI()
                end)
            end
            if pollTicker then pollTicker:Cancel() end
        end
    end)
end)
