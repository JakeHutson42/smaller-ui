local _, Addon = ...
local formats = { { 0, "Hidden" }, { 1, "Current" }, { 2, "Current / maximum" },
    { 3, "Percentage" }, { 4, "Current + percentage" }, { 5, "Current / max + %" } }
local fonts = { { 1, "Game default" }, { 2, "Arial" }, { 3, "Skurri" } }
local alignments = { { 1, "Left" }, { 2, "Centre" }, { 3, "Right" } }
local advancedTop = -124

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
    page.border = UI.Checkbox(host, prefix .. "Border", "Show bar borders", 4, 0,
        function(enabled) Addon:SetResourceStyle(scope, "border", enabled) end,
        "Hide the border around your bars. Edit mode still shows a temporary guide.")
    page.borderColour = ColourButton(host, "BorderColour", "Border colour", 208, 0, "borderColour")
    UI.Label(host, "Bar texture", 12, -48)
    page.texture = UI.Select(host, prefix .. "BarTexture", 148, -42, 164, Addon.resourceTextures,
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
    local texturePreview = host:CreateTexture(nil, "ARTWORK")
    texturePreview:SetPoint("TOPLEFT", 328, -49)
    texturePreview:SetSize(112, 12)
    local textToggle, resourceToggle
    textToggle = UI.Button(host, prefix .. "TextToggle", "Text settings...", 12, -84, 180, function()
        text:SetShown(not text:IsShown())
        textToggle:SetText(text:IsShown() and "Hide text settings" or "Text settings...")
        Reflow()
    end)
    resourceToggle = UI.Button(host, prefix .. "ResourceColoursToggle", "Resource colours...", 208, -84, 180, function()
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
        texturePreview:SetTexture(Addon.resourceTextures[style.barTexture][3])
        texturePreview:SetVertexColor(Addon:GetResourceColour(scope, "health"))
        self.autoFontSize:SetChecked(style.autoFontSize)
        self.shortNumbers:SetChecked(style.shortNumbers)
        local border, colour = style.borderColour, style.textColour
        self.borderColour.swatch:SetColorTexture(border.r, border.g, border.b)
        self.textColour.swatch:SetColorTexture(colour.r, colour.g, colour.b)
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
