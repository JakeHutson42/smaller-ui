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
local moveLayouts, moveFrame, moveTarget, moveStart

function Addon:GetElement(key)
    for _, element in ipairs(self.elements) do
        if element.key == key then return element end
    end
end

function Addon:IsValidElementScale(scale)
    return type(scale) == "number" and scale >= 0.25 and scale <= 2
end

function Addon:ValidateElements()
    local layout = self.db.elementLayouts
    if type(layout) ~= "table" then layout = {}; self.db.elementLayouts = layout end
    for key, settings in pairs(layout) do
        if not self:GetElement(key) or type(settings) ~= "table" then
            layout[key] = nil
        else
            settings.linked = settings.linked ~= false
            if type(settings.frames) ~= "table" then settings.frames = {} end
            for name, offset in pairs(settings.frames) do
                if type(name) ~= "string" or type(offset) ~= "table" then
                    settings.frames[name] = nil
                else
                    for _, axis in ipairs({ "x", "y" }) do
                        local value = offset[axis]
                        if type(value) ~= "number" or not (value >= -32768 and value <= 32768) then offset[axis] = 0 end
                    end
                    if not self:IsValidElementScale(offset.scale) then offset.scale = nil end
                end
            end
        end
    end
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
    local element = self:GetElement(key)
    return element and #GetFrames(element) > 0
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

local ApplyElementPosition

function Addon:ApplyElements()
    if InCombatLockdown() then return end
    local offsets = {}
    for _, item in ipairs(active) do
        local family = self.db.elementLayouts[item.key]
        if family then offsets[item.frame] = family.frames[item.frame:GetName()] end
    end
    for _, item in ipairs(active) do
        local frame, setting = item.frame, self.db.elements[item.key]
        local original = snapshots[frame]
        local offset = offsets[frame]
        setting = offset and offset.scale or setting
        local desired
        if setting then
            local inherited = frame:GetEffectiveScale() / frame:GetScale()
            desired = OriginalEffective(frame) * setting / inherited
            original.modified = true
        elseif original.modified then
            desired = original.scale
            original.modified = false
        end
        if not (frame.IsForbidden and frame:IsForbidden()) then
            if desired and math.abs(frame:GetScale() - desired) > 0.00001 then frame:SetScale(desired) end
            ApplyElementPosition(frame, original, offset, offsets)
        end
    end
end

-- Keep the client's anchor targets and translate every point by the same distance.
ApplyElementPosition = function(frame, original, offset, offsets)
    if not frame.GetNumPoints or not frame.GetPoint then return end
    local scale = frame:GetEffectiveScale()
    local x, y = offset and offset.x or 0, offset and offset.y or 0
    if not offset and not original.points then return end
    local points = {}
    for index = 1, frame:GetNumPoints() do
        local point, relative, relativePoint, px, py = frame:GetPoint(index)
        if issecretvalue and (issecretvalue(point) or issecretvalue(relative) or issecretvalue(relativePoint)
            or issecretvalue(px) or issecretvalue(py)) then return end
        if point then points[#points + 1] = { point, relative, relativePoint, px or 0, py or 0 } end
    end
    if #points == 0 then return end
    local same = original.applied and #original.applied == #points
    if same then
        for index, point in ipairs(points) do
            local previous = original.applied[index]
            if point[1] ~= previous[1] or point[2] ~= previous[2] or point[3] ~= previous[3]
                or math.abs(point[4] - previous[4]) > 0.001 or math.abs(point[5] - previous[5]) > 0.001 then
                same = false
                break
            end
        end
    end
    local base = same and original.points or points
    if not offset and not same then
        original.points, original.applied = nil, nil
        return
    end
    local applied, changed = {}, false
    for index, point in ipairs(base) do
        local relative = type(point[2]) == "string" and _G[point[2]] or point[2]
        local anchor = offset and offsets[relative]
        local px = point[4] + (x - (anchor and anchor.x or 0)) / scale
        local py = point[5] + (y - (anchor and anchor.y or 0)) / scale
        changed = changed or math.abs(px - points[index][4]) > 0.001 or math.abs(py - points[index][5]) > 0.001
        applied[index] = { point[1], point[2], point[3], px, py }
    end
    if changed then
        frame:ClearAllPoints()
        for _, point in ipairs(applied) do frame:SetPoint(unpack(point, 1, 5)) end
    end
    original.points, original.applied = base, applied
    if not offset then original.points, original.applied = nil, nil end
end

local function CopyElementLayouts(source)
    local copy = {}
    for key, settings in pairs(source) do
        local frames = {}
        for name, offset in pairs(settings.frames) do frames[name] = { x = offset.x, y = offset.y, scale = offset.scale } end
        copy[key] = { linked = settings.linked, frames = frames }
    end
    return copy
end

function Addon:BeginElementEdit()
    moveLayouts = CopyElementLayouts(self.db.elementLayouts)
end

function Addon:FinishElementEdit(save)
    if not moveLayouts then return end
    self:EndElementDrag()
    if save then self.db.elementLayouts = moveLayouts end
    moveLayouts, moveTarget = nil, nil
    if moveFrame then moveFrame:Hide() end
    if save then self:CaptureElements(); self:ApplyElements() end
end

local function CanMove(frame)
    return not InCombatLockdown() and frame:IsVisible() and frame:GetName() and frame.GetNumPoints and frame:GetNumPoints() > 0
end

local actionBarLabels = {
    MainMenuBar = "Main action bar", MainActionBar = "Main action bar",
    MultiBarBottomLeft = "Bottom left bar", MultiBarBottomRight = "Bottom right bar",
    MultiBarLeft = "Right bar 2", MultiBarRight = "Right bar 1",
    PetActionBarFrame = "Pet action bar", StanceBarFrame = "Stance bar", PossessBarFrame = "Possess bar",
}

function Addon:GetElementMoveChoices()
    local choices = {}
    for _, element in ipairs(self.elements) do
        local frames = GetFrames(element)
        for _, frame in ipairs(frames) do
            if CanMove(frame) then
                local name = frame:GetName()
                local label = element.label
                if #frames > 1 then
                    if element.chat then
                        label = "Chat " .. name:match("%d+$")
                    else
                        label = actionBarLabels[name] or "Action bar " .. (name:match("%d+$") or "")
                    end
                end
                choices[#choices + 1] = { "element:" .. element.key .. "/" .. name, label, "element", element.key .. "/" .. name }
            end
        end
    end
    return choices
end

local function FrameOffset(layout, frame)
    local name = frame:GetName()
    local offset = layout.frames[name]
    if not offset then offset = { x = 0, y = 0 }; layout.frames[name] = offset end
    return offset
end

local function CurrentInheritedMultiplier(frame)
    local original = snapshots[frame]
    return (original and original.scale or frame:GetScale()) * frame:GetEffectiveScale()
        / (frame:GetScale() * OriginalEffective(frame))
end

local function PositionMoveFrame()
    local target = moveTarget
    local left, bottom, right, top
    local centerX, centerY = UIParent:GetCenter()
    local rootScale = UIParent:GetEffectiveScale()
    for _, frame in ipairs(target.frames) do
        local scale = frame:GetEffectiveScale()
        local x, y, width, height = frame:GetRect()
        local public = not issecretvalue or not (issecretvalue(x) or issecretvalue(y)
            or issecretvalue(width) or issecretvalue(height) or issecretvalue(scale))
        if public and x and y and width and height then
            local offset = FrameOffset(target.layout, frame)
            local saved = Addon.db.elementLayouts[target.key]
            saved = saved and saved.frames[frame:GetName()]
            local family = Addon.db.elements[target.key]
            local current = saved and saved.scale or family
                or scale / OriginalEffective(frame)
            local desired = offset.scale or family or CurrentInheritedMultiplier(frame)
            x = x * scale + offset.x - (saved and saved.x or 0)
            y = y * scale + offset.y - (saved and saved.y or 0)
            width, height = width * scale * desired / current, height * scale * desired / current
            left, bottom = math.min(left or x, x), math.min(bottom or y, y)
            right, top = math.max(right or x + width, x + width), math.max(top or y + height, y + height)
        end
    end
    if not left then return false end
    moveFrame:ClearAllPoints()
    moveFrame:SetPoint("CENTER", UIParent, "CENTER", (left + right) / 2 - centerX * rootScale, (bottom + top) / 2 - centerY * rootScale)
    moveFrame:SetSize(math.max(1, right - left), math.max(1, top - bottom))
    moveFrame:Show()
    return true
end

function Addon:SelectElementMoveTarget(id)
    if not moveLayouts or self:GetResourceMoveState() then return false end
    local key, name = id:match("^([^/]+)/(.+)$")
    local element = self:GetElement(key)
    if not element then return false end
    local layout = moveLayouts[key] or { linked = true, frames = {} }
    local family, frames = {}, {}
    for _, frame in ipairs(GetFrames(element)) do
        if CanMove(frame) then
            family[#family + 1] = frame
            if layout.linked or frame:GetName() == name then frames[#frames + 1] = frame end
        end
    end
    if #frames == 0 then return false end
    moveLayouts[key] = layout
    moveTarget = { key = key, layout = layout, family = family, frames = frames }
    if not moveFrame then
        moveFrame = CreateFrame("Frame", "SmallerUIElementMoveTarget", UIParent, "BackdropTemplate")
        self.OptionsUI.Backdrop(moveFrame, { 0.08, 0.16, 0.18, 0.33 }, { 0.83, 0.66, 0.35, 0.45 })
        moveFrame:SetIgnoreParentScale(true)
        moveFrame:SetFrameStrata("HIGH")
        moveFrame:EnableMouse(true)
        moveFrame:RegisterForDrag("LeftButton")
        moveFrame:SetScript("OnDragStart", function(frame)
            if Addon:StartResourceMove(frame, frame, "element", nil, "element", false) then
                local x, y = frame:GetCenter()
                moveStart = { x, y }
            end
        end)
        moveFrame:SetScript("OnDragStop", function() Addon:EndElementDrag() end)
    end
    if not PositionMoveFrame() then return false end
    return self:SelectResourceMoveTarget(moveFrame, element.label, "element", id)
end

function Addon:HideElementMoveTarget()
    if moveFrame then moveFrame:Hide() end
end

function Addon:EndElementDrag()
    if not moveStart then return end
    self:FinishResourceMove()
    if not InCombatLockdown() then
        local x, y = moveFrame:GetCenter()
        for _, frame in ipairs(moveTarget.frames) do
            local offset = FrameOffset(moveTarget.layout, frame)
            offset.x = math.max(-32768, math.min(32768, offset.x + x - moveStart[1]))
            offset.y = math.max(-32768, math.min(32768, offset.y + y - moveStart[2]))
        end
        PositionMoveFrame()
    end
    moveStart = nil
end

function Addon:GetElementMoveControls()
    local target = moveTarget
    local linked
    if #target.family > 1 then linked = target.layout.linked end
    return linked, function(factor)
        for _, frame in ipairs(target.frames) do
            local offset = FrameOffset(target.layout, frame)
            local scale = offset.scale or self.db.elements[target.key] or CurrentInheritedMultiplier(frame)
            offset.scale = math.max(0.25, math.min(2, scale * factor))
        end
        PositionMoveFrame()
    end, function(linked) target.layout.linked = linked end
end

function Addon:ResetElementMoveTarget()
    for _, frame in ipairs(moveTarget.frames) do
        moveTarget.layout.frames[frame:GetName()] = nil
    end
    PositionMoveFrame()
end

function Addon:ClearElementScaleOverrides(key)
    local settings = self.db.elementLayouts[key]
    if settings then
        for _, offset in pairs(settings.frames) do offset.scale = nil end
    end
end
