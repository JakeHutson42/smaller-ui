local _, Addon = ...
local pages, notices, window = {}, {}, nil
local UI = {}
Addon.OptionsUI = UI
local WHITE = "Interface\\Buttons\\WHITE8X8"
local gold = { 0.83, 0.66, 0.35, 1 }
local muted = { 0.34, 0.33, 0.30, 1 }
local navigation = {
    { "scaling", "Interface", "INV_Misc_Gear_01" },
    { "resources", "Personal bars", "INV_Potion_54" },
    { "party", "Party bars", "INV_Misc_GroupLooking" },
    { "pet", "Pet bars", "Ability_Hunter_BeastCall" },
    { "swing", "Swing timer", "INV_Sword_04" },
}

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
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.NumberArrows(input, step, minimum, maximum, savedValue, apply)
    local function Adjust(direction)
        local value = tonumber(input:GetText())
        if not value or value ~= value or math.abs(value) == math.huge then value = savedValue() end
        value = math.max(minimum, math.min(maximum, math.floor((value + direction * step) * 100 + 0.5) / 100))
        if value == savedValue() then input:SetText(string.format("%.2f", value)); return end
        if apply(value) ~= false then input:SetText(string.format("%.2f", value)) end
    end
    local function Arrow(suffix, direction, y, texture)
        local button = CreateFrame("Button", input:GetName() .. suffix, input)
        button:SetSize(18, 12)
        button:SetPoint("TOPLEFT", input:GetWidth() + 2, y)
        button:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Down")
        button:SetHighlightTexture("Interface\\Buttons\\UI-ScrollBar-Scroll" .. texture .. "Button-Highlight")
        button.stepper, button.stepDirection = true, direction
        local function Stop(self) self:SetScript("OnUpdate", nil) end
        button:SetScript("OnMouseDown", function(self, mouse)
            if mouse ~= "LeftButton" then return end
            self.mouseStepped = true
            Adjust(direction)
            local nextStep = GetTime() + 0.35
            self:SetScript("OnUpdate", function(current)
                if not IsMouseButtonDown("LeftButton") then Stop(current); return end
                if GetTime() >= nextStep then Adjust(direction); nextStep = GetTime() + 0.07 end
            end)
        end)
        button:SetScript("OnMouseUp", Stop)
        button:SetScript("OnHide", function(self) Stop(self); self.mouseStepped = nil end)
        button:SetScript("OnClick", function(self, mouse)
            if mouse == "LeftButton" and not self.mouseStepped then Adjust(direction) end
            self.mouseStepped = nil
        end)
        UI.Tooltip(button, "Click to adjust. Hold to keep adjusting.")
        return button
    end
    input.up = Arrow("Up", 1, 0, "Up")
    input.down = Arrow("Down", -1, -12, "Down")
end

function UI.Backdrop(frame, color, border)
    frame:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    frame:SetBackdropColor(unpack(color))
    frame:SetBackdropBorderColor(unpack(border or muted))
end

function UI.Button(parent, name, text, x, y, width, callback)
    local button = CreateFrame("Button", name, parent, "BackdropTemplate")
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(width, 26)
    UI.Backdrop(button, { 0.11, 0.15, 0.19, 1 })
    local textLabel = button:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    textLabel:SetPoint("CENTER")
    button.label = textLabel
    button:SetFontString(textLabel)
    button:SetText(text)
    button:SetHighlightTexture(WHITE, "ADD")
    button:GetHighlightTexture():SetVertexColor(0.24, 0.19, 0.11, 0.35)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnClick", callback)
    return button
end

function UI.Select(parent, name, x, y, width, entries, get, set, initializeRow)
    local dropdown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("TOPLEFT", x, y)
    dropdown:SetSize(width, 26)
    dropdown:SetupMenu(function(_, root)
        local choices = type(entries) == "function" and entries() or entries
        for _, entry in ipairs(choices) do
            local row = root:CreateRadio(entry[2], function(value) return get() == value end, set, entry[1])
            if initializeRow then
                row:AddInitializer(function(button) return initializeRow(button, entry) end)
            end
        end
    end)
    return dropdown
end

function UI.Switch(parent, name, text, x, y, callback, tip)
    local button = CreateFrame("Button", name, parent)
    button:SetPoint("TOPLEFT", x, y)
    button:SetSize(text == "" and 42 or 292, 28)
    local track = CreateFrame("Frame", nil, button, "BackdropTemplate")
    track:SetSize(36, 18)
    track:SetPoint("LEFT", 2, 0)
    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetSize(13, 12)
    local label = UI.Label(button, text, 48, -7)
    label:SetWordWrap(false)
    function button:SetChecked(enabled)
        self.checked = enabled == true
        UI.Backdrop(track, self.checked and { 0.14, 0.33, 0.25, 1 } or { 0.06, 0.08, 0.11, 1 }, self.checked and gold or muted)
        thumb:ClearAllPoints()
        thumb:SetPoint(self.checked and "RIGHT" or "LEFT", self.checked and -3 or 3, 0)
        thumb:SetColorTexture(unpack(self.checked and gold or muted))
    end
    function button:GetChecked() return self.checked end
    button:SetChecked(false)
    button:SetScript("OnEnable", function(self) self:SetAlpha(1) end)
    button:SetScript("OnDisable", function(self) self:SetAlpha(0.45) end)
    button:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        callback(self:GetChecked())
    end)
    if tip then UI.Tooltip(button, tip) end
    return button
end

function UI.Section(parent, text, y)
    local heading = UI.Label(parent, text, 12, y, "GameFontNormal")
    heading:SetTextColor(unpack(gold))
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(0.83, 0.66, 0.35, 0.23)
    line:SetPoint("TOPLEFT", 12, y - 21)
    line:SetPoint("TOPRIGHT", -12, y - 21)
    line:SetHeight(1)
    return heading
end

function UI.Page(name, title, height)
    local page = CreateFrame("Frame", name, window)
    page:SetPoint("TOPLEFT", 182, -70)
    page:SetPoint("BOTTOMRIGHT", -18, 48)
    page:Hide()
    page.title = UI.Label(page, title, 12, -4, "GameFontNormalLarge")
    page.title:SetTextColor(unpack(gold))
    local scroll = CreateFrame("ScrollFrame", name .. "Scroll", page, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -44)
    scroll:SetPoint("BOTTOMRIGHT", -23, 0)
    local content = CreateFrame("Frame", name .. "Content", scroll)
    content:SetSize(620, height)
    scroll:SetScrollChild(content)
    page.scroll, page.content = scroll, content
    return page
end

function UI.Tabs(page, entries)
    page.tab = entries[1][1]
    for index, entry in ipairs(entries) do
        entry.button = UI.Button(page, nil, entry[2], 218 + (index - 1) * 122, 0, 114,
            function() page:SelectTab(entry[1]) end)
    end
    function page:SelectTab(key)
        self.tab = key
        for _, entry in ipairs(entries) do
            entry[3]:SetShown(entry[1] == key)
            entry.button:SetBackdropBorderColor(unpack(entry[1] == key and gold or muted))
            if entry[1] == key then self.content:SetHeight(entry[3]:GetHeight()) end
        end
        self.scroll:SetVerticalScroll(0)
        Addon:OptionsFeedback("")
    end
    page:SelectTab(page.tab)
end

function Addon:SetPageStatus(key, text)
    local page = pages[key]
    if not page then return end
    page.defaultStatus = text
    if not window or self.currentOptionsPage ~= key then return end
    local notice = notices[key]
    window.status:SetText(notice and notice.text or text)
    window.status:SetTextColor(unpack(notice and notice.error and { 1, 0.54, 0.45, 1 } or gold))
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
    self:RefreshResourceOptions(syncInput == true)
    self:RefreshSwingOptions()
end

local function BuildScalingOptions(self)
    local page = UI.Page("SmallerUIOptions", "Interface", 502)
    local content = page.content
    UI.Section(content, "UI scale", 0)
    local control = {}
    page.global = control
    local slider = CreateFrame("Slider", "SmallerUIGlobalSlider", content, "UISliderTemplateWithLabels")
    control.slider = slider
    slider:SetPoint("TOPLEFT", 14, -66)
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
    control.input = ExactInput(content, "SmallerUIGlobalInput", 332, -62, ApplyGlobal)
    control.apply = UI.Button(content, "SmallerUIGlobalApply", "Apply", 432, -62, 90, ApplyGlobal)
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

    UI.Section(content, "Element sizes", -118)
    UI.Label(content, "Element", 12, -158, "GameFontNormalSmall")
    UI.Label(content, "Independent", 228, -158, "GameFontNormalSmall")
    UI.Label(content, "Size", 332, -158, "GameFontNormalSmall")
    page.rows = {}
    for index, element in ipairs(self.elements) do
        local key, y = element.key, -183 - (index - 1) * 38
        local row = {}
        page.rows[key] = row
        UI.Label(content, element.label, 12, y - 7)
        row.keep = UI.Switch(content, "SmallerUIKeep_" .. key, "", 246, y - 1, function(enabled)
            Addon:SetElementIndependent(key, enabled)
            row.input:SetText("1.00")
            Addon:OptionsFeedback(InCombatLockdown() and "Saved. Scale changes apply after combat."
                or (enabled and element.label .. ": original size preserved." or element.label .. ": follows the global scale."), false, "scaling")
        end, "Keep the element at an independent scale.")
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
        UI.Tooltip(row.input, "1.00 = original size. 0.75 = 75%. 1.25 = 125%. Applying a value turns on Independent for this element.")
    end
    UI.Section(content, "General", -420)
    page.showMinimap = UI.Switch(content, "SmallerUIShowMinimap", "Show minimap button", 12, -455, function(enabled)
        Addon.db.showMinimap = enabled
        Addon:UpdateMinimap()
    end, "Click the minimap button to open this page. Drag it around the minimap to reposition it.")
    UI.Button(content, "SmallerUIResetButton", "Restore game scale", 338, -455, 190, function() Addon:Reset() end)
    page:SetScript("OnShow", function()
        Addon.currentOptionsPage = "scaling"
        Addon:OptionsFeedback("", false, "scaling")
        Addon:RefreshOptions(true)
    end)
    page:SetScript("OnHide", function()
        control.input:ClearFocus()
        for _, row in pairs(page.rows) do row.input:ClearFocus() end
    end)
    return page
end

local function FitWindow()
    local width, height = UIParent:GetSize()
    local scale = UIParent:GetEffectiveScale()
    window:SetScale(math.max(0.1, math.min(1, (width * scale - 24) / 848, (height * scale - 24) / 650)))
end

function Addon:CreateOptions()
    if window then return true end
    if not self.db then return false end
    window = CreateFrame("Frame", "SmallerUISettings", UIParent, "BackdropTemplate")
    window:Hide()
    window:SetSize(848, 650)
    window:SetPoint("CENTER")
    window:SetIgnoreParentScale(true)
    window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true)
    window:SetMovable(true)
    window:EnableMouse(true)
    UI.Backdrop(window, { 0.048, 0.065, 0.085, 0.99 }, gold)
    FitWindow()

    local header = CreateFrame("Frame", nil, window)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(54)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() window:StartMoving() end)
    header:SetScript("OnDragStop", function() window:StopMovingOrSizing() end)
    local top = header:CreateTexture(nil, "BACKGROUND")
    top:SetAllPoints()
    top:SetColorTexture(0.09, 0.13, 0.18, 1)
    local emblem = header:CreateTexture(nil, "ARTWORK")
    emblem:SetSize(30, 30)
    emblem:SetPoint("LEFT", 18, 0)
    emblem:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    emblem:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    UI.Label(header, self.displayName, 61, -16, "GameFontNormalLarge"):SetTextColor(unpack(gold))
    local close = UI.Button(header, nil, "X", 799, -14, 28, function() Addon:HideOptions() end)
    UI.Tooltip(close, "Close settings")

    local rail = window:CreateTexture(nil, "BACKGROUND")
    rail:SetPoint("TOPLEFT", 1, -55)
    rail:SetPoint("BOTTOMLEFT", 1, 43)
    rail:SetWidth(164)
    rail:SetColorTexture(0.067, 0.091, 0.117, 1)
    UI.Button(window, "SmallerUISettingsMove", "Move Mode", 16, -556, 134, function() Addon:BeginResourceEdit() end)
    window.status = UI.Label(window, "", 18, -624, "GameFontHighlightSmall", 790)
    window.entries = {}
    for index, entry in ipairs(navigation) do
        local key = entry[1]
        local item = UI.Button(window, nil, entry[2], 12, -72 - (index - 1) * 44, 142,
            function() Addon:ShowOptions(key) end)
        item:SetHeight(36)
        item.label:ClearAllPoints()
        item.label:SetPoint("LEFT", 35, 0)
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(17, 17)
        icon:SetPoint("LEFT", 9, 0)
        icon:SetTexture("Interface\\Icons\\" .. entry[3])
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        window.entries[key] = item
    end
    window:SetScript("OnHide", function()
        window:StopMovingOrSizing()
        local page = pages[Addon.currentOptionsPage]
        if page then page:Hide() end
    end)
    table.insert(UISpecialFrames, window:GetName())
    pages.scaling = BuildScalingOptions(self)
    self.options = pages.scaling
    pages.resources, pages.party, pages.pet = self:BuildResourceOptions()
    pages.swing = self:BuildSwingOptions()
    self:RefreshOptions(true)
    return true
end

function Addon:ShowOptions(key)
    key = key or self.currentOptionsPage or "scaling"
    if self:IsEditingResources() then
        self:FinishResourceEdit(true)
        return true
    end
    if InCombatLockdown() then
        self.pendingOptionsPage = key
        self:Print("Settings will open after combat.")
        return false
    end
    if not self:CreateOptions() then return false end
    if not pages[key] then key = "scaling" end
    self.currentOptionsPage = key
    for name, page in pairs(pages) do
        if name ~= key then page:Hide() end
        window.entries[name]:SetBackdropBorderColor(unpack(name == key and gold or muted))
        window.entries[name]:SetBackdropColor(name == key and 0.18 or 0.10, name == key and 0.16 or 0.13, 0.16, 1)
    end
    FitWindow()
    window:Show()
    pages[key]:Show()
    self:SetPageStatus(key, pages[key].defaultStatus or "")
    return true
end

function Addon:OpenPendingOptions()
    if self.pendingOptionsPage and not InCombatLockdown() then
        local key = self.pendingOptionsPage
        self.pendingOptionsPage = nil
        self:ShowOptions(key)
    end
end

function Addon:HideOptions()
    if window then window:Hide() end
    return true
end
