local passed = 0

local function check(condition, message)
    assert(condition, message)
    passed = passed + 1
end

local function boot(saved, characterSaved)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local messages = {}
    local state = { scale = 0.75, combat = false, writes = 0, reloads = 0, elementWrites = 0,
        now = 100, widgets = {}, objects = {}, cooldowns = {}, charges = {}, actions = {}, usable = {} }
    local frame
    local function event(name, ...)
        for _, widget in ipairs(state.widgets) do
            if widget.events[name] then widget.scripts.OnEvent(widget, name, ...) end
        end
    end
    local function tick(delta)
        delta = delta or 0.016
        state.now = state.now + delta
        for _, widget in ipairs(state.widgets) do
            if widget.scripts.OnUpdate and widget:IsVisible() then widget.scripts.OnUpdate(widget, delta) end
        end
    end
    local function Widget(name, parent)
        local widget = { scripts = {}, events = {}, parent = parent, scale = 1, shown = true, text = "" }
        widget.uid, widget._name, widget._points = #state.objects + 1, name, {}
        state.objects[#state.objects + 1] = widget
        if name then env[name] = widget end
        function widget:RegisterEvent(value) self.events[value] = true end
        function widget:SetScript(value, callback) self.scripts[value] = callback end
        function widget:GetParent() return self.parent end
        function widget:GetScale() return name == "UIParent" and state.scale or self.scale end
        function widget:GetEffectiveScale()
            if self.ignore or not self.parent then return self:GetScale() end
            return self:GetScale() * self.parent:GetEffectiveScale()
        end
        function widget:SetScale(value)
            if name == "UIParent" or self.managed then assert(not state.combat, "Scale changed in combat") end
            if name == "UIParent" then
                state.scale = value; state.writes = state.writes + 1; event("UI_SCALE_CHANGED")
            else
                self.scale = value
                if self.managed then state.elementWrites = state.elementWrites + 1 end
            end
        end
        function widget:SetIgnoreParentScale(value) self.ignore = value end
        function widget:IsIgnoringParentScale() return self.ignore or false end
        function widget:IsForbidden() return self.forbidden or false end
        function widget:SetText(text)
            self.text = text
            if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
        end
        function widget:GetText() return self.text end
        function widget:SetChecked(value) self.checked = value end
        function widget:GetChecked() return self.checked end
        function widget:SetMinMaxValues(low, high) self.low, self.high = low, high end
        function widget:SetValue(value)
            value = math.max(self.low, math.min(self.high, value))
            if self.value == value then return end
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end
        function widget:GetValue() return self.value end
        function widget:Show()
            local wasShown = self.shown
            self.shown = true
            if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
        end
        function widget:Hide()
            local wasShown = self.shown
            self.shown = false
            if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
        end
        function widget:IsShown() return self.shown end
        function widget:SetShown(value) if value then self:Show() else self:Hide() end end
        function widget:GetFrameLevel() return 1 end
        function widget:GetName() return name end
        function widget:GetAttribute(attribute) return self[attribute] end
        function widget:SetSize(width, height) self.width, self.height = width, height end
        function widget:SetWidth(width) self.width = width end
        function widget:SetHeight(height) self.height = height end
        function widget:GetWidth() return self.width or 36 end
        function widget:GetHeight() return self.height or 36 end
        function widget:GetRect() return self.left or 0, self.bottom or 0, self:GetWidth(), self:GetHeight() end
        function widget:GetCenter() return (self.left or 0) + self:GetWidth() / 2, (self.bottom or 0) + self:GetHeight() / 2 end
        function widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function widget:SetEnabled(value) self.enabled = value end
        function widget:SetAlpha(value) self.alpha = value end
        function widget:GetAlpha() return self.alpha or 1 end
        function widget:CreateFontString(_, _, font)
            local label = Widget(nil, self)
            label.kind, label.font = "FontString", font
            return label
        end
        function widget:CreateTexture()
            local texture = Widget(nil, self)
            texture.kind = "Texture"
            return texture
        end
        function widget:GetThumbTexture() return Widget(nil, self) end
        for _, method in ipairs({ "SetPoint", "SetJustifyH",
            "SetTextColor", "SetFrameStrata", "SetClampedToScreen", "SetMovable", "EnableMouse",
            "RegisterForDrag", "StartMoving", "StopMovingOrSizing", "SetBackdrop", "SetBackdropColor",
            "SetBackdropBorderColor", "SetColorTexture", "SetOrientation", "SetValueStep",
            "SetObeyStepOnDrag", "SetThumbTexture", "SetAutoFocus", "SetMaxLetters", "ClearFocus",
            "SetHitRectInsets", "SetFrameLevel", "SetTexture", "RegisterForClicks", "SetAllPoints",
            "SetBlendMode", "SetVertexColor", "SetHighlightTexture", "ClearAllPoints", "SetScrollChild",
            "SetOwner", "AddLine", "SetWordWrap" }) do
            widget[method] = function() end
        end
        function widget:SetPoint(...) self._points[#self._points + 1] = { ... } end
        function widget:ClearAllPoints() self._points = {} end
        function widget:SetColorTexture(...) self.color = { ... } end
        function widget:SetTextColor(...) self.textColor = { ... } end
        return widget
    end
    function state.Click(widget, mouseButton)
        if widget.enabled == false then return end
        if widget.kind == "CheckButton" then widget.checked = not widget.checked end
        widget.scripts.OnClick(widget, mouseButton or "LeftButton")
    end
    function state.MakeElement(name, parent, scale, ignore)
        local widget = Widget(name, parent or env.UIParent)
        widget.scale, widget.ignore, widget.managed = scale or 1, ignore, true
        return widget
    end
    env.SmallerUIDB = saved
    env.SmallerUICharDB = characterSaved
    env.CreateFrame = function(kind, name, parent, template)
        local widget = Widget(name, parent)
        widget.kind, widget.template = kind, template
        if template == "UISliderTemplateWithLabels" then
            widget.Text, widget.Low, widget.High = Widget(nil, widget), Widget(nil, widget), Widget(nil, widget)
        elseif template == "UICheckButtonTemplate" then
            widget.Text = Widget(nil, widget)
        end
        state.widgets[#state.widgets + 1] = widget
        if not frame then frame = widget end
        return widget
    end
    env.UISpecialFrames = {}
    env.UIParent = Widget("UIParent")
    env.SettingsPanel = Widget("SettingsPanel")
    env.SettingsPanel:Hide()
    state.categories = {}
    local function Category(panel, name, parent)
        local category = { panel = panel, name = name, parent = parent, id = 100 + #state.categories }
        function category:GetID() return self.id end
        state.categories[#state.categories + 1] = category
        return category
    end
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name) return Category(panel, name) end,
        RegisterCanvasLayoutSubcategory = function(parent, panel, name) return Category(panel, name, parent) end,
        RegisterAddOnCategory = function(category) state.registeredAddon = category end,
        OpenToCategory = function(id)
            assert(not state.combat, "Native settings opened in combat")
            local category
            for _, candidate in ipairs(state.categories) do if candidate.id == id then category = candidate end end
            assert(category, "Settings.OpenToCategory requires a registered numeric ID")
            if state.currentCategory and state.currentCategory ~= category then state.currentCategory.panel:Hide() end
            state.currentCategory = category
            category.panel.parent = env.SettingsPanel
            env.SettingsPanel:Show()
            category.panel:Show()
        end,
    }
    function env.SettingsPanel:HasUnappliedSettings() return state.pendingWoWSettings or false end
    function env.SettingsPanel:Close(skipTransition)
        assert(not state.combat, "Native settings closed in combat")
        state.skippedGameMenuTransition = skipTransition
        self:Hide()
    end
    env.SettingsPanel:SetScript("OnHide", function()
        if state.currentCategory then state.currentCategory.panel:Hide() end
    end)
    state.MakeElement("MinimapCluster")
    state.MakeElement("Minimap", env.MinimapCluster)
    env.Minimap:SetSize(140, 140)
    state.MakeElement("ChatFrame1")
    state.MakeElement("PlayerFrame")
    state.MakeElement("TargetFrame")
    state.MakeElement("MainMenuBar", nil, 0.9)
    state.MakeElement("MultiBarBottomLeft", env.MainMenuBar, 0.8)
    function state.MakeAction(name, action)
        local button = state.MakeElement(name, env.MainMenuBar)
        button.action = action
        state.actions[action] = { kind = "spell", id = 1000 + action }
        return button
    end
    state.MakeAction("ActionButton1", 1)
    state.MakeAction("MultiBarBottomLeftButton2", 62)
    env.GetTime = function() return state.now end
    env.GetCursorPosition = function() return 100, 100 end
    env.GetActionInfo = function(action)
        local info = state.actions[action]
        if info then return info.kind, info.id end
    end
    env.C_ActionBar = {
        GetActionCooldown = function(action)
            return state.cooldowns[action] or { startTime = 0, duration = 0, isEnabled = true }
        end,
        GetActionCharges = function(action) return state.charges[action] end,
        IsUsableAction = function(action)
            local value = state.usable[action]
            if value == nil then return true end
            return value
        end,
    }
    env.C_Spell = { GetSpellCooldown = function() return state.gcd or { startTime = 0, duration = 0 } end }
    env.issecretvalue = function(value) return type(value) == "table" and value.secret == true end
    env.GameTooltip = Widget(nil)
    env.InCombatLockdown = function() return state.combat end
    env.ReloadUI = function()
        assert(not state.combat, "ReloadUI called in combat")
        state.reloads = state.reloads + 1
    end
    env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, text) messages[#messages + 1] = text end }
    env.SlashCmdList = {}
    local namespace = {}
    for _, source in ipairs(addon_sources) do
        local addon = assert(loadstring(source))
        setfenv(addon, env)("SmallerUI", namespace)
    end
    state.addon = namespace
    event("ADDON_LOADED", "AnotherAddon")
    event("ADDON_LOADED", "SmallerUI")
    event("PLAYER_LOGIN")
    tick()
    return env, state, event, tick, env.SlashCmdList.SMALLERUI
end

local env, state, event, tick, command = boot(nil)
check(state.writes == 0 and not env.SmallerUIDB.enabled, "First install must preserve scale")
command("  0.50  ")
check(state.scale == 0.50 and env.SmallerUIDB.enabled, "Explicit scale applies and enables")
tick(); tick()
check(state.writes == 1, "Own scale events must settle without looping")

for _, invalid in ipairs({ "0", "-1", "0.09", "1.51", "1e999", "nan", "oops" }) do command(invalid) end
check(state.scale == 0.50 and env.SmallerUIDB.scale == 0.50, "Invalid values must preserve the saved scale")
command("0.10"); command("smaller")
check(state.scale == 0.10, "Lower boundary clamps")
command("1.50"); command("larger")
check(state.scale == 1.50, "Upper boundary clamps")
command("0.50"); command("smaller")
check(math.abs(state.scale - 0.45) < 0.000001, "Smaller adjusts by 0.05")
command("LARGER")
check(math.abs(state.scale - 0.50) < 0.000001, "Larger and case handling work")

state.combat = true
local writes = state.writes
command("0.40"); command("0.35"); tick()
check(state.writes == writes and env.SmallerUIDB.scale == 0.35, "Combat queues the latest choice")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick()
check(state.scale == 0.35, "Queued scale applies after combat")

for _, name in ipairs({ "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED" }) do
    state.scale = 0.75
    event(name); tick(); tick()
    check(state.scale == 0.35, name .. " must restore the override")
end

local persisted = env.SmallerUIDB
local _, loaded = boot(persisted)
check(loaded.scale == 0.35, "Saved setting reapplies on login")

state.combat = true
command("reset"); tick()
check(not env.SmallerUIDB.enabled and state.reloads == 0, "Reset defers reload during combat")
command("0.60")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick()
check(state.scale == 0.60 and state.reloads == 0, "New scale cancels pending reset")

state.combat = true
command("reset")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick()
check(state.reloads == 1 and not env.SmallerUIDB.enabled, "Deferred reset reloads once")
local _, resetState = boot(env.SmallerUIDB)
check(resetState.writes == 0, "Disabled override stays off after reload")

local _, immediate, _, _, reset = boot({ scale = 0.5, enabled = true })
reset("reset")
check(immediate.reloads == 1, "Out-of-combat reset reloads immediately")

for _, corrupt in ipairs({ false, "bad", { scale = 0 }, { scale = 0/0, enabled = true }, { scale = math.huge, enabled = true } }) do
    local recovered, clean = boot(corrupt)
    check(clean.writes == 0 and not recovered.SmallerUIDB.enabled, "Corrupt saved data disables the override")
end
local strange, clean = boot({ scale = 0.5, enabled = "yes" })
check(clean.writes == 0 and not strange.SmallerUIDB.enabled, "Only boolean true enables scaling")

local function near(actual, expected, message)
    check(math.abs(actual - expected) < 0.00001, message .. ": " .. tostring(actual))
end

env, state, event, tick, command = boot(nil)
check(#state.categories == 2 and state.registeredAddon == state.addon.settingsCategory
    and not env.SettingsPanel:IsShown(), "Native AddOns entries register at login without opening the menu")
command("")
local panel = env.SmallerUIOptions
check(panel and panel:IsShown(), "/sui opens settings")
check(env.SettingsPanel:IsShown() and state.currentCategory == state.addon.settingsCategory,
    "/sui opens the registered native AddOns category")
check(#env.UISpecialFrames == 0, "Addon does not register a separate settings window")
command("")
check(env.SmallerUIOptions == panel and #state.categories == 2, "Opening settings reuses the same registered pages")
check(state.registeredAddon == state.addon.settingsCategory
    and state.addon.readySettingsCategory.parent == state.addon.settingsCategory,
    "Cooldown settings are a native subcategory under Smaller UI")
check(env.SmallerUIGlobalSlider.template == "UISliderTemplateWithLabels", "Global slider uses Familiar Names' native labelled template")
check(not env.SmallerUIKeep_minimap and not env.SmallerUIElementInput_minimap
    and #state.addon:GetVisibleElementSettings() == 5, "Minimap scaling controls are hidden")
env.SmallerUIElementInput_chat:SetText("1.25")
env.SmallerUIGlobalSlider:SetValue(0.4)
check(state.writes == 0 and not env.SmallerUIDB.enabled, "Slider edits a draft until Apply")
state.Click(env.SmallerUIGlobalApply)
near(state.scale, 0.4, "Global Apply uses slider draft")
check(state.currentCategory == state.addon.settingsCategory, "Applying scale keeps the native settings page open")
check(env.SmallerUIElementInput_chat:GetText() == "1.25", "Applying global scale preserves unfinished element edits")
env.SmallerUIGlobalInput:SetText("0.3333")
env.SmallerUIGlobalInput.scripts.OnEnterPressed()
near(state.scale, 0.3333, "Exact entry supports finer values than slider step")
env.SmallerUIGlobalInput:SetText("bad")
state.Click(env.SmallerUIGlobalApply)
near(state.scale, 0.3333, "Invalid UI entry keeps the previous scale")
check(panel.feedback:GetText():find("between"), "Invalid entry shows inline feedback")

state.addon:SetElementIndependent("minimap", true)
near(env.MinimapCluster:GetEffectiveScale(), 0.75, "Hidden minimap setting remains compatible with existing saved values")
command("0.20")
near(env.MinimapCluster:GetEffectiveScale(), 0.75, "Independent minimap survives further global changes")
near(env.ChatFrame1:GetEffectiveScale(), 0.20, "Unchecked chat follows global scale")
state.addon:SetElementScale("minimap", 1.2)
near(env.MinimapCluster:GetEffectiveScale(), 0.9, "Selected minimap can use 120% of original size")
state.addon:SetElementIndependent("minimap", false)
near(env.MinimapCluster:GetEffectiveScale(), 0.20, "Unchecking restores global inheritance")
env.SmallerUIElementInput_chat:SetText("0.80")
state.Click(env.SmallerUIElementApply_chat)
near(env.ChatFrame1:GetEffectiveScale(), 0.6, "Individual chat scale uses original size as reference")
check(env.SmallerUIKeep_chat:GetChecked(), "Applying an inline element size enables its Keep size checkbox")
near(env.MinimapCluster:GetEffectiveScale(), 0.20, "Editing chat leaves other elements unchanged")
env.SmallerUIElementInput_chat:SetText("2.1")
state.Click(env.SmallerUIElementApply_chat)
near(env.ChatFrame1:GetEffectiveScale(), 0.6, "Out-of-range element scale is rejected")

state.Click(env.SmallerUIKeep_actionbars)
near(env.MainMenuBar:GetEffectiveScale(), 0.675, "Action bar root preserves its original scale")
near(env.MultiBarBottomLeft:GetEffectiveScale(), 0.54, "Nested action bars are not scaled twice")
check(env.MultiBarBottomLeft:GetScale() == 0.8, "Nested action bar's local scale stays untouched")

state.addon:SetElementScale("quests", 1.4)
check(not state.addon:ElementAvailable("quests"), "Missing elements can have saved settings")
local tracker = state.MakeElement("QuestWatchFrame", nil, 0.8)
event("ADDON_LOADED", "Blizzard_QuestTracker"); tick()
near(tracker:GetEffectiveScale(), 0.75 * 0.8 * 1.4, "Late-loaded frame uses the original root scale")
local secondChat = state.MakeElement("ChatFrame2", nil, 0.9)
event("UPDATE_CHAT_WINDOWS"); tick()
near(secondChat:GetEffectiveScale(), 0.75 * 0.9 * 0.8, "New chat windows receive the saved chat setting")

local savedElements = env.SmallerUIDB
local reloadEnv = boot(savedElements)
near(reloadEnv.ChatFrame1:GetEffectiveScale(), 0.6, "Element scale persists across login")

state.combat = true
local elementWrites = state.elementWrites
state.addon:SetElementScale("minimap", 1.5)
state.addon:SetElementScale("minimap", 1.1)
check(state.elementWrites == elementWrites, "Element changes never touch protected frames in combat")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick()
near(env.MinimapCluster:GetEffectiveScale(), 0.825, "Latest element choice applies after combat")
state.Click(env.SmallerUIResetButton)
check(state.reloads == 1 and next(env.SmallerUIDB.elements) == nil and not env.SmallerUIDB.enabled, "Reset button restores all game scale settings and reloads")

local special, specialState = boot({ scale = 0.4, enabled = true, elements = { minimap = 1.2 } })
special.MinimapCluster.ignore = true
specialState.addon:Apply()
near(special.MinimapCluster:GetEffectiveScale(), 1.2, "Already independent frames are not compensated twice")

local nested, nestedState = boot({ scale = 0.2, enabled = true })
nested.PlayerFrame.parent = nested.MainMenuBar
nestedState.addon:SetElementScale("actionbars", 1.4)
nestedState.addon:SetElementScale("player", 1.1)
near(nested.PlayerFrame:GetEffectiveScale(), 0.75 * 0.9 * 1.1, "Nested independently controlled groups apply ancestor first")

local corruptElements = boot({ scale = 0.5, enabled = false,
    elements = { minimap = 0/0, chat = "bad", quests = 3, unknown = 1, player = 1.2 } })
check(corruptElements.SmallerUIDB.elements.player == 1.2
    and corruptElements.SmallerUIDB.elements.minimap == nil
    and corruptElements.SmallerUIDB.elements.chat == nil
    and corruptElements.SmallerUIDB.elements.quests == nil
    and corruptElements.SmallerUIDB.elements.unknown == nil, "Corrupt element settings are discarded individually")
env.SettingsPanel:Close(true)
check(not panel:IsShown() and not env.SettingsPanel:IsShown(), "WoW's standard close dismisses the settings canvas")

local cancelEnv, cancelState, cancelEvent, cancelTick, cancelCommand = boot({ scale = 0.2, enabled = true })
cancelState.combat = true
cancelCommand("reset")
cancelState.addon:SetElementScale("minimap", 1.2)
cancelState.combat = false
cancelEvent("PLAYER_REGEN_ENABLED"); cancelTick()
check(cancelState.reloads == 0, "An element edit can cancel a pending reset")
near(cancelState.scale, 0.75, "Cancelling reset with an element edit restores the disabled global override")
near(cancelEnv.MinimapCluster:GetEffectiveScale(), 0.9, "The new individual element scale still applies after cancelling reset")

env, state, event, tick, command = boot(nil)
check(env.SmallerUIMinimapButton and env.SmallerUIMinimapButton:IsShown(), "Minimap launcher is visible by default")
state.Click(env.SmallerUIMinimapButton)
panel = env.SmallerUIOptions
check(panel:IsShown(), "Minimap launcher opens settings")
state.Click(env.SmallerUIShowMinimap)
check(not env.SmallerUIMinimapButton:IsShown(), "Minimap checkbox hides the launcher")
command("")
check(panel:IsShown(), "/sui remains available when the minimap button is hidden")
state.Click(env.SmallerUIShowMinimap)
check(env.SmallerUIMinimapButton:IsShown(), "Launcher can be shown again")
local angle = env.SmallerUIDB.minimapAngle
env.SmallerUIMinimapButton.scripts.OnDragStart(env.SmallerUIMinimapButton)
tick()
env.SmallerUIMinimapButton.scripts.OnDragStop(env.SmallerUIMinimapButton)
check(env.SmallerUIDB.minimapAngle ~= angle and not env.SmallerUIMinimapButton.scripts.OnUpdate, "Dragging saves launcher position and stops its update loop")

state.addon:SelectOptionsPage("cooldowns")
check(env.SmallerUIReadyPage:IsShown() and not panel:IsShown()
    and state.currentCategory == state.addon.readySettingsCategory, "Cooldowns use the native settings subcategory")
check(not env.SmallerUIDB.readyFlash and not env.SmallerUIChooseSlot.enabled, "Ready flashes start disabled")
state.Click(env.SmallerUIReadyEnabled)
check(env.SmallerUIDB.readyFlash and env.SmallerUIChooseSlot.enabled, "Master checkbox enables slot selection")
state.pendingWoWSettings = true
state.Click(env.SmallerUIChooseSlot)
check(not state.addon:IsPickingSlot() and env.SettingsPanel:IsShown(),
    "Slot picker respects WoW's unapplied settings before closing its native window")
state.pendingWoWSettings = false
local casts = 0
env.ActionButton1.scripts.OnClick = function() casts = casts + 1 end
state.Click(env.SmallerUIChooseSlot)
check(state.addon:IsPickingSlot() and not env.SettingsPanel:IsShown()
    and state.skippedGameMenuTransition, "Choose slot closes native settings without opening the game menu")
check(env.SmallerUIPick_ActionButton1:IsShown(), "Picker covers visible action slots")
state.Click(env.SmallerUIPick_ActionButton1)
check(casts == 0 and env.ActionButton1.action == 1, "Picking a slot neither casts nor changes the secure action")
check(env.SmallerUICharDB.readySlots.ActionButton1 and env.SettingsPanel:IsShown()
    and not state.addon:IsPickingSlot(), "Click selects a slot and returns to native settings")
check(env.SmallerUIReadyPage:IsShown(), "Picker returns to the cooldown tab")
local glow = env.SmallerUIReadyGlow_ActionButton1
tick(0.1)
check(not glow:IsShown(), "A skill already ready on startup does not flash")
state.Click(env.SmallerUITestFlashes)
check(glow:IsShown(), "Test button previews selected slots")
near(glow:GetWidth(), env.ActionButton1:GetWidth() * env.ActionButton1:GetEffectiveScale(), "Glow follows the action button's effective size")
tick(1.05)
check(not glow:IsShown(), "Preview ends after one second")

state.cooldowns[1] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05)
check(not glow:IsShown(), "Active cooldown does not flash early")
tick(2.05)
check(glow:IsShown(), "Real cooldown completion flashes the chosen slot")
tick(0.5)
check(glow:IsShown() and glow:GetAlpha() < 1, "Ready flash pulses and fades")
tick(0.55)
check(not glow:IsShown(), "Automatic flash lasts one second")
tick(0.1)
check(not glow:IsShown(), "Ready skill does not flash repeatedly")
check(not env.SmallerUIReadyGlow_MultiBarBottomLeftButton2, "Unselected slots do not get automatic flashes")

state.gcd = { startTime = state.now, duration = 1.5 }
state.cooldowns[1] = { startTime = state.now, duration = 1.5, isEnabled = true }
tick(0.05); tick(1.6)
check(not glow:IsShown(), "Global cooldown alone never arms a ready flash")
state.gcd = nil
state.cooldowns[1] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05); tick(1.8)
state.gcd = { startTime = state.now, duration = 1.5 }
state.cooldowns[1] = { startTime = state.now, duration = 1.5, isEnabled = true }
tick(0.2)
check(not glow:IsShown(), "A real cooldown waits for an overlapping global cooldown")
tick(1.4)
check(glow:IsShown(), "Pending ready flash fires after the global cooldown")
tick(1.05)
state.gcd = nil
state.usable[1] = false
state.cooldowns[1] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05); tick(2.1)
check(not glow:IsShown(), "An unusable skill waits instead of flashing")
state.usable[1] = true
tick(0.05)
check(glow:IsShown(), "Flash fires once the off-cooldown skill becomes usable")
tick(1.05)

state.charges[1] = { currentCharges = 0, maxCharges = 2 }
state.cooldowns[1] = { startTime = 0, duration = 0, isEnabled = true }
tick(0.05)
state.charges[1].currentCharges = 1
tick(0.05)
check(glow:IsShown(), "Regaining the first charge flashes an unavailable skill")
tick(1.05)
state.charges[1].currentCharges = 2
tick(0.05)
check(not glow:IsShown(), "Additional charges do not flash an already usable skill")
state.charges[1] = nil

state.cooldowns[1] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05)
env.ActionButton1.action = 13
state.actions[13] = { kind = "spell", id = 1013 }
event("ACTIONBAR_PAGE_CHANGED")
tick(2.1)
check(not glow:IsShown(), "Bar-page changes discard the previous skill's cooldown history")
state.cooldowns[13] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05); tick(2.1)
check(glow:IsShown(), "Chosen visual slot follows its current bar page")
tick(1.05)
state.cooldowns[13] = { startTime = state.now, duration = 2, isEnabled = true }
tick(0.05)
state.actions[13] = { kind = "spell", id = 9999 }
state.cooldowns[13] = nil
event("ACTIONBAR_SLOT_CHANGED", 13)
tick(0.05)
check(not glow:IsShown(), "Replacing a skill does not generate a false ready flash")

state.Click(env.SmallerUIChooseSlot)
env.SmallerUISlotPicker:Hide()
check(not state.addon:IsPickingSlot() and env.SettingsPanel:IsShown()
    and env.SmallerUICharDB.readySlots.ActionButton1, "Escape cancels selection without removing the slot")
state.Click(env.SmallerUIChooseSlot)
state.Click(env.SmallerUIPick_ActionButton1, "RightButton")
check(not state.addon:IsPickingSlot() and env.SmallerUICharDB.readySlots.ActionButton1, "Right-click cancels selection")
state.Click(env.SmallerUIChooseSlot)
state.combat = true
event("PLAYER_REGEN_DISABLED")
check(not state.addon:IsPickingSlot() and not env.SettingsPanel:IsShown()
    and state.addon.pendingOptionsPage == "cooldowns" and not env.SmallerUIChooseSlot.enabled,
    "Entering combat cancels picking and defers reopening native settings")
check(not env.SmallerUIPick_ActionButton1:IsShown(), "Combat cancellation removes click-intercepting overlays")
check(not state.addon:BeginSlotPicker(), "Picker refuses direct requests during combat")
state.cooldowns[13] = { startTime = state.now, duration = 2, isEnabled = true }
local protectedWrites = state.writes + state.elementWrites
tick(0.05); tick(2.1)
check(glow:IsShown() and state.writes + state.elementWrites == protectedWrites, "Prepared ready flashes work in combat without changing protected scales")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick(1.05)
check(env.SettingsPanel:IsShown() and state.currentCategory == state.addon.readySettingsCategory,
    "Cooldown settings reopen safely after combat")

local secret = setmetatable({ secret = true }, { __tostring = function() error("Secret was inspected") end })
state.actions[13].id = secret
state.cooldowns[13] = { startTime = secret, duration = secret, modRate = secret,
    isEnabled = true, isActive = true, isOnGCD = false }
event("SPELL_UPDATE_COOLDOWN")
tick(0.1)
state.cooldowns[13].isActive = false
event("SPELL_UPDATE_COOLDOWN")
check(glow:IsShown(), "Public ready events work without inspecting restricted timings or spell IDs")
tick(1.05)
state.cooldowns[13].isActive = true
state.cooldowns[13].isOnGCD = true
event("SPELL_UPDATE_COOLDOWN")
state.cooldowns[13].isActive = false
event("SPELL_UPDATE_COOLDOWN")
check(not glow:IsShown(), "Restricted-timing public events still ignore the global cooldown")
state.cooldowns[13].isActive = nil
state.cooldowns[13].isOnGCD = nil
event("SPELL_UPDATE_COOLDOWN")
check(state.addon.cooldownRestricted and not glow:IsShown(), "Unavailable public cooldown state is skipped without false alerts")
state.actions[13].id = 1013
state.cooldowns[13] = { startTime = state.now, duration = 4, modRate = 2, isEnabled = true }
tick(0.05); tick(2.1)
check(glow:IsShown(), "Cooldown speed modifiers are respected")

state.Click(env.SmallerUIReadyEnabled)
check(not glow:IsShown() and env.SmallerUICharDB.readySlots.ActionButton1, "Disabling the feature stops glows while keeping selected slots")
state.Click(env.SmallerUIReadyEnabled)
local savedGlobal, savedCharacter = env.SmallerUIDB, env.SmallerUICharDB
local sameCharacter = boot(savedGlobal, savedCharacter)
check(sameCharacter.SmallerUICharDB.readySlots.ActionButton1, "Selected slots persist for the same character")
local otherCharacter = boot(savedGlobal)
check(next(otherCharacter.SmallerUICharDB.readySlots) == nil, "Other characters have independent slot selections")
state.Click(env.SmallerUIChooseSlot)
state.Click(env.SmallerUIPick_ActionButton1)
check(not env.SmallerUICharDB.readySlots.ActionButton1, "Picking a selected slot again removes it")
state.addon:ToggleReadySlot("ActionButton1")
state.addon:ToggleReadySlot("MultiBarBottomLeftButton2")
check(#state.addon:GetReadySlots() == 2, "Multiple slots can be selected independently")
state.Click(env.SmallerUIReadyPage.rows[1].remove)
check(#state.addon:GetReadySlots() == 1 and not env.SmallerUICharDB.readySlots.ActionButton1,
    "Remove button untracks the corresponding list row")
state.Click(env.SmallerUIClearSlots)
check(next(env.SmallerUICharDB.readySlots) == nil and not env.SmallerUIReadyGlow_ActionButton1:IsShown(), "Clear all removes selected slots and stops their effects")

local cleaned = boot({ readyFlash = "yes", minimapAngle = 0/0 },
    { readySlots = { ActionButton1 = true, ActionButton99 = true, RandomFrame = true, ActionButton2 = "yes" } })
check(not cleaned.SmallerUIDB.readyFlash and cleaned.SmallerUIDB.minimapAngle == 225, "Invalid feature preferences recover safely")
check(cleaned.SmallerUICharDB.readySlots.ActionButton1 and not cleaned.SmallerUICharDB.readySlots.ActionButton99
    and not cleaned.SmallerUICharDB.readySlots.RandomFrame and not cleaned.SmallerUICharDB.readySlots.ActionButton2,
    "Saved slot names and flags are validated")

local legacy, legacyState, _, legacyTick = boot({ readyFlash = true }, { readySlots = { ActionButton1 = true } })
legacy.C_ActionBar, legacy.C_Spell = nil, nil
legacy.GetActionCooldown = function(action)
    local cd = legacyState.cooldowns[action] or { startTime = 0, duration = 0 }
    return cd.startTime, cd.duration, 1, 1
end
legacy.GetActionCharges = function() end
legacy.IsUsableAction = function() return true end
legacy.GetSpellCooldown = function() return 0, 0 end
legacyState.cooldowns[1] = { startTime = legacyState.now, duration = 2 }
legacyTick(0.05); legacyTick(2.1)
check(legacy.SmallerUIReadyGlow_ActionButton1:IsShown(), "Legacy public cooldown APIs remain supported")

local resetFeatures, resetFeatureState, _, _, resetFeatureCommand = boot({
    readyFlash = true, enabled = true, scale = 0.4, elements = { minimap = 1.2 } },
    { readySlots = { ActionButton1 = true } })
resetFeatureCommand("reset")
check(resetFeatureState.reloads == 1 and not resetFeatures.SmallerUIDB.enabled
    and next(resetFeatures.SmallerUIDB.elements) == nil, "Scale reset still restores global and individual sizes")
check(resetFeatures.SmallerUIDB.readyFlash and resetFeatures.SmallerUICharDB.readySlots.ActionButton1,
    "Scale reset preserves the separately managed cooldown feature")

local nativeQueue, nativeQueueState, nativeQueueEvent, nativeQueueTick, nativeQueueCommand = boot(nil)
nativeQueueState.combat = true
nativeQueueCommand("")
check(not nativeQueue.SettingsPanel:IsShown() and nativeQueueState.addon.pendingOptionsPage == "scaling",
    "/sui queues a native settings request during combat")
nativeQueueState.combat = false
nativeQueueEvent("PLAYER_REGEN_ENABLED"); nativeQueueTick()
check(nativeQueue.SettingsPanel:IsShown()
    and nativeQueueState.currentCategory == nativeQueueState.addon.settingsCategory,
    "Queued /sui opens the native page after combat")

local minimapSaved = boot({ scale = 0.4, enabled = true, elements = { minimap = 1.2 } })
check(minimapSaved.SmallerUIDB.elements.minimap == 1.2 and not minimapSaved.SmallerUIElementInput_minimap,
    "Hiding minimap size controls preserves saved minimap preferences")

print(string.format("Passed %d checks (%s).", passed, _VERSION))

return boot
