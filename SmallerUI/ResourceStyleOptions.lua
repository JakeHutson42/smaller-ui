local _, Addon = ...
local formats = { { 0, "Hidden" }, { 1, "Current" }, { 2, "Current / maximum" },
    { 3, "Percentage" }, { 4, "Current + percentage" }, { 5, "Current / max + %" } }
local fonts = { { 1, "Game default" }, { 2, "Arial" }, { 3, "Skurri" } }
local alignments = { { 1, "Left" }, { 2, "Centre" }, { 3, "Right" } }
local advancedTop = -236
local WHITE = "Interface\\Buttons\\WHITE8X8"

local function PreviewBar(parent, y, height, value)
    local bar = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    bar:SetSize(218, height)
    bar:SetPoint("TOPLEFT", 374, y)
    if bar.SetRoundLayoutToNearestPixel then bar:SetRoundLayoutToNearestPixel(true) end
    bar.fill = CreateFrame("StatusBar", nil, bar)
    bar.fill:SetStatusBarTexture(WHITE)
    bar.fill:SetMinMaxValues(0, 100)
    bar.fill:SetValue(value)
    bar.trimLayer = bar.fill
    return bar
end

local function RefreshPreview(bar, style, r, g, b)
    local pixel = (PixelUtil and PixelUtil.GetPixelToUIUnitFactor() or 1) / bar:GetEffectiveScale()
    if pixel ~= bar.pixel then
        bar.pixel = pixel
        bar:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = pixel })
    end
    local inset = style.border and pixel or 0
    bar.fill:ClearAllPoints()
    bar.fill:SetPoint("TOPLEFT", inset, -inset)
    bar.fill:SetPoint("BOTTOMRIGHT", -inset, inset)
    bar.fill:SetStatusBarColor(r, g, b)
    Addon:StyleResourceSurface(bar, style, false)
end

function Addon:BuildResourceStyleOptions(page, scope, prefix, content, appearance)
    local UI = self.OptionsUI
    local host = CreateFrame("Frame", prefix .. "Styling", content)
    host:SetPoint("TOPLEFT", 0, appearance - 184)
    host:SetWidth(620)
    page.tail = CreateFrame("Frame", prefix .. "Tail", content)
    page.tail:SetSize(620, scope == "player" and 480 or 100)
    local text = CreateFrame("Frame", prefix .. "TextSettings", host)
    text:SetPoint("TOPLEFT", 0, advancedTop)
    text:SetSize(620, 224)
    text:Hide()
    local resources = CreateFrame("Frame", prefix .. "ResourceColours", host)
    resources:SetSize(620, 116)
    resources:Hide()
    page.resourceToken = "MANA"
    local sampleUnit = scope == "party" and "party1" or scope
    if UnitExists(sampleUnit) then
        local _, token = UnitPowerType(sampleUnit)
        if Addon:IsResourceColourToken(token) then page.resourceToken = token end
    end
    local dropdowns, inputs = {}, {}
    local function Settings() return Addon:GetResourceSettings()[scope].style end
    local function Reflow()
        local textHeight = text:IsShown() and 224 or 0
        local height = -advancedTop + textHeight + (resources:IsShown() and 116 or 0)
        host:SetHeight(height)
        resources:ClearAllPoints()
        resources:SetPoint("TOPLEFT", 0, advancedTop - textHeight)
        page.tail:ClearAllPoints()
        page.tail:SetPoint("TOPLEFT", 0, appearance - 184 - height - 28)
        content:SetHeight(-appearance + 184 + height + 28 + page.tail:GetHeight())
    end
    local function ColourButton(parent, name, label, x, y, kind, token)
        local button = UI.Button(parent, prefix .. name, label, x, y, 180,
            function() Addon:OpenResourceColourPicker(scope, kind, token and page.resourceToken or nil) end)
        button.swatch = button:CreateTexture(nil, "OVERLAY")
        button.swatch:SetSize(14, 14)
        button.swatch:SetPoint("TOPLEFT", 156, -5)
        return button
    end
    UI.Label(host, "Theme preset", 12, -6)
    local theme = UI.Select(host, prefix .. "Theme", 126, 0, 208, Addon.resourceThemes,
        function() return Settings().theme end,
        function(value)
            Addon:CancelResourceColourPicker(scope)
            Addon:ApplyResourceTheme(scope, value)
        end)
    dropdowns[#dropdowns + 1] = theme
    UI.Tooltip(theme, "Apply a texture, trim and palette to these bars. You can adjust each setting below.")
    local healthPreview = PreviewBar(host, -4, 17, 78)
    local powerPreview = PreviewBar(host, -26, 10, 61)
    page.themeColours = UI.Checkbox(host, prefix .. "ThemeColours", "Apply preset colours", 4, -40,
        function(enabled) Addon:SetResourceStyle(scope, "themeColours", enabled) end,
        "When enabled, applying a preset replaces the bar, border, background and accent colours. Turn it off to keep your palette.")
    page.border = UI.Checkbox(host, prefix .. "Border", "Show bar borders", 4, -78,
        function(enabled) Addon:SetResourceStyle(scope, "border", enabled) end,
        "Hide the border around your bars. Edit mode still shows a temporary guide.")
    page.borderColour = ColourButton(host, "BorderColour", "Border colour", 208, -78, "borderColour")
    page.trackColour = ColourButton(host, "TrackColour", "Background colour", 414, -78, "trackColour")
    UI.Label(host, "Bar texture", 12, -122)
    page.texture = UI.Select(host, prefix .. "BarTexture", 126, -116, 208, Addon.resourceTextures,
        function() return Settings().barTexture end,
        function(value) Addon:SetResourceStyle(scope, "barTexture", value) end,
        function(button, entry)
            local swatch = button:AttachTexture()
            swatch:SetPoint("RIGHT", -8, 0)
            swatch:SetSize(112, 12)
            swatch:SetTexture(entry[3])
            swatch:SetVertexColor(Addon:GetResourceColour(scope, "health"))
            return 252, 22
        end)
    dropdowns[#dropdowns + 1] = page.texture
    UI.Label(host, "Trim", 350, -122)
    local trim = UI.Select(host, prefix .. "Trim", 414, -116, 180, Addon.resourceTrims,
        function() return Settings().trim end,
        function(value) Addon:SetResourceStyle(scope, "trim", value) end)
    dropdowns[#dropdowns + 1] = trim
    UI.Tooltip(trim, "Choose the decoration on the bar border. Jewels scale down on thin bars.")
    UI.Label(host, "Motion", 12, -160)
    local motion = UI.Select(host, prefix .. "Motion", 126, -154, 208, Addon.resourceMotion,
        function() return Settings().motion end,
        function(value) Addon:SetResourceStyle(scope, "motion", value) end)
    dropdowns[#dropdowns + 1] = motion
    UI.Tooltip(motion, "Choose Off for static bars, Subtle for a short flash, Fluid for softer trails, or Vivid for stronger feedback on damage, healing and power spent. Live values update immediately.")
    page.accentColour = ColourButton(host, "AccentColour", "Accent colour", 414, -154, "accentColour")
    local textToggle, resourceToggle
    textToggle = UI.Button(host, prefix .. "TextToggle", "Text settings...", 12, -196, 180, function()
        text:SetShown(not text:IsShown())
        textToggle:SetText(text:IsShown() and "Hide text settings" or "Text settings...")
        Reflow()
    end)
    resourceToggle = UI.Button(host, prefix .. "ResourceColoursToggle", "Resource colours...", 208, -196, 180, function()
        Addon:CancelResourceColourPicker(scope)
        resources:SetShown(not resources:IsShown())
        resourceToggle:SetText(resources:IsShown() and "Hide resource colours" or "Resource colours...")
        Reflow()
    end)
    local function Select(key, label, choices, x, y, labelX, width)
        UI.Label(text, label, labelX, y - 6)
        local dropdown = UI.Select(text, prefix .. key, x, y, width or 164, choices,
            function() return Settings()[key] end, function(value) Addon:SetResourceStyle(scope, key, value) end)
        dropdowns[#dropdowns + 1] = dropdown
    end
    Select("healthFormat", "Health text", formats, 148, 0, 12)
    Select("powerFormat", "Power text", formats, 432, 0, 328)
    Select("font", "Font", fonts, 148, -42, 12)
    Select("alignment", "Alignment", alignments, 148, -90, 12)
    local function Input(key, label, x, y, labelX, low, high)
        UI.Label(text, label, labelX, y - 6)
        local input = CreateFrame("EditBox", prefix .. key, text, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x, y)
        input:SetSize(72, 24)
        input:SetAutoFocus(false)
        input:SetMaxLetters(3)
        input:SetScript("OnEnterPressed", function(self)
            if not Addon:SetResourceStyle(scope, key, tonumber(self:GetText())) then
                Addon:OptionsFeedback("Enter a whole number from " .. low .. " to " .. high .. ".", true)
            end
            self:SetText(tostring(Settings()[key]))
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self) self:SetText(tostring(Settings()[key])); self:ClearFocus() end)
        UI.NumberArrows(input, 1, low, high, function() return Settings()[key] end,
            function(value) return Addon:SetResourceStyle(scope, key, value) end)
        inputs[key] = input
    end
    Input("fontSize", "Text size", 432, -42, 328, 6, 48)
    page.autoFontSize = UI.Checkbox(text, prefix .. "AutoFontSize", "Automatic size", 320, -78,
        function(enabled) Addon:SetResourceStyle(scope, "autoFontSize", enabled) end)
    page.shortNumbers = UI.Checkbox(text, prefix .. "ShortNumbers", "Short numbers (12.3k)", 4, -132,
        function(enabled) Addon:SetResourceStyle(scope, "shortNumbers", enabled) end,
        "Use compact numbers when public values are available. Exact native values remain in restricted contexts.")
    page.textColour = ColourButton(text, "TextColour", "Text colour", 328, -130, "textColour")
    Input("backgroundOpacity", "Background %", 148, -178, 12, 0, 100)
    UI.Label(text, "Resource labels appear with right-aligned text when space allows.", 328, -177, "GameFontDisableSmall", 270)
    UI.Label(resources, "Resource", 12, -6)
    page.resourceSelect = UI.Select(resources, prefix .. "ResourceToken", 148, 0, 164,
        function() return Addon:GetResourceColourChoices(page.resourceToken) end,
        function() return page.resourceToken end,
        function(token) Addon:CancelResourceColourPicker(scope); page.resourceToken = token; Addon:RefreshResourceOptions() end)
    page.resourceColour = ColourButton(resources, "ResourceColour", "Resource colour", 328, 0, "power", true)
    UI.Button(resources, prefix .. "ResetResourceColour", "Use default colour", 328, -42, 180, function()
        Addon:CancelResourceColourPicker(scope)
        Addon:SetResourcePowerOverride(scope, page.resourceToken, nil)
    end)
    UI.Label(resources, "Choose a colour for each resource.", 12, -48, "GameFontDisableSmall", 300)
    UI.Label(resources, "Overrides follow the resource, including Druid form changes. Uses power-type colours.", 12, -84, "GameFontDisableSmall", 580)
    function page:RefreshStyling(syncInput)
        local style = Settings()
        self.border:SetChecked(style.border)
        self.themeColours:SetChecked(style.themeColours)
        RefreshPreview(healthPreview, style, Addon:GetResourceColour(scope, "health"))
        RefreshPreview(powerPreview, style, Addon:GetResourceColour(scope, "power"))
        self.autoFontSize:SetChecked(style.autoFontSize)
        self.shortNumbers:SetChecked(style.shortNumbers)
        local border, colour = style.borderColour, style.textColour
        self.borderColour.swatch:SetColorTexture(border.r, border.g, border.b)
        self.textColour.swatch:SetColorTexture(colour.r, colour.g, colour.b)
        local track, accent = style.trackColour, style.accentColour
        self.trackColour.swatch:SetColorTexture(track.r, track.g, track.b)
        self.accentColour.swatch:SetColorTexture(accent.r, accent.g, accent.b)
        self.resourceColour.swatch:SetColorTexture(Addon:GetResourceColour(scope, "power", self.resourceToken))
        inputs.fontSize:SetEnabled(not style.autoFontSize)
        inputs.fontSize.up:SetEnabled(not style.autoFontSize)
        inputs.fontSize.down:SetEnabled(not style.autoFontSize)
        inputs.fontSize:SetAlpha(style.autoFontSize and 0.45 or 1)
        for key, input in pairs(inputs) do if syncInput then input:SetText(tostring(style[key])) end end
        if self:IsShown() then
            for _, dropdown in ipairs(dropdowns) do dropdown:GenerateMenu() end
            self.resourceSelect:GenerateMenu()
        end
    end
    Reflow()
    return page.tail
end
