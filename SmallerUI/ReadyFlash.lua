local _, Addon = ...
local ticker = CreateFrame("Frame")
local prefixes = {
    { "ActionButton", "Main bar" },
    { "MultiBarBottomLeftButton", "Bottom left bar" },
    { "MultiBarBottomRightButton", "Bottom right bar" },
    { "MultiBarRightButton", "Right bar" },
    { "MultiBarLeftButton", "Left bar" },
    { "MultiBar5Button", "Bar 5" }, { "MultiBar6Button", "Bar 6" }, { "MultiBar7Button", "Bar 7" },
}
local definitions, ordered = {}, {}
for _, prefix in ipairs(prefixes) do
    for index = 1, 12 do
        local name = prefix[1] .. index
        local definition = { name = name, label = prefix[2] .. " - slot " .. index }
        definitions[name], ordered[#ordered + 1] = definition, definition
    end
end
local tracked, history, visuals, flashes = {}, {}, {}, {}
local picking, picker, picks = false, nil, {}
local accumulator = 0

local function Public(value)
    return not issecretvalue or not issecretvalue(value)
end

local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function UsableFrame(frame)
    return frame and frame.GetRect and frame.GetEffectiveScale
        and not (frame.IsForbidden and frame:IsForbidden())
end

function Addon:ValidateReadyFlash()
    self.db.readyFlash = self.db.readyFlash == true
    if type(SmallerUICharDB) ~= "table" then SmallerUICharDB = {} end
    self.character = SmallerUICharDB
    if type(self.character.readySlots) ~= "table" then self.character.readySlots = {} end
    for name, enabled in pairs(self.character.readySlots) do
        if not definitions[name] or enabled ~= true then self.character.readySlots[name] = nil end
    end
end

function Addon:GetReadySlots()
    local result = {}
    for _, definition in ipairs(ordered) do
        if self.character.readySlots[definition.name] then result[#result + 1] = definition end
    end
    return result
end

-- Independent overlays use screen coordinates and never alter a secure action
-- button's attributes, scripts, parent, scale, or mouse bindings.
local function PositionOverlay(overlay, button, padding)
    if not UsableFrame(button) or not button:IsVisible() then return false end
    local left, bottom, width, height = button:GetRect()
    local scale = button:GetEffectiveScale()
    if not Number(left) or not Number(bottom) or not Number(width) or not Number(height)
        or not Number(scale) or width <= 0 or height <= 0 then return false end
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * scale - padding, bottom * scale - padding)
    overlay:SetSize(width * scale + padding * 2, height * scale + padding * 2)
    if overlay.glow then
        local insetX, insetY = width * scale * 0.4, height * scale * 0.4
        overlay.glow:SetPoint("TOPLEFT", -insetX, insetY)
        overlay.glow:SetPoint("BOTTOMRIGHT", insetX, -insetY)
    end
    return true
end

local function Visual(name)
    if visuals[name] then return visuals[name] end
    if InCombatLockdown() then return end -- Prepare visual frames before combat.
    local overlay = CreateFrame("Frame", "SmallerUIReadyGlow_" .. name, UIParent)
    overlay:SetIgnoreParentScale(true)
    overlay:SetScale(1)
    overlay:SetFrameStrata("HIGH")
    overlay:EnableMouse(false)
    local glow = overlay:CreateTexture(nil, "OVERLAY")
    overlay.glow = glow
    glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(1, 0.76, 0.12)
    local fill = overlay:CreateTexture(nil, "ARTWORK")
    fill:SetAllPoints()
    fill:SetColorTexture(1, 0.76, 0.12, 0.20)
    overlay:Hide()
    visuals[name] = overlay
    return overlay
end

local function Flash(name, now)
    local overlay, button = visuals[name], _G[name]
    if overlay and PositionOverlay(overlay, button, 0) then
        flashes[name] = now
        overlay:SetAlpha(1)
        overlay:Show()
        return true
    end
    return false
end

local function StopFlashes()
    for name in pairs(flashes) do visuals[name]:Hide() end
    flashes = {}
end

local function Cooldown(action)
    if C_ActionBar and C_ActionBar.GetActionCooldown then return C_ActionBar.GetActionCooldown(action) end
    if not GetActionCooldown then return end
    local start, duration, enabled, rate = GetActionCooldown(action)
    return { startTime = start, duration = duration, isEnabled = enabled, modRate = rate }
end

local function Charges(action)
    if C_ActionBar and C_ActionBar.GetActionCharges then return C_ActionBar.GetActionCharges(action) end
    if not GetActionCharges then return end
    local current, maximum = GetActionCharges(action)
    return maximum and { currentCharges = current, maxCharges = maximum } or nil
end

local function GCD()
    if C_Spell and C_Spell.GetSpellCooldown then return C_Spell.GetSpellCooldown(61304) end
    if GetSpellCooldown then
        local start, duration = GetSpellCooldown(61304)
        return { startTime = start, duration = duration }
    end
end

local function ReadState(button, now, fromCooldownEvent)
    if not UsableFrame(button) then return end
    local action = button.action
    if not Number(action) and button.GetAttribute then action = button:GetAttribute("action") end
    if not Number(action) or action < 1 or action % 1 ~= 0 then return end
    local kind = GetActionInfo(action)
    if not Public(kind) then return nil, true end
    if not kind then return end
    local cooldown = Cooldown(action)
    if not cooldown or not Public(cooldown.isEnabled) then return nil, true end
    local enabled = cooldown.isEnabled == nil or cooldown.isEnabled == true or cooldown.isEnabled == 1
    local rate = cooldown.modRate
    local active, gcdOnly = false, false
    local publicTiming = Number(cooldown.startTime) and Number(cooldown.duration) and Public(rate)
    if not publicTiming then
        -- These flags are documented NeverSecret. isOnGCD is only trusted
        -- during SPELL_UPDATE_COOLDOWN dispatch, as required by Blizzard.
        if not fromCooldownEvent or not Public(cooldown.isActive)
            or type(cooldown.isActive) ~= "boolean" then return nil, true end
        active = cooldown.isActive
        if active then
            if not Public(cooldown.isOnGCD) or type(cooldown.isOnGCD) ~= "boolean" then return nil, true end
            gcdOnly = cooldown.isOnGCD
        end
    else
        if rate == nil then rate = 1 end
        if not Number(rate) or rate <= 0 then return nil, true end
        local start, duration = cooldown.startTime, cooldown.duration / rate
        active = start > 0 and duration > 0 and start + duration > now + 0.01
        if active then
            local gcd = GCD()
            if gcd then
                if not Number(gcd.startTime) or not Number(gcd.duration) then return nil, true end
                local gcdRate = gcd.modRate
                if not Public(gcdRate) then return nil, true end
                if gcdRate == nil then gcdRate = 1 end
                if not Number(gcdRate) or gcdRate <= 0 then return nil, true end
                gcdOnly = gcd.duration > 0 and math.abs(start - gcd.startTime) < 0.04
                    and math.abs(duration - gcd.duration / gcdRate) < 0.04
            elseif not C_Spell and not GetSpellCooldown then
                gcdOnly = duration <= 1.7 -- Compatibility with clients lacking a GCD query.
            elseif Public(cooldown.isOnGCD) and cooldown.isOnGCD == true then
                gcdOnly = true
            end
        end
    end
    local charge = Charges(action)
    local emptyCharges, hasCharges = false, false
    if charge and not Public(charge.maxCharges) then return nil, true end
    if charge and Number(charge.maxCharges) and charge.maxCharges > 1 then
        if not Number(charge.currentCharges) then return nil, true end
        hasCharges = true
        emptyCharges = charge.currentCharges == 0
    end
    local usableFunction = C_ActionBar and C_ActionBar.IsUsableAction or IsUsableAction
    if not usableFunction then return end
    local usable = usableFunction(action)
    if not Public(usable) then return nil, true end
    return {
        -- Content changes reset history via ACTIONBAR_SLOT_CHANGED. Spell IDs
        -- need not be inspected, which also accommodates restricted spell IDs.
        identity = action .. ":" .. tostring(kind),
        cooling = emptyCharges or (not hasCharges and active and not gcdOnly),
        blocked = not enabled or (active and gcdOnly),
        usable = usable == true,
        eventOnly = not publicTiming,
    }
end

function Addon:PollReadyFlash(now, fromCooldownEvent)
    if not self.db or not self.db.readyFlash then return end
    local restricted = false
    for _, definition in ipairs(tracked) do
        local name = definition.name
        local ok, current, private = pcall(ReadState, _G[name], now, fromCooldownEvent)
        if not ok or not current then
            -- Preserve a public event's history while numeric timings are
            -- private; a future public cooldown event can complete it.
            if not ok or not private then history[name] = nil end
            local previous = history[name]
            local hasPublicEvents = ok and private and not fromCooldownEvent and previous and previous.eventOnly
            if fromCooldownEvent and previous then previous.eventOnly = false end
            if not hasPublicEvents then restricted = restricted or private == true or not ok end
        else
            local previous = history[name]
            if not previous or previous.identity ~= current.identity then
                previous = { identity = current.identity, armed = false }
                history[name] = previous
            end
            previous.eventOnly = current.eventOnly
            if current.cooling then
                previous.armed = true
            elseif previous.armed and not current.blocked and current.usable then
                previous.armed = false
                Flash(name, now)
            end
        end
    end
    if self.cooldownRestricted ~= restricted then
        self.cooldownRestricted = restricted
        if self.RefreshReadyOptions then self:RefreshReadyOptions() end
    end
end

local function Update(_, elapsed)
    local now = GetTime()
    accumulator = accumulator + elapsed
    if accumulator >= 0.05 then
        accumulator = 0
        Addon:PollReadyFlash(now)
    end
    for name, started in pairs(flashes) do
        local age = now - started
        if age >= 1 or not PositionOverlay(visuals[name], _G[name], 0) then
            visuals[name]:Hide()
            flashes[name] = nil
        else
            visuals[name]:SetAlpha((0.55 + 0.45 * math.cos(age * math.pi * 4)) * (1 - age))
        end
    end
end

function Addon:RefreshReadyTracking()
    if not self.character then return end
    tracked, history = self:GetReadySlots(), {}
    self.cooldownRestricted = false
    StopFlashes()
    for _, definition in ipairs(tracked) do Visual(definition.name) end
    ticker:SetScript("OnUpdate", self.db.readyFlash and #tracked > 0 and Update or nil)
    if self.RefreshReadyOptions then self:RefreshReadyOptions() end
end

function Addon:SetReadyFlashEnabled(enabled)
    self.db.readyFlash = enabled == true
    self:RefreshReadyTracking()
end

function Addon:ToggleReadySlot(name)
    if not definitions[name] or not self.character then return end
    self.character.readySlots[name] = not self.character.readySlots[name] or nil
    self:RefreshReadyTracking()
end

function Addon:ClearReadySlots()
    self.character.readySlots = {}
    self:RefreshReadyTracking()
end

function Addon:TestReadyFlashes()
    if not self.db.readyFlash then return end
    for _, definition in ipairs(tracked) do Flash(definition.name, GetTime()) end
end

function Addon:IsPickingSlot() return picking end

function Addon:CancelSlotPicker(reopen)
    if not picking then return end
    picking = false
    for _, overlay in pairs(picks) do overlay:Hide() end
    picker:Hide()
    if reopen then self:ShowOptions("cooldowns") end
end

function Addon:BeginSlotPicker()
    if InCombatLockdown() then
        self:OptionsFeedback("Choose slots after combat ends.", true)
        return false
    end
    if not self.db.readyFlash then return false end
    if not self:HideOptions() then return false end
    if not picker then
        picker = CreateFrame("Frame", "SmallerUISlotPicker", UIParent, "BackdropTemplate")
        picker:Hide()
        picker:SetIgnoreParentScale(true)
        picker:SetScale(1)
        picker:SetFrameStrata("FULLSCREEN_DIALOG")
        picker:SetSize(540, 80)
        picker:SetPoint("TOP", 0, -60)
        picker:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 })
        picker:SetBackdropColor(0.04, 0.06, 0.09, 0.98)
        local text = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        text:SetPoint("TOP", 0, -15)
        text:SetText("Click a slot to toggle its ready flash. Escape cancels.")
        local cancel = CreateFrame("Button", "SmallerUICancelSlotPicker", picker, "UIPanelButtonTemplate")
        cancel:SetSize(100, 24)
        cancel:SetPoint("BOTTOM", 0, 10)
        cancel:SetText("Cancel")
        cancel:SetScript("OnClick", function() Addon:CancelSlotPicker(true) end)
        picker:SetScript("OnHide", function() Addon:CancelSlotPicker(true) end)
        table.insert(UISpecialFrames, "SmallerUISlotPicker")
    end
    local count = 0
    for _, definition in ipairs(ordered) do
        local name, button = definition.name, _G[definition.name]
        if UsableFrame(button) and button:IsVisible() then
            local overlay = picks[name]
            if not overlay then
                overlay = CreateFrame("Button", "SmallerUIPick_" .. name, UIParent, "BackdropTemplate")
                overlay:SetIgnoreParentScale(true)
                overlay:SetScale(1)
                overlay:SetFrameStrata("FULLSCREEN_DIALOG")
                overlay:SetFrameLevel(picker:GetFrameLevel() + 5)
                overlay:EnableMouse(true)
                overlay:RegisterForClicks("LeftButtonUp", "RightButtonUp")
                overlay:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 2 })
                overlay:SetBackdropBorderColor(0.45, 0.8, 1, 1)
                overlay.label = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                overlay.label:SetPoint("CENTER")
                overlay:SetScript("OnClick", function(_, mouseButton)
                    if mouseButton == "RightButton" then Addon:CancelSlotPicker(true); return end
                    if not picking or InCombatLockdown() then return end
                    Addon:ToggleReadySlot(name)
                    Addon:CancelSlotPicker(true)
                    Addon:OptionsFeedback(definition.label .. (Addon.character.readySlots[name]
                        and ": ready flash enabled." or ": ready flash removed."))
                end)
                picks[name] = overlay
            end
            if PositionOverlay(overlay, button, 0) then
                local selected = self.character.readySlots[name]
                overlay:SetBackdropColor(selected and 0.1 or 0.05, selected and 0.65 or 0.3, 0.6, 0.65)
                overlay.label:SetText(selected and "On" or "+")
                overlay:Show()
                count = count + 1
            end
        end
    end
    if count == 0 then
        self:ShowOptions("cooldowns")
        self:OptionsFeedback("No visible default action-bar slots found. Show a bar and try again.", true)
        return false
    end
    picking = true
    picker:Show()
    return true
end

for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "SPELL_UPDATE_COOLDOWN" }) do ticker:RegisterEvent(event) end
ticker:SetScript("OnEvent", function(_, event)
    if not Addon.db or not Addon.character then return end
    if event == "SPELL_UPDATE_COOLDOWN" then
        Addon:PollReadyFlash(GetTime(), true)
    elseif event == "PLAYER_REGEN_DISABLED" then
        if picking then Addon:CancelSlotPicker(true); Addon:OptionsFeedback("Slot selection cancelled because combat started.") end
        if Addon.RefreshReadyOptions then Addon:RefreshReadyOptions() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        for _, definition in ipairs(tracked) do Visual(definition.name) end
        if Addon.RefreshReadyOptions then Addon:RefreshReadyOptions() end
    else
        history = {}
        StopFlashes()
    end
end)
