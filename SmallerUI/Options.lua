local _, Addon = ...
local pages, notices = {}, {}
local UI = {}
Addon.OptionsUI = UI

function UI.Label(parent, text, x, y, font, width)
    local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlight")
    label:SetPoint("TOPLEFT", x, y)
    label:SetJustifyH("LEFT")
    if width then label:SetWidth(width); label:SetWordWrap(true) end
    label:SetText(text)
    return label
end

function UI.Tooltip(widget, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(text, 1, 1, 1, 1, true)
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.Button(parent, name, text, x, y, width, callback)
    local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", callback)
    return button
end

function UI.Checkbox(parent, name, text, x, y, callback, tip)
    local checkbox = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
    checkbox:SetSize(26, 26)
    checkbox:SetPoint("TOPLEFT", x, y)
    checkbox.Text:SetText(text)
    checkbox:SetScript("OnClick", function(self) callback(self:GetChecked() == true) end)
    if text ~= "" then checkbox:SetHitRectInsets(0, -200, 0, 0) end
    if tip then UI.Tooltip(checkbox, tip) end
    return checkbox
end

function UI.Section(parent, text, y)
    local heading = UI.Label(parent, text, 8, y, "GameFontNormalLarge")
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.22)
    line:SetPoint("TOPLEFT", 8, y - 23)
    line:SetPoint("TOPRIGHT", -8, y - 23)
    line:SetHeight(1)
    return heading
end

function UI.Page(name, title, description, height)
    local page = CreateFrame("Frame", name)
    page:Hide()
    UI.Label(page, title, 16, -16, "GameFontNormalLarge")
    UI.Label(page, description, 16, -42, "GameFontHighlight", 600)
    page.status = UI.Label(page, "", 16, -62, "GameFontDisableSmall", 600)
    page.feedback = page.status
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -90)
    scroll:SetPoint("BOTTOMRIGHT", -32, 16)
    local content = CreateFrame("Frame", name .. "Content", scroll)
    content:SetSize(620, height)
    scroll:SetScrollChild(content)
    scroll:SetScript("OnSizeChanged", function(_, width) content:SetWidth(math.max(600, width)) end)
    page.scroll, page.content = scroll, content
    return page
end

function Addon:SetPageStatus(key, text)
    local page = pages[key]
    if not page then return end
    page.defaultStatus = text
    local notice = notices[key]
    page.status:SetText(notice and notice.text or text)
    if notice then
        page.status:SetTextColor(notice.error and 1 or 0.5, notice.error and 0.35 or 1, notice.error and 0.35 or 0.5)
    else
        page.status:SetTextColor(0.6, 0.6, 0.6)
    end
end

function Addon:OptionsFeedback(text, error, key)
    key = key or self.currentOptionsPage or "scaling"
    notices[key] = text ~= "" and { text = text, error = error } or nil
    local page = pages[key]
    if page then self:SetPageStatus(key, page.defaultStatus or "") end
end

local function ExactInput(parent, name, x, y, callback)
    local input = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    input:SetPoint("TOPLEFT", x, y)
    input:SetSize(80, 24)
    input:SetAutoFocus(false)
    input:SetMaxLetters(12)
    input:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    input:SetScript("OnEnterPressed", function() callback() end)
    return input
end

function Addon:GetVisibleElementSettings()
    local result = {}
    for _, element in ipairs(self.elements) do
        -- The minimap scaler is temporarily hidden. Saved values remain intact.
        if element.key ~= "minimap" then result[#result + 1] = element end
    end
    return result
end

function Addon:RefreshOptions(syncInput)
    local page = pages.scaling
    if not page then return end
    local status = string.format("Current scale: %.3f", UIParent:GetScale())
    if self:IsResetPending() then
        status = status .. ". Reset and reload queued after combat."
    elseif InCombatLockdown() then
        status = status .. ". Scale changes apply after combat."
    else
        status = status .. (self.db.enabled and ". Custom scale enabled." or ". Using the game's scale.")
    end
    self:SetPageStatus("scaling", status)
    page.showMinimap:SetChecked(self.db.showMinimap)
    if syncInput then
        local value = self.db.enabled and self.db.scale or UIParent:GetScale()
        page.global.syncing = true
        page.global.slider:SetValue(math.max(self.MIN_SCALE, math.min(self.MAX_SCALE, value)))
        page.global.input:SetText(string.format("%.3f", value))
        page.global.syncing = false
    end
    for key, row in pairs(page.rows) do
        row.keep:SetChecked(self.db.elements[key] ~= nil)
        if syncInput == true then row.input:SetText(string.format("%.2f", self.db.elements[key] or 1)) end
    end
    self:RefreshReadyOptions()
end

function Addon:CreateOptions()
    if self.settingsCategory then return true end
    if not self.db or InCombatLockdown() then return false end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then
        if C_AddOns and C_AddOns.LoadAddOn then C_AddOns.LoadAddOn("Blizzard_Settings") end
    end
    if not Settings or not Settings.RegisterCanvasLayoutCategory then return false end

    local page = UI.Page("SmallerUIOptions", "Smaller UI", "Adjust the interface and keep important elements easy to read.", 710)
    pages.scaling, self.options = page, page
    local content = page.content
    UI.Section(content, "UI scale", 0)
    UI.Label(content, "Lower values make the interface smaller.", 12, -42, "GameFontDisableSmall")
    local control = {}
    page.global = control
    local slider = CreateFrame("Slider", "SmallerUIGlobalSlider", content, "UISliderTemplateWithLabels")
    control.slider = slider
    slider:SetPoint("TOPLEFT", 14, -90)
    slider:SetSize(280, 16)
    slider:SetMinMaxValues(self.MIN_SCALE, self.MAX_SCALE)
    slider:SetValueStep(0.01)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("0.10")
    slider.High:SetText("1.50")
    slider.Text:SetText("Global UI scale")
    local function ApplyGlobal()
        if not Addon:SetScale(tonumber(control.input:GetText())) then
            Addon:OptionsFeedback("Enter a scale between 0.10 and 1.50.", true, "scaling")
            return
        end
        control.input:ClearFocus()
        Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat." or "UI scale saved.", false, "scaling")
    end
    control.input = ExactInput(content, "SmallerUIGlobalInput", 332, -86, ApplyGlobal)
    control.apply = UI.Button(content, "SmallerUIGlobalApply", "Apply", 432, -86, 90, ApplyGlobal)
    control.input:SetScript("OnTextChanged", function(self)
        if control.syncing then return end
        Addon:OptionsFeedback("", false, "scaling")
        local value = tonumber(self:GetText())
        if Addon:IsValidScale(value) then
            control.syncing = true
            slider:SetValue(value)
            control.syncing = false
        end
    end)
    slider:SetScript("OnValueChanged", function(_, value)
        if control.syncing then return end
        control.syncing = true
        control.input:SetText(string.format("%.3f", value))
        control.syncing = false
        Addon:OptionsFeedback("", false, "scaling")
    end)

    UI.Section(content, "Element sizes", -168)
    UI.Label(content, "Keep an element's original size, or enter a custom multiplier and click Apply.", 12, -208, "GameFontDisableSmall", 580)
    UI.Label(content, "Element", 12, -248, "GameFontNormalSmall")
    UI.Label(content, "Keep size", 236, -248, "GameFontNormalSmall")
    UI.Label(content, "Size", 332, -248, "GameFontNormalSmall")
    page.rows = {}
    for index, element in ipairs(self:GetVisibleElementSettings()) do
        local key, y = element.key, -276 - (index - 1) * 38
        local row = {}
        page.rows[key] = row
        UI.Label(content, element.label, 12, y - 7)
        row.keep = UI.Checkbox(content, "SmallerUIKeep_" .. key, "", 246, y - 1, function(enabled)
            Addon:SetElementIndependent(key, enabled)
            row.input:SetText("1.00")
            Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat."
                or (enabled and element.label .. ": original size preserved." or element.label .. ": follows the global scale."), false, "scaling")
        end, "Check to keep the original size. Uncheck to follow the global UI scale.")
        local function ApplyElement()
            if not Addon:SetElementScale(key, tonumber(row.input:GetText())) then
                Addon:OptionsFeedback("Enter an element size between 0.25 and 2.00.", true, "scaling")
                return
            end
            row.input:ClearFocus()
            Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat."
                or element.label .. ": size saved.", false, "scaling")
        end
        row.input = ExactInput(content, "SmallerUIElementInput_" .. key, 332, y, ApplyElement)
        row.apply = UI.Button(content, "SmallerUIElementApply_" .. key, "Apply", 432, y, 90, ApplyElement)
        UI.Tooltip(row.input, "1.00 = original size. 0.75 = 75%. 1.25 = 125%. Applying a value enables Keep size for this element.")
    end
    UI.Label(content, "1.00 = original size. 0.75 = 75%. 1.25 = 125%.", 12, -480, "GameFontDisableSmall")
    UI.Section(content, "Access and recovery", -534)
    page.showMinimap = UI.Checkbox(content, "SmallerUIShowMinimap", "Show minimap button", 4, -574, function(enabled)
        Addon.db.showMinimap = enabled
        Addon:UpdateMinimap()
    end, "Click the minimap button to open this page. Drag it around the minimap to reposition it.")
    UI.Button(content, "SmallerUIResetButton", "Restore game scale", 12, -622, 190, function() Addon:Reset() end)
    UI.Label(content, "/sui reset also restores the game's scale and reloads the UI.", 12, -658, "GameFontDisableSmall")
    page:SetScript("OnShow", function()
        Addon.currentOptionsPage = "scaling"
        Addon:OptionsFeedback("", false, "scaling")
        Addon:RefreshOptions(true)
    end)
    page:SetScript("OnHide", function()
        control.input:ClearFocus()
        for _, row in pairs(page.rows) do row.input:ClearFocus() end
    end)
    local ready = self:BuildReadyOptions()
    pages.cooldowns = ready
    self.settingsCategory = Settings.RegisterCanvasLayoutCategory(page, "Smaller UI")
    self.readySettingsCategory = Settings.RegisterCanvasLayoutSubcategory(self.settingsCategory, ready, "Cooldown flashes")
    Settings.RegisterAddOnCategory(self.settingsCategory)
    self:RefreshOptions(true)
    return true
end

function Addon:ShowOptions(key)
    key = key == "cooldowns" and "cooldowns" or "scaling"
    if InCombatLockdown() then
        self.pendingOptionsPage = key
        self:Print("Settings will open after combat.")
        return false
    end
    if not self:CreateOptions() then
        self:Print("WoW's addon settings are not available yet. Try /sui again after loading.")
        return false
    end
    local category = key == "cooldowns" and self.readySettingsCategory or self.settingsCategory
    self.currentOptionsPage = key
    Settings.OpenToCategory(category:GetID())
    return true
end

function Addon:SelectOptionsPage(key) return self:ShowOptions(key) end

function Addon:OpenPendingOptions()
    if self.pendingOptionsPage and not InCombatLockdown() then
        local key = self.pendingOptionsPage
        self.pendingOptionsPage = nil
        self:ShowOptions(key)
    end
end

function Addon:HideOptions()
    if InCombatLockdown() then return false end
    if SettingsPanel and SettingsPanel:IsShown() then
        if SettingsPanel:HasUnappliedSettings() then
            self:OptionsFeedback("Apply or discard your pending WoW settings, then choose a slot.", true, "cooldowns")
            return false
        end
        SettingsPanel:Close(true)
        return not SettingsPanel:IsShown()
    end
    return true
end
