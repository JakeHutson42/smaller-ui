local addonName, Addon = ...
local frame = CreateFrame("Frame")
local loggedIn, resetPending = false, false
local globalModified = false
Addon.displayName = "Forever QoL"
Addon.MIN_SCALE, Addon.MAX_SCALE = 0.10, 1.50

function Addon:Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccff" .. self.displayName .. ":|r " .. message)
end

function Addon:IsValidScale(value)
    return type(value) == "number" and value >= self.MIN_SCALE and value <= self.MAX_SCALE
end

function Addon:IsResetPending()
    return resetPending
end

function Addon:RefreshOptions() end -- Options.lua replaces this before login.

function Addon:Apply()
    if not loggedIn or not self.db then return end
    if InCombatLockdown() then
        self:RefreshOptions(false)
        return -- PLAYER_REGEN_ENABLED retries the latest saved request.
    end
    if resetPending then
        resetPending = false
        ReloadUI() -- Restore the client's scale without changing its CVars.
        return
    end
    self:CaptureElements() -- Snapshot before changing their parent's scale.
    if self.db.enabled then
        if math.abs(UIParent:GetScale() - self.db.scale) > 0.00001 then UIParent:SetScale(self.db.scale) end
        globalModified = true
    elseif globalModified then
        -- An element edit can cancel a queued reset. Restore the global scale
        -- as well, so the disabled global override cannot remain on screen.
        UIParent:SetScale(self.baseRootLocalScale)
        globalModified = false
    end
    self:ApplyElements()
    self:ApplyResources()
    self:UpdateMinimap()
    self:CreateOptions()
    self:RefreshOptions(false)
    self:OpenPendingOptions()
end

local function ScheduleApply()
    frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        Addon:Apply()
    end)
end

function Addon:SetScale(scale)
    if not self:IsValidScale(scale) then
        self:Print("Enter a scale from 0.10 to 1.50.")
        return false
    end
    self.db.scale, self.db.enabled = scale, true
    resetPending = false
    self:Apply()
    local suffix = InCombatLockdown() and " Queued until combat ends." or ""
    self:Print(string.format("Scale saved: %.3f.%s", scale, suffix))
    self:RefreshOptions("global")
    return true
end

function Addon:SetElementScale(key, scale)
    if not self:GetElement(key) or not self:IsValidElementScale(scale) then return false end
    self:ClearElementScaleOverrides(key)
    self.db.elements[key] = scale
    resetPending = false
    self:Apply()
    self:RefreshOptions(false)
    return true
end

function Addon:SetElementIndependent(key, enabled)
    if not self:GetElement(key) then return end
    self:ClearElementScaleOverrides(key)
    self.db.elements[key] = enabled and 1 or nil
    resetPending = false
    self:Apply()
    self:RefreshOptions(false)
end

function Addon:Reset()
    self.db.enabled = false
    self.db.elements = {}
    for _, element in ipairs(self.elements) do self:ClearElementScaleOverrides(element.key) end
    resetPending = true
    if InCombatLockdown() then
        self:Print("Reset saved. The UI will reload after combat to restore the game's scale.")
    else
        self:Print("Restoring the game's scale and reloading the UI.")
    end
    self:Apply()
end

local function HandleCommand(message)
    if not Addon.db or not loggedIn then
        Addon:Print("Please wait until your character has finished loading.")
        return
    end
    local command = string.lower((message or ""):match("^%s*(.-)%s*$"))
    local number = tonumber(command)
    if command == "" then
        Addon:ShowOptions()
    elseif command == "move" then
        Addon:BeginResourceEdit()
    elseif number then
        Addon:SetScale(number)
    elseif command == "smaller" or command == "larger" then
        local current = Addon.db.enabled and Addon.db.scale or UIParent:GetScale()
        local delta = command == "smaller" and -0.05 or 0.05
        Addon:SetScale(math.max(Addon.MIN_SCALE, math.min(Addon.MAX_SCALE, current + delta)))
    elseif command == "reset" then
        Addon:Reset()
    elseif command == "status" then
        Addon:Print(string.format("Current scale: %.3f. Override: %s.",
            UIParent:GetScale(), Addon.db.enabled and string.format("%.3f", Addon.db.scale) or "off"))
        if resetPending then Addon:Print("Reset and UI reload are waiting for combat to end.") end
    else
        Addon:Print("/fqol - open settings. /fqol 0.50 - set scale (0.10 to 1.50).")
        Addon:Print("/fqol move, /fqol smaller, /fqol larger, /fqol status, /fqol reset.")
    end
end

SLASH_SMALLERUI1, SLASH_SMALLERUI2, SLASH_SMALLERUI3 = "/sui", "/smallerui", "/fqol"
SlashCmdList.SMALLERUI = HandleCommand
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD",
    "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "DISPLAY_SIZE_CHANGED",
    "UI_SCALE_CHANGED", "UPDATE_CHAT_WINDOWS", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    frame:RegisterEvent(event)
end

frame:SetScript("OnEvent", function(_, event, name, action)
    if event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        if name == addonName then
            -- Record only our own action/stack. Do not suppress Blizzard's warning.
            Addon.lastBlockedAction = { event = event, action = type(action) == "string" and action or "Unknown",
                stack = debugstack and debugstack(2, 15, 0) or "", at = GetTime() }
            if Addon.character then Addon.character.lastBlockedAction = Addon.lastBlockedAction end
        end
        return
    elseif event == "ADDON_LOADED" and name == addonName and not Addon.db then
        local firstLoad = SmallerUIDB == nil
        if type(SmallerUIDB) ~= "table" then SmallerUIDB = {} end
        if type(SmallerUICharDB) ~= "table" then SmallerUICharDB = {} end
        Addon.db = SmallerUIDB
        Addon.character = SmallerUICharDB
        local db = Addon.db
        db.readyFlash = nil
        Addon.character.readySlots = nil
        if not Addon:IsValidScale(db.scale) then
            db.scale, db.enabled = 0.50, false
        else
            db.enabled = db.enabled == true
        end
        Addon:ValidateElements()
        Addon:ValidateMinimap()
        Addon:ValidateResources()
        if Addon.lastBlockedAction then Addon.character.lastBlockedAction = Addon.lastBlockedAction end
        if firstLoad then
            Addon:Print("Ready. Type /fqol for settings. /fqol reset restores the game's scale.")
        end
    elseif event == "PLAYER_LOGIN" then
        loggedIn = true
        Addon.baseRootLocalScale = UIParent:GetScale()
        Addon.baseRootScale = UIParent:GetEffectiveScale()
        Addon:ApplyResources()
        Addon:UpdateMinimap()
        Addon:CreateOptions()
        ScheduleApply()
    elseif loggedIn and Addon.db then
        ScheduleApply() -- Includes late-loaded frames and new chat windows.
    end
end)
