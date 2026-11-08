local _, Addon = ...
Addon.elements = {
    { key = "minimap", label = "Minimap", names = { "MinimapCluster", "Minimap" }, first = true },
    { key = "chat", label = "Chat windows", chat = true },
    { key = "actionbars", label = "Action bars", names = { "MainMenuBar", "MainActionBar",
        "MultiBarBottomLeft", "MultiBarBottomRight", "MultiBarLeft", "MultiBarRight",
        "MultiBar5", "MultiBar6", "MultiBar7", "PetActionBarFrame", "StanceBarFrame", "PossessBarFrame" } },
    { key = "player", label = "Player frame", names = { "PlayerFrame" } },
    { key = "target", label = "Target frame", names = { "TargetFrame" } },
    { key = "quests", label = "Quest tracker", names = { "ObjectiveTrackerFrame", "WatchFrame", "QuestWatchFrame" }, first = true },
}
local snapshots, active = {}, {}

function Addon:GetElement(key)
    for _, element in ipairs(self.elements) do
        if element.key == key then return element end
    end
end

function Addon:IsValidElementScale(scale)
    return type(scale) == "number" and scale >= 0.25 and scale <= 2
end

function Addon:ValidateElements()
    if type(self.db.elements) ~= "table" then self.db.elements = {} end
    for key, scale in pairs(self.db.elements) do
        if not self:GetElement(key) or not self:IsValidElementScale(scale) then self.db.elements[key] = nil end
    end
end

local function Usable(frame)
    return frame and frame.GetScale and frame.GetEffectiveScale and frame.GetParent
        and not (frame.IsForbidden and frame:IsForbidden())
end

local function GetFrames(element)
    local frames, seen = {}, {}
    local function Add(frame)
        if Usable(frame) and not seen[frame] then
            seen[frame] = true
            frames[#frames + 1] = frame
            return true
        end
    end
    if element.chat then
        for index = 1, (NUM_CHAT_WINDOWS or 10) do Add(_G["ChatFrame" .. index]) end
    else
        for _, name in ipairs(element.names) do
            if Add(_G[name]) and element.first then break end
        end
    end
    local roots = {}
    for _, frame in ipairs(frames) do
        local parent, nested = frame:GetParent(), false
        while parent do
            if seen[parent] then nested = true; break end
            parent = parent:GetParent()
        end
        if not nested then roots[#roots + 1] = frame end
    end
    return roots -- A root already controls its descendants; don't scale twice.
end

function Addon:ElementAvailable(key)
    return #GetFrames(self:GetElement(key)) > 0
end

-- Rebuild the original effective scale from the parent chain. Snapshots for
-- managed parents also handle late-loaded and nested frames correctly.
local function OriginalEffective(frame)
    if frame == UIParent then return Addon.baseRootScale end
    local original = snapshots[frame]
    local scale = original and original.scale or frame:GetScale()
    if frame:IsIgnoringParentScale() then return scale end
    local parent = frame:GetParent()
    return scale * (parent and OriginalEffective(parent) or 1)
end

function Addon:CaptureElements()
    active = {}
    for _, element in ipairs(self.elements) do
        for _, frame in ipairs(GetFrames(element)) do
            if not snapshots[frame] then snapshots[frame] = { scale = frame:GetScale() } end
            active[#active + 1] = { frame = frame, key = element.key }
        end
    end
    local function Depth(frame)
        local depth = 0
        while frame do depth = depth + 1; frame = frame:GetParent() end
        return depth
    end
    table.sort(active, function(a, b) return Depth(a.frame) < Depth(b.frame) end)
end

function Addon:ApplyElements()
    for _, item in ipairs(active) do
        local frame, setting = item.frame, self.db.elements[item.key]
        local original = snapshots[frame]
        local desired
        if setting then
            local inherited = frame:GetEffectiveScale() / frame:GetScale()
            desired = OriginalEffective(frame) * setting / inherited
            original.modified = true
        elseif original.modified then
            desired = original.scale
            original.modified = false
        end
        if desired and math.abs(frame:GetScale() - desired) > 0.00001 then frame:SetScale(desired) end
    end
end
