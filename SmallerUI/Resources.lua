local _, Addon = ...
local driver = CreateFrame("Frame")
local display, editor, toolbar, shuttingDown, Tick, Layout
local WHITE = "Interface\\Buttons\\WHITE8X8"
local enabledKeys = { player = "enabled", pet = "petEnabled", party = "partyEnabled" }

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Clamp(value, low, high) return math.max(low, math.min(high, value)) end
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result
end

local function DefaultColours()
    return { health = { r = 0.85, g = 0.15, b = 0.17 },
        power = { r = 0.2, g = 0.5, b = 0.95 }, powerByType = true, powerOverrides = {} }
end

local function Defaults()
    return {
        enabled = false, partyEnabled = false, petEnabled = false, hideBlizzard = true, smooth = true,
        incomingHeals = true, periodicHeals = true, periodicDamage = false,
        swing = Addon:DefaultSwingSettings(),
        seal = { enabled = true, linked = true, x = 8, y = 0, size = 32, lastSpellID = 0 },
        player = { x = 0, y = -150, scale = 1, linked = true, gap = 4, values = true, colours = DefaultColours(), style = Addon:DefaultResourceStyle(),
            curved = false, arc = { x = 0, y = -12, scale = 1, width = 42, height = 216, gap = 214, linked = true, health = { x = 0, y = 0, scale = 1 }, power = { x = 0, y = 0, scale = 1 } },
            health = { enabled = true, width = 240, height = 22, x = 0, y = 0 },
            power = { enabled = true, width = 240, height = 12, x = 0, y = 0 } },
        party = { x = -420, y = 140, scale = 1, linked = true, gap = 3, spacing = 14, names = true, portraits = true, values = true, colours = DefaultColours(), style = Addon:DefaultResourceStyle(),
            health = { enabled = true, width = 200, height = 20, x = 0, y = 0 },
            power = { enabled = true, width = 200, height = 10, x = 0, y = 0 } },
        pet = { x = -170, y = -210, scale = 1, linked = true, gap = 3, names = true, portraits = true, values = true, colours = DefaultColours(), style = Addon:DefaultResourceStyle(),
            health = { enabled = true, width = 200, height = 20, x = 0, y = 0 },
            power = { enabled = true, width = 200, height = 10, x = 0, y = 0 } },
    }
end

local limits = { width = { 8, 8192 }, height = { 2, 1024 }, x = { -32768, 32768 },
    y = { -32768, 32768 }, scale = { 0.1, 5 }, gap = { 0, 200 }, spacing = { 0, 200 },
    size = { 8, 256 }, lastSpellID = { 0, 10000000 }, r = { 0, 1 }, g = { 0, 1 }, b = { 0, 1 } }
Addon.resourceArcLimits = { width = { 20, 120 }, height = { 80, 640 }, gap = { 80, 1000 }, scale = { 0.25, 3 } }

local function Validate(value, defaults)
    if type(value) ~= "table" then value = {} end
    for key, fallback in pairs(defaults) do
        if type(fallback) == "table" then
            value[key] = Validate(value[key], fallback)
        elseif type(fallback) == "boolean" then
            if value[key] == nil then value[key] = fallback else value[key] = value[key] == true end
        else
            if not Number(value[key]) then value[key] = fallback end
            local range = limits[key]
            if range then value[key] = Clamp(value[key], range[1], range[2]) end
        end
    end
    return value
end

function Addon:ValidateResources()
    self.character.resources = Validate(self.character.resources, Defaults())
    local arc = self.character.resources.player.arc
    for key, range in pairs(self.resourceArcLimits) do arc[key] = Clamp(arc[key], range[1], range[2]) end
    self:ValidateResourceStyles()
    self:ValidateSwingSettings()
    self.character.resources.seal.lastSpellID = math.floor(self.character.resources.seal.lastSpellID)
    local original = self.character.originalSelfResourceCVar
    if original ~= "0" and original ~= "1" then self.character.originalSelfResourceCVar = nil end
end

function Addon:GetResourceSettings() return self.character.resources end
function Addon:IsEditingResources() return editor ~= nil end
function Addon:GetResourceDisplay() return display end

function Addon:GetResourceColour(scope, kind, token)
    local colours = self:GetResourceSettings()[scope].colours
    if token then
        local color = colours.powerOverrides[token] or PowerBarColor and PowerBarColor[token] or colours.power
        return color.r, color.g, color.b
    end
    if kind == "power" and colours.powerByType then
        local view = display and (scope == "party" and display.party[1] or display[scope])
        local color = view and (colours.powerOverrides[view.powerToken] or view.defaultPowerColour) or PowerBarColor and PowerBarColor.MANA or DefaultColours().power
        return color.r, color.g, color.b
    end
    local color = colours[kind]
    return color.r, color.g, color.b
end

local function ColourBar(bar, colour, tintTrail)
    local r, g, b = colour.r, colour.g, colour.b
    if bar.red == r and bar.green == g and bar.blue == b and bar.tintTrail == tintTrail then return false end
    bar.red, bar.green, bar.blue, bar.tintTrail = r, g, b, tintTrail
    Addon:SetResourceFillColour(bar.fill, r, g, b)
    if tintTrail then
        Addon:SetResourceFillColour(bar.trail, r * 0.6 + 0.28, g * 0.6 + 0.28, b * 0.6 + 0.28, 0.56)
    else
        Addon:SetResourceFillColour(bar.trail, 0.32, 0.37, 0.4, 0.35)
    end
    return true
end

local function ColourView(view)
    local settings = Addon:GetResourceSettings()[view.scope]
    local colours = settings.colours
    local health = colours.health
    local power = colours.powerByType and (colours.powerOverrides[view.powerToken] or view.defaultPowerColour) or colours.power
    power = power or colours.power
    local motion = Addon.resourceMotion[settings.style.motion]
    ColourBar(view.power, power, motion.tintTrail)
    local changed = ColourBar(view.health, health, motion.tintTrail)
    local forecasts = view.health.forecasts
    if changed and forecasts then
        Addon:SetResourceFillColour(forecasts.direct, health.r + (1 - health.r) * 0.35, health.g + (1 - health.g) * 0.35, health.b + (1 - health.b) * 0.35, 0.95)
        Addon:SetResourceFillColour(forecasts.hot, health.r + (1 - health.r) * 0.55, health.g + (1 - health.g) * 0.55, health.b + (1 - health.b) * 0.55, 0.6)
    end
end

function Addon:SetResourcePowerOverride(scope, token, r, g, b)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.colours or not self:IsResourceColourToken(token) then return false end
    if r == nil then settings.colours.powerOverrides[token] = nil
    else
        if not Number(r) or not Number(g) or not Number(b) or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return false end
        settings.colours.powerOverrides[token] = { r = r, g = g, b = b }
    end
    settings.colours.powerByType = true
    self:RefreshResourceColours()
    return true
end

function Addon:RefreshResourceColours()
    if display then
        ColourView(display.player)
        ColourView(display.pet)
        for _, view in ipairs(display.party) do ColourView(view) end
    end
    if self.RefreshResourceOptions then self:RefreshResourceOptions() end
end

function Addon:SetResourceColour(scope, kind, r, g, b)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.colours or kind ~= "health" and kind ~= "power" then return false end
    if not Number(r) or not Number(g) or not Number(b) or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return false end
    settings.colours[kind] = { r = r, g = g, b = b }
    if kind == "power" then settings.colours.powerByType = false end
    self:RefreshResourceColours()
    return true
end

function Addon:SetResourcePowerByType(scope, enabled)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.colours then return false end
    settings.colours.powerByType = enabled == true
    self:RefreshResourceColours()
    return true
end

function Addon:ResetResourceColours(scope)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.colours then return false end
    settings.colours = DefaultColours()
    local defaults = self:DefaultResourceStyle()
    for key in pairs(self.resourceStyleColours) do settings.style[key] = defaults[key] end
    self:RefreshResourceStyles()
    return true
end

local function RGB(hex)
    return { r = math.floor(hex / 65536) / 255, g = math.floor(hex / 256) % 256 / 255, b = hex % 256 / 255 }
end

function Addon:ApplyResourceTheme(scope, id)
    local settings = self:GetResourceSettings()[scope]
    local theme = Number(id) and self.resourceThemes[id]
    if not settings or not settings.style or not theme then return false end
    local style = settings.style
    local defaults = self:DefaultResourceStyle()
    style.theme = id
    style.barTexture = theme.texture or defaults.barTexture
    style.trim = theme.trim or defaults.trim
    if style.themeColours then
        local colours = DefaultColours()
        style.accentColour, style.trackColour, style.borderColour = defaults.accentColour, defaults.trackColour, defaults.borderColour
        settings.colours.health, settings.colours.power = colours.health, colours.power
        settings.colours.powerByType = colours.powerByType
        if theme.accent then
            local accent = RGB(theme.accent)
            style.accentColour = accent
            style.trackColour = { r = 0.025 + accent.r * 0.055, g = 0.025 + accent.g * 0.055, b = 0.032 + accent.b * 0.055 }
            style.borderColour = { r = 0.05 + accent.r * 0.26, g = 0.05 + accent.g * 0.26, b = 0.05 + accent.b * 0.26 }
            settings.colours.health, settings.colours.power = RGB(theme.health), RGB(theme.power)
            settings.colours.powerByType = false
        end
    end
    self:RefreshResourceStyles()
    return true
end

function Addon:SyncNativeResources()
    if shuttingDown then return end
    local get = C_CVar and C_CVar.GetCVar or GetCVar
    local set = C_CVar and C_CVar.SetCVar or SetCVar
    if not get or not set then return end
    local cfg = self:GetResourceSettings()
    local original = self.character.originalSelfResourceCVar
    local hide = cfg.enabled and cfg.hideBlizzard and (cfg.player.health.enabled or cfg.player.power.enabled)
    if not hide and original == nil then self.resourceCVarPending = false; return end
    if InCombatLockdown() then self.resourceCVarPending = true; return end
    local current = get("nameplateShowSelf")
    if current == nil then self.resourceCVarPending = false; return end
    if hide then
        if original == nil then self.character.originalSelfResourceCVar = current end
        if current ~= "0" then set("nameplateShowSelf", "0") end
    else
        if current ~= original then set("nameplateShowSelf", original) end
        self.character.originalSelfResourceCVar = nil
    end
    self.resourceCVarPending = false
end

local function NativeValue(bar, value, smooth)
    local modes = Enum and Enum.StatusBarInterpolation
    if smooth and modes and modes.ExponentialEaseOut then
        bar:SetValue(value, modes.ExponentialEaseOut)
    else
        bar:SetValue(value, modes and modes.Immediate)
    end
end

local function ResetBarFeedback(bar)
    NativeValue(bar.trail, bar.currentValue, false)
    bar.pendingAt, bar.pendingValue, bar.pulseAt = nil, nil, nil
    bar.pulse:Hide()
    if bar.arcPulse then bar.arcPulse:Hide() end
end

local function GroupPosition(frame, settings)
    frame:SetScale(settings.scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", settings.x / settings.scale, settings.y / settings.scale)
end

local function RoundToPixel(value, pixel)
    return math.floor(value / pixel + 0.5) * pixel
end

local function LayoutBar(bar, settings, view, left, top)
    -- One UI unit is not one screen pixel, especially at reduced scales.
    local pixel = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor() or 1) / bar:GetEffectiveScale()
    if bar.pixel ~= pixel then
        bar.pixel = pixel
        bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = pixel })
        for _, piece in ipairs({ "TopLeftCorner", "TopRightCorner", "BottomLeftCorner", "BottomRightCorner",
            "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "Center" }) do
            local region = bar[piece]
            if region then
                if region.SetRoundLayoutToNearestPixel then region:SetRoundLayoutToNearestPixel(false) end
                if region.SetTexelSnappingBias then region:SetTexelSnappingBias(0) end
                if region.SetSnapToPixelGrid then region:SetSnapToPixelGrid(false) end
            end
        end
    end
    local inset = (editor or Addon:GetResourceSettings()[view.scope].style.border) and pixel or 0
    bar.trail:ClearAllPoints()
    bar.trail:SetPoint("TOPLEFT", inset, -inset)
    bar.trail:SetPoint("BOTTOMRIGHT", -inset, inset)
    local minimum = inset > 0 and 3 * pixel or pixel -- Leave at least one pixel for the live fill.
    bar:SetSize(math.max(minimum, RoundToPixel(settings.width, pixel)), math.max(minimum, RoundToPixel(settings.height, pixel)))
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", view, "TOPLEFT", left + settings.x, top + settings.y)
    bar.valueText:SetWidth(math.max(1, settings.width - 12))
    bar:EnableMouse(editor ~= nil)
    bar.grip:SetShown(editor ~= nil)
    Addon:StyleResourceBar(bar, Addon:GetResourceSettings()[view.scope], editor ~= nil)
end

local function LayoutView(view, settings, party)
    local nameHeight = party and settings.names and (settings.style.autoFontSize and 16 or math.max(16, settings.style.fontSize + 4)) or 0
    local showHealth = editor ~= nil or settings.health.enabled
    local showPower = editor ~= nil or settings.power.enabled and view.hasPower ~= false
    local powerTop = settings.health.height + settings.gap
    if settings.linked and not showHealth then powerTop = 0 end
    local bodyHeight = showHealth and settings.health.height - settings.health.y or 1
    if showPower then bodyHeight = math.max(bodyHeight, powerTop + settings.power.height - settings.power.y) end
    local portraitSize = party and settings.portraits and Clamp(bodyHeight + nameHeight, 20, 72) or 0
    local left = portraitSize > 0 and portraitSize + 8 or 0
    local width = math.max(settings.health.width, settings.power.width)
    view:SetSize(width + left, math.max(bodyHeight + nameHeight, portraitSize))
    view.barLeft, view.nameHeight = left, nameHeight
    view.name:ClearAllPoints()
    view.name:SetPoint("TOPLEFT", left + 2, 0)
    view.name:SetWidth(width - 4)
    Addon:ResourceFont(view.name, settings.style, 24)
    view.name:SetShown(party and settings.names)
    view.portrait:SetShown(portraitSize > 0)
    view.portrait:SetSize(math.max(1, portraitSize), math.max(1, portraitSize))
    LayoutBar(view.health, settings.health, view, left, -nameHeight)
    LayoutBar(view.power, settings.power, view, left, -nameHeight - powerTop)
    if view.power.SetRoundLayoutToNearestPixel then view.power:SetRoundLayoutToNearestPixel(not settings.linked) end
    if settings.linked and showHealth then
        -- Only health snaps to the screen. Both bars use whole-pixel sizes and
        -- the same origin, including their fills and borders.
        local pixel = view.health.pixel
        local x = settings.health.width == settings.power.width and 0 or settings.power.x - settings.health.x
        local y = settings.power.y - settings.health.y - settings.gap
        view.power:ClearAllPoints()
        view.power:SetPoint("TOPLEFT", view.health, "BOTTOMLEFT", RoundToPixel(x, pixel), RoundToPixel(y, pixel))
    end
    Addon:LayoutResourcePredictions(view.health)
    view.health:SetShown(showHealth)
    view.power:SetShown(showPower)
end

local function LayoutCurvedView(view, settings)
    local arc = settings.arc
    GroupPosition(view, arc)
    view:SetSize(arc.gap + 2 * arc.width, arc.height)
    view.name:Hide()
    view.portrait:Hide()
    for _, kind in ipairs({ "health", "power" }) do
        local bar = view[kind]
        Addon:SetResourceBarCurved(bar, true)
        local side = kind == "health" and "LEFT" or "RIGHT"
        if bar.SetRoundLayoutToNearestPixel then bar:SetRoundLayoutToNearestPixel(true) end
        local offset = arc[kind]
        bar:SetSize(arc.width * offset.scale, arc.height * offset.scale)
        bar:ClearAllPoints()
        bar:SetPoint(side, view, side, offset.x, offset.y)
        bar.trail:SetAllPoints(bar)
        bar:EnableMouse(editor ~= nil)
        bar.grip:Hide()
        Addon:StyleResourceBar(bar, settings, editor ~= nil)
    end
    Addon:LayoutResourcePredictions(view.health)
    view.health:SetShown(editor ~= nil or settings.health.enabled)
    view.power:SetShown(editor ~= nil or settings.power.enabled and view.hasPower ~= false)
end

function Addon:RefreshResourceStyles()
    if display then
        Layout()
        local views = { display.player, display.pet, unpack(display.party) }
        for _, view in ipairs(views) do
            ColourView(view)
            for _, kind in ipairs({ "health", "power" }) do
                local bar = view[kind]
                if bar.initialized then
                    local motion = self:GetResourceSettings()[view.scope].style.motion
                    if motion ~= bar.motion then ResetBarFeedback(bar); bar.motion = motion end
                    self:RenderResourceText(bar, bar.currentValue, bar.currentMaximum, bar.currentDemo)
                end
            end
        end
    end
    if self.RefreshResourceOptions then self:RefreshResourceOptions() end
end

Layout = function()
    if not display then return end
    local cfg = Addon:GetResourceSettings()
    if cfg.player.curved then
        LayoutCurvedView(display.player, cfg.player)
    else
        Addon:SetResourceBarCurved(display.player.health, false)
        Addon:SetResourceBarCurved(display.player.power, false)
        GroupPosition(display.player, cfg.player)
        LayoutView(display.player, cfg.player, false)
    end
    Addon:LayoutSealIndicator(display.player, editor ~= nil)
    GroupPosition(display.pet, cfg.pet)
    LayoutView(display.pet, cfg.pet, true)
    GroupPosition(display.partyRoot, cfg.party)
    local height, width = 0, 0
    for index, view in ipairs(display.party) do
        LayoutView(view, cfg.party, true)
        view:ClearAllPoints()
        view:SetPoint("TOPLEFT", display.partyRoot, "TOPLEFT", 0, -height)
        height = height + view:GetHeight() + cfg.party.spacing
        width = math.max(width, view:GetWidth())
    end
    display.partyRoot:SetSize(width, math.max(1, height - cfg.party.spacing))
end

local function UpdateBar(bar, value, maximum, snap, demo)
    local cfg = Addon:GetResourceSettings()
    bar.motion = cfg[bar.view.scope].style.motion
    local motion = Addon.resourceMotion[bar.motion]
    if Public(maximum) and (not Number(maximum) or maximum <= 0) then maximum = 1 end
    bar.fill:SetMinMaxValues(0, maximum)
    -- The live fill and number always use the latest API value immediately.
    -- Smoothing is exclusively decorative and never controls current health.
    NativeValue(bar.fill, value, false)
    bar.currentValue, bar.currentMaximum, bar.currentDemo = value, maximum, demo
    Addon:RenderResourceText(bar, value, maximum, demo)
    bar.trail:SetMinMaxValues(0, maximum)
    if snap or not bar.initialized or motion.hold == 0 then
        ResetBarFeedback(bar)
    elseif not cfg.smooth then
        NativeValue(bar.trail, value, false)
        bar.pendingAt, bar.pendingValue = nil, nil
    elseif not Number(value) or value ~= bar.lastPublic then
        bar.pendingValue = value
        if not bar.pendingAt then bar.pendingAt = GetTime() + motion.hold end
        driver:SetScript("OnUpdate", Tick)
    end
    -- Only public values are compared for decorative damage/heal feedback.
    -- Restricted health/power values go directly to native rendering APIs.
    if motion.fade and not snap and Number(value) and Number(bar.lastPublic) and value ~= bar.lastPublic then
        local change = value - bar.lastPublic
        local isHealth = bar.resourceKind == "health"
        if isHealth or motion.powerPulse and Number(maximum) and change <= -maximum * 0.05 then
            local healed = change > 0
            local opacity = motion.opacity
            if motion.tintTrail and Number(maximum) then opacity = opacity * Clamp(math.abs(change) / maximum * 3, 0.4, 1) end
            local pulse = bar.curved and bar.arcPulse or bar.pulse
            local r, g, b = 1, 1, 1
            if isHealth then
                r, g, b = healed and 0.35 or 1, healed and 1 or 0.3, 0.3
            else
                opacity = opacity * 0.7
            end
            if bar.curved then pulse:SetVertexColor(r, g, b, opacity)
            else pulse:SetColorTexture(r, g, b, opacity) end
            pulse:Show()
            pulse:SetAlpha(1)
            bar.pulseAt = GetTime()
            driver:SetScript("OnUpdate", Tick)
        end
    end
    if Public(value) then bar.lastPublic = value else bar.lastPublic = nil end
    bar.initialized = true
end

local function UpdateHealth(view, health, maximum, snap, demo)
    view.health.statusLabel = nil
    UpdateBar(view.health, health, maximum, snap, demo)
    if not demo then
        local connected = UnitIsConnected(view.unit)
        local dead = UnitIsDeadOrGhost(view.unit)
        if Public(connected) and connected == false then view.health.statusLabel = "Offline"
        elseif Public(dead) and dead == true then view.health.statusLabel = "Dead" end
        if view.health.statusLabel then view.health.valueText:SetText(view.health.statusLabel) end
    end
end

local samples = { "Party member 1", "Party member 2", "Party member 3", "Party member 4" }

local function UpdateViewVisibility(view)
    local cfg = Addon:GetResourceSettings()
    local exists = UnitExists(view.unit)
    local preview = editor ~= nil
    local settings = cfg[view.scope]
    local hasContent = settings.health.enabled or settings.power.enabled
        or settings.names or settings.portraits
        or view.scope == "player" and cfg.seal.enabled and Addon:IsPaladin()
    local active = cfg[enabledKeys[view.scope]] and exists and hasContent or preview
    local style = settings.style
    local opacity = 100
    if not preview then
        if InCombatLockdown() then
            opacity = style.combatOpacity
        elseif style.hideOutOfCombat then
            opacity = 0
        else
            opacity = style.outOfCombatOpacity
        end
    end
    view:SetAlpha(opacity / 100)
    view:SetShown(active and opacity > 0)
    return active, exists
end

function Addon:RefreshResourceVisibility(scope)
    if not display then return end
    if scope ~= "party" then
        UpdateViewVisibility(display[scope])
        return
    end
    local any = false
    for _, view in ipairs(display.party) do
        UpdateViewVisibility(view)
        any = any or view:IsShown()
    end
    display.partyRoot:SetShown(any)
end

local function UpdateView(view, snap, event)
    local cfg = Addon:GetResourceSettings()
    local isPlayer = view.unit == "player"
    local isPet = view.unit == "pet"
    local settings = cfg[view.scope]
    local active, exists = UpdateViewVisibility(view)
    if not active then return false end
    local demo = editor and (not exists or editor.demoUntil and GetTime() < editor.demoUntil)
    local updateHealth = snap or not event or event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION"
    local health, healthMax, power, powerMax, powerType, powerToken, red, green, blue
    if demo then
        healthMax, powerMax = 5000, 100
        health = editor.demoHealth or (3900 - (view.index or 0) * 370)
        if updateHealth then UpdateHealth(view, health, healthMax, snap or event == "UNIT_MAXHEALTH", true) end
        power, powerType, powerToken = 72, isPet and 2 or 0, isPet and "FOCUS" or "MANA"
        view.name:SetText(isPlayer and "Your character" or isPet and "Your pet" or samples[view.index])
        view.portrait:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
    else
        health, healthMax = UnitHealth(view.unit), UnitHealthMax(view.unit)
        if updateHealth then UpdateHealth(view, health, healthMax, snap or event == "UNIT_MAXHEALTH", false) end
        powerType, powerToken, red, green, blue = UnitPowerType(view.unit)
        power, powerMax = UnitPower(view.unit, powerType), UnitPowerMax(view.unit, powerType)
        local name = UnitName(view.unit)
        if not Public(name) then view.name:SetText(name) else view.name:SetText(name or "") end
        if settings.portraits and not isPlayer and (snap or event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_MODEL_CHANGED") then
            SetPortraitTexture(view.portrait, view.unit)
        end
    end
    -- Reread the active pool, even when an event names a secondary resource.
    -- Snap on pool changes so a form switch never animates from old Mana/Rage.
    local powerChanged = Public(powerType) and view.powerType ~= powerType
        or Public(powerToken) and view.powerToken ~= powerToken
    if Public(powerType) then view.powerType = powerType end
    if Public(powerToken) then view.powerToken = powerToken end
    local hasPower = not Number(powerMax) or powerMax > 0
    if view.hasPower ~= hasPower then view.hasPower = hasPower; Layout() end
    if snap or powerChanged or not event or event == "UNIT_POWER_FREQUENT" or event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
        local color = Public(powerToken) and PowerBarColor and PowerBarColor[powerToken]
        if not color and Public(powerType) and PowerBarColor then color = PowerBarColor[powerType] end
        view.defaultPowerColour = { r = color and color.r or Number(red) and red or 0.26,
            g = color and color.g or Number(green) and green or 0.55, b = color and color.b or Number(blue) and blue or 0.94 }
        view.power.label:SetText(Public(powerToken) and (_G[powerToken] or powerToken or "Power") or "Power")
        UpdateBar(view.power, power, powerMax, snap or powerChanged or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER", demo)
    end
    ColourView(view)
    Addon:UpdateResourcePredictions(view, demo == true)
    return view:IsShown()
end

local function RefreshUnits(snap)
    if not display then return end
    UpdateView(display.player, snap)
    UpdateView(display.pet, snap)
    local any = false
    for _, view in ipairs(display.party) do if UpdateView(view, snap) then any = true end end
    display.partyRoot:SetShown(any)
    Addon:RefreshResourceForecasts()
end

local function SaveGroup(frame, settings)
    frame:StopMovingOrSizing()
    local x, y = frame:GetCenter()
    local centerX, centerY = UIParent:GetCenter()
    settings.x = x * frame:GetEffectiveScale() - centerX * UIParent:GetEffectiveScale()
    settings.y = y * frame:GetEffectiveScale() - centerY * UIParent:GetEffectiveScale()
end

local function DragTarget(view, kind, settings)
    local linked = (view.health.curved and settings.arc or settings).linked
    return linked and (view.scope == "party" and display.partyRoot or view) or view[kind], linked
end

local scopeNames = { player = "Personal", party = "Party", pet = "Pet" }

local function SelectBar(view, kind, target, linked)
    local name = scopeNames[view.scope] .. " " .. kind
    if linked then name = scopeNames[view.scope] .. (view.health.curved and " curved HUD" or " bars") end
    return Addon:SelectResourceMoveTarget(target, name, view.scope, kind)
end

function Addon:BeginResourceDrag(view, kind)
    if not editor or InCombatLockdown() then return end
    if editor.drag or self:GetResourceMoveState() then return end
    editor.resize = nil
    local scope = view.scope
    local settings = self:GetResourceSettings()[scope]
    local target, linked = DragTarget(view, kind, settings)
    editor.drag = { target = target, view = view, kind = kind, scope = scope, linked = linked }
    SelectBar(view, kind, target, linked)
    if not self:StartResourceMove(target, view[kind], scope, nil, kind, linked) then
        editor.drag = nil
    end
end

function Addon:EndResourceDrag()
    if not editor or not editor.drag then return end
    local drag = editor.drag
    self:FinishResourceMove()
    local settings = self:GetResourceSettings()[drag.scope]
    if drag.linked then
        SaveGroup(drag.target, drag.view.health.curved and settings.arc or settings)
    else
        drag.target:StopMovingOrSizing()
        local left, bottom, _, height = drag.target:GetRect()
        local viewLeft, viewBottom, _, viewHeight = drag.view:GetRect()
        local targetScale, viewScale = drag.target:GetEffectiveScale(), drag.view:GetEffectiveScale()
        if drag.view.health.curved then
            local arc = settings.arc
            local right = drag.kind == "power"
            local edge = (left + (right and drag.target:GetWidth() or 0)) * targetScale / viewScale
            arc[drag.kind].x = edge - viewLeft - (right and drag.view:GetWidth() or 0)
            arc[drag.kind].y = (bottom + height / 2) * targetScale / viewScale - viewBottom - viewHeight / 2
        else
            local bar = settings[drag.kind]
            bar.x = left * targetScale / viewScale - viewLeft - drag.view.barLeft
            local baseline = -drag.view.nameHeight
            if drag.kind == "power" then baseline = baseline - settings.health.height - settings.gap end
            bar.y = (bottom + height) * targetScale / viewScale - viewBottom - viewHeight - baseline
        end
    end
    editor.drag = nil
    Layout()
end

function Addon:BeginResourceResize(view, kind)
    if not editor or InCombatLockdown() or view.health.curved then return end
    if self:GetResourceMoveState() then return end
    local scope = view.scope
    local settings = self:GetResourceSettings()[scope]
    local target, linked = DragTarget(view, kind, settings)
    SelectBar(view, kind, target, linked)
    local x, y = GetCursorPosition()
    local left, bottom, _, height = view[kind]:GetRect()
    local scale = view:GetEffectiveScale()
    if not Number(left) or not Number(bottom) or not Number(height) then return end
    editor.resize = { scope = scope, kind = kind, x = x, y = y,
        settings = Copy(self:GetResourceSettings()[scope]), scale = scale,
        view = view, fixedLeft = left * scale, fixedTop = (bottom + height) * scale }
end

function Addon:ResizeResourceBars(scope, kind, width, height, original)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings[kind] or not Number(width) or not Number(height) then return false end
    original = original or Copy(settings)
    width, height = Clamp(width, 8, 8192), Clamp(height, 2, 1024)
    if settings.linked then
        local other = kind == "health" and "power" or "health"
        settings[other].width = Clamp(original[other].width * width / original[kind].width, 8, 8192)
        settings[other].height = Clamp(original[other].height * height / original[kind].height, 2, 1024)
    elseif kind == "health" then
        -- Independently sizing health must not push the power bar down.
        settings.power.y = original.power.y + height - original.health.height
    end
    settings[kind].width, settings[kind].height = width, height
    Layout()
    return true
end

local function CreateBar(view, kind)
    local bar = CreateFrame("Frame", view:GetName() .. (kind == "health" and "Health" or "Power"), view, "BackdropTemplate")
    bar.resourceKind, bar.view = kind, view
    if bar.SetRoundLayoutToNearestPixel then bar:SetRoundLayoutToNearestPixel(true) end
    bar:SetMovable(true)
    bar:SetClampedToScreen(true)
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function() Addon:BeginResourceDrag(view, kind) end)
    bar:SetScript("OnDragStop", function() Addon:EndResourceDrag() end)
    bar:SetScript("OnMouseDown", function(_, button)
        if button ~= "LeftButton" or not editor then return end
        local settings = Addon:GetResourceSettings()[view.scope]
        local target, linked = DragTarget(view, kind, settings)
        SelectBar(view, kind, target, linked)
    end)
    bar.trail = CreateFrame("StatusBar", nil, bar)
    if bar.trail.SetRoundLayoutToNearestPixel then bar.trail:SetRoundLayoutToNearestPixel(false) end
    bar.trail:SetStatusBarTexture(WHITE)
    local trailTexture = bar.trail:GetStatusBarTexture()
    if trailTexture.SetTexelSnappingBias then trailTexture:SetTexelSnappingBias(0) end
    if trailTexture.SetSnapToPixelGrid then trailTexture:SetSnapToPixelGrid(false) end
    Addon:SetResourceFillColour(bar.trail, 0.32, 0.37, 0.4, 0.35)
    bar.fill = CreateFrame("StatusBar", nil, bar)
    if bar.fill.SetRoundLayoutToNearestPixel then bar.fill:SetRoundLayoutToNearestPixel(false) end
    bar.fill:SetAllPoints(bar.trail)
    bar.fill:SetFrameLevel(bar.trail:GetFrameLevel() + 1)
    bar.fill:SetStatusBarTexture(WHITE)
    local fillTexture = bar.fill:GetStatusBarTexture()
    if fillTexture.SetTexelSnappingBias then fillTexture:SetTexelSnappingBias(0) end
    if fillTexture.SetSnapToPixelGrid then fillTexture:SetSnapToPixelGrid(false) end
    bar.fill:SetStatusBarColor(0.85, 0.15, 0.17)
    bar.fill:EnableMouse(false)
    bar.trail:EnableMouse(false)
    local textLayer = CreateFrame("Frame", nil, bar)
    bar.trimLayer = textLayer
    textLayer:SetAllPoints(bar.fill)
    textLayer:SetFrameLevel(bar.fill:GetFrameLevel() + 4)
    textLayer:EnableMouse(false)
    bar.label = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.label:SetPoint("LEFT", 6, 0)
    bar.label:SetText(kind == "health" and "Health" or "Power")
    bar.valueText = textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bar.valueText:SetPoint("RIGHT", -6, 0)
    bar.valueText:SetWordWrap(false)
    bar.pulse = bar.fill:CreateTexture(nil, "ARTWORK")
    bar.pulse:SetAllPoints(bar.fill:GetStatusBarTexture())
    bar.pulse:Hide()
    bar.grip = CreateFrame("Button", nil, bar)
    bar.grip:SetSize(14, 14)
    bar.grip:SetPoint("BOTTOMRIGHT", 4, -4)
    bar.grip:SetFrameLevel(bar.fill:GetFrameLevel() + 3)
    bar.grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    bar.grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    bar.grip:SetScript("OnMouseDown", function(_, button) if button == "LeftButton" then Addon:BeginResourceResize(view, kind) end end)
    bar.grip:SetScript("OnMouseUp", function() if editor then editor.resize = nil end end)
    if kind == "health" then Addon:CreateResourcePredictions(view, bar) end
    return bar
end

local function CreateView(name, unit, parent, index)
    local view = CreateFrame("Frame", name, parent)
    view.unit, view.index = unit, index
    view.scope = (unit == "player" or unit == "pet") and unit or "party"
    view:SetMovable(true)
    view:SetClampedToScreen(true)
    view.name = view:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    view.name:SetJustifyH("LEFT")
    view.name:SetWordWrap(false)
    view.portrait = view:CreateTexture(nil, "ARTWORK")
    view.portrait:SetPoint("TOPLEFT")
    view.portrait:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    view.health, view.power = CreateBar(view, "health"), CreateBar(view, "power")
    return view
end

local function EnsureDisplay()
    if display then return end
    display = { party = {} }
    display.player = CreateView("SmallerUIPlayerResources", "player", UIParent)
    display.player:SetIgnoreParentScale(true)
    Addon:CreateSealIndicator(display.player)
    display.pet = CreateView("SmallerUIPetResources", "pet", UIParent)
    display.pet:SetIgnoreParentScale(true)
    display.partyRoot = CreateFrame("Frame", "SmallerUIPartyResources", UIParent)
    display.partyRoot:SetIgnoreParentScale(true)
    display.partyRoot:SetMovable(true)
    display.partyRoot:SetClampedToScreen(true)
    for index = 1, 4 do
        display.party[index] = CreateView("SmallerUIPartyResource" .. index, "party" .. index, display.partyRoot, index)
    end
end

function Addon:ApplyResources()
    if not self.character or not self.character.resources then return end
    local cfg = self:GetResourceSettings()
    if cfg.enabled or cfg.partyEnabled or cfg.petEnabled or editor or display then
        EnsureDisplay()
        if not editor or not editor.drag then Layout() end
        RefreshUnits(true)
    end
    self:SyncNativeResources()
    self:UpdateSealIndicator()
    self:ApplySwingTimer()
    if self.RefreshResourceOptions then self:RefreshResourceOptions() end
end

function Addon:SetResourceBarEnabled(scope, kind, enabled)
    local settings = self:GetResourceSettings()[scope]
    if not enabledKeys[scope] or (kind ~= "health" and kind ~= "power") then return false end
    settings[kind].enabled = enabled == true
    self:ApplyResources()
    return true
end

function Addon:SetResourceOption(scope, key, value)
    local target = scope == "root" and self:GetResourceSettings() or self:GetResourceSettings()[scope]
    local defaults = Defaults()
    if scope == "arc" then
        target, defaults.arc = self:GetResourceSettings().player.arc, defaults.player.arc
    end
    local expected
    if scope == "root" then expected = defaults[key]
    elseif defaults[scope] then expected = defaults[scope][key] end
    if not target or type(expected) ~= "boolean" then return false end
    if scope == "seal" and key == "linked" then return self:SetSealLinked(value == true) end
    local changed = target[key] ~= value
    target[key] = value == true
    if enabledKeys[scope] and key == "linked" and value == true and changed then
        target.health.x, target.health.y, target.power.x, target.power.y = 0, 0, 0, 0
    end
    self:ApplyResources()
    return true
end

function Addon:SetResourceDimensions(scope, values)
    if scope == "arc" then
        for key, value in pairs(values) do
            local range = self.resourceArcLimits[key]
            if not range or not Number(value) or value < range[1] or value > range[2] then return false end
        end
        local arc = self:GetResourceSettings().player.arc
        for key, value in pairs(values) do arc[key] = value end
        self:ApplyResources()
        return true
    end
    local target = self:GetResourceSettings()[scope]
    if not target then return false end
    local previousHeight = target.health and target.health.height
    for key, value in pairs(values) do
        local range = limits[key]
        if key == "healthWidth" or key == "powerWidth" then range = limits.width end
        if key == "healthHeight" or key == "powerHeight" then range = limits.height end
        if not range or not Number(value) or value < range[1] or value > range[2] then return false end
        if scope == "seal" then
            if key ~= "x" and key ~= "y" and key ~= "size" then return false end
        elseif key ~= "healthWidth" and key ~= "powerWidth" and key ~= "healthHeight" and key ~= "powerHeight"
            and key ~= "scale" and key ~= "gap" and not (scope == "party" and key == "spacing") then return false end
    end
    for key, value in pairs(values) do
        if key == "healthWidth" then target.health.width = value
        elseif key == "powerWidth" then target.power.width = value
        elseif key == "healthHeight" then target.health.height = value
        elseif key == "powerHeight" then target.power.height = value
        else target[key] = value end
    end
    if target.health and not target.linked then target.power.y = target.power.y + target.health.height - previousHeight end
    self:ApplyResources()
    return true
end

function Addon:ResetResourceLayout(scope)
    if scope ~= "player" and scope ~= "party" and scope ~= "pet" then return end
    local cfg = self:GetResourceSettings()
    local previous = cfg[scope]
    if scope == "player" and previous.curved then
        previous.arc = Defaults().player.arc
        self:ApplyResources()
        return
    end
    cfg[scope] = Defaults()[scope]
    if scope == "player" then cfg.player.arc = previous.arc end
    cfg[scope].health.enabled, cfg[scope].power.enabled = previous.health.enabled, previous.power.enabled
    cfg[scope].values = previous.values
    cfg[scope].colours = previous.colours
    cfg[scope].style = previous.style
    if scope ~= "player" then cfg[scope].names, cfg[scope].portraits = previous.names, previous.portraits end
    self:ApplyResources()
end

function Addon:SelectMoveElement(scope, kind)
    if scope == "element" then return self:SelectElementMoveTarget(kind) end
    if scope == "swing" then
        return self:SelectResourceMoveTarget(self:GetSwingTimerFrame(), "Swing timer", scope, scope)
    end
    if scope == "seal" then
        return self:SelectResourceMoveTarget(display.player.seal, "Paladin seal", scope, scope)
    end
    local view = scope == "party" and display.party[1] or display[scope]
    local target, linked = DragTarget(view, kind, self:GetResourceSettings()[scope])
    return SelectBar(view, kind, target, linked)
end

function Addon:GetMoveElementControls(scope, kind)
    if scope == "element" then return self:GetElementMoveControls() end
    local cfg = self:GetResourceSettings()
    if scope == "swing" then
        return nil, function(factor)
            local swing = cfg.swing
            for _, key in ipairs({ "width", "height" }) do
                local range = self.swingSizeLimits[key]
                swing[key] = Clamp(math.floor(swing[key] * factor + 0.5), range[1], range[2])
            end
            self:ApplySwingTimer()
        end
    end
    if scope == "seal" then
        return cfg.seal.linked, function(factor)
            self:SetResourceDimensions("seal", { size = Clamp(math.floor(cfg.seal.size * factor + 0.5), 8, 256) })
        end, function(linked) self:SetSealLinked(linked) end
    end
    local settings = cfg[scope]
    local curved = scope == "player" and settings.curved
    local layout = curved and settings.arc or settings
    local function Resize(factor)
        if curved and not layout.linked then
            local arc = layout[kind]
            arc.scale = Clamp(arc.scale * factor, 0.25, 3)
            Layout()
        elseif layout.linked then
            local range = curved and self.resourceArcLimits.scale or limits.scale
            self:SetResourceDimensions(curved and "arc" or scope, { scale = Clamp(layout.scale * factor, range[1], range[2]) })
        else
            local bar = settings[kind]
            self:ResizeResourceBars(scope, kind, bar.width * factor, bar.height * factor)
        end
    end
    return layout.linked, Resize, function(linked)
        self:SetResourceOption(curved and "arc" or scope, "linked", linked)
    end
end

function Addon:FinishResourceEdit(save, closing)
    if not editor then return end
    save = save and not InCombatLockdown()
    self:EndResourceDrag()
    self:EndSealDrag()
    self:EndSwingTimerDrag()
    self:FinishElementEdit(save)
    self:CloseResourceMoveMode()
    local previous = editor
    editor = nil
    if not save then
        local lastSeal = self:GetResourceSettings().seal.lastSpellID
        self.character.resources = previous.snapshot
        self.character.resources.seal.lastSpellID = lastSeal
    end
    toolbar:Hide()
    if closing then return end
    self:ApplyResources()
    self:ShowOptions(previous.origin)
    self:OptionsFeedback(save and "Layout saved." or "Layout changes cancelled.", false, previous.origin)
end

function Addon:TestResourceDamage()
    if not editor then return end
    local now = GetTime()
    editor.demoHealth, editor.demoUntil = 4500, now + 2.3
    editor.damageAt, editor.healAt = now + 0.1, now + 0.9
    RefreshUnits(true)
end

function Addon:BeginResourceEdit()
    if InCombatLockdown() then
        if self.currentOptionsPage then self:OptionsFeedback("Move Mode is available after combat.", true)
        else self:Print("Move Mode is available after combat.") end
        return false
    end
    if not self:HideOptions() then return false end
    if editor then return true end
    local origin = self.currentOptionsPage
    editor = { snapshot = Copy(self:GetResourceSettings()), origin = origin or "scaling" }
    EnsureDisplay()
    self:BeginElementEdit()
    toolbar = self:CreateResourceMoveToolbar()
    self:ApplyResources()
    local scope = editor.origin == "party" and "party" or editor.origin == "pet" and "pet"
        or editor.origin == "swing" and "swing" or "player"
    self:SelectMoveElement(scope, "health")
    driver:SetScript("OnUpdate", Tick)
    toolbar:Show()
    return true
end

Tick = function()
    if not display then return end
    local now = GetTime()
    if editor then Addon:UpdateResourceMoveMode() end
    if editor and editor.resize then
        if not IsMouseButtonDown("LeftButton") then editor.resize = nil
        else
            local resize = editor.resize
            local x, y = GetCursorPosition()
            local bar = resize.settings[resize.kind]
            Addon:ResizeResourceBars(resize.scope, resize.kind,
                bar.width + (x - resize.x) / resize.scale, bar.height - (y - resize.y) / resize.scale, resize.settings)
            -- Keep the grabbed bar's opposite corner fixed while its bounds
            -- change; centre-anchored group growth must not fight the pointer.
            local left, bottom, _, height = resize.view[resize.kind]:GetRect()
            if Number(left) and Number(bottom) and Number(height) then
                local settings = Addon:GetResourceSettings()[resize.scope]
                settings.x = settings.x + resize.fixedLeft - left * resize.scale
                settings.y = settings.y + resize.fixedTop - (bottom + height) * resize.scale
                Layout()
            end
        end
    end
    if editor and editor.damageAt and now >= editor.damageAt then
        editor.damageAt, editor.demoHealth = nil, 2100
        RefreshUnits(false)
    end
    if editor and editor.healAt and now >= editor.healAt then
        editor.healAt, editor.demoHealth = nil, 4400
        RefreshUnits(false)
    end
    if editor and editor.demoUntil and now >= editor.demoUntil then
        editor.demoUntil, editor.demoHealth = nil, nil
        RefreshUnits(true)
    end
    local active = editor ~= nil
    local function Animate(bar)
        if bar.pendingAt and now >= bar.pendingAt then
            NativeValue(bar.trail, bar.pendingValue, Addon:GetResourceSettings().smooth)
            bar.pendingAt, bar.pendingValue = nil, nil
        end
        if bar.pulseAt then
            local remaining = 1 - (now - bar.pulseAt) / Addon.resourceMotion[bar.motion].fade
            local pulse = bar.curved and bar.arcPulse or bar.pulse
            if remaining <= 0 then pulse:Hide(); bar.pulseAt = nil
            else pulse:SetAlpha(remaining * remaining) end
        end
        if bar.pendingAt or bar.pulseAt then active = true end
    end
    Animate(display.player.health)
    Animate(display.player.power)
    Animate(display.pet.health)
    Animate(display.pet.power)
    for _, view in ipairs(display.party) do Animate(view.health); Animate(view.power) end
    if not active then driver:SetScript("OnUpdate", nil) end
end

for _, event in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_POWER_UPDATE", "UNIT_MAXPOWER",
    "UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_PORTRAIT_UPDATE", "UNIT_MODEL_CHANGED", "UNIT_CONNECTION",
    "GROUP_ROSTER_UPDATE", "UNIT_PET", "UPDATE_SHAPESHIFT_FORM", "PLAYER_ENTERING_WORLD", "PLAYER_ALIVE", "PLAYER_DEAD", "PLAYER_UNGHOST",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_LOGOUT", "CVAR_UPDATE" }) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event, unit)
    if not Addon.character or not Addon.character.resources then return end
    if event == "PLAYER_LOGOUT" then
        shuttingDown = true
        if editor then Addon:FinishResourceEdit(false, true) end
        local original = Addon.character.originalSelfResourceCVar
        local set = C_CVar and C_CVar.SetCVar or SetCVar
        if original ~= nil and set and not InCombatLockdown() then
            set("nameplateShowSelf", original)
            Addon.character.originalSelfResourceCVar = nil
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if editor then Addon:FinishResourceEdit(false) else RefreshUnits(true) end
        if Addon.RefreshResourceOptions then Addon:RefreshResourceOptions() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        RefreshUnits(true)
        Addon:SyncNativeResources()
        if Addon.RefreshResourceOptions then Addon:RefreshResourceOptions() end
    elseif event == "CVAR_UPDATE" then
        if unit and string.lower(unit) == "nameplateshowself" then Addon:SyncNativeResources() end
    elseif event == "UNIT_PET" then
        if display and unit == "player" then UpdateView(display.pet, true) end
    elseif event == "UPDATE_SHAPESHIFT_FORM" then
        if display then UpdateView(display.player, true) end
    elseif event:sub(1, 5) == "UNIT_" then
        if not display then return end
        local view = unit == "player" and display.player or unit == "pet" and display.pet
        if not view then for _, member in ipairs(display.party) do if member.unit == unit then view = member; break end end end
        if view then
            if event == "UNIT_HEALTH" and editor and editor.demoUntil and UnitExists(unit) then
                -- Actual damage/healing interrupts the demonstration immediately.
                editor.demoUntil, editor.demoHealth, editor.damageAt, editor.healAt = nil, nil, nil, nil
                RefreshUnits(true)
            else UpdateView(view, false, event) end
        end
    else
        if display then RefreshUnits(true) end
    end
end)
