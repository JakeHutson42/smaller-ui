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
}
local ranges = { healthFormat = { 0, 5 }, powerFormat = { 0, 5 }, fontSize = { 6, 48 },
    font = { 1, 3 }, alignment = { 1, 3 }, backgroundOpacity = { 0, 100 },
    combatOpacity = { 0, 100 }, outOfCombatOpacity = { 0, 100 }, barTexture = { 1, #Addon.resourceTextures } }
local fonts = { false, "Fonts\\ARIALN.TTF", "Fonts\\SKURRI.TTF" }
local alignments = { "LEFT", "CENTER", "RIGHT" }

function Addon:DefaultResourceStyle()
    return { healthFormat = 2, powerFormat = 2, fontSize = 12, autoFontSize = true, font = 1,
        alignment = 3, shortNumbers = false, border = true, backgroundOpacity = 94,
        hideOutOfCombat = false, combatOpacity = 100, outOfCombatOpacity = 100, barTexture = 1,
        textColour = { r = 1, g = 1, b = 1 }, borderColour = { r = 0.13, g = 0.16, b = 0.19 } }
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

function Addon:StyleResourceBar(bar, settings, editing)
    local style = settings.style
    local texture = self.resourceTextures[style.barTexture][3]
    if bar.appliedTexture ~= texture then
        -- Keep the same texture regions so the prediction and pulse anchors stay attached.
        bar.fill:GetStatusBarTexture():SetTexture(texture)
        bar.trail:GetStatusBarTexture():SetTexture(texture)
        if bar.forecasts then
            for _, kind in ipairs({ "direct", "hot", "dot" }) do
                bar.forecasts[kind]:GetStatusBarTexture():SetTexture(texture)
            end
        end
        bar.appliedTexture = texture
    end
    local color = style.borderColour
    bar:SetBackdropBorderColor(editing and 0.85 or color.r, editing and 0.7 or color.g, editing and 0.35 or color.b,
        editing and 1 or style.border and 1 or 0)
    bar:SetBackdropColor(0.035, 0.045, 0.055, style.backgroundOpacity / 100)
    self:ResourceFont(bar.label, style, settings[bar.resourceKind].height)
    self:ResourceFont(bar.valueText, style, settings[bar.resourceKind].height)
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
    if not settings or not settings.style then return false end
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
    if not settings or not settings.style or key ~= "textColour" and key ~= "borderColour" then return false end
    if not Number(r) or not Number(g) or not Number(b) or r < 0 or r > 1 or g < 0 or g > 1 or b < 0 or b > 1 then return false end
    settings.style[key] = { r = r, g = g, b = b }
    self:RefreshResourceStyles()
    return true
end
