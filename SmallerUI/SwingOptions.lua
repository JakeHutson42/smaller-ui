local _, Addon = ...
local page
local weapons = { { 1, "Main hand" }, { 2, "Off hand" }, { 3, "Ranged" } }
local shapes = { { 1, "Line and dot" }, { 2, "Filled bar" } }

local function Settings() return Addon:GetResourceSettings().swing end

function Addon:RefreshSwingOptions()
    if not page then return end
    local settings = Settings()
    local supported = self:SupportsSwingTimer()
    page.enabled:SetEnabled(supported == true)
    page.enabled:SetChecked(supported and settings.enabled or false)
    page.move:SetEnabled(not InCombatLockdown())
    page.texture:SetEnabled(settings.shape == 2)
    for key, input in pairs(page.inputs) do input:SetText(tostring(settings[key])) end
    for _, dropdown in ipairs(page.dropdowns) do dropdown:GenerateMenu() end
    self:StyleSwingDisplay(page.preview, settings)
    page.preview.bar:SetValue(0.56)
    self:SetPageStatus("swing", supported and ""
        or "The native swing event is unavailable on this client.")
end

function Addon:BuildSwingOptions()
    local UI = self.OptionsUI
    page = UI.Page("SmallerUISwingOptions", "Swing timer", 324)
    local content = page.content
    local prefix = "SmallerUISwing"
    page.inputs, page.dropdowns = {}, {}
    page.enabled = UI.Switch(content, prefix .. "Enabled", "Show swing timer", 4, 0,
        function(value) Addon:SetSwingTimerOption("enabled", value) end)
    page.move = UI.Button(content, prefix .. "Move", "Move timer", 328, 0, 148, function() Addon:BeginResourceEdit() end)
    UI.Section(content, "Style and weapon", -46)

    local function Select(key, label, entries, x, y, initialize)
        UI.Label(content, label, x, y - 6)
        local dropdown = UI.Select(content, prefix .. key, x + 102, y, 164, entries,
            function() return Settings()[key] end,
            function(value) Addon:SetSwingTimerOption(key, value) end, initialize)
        page.dropdowns[#page.dropdowns + 1] = dropdown
        return dropdown
    end
    Select("weapon", "Track", weapons, 12, -82)
    Select("shape", "Style", shapes, 322, -82)
    Select("theme", "Theme", Addon.swingThemes, 12, -124, function(button, entry)
        local swatch = button:AttachTexture()
        swatch:SetPoint("RIGHT", -8, 0)
        swatch:SetSize(36, 10)
        swatch:SetColorTexture(entry[3], entry[4], entry[5])
        return 150, 22
    end)
    page.texture = Select("texture", "Bar texture", Addon.resourceTextures, 322, -124, function(button, entry)
        local swatch = button:AttachTexture()
        swatch:SetPoint("RIGHT", -8, 0)
        swatch:SetSize(104, 12)
        swatch:SetTexture(entry[3])
        local theme = Addon.swingThemes[Settings().theme]
        swatch:SetVertexColor(theme[3], theme[4], theme[5])
        return 244, 22
    end)
    UI.Tooltip(page.texture, "Applies to the filled bar style.")

    local function SizeInput(key, label, x)
        UI.Label(content, label, x, -172)
        local range = Addon.swingSizeLimits[key]
        local input = CreateFrame("EditBox", prefix .. key, content, "InputBoxTemplate")
        input:SetPoint("TOPLEFT", x + 102, -166)
        input:SetSize(72, 24)
        input:SetAutoFocus(false)
        input:SetMaxLetters(3)
        input:SetScript("OnEnterPressed", function(self)
            if not Addon:SetSwingTimerOption(key, tonumber(self:GetText())) then
                Addon:OptionsFeedback(string.format("Enter a whole number from %d to %d.", range[1], range[2]), true, "swing")
            end
            self:SetText(tostring(Settings()[key]))
            self:ClearFocus()
        end)
        input:SetScript("OnEscapePressed", function(self) self:SetText(tostring(Settings()[key])); self:ClearFocus() end)
        UI.NumberArrows(input, 1, range[1], range[2], function() return Settings()[key] end,
            function(value) return Addon:SetSwingTimerOption(key, value) end)
        page.inputs[key] = input
    end
    SizeInput("width", "Width", 12)
    SizeInput("height", "Height / dot", 322)

    UI.Section(content, "Preview", -222)
    page.preview = self:CreateSwingDisplay(content, prefix .. "Preview")
    page.preview:SetPoint("TOPLEFT", 18, -270)
    page:SetScript("OnShow", function()
        Addon.currentOptionsPage = "swing"
        Addon:OptionsFeedback("", false, "swing")
        Addon:RefreshSwingOptions()
    end)
    return page
end
