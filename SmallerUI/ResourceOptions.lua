local _, Addon = ...
local pages = {}
local activePicker
local definitions = {
    player = { key = "resources", prefix = "SmallerUIPersonal", title = "Personal bars", enabled = "enabled",
        subtitle = "Health and power bars, exactly where you want them.",
        tip = "Show your health and current primary resource. Each character keeps their own layout.",
        status = "Live health and power updates. Layout saves for this character." },
    party = { key = "party", prefix = "SmallerUIParty", title = "Party bars", enabled = "partyEnabled",
        subtitle = "A compact health and power display for your party.",
        tip = "Show up to four party members. These visual bars leave your normal party controls available.",
        status = "Enabled. Party members appear when you are in a group." },
    pet = { key = "pet", prefix = "SmallerUIPet", title = "Pet bars", enabled = "petEnabled",
        subtitle = "Your pet's health and power, with a layout of its own.",
        tip = "Show your active pet's health and current power. Automatically hides when no pet is present.",
        status = "Enabled. Bars appear while you have an active pet." },
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
        if page.layout then
            page.horizontalLayout:SetShown(not settings.curved)
            page.arcLayout:SetShown(settings.curved)
            page.moveNote:SetText(settings.curved and "Drag either arc to move the pair. Hold Shift to ignore snapping. Escape cancels."
                or "Drag to move. Hold Shift to ignore snapping. Escape cancels. Corners resize.")
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
            page.periodicNote:SetText(periodic and "Applies to your personal, party and pet bars. Periodic previews are estimates."
                or "Separate HoT/DoT estimates are unavailable on this client. Incoming healing uses WoW's prediction.")
            page.seal:SetChecked(cfg.seal.enabled)
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
        local status = enabled and definition.status or "Disabled. Preview and position the bars before enabling."
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
        local page = UI.Page(prefix .. "Options", definition.title, definition.subtitle, player and 1140 or scope == "party" and 780 or 760)
        pages[scope], page.inputs = page, {}
        local content = page.content
        local function Notice(text, error) Addon:OptionsFeedback(text, error, key) end
        local function Checkbox(name, label, x, y, settingScope, setting, tip, parent)
            return UI.Checkbox(parent or content, prefix .. name, label, x, y, function(enabled)
                Addon:SetResourceOption(settingScope, setting, enabled)
            end, tip)
        end
        local enableLabel = player and "Show personal bars" or scope == "pet" and "Show pet bars" or "Show party bars"
        page.enabled = Checkbox("Enabled", enableLabel, 4, 0, "root", definition.enabled, definition.tip)
        if player then
            page.hideBlizzard = Checkbox("HideBlizzard", "Hide Blizzard's personal bar", 320, 0, "root", "hideBlizzard",
                "Hide the built-in personal resource display while custom bars are enabled. Your previous setting is restored when disabled or on a normal logout. Changes wait until combat ends.")
        end
        UI.Section(content, "Position and size", -54)
        page.move = UI.Button(content, prefix .. "Move", "Move mode", 12, -90, 172, function() Addon:BeginResourceEdit() end)
        UI.Button(content, prefix .. "Reset", "Reset layout", 196, -90, 140, function()
            Addon:ResetResourceLayout(scope)
            Addon:RefreshResourceOptions(true)
            Notice("Default layout restored.")
        end)
        page.moveNote = UI.Label(content, "Drag to move. Hold Shift to ignore snapping. Escape cancels. Corners resize.",
            12, -126, "GameFontDisableSmall", 580)
        local horizontal = content
        if player then
            page.layout = UI.Select(content, prefix .. "Layout", 356, -90, 212, { { 1, "Horizontal bars" }, { 2, "Curved HUD" } },
                function() return Addon:GetResourceSettings().player.curved and 2 or 1 end,
                function(value)
                    Addon:SetResourceOption("player", "curved", value == 2)
                    Addon:RefreshResourceOptions(true)
                end)
            UI.Tooltip(page.layout, "Choose stacked horizontal bars or put health and power on either side of the screen centre.")
            horizontal = CreateFrame("Frame", nil, content)
            horizontal:SetPoint("TOPLEFT", 0, 0)
            horizontal:SetSize(620, 390)
            page.horizontalLayout = horizontal
            page.arcLayout = CreateFrame("Frame", nil, content)
            page.arcLayout:SetPoint("TOPLEFT", 0, 0)
            page.arcLayout:SetSize(620, 390)
            page.arcLayout:Hide()
            page.arcInputs = {}
        end
        page.linked = Checkbox("Linked", "Move and resize bars together", 4, -160, scope, "linked",
            "In edit mode, dragging moves the whole group and corner resizing changes both bars proportionally. Uncheck to move and resize each bar separately. Exact sizes below can always be entered individually.", horizontal)
        local function Apply(arc)
            local inputs = arc and page.arcInputs or page.inputs
            local values = {}
            for field, input in pairs(inputs) do
                values[field] = tonumber(input:GetText())
                if not values[field] then Notice("Enter a valid number in every size field.", true); return end
            end
            if not Addon:SetResourceDimensions(arc and "arc" or scope, values) then
                Notice(arc and "Arc width 20–120, height 80–640, separation 80–1000, scale 0.25–3."
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
        UI.Label(horizontal, "Scale", 12, -212)
        Input("scale", 148, -206)
        UI.Label(horizontal, "Bar gap", 312, -212)
        Input("gap", 444, -206)
        UI.Label(horizontal, "Bar", 12, -256, "GameFontNormalSmall")
        UI.Label(horizontal, "Width", 148, -256, "GameFontNormalSmall")
        UI.Label(horizontal, "Height", 308, -256, "GameFontNormalSmall")
        UI.Label(horizontal, "Health", 12, -286)
        UI.Label(horizontal, "Power", 12, -324)
        Input("healthWidth", 148, -280)
        Input("healthHeight", 308, -280)
        Input("powerWidth", 148, -318)
        Input("powerHeight", 308, -318)
        UI.Button(horizontal, prefix .. "Apply", "Apply sizes", 432, -318, 132, function() Apply(false) end)
        UI.Label(horizontal, "Use Scale for the whole group, or enter each bar's exact dimensions.", 12, -358, "GameFontDisableSmall", 580)
        if player then
            UI.Label(page.arcLayout, "Health on the left. Your active resource on the right.", 12, -171, "GameFontHighlight")
            UI.Label(page.arcLayout, "Arc scale", 12, -212)
            Input("scale", 148, -206, true)
            UI.Label(page.arcLayout, "Separation", 312, -212)
            Input("gap", 444, -206, true)
            UI.Label(page.arcLayout, "Arc width", 12, -258)
            Input("width", 148, -252, true)
            UI.Label(page.arcLayout, "Arc height", 312, -258)
            Input("height", 444, -252, true)
            UI.Button(page.arcLayout, prefix .. "ArcApply", "Apply arc sizes", 432, -318, 132, function() Apply(true) end)
        end
        local appearance = -412
        if scope == "party" then
            UI.Label(content, "Member spacing", 12, -402)
            Input("spacing", 148, -396)
            appearance = -458
        end
        UI.Section(content, "Combat visibility", appearance)
        page.combatOnly = UI.Checkbox(content, prefix .. "CombatOnly", "Hide out of combat", 4, appearance - 36,
            function(enabled) Addon:SetResourceStyle(scope, "hideOutOfCombat", enabled) end,
            "Show this display during combat and in Move Mode.")
        local function OpacitySlider(key, caption, x)
            local slider = CreateFrame("Slider", prefix .. key, content, "UISliderTemplateWithLabels")
            slider:SetPoint("TOPLEFT", x, appearance - 100)
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
        UI.Tooltip(page.opacitySliders.outOfCombatOpacity, "Applies when Hide out of combat is off.")
        appearance = appearance - 156
        UI.Section(content, "Appearance", appearance)
        page.values = Checkbox("Values", "Show health and power values", 4, appearance - 36, scope, "values")
        if player then
            page.smooth = Checkbox("Smooth", "Animate change trail", 320, appearance - 36, "root", "smooth",
                "Animate only the dim recent-change trail. Current health, power and their numbers always update immediately from WoW, with no smoothing or timer delay.")
        else
            page.names = Checkbox("Names", scope == "pet" and "Show name" or "Show names", 320, appearance - 36, scope, "names")
            page.portraits = Checkbox("Portraits", scope == "pet" and "Show portrait" or "Show portraits", 4, appearance - 70, scope, "portraits")
        end
        local function ColourButton(kind, label, x)
            local button = UI.Button(content, prefix .. kind .. "Colour", label, x, appearance - 112, 180,
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
        UI.Button(content, prefix .. "ResetColours", "Reset colours", 408, appearance - 112, 164, function()
            Addon:CancelResourceColourPicker(scope)
            Addon:ResetResourceColours(scope)
            Notice("Default colours restored: red health and power-type colours.")
        end)
        page.powerByType = UI.Checkbox(content, prefix .. "PowerByType", "Use power-type colours", 4, appearance - 150,
            function(enabled)
                Addon:CancelResourceColourPicker(scope)
                Addon:SetResourcePowerByType(scope, enabled)
            end, "Automatically colour Mana, Rage, Energy, Focus and other resources to match their type. Uncheck to use your custom power colour.")
        content = Addon:BuildResourceStyleOptions(page, scope, prefix, content, appearance)
        if player then
            UI.Section(content, "Health previews", 0)
            page.incoming = Checkbox("IncomingHeals", "Show incoming healing", 4, -36, "root", "incomingHeals",
                "A lighter extension shows healing reported by WoW, including your own casts. It clears when casts end or cancel. Instant heals may apply before a preview can appear.")
            page.hots = Checkbox("PeriodicHeals", "Estimate healing over time", 4, -70, "root", "periodicHeals",
                "A pale extension estimates the next 5 seconds after observing at least two ticks of an active HoT. Estimates change with recent ticks and disappear if the game hides the required data.")
            page.dots = Checkbox("PeriodicDamage", "Estimate damage over time", 4, -104, "root", "periodicDamage",
                "A muted red overlay estimates the next 5 seconds after observing at least two ticks of an active DoT. This is an estimate, not guaranteed damage.")
            page.periodicNote = UI.Label(content, "", 12, -144, "GameFontDisableSmall", 580)
            UI.Section(content, "Paladin seal", -212)
            page.seal = Checkbox("SealEnabled", "Show active seal and missing-seal reminder", 4, -248, "seal", "enabled",
                "Paladins only. Shows your active seal. When it ends, its last icon turns grey with a reminder. Drag the icon separately in Move mode. A question mark means the game withheld its aura status.")
            page.sealInputs = {}
            local function ApplySeal()
                local values = {}
                for field, input in pairs(page.sealInputs) do
                    values[field] = tonumber(input:GetText())
                    if not values[field] then Notice("Enter valid seal dimensions and offsets.", true); return end
                end
                if not Addon:SetResourceDimensions("seal", values) then Notice("Icon size: 8-256. Offsets: -32768 to 32768.", true); return end
                for _, input in pairs(page.sealInputs) do input:ClearFocus() end
                Addon:RefreshResourceOptions(true)
                Notice("Seal layout saved.")
            end
            local function SealInput(field, x, y)
                local input = CreateFrame("EditBox", prefix .. "Seal" .. field, content, "InputBoxTemplate")
                input:SetSize(80, 24)
                input:SetPoint("TOPLEFT", x, y)
                input:SetAutoFocus(false)
                input:SetMaxLetters(12)
                input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                input:SetScript("OnEnterPressed", ApplySeal)
                UI.NumberArrows(input, 1, field == "size" and 8 or -32768, field == "size" and 256 or 32768,
                    function() return Addon:GetResourceSettings().seal[field] end,
                    function(value) return Addon:SetResourceDimensions("seal", { [field] = value }) end)
                page.sealInputs[field] = input
            end
            UI.Label(content, "Icon size", 12, -300)
            SealInput("size", 148, -294)
            UI.Label(content, "Horizontal", 312, -300)
            SealInput("x", 444, -294)
            UI.Label(content, "Vertical", 12, -342)
            SealInput("y", 148, -336)
            UI.Button(content, prefix .. "SealApply", "Apply seal layout", 432, -336, 144, ApplySeal)
            UI.Label(content, "Icon centres beside both bars. Offsets move it from there. Hold an arrow to fine-tune.", 12, -376, "GameFontDisableSmall", 580)
        else
            UI.Label(content, scope == "pet" and "Preview includes a sample pet. Power follows your pet's active resource."
                or "Preview includes sample party members, so you can set up while solo.", 12, 0, "GameFontDisableSmall", 580)
        end
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
