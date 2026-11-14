local _, Addon = ...
local pages = {}
local activePicker
local definitions = {
    player = { key = "resources", prefix = "SmallerUIPersonal", title = "Personal bars", enabled = "enabled" },
    party = { key = "party", prefix = "SmallerUIParty", title = "Party bars", enabled = "partyEnabled" },
    pet = { key = "pet", prefix = "SmallerUIPet", title = "Pet bars", enabled = "petEnabled" },
}

function Addon:CancelResourceColourPicker(scope)
    if not activePicker or scope and activePicker.scope ~= scope then return end
    local ticket = activePicker
    if ColorPickerFrame and ColorPickerFrame:IsShown() and ColorPickerFrame.extraInfo == ticket then
        ticket.cancel()
        ColorPickerFrame:Hide()
    end
    activePicker = nil
end

function Addon:OpenResourceColourPicker(scope, kind, token)
    self:CancelResourceColourPicker()
    if not ColorPickerFrame and C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_ColorPickerFrame") end
    if not ColorPickerFrame or not ColorPickerFrame.SetupColorPickerAndShow then
        self:OptionsFeedback("WoW's colour picker is unavailable. Try again after loading.", true, definitions[scope].key)
        return false
    end
    if ColorPickerFrame:IsShown() then
        if ColorPickerFrame.cancelFunc then ColorPickerFrame.cancelFunc(ColorPickerFrame.previousValues) end
        ColorPickerFrame:Hide()
    end
    local colours = self:GetResourceSettings()[scope].colours
    local styleColour = self.resourceStyleColours[kind]
    local original
    if token then original = colours.powerOverrides[token]
    elseif styleColour then original = self:GetResourceSettings()[scope].style[kind]
    else original = colours[kind] end
    local byType = colours.powerByType
    local r, g, b
    if styleColour then r, g, b = original.r, original.g, original.b
    else r, g, b = self:GetResourceColour(scope, kind, token) end
    local function Apply(red, green, blue)
        if token then return self:SetResourcePowerOverride(scope, token, red, green, blue) end
        if styleColour then return self:SetResourceStyleColour(scope, kind, red, green, blue) end
        return self:SetResourceColour(scope, kind, red, green, blue)
    end
    local ticket = { scope = scope }
    local initializing = true
    ticket.cancel = function()
        if activePicker ~= ticket then return end
        if original then Apply(original.r, original.g, original.b) else Apply(nil) end
        if kind == "power" then self:SetResourcePowerByType(scope, byType) end
        activePicker = nil
    end
    activePicker = ticket
    ColorPickerFrame:SetupColorPickerAndShow({ r = r, g = g, b = b, hasOpacity = false, extraInfo = ticket,
        swatchFunc = function()
            if initializing or activePicker ~= ticket then return end
            Apply(ColorPickerFrame:GetColorRGB())
        end,
        cancelFunc = ticket.cancel,
    })
    initializing = false
    return true
end

function Addon:RefreshResourceOptions(syncInput)
    if not self.character or not self.character.resources then return end
    local cfg = self:GetResourceSettings()
    for scope, page in pairs(pages) do
        local settings = cfg[scope]
        local definition = definitions[scope]
        local enabled = cfg[definition.enabled]
        page.enabled:SetChecked(enabled)
        page.linked:SetChecked(settings.linked)
        page.healthEnabled:SetChecked(settings.health.enabled)
        page.powerEnabled:SetChecked(settings.power.enabled)
        if page.arcLinked then page.arcLinked:SetChecked(settings.arc.linked) end
        if page.layout then
            page.horizontalLayout:SetShown(not settings.curved)
            page.arcLayout:SetShown(settings.curved)
            if page:IsShown() then page.layout:GenerateMenu() end
        end
        page.values:SetChecked(settings.values)
        page.powerByType:SetChecked(settings.colours.powerByType)
        page.healthColour.swatch:SetColorTexture(self:GetResourceColour(scope, "health"))
        page.powerColour.swatch:SetColorTexture(self:GetResourceColour(scope, "power"))
        page.combatOnly:SetChecked(settings.style.hideOutOfCombat)
        page.syncingOpacity = true
        for key, slider in pairs(page.opacitySliders) do
            local value = settings.style[key]
            slider:SetValue(value)
            slider.Text:SetText(string.format("%s  %d%%", slider.caption, value))
        end
        page.syncingOpacity = false
        if page.RefreshStyling then page:RefreshStyling(syncInput) end
        page.move:SetEnabled(not InCombatLockdown())
        if scope == "player" then
            page.hideBlizzard:SetChecked(cfg.hideBlizzard)
            page.smooth:SetChecked(cfg.smooth)
            page.incoming:SetChecked(cfg.incomingHeals)
            local periodic = self:CanPredictPeriodicResources()
            page.hots:SetChecked(periodic and cfg.periodicHeals)
            page.dots:SetChecked(periodic and cfg.periodicDamage)
            page.hots:SetEnabled(periodic)
            page.dots:SetEnabled(periodic)
            if page.seal then
                page.seal:SetChecked(cfg.seal.enabled)
                page.sealLinked:SetChecked(cfg.seal.linked)
            end
        else
            page.names:SetChecked(settings.names)
            page.portraits:SetChecked(settings.portraits)
        end
        if syncInput then
            local values = { scale = settings.scale, gap = settings.gap, spacing = settings.spacing,
                healthWidth = settings.health.width, healthHeight = settings.health.height,
                powerWidth = settings.power.width, powerHeight = settings.power.height }
            for key, input in pairs(page.inputs) do input:SetText(string.format("%.2f", values[key])) end
            for key, input in pairs(page.arcInputs or {}) do input:SetText(string.format("%.2f", settings.arc[key])) end
            if page.sealInputs then
                for key, input in pairs(page.sealInputs) do input:SetText(string.format("%.2f", cfg.seal[key])) end
            end
        end
        local status = ""
        if InCombatLockdown() then status = "Live values keep updating. Move and resize after combat."
        elseif self.resourceCVarPending then status = "Blizzard display changes will apply after combat." end
        self:SetPageStatus(definition.key, status)
    end
end

function Addon:BuildResourceOptions()
    local UI = self.OptionsUI
    local function Build(scope)
        local player = scope == "player"
        local definition = definitions[scope]
        local key, prefix = definition.key, definition.prefix
        local page = UI.Page(prefix .. "Options", definition.title, 360)
        pages[scope], page.inputs = page, {}
        local function Panel(height)
            local panel = CreateFrame("Frame", nil, page.content)
            panel:SetPoint("TOPLEFT")
            panel:SetSize(620, height)
            return panel
        end
        local display = Panel(player and 478 or 284)
        local layout = Panel(scope == "party" and 360 or player and Addon:IsPaladin() and 424 or 306)
        local appearancePanel = Panel(340)
        local content = display
        local function Notice(text, error) Addon:OptionsFeedback(text, error, key) end
        local function Switch(name, label, x, y, settingScope, setting, tip, parent)
            return UI.Switch(parent or content, prefix .. name, label, x, y, function(enabled)
                Addon:SetResourceOption(settingScope, setting, enabled)
            end, tip)
        end
        UI.Section(display, "Visibility", 0)
        page.enabled = Switch("Enabled", "Show " .. definition.title:lower(), 12, -34, "root", definition.enabled)
        page.healthEnabled = UI.Switch(display, prefix .. "HealthEnabled", "Health bar", 12, -72,
            function(enabled) Addon:SetResourceBarEnabled(scope, "health", enabled) end)
        page.powerEnabled = UI.Switch(display, prefix .. "PowerEnabled", "Power bar", 314, -72,
            function(enabled) Addon:SetResourceBarEnabled(scope, "power", enabled) end)
        if player then
            page.hideBlizzard = Switch("HideBlizzard", "Hide Blizzard's personal bar", 314, -34, "root", "hideBlizzard")
        else
            page.names = Switch("Names", scope == "pet" and "Show name" or "Show names", 12, -110, scope, "names")
            page.portraits = Switch("Portraits", scope == "pet" and "Show portrait" or "Show portraits", 314, -110, scope, "portraits")
        end
        content = layout
        UI.Section(layout, "Position and size", 0)
        page.move = UI.Button(layout, prefix .. "Move", "Move Mode", 12, -34, 172, function() Addon:BeginResourceEdit() end)
        UI.Button(layout, prefix .. "Reset", "Reset layout", 196, -34, 140, function()
            Addon:ResetResourceLayout(scope)
            Addon:RefreshResourceOptions(true)
            Notice("Default layout restored.")
        end)
        local horizontal = content
        if player then
            page.layout = UI.Select(content, prefix .. "Layout", 356, -34, 212, { { 1, "Horizontal bars" }, { 2, "Curved HUD" } },
                function() return Addon:GetResourceSettings().player.curved and 2 or 1 end,
                function(value)
                    Addon:SetResourceOption("player", "curved", value == 2)
                    Addon:RefreshResourceOptions(true)
                end)
            UI.Tooltip(page.layout, "Choose stacked bars or arcs on either side of the screen.")
            horizontal = CreateFrame("Frame", nil, content)
            horizontal:SetPoint("TOPLEFT", 0, 0)
            horizontal:SetSize(620, 290)
            page.horizontalLayout = horizontal
            page.arcLayout = CreateFrame("Frame", nil, content)
            page.arcLayout:SetPoint("TOPLEFT", 0, 0)
            page.arcLayout:SetSize(620, 290)
            page.arcLayout:Hide()
            page.arcInputs = {}
        end
        page.linked = Switch("Linked", "Move and resize bars together", 4, -100, scope, "linked",
            "In edit mode, dragging moves the whole group and corner resizing changes both bars proportionally. Uncheck to move and resize each bar separately. Exact sizes below can always be entered individually.", horizontal)
        local function Apply(arc)
            local inputs = arc and page.arcInputs or page.inputs
            local values = {}
            for field, input in pairs(inputs) do
                values[field] = tonumber(input:GetText())
                if not values[field] then Notice("Enter a valid number in every size field.", true); return end
            end
            if not Addon:SetResourceDimensions(arc and "arc" or scope, values) then
                Notice(arc and "Arc width: 20-120. Height: 80-640. Separation: 80-1000. Scale: 0.25-3."
                    or "Width: 8-8192. Height: 2-1024. Scale: 0.10-5.00. Spacing: 0-200.", true)
                return
            end
            for _, input in pairs(inputs) do input:ClearFocus() end
            Addon:RefreshResourceOptions(true)
            Notice("Bar sizes saved.")
        end
        local function Input(field, x, y, arc)
            local input = CreateFrame("EditBox", prefix .. (arc and "Arc" or "") .. field, arc and page.arcLayout or horizontal, "InputBoxTemplate")
            input:SetSize(80, 24)
            input:SetPoint("TOPLEFT", x, y)
            input:SetAutoFocus(false)
            input:SetMaxLetters(12)
            input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            input:SetScript("OnEnterPressed", function() Apply(arc) end)
            local minimum = field == "scale" and 0.1 or field:find("Width") and 8 or field:find("Height") and 2 or 0
            local maximum = field == "scale" and 5 or field:find("Width") and 8192 or field:find("Height") and 1024 or 200
            if arc then minimum, maximum = unpack(Addon.resourceArcLimits[field]) end
            local function Current()
                local settings = Addon:GetResourceSettings()[scope]
                if arc then return settings.arc[field] end
                if field == "healthWidth" then return settings.health.width end
                if field == "healthHeight" then return settings.health.height end
                if field == "powerWidth" then return settings.power.width end
                if field == "powerHeight" then return settings.power.height end
                return settings[field]
            end
            UI.NumberArrows(input, field == "scale" and 0.01 or 1, minimum, maximum, Current, function(value)
                if not Addon:SetResourceDimensions(arc and "arc" or scope, { [field] = value }) then return false end
                Notice("Bar size saved.")
            end)
            local inputs = arc and page.arcInputs or page.inputs
            inputs[field] = input
        end
        UI.Label(horizontal, "Scale", 12, -152)
        Input("scale", 148, -146)
        UI.Label(horizontal, "Bar gap", 312, -152)
        Input("gap", 444, -146)
        UI.Label(horizontal, "Bar", 12, -196, "GameFontNormalSmall")
        UI.Label(horizontal, "Width", 148, -196, "GameFontNormalSmall")
        UI.Label(horizontal, "Height", 308, -196, "GameFontNormalSmall")
        UI.Label(horizontal, "Health", 12, -226)
        UI.Label(horizontal, "Power", 12, -264)
        Input("healthWidth", 148, -220)
        Input("healthHeight", 308, -220)
        Input("powerWidth", 148, -258)
        Input("powerHeight", 308, -258)
        UI.Button(horizontal, prefix .. "Apply", "Apply sizes", 432, -258, 132, function() Apply(false) end)
        if player then
            page.arcLinked = UI.Switch(page.arcLayout, prefix .. "ArcLinked", "Move arcs together", 4, -100,
                function(enabled) Addon:SetResourceOption("arc", "linked", enabled) end)
            UI.Label(page.arcLayout, "Arc scale", 12, -152)
            Input("scale", 148, -146, true)
            UI.Label(page.arcLayout, "Separation", 312, -152)
            Input("gap", 444, -146, true)
            UI.Label(page.arcLayout, "Arc width", 12, -198)
            Input("width", 148, -192, true)
            UI.Label(page.arcLayout, "Arc height", 312, -198)
            Input("height", 444, -192, true)
            UI.Button(page.arcLayout, prefix .. "ArcApply", "Apply arc sizes", 432, -258, 132, function() Apply(true) end)
        end
        if scope == "party" then
            UI.Label(layout, "Member spacing", 12, -316)
            Input("spacing", 148, -310)
        end
        content = display
        local combat = player and -118 or -154
        UI.Section(display, "Combat visibility", combat)
        page.combatOnly = UI.Switch(display, prefix .. "CombatOnly", "Hide out of combat", 12, combat - 30,
            function(enabled) Addon:SetResourceStyle(scope, "hideOutOfCombat", enabled) end)
        local function OpacitySlider(key, caption, x)
            local slider = CreateFrame("Slider", prefix .. key, display, "UISliderTemplateWithLabels")
            slider:SetPoint("TOPLEFT", x, combat - 88)
            slider:SetSize(236, 16)
            slider:SetMinMaxValues(0, 100)
            slider:SetValueStep(1)
            slider:SetObeyStepOnDrag(true)
            slider.Low:SetText("0%")
            slider.High:SetText("100%")
            slider.caption = caption
            slider:SetScript("OnValueChanged", function(_, value)
                if page.syncingOpacity then return end
                Addon:SetResourceStyle(scope, key, math.floor(value + 0.5))
            end)
            return slider
        end
        page.opacitySliders = {
            combatOpacity = OpacitySlider("combatOpacity", "In-combat opacity", 12),
            outOfCombatOpacity = OpacitySlider("outOfCombatOpacity", "Out-of-combat opacity", 320),
        }
        content = appearancePanel
        local appearance = 0
        UI.Section(content, "Bar style", appearance)
        page.values = Switch("Values", "Show bar values", 12, -34, scope, "values")
        if player then
            page.smooth = Switch("Smooth", "Animate change trail", 314, -34, "root", "smooth",
                "Animate the trail behind each bar. Live values update immediately.")
        end
        local function ColourButton(kind, label, x)
            local button = UI.Button(content, prefix .. kind .. "Colour", label, x, appearance - 72, 180,
                function() Addon:OpenResourceColourPicker(scope, kind) end)
            button.swatch = button:CreateTexture(nil, "OVERLAY")
            button.swatch:SetSize(14, 14)
            button.swatch:SetPoint("TOPLEFT", 156, -5)
            UI.Tooltip(button, kind == "health" and "Choose your health bar colour. Incoming healing uses lighter shades of this colour."
                or "Choose a custom power bar colour for this display. This switches off automatic power-type colouring until you enable it again.")
            return button
        end
        page.healthColour = ColourButton("health", "Health colour", 12)
        page.powerColour = ColourButton("power", "Power colour", 208)
        UI.Button(content, prefix .. "ResetColours", "Reset colours", 408, appearance - 72, 164, function()
            Addon:CancelResourceColourPicker(scope)
            Addon:ResetResourceColours(scope)
            Notice("Default colours restored: red health and power-type colours.")
        end)
        page.powerByType = UI.Switch(content, prefix .. "PowerByType", "Use power-type colours", 4, appearance - 106,
            function(enabled)
                Addon:CancelResourceColourPicker(scope)
                Addon:SetResourcePowerByType(scope, enabled)
            end, "Automatically colour Mana, Rage, Energy, Focus and other resources to match their type. Uncheck to use your custom power colour.")
        Addon:BuildResourceStyleOptions(page, scope, prefix, appearancePanel, -142)
        content = display
        if player then
            local forecasts = -252
            UI.Section(content, "Health previews (all bars)", forecasts)
            page.incoming = Switch("IncomingHeals", "Show incoming healing", 12, forecasts - 32, "root", "incomingHeals",
                "A lighter extension shows healing reported by WoW, including your own casts. It clears when casts end or cancel. Instant heals may apply before a preview can appear.")
            page.hots = Switch("PeriodicHeals", "Estimate healing over time", 314, forecasts - 32, "root", "periodicHeals",
                "A pale extension estimates the next 5 seconds after observing at least two ticks of an active HoT. Estimates change with recent ticks and disappear if the game hides the required data.")
            page.dots = Switch("PeriodicDamage", "Estimate damage over time", 12, forecasts - 66, "root", "periodicDamage",
                "A muted red overlay estimates the next 5 seconds after observing at least two ticks of an active DoT. This is an estimate, not guaranteed damage.")
            if Addon:IsPaladin() then
                UI.Section(content, "Paladin seal", -368)
                page.seal = Switch("SealEnabled", "Show seal reminder", 12, -398, "seal", "enabled",
                    "Paladins only. Shows your active seal. When it ends, its last icon turns grey with a reminder. Drag the icon separately in Move mode. A question mark means the game withheld its aura status.")
                page.sealLinked = Switch("SealLinked", "Follow personal bars", 314, -398, "seal", "linked")
                display:SetHeight(442)
                UI.Section(layout, "Seal position and size", -304)
                page.sealInputs = {}
                local fields = { { "size", "Size", 12, 76, 8, 256 }, { "x", "X", 204, 232, -32768, 32768 },
                    { "y", "Y", 364, 392, -32768, 32768 } }
                for _, field in ipairs(fields) do
                    local setting, label, labelX, x, low, high = unpack(field)
                    UI.Label(layout, label, labelX, -344)
                    local input = CreateFrame("EditBox", prefix .. "Seal" .. setting, layout, "InputBoxTemplate")
                    input:SetSize(72, 24)
                    input:SetPoint("TOPLEFT", x, -338)
                    input:SetAutoFocus(false)
                    input:SetMaxLetters(10)
                    local function Current() return Addon:GetResourceSettings().seal[setting] end
                    local function Apply(value)
                        if not value then return false end
                        return Addon:SetResourceDimensions("seal", { [setting] = value })
                    end
                    input:SetScript("OnEscapePressed", function(self) self:SetText(tostring(Current())); self:ClearFocus() end)
                    input:SetScript("OnEnterPressed", function(self)
                        if not Apply(tonumber(self:GetText())) then
                            Notice(string.format("Enter a value from %d to %d.", low, high), true)
                        end
                        self:SetText(tostring(Current()))
                        self:ClearFocus()
                    end)
                    UI.NumberArrows(input, 1, low, high, Current, Apply)
                    page.sealInputs[setting] = input
                end
            else
                display:SetHeight(356)
            end
        end
        UI.Tabs(page, { { "display", "Display", display }, { "layout", "Layout", layout },
            { "appearance", "Appearance", appearancePanel } })
        page:SetScript("OnShow", function()
            Addon.currentOptionsPage = key
            Addon:OptionsFeedback("", false, key)
            Addon:RefreshResourceOptions(true)
        end)
        page:SetScript("OnHide", function()
            Addon:CancelResourceColourPicker(scope)
            for _, input in pairs(page.inputs) do input:ClearFocus() end
            for _, input in pairs(page.arcInputs or {}) do input:ClearFocus() end
            for _, input in pairs(page.sealInputs or {}) do input:ClearFocus() end
        end)
        return page
    end
    return Build("player"), Build("party"), Build("pet")
end
