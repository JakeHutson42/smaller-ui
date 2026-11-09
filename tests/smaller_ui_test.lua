local passed = 0

local function check(condition, message)
    assert(condition, message)
    passed = passed + 1
end

local function boot(saved, characterSaved, compatibility)
    local env = setmetatable({}, { __index = _G })
    env._G = env
    local messages = {}
    local state = { scale = 0.75, combat = false, writes = 0, reloads = 0, elementWrites = 0,
        now = 100, widgets = {}, objects = {}, cooldowns = {}, charges = {}, actions = {}, usable = {},
        units = { player = { health = 1000, maximum = 1000, power = 70, powerMax = 100, token = "MANA", name = "Your character" } },
        cvars = { nameplateShowSelf = "1" }, cvarWrites = 0, forbiddenActions = 0,
        combatLogRegistrations = 0, legacyCombatLog = compatibility and compatibility.legacyCombatLog == true }
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
        function widget:RegisterEvent(value)
            if value == "COMBAT_LOG_EVENT_UNFILTERED" then
                state.combatLogRegistrations = state.combatLogRegistrations + 1
                if not state.legacyCombatLog then
                    state.forbiddenActions = state.forbiddenActions + 1
                    event("ADDON_ACTION_FORBIDDEN", "SmallerUI", "Frame:RegisterEvent()")
                    error("Combat-log registration forbidden; notification already emitted")
                end
            end
            self.events[value] = true
        end
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
        function widget:SetValue(value, interpolation)
            if self.kind == "StatusBar" then
                self.value, self.interpolation = value, interpolation
                if interpolation ~= 1 then self.rendered = value end
                self.valueCalls = (self.valueCalls or 0) + 1
                return
            end
            value = math.max(self.low, math.min(self.high, value))
            if self.value == value then return end
            self.value = value
            if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, value) end
        end
        function widget:GetValue() return self.value end
        function widget:GetInterpolatedValue() return self.rendered end
        function widget:SetupMenu(generator) self.menuGenerator = generator; self:GenerateMenu() end
        function widget:GenerateMenu()
            self.menu = {}
            local owner = self
            local root = {}
            function root:CreateRadio(label, selected, respond, data)
                local row = { label = label, respond = respond, data = data }
                function row:AddInitializer(initializer) self.initialize = initializer end
                owner.menu[#owner.menu + 1] = row
                if selected(data) then owner.text = label end
                return row
            end
            self.menuGenerator(self, root)
        end
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
        function widget:GetWidth()
            if state.geometry then local _, _, width = state.GeometryRect(self); return width end
            return self.width or 36
        end
        function widget:GetHeight()
            if state.geometry then local _, _, _, height = state.GeometryRect(self); return height end
            return self.height or 36
        end
        function widget:GetRect()
            if state.geometry then return state.GeometryRect(self) end
            return self.left or 0, self.bottom or 0, self:GetWidth(), self:GetHeight()
        end
        function widget:GetCenter()
            local x, y, width, height = self:GetRect()
            return x + width / 2, y + height / 2
        end
        function widget:IsVisible() return self.shown and (not self.parent or self.parent:IsVisible()) end
        function widget:SetEnabled(value) self.enabled = value end
        function widget:SetAlpha(value) self.alpha = value end
        function widget:GetAlpha() return self.alpha or 1 end
        function widget:SetStatusBarColor(...) self.barColor = { ... } end
        function widget:SetFormattedText(format, ...)
            self.format, self.formatArgs = format, { ... }
            for _, value in ipairs(self.formatArgs) do
                if type(value) == "table" and value.secret then self.text = "restricted"; return end
            end
            self.text = string.format(format, ...)
        end
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
            "SetOwner", "AddLine", "SetWordWrap", "SetFont", "SetStatusBarTexture", "SetTexCoord", "SetNormalTexture",
            "SetPushedTexture", "SetClipsChildren", "SetReverseFill" }) do
            widget[method] = function() end
        end
        function widget:SetPoint(...) self._points[#self._points + 1] = { ... } end
        function widget:ClearAllPoints() self._points = {}; self.allPoints = nil end
        function widget:SetAllPoints(target) self.allPoints = target or self.parent; self._points = {} end
        function widget:SetColorTexture(...) self.color = { ... } end
        function widget:SetTextColor(...) self.textColor = { ... } end
        function widget:SetFont(path, size, flags) self.fontPath, self.fontSize, self.fontFlags = path, size, flags end
        function widget:SetJustifyH(value) self.justifyH = value end
        function widget:SetBackdropBorderColor(...) self.borderColor = { ... } end
        function widget:SetBackdropColor(...) self.backgroundColor = { ... } end
        function widget:SetBackdrop(info) self.backdrop = info end
        function widget:SetRoundLayoutToNearestPixel(value) self.roundLayout = value end
        function widget:SetTexelSnappingBias(value) self.texelBias = value end
        function widget:SetSnapToPixelGrid(value) self.snapToGrid = value end
        function widget:EnableMouse(value) self.mouseEnabled = value end
        function widget:SetTexture(value) self.textureValue = value end
        function widget:SetDesaturated(value) self.desaturated = value end
        function widget:SetClipsChildren(value) self.clipsChildren = value end
        function widget:SetReverseFill(value) self.reverseFill = value end
        function widget:GetStatusBarTexture()
            if not self.statusTexture then self.statusTexture = Widget(nil, self) end
            return self.statusTexture
        end
        return widget
    end
    function state.Click(widget, mouseButton)
        if widget.enabled == false then return end
        if widget.kind == "CheckButton" then widget.checked = not widget.checked end
        widget.scripts.OnClick(widget, mouseButton or "LeftButton")
    end
    function state.Select(dropdown, value)
        dropdown:GenerateMenu()
        for _, entry in ipairs(dropdown.menu) do
            if entry.data == value then entry.respond(value); dropdown:GenerateMenu(); return end
        end
        error("Unknown dropdown selection")
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
    env.UIParent:SetSize(1920, 1080)
    env.SettingsPanel = Widget("SettingsPanel")
    env.SettingsPanel:Hide()
    env.ColorPickerFrame = Widget("ColorPickerFrame")
    env.ColorPickerFrame:Hide()
    function env.ColorPickerFrame:SetupColorPickerAndShow(info)
        self.extraInfo, self.previousValues = info.extraInfo, { r = info.r, g = info.g, b = info.b }
        self.swatchFunc, self.cancelFunc = info.swatchFunc, info.cancelFunc
        self.rgb = { info.r, info.g, info.b }
        self.swatchFunc() -- WoW also fires a colour change while initializing.
        self:Show()
    end
    function env.ColorPickerFrame:GetColorRGB() return unpack(self.rgb) end
    function env.ColorPickerFrame:OnOkay() self.swatchFunc(); self:Hide() end
    function env.ColorPickerFrame:OnCancel() self.cancelFunc(self.previousValues); self:Hide() end
    function state.PickColour(r, g, b)
        env.ColorPickerFrame.rgb = { r, g, b }
        env.ColorPickerFrame.swatchFunc()
    end
    state.categories = {}
    local categoryList = { callbacks = {} }
    function categoryList:RegisterCallback(eventName, callback, owner)
        self.callbacks[#self.callbacks + 1] = { event = eventName, callback = callback, owner = owner }
    end
    function categoryList:Notify()
        for _, entry in ipairs(self.callbacks) do entry.callback(entry.owner) end
    end
    env.SettingsCategoryListMixin = { Event = { OnCategoriesUpdated = "OnCategoriesUpdated" } }
    function env.SettingsPanel:GetCategoryList() return categoryList end
    function env.SettingsPanel:GetCurrentCategory() return state.currentCategory end
    local function Category(panel, name, parent)
        local category = { panel = panel, name = name, parent = parent, id = 100 + #state.categories, subcategories = {} }
        function category:GetID() return self.id end
        function category:SetExpanded(value) self.expanded = value end
        function category:IsExpanded() return self.expanded end
        function category:SetShouldSortAlphabetically(value) self.alphabetical = value end
        if parent then table.insert(parent.subcategories, category) end
        state.categories[#state.categories + 1] = category
        return category
    end
    function env.SettingsPanel:SelectCategory(category)
        if state.currentCategory and state.currentCategory ~= category then state.currentCategory.panel:Hide() end
        state.currentCategory = category
        local parent = category.parent
        while parent do parent:SetExpanded(true); parent = parent.parent end
        categoryList:Notify()
        category.panel.parent = env.SettingsPanel
        category.panel:Show()
    end
    function state.ToggleCategory(category)
        category:SetExpanded(not category:IsExpanded())
        categoryList:Notify()
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
            env.SettingsPanel:Show()
            category:SetExpanded(true)
            env.SettingsPanel:SelectCategory(category)
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
    env.GetCursorPosition = function() return state.cursorX or 100, state.cursorY or 100 end
    env.IsMouseButtonDown = function() return state.mouseDown or false end
    env.IsShiftKeyDown = function() return state.shift or false end
    env.PixelUtil = { GetPixelToUIUnitFactor = function() return state.pixelSize or 1 end }
    env.Enum = { StatusBarInterpolation = { Immediate = 0, ExponentialEaseOut = 1 } }
    env.Enum.UnitIncomingHealClampMode = { MissingHealth = 0 }
    env.PowerBarColor = { MANA = { r = 0.2, g = 0.5, b = 0.95 }, RAGE = { r = 0.9, g = 0.2, b = 0.15 }, ENERGY = { r = 1, g = 0.8, b = 0.1 }, FOCUS = { r = 1, g = 0.5, b = 0.25 } }
    env.MANA, env.RAGE, env.ENERGY, env.FOCUS = "Mana", "Rage", "Energy", "Focus"
    env.UnitExists = function(unit) return state.units[unit] ~= nil end
    env.UnitHealth = function(unit) return state.units[unit].health end
    env.UnitHealthMax = function(unit) return state.units[unit].maximum end
    env.UnitPower = function(unit, powerType)
        local data = state.units[unit]
        data.queriedPowerType = powerType
        if data.pools then return data.pools[powerType].value end
        return data.power
    end
    env.UnitPowerMax = function(unit, powerType)
        local data = state.units[unit]
        data.queriedMaxPowerType = powerType
        if data.pools then return data.pools[powerType].maximum end
        return data.powerMax
    end
    env.UnitPowerType = function(unit)
        local data = state.units[unit]
        return data.powerType or ({ MANA = 0, RAGE = 1, FOCUS = 2, ENERGY = 3 })[data.token], data.token,
            data.red, data.green, data.blue
    end
    function state.GeometryRect(widget)
        local Canvas
        local function Fraction(anchor)
            return anchor:find("LEFT") and 0 or anchor:find("RIGHT") and 1 or 0.5,
                anchor:find("BOTTOM") and 0 or anchor:find("TOP") and 1 or 0.5
        end
        Canvas = function(item)
            local scale = item:GetEffectiveScale()
            if item.allPoints then return Canvas(item.allPoints) end
            local width, height = (item.width or 36) * scale, (item.height or 36) * scale
            local function Rect(x, y, w, h)
                if state.roundGeometry and item.roundLayout then
                    local pixel = state.pixelSize or 1
                    local function Round(value) return math.floor(value / pixel + 0.5) * pixel end
                    return Round(x), Round(y), Round(w), Round(h)
                end
                return x, y, w, h
            end
            if #item._points == 0 then return Rect((item.left or 0) * scale, (item.bottom or 0) * scale, width, height) end
            local constraints = {}
            for _, point in ipairs(item._points) do
                local parent, relative, ox, oy
                if type(point[2]) == "table" then parent, relative, ox, oy = point[2], point[3], point[4] or 0, point[5] or 0
                else parent, relative, ox, oy = item.parent, point[1], point[2] or 0, point[3] or 0 end
                local px, py, pw, ph = Canvas(parent)
                local fx, fy = Fraction(point[1])
                local rx, ry = Fraction(relative)
                constraints[#constraints + 1] = { fx = fx, fy = fy, x = px + pw * rx + ox * scale, y = py + ph * ry + oy * scale }
            end
            local first = constraints[1]
            for index = 2, #constraints do
                local other = constraints[index]
                if other.fx ~= first.fx then width = (other.x - first.x) / (other.fx - first.fx) end
                if other.fy ~= first.fy then height = (other.y - first.y) / (other.fy - first.fy) end
            end
            return Rect(first.x - first.fx * width, first.y - first.fy * height, width, height)
        end
        local x, y, width, height = Canvas(widget)
        local scale = widget:GetEffectiveScale()
        return x / scale, y / scale, width / scale, height / scale
    end
    env.CurveConstants = { ScaleTo100 = {} }
    env.UnitHealthPercent = function(unit, predicted, curve)
        assert(predicted == true and curve == env.CurveConstants.ScaleTo100, "Health percentage must match the live HP mode and use native scaling")
        local data = state.units[unit]
        if data.percent ~= nil then return data.percent end
        return data.maximum > 0 and data.health / data.maximum * 100 or 0
    end
    env.UnitPowerPercent = function(unit, powerType, unmodified, curve)
        assert(not unmodified and curve == env.CurveConstants.ScaleTo100, "Power percentage must use displayed units and native scaling")
        local data = state.units[unit]
        data.percentPowerType = powerType
        if data.powerPercent ~= nil then return data.powerPercent end
        local pool = data.pools and data.pools[powerType]
        local value, maximum = pool and pool.value or data.power, pool and pool.maximum or data.powerMax
        return maximum > 0 and value / maximum * 100 or 0
    end
    env.UnitName = function(unit) return state.units[unit].name end
    env.UnitGUID = function(unit)
        local data = state.units[unit]
        return data and (data.guid or unit .. "-guid")
    end
    env.UnitClass = function() return state.class or "Mage", state.class or "MAGE" end
    env.UnitIsConnected = function(unit) return state.units[unit].connected ~= false end
    env.UnitIsDeadOrGhost = function(unit) return state.units[unit].dead or false end
    env.SetPortraitTexture = function(texture, unit) texture.portraitUnit = unit end
    env.C_CVar = {
        GetCVar = function(name) return state.cvars[name] end,
        SetCVar = function(name, value)
            assert(not state.combat, "CVar changed in combat")
            state.cvars[name] = value
            state.cvarWrites = state.cvarWrites + 1
            event("CVAR_UPDATE", name)
        end,
    }
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
    state.auras = {}
    env.C_UnitAuras = { GetAuraDataByIndex = function(unit, index, filter)
        if state.auraUnavailable then error("Aura access unavailable") end
        local auras = state.auras[unit]
        return auras and auras[filter] and auras[filter][index]
    end }
    env.C_CombatLog = { IsCombatLogRestricted = function() return state.logRestricted or false end }
    if not (compatibility and compatibility.noEventMetadata) then
        env.C_EventUtils = {
            IsEventValid = function() return not (compatibility and compatibility.invalidCombatLog) end,
            IsCallbackEvent = function(name) return name == "COMBAT_LOG_EVENT_UNFILTERED" and not state.legacyCombatLog end,
        }
    end
    env.CombatLogGetCurrentEventInfo = function() return unpack(state.combatLog or {}) end
    env.CreateUnitHealPredictionCalculator = function()
        local calculator = {}
        function calculator:SetIncomingHealClampMode(value) self.clamp = value end
        function calculator:SetIncomingHealOverflowPercent(value) self.overflow = value end
        function calculator:GetIncomingHeals()
            local unit = state.units[self.unit]
            local amount = unit.incoming or 0
            if type(amount) ~= "number" or type(unit.health) ~= "number" or type(unit.maximum) ~= "number" then return amount end
            return math.max(0, math.min(amount - (unit.healAbsorb or 0), unit.maximum - unit.health))
        end
        return calculator
    end
    env.UnitGetDetailedHealPrediction = function(unit, healer, calculator) calculator.unit, calculator.healer = unit, healer end
    env.UnitGetIncomingHeals = function(unit) return state.units[unit].incoming end
    env.C_Spell = {
        GetSpellCooldown = function() return state.gcd or { startTime = 0, duration = 0 } end,
        GetSpellInfo = function(spell)
            if state.spellInfo and state.spellInfo[spell] then return state.spellInfo[spell] end
            local names = { [20154] = "Seal of Righteousness", [21084] = "Seal of Righteousness",
                [21082] = "Seal of the Crusader", [20163] = "Seal of Fury",
                [20375] = "Seal of Command", [20166] = "Seal of Wisdom" }
            if names[spell] then return { name = names[spell], iconID = spell + 1000 } end
        end,
    }
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
check(#state.categories == 6 and state.registeredAddon == state.addon.settingsCategory
    and not env.SettingsPanel:IsShown(), "Native AddOns entries register at login without opening the menu")
command("")
local panel = env.SmallerUIOptions
check(panel and panel:IsShown(), "/sui opens settings")
check(env.SettingsPanel:IsShown() and state.currentCategory == state.addon.scaleSettingsCategory,
    "/sui opens the UI scaling subcategory")
check(#env.UISpecialFrames == 0, "Addon does not register a separate settings window")
command("")
check(env.SmallerUIOptions == panel and #state.categories == 6, "Opening settings reuses the same registered pages")
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
check(state.currentCategory == state.addon.scaleSettingsCategory, "Applying scale keeps the native settings page open")
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
    and nativeQueueState.currentCategory == nativeQueueState.addon.scaleSettingsCategory,
    "Queued /sui opens the native page after combat")

local minimapSaved = boot({ scale = 0.4, enabled = true, elements = { minimap = 1.2 } })
check(minimapSaved.SmallerUIDB.elements.minimap == 1.2 and not minimapSaved.SmallerUIElementInput_minimap,
    "Hiding minimap size controls preserves saved minimap preferences")

env, state, event, tick, command = boot(nil)
local addon = state.addon
check(not addon:GetResourceSettings().enabled and not addon:GetResourceSettings().partyEnabled
    and not addon:GetResourceDisplay() and state.cvarWrites == 0, "New resource displays are opt-in and leave Blizzard unchanged by default")
addon:ShowOptions("resources")
check(state.currentCategory == addon.resourceSettingsCategory
    and addon.resourceSettingsCategory.parent == addon.settingsCategory, "Personal resources has a native settings subcategory")
state.Click(env.SmallerUIPersonalEnabled)
local hud = addon:GetResourceDisplay()
check(hud.player:IsShown() and not hud.partyRoot:IsShown(), "Enabling personal resources shows player bars without a party")
check(hud.player.health.fill:GetValue() == 1000 and hud.player.power.fill:GetValue() == 70,
    "Personal bars initialize from the live health and power APIs")
check(state.cvars.nameplateShowSelf == "0" and env.SmallerUICharDB.originalSelfResourceCVar == "1",
    "Enabling the replacement remembers and hides the original personal resource display")
check(not hud.player.health.mouseEnabled and not hud.player.health.grip:IsShown(), "Locked bars are mouse-transparent and have no resize handles")
command("0.4")
near(hud.player:GetEffectiveScale(), 1, "Resource display size is independent of the global UI scale")

state.units.player.health = 650
event("UNIT_HEALTH", "player")
check(hud.player.health.fill:GetValue() == 650
    and hud.player.health.fill:GetInterpolatedValue() == 650
    and hud.player.health.fill.interpolation == env.Enum.StatusBarInterpolation.Immediate,
    "Damage updates displayed health immediately with no interpolation")
check(hud.player.health.trail:GetValue() == 1000, "Damage leaves a short previous-health trail")
check(hud.player.health.valueText:GetText() == "650 / 1000" and hud.player.health.pulse.color[1] == 1,
    "Health values and subtle damage feedback update together")
tick(0.13)
check(hud.player.health.trail:GetValue() == 650, "Damage trail catches up after its short delay")
state.units.player.health = 920
event("UNIT_HEALTH", "player")
check(hud.player.health.fill:GetValue() == 920 and hud.player.health.pulse.color[1] == 0.35,
    "Healing raises the health bar and uses positive feedback")
tick(0.3)
check(not hud.player.health.pulse:IsShown(), "Health feedback fades quickly")
local healthCalls = hud.player.health.fill.valueCalls
state.units.player.power = 24
event("UNIT_POWER_FREQUENT", "player")
check(hud.player.power.fill:GetValue() == 24 and hud.player.health.fill.valueCalls == healthCalls,
    "Frequent power updates do not reanimate unrelated health values")
state.units.player.token = "RAGE"
event("UNIT_DISPLAYPOWER", "player")
check(hud.player.power.label:GetText() == "Rage" and hud.player.power.fill.barColor[1] == 0.9,
    "Changing resource type updates its label and colour")
state.units.player.maximum = 1800
event("UNIT_MAXHEALTH", "player")
check(hud.player.health.fill.high == 1800 and hud.player.health.trail:GetValue() == 920,
    "Max-health changes reset both bar ranges without stale trails")
healthCalls = hud.player.health.fill.valueCalls
event("UNIT_HEALTH", "target")
check(hud.player.health.fill.valueCalls == healthCalls, "Unrelated unit events are ignored")
state.units.player.dead = true
event("PLAYER_DEAD")
check(hud.player.health.valueText:GetText() == "Dead", "Death has a clear status label")
state.units.player.dead = false

local privateValue = setmetatable({ secret = true }, {
    __tostring = function() error("Private unit value was formatted in Lua") end,
    __lt = function() error("Private unit value was compared in Lua") end,
    __add = function() error("Private unit value was added in Lua") end,
    __div = function() error("Private unit value was divided in Lua") end,
})
state.units.player.health, state.units.player.maximum = privateValue, privateValue
event("UNIT_HEALTH", "player")
check(hud.player.health.fill:GetValue() == privateValue and hud.player.health.fill.high == privateValue,
    "Restricted health values are passed directly to native bars without Lua arithmetic")
check(hud.player.health.valueText.formatArgs[1] == privateValue and hud.player.health.lastPublic == nil,
    "Restricted text uses native formatting and is not kept as a public comparison value")
tick(0.15)
check(hud.player.health.trail:GetValue() == privateValue, "Restricted values also support the native trail renderer")
state.units.player.health, state.units.player.maximum = 850, 1800
event("UNIT_HEALTH", "player")

addon:ShowOptions("party")
check(state.currentCategory == addon.partySettingsCategory, "Party display has its own simple native page")
state.Click(env.SmallerUIPartyEnabled)
check(not hud.partyRoot:IsShown(), "Optional party display stays hidden while solo")
state.units.party1 = { health = 1900, maximum = 2500, power = 80, powerMax = 100, token = "ENERGY", name = "Alex" }
state.units.party2 = { health = 1400, maximum = 2000, power = 40, powerMax = 100, token = "RAGE", name = "Morgan" }
event("GROUP_ROSTER_UPDATE")
check(hud.partyRoot:IsShown() and hud.party[1]:IsShown() and hud.party[2]:IsShown()
    and not hud.party[3]:IsShown(), "Roster updates show exactly the available party members")
check(hud.party[1].name:GetText() == "Alex" and hud.party[1].portrait.portraitUnit == "party1",
    "Party display uses real unit names and portraits")
state.units.party1.power = 35
event("UNIT_POWER_UPDATE", "party1")
check(hud.party[1].power.fill:GetValue() == 35, "Party resources also receive normal unit power updates")
local namedHeight, portraitWidth = hud.party[1]:GetHeight(), hud.party[1]:GetWidth()
state.Click(env.SmallerUIPartyNames)
check(not hud.party[1].name:IsShown() and hud.party[1]:GetHeight() < namedHeight,
    "Hiding names removes their layout space")
state.Click(env.SmallerUIPartyPortraits)
check(not hud.party[1].portrait:IsShown() and hud.party[1]:GetWidth() < portraitWidth,
    "Hiding portraits makes the party frames narrower")
state.Click(env.SmallerUIPartyValues)
check(not hud.party[1].health.valueText:IsShown(), "Party values can be hidden separately")
env.SmallerUIPartyhealthWidth:SetText("320")
env.SmallerUIPartyhealthHeight:SetText("42")
env.SmallerUIPartypowerWidth:SetText("175")
env.SmallerUIPartypowerHeight:SetText("17")
env.SmallerUIPartyscale:SetText("1.5")
env.SmallerUIPartygap:SetText("8")
env.SmallerUIPartyspacing:SetText("20")
state.Click(env.SmallerUIPartyApply)
check(hud.party[1].health:GetWidth() == 320 and hud.party[1].health:GetHeight() == 42
    and math.abs(hud.party[1].power:GetWidth() * 1.5 - 263) < 0.00001
    and math.abs(hud.party[1].power:GetHeight() * 1.5 - 26) < 0.00001
    and addon:GetResourceSettings().party.power.width == 175 and addon:GetResourceSettings().party.power.height == 17,
    "Independent party sizes render at the nearest physical pixel while preserving exact saved inputs")
near(hud.partyRoot:GetEffectiveScale(), 1.5, "Party scale adjusts the whole group")
local previousWidth = addon:GetResourceSettings().party.health.width
env.SmallerUIPartyhealthWidth:SetText("bad")
state.Click(env.SmallerUIPartyApply)
check(addon:GetResourceSettings().party.health.width == previousWidth, "Invalid settings apply atomically without losing the prior layout")
state.Click(env.SmallerUIPartyReset)
check(addon:GetResourceSettings().party.health.width == 200
    and not addon:GetResourceSettings().party.names and not addon:GetResourceSettings().party.portraits,
    "Reset layout preserves appearance preferences")
state.units.party2 = nil
event("GROUP_ROSTER_UPDATE")
check(not hud.party[2]:IsShown(), "Members leaving the party disappear promptly")
state.units.party1.connected = false
event("UNIT_CONNECTION", "party1")
check(hud.party[1].health.valueText:GetText() == "Offline", "Disconnected party members are labelled")

addon:ShowOptions("resources")
state.Click(env.SmallerUIPersonalEnabled)
check(not hud.player:IsShown() and hud.partyRoot:IsShown() and state.cvars.nameplateShowSelf == "1",
    "Disabling personal bars restores Blizzard while optional party bars remain active")
state.Click(env.SmallerUIPersonalMove)
check(addon:IsEditingResources() and not env.SettingsPanel:IsShown() and hud.player:IsShown()
    and hud.party[4]:IsShown(), "Preview mode shows personal bars and sample party members even when solo or disabled")
check(hud.player.health.mouseEnabled and hud.player.health.grip:IsShown(), "Edit mode enables drag and resize handles")
local playerBefore = addon:GetResourceSettings().player.health.width
addon:ResizeResourceBars("player", "health", 480, 44)
check(addon:GetResourceSettings().player.power.width == 480 and addon:GetResourceSettings().player.power.height == 24,
    "Linked corner resizing changes both bars proportionally")
addon:SetResourceOption("player", "linked", false)
addon:ResizeResourceBars("player", "health", 300, 60)
check(addon:GetResourceSettings().player.health.width == 300 and addon:GetResourceSettings().player.power.width == 480,
    "Unlinked resizing changes only the selected bar")
state.Click(env.SmallerUIResourceDemo)
tick(0.11)
check(hud.player.health.fill:GetValue() == 2100, "Layout preview can demonstrate damage")
tick(0.9)
check(hud.player.health.fill:GetValue() == 4400, "Preview then demonstrates a heal")
env.SmallerUIResourceEditor:Hide()
check(not addon:IsEditingResources() and addon:GetResourceSettings().player.health.width == playerBefore
    and not hud.player:IsShown(), "Escape cancels sizing edits and removes temporary preview bars")
check(state.currentCategory == addon.resourceSettingsCategory, "Exiting edit mode returns to the correct native settings page")
state.Click(env.SmallerUIPersonalMove)
addon:ResizeResourceBars("player", "health", 360, 33)
addon:BeginResourceDrag(hud.player, "health")
hud.player.left, hud.player.bottom = 900, 300
addon:EndResourceDrag()
check(addon:GetResourceSettings().player.x ~= 0, "Dragging linked bars saves the group's screen-relative position")
state.Click(env.SmallerUIResourceDone)
check(addon:GetResourceSettings().player.health.width == 360 and not addon:IsEditingResources()
    and not hud.player.health.grip:IsShown(), "Done saves sizes and relocks the display")
local sameResources = boot(nil, env.SmallerUICharDB)
check(sameResources.SmallerUICharDB.resources.player.health.width == 360
    and sameResources.SmallerUICharDB.resources.player.x == addon:GetResourceSettings().player.x,
    "Resource layouts persist per character")
local freshResources = boot(nil)
check(freshResources.SmallerUICharDB.resources.player.health.width == 240,
    "Another character starts with its own independent layout")

state.Click(env.SmallerUIPersonalMove)
addon:ResizeResourceBars("player", "health", 700, 80)
state.combat = true
event("PLAYER_REGEN_DISABLED")
check(not addon:IsEditingResources() and addon:GetResourceSettings().player.health.width == 360
    and addon.pendingOptionsPage == "resources", "Combat safely cancels editing and defers reopening native settings")
addon:SetResourceOption("root", "enabled", true)
check(state.cvars.nameplateShowSelf == "1" and addon.resourceCVarPending,
    "Blizzard personal-display CVar changes are queued in combat")
state.units.player.health = 650
event("UNIT_HEALTH", "player")
check(hud.player.health.fill:GetValue() == 650, "Live health updates continue in combat")
check(not addon:BeginResourceEdit(), "Layout editing is unavailable during combat")
state.combat = false
event("PLAYER_REGEN_ENABLED"); tick()
check(state.cvars.nameplateShowSelf == "0" and not addon.resourceCVarPending
    and state.currentCategory == addon.resourceSettingsCategory, "Queued native changes and the settings page resume after combat")
event("PLAYER_LOGOUT")
check(state.cvars.nameplateShowSelf == "1" and env.SmallerUICharDB.originalSelfResourceCVar == nil,
    "Normal logout restores Blizzard's original personal resource setting")

local recoveredResources = boot(nil, { resources = { enabled = "yes", player = { scale = 0/0,
    health = { width = 1e20, height = -4 } } }, originalSelfResourceCVar = "invalid" })
check(not recoveredResources.SmallerUICharDB.resources.enabled
    and recoveredResources.SmallerUICharDB.resources.player.scale == 1
    and recoveredResources.SmallerUICharDB.resources.player.health.width == 8192
    and recoveredResources.SmallerUICharDB.resources.player.health.height == 2,
    "Invalid saved resource settings recover to finite usable bounds")
check(recoveredResources.SmallerUICharDB.originalSelfResourceCVar == nil, "Invalid saved CVar restore values are discarded")

local resizeEnv, resizeState, resizeEvent, resizeTick = boot(nil)
local resizeAddon = resizeState.addon
resizeAddon:ShowOptions("resources")
resizeState.Click(resizeEnv.SmallerUIPersonalMove)
local resizeHud = resizeAddon:GetResourceDisplay()
resizeState.mouseDown = true
resizeAddon:BeginResourceResize(resizeHud.player, "health")
resizeState.cursorX, resizeState.cursorY = 160, 89
resizeTick()
check(resizeAddon:GetResourceSettings().player.health.width == 300
    and resizeAddon:GetResourceSettings().player.health.height == 33,
    "Resize handles convert cursor motion into exact bar dimensions")
check(resizeAddon:GetResourceSettings().player.power.width == 300
    and resizeAddon:GetResourceSettings().player.power.height == 18,
    "Handle resizing preserves the linked bars' proportions")
resizeState.mouseDown = false
resizeTick()
resizeAddon:SetResourceOption("player", "linked", false)
local oldPowerY = resizeAddon:GetResourceSettings().player.power.y
resizeAddon:ResizeResourceBars("player", "health", 300, 50)
check(resizeAddon:GetResourceSettings().player.power.y == oldPowerY + 17,
    "Independent health resizing compensates the power position instead of pushing it away")
resizeAddon:SetResourceDimensions("player", { healthHeight = 60 })
check(resizeAddon:GetResourceSettings().player.power.y == oldPowerY + 27,
    "Exact independent health sizing also preserves the power position")
resizeAddon:BeginResourceDrag(resizeHud.player, "health")
resizeHud.player.left, resizeHud.player.bottom = 400, 400
resizeHud.player.health.left, resizeHud.player.health.bottom = 450, 420
resizeAddon:EndResourceDrag()
check(resizeAddon:GetResourceSettings().player.health.x == 50 and resizeAddon:GetResourceSettings().player.health.y == 20,
    "Unlinked dragging saves the individual bar's local position")
resizeAddon:FinishResourceEdit(true)
resizeAddon:SetResourceOption("root", "enabled", true)
resizeAddon:SetResourceOption("root", "smooth", false)
resizeState.units.player.health = 700
resizeEvent("UNIT_HEALTH", "player")
check(resizeHud.player.health.fill.interpolation == resizeEnv.Enum.StatusBarInterpolation.Immediate and resizeHud.player.health.trail:GetValue() == 700,
    "Turning smoothing off makes fills and trails update immediately")
resizeTick(0.3)
for _, widget in ipairs(resizeState.widgets) do
    if widget.events.UNIT_HEALTH then check(widget.scripts.OnUpdate == nil, "Idle displays stop their Lua animation update loop") end
end

resizeAddon:SetResourceOption("root", "smooth", true)
resizeState.units.player.health = 600
resizeEvent("UNIT_HEALTH", "player")
resizeTick(0.06)
resizeState.units.player.health = 500
resizeEvent("UNIT_HEALTH", "player")
resizeTick(0.07)
check(resizeHud.player.health.trail:GetValue() == 500,
    "Rapid damage does not postpone the health trail indefinitely")
resizeState.units.player.power, resizeState.units.player.powerMax = privateValue, privateValue
resizeEvent("UNIT_POWER_FREQUENT", "player")
check(resizeHud.player.power.fill:GetValue() == privateValue and resizeHud.player.power.fill.high == privateValue,
    "Restricted resource values use the same native rendering path as health")

local originalOff, originalOffState = boot(nil)
originalOffState.cvars.nameplateShowSelf = "0"
originalOffState.addon:SetResourceOption("root", "enabled", true)
originalOffState.addon:SetResourceOption("root", "enabled", false)
check(originalOffState.cvars.nameplateShowSelf == "0", "Restoring Blizzard preserves an originally disabled personal resource display")

local powerEnv, powerState, powerEvent, powerTick = boot(nil)
local powerAddon = powerState.addon
powerAddon:SetResourceOption("root", "enabled", true)
local powerHud = powerAddon:GetResourceDisplay()
local character = powerState.units.player
character.pools = { [0] = { value = 3600, maximum = 5000 }, [1] = { value = 35, maximum = 100 },
    [3] = { value = 80, maximum = 120 } }
local function Power(token, id, eventName, label, value, maximum)
    character.token = token
    powerEvent(eventName, "player", token)
    check(character.queriedPowerType == id and character.queriedMaxPowerType == id,
        label .. " queries the active power ID for both value and maximum")
    check(powerHud.player.power.fill:GetValue() == value and powerHud.player.power.fill.high == maximum
        and powerHud.player.power.label:GetText() == label, label .. " uses the right pool, range and label")
end
Power("RAGE", 1, "UNIT_DISPLAYPOWER", "Rage", 35, 100)
check(powerHud.player.power.fill.barColor[1] == 0.9, "Warrior Rage has its matching resource colour")
Power("ENERGY", 3, "UNIT_DISPLAYPOWER", "Energy", 80, 120)
check(powerHud.player.power.fill.barColor[2] == 0.8, "Rogue Energy supports an increased maximum")
Power("MANA", 0, "UPDATE_SHAPESHIFT_FORM", "Mana", 3600, 5000)
Power("ENERGY", 3, "UPDATE_SHAPESHIFT_FORM", "Energy", 80, 120)
character.pools[0].value = 3800
powerEvent("UNIT_POWER_UPDATE", "player", "MANA")
check(powerHud.player.power.fill:GetValue() == 80 and character.queriedPowerType == 3,
    "Cat form ignores hidden Mana regeneration and continues displaying Energy")
character.pools[3].value = 45
powerEvent("UNIT_POWER_FREQUENT", "player", "ENERGY")
check(powerHud.player.power.pendingAt ~= nil, "Current-pool changes can animate normally")
Power("RAGE", 1, "UNIT_POWER_UPDATE", "Rage", 35, 100)
check(powerHud.player.power.trail:GetValue() == 35 and powerHud.player.power.pendingAt == nil
    and powerHud.player.power.fill.interpolation == powerEnv.Enum.StatusBarInterpolation.Immediate,
    "Bear form resets the old pool's trail even if a power event precedes the form event")
powerTick(0.3)
check(powerHud.player.power.trail:GetValue() == 35, "A delayed Energy update cannot overwrite the new Rage trail")
Power("MANA", 0, "UNIT_DISPLAYPOWER", "Mana", 3800, 5000)
character.powerType, character.token = 17, "CUSTOM_POWER"
character.pools[17] = { value = 4, maximum = 6 }
character.red, character.green, character.blue = 0.7, 0.3, 0.6
powerEvent("UNIT_DISPLAYPOWER", "player")
check(powerHud.player.power.fill:GetValue() == 4 and powerHud.player.power.fill.barColor[3] == 0.6,
    "Unknown power tokens use the unit API's fallback colour and active pool")

local petEnv, petState, petEvent, petTick = boot(nil)
local petAddon = petState.addon
check(not petAddon:GetResourceSettings().petEnabled, "Pet display is disabled by default")
petAddon:ShowOptions("pet")
check(petState.currentCategory == petAddon.petSettingsCategory
    and petAddon.petSettingsCategory.parent == petAddon.settingsCategory, "Pet display has its own native settings page")
petState.Click(petEnv.SmallerUIPetEnabled)
local petHud, petCfg = petAddon:GetResourceDisplay(), petAddon:GetResourceSettings()
check(not petHud.pet:IsShown() and not petHud.player:IsShown() and not petHud.partyRoot:IsShown()
    and petState.cvarWrites == 0, "Pet-only mode waits for a pet and leaves the personal display setting alone")
petState.units.pet = { health = 1500, maximum = 2000, power = 65, powerMax = 100, token = "FOCUS", name = "Companion" }
petEvent("UNIT_PET", "player")
check(petHud.pet:IsShown() and petHud.pet.health.fill:GetValue() == 1500
    and petHud.pet.power.fill:GetValue() == 65, "Summoning a pet initializes its health and Focus")
check(petHud.pet.name:GetText() == "Companion" and petHud.pet.portrait.portraitUnit == "pet"
    and petHud.pet.power.label:GetText() == "Focus" and petState.units.pet.queriedPowerType == 2,
    "Hunter pet name, portrait and Focus power ID are correct")
petState.units.pet.health = 900
petEvent("UNIT_HEALTH", "pet")
check(petHud.pet.health.fill:GetValue() == 900 and petHud.pet.health.trail:GetValue() == 1500
    and petHud.pet.health.pulse.color[1] == 1, "Pet damage has the same responsive health feedback")
petTick(0.15)
check(petHud.pet.health.trail:GetValue() == 900, "Pet health trails catch up")
petState.units.pet.health = 1300
petEvent("UNIT_HEALTH", "pet")
check(petHud.pet.health.pulse.color[1] == 0.35, "Pet healing uses positive feedback")
petState.units.pet.name = "Renamed companion"
petEvent("UNIT_NAME_UPDATE", "pet")
check(petHud.pet.name:GetText() == "Renamed companion", "Pet names refresh after renaming")
petState.units.pet = { health = 2800, maximum = 3000, power = 1800, powerMax = 2500, token = "MANA", name = "Demon" }
petEvent("UNIT_PET", "player")
check(petHud.pet.health.trail:GetValue() == 2800 and petHud.pet.health.pendingAt == nil
    and petHud.pet.power.fill.high == 2500 and petHud.pet.power.fill:GetValue() == 1800
    and petHud.pet.power.label:GetText() == "Mana", "Replacing a pet resets health feedback and follows the new pet's Mana")
petState.units.pet.dead, petState.units.pet.health = true, 0
petEvent("UNIT_HEALTH", "pet")
check(petHud.pet:IsShown() and petHud.pet.health.valueText:GetText() == "Dead", "A dead pet keeps a clear status while its unit exists")
petState.units.pet = nil
petEvent("UNIT_PET", "player")
check(not petHud.pet:IsShown(), "Dismissing a pet immediately hides its display")
petState.Click(petEnv.SmallerUIPetEnabled)
petState.units.pet = { health = 1000, maximum = 1000, power = 0, powerMax = 0, token = "MANA", name = "Guardian" }
petEvent("UNIT_PET", "player")
check(not petHud.pet:IsShown(), "A disabled pet display stays hidden when a pet appears")
petState.Click(petEnv.SmallerUIPetEnabled)
check(petHud.pet:IsShown() and not petHud.pet.power:IsShown(), "Pets without a power pool show health without a misleading resource bar")
local noPowerHeight = petHud.pet:GetHeight()
petState.units.pet.powerMax, petState.units.pet.power, petState.units.pet.token = 100, 40, "FOCUS"
petEvent("UNIT_DISPLAYPOWER", "pet")
check(petHud.pet.power:IsShown() and petHud.pet:GetHeight() > noPowerHeight
    and petHud.pet.power.fill:GetValue() == 40, "A newly available pet power pool restores its bar and layout")
petState.combat = true
petEvent("PLAYER_REGEN_DISABLED")
petState.units.pet.health, petState.units.pet.power = 750, 25
petEvent("UNIT_HEALTH", "pet")
petEvent("UNIT_POWER_FREQUENT", "pet")
check(petHud.pet.health.fill:GetValue() == 750 and petHud.pet.power.fill:GetValue() == 25,
    "Pet health and power stay responsive during combat")
check(not petAddon:BeginResourceEdit(), "Pet layout editing waits until combat ends")
petState.combat = false
petEvent("PLAYER_REGEN_ENABLED")
petState.Click(petEnv.SmallerUIPetNames)
petState.Click(petEnv.SmallerUIPetPortraits)
check(not petHud.pet.name:IsShown() and not petHud.pet.portrait:IsShown()
    and petCfg.party.names and petCfg.party.portraits, "Pet appearance settings are independent of party settings")
petState.Click(petEnv.SmallerUIPetMove)
petAddon:BeginResourceDrag(petHud.pet, "health")
check(petAddon:GetResourceMoveState().target == petHud.pet,
    "Linked pet dragging moves only the pet group")
petHud.pet.left, petHud.pet.bottom = 460, 200
petAddon:EndResourceDrag()
local savedPetX, savedPetY = petCfg.pet.x, petCfg.pet.y
check(savedPetX ~= -170 and petCfg.player.x == 0 and petCfg.party.x == -420,
    "Pet position saves independently from player and party")
petState.mouseDown = true
petAddon:BeginResourceResize(petHud.pet, "health")
petState.cursorX, petState.cursorY = 160, 90
petTick()
check(petCfg.pet.health.width == 260 and petCfg.pet.health.height == 30
    and petCfg.pet.power.width == 260 and petCfg.pet.power.height == 15
    and petCfg.player.health.width == 240, "Pet handles resize its linked bars without affecting player bars")
petState.mouseDown = false
petTick()
petAddon:SetResourceOption("pet", "linked", false)
petAddon:ResizeResourceBars("pet", "power", 180, 18)
check(petCfg.pet.health.width == 260 and petCfg.pet.power.width == 180, "Unlinked pet bars resize independently")
petAddon:SetResourceDimensions("pet", { scale = 1.6, healthWidth = 310, healthHeight = 28, powerWidth = 280, powerHeight = 16 })
near(petHud.pet:GetEffectiveScale(), 1.6, "Pet scale is independent of global UI scaling")
petAddon:FinishResourceEdit(true)
check(petState.currentCategory == petAddon.petSettingsCategory, "Pet editing returns to the pet settings page")
local reloadedPet, reloadedPetState = boot(nil, petEnv.SmallerUICharDB)
check(reloadedPetState.addon:GetResourceSettings().pet.health.width == 310
    and reloadedPetState.addon:GetResourceSettings().pet.x == petCfg.pet.x,
    "Pet layout persists for the character")
petAddon:BeginResourceEdit()
petAddon:SetResourceDimensions("pet", { scale = 2 })
petAddon:FinishResourceEdit(false)
check(petAddon:GetResourceSettings().pet.scale == 1.6, "Cancel restores the previous pet layout")
petAddon:ResetResourceLayout("pet")
petCfg = petAddon:GetResourceSettings()
check(petCfg.pet.scale == 1 and petCfg.pet.x == -170 and not petCfg.pet.names and not petCfg.pet.portraits,
    "Pet reset restores geometry while preserving appearance choices")
petAddon:SetResourceOption("root", "petEnabled", false)
petState.units.pet = nil
petAddon:BeginResourceEdit()
check(petHud.pet:IsShown() and petHud.pet.name:GetText() == "Your pet"
    and petHud.pet.power.label:GetText() == "Focus", "Pet settings preview works without a summoned pet")
petAddon:FinishResourceEdit(true)
check(not petHud.pet:IsShown(), "Finishing a preview does not enable the pet display")
petAddon:ShowOptions("resources")
petAddon:BeginResourceEdit()
check(not petHud.pet:IsShown(), "Disabled pet bars do not clutter editing from other settings pages")
petAddon:FinishResourceEdit(true)
check(petState.cvarWrites == 0, "Pet settings and previews never alter Blizzard's personal resource preference")

local menuEnv, menuState, menuEvent, menuTick, menuCommand = boot(nil)
local menuAddon = menuState.addon
local menuRoot = menuAddon.settingsCategory
local expectedMenus = { "UI scaling", "Personal resources", "Party display", "Pet display", "Cooldown flashes" }
check(menuRoot.panel ~= menuEnv.SmallerUIOptions and menuRoot.alphabetical == false,
    "The parent is a navigation group and preserves the chosen child order")
for index, name in ipairs(expectedMenus) do
    check(menuRoot.subcategories[index].name == name, "Native settings entry " .. index .. " is " .. name)
end
menuEnv.SettingsPanel:Show()
menuEnv.SettingsPanel:SelectCategory(menuRoot)
menuTick()
check(menuState.currentCategory == menuAddon.scaleSettingsCategory and menuRoot:IsExpanded()
    and menuEnv.SmallerUIOptions:IsShown() and not menuRoot.panel:IsShown(),
    "Clicking the parent expands the group and selects the first child with scaling controls")
menuAddon:ShowOptions("cooldowns")
menuState.ToggleCategory(menuRoot)
menuTick()
check(not menuRoot:IsExpanded() and menuState.currentCategory == menuAddon.readySettingsCategory,
    "Collapsing the dropdown stays collapsed without changing the selected settings page")
menuState.pendingWoWSettings = true
menuState.ToggleCategory(menuRoot)
menuTick()
check(menuRoot:IsExpanded() and menuState.currentCategory == menuAddon.scaleSettingsCategory
    and menuState.pendingWoWSettings, "Expanding the dropdown selects scaling without reopening or discarding native settings")
menuState.ToggleCategory(menuRoot)
menuAddon:ShowOptions("pet")
menuTick()
check(menuState.currentCategory == menuAddon.petSettingsCategory,
    "Opening a specific child from a collapsed group preserves that requested page")
menuState.ToggleCategory(menuRoot)
menuState.ToggleCategory(menuRoot)
menuAddon:ShowOptions("party")
menuTick()
check(menuState.currentCategory == menuAddon.partySettingsCategory,
    "A pending default selection never overrides a newer navigation request")
menuState.ToggleCategory(menuRoot)
menuState.ToggleCategory(menuRoot)
menuEnv.SettingsPanel:Hide()
menuTick()
check(not menuEnv.SettingsPanel:IsShown(), "A queued dropdown selection never reopens closed settings")
menuCommand("")
menuTick()
check(menuState.currentCategory == menuAddon.scaleSettingsCategory and #menuState.categories == 6,
    "Slash access reuses the first child and never registers duplicate menus")

local forecastEnv, forecastState, forecastEvent, forecastTick = boot(nil, nil, { legacyCombatLog = true })
local forecastAddon = forecastState.addon
forecastAddon:SetResourceOption("root", "enabled", true)
local forecastHud = forecastAddon:GetResourceDisplay()
local forecasts = forecastHud.player.health.forecasts
forecastState.units.player.health, forecastState.units.player.incoming = 400, 250
forecastEvent("UNIT_HEAL_PREDICTION", "player")
check(forecasts.direct:IsShown() and forecasts.direct:GetValue() == 250 and forecasts.direct.high == 1000,
    "Incoming self/other healing renders as a separate segment without changing current health")
check(forecasts.clip.clipsChildren and forecasts.direct._points[1][2] == forecastHud.player.health.fill:GetStatusBarTexture(),
    "Prediction anchors start at the native health fill and clip at bar bounds")
forecastState.units.player.incoming = 900
forecastEvent("UNIT_HEAL_PREDICTION", "player")
check(forecasts.direct:GetValue() == 600, "Native prediction clamps overhealing to missing health")
forecastState.units.player.healAbsorb = 750
forecastEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player")
check(forecasts.direct:GetValue() == 150, "Native incoming prediction respects healing absorption")
forecastState.units.player.incoming, forecastState.units.player.healAbsorb = 0, 0
forecastEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
check(not forecasts.direct:IsShown() and forecasts.direct:GetValue() == 0, "Interrupting the incoming cast clears its preview")
forecastState.units.player.incoming = privateValue
forecastEvent("UNIT_HEAL_PREDICTION", "player")
check(forecasts.direct:IsShown() and forecasts.direct:GetValue() == privateValue,
    "Secret incoming amounts pass directly from the native calculator to the native prediction bar")
forecastAddon:SetResourceOption("root", "incomingHeals", false)
check(not forecasts.direct:IsShown(), "Incoming-healing previews can be independently disabled")
forecastState.units.player.incoming = 0
forecastAddon:SetResourceOption("root", "incomingHeals", true)
forecastState.auras.player = { HELPFUL = { { spellId = 139, sourceUnit = "player", expirationTime = forecastState.now + 20, auraInstanceID = 1 } },
    HARMFUL = { { spellId = 589, sourceUnit = "player", expirationTime = forecastState.now + 20, auraInstanceID = 2 } } }
local function Periodic(kind, spell, amount, source, destination)
    forecastState.combatLog = { forecastState.now, kind, false, source or "player-guid", "Source", 0, 0,
        destination or "player-guid", "Destination", 0, 0, spell, "Periodic spell", 2, amount }
    forecastEvent("COMBAT_LOG_EVENT_UNFILTERED")
end
Periodic("SPELL_PERIODIC_HEAL", 139, 100)
check(not forecasts.hot:IsShown(), "HoT estimates wait for observed tick spacing instead of inventing a tick rate")
forecastTick(2)
Periodic("SPELL_PERIODIC_HEAL", 139, 100)
check(forecasts.hot:IsShown() and forecasts.hot:GetValue() == 200,
    "Two observed HoT ticks produce a five-second estimate of the next two ticks")
check(forecasts.hot._points[1][2] == forecasts.direct:GetStatusBarTexture(),
    "Periodic healing follows the direct-heal segment rather than covering it")
forecastTick(2)
Periodic("SPELL_PERIODIC_HEAL", 139, 200)
check(forecasts.hot:GetValue() == 300, "Recent observed tick sizes update the periodic estimate")
forecastState.auras.player.HELPFUL[1].expirationTime = forecastState.now + 1
forecastEvent("UNIT_AURA", "player")
check(not forecasts.hot:IsShown(), "Changing an aura's application clears its old tick estimate")
forecastState.auras.player.HELPFUL[1].expirationTime = forecastState.now + 20
Periodic("SPELL_PERIODIC_HEAL", 139, 100)
forecastTick(2)
Periodic("SPELL_PERIODIC_HEAL", 139, 100)
check(forecasts.hot:GetValue() == 200, "Fresh ticks relearn the refreshed HoT")
forecastState.auras.player.HELPFUL = {}
forecastEvent("UNIT_AURA", "player")
check(not forecasts.hot:IsShown(), "Removing a HoT immediately clears the estimate")
forecastAddon:SetResourceOption("root", "periodicDamage", true)
Periodic("SPELL_PERIODIC_DAMAGE", 589, 75)
forecastTick(2)
Periodic("SPELL_PERIODIC_DAMAGE", 589, 75)
check(forecasts.dot:IsShown() and forecasts.dot:GetValue() == 150 and forecasts.dot.reverseFill,
    "Optional DoT prediction shades expected loss backwards from current health")
forecastState.logRestricted = true
forecastTick(0.3)
check(not forecasts.dot:IsShown(), "Restricted combat information clears periodic estimates without secret arithmetic")
forecastState.logRestricted = false
forecastState.auras.player.HARMFUL[1].expirationTime = forecastState.now + 2
forecastEvent("UNIT_AURA", "player")
Periodic("SPELL_PERIODIC_DAMAGE", 589, 75)
forecastTick(0.5)
Periodic("SPELL_PERIODIC_DAMAGE", 589, 75)
check(forecasts.dot:GetValue() == 225, "Periodic forecasts count only ticks due before aura expiration")
forecastTick(2)
check(not forecasts.dot:IsShown() and not forecastHud.player.forecastActive,
    "A periodic forecast expires even if no removal event is delivered")
forecastState.auras.player.HARMFUL = {}
forecastEvent("UNIT_AURA", "player")
Periodic("SPELL_PERIODIC_DAMAGE", 589, privateValue)
check(not forecasts.dot:IsShown(), "Secret tick amounts are not learned or estimated")
forecastAddon:SetResourceOption("root", "partyEnabled", true)
forecastAddon:SetResourceOption("root", "petEnabled", true)
forecastState.units.party1 = { health = 500, maximum = 1500, power = 10, powerMax = 100, token = "MANA", name = "Healer", incoming = 200 }
forecastState.units.pet = { health = 800, maximum = 1000, power = 10, powerMax = 100, token = "FOCUS", name = "Pet", incoming = 150 }
forecastEvent("GROUP_ROSTER_UPDATE")
check(forecastHud.party[1].health.forecasts.direct:GetValue() == 200 and forecastHud.pet.health.forecasts.direct:GetValue() == 150,
    "Native incoming-healing previews also work for party members and pets")
forecastState.units.pet.dead = true
forecastEvent("UNIT_HEAL_PREDICTION", "pet")
check(not forecastHud.pet.health.forecasts.direct:IsShown(), "Dead units do not retain an incoming-heal preview")
local fallbackEnv, fallbackState, fallbackEvent = boot(nil)
fallbackState.addon:SetResourceOption("root", "enabled", true)
local fallbackHud = fallbackState.addon:GetResourceDisplay()
fallbackHud.player.healCalculator = nil
fallbackState.units.player.incoming = privateValue
fallbackEvent("UNIT_HEAL_PREDICTION", "player")
check(fallbackHud.player.health.forecasts.direct:GetValue() == privateValue,
    "Clients without a prediction calculator retain the direct native amount renderer")

local sealEnv, sealState, sealEvent, sealTick = boot(nil)
local sealAddon = sealState.addon
sealState.class = "PALADIN"
sealAddon:SetResourceOption("root", "enabled", true)
local sealHud, sealCfg = sealAddon:GetResourceDisplay(), sealAddon:GetResourceSettings()
local sealIcon = sealHud.player.seal
check(sealIcon:IsShown() and sealIcon.status == "missing" and sealIcon.reminder:GetText() == "!",
    "Paladins receive a missing-seal reminder before their first observed seal")
sealState.auras.player = { HELPFUL = { { spellId = 20154, name = "Seal of Righteousness", icon = 1234 } } }
sealEvent("UNIT_AURA", "player")
check(sealIcon.status == "active" and sealIcon.texture.textureValue == 1234 and not sealIcon.texture.desaturated
    and sealCfg.seal.lastSpellID == 20154, "Active Paladin seals display their own icon and remember their identity")
sealState.auras.player.HELPFUL[1].icon = privateValue
sealEvent("UNIT_AURA", "player")
check(sealIcon.texture.textureValue == privateValue and sealCfg.seal.lastSpellID == 20154,
    "Restricted icon artwork passes straight to the native texture without being saved")
sealState.auras.player.HELPFUL = {}
sealEvent("UNIT_AURA", "player")
check(sealIcon.status == "missing" and sealIcon.texture.desaturated and sealIcon.texture:GetAlpha() == 0.45
    and sealIcon.texture.textureValue == 21154, "An expired seal becomes a grey version of the remembered seal")
sealState.spellInfo = { [20287] = { name = "Seal of Righteousness", iconID = 1234 } }
sealState.auras.player.HELPFUL = { { spellId = 20287, name = "Seal of Righteousness", icon = 1234 } }
sealEvent("UNIT_AURA", "player")
check(sealIcon.status == "active" and sealCfg.seal.lastSpellID == 20287,
    "Higher seal ranks are recognized through localized spell names")
sealState.spellInfo[20154] = { name = "Localized seal", iconID = 1234 }
sealState.spellInfo[20287].name = "Localized seal"
sealState.auras.player.HELPFUL[1].name = "Localized seal"
sealEvent("SPELLS_CHANGED")
check(sealIcon.status == "active", "Seal detection does not rely on English spell names")
sealState.auraUnavailable = true
sealEvent("UNIT_AURA", "player")
check(sealIcon.status == "unknown" and sealIcon.reminder:GetText() == "?",
    "Unreadable aura status is distinguished from a confirmed missing seal")
sealState.auraUnavailable = false
sealState.auras.player.HELPFUL = { { spellId = privateValue, name = privateValue, icon = privateValue } }
sealEvent("UNIT_AURA", "player")
check(sealIcon.status == "unknown" and sealCfg.seal.lastSpellID == 20287,
    "Secret aura identity is never compared, indexed or saved")
sealState.auras.player.HELPFUL = {}
sealEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 20375)
check(sealCfg.seal.lastSpellID == 20375, "A successfully cast seal can supply the last-used reminder")
sealAddon:SetResourceOption("seal", "enabled", false)
check(not sealIcon:IsShown(), "The seal indicator can be disabled")
sealAddon:SetResourceOption("seal", "enabled", true)
sealAddon:ShowOptions("resources")
sealAddon:BeginResourceEdit()
sealIcon.scripts.OnDragStart(sealIcon)
sealIcon.left, sealIcon.bottom = 300, 25
sealHud.player.health.left, sealHud.player.health.bottom = 20, 30
sealHud.player.power.bottom = 14
sealIcon.scripts.OnDragStop(sealIcon)
check(sealCfg.seal.x == 40 and sealCfg.seal.y == 8 and sealCfg.player.x == 0,
    "Dragging the seal saves a separate offset relative to the combined bar centre")
sealAddon:FinishResourceEdit(true)
check(sealAddon:SetResourceDimensions("seal", { x = -15, y = 24, size = 48 })
    and sealIcon:GetWidth() == 48, "Seal size and both offsets can be set exactly")
sealAddon:BeginResourceEdit()
sealAddon:SetResourceDimensions("seal", { x = 80 })
sealAddon:FinishResourceEdit(false)
check(sealAddon:GetResourceSettings().seal.x == -15, "Cancelling edit restores the previous seal position")
local rememberedSeal, rememberedSealState = boot(nil, sealEnv.SmallerUICharDB)
check(rememberedSealState.addon:GetResourceSettings().seal.lastSpellID == 20375
    and rememberedSealState.addon:GetResourceSettings().seal.size == 48,
    "Last seal and icon layout persist for the character")
sealState.class = "WARRIOR"
sealEvent("PLAYER_ENTERING_WORLD")
check(not sealIcon:IsShown(), "Other classes do not receive a Paladin seal icon")

do
    local env, state, event, tick = boot(nil)
    state.class = "PALADIN"
    local addon = state.addon
    addon:SetResourceOption("root", "enabled", true)
    local cfg = addon:GetResourceSettings()
    local icon = addon:GetResourceDisplay().player.seal
    state.auras.player = { HELPFUL = { { spellId = 20287, name = "Seal of Righteousness", icon = 1234 } } }
    event("UNIT_AURA", "player")
    state.spellInfo = { [20162] = { name = "Seal of the Crusader", iconID = 4321 } }
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 20162)
    check(cfg.seal.lastSpellID == 20162, "A Crusader rank cast is remembered even while the previous seal remains in the aura snapshot")
    state.auras.player.HELPFUL = { { spellId = 20162, name = "Seal of the Crusader", icon = 4321 } }
    event("UNIT_AURA", "player")
    check(icon.status == "active" and icon.texture.textureValue == 4321 and not icon.texture.desaturated and icon.texture:GetAlpha() == 1,
        "Switching Righteousness to Crusader replaces the active icon immediately on its aura update")
    state.auras.player.HELPFUL = {
        { spellId = 20287, name = "Seal of Righteousness", icon = 1234 },
        { spellId = 20162, name = "Seal of the Crusader", icon = 4321 },
    }
    event("UNIT_AURA", "player")
    check(icon.texture.textureValue == 4321 and cfg.seal.lastSpellID == 20162,
        "An overlapping old seal cannot take priority over the most recently cast active seal")
    state.auras.player.HELPFUL = {}
    event("UNIT_AURA", "player")
    check(icon.status == "missing" and icon.texture.desaturated and icon.texture.textureValue == 4321,
        "After Crusader expires the reminder greys the new seal rather than the original Righteousness icon")
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "recast-guid", 20162)
    event("UNIT_AURA", "player") -- Both events still see the old, empty aura list.
    tick(0.02)
    check(icon.status == "missing", "A cast alone does not confirm that the seal buff is active")
    state.auras.player.HELPFUL = { { spellId = 20162, name = "Seal of the Crusader", icon = 4321 } }
    tick(0.12)
    check(icon.status == "active" and icon.texture.textureValue == 4321 and not icon.texture.desaturated,
        "Recasting the same seal recovers when the aura appears after the last event")
    state.auras.player.HELPFUL = {}
    event("UNIT_AURA", "player")
    check(icon.status == "missing" and icon.texture.textureValue == 4321,
        "Removing the reapplied seal immediately restores its reminder during the recheck window")
    tick(1.1)
    state.auras.player.HELPFUL = { { spellId = 20162, name = "Seal of the Crusader", icon = 4321 } }
    tick(0.2)
    check(icon.status == "missing", "Seal rechecks stop after the short post-cast window")
    state.auras.player.HELPFUL = {}
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "restricted-cast", privateValue)
    state.auras.player.HELPFUL = { { spellId = 20162, name = "Seal of the Crusader", icon = 4321 } }
    tick(0.12)
    check(icon.status == "active" and cfg.seal.lastSpellID == 20162,
        "A late readable aura confirms a recast even if the cast ID is restricted")
    state.spellInfo[21082] = { name = "Localized Crusader", iconID = 4321 }
    state.spellInfo[20305] = { name = "Localized Crusader", iconID = 5432 }
    event("SPELLS_CHANGED")
    state.auras.player.HELPFUL = { { spellId = 20305, name = "Localized Crusader", icon = 5432 } }
    event("UNIT_AURA", "player")
    check(icon.status == "active" and cfg.seal.lastSpellID == 20305 and icon.texture.textureValue == 5432,
        "Other Crusader ranks are detected with localized family names")
    state.auras.player.HELPFUL = { { spellId = 20163, name = privateValue, icon = 6543 } }
    event("UNIT_AURA", "player")
    check(icon.status == "active" and cfg.seal.lastSpellID == 20163 and icon.texture.textureValue == 6543,
        "A known Fury identity is sufficient when its display name is restricted")
    addon:SetResourceOption("seal", "enabled", false)
    event("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", 21082)
    check(cfg.seal.lastSpellID == 21082 and not icon:IsShown(), "Disabled seal indicators still remember newly cast seal families")
end

local stepEnv, stepState, stepEvent, stepTick = boot(nil)
local stepAddon = stepState.addon
stepAddon:ShowOptions("resources")
local widthInput, heightInput, scaleInput = stepEnv.SmallerUIPersonalhealthWidth, stepEnv.SmallerUIPersonalhealthHeight, stepEnv.SmallerUIPersonalscale
stepState.Click(widthInput.up)
check(stepAddon:GetResourceSettings().player.health.width == 241 and widthInput:GetText() == "241.00",
    "A dimension up arrow saves a one-pixel increase immediately")
stepState.Click(widthInput.down)
check(stepAddon:GetResourceSettings().player.health.width == 240, "A down arrow decrements only its own field")
stepState.Click(scaleInput.up)
near(stepAddon:GetResourceSettings().player.scale, 1.01, "Scale arrows use a precise 0.01 step")
stepState.mouseDown = true
heightInput.up.scripts.OnMouseDown(heightInput.up, "LeftButton")
check(stepAddon:GetResourceSettings().player.health.height == 23, "Holding begins with an immediate single adjustment")
stepTick(0.2)
check(stepAddon:GetResourceSettings().player.health.height == 23, "Holding waits briefly before repeating")
stepTick(0.16)
stepTick(0.08)
check(stepAddon:GetResourceSettings().player.health.height == 25, "A held arrow repeats after its initial delay")
stepState.mouseDown = false
heightInput.up.scripts.OnMouseUp(heightInput.up, "LeftButton")
heightInput.up.scripts.OnClick(heightInput.up, "LeftButton")
stepTick(0.5)
check(stepAddon:GetResourceSettings().player.health.height == 25 and not heightInput.up.scripts.OnUpdate,
    "Releasing stops repetition and the release click does not double-step")
heightInput:SetText("2")
stepState.Click(heightInput.down)
check(stepAddon:GetResourceSettings().player.health.height == 2, "Fine-tuning respects the minimum dimension")
widthInput:SetText("8192")
stepState.Click(widthInput.up)
check(stepAddon:GetResourceSettings().player.health.width == 8192, "Fine-tuning respects the maximum dimension")
widthInput:SetText("bad")
stepState.Click(widthInput.down)
check(stepAddon:GetResourceSettings().player.health.width == 8191, "An invalid draft recovers from the saved value when stepping")
stepState.Click(stepEnv.SmallerUIPersonalSealx.down)
check(stepAddon:GetResourceSettings().seal.x == 7, "Seal offsets use the same arrow controls")
stepState.mouseDown = true
scaleInput.up.scripts.OnMouseDown(scaleInput.up, "LeftButton")
scaleInput.up:Hide()
stepTick(1)
check(not scaleInput.up.scripts.OnUpdate and not scaleInput.up.mouseStepped,
    "Hiding a held arrow immediately cancels its repeat handler")

local migratedForecasts, migratedForecastState = boot(nil, { resources = {
    enabled = true, player = { health = { width = 380 } }, seal = { x = 0/0, size = math.huge, lastSpellID = privateValue }
} })
local migrated = migratedForecastState.addon:GetResourceSettings()
check(migrated.player.health.width == 380 and migrated.incomingHeals and migrated.periodicHeals and not migrated.periodicDamage
    and migrated.seal.x == 8 and migrated.seal.size == 32 and migrated.seal.lastSpellID == 0,
    "Older or corrupt saved layouts migrate without losing dimensions or retaining restricted seal data")

do
    local liveEnv, liveState, liveEvent, liveTick = boot(nil)
    local liveAddon = liveState.addon
    liveAddon:SetResourceOption("root", "enabled", true)
    liveAddon:SetResourceOption("root", "partyEnabled", true)
    liveAddon:SetResourceOption("root", "petEnabled", true)
    liveState.units.party1 = { health = 1000, maximum = 1000, power = 100, powerMax = 100, token = "MANA", name = "Party" }
    liveState.units.pet = { health = 1000, maximum = 1000, power = 100, powerMax = 100, token = "FOCUS", name = "Pet" }
    liveEvent("GROUP_ROSTER_UPDATE")
    local liveHud = liveAddon:GetResourceDisplay()
    local views = { player = liveHud.player, party1 = liveHud.party[1], pet = liveHud.pet }
    local oldPrediction = liveEnv.UnitGetDetailedHealPrediction
    local expectedUnit
    liveEnv.UnitGetDetailedHealPrediction = function(unit, healer, calculator)
        if expectedUnit == unit then
            assert(views[unit].health.fill:GetInterpolatedValue() == liveState.units[unit].health,
                "Forecast work ran before the current health fill was displayed")
            assert(views[unit].health.valueText:GetText() == string.format("%d / %d", liveState.units[unit].health, liveState.units[unit].maximum),
                "Forecast work ran before the current HP number was displayed")
        end
        return oldPrediction(unit, healer, calculator)
    end
    liveState.combat = true
    liveEvent("PLAYER_REGEN_DISABLED")
    local startTime = liveState.now
    for unit, view in pairs(views) do
        expectedUnit = unit
        for index = 1, 200 do
            local value = (index * 137) % 1001
            liveState.units[unit].health = value
            liveEvent("UNIT_HEALTH", unit)
            assert(view.health.fill:GetValue() == value and view.health.fill:GetInterpolatedValue() == value
                and view.health.fill.interpolation == liveEnv.Enum.StatusBarInterpolation.Immediate,
                "Rapid " .. unit .. " health changes waited for animation or a timer")
            assert(view.health.valueText:GetText() == value .. " / 1000", "HP text disagreed with the live fill")
        end
        check(view.health.fill:GetInterpolatedValue() == liveState.units[unit].health,
            unit .. " damage/healing bursts display every event immediately, before forecasts")
    end
    expectedUnit = nil
    check(liveState.now == startTime, "All 600 rapid health events completed without any frame/timer advancement")
    liveState.units.player.health, liveState.units.player.maximum = 1, 2000000
    liveEvent("UNIT_HEALTH", "player")
    check(liveHud.player.health.fill:GetInterpolatedValue() == 1 and liveHud.player.health.fill.high == 2000000
        and liveHud.player.health.valueText:GetText() == "1 / 2000000", "Critical HP uses the newest maximum even before a separate max-health event")
    liveState.units.player.maximum = 2400000
    liveEvent("UNIT_MAXHEALTH", "player")
    check(liveHud.player.health.fill:GetInterpolatedValue() == 1 and liveHud.player.health.trail:GetInterpolatedValue() == 1
        and liveHud.player.health.fill.high == 2400000, "Max-health changes immediately update the range and clear old trails")
    liveState.units.player.health, liveState.units.player.dead = 0, true
    liveEvent("UNIT_HEALTH", "player")
    check(liveHud.player.health.fill:GetInterpolatedValue() == 0 and liveHud.player.health.valueText:GetText() == "Dead",
        "Fatal damage empties current HP immediately even while an old trail exists")
    check(liveHud.player.health.pulse.allPoints == liveHud.player.health.fill:GetStatusBarTexture(),
        "Damage/heal tint is confined to the current fill and cannot paint empty HP as filled")
    liveState.units.player.health, liveState.units.player.dead = 100, false
    liveEvent("PLAYER_ALIVE")
    check(liveHud.player.health.fill:GetInterpolatedValue() == 100, "Resurrection immediately restores current HP")
    liveState.units.player.health, liveState.units.player.maximum = privateValue, privateValue
    liveEvent("UNIT_HEALTH", "player")
    check(liveHud.player.health.fill:GetInterpolatedValue() == privateValue
        and liveHud.player.health.fill.interpolation == liveEnv.Enum.StatusBarInterpolation.Immediate
        and liveHud.player.health.valueText.formatArgs[1] == privateValue,
        "Restricted health and text retain immediate native rendering in combat")
    liveState.units.player.health, liveState.units.player.maximum = 250, 1000
    liveEvent("UNIT_HEALTH", "player")
    liveTick(1)
    check(liveHud.player.health.fill:GetInterpolatedValue() == 250 and liveHud.player.health.valueText:GetText() == "250 / 1000",
        "Delayed trail animation cannot overwrite current HP or its number")
    liveState.units.player.power = 30
    liveEvent("UNIT_POWER_FREQUENT", "player")
    check(liveHud.player.power.fill:GetInterpolatedValue() == 30
        and liveHud.player.power.fill.interpolation == liveEnv.Enum.StatusBarInterpolation.Immediate,
        "Current Mana/Energy/Rage also updates without a visual interpolation delay")
    liveState.combat = false
    liveEvent("PLAYER_REGEN_ENABLED")
    liveAddon:ShowOptions("resources")
    liveAddon:BeginResourceEdit()
    liveAddon:TestResourceDamage()
    liveTick(0.2)
    check(liveHud.player.health.fill:GetInterpolatedValue() == 2100, "The explicit edit-mode damage demo still works")
    liveState.units.player.health = 42
    liveEvent("UNIT_HEALTH", "player")
    check(liveHud.player.health.fill:GetInterpolatedValue() == 42 and liveHud.player.health.valueText:GetText() == "42 / 1000",
        "Real health interrupts a preview immediately, including damage outside combat")
    liveTick(1)
    check(liveHud.player.health.fill:GetInterpolatedValue() == 42, "An old demo heal cannot overwrite real HP after interruption")
    liveAddon:FinishResourceEdit(true)

    -- Resolve horizontal native anchor constraints in physical pixels. Different
    -- bar heights and fractional scales must still give identical left/right edges.
    local Horizontal
    Horizontal = function(widget)
        if widget.allPoints then return Horizontal(widget.allPoints) end
        local scale = widget:GetEffectiveScale()
        local width = widget:GetWidth() * scale
        local points = widget._points
        if not points or #points == 0 then return (widget.left or 0) * scale, width end
        local function Constraint(point)
            local relative, relativePoint, offset
            if type(point[2]) == "table" then relative, relativePoint, offset = point[2], point[3], point[4] or 0
            else relative, relativePoint, offset = widget:GetParent(), point[1], point[2] or 0 end
            local left, span = Horizontal(relative)
            local fraction = relativePoint:find("RIGHT") and 1 or relativePoint:find("LEFT") and 0 or 0.5
            return left + span * fraction + offset * scale
        end
        local first = points[1]
        local position = Constraint(first)
        if #points == 2 then
            local other = Constraint(points[2])
            return position, other - position
        end
        local fraction = first[1]:find("RIGHT") and 1 or first[1]:find("LEFT") and 0 or 0.5
        return position - width * fraction, width
    end
    for _, scale in ipairs({ 0.5, 0.67, 0.8, 1, 1.25 }) do
        liveAddon:SetResourceDimensions("player", { healthWidth = 280, powerWidth = 280,
            healthHeight = 15, powerHeight = 12, gap = 0, scale = scale })
        local leftHP, widthHP = Horizontal(liveHud.player.health)
        local leftPower, widthPower = Horizontal(liveHud.player.power)
        check(math.abs(leftHP - leftPower) < 0.00001 and math.abs(widthHP - widthPower) < 0.00001,
            "Equal-width outer bars share both physical edges at scale " .. scale)
        leftHP, widthHP = Horizontal(liveHud.player.health.fill)
        leftPower, widthPower = Horizontal(liveHud.player.power.fill)
        check(math.abs(leftHP - leftPower) < 0.00001 and math.abs(widthHP - widthPower) < 0.00001,
            "Equal-width live fills use identical inner edges at scale " .. scale)
    end
    liveAddon:SetResourceOption("player", "linked", false)
    liveAddon:GetResourceSettings().player.power.x = 17
    liveAddon:SetResourceDimensions("player", { powerWidth = 190, scale = 0.8 })
    local hpLeft = Horizontal(liveHud.player.health)
    local powerLeft, powerWidth = Horizontal(liveHud.player.power)
    check(math.abs(powerLeft - hpLeft - 17 * 0.8) < 0.00001 and math.abs(powerWidth - 190 * 0.8) < 0.00001,
        "Independent positions and deliberately different widths remain available")
end

do
    local colourEnv, colourState, colourEvent = boot(nil)
    local colourAddon = colourState.addon
    colourAddon:SetResourceOption("root", "enabled", true)
    colourAddon:SetResourceOption("root", "partyEnabled", true)
    colourAddon:SetResourceOption("root", "petEnabled", true)
    colourState.units.party1 = { health = 800, maximum = 1000, power = 50, powerMax = 100, token = "RAGE", name = "Party" }
    colourState.units.pet = { health = 500, maximum = 1000, power = 20, powerMax = 100, token = "FOCUS", name = "Pet" }
    colourEvent("GROUP_ROSTER_UPDATE")
    local colourHud, cfg = colourAddon:GetResourceDisplay(), colourAddon:GetResourceSettings()
    check(colourHud.player.health.fill.barColor[1] == 0.85 and colourHud.player.health.fill.barColor[2] == 0.15
        and colourHud.party[1].health.fill.barColor[1] == 0.85 and colourHud.pet.health.fill.barColor[1] == 0.85,
        "Health defaults to red for personal, party and pet displays")
    check(colourHud.player.power.fill.barColor[3] == 0.95 and colourHud.party[1].power.fill.barColor[1] == 0.9
        and colourHud.pet.power.fill.barColor[2] == 0.5, "Default power colours follow each individual unit's active resource")
    colourAddon:ShowOptions("resources")
    colourState.Click(colourEnv.SmallerUIPersonalhealthColour)
    check(colourEnv.ColorPickerFrame:IsShown() and cfg.player.colours.health.r == 0.85,
        "The native colour picker opens without treating initialization as a choice")
    local calls = colourHud.player.health.fill.valueCalls
    colourState.PickColour(0.1, 0.6, 0.8)
    check(colourHud.player.health.fill.barColor[1] == 0.1 and colourHud.player.health.fill.barColor[3] == 0.8
        and colourHud.player.health.fill.valueCalls == calls, "Colour previews update paint without rewriting HP or restarting its live rendering")
    check(colourHud.player.health.forecasts.direct.barColor[1] > 0.1
        and colourHud.player.health.forecasts.direct.barColor[2] > 0.6,
        "Incoming-heal previews use a lighter shade of the chosen health colour")
    colourEnv.ColorPickerFrame:OnCancel()
    check(cfg.player.colours.health.r == 0.85 and colourHud.player.health.fill.barColor[1] == 0.85,
        "Cancelling the native picker restores the prior health colour")
    colourState.Click(colourEnv.SmallerUIPersonalhealthColour)
    colourState.PickColour(0.2, 0.7, 0.3)
    colourEnv.ColorPickerFrame:OnOkay()
    colourAddon:ShowOptions("party")
    check(cfg.player.colours.health.r == 0.2 and cfg.party.colours.health.r == 0.85,
        "Confirmed colours survive navigation and stay independent per display")
    colourAddon:ShowOptions("resources")
    colourState.units.player.token = "RAGE"
    colourEvent("UNIT_DISPLAYPOWER", "player")
    colourState.Click(colourEnv.SmallerUIPersonalpowerColour)
    check(cfg.player.colours.powerByType and colourEnv.ColorPickerFrame.rgb[1] == 0.9,
        "The power picker opens at the active type colour without disabling automatic colours")
    colourState.PickColour(0.7, 0.2, 0.9)
    check(not cfg.player.colours.powerByType and not colourEnv.SmallerUIPersonalPowerByType:GetChecked()
        and colourHud.player.power.fill.barColor[3] == 0.9,
        "Choosing a custom power colour switches this display to its custom palette")
    colourEnv.ColorPickerFrame:OnCancel()
    check(cfg.player.colours.powerByType and colourHud.player.power.fill.barColor[1] == 0.9,
        "Cancelling a power colour restores automatic resource colouring")
    colourState.Click(colourEnv.SmallerUIPersonalpowerColour)
    colourState.PickColour(0.7, 0.2, 0.9)
    colourEnv.ColorPickerFrame:OnOkay()
    colourState.units.player.token = "ENERGY"
    colourEvent("UNIT_DISPLAYPOWER", "player")
    check(colourHud.player.power.fill.barColor[3] == 0.9 and colourHud.player.power.label:GetText() == "Energy",
        "A chosen custom power colour remains stable while resource values and labels still follow form changes")
    colourState.Click(colourEnv.SmallerUIPersonalPowerByType)
    check(colourHud.player.power.fill.barColor[1] == 1 and colourHud.player.power.fill.barColor[2] == 0.8,
        "Automatic power colours can be re-enabled after a custom choice")
    colourState.Click(colourEnv.SmallerUIPersonalPowerByType)
    check(colourHud.player.power.fill.barColor[3] == 0.9, "The custom power colour is retained when switching automatic colours on and off")
    colourAddon:SetResourceDimensions("player", { healthWidth = 370 })
    colourState.Click(colourEnv.SmallerUIPersonalResetColours)
    check(cfg.player.colours.health.r == 0.85 and cfg.player.colours.powerByType
        and colourHud.player.power.fill.barColor[2] == 0.8 and cfg.player.health.width == 370,
        "Restore defaults resets only colours to red health and resource-type power")
    colourAddon:SetResourceColour("party", "health", 0.3, 0.4, 0.5)
    colourAddon:SetResourceColour("pet", "power", 0.9, 0.8, 0.2)
    colourAddon:ResetResourceLayout("party")
    check(cfg.party.colours.health.r == 0.3 and cfg.pet.colours.power.r == 0.9,
        "Reset layout preserves chosen colours for party and pet displays")
    colourState.combat = true
    colourAddon:SetResourceColour("player", "health", 0.8, 0.2, 0.4)
    colourState.units.player.health = 12
    colourEvent("UNIT_HEALTH", "player")
    check(colourHud.player.health.fill:GetInterpolatedValue() == 12
        and colourHud.player.health.fill.interpolation == colourEnv.Enum.StatusBarInterpolation.Immediate,
        "Custom colours keep current HP immediate during combat")
    check(not colourAddon:SetResourceColour("player", "health", 0/0, 0.5, 0.5)
        and not colourAddon:SetResourceColour("player", "health", 1.1, 0, 0)
        and not colourAddon:SetResourceColour("seal", "health", 1, 0, 0), "Invalid colour input is rejected atomically")
    colourState.combat = false
    colourState.Click(colourEnv.SmallerUIPersonalhealthColour)
    colourState.PickColour(0.1, 0.1, 0.1)
    colourAddon:ShowOptions("pet")
    check(not colourEnv.ColorPickerFrame:IsShown() and cfg.player.colours.health.r == 0.8,
        "Leaving a settings page cancels an unconfirmed colour preview")
    local reloaded, reloadedState = boot(nil, colourEnv.SmallerUICharDB)
    check(reloadedState.addon:GetResourceSettings().player.colours.health.r == 0.8
        and reloadedState.addon:GetResourceSettings().pet.colours.power.r == 0.9,
        "Colour choices persist per character")
    local migrated, migratedState = boot(nil, { resources = { player = { health = { width = 333 },
        colours = { health = { r = math.huge, g = -1, b = 4 }, power = false } } } })
    local migratedColours = migratedState.addon:GetResourceSettings().player
    check(migratedColours.health.width == 333 and migratedColours.colours.health.r == 0.85
        and migratedColours.colours.health.g == 0 and migratedColours.colours.health.b == 1
        and migratedColours.colours.powerByType, "Old layouts and malformed colour values migrate to usable bounded defaults")
end

do
    local styleEnv, styleState, styleEvent, styleTick = boot(nil)
    local styleAddon = styleState.addon
    styleAddon:SetResourceOption("root", "enabled", true)
    styleAddon:ShowOptions("resources")
    local styleHud, styleCfg = styleAddon:GetResourceDisplay(), styleAddon:GetResourceSettings()
    local bar = styleHud.player.health
    local originalHeight = styleEnv.SmallerUIPersonalOptions.content:GetHeight()
    check(not styleEnv.SmallerUIPersonalTextSettings:IsShown() and not styleEnv.SmallerUIPersonalResourceColours:IsShown(),
        "Advanced text and resource-colour controls start collapsed")
    styleState.Click(styleEnv.SmallerUIPersonalTextToggle)
    check(styleEnv.SmallerUIPersonalTextSettings:IsShown() and styleEnv.SmallerUIPersonalOptions.content:GetHeight() == originalHeight + 224,
        "Opening text controls reflows following sections without overlapping")
    styleState.units.player.health, styleState.units.player.maximum = 420, 1000
    styleEvent("UNIT_HEALTH", "player")
    local calls = bar.fill.valueCalls
    for _, example in ipairs({ { 1, "420" }, { 2, "420 / 1000" }, { 3, "42%" },
        { 4, "420 (42%)" }, { 5, "420 / 1000 (42%)" } }) do
        styleState.Select(styleEnv.SmallerUIPersonalhealthFormat, example[1])
        check(bar.valueText:GetText() == example[2], "Health text format renders " .. example[2])
    end
    check(bar.fill.valueCalls == calls and bar.fill:GetInterpolatedValue() == 420,
        "Changing text formatting never rewrites, delays or interpolates current HP")
    styleState.Select(styleEnv.SmallerUIPersonalhealthFormat, 0)
    check(not bar.valueText:IsShown() and not bar.label:IsShown(), "A single bar's text can be hidden independently")
    styleState.Select(styleEnv.SmallerUIPersonalhealthFormat, 2)
    styleState.Select(styleEnv.SmallerUIPersonalalignment, 2)
    check(bar.valueText.justifyH == "CENTER" and not bar.label:IsShown(), "Centre alignment hides the separate label to avoid collisions")
    styleState.Select(styleEnv.SmallerUIPersonalalignment, 1)
    check(bar.valueText.justifyH == "LEFT", "Left text alignment applies immediately")
    styleState.Select(styleEnv.SmallerUIPersonalalignment, 3)
    check(bar.valueText.justifyH == "RIGHT" and bar.label:IsShown(), "Right alignment restores resource labels when they fit")
    styleState.Click(styleEnv.SmallerUIPersonalAutoFontSize)
    styleEnv.SmallerUIPersonalfontSize:SetText("18")
    styleEnv.SmallerUIPersonalfontSize.scripts.OnEnterPressed(styleEnv.SmallerUIPersonalfontSize)
    styleState.Select(styleEnv.SmallerUIPersonalfont, 2)
    check(bar.valueText.fontSize == 18 and bar.valueText.fontPath == "Fonts\\ARIALN.TTF",
        "Custom text size and font use native font rendering")
    styleState.Click(styleEnv.SmallerUIPersonalTextColour)
    styleState.PickColour(0.8, 0.9, 0.3)
    styleEnv.ColorPickerFrame:OnOkay()
    check(bar.valueText.textColor[1] == 0.8 and bar.label.textColor[3] == 0.3, "Text colour applies consistently to values and labels")
    styleState.Click(styleEnv.SmallerUIPersonalBorder)
    check(bar.borderColor[4] == 0 and styleHud.player.power.borderColor[4] == 0,
        "The border around both bars can be removed without changing bar dimensions")
    styleState.Click(styleEnv.SmallerUIPersonalBorderColour)
    styleState.PickColour(0.2, 0.6, 0.9)
    styleEnv.ColorPickerFrame:OnOkay()
    styleState.Click(styleEnv.SmallerUIPersonalBorder)
    check(bar.borderColor[2] == 0.6 and bar.borderColor[4] == 1, "A chosen border colour appears when borders are enabled")
    styleEnv.SmallerUIPersonalbackgroundOpacity:SetText("40")
    styleEnv.SmallerUIPersonalbackgroundOpacity.scripts.OnEnterPressed(styleEnv.SmallerUIPersonalbackgroundOpacity)
    check(bar.backgroundColor[4] == 0.4, "Bar background opacity is independently configurable")
    styleState.units.player.health, styleState.units.player.maximum = 12345, 20000
    styleEvent("UNIT_HEALTH", "player")
    styleState.Click(styleEnv.SmallerUIPersonalShortNumbers)
    check(bar.valueText:GetText() == "12.3k / 20.0k", "Optional short numbers abbreviate readable values")
    styleState.units.player.health, styleState.units.player.maximum, styleState.units.player.percent = privateValue, privateValue, privateValue
    styleState.Select(styleEnv.SmallerUIPersonalhealthFormat, 5)
    styleEvent("UNIT_HEALTH", "player")
    check(bar.fill:GetInterpolatedValue() == privateValue and bar.valueText.formatArgs[1] == privateValue
        and bar.valueText.formatArgs[3] == privateValue, "Secret HP and percentage go directly to native text without Lua arithmetic or abbreviation")
    local healthPercent = styleEnv.UnitHealthPercent
    styleEnv.UnitHealthPercent = nil
    styleState.Select(styleEnv.SmallerUIPersonalhealthFormat, 3)
    check(bar.valueText.format == "%d / %d" and bar.valueText.formatArgs[1] == privateValue,
        "Unavailable secret-safe percentages fall back to exact HP rather than misleading guessed values")
    styleEnv.UnitHealthPercent = healthPercent
    styleState.units.player.health, styleState.units.player.maximum = 100, 1000
    styleState.units.player.percent = nil
    styleState.units.player.dead = true
    styleEvent("UNIT_HEALTH", "player")
    styleAddon:SetResourceStyle("player", "fontSize", 20)
    check(bar.valueText:GetText() == "Dead", "Styling changes preserve death/offline status text")
    styleState.units.player.dead = false
    styleEvent("UNIT_HEALTH", "player")
    styleState.Click(styleEnv.SmallerUIPersonalResourceColoursToggle)
    check(styleEnv.SmallerUIPersonalResourceColours:IsShown()
        and styleEnv.SmallerUIPersonalOptions.content:GetHeight() == originalHeight + 340,
        "Resource override controls expand below the text controls without hiding subsequent settings")
    styleState.Select(styleEnv.SmallerUIPersonalResourceToken, "ENERGY")
    styleState.Click(styleEnv.SmallerUIPersonalResourceColour)
    styleState.PickColour(0.3, 0.8, 0.9)
    styleEnv.ColorPickerFrame:OnCancel()
    check(styleCfg.player.colours.powerOverrides.ENERGY == nil, "Cancelling a new resource override restores the absence of an override")
    styleState.Click(styleEnv.SmallerUIPersonalResourceColour)
    styleState.PickColour(0.3, 0.8, 0.9)
    styleEnv.ColorPickerFrame:OnOkay()
    check(styleCfg.player.colours.powerOverrides.ENERGY.b == 0.9 and styleCfg.player.colours.powerByType,
        "Per-resource overrides save separately and enable type-based colouring")
    styleState.units.player.token = "ENERGY"
    styleEvent("UPDATE_SHAPESHIFT_FORM")
    check(styleHud.player.power.fill.barColor[3] == 0.9, "Cat form applies the chosen Energy override")
    styleState.units.player.token = "RAGE"
    styleEvent("UPDATE_SHAPESHIFT_FORM")
    check(styleHud.player.power.fill.barColor[1] == 0.9 and styleHud.player.power.fill.barColor[3] == 0.15,
        "Bear form retains its own Rage colour rather than the Cat Energy override")
    styleState.units.player.token = "ENERGY"
    styleEvent("UPDATE_SHAPESHIFT_FORM")
    check(styleHud.player.power.fill.barColor[3] == 0.9, "Returning to Cat form restores its Energy override")
    styleState.units.player.power, styleState.units.player.powerMax, styleState.units.player.powerPercent = privateValue, privateValue, privateValue
    styleState.Select(styleEnv.SmallerUIPersonalpowerFormat, 3)
    styleEvent("UNIT_POWER_UPDATE", "player")
    check(styleState.units.player.percentPowerType == 3 and styleHud.player.power.valueText.formatArgs[1] == privateValue,
        "Secret power percentages use the active power ID after a form change")
    styleState.Click(styleEnv.SmallerUIPersonalResetResourceColour)
    check(styleCfg.player.colours.powerOverrides.ENERGY == nil and styleHud.player.power.fill.barColor[2] == 0.8,
        "An individual resource colour can be restored to its default")
    styleAddon:SetResourcePowerOverride("player", "FOCUS", 0.7, 0.1, 0.8)
    styleAddon:SetResourceStyle("player", "border", false)
    styleAddon:ResetResourceLayout("player")
    check(not styleAddon:GetResourceSettings().player.style.border
        and styleAddon:GetResourceSettings().player.colours.powerOverrides.FOCUS.b == 0.8,
        "Reset layout preserves text/border styling and resource-specific colours")
    local migratedEnv, migratedState = boot(nil, styleEnv.SmallerUICharDB)
    local restored = migratedState.addon:GetResourceSettings().player
    check(restored.style.fontSize == 20 and restored.style.alignment == 3 and not restored.style.border
        and restored.colours.powerOverrides.FOCUS.b == 0.8, "Text, border and resource overrides persist per character")
    local badEnv, badState = boot(nil, { resources = { player = { style = { font = 99, fontSize = 0/0 },
        colours = { powerOverrides = { ENERGY = { r = privateValue, g = 0, b = 0 }, bad = { r = 0, g = 0, b = 0 } } } } } })
    check(badState.addon:GetResourceSettings().player.style.font == 1
        and badState.addon:GetResourceSettings().player.style.fontSize == 12
        and next(badState.addon:GetResourceSettings().player.colours.powerOverrides) == nil,
        "Malformed styles and invalid/private override data recover safely")
    check(not styleAddon:SetResourceStyle("player", "healthFormat", 99)
        and not styleAddon:SetResourceStyle("player", "fontSize", 12.5)
        and not styleAddon:SetResourcePowerOverride("player", "BAD1", 1, 0, 0), "Invalid style values and resource tokens are rejected")
end

do
    local function Bounds(frame)
        local x, y, width, height = frame:GetRect()
        local scale = frame:GetEffectiveScale()
        return x * scale, y * scale, width * scale, height * scale
    end
    local function Fixture(scale, pixels)
        local env, state, event, tick = boot(nil)
        state.geometry, state.pixelSize = true, pixels or 1
        local addon = state.addon
        local cfg = addon:GetResourceSettings()
        cfg.enabled, cfg.petEnabled = true, true
        cfg.player.linked, cfg.player.scale = false, scale or 1
        cfg.player.x, cfg.player.y = -320, -80
        cfg.player.health.width, cfg.player.health.height = 200, 20
        cfg.player.power.width, cfg.player.power.height = 200, 10
        cfg.pet.x, cfg.pet.y, cfg.pet.names, cfg.pet.portraits = 280, 50, false, false
        cfg.pet.health.width, cfg.pet.health.height = 200, 20
        cfg.pet.power.width, cfg.pet.power.height = 200, 10
        state.units.pet = { health = 900, maximum = 1000, power = 40, powerMax = 100, token = "FOCUS", name = "Pet" }
        addon:ApplyResources()
        addon:ShowOptions("resources")
        addon:BeginResourceEdit()
        local hud = addon:GetResourceDisplay()
        hud.partyRoot:Hide() -- Isolate each alignment case from sample-party geometry.
        return env, state, event, tick, addon, hud
    end
    local env, state, event, tick, addon, hud = Fixture()
    check(env.SmallerUIMoveSelection:IsShown() and env.SmallerUIMoveSelection.label:GetText() == "Personal resources",
        "Move mode initially highlights and names the current display")
    local startX, startY = Bounds(hud.player.health)
    local petX, petY = Bounds(hud.pet.health)
    state.mouseDown = true
    addon:BeginResourceDrag(hud.player, "health")
    state.cursorX, state.cursorY = 100 + petX - 6 - startX, 100 + petY + 100 - startY
    tick()
    local x, y = Bounds(hud.player.health)
    near(x, petX, "A bar snaps to another bar's edge within eight screen pixels")
    check(env.SmallerUIMoveVerticalGuide:IsShown() and addon:GetResourceMoveState().snapX == petX,
        "Active alignment displays a vertical guide at the matched edge")
    check(env.SmallerUIMoveSelection.label:GetText() == "Personal resources - health",
        "Independent dragging identifies the selected bar")
    state.shift = true
    tick()
    x = Bounds(hud.player.health)
    near(x, petX - 6, "Shift immediately releases snapping to the original cursor position")
    check(not env.SmallerUIMoveVerticalGuide:IsShown() and not env.SmallerUIMoveHorizontalGuide:IsShown(),
        "Shift hides snapping guides")
    state.shift = false
    tick()
    x = Bounds(hud.player.health)
    near(x, petX, "Releasing Shift resumes snapping without accumulating a positional offset")
    state.cursorX = state.cursorX - 20
    tick()
    x = Bounds(hud.player.health)
    near(x, petX - 26, "Moving beyond the threshold releases the edge instead of remaining stuck")
    state.cursorX = state.cursorX + 20
    tick()
    state.shift = true -- Release modifier is honored even without another frame.
    state.mouseDown = false
    addon:EndResourceDrag()
    x = Bounds(hud.player.health)
    near(x, petX - 6, "The final Shift state is re-evaluated on mouse release")
    check(not addon:GetResourceMoveState() and not env.SmallerUIMoveVerticalGuide:IsShown(),
        "Releasing completes the drag and removes its guides")
    addon:FinishResourceEdit(true)
    local saved = addon:GetResourceSettings().player.health.x
    check(saved ~= 0 and not env.SmallerUIMoveOverlay:IsShown(), "Done saves the moved bar and clears the selection overlay")
    local droppedX = Bounds(hud.player.health)
    addon:GetResourceSettings().pet.x = addon:GetResourceSettings().pet.x + 25
    addon:ApplyResources()
    near(Bounds(hud.player.health), droppedX, "Snapping does not create a permanent link to the other display")
    local reloaded, reloadedState = boot(nil, env.SmallerUICharDB)
    near(reloadedState.addon:GetResourceSettings().player.health.x, saved, "Moved positions persist for the character")

    env, state, event, tick, addon, hud = Fixture()
    local originalPlayerX, originalPetX = addon:GetResourceSettings().player.x, addon:GetResourceSettings().pet.x
    addon:SetResourceOption("player", "linked", true)
    hud.partyRoot:Hide()
    local hpX, hpY = Bounds(hud.player.health)
    local powerX, powerY = Bounds(hud.player.power)
    state.mouseDown, state.shift = true, true
    addon:BeginResourceDrag(hud.player, "health")
    state.cursorX, state.cursorY = 145, 127
    tick()
    x, y = Bounds(hud.player.health)
    local movedPowerX, movedPowerY = Bounds(hud.player.power)
    near(x - hpX, 45, "Linked bars follow the cursor together horizontally")
    near(movedPowerX - powerX, 45, "Power keeps the group's horizontal offset")
    near(movedPowerY - powerY, y - hpY, "Power and health retain their vertical spacing while moving")
    addon:FinishResourceEdit(true) -- Done while the pointer is still held.
    near(addon:GetResourceSettings().player.x, originalPlayerX + 45, "Done finalizes an in-progress linked drag")
    near(addon:GetResourceSettings().pet.x, originalPetX, "Moving one group does not move another display")
    addon:BeginResourceEdit()
    hud.partyRoot:Hide()
    local beforeCancel = addon:GetResourceSettings().player.x
    addon:BeginResourceDrag(hud.player, "power")
    state.cursorX, state.cursorY = 190, 154
    tick()
    addon:EndResourceDrag()
    addon:ResizeResourceBars("player", "health", 310, 24)
    env.SmallerUIResourceEditor:Hide() -- WoW's existing Escape/UISpecialFrames path.
    near(addon:GetResourceSettings().player.x, beforeCancel, "Escape restores the entire session's position changes")
    check(addon:GetResourceSettings().player.health.width == 200 and not env.SmallerUIMoveOverlay:IsShown()
        and not addon:GetResourceMoveState(), "Escape also restores sizes and clears all move state")

    for _, scale in ipairs({ 0.67, 0.8, 1.25 }) do
        env, state, event, tick, addon, hud = Fixture(scale)
        startX, startY = Bounds(hud.player.health)
        petX, petY = Bounds(hud.pet.health)
        state.mouseDown = true
        addon:BeginResourceDrag(hud.player, "health")
        state.cursorX, state.cursorY = 100 + petX - 6 - startX, 100 + petY + 100 - startY
        tick()
        x = Bounds(hud.player.health)
        near(x, petX, "Snapping uses screen coordinates at bar scale " .. scale)
        state.shift = true
        tick()
        x = Bounds(hud.player.health)
        near(x, petX - 6, "Shift preserves exact cursor movement at bar scale " .. scale)
        addon:FinishResourceEdit(false)
    end
    env, state, event, tick, addon, hud = Fixture(0.8, 0.5)
    startX, startY = Bounds(hud.player.health)
    petX, petY = Bounds(hud.pet.health)
    state.mouseDown = true
    addon:BeginResourceDrag(hud.player, "health")
    state.cursorX, state.cursorY = 100 + petX - 6 - startX, 100 + petY + 100 - startY
    tick()
    x = Bounds(hud.player.health)
    near(x, petX - 6, "Eight device pixels convert to four canvas units at a half-unit pixel factor")
    state.cursorX = state.cursorX + 3
    tick()
    x = Bounds(hud.player.health)
    near(x, petX, "A six-device-pixel gap snaps with that same pixel factor")
    near(env.SmallerUIMoveVerticalGuide:GetWidth(), 0.5, "Guide thickness remains one device pixel")
    addon:FinishResourceEdit(false)

    env, state, event, tick, addon, hud = Fixture()
    startX, startY = Bounds(hud.player.health)
    local rootX, rootY, rootWidth, rootHeight = Bounds(env.UIParent)
    local _, _, barWidth, barHeight = Bounds(hud.player.health)
    state.mouseDown = true
    addon:BeginResourceDrag(hud.player, "health")
    state.cursorX = 100 + rootX + rootWidth / 2 - barWidth / 2 - 5 - startX
    state.cursorY = 100 + rootY + rootHeight / 2 - barHeight / 2 - 4 - startY
    tick()
    x, y = Bounds(hud.player.health)
    near(x + barWidth / 2, rootX + rootWidth / 2, "Bars can snap to screen horizontal centre")
    near(y + barHeight / 2, rootY + rootHeight / 2, "Bars can snap to screen vertical centre")
    check(env.SmallerUIMoveVerticalGuide:IsShown() and env.SmallerUIMoveHorizontalGuide:IsShown(),
        "Both centre guides appear when both axes align")
    state.shift = true
    state.cursorX, state.cursorY = -9999, -9999
    tick()
    x, y = Bounds(hud.player.health)
    near(x, rootX, "Free placement remains inside the screen horizontally")
    near(y, rootY, "Free placement remains inside the screen vertically")
    state.mouseDown = false
    tick()
    check(not addon:GetResourceMoveState(), "A missed native drag-stop event is recovered when the mouse is released")
    addon:FinishResourceEdit(false)

    env, state, event, tick, addon, hud = Fixture()
    state.class = "PALADIN"
    addon:ApplyResources()
    hud.partyRoot:Hide()
    state.mouseDown, state.shift = true, true
    local sealX, sealY = Bounds(hud.player.seal)
    local sealBeforeX, sealBeforeY = addon:GetResourceSettings().seal.x, addon:GetResourceSettings().seal.y
    hud.player.seal.scripts.OnDragStart(hud.player.seal)
    state.cursorX, state.cursorY = 129, 118
    tick()
    x, y = Bounds(hud.player.seal)
    near(x - sealX, 29, "The Paladin seal uses the shared precision drag path")
    near(y - sealY, 18, "The seal moves independently on both axes")
    addon:FinishResourceEdit(true)
    near(addon:GetResourceSettings().seal.x, sealBeforeX + 29, "Done saves an in-progress seal drag")
    near(addon:GetResourceSettings().seal.y, sealBeforeY + 18, "Seal vertical placement persists relative to health")
    addon:BeginResourceEdit()
    hud.player.seal.scripts.OnDragStart(hud.player.seal)
    state.cursorX = state.cursorX + 40
    tick()
    state.combat = true
    event("PLAYER_REGEN_DISABLED")
    check(not addon:IsEditingResources() and not addon:GetResourceMoveState() and not env.SmallerUIMoveOverlay:IsShown(),
        "Combat cancels active move mode and removes guides/highlighting")
    near(addon:GetResourceSettings().seal.x, sealBeforeX + 29, "Combat cancellation restores the seal's prior saved position")
    state.units.player.health = 1
    event("UNIT_HEALTH", "player")
    check(hud.player.health.fill:GetInterpolatedValue() == 1, "Immediate HP rendering remains intact after move-mode cancellation")

    env, state, event, tick, addon, hud = Fixture(0.8)
    state.class = "PALADIN"
    addon:ApplyResources()
    hud.partyRoot:Hide()
    state.mouseDown, state.shift = true, true
    sealBeforeX = addon:GetResourceSettings().seal.x
    hud.player.seal.scripts.OnDragStart(hud.player.seal)
    state.cursorX = 116
    tick()
    addon:EndSealDrag()
    near(addon:GetResourceSettings().seal.x, sealBeforeX + 20, "Scaled seal movement stores offsets in its own local units")
    addon:FinishResourceEdit(false)

    env, state, event, tick, addon, hud = Fixture()
    local partyCfg = addon:GetResourceSettings().party
    partyCfg.scale, partyCfg.x, partyCfg.y = 0.8, 123, 90
    addon:ApplyResources()
    local firstX, firstY = Bounds(hud.party[1].health)
    local secondX, secondY = Bounds(hud.party[2].health)
    state.mouseDown, state.shift = true, true
    addon:BeginResourceDrag(hud.party[2], "health")
    state.cursorX, state.cursorY = 155, 79
    tick()
    x, y = Bounds(hud.party[1].health)
    local nextX, nextY = Bounds(hud.party[2].health)
    near(x - firstX, 55, "Dragging a linked party row moves the whole party display")
    near(y - firstY, -21, "Party group dragging converts vertical cursor motion correctly")
    near(nextX - secondX, 55, "Other party rows retain the same horizontal movement")
    near(nextY - y, secondY - firstY, "Party member spacing stays fixed during linked dragging")
    addon:EndResourceDrag()
    near(addon:GetResourceSettings().party.x, 178, "Party-group placement persists using the correct scaled root")
    addon:FinishResourceEdit(false)

    env, state, event, tick, addon, hud = Fixture()
    partyCfg = addon:GetResourceSettings().party
    partyCfg.linked, partyCfg.x, partyCfg.names, partyCfg.portraits = false, 123, false, false
    partyCfg.power.x = 275
    addon:ApplyResources()
    firstX, firstY = Bounds(hud.party[1].health)
    secondX = Bounds(hud.party[2].health)
    state.mouseDown = true
    addon:BeginResourceDrag(hud.party[1], "health")
    state.cursorX, state.cursorY = 105, 130
    tick()
    x = Bounds(hud.party[1].health)
    near(x, firstX + 5, "Unlinked party health does not snap to its own coupled clones")
    addon:EndResourceDrag()
    nextX = Bounds(hud.party[2].health)
    near(nextX, secondX + 5, "Shared party bar offsets apply consistently to every member after drop")
    addon:FinishResourceEdit(false)

    env, state, event, tick, addon, hud = Fixture()
    local beforeLogout = addon:GetResourceSettings().player.health.x
    state.mouseDown, state.shift = true, true
    addon:BeginResourceDrag(hud.player, "health")
    state.cursorX, state.cursorY = 160, 130
    tick()
    addon:EndResourceDrag()
    check(addon:GetResourceSettings().player.health.x ~= beforeLogout, "A pending layout edit is available before confirmation")
    event("PLAYER_LOGOUT")
    near(addon:GetResourceSettings().player.health.x, beforeLogout, "Logout/reload discards unconfirmed layout edits")
    check(not addon:IsEditingResources() and not env.SmallerUIMoveOverlay:IsShown() and not env.SettingsPanel:IsShown(),
        "Logout cleans up move mode without reopening settings")
end

do
    local safeEnv, safeState, safeEvent, safeTick = boot(nil)
    local safeAddon = safeState.addon
    check(safeState.combatLogRegistrations == 0 and safeState.forbiddenActions == 0,
        "Login never attempts to register the client's restricted callback combat-log event")
    check(not safeAddon:CanPredictPeriodicResources(), "Unsupported periodic estimates are explicitly unavailable")
    safeAddon:ShowOptions("resources")
    check(safeEnv.SmallerUIPersonalPeriodicHeals.enabled == false and safeEnv.SmallerUIPersonalPeriodicDamage.enabled == false
        and not safeEnv.SmallerUIPersonalPeriodicHeals:GetChecked(), "Unsupported periodic controls are disabled instead of promising unavailable estimates")
    safeState.Click(safeEnv.SmallerUIPersonalEnabled)
    local safeHud = safeAddon:GetResourceDisplay()
    safeState.units.player.health, safeState.units.player.incoming = 400, 200
    safeEvent("UNIT_HEALTH", "player")
    safeEvent("UNIT_HEAL_PREDICTION", "player")
    check(safeHud.player.health.fill:GetInterpolatedValue() == 400 and safeHud.player.health.forecasts.direct:GetValue() == 200,
        "Restricted combat logs do not disable immediate HP or native incoming-healing previews")
    safeAddon:BeginResourceEdit()
    safeAddon:TestResourceDamage()
    check(not safeHud.player.health.forecasts.hot:IsShown() and not safeHud.player.health.forecasts.dot:IsShown(),
        "Edit previews do not invent unsupported periodic estimates")
    safeAddon:FinishResourceEdit(false)
    check(safeState.combatLogRegistrations == 0, "Toggles and move mode do not retry restricted registration")
    local noMetaEnv, noMetaState = boot(nil, nil, { noEventMetadata = true })
    check(noMetaState.combatLogRegistrations == 0 and not noMetaState.addon:CanPredictPeriodicResources(),
        "Missing event metadata fails closed without a forbidden probe")
    local invalidEnv, invalidState = boot(nil, nil, { legacyCombatLog = true, invalidCombatLog = true })
    check(invalidState.combatLogRegistrations == 0, "Invalid legacy combat-log events are not registered")
    local legacyEnv, legacyState = boot(nil, nil, { legacyCombatLog = true })
    check(legacyState.combatLogRegistrations == 1 and legacyState.forbiddenActions == 0
        and legacyState.addon:CanPredictPeriodicResources(), "Legacy frame-event clients retain periodic estimates without unsafe callback registration")
    safeEvent("ADDON_ACTION_FORBIDDEN", "AnotherAddon", "Other:Action()")
    check(not safeEnv.SmallerUICharDB.lastBlockedAction, "Diagnostics ignore blocked actions attributed to other addons")
    safeEvent("ADDON_ACTION_BLOCKED", "SmallerUI", "Example:ProtectedAction()")
    check(safeEnv.SmallerUICharDB.lastBlockedAction.action == "Example:ProtectedAction()"
        and safeEnv.SmallerUICharDB.lastBlockedAction.event == "ADDON_ACTION_BLOCKED",
        "Own blocked actions are recorded for diagnosis without suppressing Blizzard's warning")
end

do
    local pixelEnv, pixelState, pixelEvent = boot(nil)
    pixelState.geometry, pixelState.roundGeometry, pixelState.class = true, true, "PALADIN"
    local addon = pixelState.addon
    local cfg = addon:GetResourceSettings()
    cfg.enabled, cfg.petEnabled, cfg.partyEnabled = true, true, true
    pixelState.units.pet = { health = 500, maximum = 500, power = 100, powerMax = 100, token = "FOCUS", name = "Pet" }
    pixelState.units.party1 = { health = 1000, maximum = 1000, power = 100, powerMax = 100, token = "MANA", name = "Party" }
    local function Pixels(frame)
        local x, y, width, height = frame:GetRect()
        local factor = frame:GetEffectiveScale() / pixelState.pixelSize
        return x * factor, y * factor, width * factor, height * factor
    end
    local function Near(a, b) return math.abs(a - b) < 0.00001 end
    pixelState.pixelSize = 768 / 1440
    addon:ApplyResources()
    local defaultHud = addon:GetResourceDisplay()
    for _, view in ipairs({ defaultHud.player, defaultHud.pet, defaultHud.party[1] }) do
        local x, _, width = Pixels(view.health.fill)
        local px, _, powerWidth = Pixels(view.power.fill)
        check(Near(x, px) and Near(width, powerWidth), "Default health and power fills share their rendered horizontal edges for " .. view.scope)
    end
    for _, density in ipairs({ 768 / 1080, 768 / 1440, 768 / 2160 }) do
        pixelState.pixelSize = density
        for _, scale in ipairs({ 0.5, 0.67, 0.8, 1, 1.25 }) do
            for _, scope in ipairs({ "player", "pet", "party" }) do
                cfg[scope].scale = scale
                cfg[scope].gap = 0
                cfg[scope].health.height, cfg[scope].power.height = 15, 12
                cfg[scope].health.width, cfg[scope].power.width = 280, 280
            end
            addon:ApplyResources()
            local hud = addon:GetResourceDisplay()
            for _, view in ipairs({ hud.player, hud.pet, hud.party[1] }) do
                local hx, hy, hw = Pixels(view.health)
                local px, py, pw, ph = Pixels(view.power)
                check(Near(hx, px) and Near(hw, pw) and Near(hy, py + ph),
                    "Linked bars meet without seams and share their rendered edges at " .. density .. "/" .. scale .. "/" .. view.scope)
                for _, kind in ipairs({ "health", "power" }) do
                    local bar = view[kind]
                    local x, y, w, h = Pixels(bar)
                    local ix, iy, iw, ih = Pixels(bar.fill)
                    check(Near(ix - x, 1) and Near(iy - y, 1) and Near(x + w - ix - iw, 1) and Near(y + h - iy - ih, 1)
                        and Near(bar.backdrop.edgeSize * bar:GetEffectiveScale() / density, 1),
                        "All four border/fill insets are one physical pixel at " .. density .. "/" .. scale .. "/" .. view.scope .. "/" .. kind)
                end
                local _, _, fillWidth, fillHeight = view.health.fill:GetRect()
                check(Near(view.health.forecasts.direct:GetWidth(), fillWidth) and Near(view.health.forecasts.direct:GetHeight(), fillHeight),
                    "Incoming-heal preview uses the actual pixel-aligned fill dimensions")
            end
            local _, healthY, _, healthHeight = Pixels(hud.player.health)
            local _, powerY, _, powerHeight = Pixels(hud.player.power)
            local _, sealY, _, sealHeight = Pixels(hud.player.seal)
            check(Near(sealY + sealHeight / 2, (math.min(healthY, powerY) + math.max(healthY + healthHeight, powerY + powerHeight)) / 2),
                "Default seal position centres on the combined rendered bars at " .. density .. "/" .. scale)
        end
    end
    addon:SetResourceStyle("player", "border", false)
    local hud = addon:GetResourceDisplay()
    local x, y, w, h = Pixels(hud.player.health)
    local ix, iy, iw, ih = Pixels(hud.player.health.fill)
    check(Near(x, ix) and Near(y, iy) and Near(w, iw) and Near(h, ih), "Borderless bars fill their complete frame without invisible padding")
    local powerInnerLeft = hud.player.power.trail._points[1]
    check(powerInnerLeft[2] == hud.player.health.trail and powerInnerLeft[3] == "BOTTOMLEFT"
        and hud.player.health.fill:GetStatusBarTexture().snapToGrid == false
        and hud.player.power.fill:GetStatusBarTexture().snapToGrid == false,
        "Linked live fills share their inner left-edge anchor without independent texture snapping")
    pixelState.units.player.powerMax = 0
    pixelEvent("UNIT_MAXPOWER", "player")
    local _, hy, _, hh = Pixels(hud.player.health)
    local _, sy, _, sh = Pixels(hud.player.seal)
    check(not hud.player.power:IsShown() and Near(sy + sh / 2, hy + hh / 2), "The seal centres on health alone when no power bar is shown")
    pixelState.units.player.health = 1
    pixelEvent("UNIT_HEALTH", "player")
    check(hud.player.health.fill:GetInterpolatedValue() == 1 and hud.player.health.fill.interpolation == pixelEnv.Enum.StatusBarInterpolation.Immediate,
        "Pixel alignment retains immediate live HP updates")
end

do
    local env, state, event = boot(nil)
    local addon = state.addon
    state.class = "PALADIN"
    state.units.pet = { health = 700, maximum = 1000, power = 50, powerMax = 100, token = "FOCUS", name = "Pet" }
    state.units.party1 = { health = 800, maximum = 1000, power = 50, powerMax = 100, token = "MANA", name = "Party" }
    addon:SetResourceOption("root", "enabled", true)
    addon:SetResourceOption("root", "partyEnabled", true)
    addon:SetResourceOption("root", "petEnabled", true)
    addon:ShowOptions("resources")
    local hud = addon:GetResourceDisplay()
    local cfg = addon:GetResourceSettings()
    check(hud.player:IsVisible() and hud.player:GetAlpha() == 1 and cfg.player.style.barTexture == 1,
        "Existing layouts default to visible, fully opaque flat bars")
    env.SmallerUIPersonalcombatOpacity:SetValue(68)
    env.SmallerUIPersonaloutOfCombatOpacity:SetValue(25)
    check(hud.player:GetAlpha() == 0.25 and hud.pet:GetAlpha() == 1 and hud.party[1]:GetAlpha() == 1,
        "Opacity sliders apply immediately to their own display and combat state")
    state.Click(env.SmallerUIPersonalCombatOnly)
    check(not hud.player:IsVisible() and not hud.player.seal:IsVisible() and hud.pet:IsVisible(),
        "Combat-only personal display also hides its seal while leaving the pet visible")
    state.units.player.health = 321
    event("UNIT_HEALTH", "player")
    check(hud.player.health.fill:GetInterpolatedValue() == 321, "Hidden resource bars keep their live HP up to date")
    state.combat = true
    event("PLAYER_REGEN_DISABLED")
    check(hud.player:IsVisible() and hud.player:GetAlpha() == 0.68 and hud.player.health.fill:GetInterpolatedValue() == 321,
        "Entering combat immediately shows the latest health at the configured opacity")
    env.SmallerUIPersonalcombatOpacity:SetValue(0)
    check(not hud.player:IsVisible(), "Zero combat opacity hides the display")
    env.SmallerUIPersonalcombatOpacity:SetValue(68)
    state.combat = false
    event("PLAYER_REGEN_ENABLED")
    check(not hud.player:IsVisible(), "Leaving combat reapplies the hide setting immediately")
    check(addon:BeginResourceEdit() and hud.player:IsVisible() and hud.player:GetAlpha() == 1,
        "Move Mode can position combat-only bars at full opacity")
    addon:FinishResourceEdit(false)
    state.Click(env.SmallerUIPersonalCombatOnly)
    check(hud.player:IsVisible() and hud.player:GetAlpha() == 0.25, "Turning combat-only off restores the saved out-of-combat opacity")

    local dropdown = env.SmallerUIPersonalBarTexture
    local fillTexture = hud.player.health.fill:GetStatusBarTexture()
    dropdown:GenerateMenu()
    local paths = {}
    for _, row in ipairs(dropdown.menu) do
        local swatch = env.CreateFrame("Frame"):CreateTexture()
        row.initialize({ AttachTexture = function() return swatch end })
        check(swatch.textureValue and not paths[swatch.textureValue], "Each texture row previews a distinct bar texture")
        paths[swatch.textureValue] = true
        state.Select(dropdown, row.data)
        check(fillTexture.textureValue == swatch.textureValue
            and hud.player.power.fill:GetStatusBarTexture().textureValue == swatch.textureValue,
            "Selecting a swatch applies that exact artwork to both live fills")
    end
    check(hud.player.health.fill:GetStatusBarTexture() == fillTexture
        and hud.player.health.forecasts.direct._points[1][2] == fillTexture
        and hud.player.health.fill:GetInterpolatedValue() == 321,
        "Changing texture preserves the live value and incoming-heal anchor")
    check(hud.pet.health.fill:GetStatusBarTexture().textureValue == addon.resourceTextures[1][3],
        "Texture changes stay on the selected display")
    local _, restored = boot(nil, env.SmallerUICharDB)
    local style = restored.addon:GetResourceSettings().player.style
    check(style.combatOpacity == 68 and style.outOfCombatOpacity == 25 and style.barTexture == #addon.resourceTextures,
        "Opacity and texture settings persist through reload")
end

print(string.format("Passed %d checks (%s).", passed, _VERSION))

return boot
