local _, Addon = ...
local button

function Addon:ValidateMinimap()
    self.db.showMinimap = self.db.showMinimap ~= false
    local angle = self.db.minimapAngle
    if type(angle) ~= "number" or angle ~= angle or math.abs(angle) == math.huge then angle = 225 end
    self.db.minimapAngle = angle % 360
end

local function Position()
    local angle = math.rad(Addon.db.minimapAngle)
    local radius = Minimap:GetWidth() / 2 + 8
    local x, y = math.cos(angle), math.sin(angle)
    if GetMinimapShape and GetMinimapShape() == "SQUARE" then
        radius = radius / math.max(math.abs(x), math.abs(y))
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * radius, y * radius)
end

function Addon:UpdateMinimap()
    if not self.db or not Minimap or InCombatLockdown() then return end
    if not button then
        button = CreateFrame("Button", "SmallerUIMinimapButton", Minimap)
        button:SetSize(32, 32)
        button:SetFrameLevel(Minimap:GetFrameLevel() + 5)
        button:RegisterForClicks("LeftButtonUp")
        button:RegisterForDrag("LeftButton")
        local icon = button:CreateTexture(nil, "BACKGROUND")
        icon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        icon:SetPoint("CENTER")
        icon:SetSize(20, 20)
        local border = button:CreateTexture(nil, "OVERLAY")
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetSize(54, 54)
        border:SetPoint("TOPLEFT")
        button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
        button:SetScript("OnClick", function() Addon:ShowOptions() end)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(Addon.displayName, 0.4, 0.75, 1)
            GameTooltip:AddLine("Click to open settings. Drag to move.", 1, 1, 1)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        button:SetScript("OnDragStart", function(self)
            if InCombatLockdown() then return end
            GameTooltip:Hide()
            self:SetScript("OnUpdate", function()
                if InCombatLockdown() then self:SetScript("OnUpdate", nil); return end
                local x, y = GetCursorPosition()
                local centerX, centerY = Minimap:GetCenter()
                local scale = Minimap:GetEffectiveScale()
                Addon.db.minimapAngle = math.deg(math.atan2(y / scale - centerY, x / scale - centerX)) % 360
                Position()
            end)
        end)
        button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    end
    Position()
    button:SetShown(self.db.showMinimap)
end
