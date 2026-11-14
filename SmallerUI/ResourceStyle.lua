local _, Addon = ...
local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local media = "Interface\\AddOns\\SmallerUI\\Media\\"
Addon.resourceTextures = {
    { 1, "Flat", "Interface\\Buttons\\WHITE8X8" },
    { 2, "Soft gradient", media .. "SoftGradient.tga" },
    { 3, "Gloss", media .. "Gloss.tga" },
    { 4, "Brushed", media .. "Brushed.tga" },
    { 5, "Satin", media .. "Satin.tga" },
    { 6, "Etched", media .. "Etched.tga" },
    { 7, "Woven", media .. "Woven.tga" },
    { 8, "Glacier Glass", media .. "GlacierGlass.tga" },
    { 9, "Runefang", media .. "Runefang.tga" },
    { 10, "Rivetsteel", media .. "Rivetsteel.tga" },
}
Addon.resourceThemes = {
    { 1, "Classic" },
    { 2, "Satin", texture = 5, trim = 2, health = 0xCB465A, power = 0x498BDE, accent = 0x97AFCF },
    { 3, "Warlock: Soulfire", texture = 9, trim = 3, health = 0xAD55DB, power = 0x82C844, accent = 0xCDA5F8 },
    { 4, "Warrior: Iron Guard", texture = 10, trim = 2, health = 0xBE5045, power = 0xE39545, accent = 0xD6A27A },
    { 5, "Paladin: Judgement", texture = 6, trim = 3, health = 0xDDA542, power = 0x6F9CE5, accent = 0xFFE0A0 },
    { 6, "Hunter: Wildshot", texture = 7, trim = 2, health = 0x79AB57, power = 0xC7A057, accent = 0xBBD39C },
    { 7, "Rogue: Shadowstep", texture = 6, trim = 2, health = 0x986BB0, power = 0xDCB449, accent = 0xC8ADC9 },
    { 8, "Priest: Inner Light", texture = 5, trim = 3, health = 0xDDBD96, power = 0x7597D8, accent = 0xF9E4CD },
    { 9, "Shaman: Stormcall", texture = 6, trim = 3, health = 0x4EACC7, power = 0x647EE0, accent = 0xA5E2F4 },
    { 10, "Mage: Frostfire", texture = 8, trim = 3, health = 0x72C6ED, power = 0xA978EC, accent = 0xB6E7FF },
    { 11, "Druid: Wild Growth", texture = 7, trim = 3, health = 0x74B768, power = 0xCE9446, accent = 0xCCDF9A },
}
Addon.resourceMotion = {
    { 1, "Off", hold = 0 },
    { 2, "Subtle", hold = 0.12, fade = 0.25, opacity = 0.22 },
    { 3, "Fluid", hold = 0.08, fade = 0.34, opacity = 0.30, tintTrail = true },
    { 4, "Vivid", hold = 0.06, fade = 0.42, opacity = 0.40, tintTrail = true, powerPulse = true },
}
Addon.resourceTrims = { { 1, "Plain" }, { 2, "Fine line" }, { 3, "Jewelled" } }
local ranges = { healthFormat = { 0, 5 }, powerFormat = { 0, 5 }, fontSize = { 6, 48 },
    font = { 1, 3 }, alignment = { 1, 3 }, backgroundOpacity = { 0, 100 },
    combatOpacity = { 0, 100 }, outOfCombatOpacity = { 0, 100 }, barTexture = { 1, #Addon.resourceTextures },
    theme = { 1, #Addon.resourceThemes }, trim = { 1, #Addon.resourceTrims }, motion = { 1, #Addon.resourceMotion } }
Addon.resourceStyleColours = { textColour = true, borderColour = true, trackColour = true, accentColour = true }
local fonts = { false, "Fonts\\ARIALN.TTF", "Fonts\\SKURRI.TTF" }
local alignments = { "LEFT", "CENTER", "RIGHT" }

function Addon:DefaultResourceStyle()
    return { healthFormat = 2, powerFormat = 2, fontSize = 12, autoFontSize = true, font = 1,
        alignment = 3, shortNumbers = false, border = true, backgroundOpacity = 94,
        hideOutOfCombat = false, combatOpacity = 100, outOfCombatOpacity = 100, barTexture = 1,
        theme = 1, themeColours = true, trim = 1, motion = 2,
        textColour = { r = 1, g = 1, b = 1 }, borderColour = { r = 0.13, g = 0.16, b = 0.19 },
        trackColour = { r = 0.035, g = 0.045, b = 0.055 }, accentColour = { r = 0.59, g = 0.69, b = 0.81 } }
end

function Addon:IsResourceColourToken(token)
    return Public(token) and type(token) == "string" and #token <= 32 and token:match("^[A-Z_]+$") ~= nil
end

function Addon:GetResourceColourChoices(selected)
    local choices = { { "MANA", "Mana" }, { "RAGE", "Rage" }, { "ENERGY", "Energy" }, { "FOCUS", "Focus" } }
    local seen = { MANA = true, RAGE = true, ENERGY = true, FOCUS = true }
    local function Add(token)
        if self:IsResourceColourToken(token) and not seen[token] then
            local label = _G[token]
            choices[#choices + 1] = { token, type(label) == "string" and label or token }
            seen[token] = true
        end
    end
    for _, unit in ipairs({ "player", "pet", "party1", "party2", "party3", "party4" }) do
        if UnitExists(unit) then local _, token = UnitPowerType(unit); Add(token) end
    end
    Add(selected)
    return choices
end

function Addon:ValidateResourceStyles()
    for _, scope in ipairs({ "player", "party", "pet" }) do
        local settings = self:GetResourceSettings()[scope]
        local defaults = self:DefaultResourceStyle()
        for key, range in pairs(ranges) do
            local value = settings.style[key]
            if not Number(value) or value ~= math.floor(value) or value < range[1] or value > range[2] then settings.style[key] = defaults[key] end
        end
        local overrides = settings.colours.powerOverrides
        for token, color in pairs(overrides) do
            if not self:IsResourceColourToken(token) or type(color) ~= "table" or not Number(color.r)
                or not Number(color.g) or not Number(color.b) then overrides[token] = nil
            else
                for _, component in ipairs({ "r", "g", "b" }) do color[component] = math.max(0, math.min(1, color[component])) end
            end
        end
    end
end

function Addon:ResourceFont(label, style, height)
    local size = style.autoFontSize and math.max(9, math.min(15, height * 0.5)) or style.fontSize
    local font = fonts[style.font] or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
    if label.resourceFont ~= font or label.resourceFontSize ~= size then
        label:SetFont(font, size, "OUTLINE")
        label.resourceFont, label.resourceFontSize = font, size
    end
    local color = style.textColour
    label:SetTextColor(color.r, color.g, color.b)
end

local function TrimTexture(bar)
    local texture = bar:CreateTexture(nil, "OVERLAY")
    if texture.SetSnapToPixelGrid then texture:SetSnapToPixelGrid(false) end
    if texture.SetTexelSnappingBias then texture:SetTexelSnappingBias(0) end
    return texture
end

function Addon:SetResourceBarCurved(bar, curved)
    if bar.curved == curved then return end
    bar.curved = curved
    if curved and not bar.arcMask then
        local function Place(texture, file)
            texture:SetTexture(media .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            texture:SetAllPoints(bar)
            if bar.resourceKind == "power" then texture:SetTexCoord(1, 0, 0, 1) end
            return texture
        end
        bar.arcMask = Place(bar:CreateMaskTexture(), "ArcFill.tga")
        bar.arcTrack = Place(bar:CreateTexture(nil, "BACKGROUND"), "ArcFill.tga")
        bar.arcOutline = Place(bar:CreateTexture(nil, "BORDER"), "ArcOutline.tga")
    end
    if not bar.arcMask then return end

    local function Mask(texture)
        if curved then texture:AddMaskTexture(bar.arcMask)
        else texture:RemoveMaskTexture(bar.arcMask) end
    end
    local function Orient(status)
        status:SetOrientation(curved and "VERTICAL" or "HORIZONTAL")
        status:SetRotatesTexture(curved)
        Mask(status:GetStatusBarTexture())
    end
    Orient(bar.fill)
    Orient(bar.trail)
    Mask(bar.pulse)
    if bar.forecasts then
        for _, kind in ipairs({ "direct", "hot", "dot" }) do Orient(bar.forecasts[kind]) end
    end
    bar.arcTrack:SetShown(curved)
    bar.arcOutline:SetShown(curved)
end

function Addon:StyleResourceSurface(bar, style, editing)
    local texture = self.resourceTextures[style.barTexture][3]
    if bar.appliedTexture ~= texture then
        -- Keep the same texture regions so the prediction and pulse anchors stay attached.
        bar.fill:GetStatusBarTexture():SetTexture(texture)
        if bar.trail then bar.trail:GetStatusBarTexture():SetTexture(texture) end
        if bar.forecasts then
            for _, kind in ipairs({ "direct", "hot", "dot" }) do
                bar.forecasts[kind]:GetStatusBarTexture():SetTexture(texture)
            end
        end
        bar.appliedTexture = texture
    end
    local color = style.borderColour
    bar:SetBackdropBorderColor(editing and 0.85 or color.r, editing and 0.7 or color.g, editing and 0.35 or color.b,
        not bar.curved and (editing or style.border) and 1 or 0)
    local track = style.trackColour
    local opacity = style.backgroundOpacity / 100
    bar:SetBackdropColor(track.r, track.g, track.b, bar.curved and 0 or opacity)
    if bar.curved then
        local outline = style.trim > 1 and style.accentColour or color
        bar.arcTrack:SetVertexColor(track.r, track.g, track.b, opacity)
        bar.arcOutline:SetVertexColor(editing and 0.85 or outline.r, editing and 0.7 or outline.g, editing and 0.35 or outline.b,
            editing and 1 or style.trim > 1 and 0.65 or 1)
        bar.arcOutline:SetShown(style.border or editing)
    end

    local showTrim = not bar.curved and style.border and style.trim > 1 and not editing
    if showTrim and not bar.trim then
        local layer = bar.trimLayer
        local line = TrimTexture(layer)
        line:SetPoint("TOPLEFT", bar, "TOPLEFT")
        line:SetPoint("TOPRIGHT", bar, "TOPRIGHT")
        bar.trim = { line = line, left = TrimTexture(layer), right = TrimTexture(layer) }
        for _, side in ipairs({ "left", "right" }) do
            bar.trim[side]:SetTexture(media .. "TrimJewel.tga")
        end
        bar.trim.left:SetPoint("CENTER", bar, "LEFT")
        bar.trim.right:SetPoint("CENTER", bar, "RIGHT")
    end
    if not bar.trim then return end
    local accent, pixel = style.accentColour, bar.pixel
    bar.trim.line:SetHeight(pixel)
    bar.trim.line:SetColorTexture(accent.r, accent.g, accent.b, 0.62)
    bar.trim.line:SetShown(showTrim)
    local size = math.min(10, math.floor(bar:GetHeight() / pixel + 0.01) - 2) * pixel
    local showJewels = showTrim and style.trim == 3 and size >= 4 * pixel and bar:GetWidth() >= 8 * size
    for _, side in ipairs({ "left", "right" }) do
        local jewel = bar.trim[side]
        jewel:SetShown(showJewels)
        if showJewels then
            jewel:SetSize(size, size)
            jewel:SetVertexColor(accent.r, accent.g, accent.b)
        end
    end
end

function Addon:StyleResourceBar(bar, settings, editing)
    local style = settings.style
    self:StyleResourceSurface(bar, style, editing)
    local kind = bar.resourceKind
    if bar.curved then
        local tipOffset = settings.arc.width * (kind == "health" and 0.25 or -0.25)
        self:ResourceFont(bar.label, style, 18)
        self:ResourceFont(bar.valueText, style, 22)
        bar.label:ClearAllPoints()
        bar.label:SetPoint("BOTTOM", bar, "TOP", tipOffset, 1)
        bar.valueText:ClearAllPoints()
        bar.valueText:SetPoint("TOP", bar, "BOTTOM", tipOffset, -3)
        bar.valueText:SetWidth(math.min(140, settings.arc.gap))
        bar.valueText:SetJustifyH("CENTER")
        local visible = settings.values and style[kind .. "Format"] ~= 0
        bar.valueText:SetShown(visible)
        bar.label:SetShown(visible)
        return
    end
    bar.label:ClearAllPoints()
    bar.label:SetPoint("LEFT", 6, 0)
    self:ResourceFont(bar.label, style, settings[kind].height)
    self:ResourceFont(bar.valueText, style, settings[kind].height)
    bar.valueText:ClearAllPoints()
    bar.valueText:SetPoint("LEFT", 6, 0)
    bar.valueText:SetPoint("RIGHT", -6, 0)
    bar.valueText:SetJustifyH(alignments[style.alignment])
    local visible = settings.values and style[bar.resourceKind .. "Format"] ~= 0
        and settings[bar.resourceKind].height >= 12 and settings[bar.resourceKind].width >= 90
    bar.valueText:SetShown(visible)
    bar.label:SetShown(visible and style.alignment == 3 and style[bar.resourceKind .. "Format"] < 4 and settings[bar.resourceKind].width >= 180)
end

local function Short(value)
    if value >= 1000000000 then return string.format("%.1fb", value / 1000000000) end
    if value >= 1000000 then return string.format("%.1fm", value / 1000000) end
    if value >= 1000 then return string.format("%.1fk", value / 1000) end
    return string.format("%d", value)
end

function Addon:RenderResourceText(bar, value, maximum, demo)
    local style = self:GetResourceSettings()[bar.view.scope].style
    local format = style[bar.resourceKind .. "Format"]
    if bar.statusLabel then bar.valueText:SetText(bar.statusLabel); return end
    if format == 0 then bar.valueText:SetText(""); return end
    local percent
    if format >= 3 then
        if Number(value) and Number(maximum) then percent = maximum > 0 and value / maximum * 100 or 0
        elseif not demo and UnitExists(bar.view.unit) and CurveConstants and CurveConstants.ScaleTo100 then
            if bar.resourceKind == "health" and UnitHealthPercent then
                percent = UnitHealthPercent(bar.view.unit, true, CurveConstants.ScaleTo100)
            elseif bar.resourceKind == "power" and UnitPowerPercent then
                percent = UnitPowerPercent(bar.view.unit, bar.view.powerType, false, CurveConstants.ScaleTo100)
            end
        end
        -- Older clients may not expose a secret-safe percentage. Keep exact HP.
        if Public(percent) and percent == nil then format = 2 end
    end
    local short = style.shortNumbers and Number(value) and Number(maximum)
    local current, cap = value, maximum
    if short then current, cap = Short(value), Short(maximum) end
    if format == 1 then bar.valueText:SetFormattedText(short and "%s" or "%d", current)
    elseif format == 2 then bar.valueText:SetFormattedText(short and "%s / %s" or "%d / %d", current, cap)
    elseif format == 3 then bar.valueText:SetFormattedText("%.0f%%", percent)
    elseif format == 4 then bar.valueText:SetFormattedText(short and "%s (%.0f%%)" or "%d (%.0f%%)", current, percent)
    else bar.valueText:SetFormattedText(short and "%s / %s (%.0f%%)" or "%d / %d (%.0f%%)", current, cap, percent) end
end

function Addon:SetResourceStyle(scope, key, value)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.style or key == "theme" then return false end
    local default = self:DefaultResourceStyle()[key]
    if type(default) == "boolean" then
        if type(value) ~= "boolean" then return false end
    else
        local range = ranges[key]
        if not range or not Number(value) or value ~= math.floor(value) or value < range[1] or value > range[2] then return false end
    end
    if settings.style[key] == value then return true end
    settings.style[key] = value
    if key == "hideOutOfCombat" or key == "combatOpacity" or key == "outOfCombatOpacity" then
        self:RefreshResourceVisibility(scope)
        if self.RefreshResourceOptions then self:RefreshResourceOptions() end
    else
        self:RefreshResourceStyles()
    end
    return true
end

function Addon:SetResourceStyleColour(scope, key, r, g, b)
    local settings = self:GetResourceSettings()[scope]
    if not settings or not settings.style or not self.resourceStyleColours[key] then return false end
    if not Number(r) or not Number(g) or not Number(b) or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return false end
    settings.style[key] = { r = r, g = g, b = b }
    self:RefreshResourceStyles()
    return true
end
