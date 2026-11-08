local _, Addon = ...
local page

function Addon:RefreshReadyOptions()
    if not page or not self.character then return end
    page.enabled:SetChecked(self.db.readyFlash)
    local slots = self:GetReadySlots()
    page.choose:SetEnabled(self.db.readyFlash and not InCombatLockdown())
    page.test:SetEnabled(self.db.readyFlash and #slots > 0)
    page.clear:SetEnabled(#slots > 0)
    page.heading:SetText(string.format("Selected slots (%d)", #slots))
    page.empty:SetShown(#slots == 0)
    page.content:SetHeight(math.max(360, 268 + #slots * 34 + 50))
    local status = "Selections are saved for this character."
    if self.cooldownRestricted then
        status = "WoW is restricting some cooldown data. Alerts resume when it is available."
    elseif InCombatLockdown() then
        status = "Choose new slots after combat. Existing flashes remain enabled."
    end
    self:SetPageStatus("cooldowns", status)
    for index, definition in ipairs(slots) do
        local row = page.rows[index]
        if not row then
            row = CreateFrame("Frame", nil, page.content)
            row:SetSize(580, 34)
            row:SetPoint("TOPLEFT", 12, -268 - (index - 1) * 34)
            row.label = self.OptionsUI.Label(row, "", 0, -7, "GameFontHighlight", 430)
            row.remove = self.OptionsUI.Button(row, nil, "Remove", 452, 0, 100, function()
                Addon:ToggleReadySlot(row.name)
            end)
            page.rows[index] = row
        end
        row.name = definition.name
        row.label:SetText(definition.label)
        row:Show()
    end
    for index = #slots + 1, #page.rows do page.rows[index]:Hide() end
end

function Addon:BuildReadyOptions()
    local UI = self.OptionsUI
    page = UI.Page("SmallerUIReadyPage", "Cooldown flashes", "Choose which action-bar slots glow when their skills become ready.", 360)
    page.rows = {}
    local content = page.content
    page.enabled = UI.Checkbox(content, "SmallerUIReadyEnabled", "Enable cooldown ready flashes", 4, 0, function(enabled)
        Addon:SetReadyFlashEnabled(enabled)
    end, "Selected slots pulse gold for one second after a real cooldown ends and the skill becomes usable. Global cooldowns do not trigger a flash.")
    UI.Section(content, "Action-bar slots", -52)
    UI.Label(content, "A gold pulse for one second when a skill is ready. Global cooldowns are ignored.", 12, -88, "GameFontDisableSmall", 580)
    page.choose = UI.Button(content, "SmallerUIChooseSlot", "Choose slot...", 12, -120, 160, function() Addon:BeginSlotPicker() end)
    page.test = UI.Button(content, "SmallerUITestFlashes", "Preview", 184, -120, 110, function()
        Addon:TestReadyFlashes()
        Addon:OptionsFeedback("Previewing your visible selected slots.", false, "cooldowns")
    end)
    page.clear = UI.Button(content, "SmallerUIClearSlots", "Clear all", 306, -120, 110, function() Addon:ClearReadySlots() end)
    UI.Tooltip(page.choose, "Click Choose slot, then click an action-bar button. The selection click does not cast the skill. Choose an existing slot again to remove it. Escape cancels.")
    UI.Label(content, "Click Choose slot, then click a button on your action bar. Escape cancels.", 12, -160, "GameFontDisableSmall", 580)
    page.heading = UI.Section(content, "Selected slots (0)", -206)
    UI.Label(content, "Action-bar slot", 12, -244, "GameFontNormalSmall")
    page.empty = UI.Label(content, "No slots selected. Enable ready flashes, then click Choose slot.", 12, -276, "GameFontDisableSmall", 580)
    page:SetScript("OnShow", function()
        Addon.currentOptionsPage = "cooldowns"
        Addon:OptionsFeedback("", false, "cooldowns")
        Addon:RefreshReadyOptions()
    end)
    self:RefreshReadyOptions()
    return page
end
