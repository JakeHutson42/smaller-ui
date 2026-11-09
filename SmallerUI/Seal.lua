local _, Addon = ...
local driver = CreateFrame("Frame")
-- Seed localized names for every seal family; ranks share their family's name.
local seals = { 20154, 21084, 21082, 20163, 20375, 20164, 20165, 20166, 31801, 53736, 31892, 53720 }
local sealIDs, names = {}, {}
local icon, dragging, pendingSeal
local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function Info(spell)
    if C_Spell and C_Spell.GetSpellInfo then return C_Spell.GetSpellInfo(spell) end
    if GetSpellInfo then
        local name, _, texture = GetSpellInfo(spell)
        return name and { name = name, iconID = texture }
    end
end
local function RefreshNames()
    names = {}
    for _, spell in ipairs(seals) do
        sealIDs[spell] = true
        local info = Info(spell)
        if info and Public(info.name) and info.name then names[info.name] = true end
    end
end
local function IsSeal(spell, name)
    if Number(spell) and sealIDs[spell] then return true end
    if Public(name) and name and names[name] then return true end
    if Number(spell) then
        local info = Info(spell)
        return info and Public(info.name) and names[info.name] == true
    end
    return false
end

local function VerticalOffset(view)
    if not view.power:IsShown() then return 0 end
    local _, bottom, _, height = view.health:GetRect()
    local _, powerBottom, _, powerHeight = view.power:GetRect()
    if not Number(bottom) or not Number(height) or not Number(powerBottom) or not Number(powerHeight) then return 0 end
    return (math.min(bottom, powerBottom) + math.max(bottom + height, powerBottom + powerHeight)) / 2 - bottom - height / 2
end

function Addon:EndSealDrag()
    if not icon or not dragging then return end
    self:FinishResourceMove()
    icon:StopMovingOrSizing()
    local view = self:GetResourceDisplay().player
    if self:IsEditingResources() and not InCombatLockdown() then
        local x, y = icon:GetCenter()
        local left, bottom, width, height = view.health:GetRect()
        if Number(x) and Number(y) and Number(left) and Number(bottom) and Number(width) and Number(height) then
            local ratio = icon:GetEffectiveScale() / view.health:GetEffectiveScale()
            local cfg = self:GetResourceSettings().seal
            cfg.x = math.max(-32768, math.min(32768, x * ratio - icon:GetWidth() / 2 - left - width))
            cfg.y = math.max(-32768, math.min(32768, y * ratio - bottom - height / 2 - VerticalOffset(view)))
        end
    end
    dragging = nil
    self:LayoutSealIndicator(view, self:IsEditingResources())
end
function Addon:IsPaladin()
    if not UnitClass then return false end
    local _, class = UnitClass("player")
    return Public(class) and class == "PALADIN"
end

function Addon:LayoutSealIndicator(view, editing)
    if not icon then return end
    local cfg = self:GetResourceSettings().seal
    if not editing then icon:StopMovingOrSizing(); dragging = nil end
    if not dragging then
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", view.health, "RIGHT", cfg.x, cfg.y + VerticalOffset(view))
    end
    icon:SetSize(cfg.size, cfg.size)
    icon:EnableMouse(editing and self:IsPaladin() and cfg.enabled)
end

function Addon:CreateSealIndicator(view)
    if icon then return end
    icon = CreateFrame("Frame", "SmallerUISealIndicator", view, "BackdropTemplate")
    view.seal = icon
    icon:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
    icon:SetBackdropColor(0.03, 0.04, 0.05, 1)
    icon:SetMovable(true)
    icon:SetClampedToScreen(true)
    icon:RegisterForDrag("LeftButton")
    icon.texture = icon:CreateTexture(nil, "ARTWORK")
    icon.texture:SetPoint("TOPLEFT", 2, -2)
    icon.texture:SetPoint("BOTTOMRIGHT", -2, 2)
    icon.texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon.reminder = icon:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    icon.reminder:SetPoint("CENTER")
    icon:SetScript("OnDragStart", function(self)
        if not Addon:IsEditingResources() or InCombatLockdown() then return end
        dragging = Addon:StartResourceMove(self, self, "seal", "Paladin seal", "seal", false)
    end)
    icon:SetScript("OnDragStop", function() Addon:EndSealDrag() end)
    icon:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then Addon:SelectResourceMoveTarget(icon, "Paladin seal") end
    end)
    icon:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.status == "active" and "Active seal" or self.status == "missing" and "Reactivate your seal" or "Seal status unavailable")
        GameTooltip:Show()
    end)
    icon:SetScript("OnLeave", function() GameTooltip:Hide() end)
    RefreshNames()
end

function Addon:UpdateSealIndicator()
    if not icon then return end
    local cfg = self:GetResourceSettings()
    local editing = self:IsEditingResources()
    icon:SetShown(self:IsPaladin() and cfg.seal.enabled and (cfg.enabled or editing))
    if not icon:IsShown() then return end
    local active, unknown
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 100 do
            local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, "player", index, "HELPFUL")
            if not ok or not Public(aura) then unknown = true; break end
            if not aura then break end
            if IsSeal(aura.spellId, aura.name) then
                active = active or aura
                if Number(aura.spellId) and aura.spellId == cfg.seal.lastSpellID then active = aura; break end
            elseif not Public(aura.spellId) or not Public(aura.name) then unknown = true end
        end
    else unknown = true end
    -- Spellcast success can precede UNIT_AURA. An old aura must not overwrite
    -- the newly cast seal's reminder while the aura list catches up.
    local spell = cfg.seal.lastSpellID
    if active and Number(active.spellId) then
        spell = active.spellId
        if not pendingSeal or spell == pendingSeal then cfg.seal.lastSpellID = spell end
    end
    local info = Number(spell) and spell > 0 and Info(spell) or Info(20154)
    local texture = info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
    if active and (not Public(active.icon) or active.icon ~= nil) then texture = active.icon end
    icon.texture:SetTexture(texture)
    icon.texture:SetDesaturated(active == nil)
    icon.texture:SetAlpha(active and 1 or 0.45)
    icon.status = active and "active" or unknown and "unknown" or "missing"
    icon.reminder:SetText(active and "" or unknown and "?" or "!")
    icon:SetBackdropBorderColor(active and 0.2 or 0.85, active and 0.75 or 0.67, active and 0.4 or 0.3, 1)
end

local function RecheckAfterCast(spell)
    pendingSeal = spell
    local nextCheck = GetTime()
    local deadline = nextCheck + 1
    driver:SetScript("OnUpdate", function(self)
        local now = GetTime()
        if now < nextCheck then return end
        nextCheck = now + 0.1
        if now >= deadline or not icon:IsShown() then
            pendingSeal = nil
            self:SetScript("OnUpdate", nil)
        end
        -- Aura data can catch up after both the cast and aura event handlers.
        Addon:UpdateSealIndicator()
    end)
end

for _, event in ipairs({ "UNIT_AURA", "UNIT_SPELLCAST_SUCCEEDED", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED", "PLAYER_ALIVE", "PLAYER_DEAD" }) do driver:RegisterEvent(event) end
driver:SetScript("OnEvent", function(_, event, unit, _, spell)
    if not Addon.character or not Addon.character.resources then return end
    if event:sub(1, 5) == "UNIT_" and (not Public(unit) or unit ~= "player") then return end
    if event == "SPELLS_CHANGED" or event == "PLAYER_ENTERING_WORLD" then RefreshNames() end
    if event == "UNIT_SPELLCAST_SUCCEEDED" and Addon:IsPaladin() then
        if IsSeal(spell) then
            Addon:GetResourceSettings().seal.lastSpellID = spell
            if icon and icon:IsShown() then RecheckAfterCast(spell) end
        elseif not Public(spell) and icon and icon:IsShown() and icon.status ~= "active" then
            RecheckAfterCast(pendingSeal)
        end
    end
    Addon:UpdateSealIndicator()
end)
