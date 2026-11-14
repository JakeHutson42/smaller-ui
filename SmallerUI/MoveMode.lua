local _, Addon = ...
local overlay, selection, drag, selected, selectedName
local toolbar, activeScope, activeKind
local WHITE = "Interface\\Buttons\\WHITE8X8"
local function Number(value)
    return (not issecretvalue or not issecretvalue(value)) and type(value) == "number"
        and value == value and math.abs(value) < math.huge
end
local function Pixel()
    local size = PixelUtil and PixelUtil.GetPixelToUIUnitFactor and PixelUtil.GetPixelToUIUnitFactor()
    return Number(size) and size > 0 and size or 1
end
local function Rect(frame)
    if not frame then return end
    local x, y, width, height = frame:GetRect()
    local scale = frame:GetEffectiveScale()
    if not Number(x) or not Number(y) or not Number(width) or not Number(height) or not Number(scale) or scale <= 0 then return end
    return { x = x * scale, y = y * scale, width = width * scale, height = height * scale }
end
local function Descendant(frame, parent)
    while frame do
        if frame == parent then return true end
        frame = frame:GetParent()
    end
    return false
end
local function EnsureOverlay()
    if overlay then return end
    overlay = CreateFrame("Frame", "SmallerUIMoveOverlay", UIParent)
    overlay:SetIgnoreParentScale(true)
    overlay:SetScale(1)
    overlay:SetAllPoints(UIParent)
    overlay:SetFrameStrata("DIALOG")
    overlay:EnableMouse(false)
    local function Guide(name)
        local line = CreateFrame("Frame", name, overlay)
        line:EnableMouse(false)
        line.texture = line:CreateTexture(nil, "OVERLAY")
        line.texture:SetAllPoints()
        line.texture:SetColorTexture(0.95, 0.78, 0.35, 0.7)
        line:Hide()
        return line
    end
    overlay.vertical = Guide("SmallerUIMoveVerticalGuide")
    overlay.horizontal = Guide("SmallerUIMoveHorizontalGuide")
    selection = CreateFrame("Frame", "SmallerUIMoveSelection", overlay, "BackdropTemplate")
    selection:SetFrameLevel(100)
    selection:EnableMouse(false)
    selection.label = selection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    selection.label:SetWordWrap(false)
    selection:Hide()
end
local function HideGuides()
    if overlay then overlay.vertical:Hide(); overlay.horizontal:Hide() end
end
local function DrawSelection()
    if not selected or not selected:IsVisible() then selection:Hide(); return end
    local bounds, screen = Rect(selected), Rect(UIParent)
    if not bounds or not screen then selection:Hide(); return end
    local pixel = Pixel()
    if selection.pixel ~= pixel then
        selection:SetBackdrop({ edgeFile = WHITE, edgeSize = pixel })
        selection.pixel = pixel
    end
    selection:SetBackdropBorderColor(1, 0.82, 0.3, 1)
    selection:SetSize(bounds.width + 6 * pixel, bounds.height + 6 * pixel)
    selection:ClearAllPoints()
    selection:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.x - screen.x - 3 * pixel, bounds.y - screen.y - 3 * pixel)
    local labelWidth = math.max(1, math.min(240, screen.width - 8))
    local labelLeft = math.max(screen.x + 4, math.min(screen.x + screen.width - labelWidth - 4, bounds.x))
    selection.label:ClearAllPoints()
    selection.label:SetWidth(labelWidth)
    if bounds.y + bounds.height + 20 > screen.y + screen.height then
        selection.label:SetPoint("TOPLEFT", selection, "TOPLEFT", labelLeft - bounds.x + 3 * pixel, -4)
    else selection.label:SetPoint("BOTTOMLEFT", selection, "TOPLEFT", labelLeft - bounds.x + 3 * pixel, 4) end
    selection.label:SetText(selectedName)
    selection:Show()
end

function Addon:SelectResourceMoveTarget(target, name, scope, kind)
    if not self:IsEditingResources() or InCombatLockdown() or not target then return false end
    if drag and drag.target ~= target then return false end
    EnsureOverlay()
    if scope and scope ~= "element" then self:HideElementMoveTarget() end
    selected, selectedName = target, name
    overlay:Show()
    if scope then
        activeScope, activeKind = scope, kind
        if toolbar then toolbar:RefreshSelection() end
    end
    DrawSelection()
    return true
end

function Addon:StartResourceMove(target, anchor, scope, name, kind, linked)
    if not self:IsEditingResources() or InCombatLockdown() or drag then return false end
    local bounds, anchorBounds = Rect(target), Rect(anchor)
    local x, y = GetCursorPosition()
    if not bounds or not anchorBounds or not Number(x) or not Number(y) then return false end
    if name then self:SelectResourceMoveTarget(target, name, scope, kind) end
    target:StopMovingOrSizing()
    target:SetClampedToScreen(false) -- The raw cursor and our screen clamp stay independent of snapping.
    drag = { target = target, anchor = anchor, scope = scope, kind = kind, linked = linked,
        bounds = bounds, anchorBounds = anchorBounds, cursorX = x, cursorY = y,
        sawHeld = IsMouseButtonDown("LeftButton") }
    return true
end

local function Candidates()
    local result, display = {}, Addon:GetResourceDisplay()
    local function Add(frame, scope, kind)
        if not frame or not frame:IsVisible() or Descendant(frame, drag.target) then return end
        if drag.scope == "party" and scope == "party" and (drag.linked or kind == drag.kind or not kind) then return end
        if not kind and scope == drag.scope then return end
        -- The seal follows personal health, even when that health bar is unlinked.
        if kind == "seal" and Addon:GetResourceSettings().seal.linked and drag.scope == "player"
            and (drag.linked or drag.kind == "health") then return end
        local bounds = Rect(frame)
        if bounds then result[#result + 1] = bounds end
    end
    local function View(view)
        Add(view, view.scope)
        Add(view.health, view.scope, "health")
        Add(view.power, view.scope, "power")
    end
    View(display.player)
    View(display.pet)
    Add(display.partyRoot, "party")
    for _, view in ipairs(display.party) do View(view) end
    Add(display.player.seal, "player", "seal")
    Add(Addon:GetSwingTimerFrame(), "swing", "swing")
    return result
end
local function ClampOrigin(value, size, low, high)
    if size > high - low then return math.max(high - size, math.min(low, value)) end
    return math.max(low, math.min(high - size, value))
end
local function Features(bounds, axis, delta)
    local low = bounds[axis] + delta
    local size = axis == "x" and bounds.width or bounds.height
    return { low, low + size / 2, low + size }
end
local function Snap(axis, delta, targets, screen)
    local best, guide, distance = 0, nil, 8 * Pixel() + 0.000001
    local source = Features(drag.bounds, axis, delta)
    if drag.anchor ~= drag.target then
        for _, value in ipairs(Features(drag.anchorBounds, axis, delta)) do source[#source + 1] = value end
    end
    local marks = Features(screen, axis, 0)
    for _, target in ipairs(targets) do
        for _, value in ipairs(Features(target, axis, 0)) do marks[#marks + 1] = value end
    end
    for _, mark in ipairs(marks) do
        for _, value in ipairs(source) do
            local offset = mark - value
            if math.abs(offset) < distance then best, guide, distance = offset, mark, math.abs(offset) end
        end
    end
    return best, guide
end
local function DrawGuides(screen, x, y)
    HideGuides()
    local pixel = Pixel()
    if x then
        overlay.vertical:ClearAllPoints()
        overlay.vertical:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x - screen.x, 0)
        overlay.vertical:SetSize(pixel, screen.height)
        overlay.vertical:Show()
    end
    if y then
        overlay.horizontal:ClearAllPoints()
        overlay.horizontal:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, y - screen.y)
        overlay.horizontal:SetSize(screen.width, pixel)
        overlay.horizontal:Show()
    end
end

function Addon:UpdateResourceMoveMode()
    if not overlay or not self:IsEditingResources() then return end
    if drag and not drag.finishing then
        if IsMouseButtonDown("LeftButton") then drag.sawHeld = true
        elseif drag.sawHeld then
            if drag.scope == "seal" then self:EndSealDrag()
            elseif drag.scope == "swing" then self:EndSwingTimerDrag()
            elseif drag.scope == "element" then self:EndElementDrag()
            else self:EndResourceDrag() end
            return
        end
    end
    if drag and not InCombatLockdown() then
        local x, y = GetCursorPosition()
        local screen = Rect(UIParent)
        if Number(x) and Number(y) and screen then
            local rawX, rawY = x - drag.cursorX, y - drag.cursorY
            local offsetX, offsetY, guideX, guideY = 0, 0, nil, nil
            local shift = IsShiftKeyDown and IsShiftKeyDown()
            if not shift then
                local targets = Candidates()
                offsetX, guideX = Snap("x", rawX, targets, screen)
                offsetY, guideY = Snap("y", rawY, targets, screen)
            end
            local left = ClampOrigin(drag.bounds.x + rawX + offsetX, drag.bounds.width, screen.x, screen.x + screen.width)
            local bottom = ClampOrigin(drag.bounds.y + rawY + offsetY, drag.bounds.height, screen.y, screen.y + screen.height)
            if math.abs(left - drag.bounds.x - rawX - offsetX) > 0.001 then guideX = nil end
            if math.abs(bottom - drag.bounds.y - rawY - offsetY) > 0.001 then guideY = nil end
            local scale = drag.target:GetEffectiveScale()
            drag.target:ClearAllPoints()
            drag.target:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", (left - screen.x) / scale, (bottom - screen.y) / scale)
            drag.snapX, drag.snapY, drag.shift = guideX, guideY, shift
            DrawGuides(screen, guideX, guideY)
        end
    end
    DrawSelection()
end

function Addon:FinishResourceMove()
    if not drag then return end
    -- Re-evaluate modifiers and the final pointer position on release.
    drag.finishing = true
    self:UpdateResourceMoveMode()
    local previous = drag
    drag = nil
    previous.target:SetClampedToScreen(true)
    HideGuides()
end

function Addon:CloseResourceMoveMode()
    if drag then drag.target:SetClampedToScreen(true) end
    drag, selected, selectedName = nil, nil, nil
    activeScope, activeKind = nil, nil
    if overlay then HideGuides(); selection:Hide(); overlay:Hide() end
end

function Addon:GetResourceMoveState() return drag end

local targets = {
    { "player:health", "Personal health", "player", "health" },
    { "player:power", "Personal power", "player", "power" },
    { "party:health", "Party health", "party", "health" },
    { "party:power", "Party power", "party", "power" },
    { "pet:health", "Pet health", "pet", "health" },
    { "pet:power", "Pet power", "pet", "power" },
    { "swing:swing", "Swing timer", "swing", "swing" },
}
local sealTarget = { "seal:seal", "Paladin seal", "seal", "seal" }

function Addon:CreateResourceMoveToolbar()
    if toolbar then return toolbar end
    local UI = self.OptionsUI
    toolbar = CreateFrame("Frame", "SmallerUIResourceEditor", UIParent, "BackdropTemplate")
    toolbar:Hide()
    toolbar:SetIgnoreParentScale(true)
    toolbar:SetFrameStrata("DIALOG")
    toolbar:SetFrameLevel(110)
    toolbar:SetSize(570, 115)
    toolbar:SetPoint("TOP", 0, -40)
    toolbar:SetMovable(true)
    toolbar:SetClampedToScreen(true)
    toolbar:EnableMouse(true)
    toolbar:RegisterForDrag("LeftButton")
    toolbar:SetScript("OnDragStart", function(self) self:StartMoving() end)
    toolbar:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    UI.Backdrop(toolbar, { 0.048, 0.065, 0.085, 0.99 }, { 0.83, 0.66, 0.35, 1 })
    UI.Label(toolbar, "Move Mode", 16, -12, "GameFontNormalLarge")
    UI.Label(toolbar, "Drag to move  /  Shift to bypass snap", 162, -16, "GameFontHighlightSmall")
    local choices, byKey = {}, {}
    for _, entry in ipairs(targets) do choices[#choices + 1] = entry; byKey[entry[1]] = entry end
    if self:IsPaladin() then choices[#choices + 1] = sealTarget; byKey[sealTarget[1]] = sealTarget end
    local function Choices()
        local available = { unpack(choices) }
        for _, entry in ipairs(Addon:GetElementMoveChoices()) do
            available[#available + 1] = entry
            byKey[entry[1]] = entry
        end
        return available
    end
    local select = UI.Select(toolbar, "SmallerUIMoveTarget", 16, -42, 172, Choices, function()
        return activeScope and activeScope .. ":" .. activeKind
    end, function(key)
        local entry = byKey[key]
        Addon:SelectMoveElement(entry[3], entry[4])
    end)
    local function Adjust(factor)
        if not activeScope or drag or InCombatLockdown() then return end
        local _, resize = Addon:GetMoveElementControls(activeScope, activeKind)
        resize(factor)
        DrawSelection()
    end
    local smaller = UI.Button(toolbar, nil, "-", 200, -42, 32, function() Adjust(1 / 1.1) end)
    UI.Tooltip(smaller, "Scale down")
    local larger = UI.Button(toolbar, nil, "+", 238, -42, 32, function() Adjust(1.1) end)
    UI.Tooltip(larger, "Scale up")
    local link = UI.Switch(toolbar, nil, "Group", 286, -42, function(enabled)
        if not activeScope or drag then toolbar:RefreshSelection(); return end
        local _, _, setLinked = Addon:GetMoveElementControls(activeScope, activeKind)
        if setLinked then setLinked(enabled) end
        Addon:SelectMoveElement(activeScope, activeKind)
    end, "Move and scale the bars together. For the seal, group it with personal health.")
    link:SetWidth(100)
    local reset = UI.Button(toolbar, nil, "Reset", 458, -42, 96, function()
        if activeScope ~= "element" or drag then return end
        Addon:ResetElementMoveTarget()
        DrawSelection()
    end)
    UI.Tooltip(reset, "Restore the selected Blizzard frame's position and family scale.")
    function toolbar:RefreshSelection()
        reset:SetShown(activeScope == "element")
        select:GenerateMenu()
        local linked = Addon:GetMoveElementControls(activeScope, activeKind)
        link:SetShown(linked ~= nil)
        link:SetChecked(linked)
    end
    UI.Button(toolbar, "SmallerUIResourceDemo", "Preview damage / heal", 16, -77, 172,
        function() Addon:TestResourceDamage() end)
    UI.Button(toolbar, "SmallerUIResourceCancel", "Cancel", 312, -77, 84,
        function() Addon:FinishResourceEdit(false) end)
    UI.Button(toolbar, "SmallerUIResourceDone", "Done & Settings", 408, -77, 146,
        function() Addon:FinishResourceEdit(true) end)
    toolbar:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
        if Addon:IsEditingResources() then Addon:FinishResourceEdit(false) end
    end)
    table.insert(UISpecialFrames, toolbar:GetName())
    return toolbar
end
