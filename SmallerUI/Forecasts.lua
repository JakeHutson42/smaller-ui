local _, Addon = ...
local driver = CreateFrame("Frame")
local WHITE = "Interface\\Buttons\\WHITE8X8"
local HORIZON = 5
local samples = {}
local Refresh, Tick
local periodicAvailable = false

local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Number(value)
    return Public(value) and type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function ReadableLog()
    return not C_CombatLog or not C_CombatLog.IsCombatLogRestricted or not C_CombatLog.IsCombatLogRestricted()
end
function Addon:CanPredictPeriodicResources() return periodicAvailable end
local function Views()
    local display = Addon:GetResourceDisplay()
    if not display then return {} end
    return { display.player, display.pet, unpack(display.party) }
end
local function Aura(unit, index, filter)
    if not C_UnitAuras or not C_UnitAuras.GetAuraDataByIndex then return end
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
    if ok and Public(aura) then return aura end
end
local function Source(aura, unit)
    if Public(aura.sourceUnit) and aura.sourceUnit and UnitGUID then
        local guid = UnitGUID(aura.sourceUnit)
        if Public(guid) then return guid end
    end
    if C_UnitAuras.GetAuraCasterGUID and Number(aura.auraInstanceID) then
        local ok, guid = pcall(C_UnitAuras.GetAuraCasterGUID, unit, aura.auraInstanceID)
        if ok and Public(guid) then return guid end
    end
end
local function Periodic(unit, kind)
    local unitSamples = samples[unit]
    if not periodicAvailable or not unitSamples or not ReadableLog() or not UnitGUID then return 0, false end
    local guid = UnitGUID(unit)
    if not Public(guid) or guid ~= unitSamples.guid then samples[unit] = nil; return 0, false end
    local now, total, active = GetTime(), 0, false
    local filter = kind == "heal" and "HELPFUL" or "HARMFUL"
    for index = 1, 100 do
        local aura = Aura(unit, index, filter)
        if not aura then break end
        if Number(aura.spellId) and Number(aura.expirationTime) and aura.expirationTime > now then
            local source = Source(aura, unit)
            local sample = source and unitSamples[kind .. ":" .. aura.spellId .. ":" .. source]
            if sample and not sample.expiration then
                sample.expiration = aura.expirationTime
                sample.instance = Number(aura.auraInstanceID) and aura.auraInstanceID or nil
            end
            if sample and sample.interval and sample.interval >= 0.2 and now - sample.at < sample.interval * 2.5 then
                local nextTick = sample.at + sample.interval
                if nextTick < now then nextTick = nextTick + math.ceil((now - nextTick) / sample.interval) * sample.interval end
                local untilTime = math.min(now + HORIZON, aura.expirationTime)
                local count = math.max(0, math.floor((untilTime - nextTick + 0.01) / sample.interval) + 1)
                total = total + count * sample.amount
                active = true
            end
        end
    end
    return total, active
end

function Addon:CreateResourcePredictions(view, bar)
    local clip = CreateFrame("Frame", nil, bar)
    clip:SetAllPoints(bar.fill)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(bar.fill:GetFrameLevel() + 1)
    clip:EnableMouse(false)
    bar.forecasts = { clip = clip }
    local function Segment(kind, r, g, b, alpha)
        local segment = CreateFrame("StatusBar", nil, clip)
        segment:SetStatusBarTexture(WHITE)
        segment:SetStatusBarColor(r, g, b, alpha)
        segment:EnableMouse(false)
        segment:SetMinMaxValues(0, 1)
        segment:SetValue(0)
        bar.forecasts[kind] = segment
        return segment
    end
    local direct = Segment("direct", 0.48, 0.9, 0.67, 0.95)
    direct:SetPoint("TOPLEFT", bar.fill:GetStatusBarTexture(), "TOPRIGHT")
    local hot = Segment("hot", 0.64, 0.91, 0.75, 0.6)
    hot:SetPoint("TOPLEFT", direct:GetStatusBarTexture(), "TOPRIGHT")
    local dot = Segment("dot", 0.88, 0.37, 0.32, 0.65)
    dot:SetPoint("TOPRIGHT", bar.fill:GetStatusBarTexture(), "TOPRIGHT")
    dot:SetReverseFill(true)
    if CreateUnitHealPredictionCalculator and UnitGetDetailedHealPrediction then
        view.healCalculator = CreateUnitHealPredictionCalculator()
        local modes = Enum and Enum.UnitIncomingHealClampMode
        if modes then view.healCalculator:SetIncomingHealClampMode(modes.MissingHealth) end
        view.healCalculator:SetIncomingHealOverflowPercent(1)
    end
end

function Addon:LayoutResourcePredictions(bar)
    for _, kind in ipairs({ "direct", "hot", "dot" }) do
        bar.forecasts[kind]:SetSize(math.max(0, bar.fill:GetWidth()), math.max(0, bar.fill:GetHeight()))
    end
end

function Addon:UpdateResourcePredictions(view, demo)
    local cfg = self:GetResourceSettings()
    local bars = view.health.forecasts
    local maximum = UnitExists(view.unit) and UnitHealthMax(view.unit) or 5000
    if Number(maximum) and maximum <= 0 then maximum = 1 end
    local direct, hot, dot, active = 0, 0, 0, false
    if demo then
        maximum = 5000
        direct, hot, dot = cfg.incomingHeals and 700 or 0, periodicAvailable and cfg.periodicHeals and 350 or 0,
            periodicAvailable and cfg.periodicDamage and 300 or 0
    elseif UnitExists(view.unit) and view:IsVisible() then
        local dead = UnitIsDeadOrGhost(view.unit)
        local connected = UnitIsConnected(view.unit)
        if not (Public(dead) and dead == true or Public(connected) and connected == false) then
            if cfg.incomingHeals then
                if view.healCalculator then
                    UnitGetDetailedHealPrediction(view.unit, "player", view.healCalculator)
                    direct = view.healCalculator:GetIncomingHeals()
                elseif UnitGetIncomingHeals then
                    direct = UnitGetIncomingHeals(view.unit)
                    if Public(direct) and direct == nil then direct = 0 end
                end
            end
            local hotActive, dotActive
            if cfg.periodicHeals then hot, hotActive = Periodic(view.unit, "heal") end
            if cfg.periodicDamage then dot, dotActive = Periodic(view.unit, "damage") end
            active = hotActive or dotActive or false
        end
    end
    -- Native bars/anchors handle secret amounts. Lua never adds them to health.
    for kind, value in pairs({ direct = direct, hot = hot, dot = dot }) do
        bars[kind]:SetMinMaxValues(0, maximum)
        bars[kind]:SetValue(value)
        bars[kind]:SetShown(not Number(value) or value > 0)
    end
    view.forecastDemo = demo
    view.forecastActive = active
    if active then driver:SetScript("OnUpdate", Tick) end
end

Refresh = function()
    local active = false
    for _, view in ipairs(Views()) do
        if view:IsVisible() and UnitExists(view.unit) then Addon:UpdateResourcePredictions(view, view.forecastDemo) end
        if view:IsVisible() and view.forecastActive then active = true end
    end
    if not active then driver:SetScript("OnUpdate", nil) end
end
function Addon:RefreshResourceForecasts() Refresh() end
local elapsed = 0
Tick = function(_, delta)
    elapsed = elapsed + delta
    if elapsed < 0.2 then return end
    elapsed = 0
    Refresh()
end

local function Observe()
    if not periodicAvailable or not CombatLogGetCurrentEventInfo or not ReadableLog() then return end
    local ok, timestamp, kind, _, source, _, _, _, destination, _, _, _, spell, _, _, amount = pcall(CombatLogGetCurrentEventInfo)
    if not ok or not Public(kind) or kind ~= "SPELL_PERIODIC_HEAL" and kind ~= "SPELL_PERIODIC_DAMAGE" then return end
    if not Number(timestamp) or not Number(spell) or not Number(amount) or amount <= 0
        or not Public(source) or type(source) ~= "string" or not Public(destination) or type(destination) ~= "string" then return end
    local cfg = Addon:GetResourceSettings()
    local heal = kind == "SPELL_PERIODIC_HEAL"
    if heal and not cfg.periodicHeals or not heal and not cfg.periodicDamage then return end
    for _, view in ipairs(Views()) do
        if view:IsVisible() and UnitExists(view.unit) then
            local guid = UnitGUID(view.unit)
            if Public(guid) and guid == destination then
                local data = samples[view.unit]
                if not data or data.guid ~= guid then data = { guid = guid }; samples[view.unit] = data end
                local key = (heal and "heal:" or "damage:") .. spell .. ":" .. source
                local previous = data[key]
                local interval = previous and timestamp - previous.timestamp
                if interval and (interval < 0.2 or interval > 15) then interval = nil end
                if not previous then
                    local count = 0
                    for _ in pairs(data) do count = count + 1 end
                    if count >= 101 then data = { guid = guid }; samples[view.unit] = data end
                end
                data[key] = { timestamp = timestamp, at = GetTime(),
                    interval = interval, amount = interval and (previous.amount + amount) / 2 or amount }
                Addon:UpdateResourcePredictions(view, view.forecastDemo)
            end
        end
    end
end

-- Resources.lua refreshes predictions after the live fill on health events.
for _, event in ipairs({ "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "UNIT_AURA",
    "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD", "UNIT_PET",
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_DELAYED", "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP" }) do driver:RegisterEvent(event) end
-- Query event metadata before registration. Protected callback events cannot be
-- subscribed to by an addon frame; attempting it can show Blizzard's blocked-
-- action dialog even inside pcall. Fail closed when metadata is unavailable.
local eventName = "COMBAT_LOG_EVENT_UNFILTERED"
if C_EventUtils and C_EventUtils.IsEventValid and C_EventUtils.IsCallbackEvent
    and C_EventUtils.IsEventValid(eventName) and not C_EventUtils.IsCallbackEvent(eventName)
    and CombatLogGetCurrentEventInfo and ReadableLog() then
    driver:RegisterEvent(eventName)
    periodicAvailable = true
end
driver:SetScript("OnEvent", function(_, event, unit)
    if not Addon.character or not Addon.character.resources then return end
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then Observe(); return end
    if event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then samples = {} end
    if event == "UNIT_AURA" and samples[unit] then
        -- Prune vanished auras so a refreshed application must supply fresh ticks.
        local data, keep = samples[unit], {}
        for _, filter in ipairs({ "HELPFUL", "HARMFUL" }) do
            for index = 1, 100 do
                local aura = Aura(unit, index, filter)
                if not aura then break end
                if Number(aura.spellId) then
                    local source = Source(aura, unit)
                    if source then
                        local key = (filter == "HELPFUL" and "heal:" or "damage:") .. aura.spellId .. ":" .. source
                        local sample = data[key]
                        if sample and sample.expiration and (not Number(aura.expirationTime) or sample.expiration ~= aura.expirationTime
                            or Number(aura.auraInstanceID) and sample.instance ~= aura.auraInstanceID) then data[key] = nil
                        else keep[key] = true end
                    end
                end
            end
        end
        for key in pairs(data) do if key ~= "guid" and not keep[key] then data[key] = nil end end
    end
    Refresh()
end)
