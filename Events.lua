local addonName, ns = ...

------------------------------------------------------------------------
-- Taint laundering
-- spellID from UNIT_SPELLCAST_SUCCEEDED is sometimes tainted by WoW's
-- secure execution model. Passing it through a StatusBar's SetValue
-- causes C++ to re-emit a clean value via OnValueChanged.
------------------------------------------------------------------------
local launderBar = CreateFrame("StatusBar")
launderBar:SetMinMaxValues(0, 9999999)
local _launderedID = nil
launderBar:SetScript("OnValueChanged", function(_, v) _launderedID = v end)

local function SafeGetInterruptData(spellID)
    -- Try direct lookup first (pcall guards against tainted key access)
    local ok, data = pcall(function() return ns.INTERRUPT_SPELLS["" .. spellID] end)
    if ok and data then return data, spellID end
    -- Launder through StatusBar to strip taint
    _launderedID = nil
    launderBar:SetValue(0)
    pcall(launderBar.SetValue, launderBar, spellID)
    local cleanID = _launderedID
    if cleanID then
        local ok2, data2 = pcall(function() return ns.INTERRUPT_SPELLS["" .. cleanID] end)
        if ok2 and data2 then return data2, cleanID end
    end
    return nil, nil
end

------------------------------------------------------------------------
-- Resolve primary interrupt spellID string for any unit
------------------------------------------------------------------------
local function GetPrimaryInterruptForUnit(unit)
    local playerClass = select(2, UnitClass(unit))
    local entry = ns.PRIMARY_INTERRUPT[playerClass]
    if not entry then return nil end
    if type(entry) == "function" then
        local specID = (unit == "player")
            and select(1, GetSpecializationInfo(GetSpecialization()))
            or GetInspectSpecialization(unit)
        return entry(specID)
    end
    return entry
end

------------------------------------------------------------------------
-- Pre-populate a unit's row without a cooldown (spell available)
------------------------------------------------------------------------
local function InitUnitRow(unit)
    local guid = UnitGUID(unit)
    if not guid then return end

    local spellIDStr = GetPrimaryInterruptForUnit(unit)
    if not spellIDStr then return end

    local existing  = ns.trackedPlayers[guid]
    local spellInfo = C_Spell.GetSpellInfo(tonumber(spellIDStr))

    ns.trackedPlayers[guid] = {
        name    = UnitName(unit),
        class   = select(2, UnitClass(unit)),
        spellID = spellIDStr,
        icon    = spellInfo and spellInfo.iconID,
        cdEnd   = existing and existing.cdEnd or 0,
    }

    local isNew = not existing
    if isNew then ns.LayoutRows() end
    ns.InitRow(guid)
end

------------------------------------------------------------------------
-- Record an interrupt into shared state
------------------------------------------------------------------------
local function RecordInterrupt(srcGUID, srcName, srcClass, spellID)
    local spellIDStr = "" .. spellID
    local cdInfo     = ns.INTERRUPT_SPELLS[spellIDStr]
    local cd         = cdInfo and cdInfo.cd or 15
    local isNew      = not ns.trackedPlayers[srcGUID]
    local iconChanged = not isNew and (ns.trackedPlayers[srcGUID].spellID ~= spellIDStr)

    if isNew then
        local spellInfo = C_Spell.GetSpellInfo(tonumber(spellIDStr))
        ns.trackedPlayers[srcGUID] = {
            name    = srcName,
            class   = srcClass,
            spellID = spellIDStr,
            icon    = spellInfo and spellInfo.iconID,
            cdEnd   = GetTime() + cd,
        }
        if not InCombatLockdown() then
            ns.LayoutRows()
            ns.InitRow(srcGUID)
        end
    else
        local data = ns.trackedPlayers[srcGUID]
        if iconChanged and not InCombatLockdown() then
            local spellInfo = C_Spell.GetSpellInfo(tonumber(spellIDStr))
            data.icon    = spellInfo and spellInfo.iconID
            data.spellID = spellIDStr
            ns.InitRow(srcGUID)
        end
        data.cdEnd = GetTime() + cd
    end
end

------------------------------------------------------------------------
-- Broadcast our own interrupt to the group
------------------------------------------------------------------------
local function BroadcastInterrupt(spellID)
    if C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() then return end
    local msg     = UnitGUID("player") .. "|" .. spellID
    local channel = IsInRaid() and "RAID" or "PARTY"
    local ok, ret = pcall(C_ChatInfo.SendAddonMessage, ns.ADDON_MSG_PREFIX, msg, channel)
    if ok and ret == 0 then return end
    -- PARTY/RAID blocked inside instances — whisper each member
    for i = 1, GetNumGroupMembers() do
        local unit = (IsInRaid() and "raid" or "party") .. i
        if UnitExists(unit) then
            local name, realm = UnitName(unit)
            local target = realm and realm ~= "" and (name .. "-" .. realm) or name
            pcall(C_ChatInfo.SendAddonMessage, ns.ADDON_MSG_PREFIX, msg, "WHISPER", target)
        end
    end
end

------------------------------------------------------------------------
-- Shared cast handler (used by both player and party frames)
------------------------------------------------------------------------
local function HandleCast(unit, spellID)
    local cdInfo, cleanID = SafeGetInterruptData(spellID)
    if not cdInfo then return end

    local srcGUID  = UnitGUID(unit)
    local srcName  = UnitName(unit)
    local srcClass = select(2, UnitClass(unit))
    if not srcGUID then return end

    if unit == "player" and IsInGroup() then
        BroadcastInterrupt(cleanID or spellID)
    end

    RecordInterrupt(srcGUID, srcName, srcClass, cleanID or spellID)
end

------------------------------------------------------------------------
-- Player/pet cast frame — UNIT_SPELLCAST_SUCCEEDED is reliable for
-- the local player and handles the broadcast to group members.
------------------------------------------------------------------------
local playerCastFrame = CreateFrame("Frame")
playerCastFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet")
playerCastFrame:SetScript("OnEvent", function(_, _, unit, _, spellID)
    HandleCast(unit, spellID)
end)


------------------------------------------------------------------------
-- Correlation-based party interrupt detection (no CLEU, no tainted spellID)
--
-- UNIT_SPELLCAST_SUCCEEDED fires for party members but spellID is tainted.
-- UNIT_SPELLCAST_INTERRUPTED fires on the nameplate when a mob's cast
-- is interrupted. We match the two by timestamp within a 50ms window
-- to determine who interrupted without ever touching the spellID.
------------------------------------------------------------------------
local pendingCasts      = {}  -- [unit] = timestamp
local pendingInterrupts = {}  -- [nameplateUnit] = timestamp
local correlPending     = false
local TIME_WINDOW       = 0.050

local function ProcessCorrelation()
    correlPending = false

    local interruptCount, targetUnit = 0, nil
    for unit in pairs(pendingInterrupts) do
        interruptCount = interruptCount + 1
        targetUnit = unit
    end

    if interruptCount == 0 then
        wipe(pendingCasts)
        return
    end

    -- Multiple simultaneous interrupts = AOE CC, not a kick
    if interruptCount > 1 then
        wipe(pendingInterrupts)
        wipe(pendingCasts)
        return
    end

    local interruptTime = pendingInterrupts[targetUnit]

    -- Find the party member whose cast timestamp is closest
    local bestUnit, bestDiff = nil, math.huge
    for unit, castTime in pairs(pendingCasts) do
        local diff = math.abs(interruptTime - castTime)
        if diff <= TIME_WINDOW and diff < bestDiff then
            bestUnit, bestDiff = unit, diff
        end
    end

    if bestUnit then
        local guid = UnitGUID(bestUnit)
        if guid and ns.trackedPlayers[guid] then
            local data   = ns.trackedPlayers[guid]
            local cdInfo = data.spellID and ns.INTERRUPT_SPELLS[data.spellID]
            data.cdEnd   = GetTime() + (cdInfo and cdInfo.cd or 15)
        end
    end

    wipe(pendingInterrupts)
    wipe(pendingCasts)
end

local correlFrame = CreateFrame("Frame")
correlFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
correlFrame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
correlFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if unit == "player" or unit == "pet" then return end  -- handled by playerCastFrame
        if not unit:find("^party") then return end
        pendingCasts[unit] = GetTime()
        if not correlPending then
            correlPending = true
            C_Timer.After(0.03, ProcessCorrelation)
        end

    elseif event == "UNIT_SPELLCAST_INTERRUPTED" then
        if not unit:find("^nameplate") then return end
        pendingInterrupts[unit] = GetTime()
        if not correlPending then
            correlPending = true
            C_Timer.After(0.03, ProcessCorrelation)
        end
    end
end)

local function RegisterPartyWatchers() end  -- no longer needed, kept for call-site compat

------------------------------------------------------------------------
-- Main event frame
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function RegisterEvents()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
end

RegisterEvents()
RegisterPartyWatchers()

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "CHAT_MSG_ADDON" then
        local prefix, msg = ...
        if prefix ~= ns.ADDON_MSG_PREFIX then return end

        local srcGUID, spellIDStr = strsplit("|", msg)
        local spellID = tonumber(spellIDStr)
        if not spellID or not srcGUID then return end

        local srcName, srcClass
        for i = 1, GetNumGroupMembers() do
            local unit = (IsInRaid() and "raid" or "party") .. i
            if UnitGUID(unit) == srcGUID then
                srcName  = UnitName(unit)
                srcClass = select(2, UnitClass(unit))
                break
            end
        end

        if srcName then
            RecordInterrupt(srcGUID, srcName, srcClass, spellID)
        end

    elseif event == "PLAYER_LOGIN" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        InitUnitRow("player")

    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        local toRemove = {}
        for guid in pairs(ns.trackedPlayers) do
            local found = UnitGUID("player") == guid
            if not found then
                for i = 1, GetNumGroupMembers() do
                    local unit = (IsInRaid() and "raid" or "party") .. i
                    if UnitGUID(unit) == guid then found = true; break end
                end
            end
            if not found then toRemove[#toRemove + 1] = guid end
        end
        for _, guid in ipairs(toRemove) do
            ns.trackedPlayers[guid] = nil
            ns.RemoveRow(guid)
        end

        for i = 1, GetNumGroupMembers() do
            local unit = (IsInRaid() and "raid" or "party") .. i
            if UnitGUID(unit) and not ns.trackedPlayers[UnitGUID(unit)] then
                InitUnitRow(unit)
            end
        end

        ns.LayoutRows()
        RegisterEvents()
        RegisterPartyWatchers()
    end
end)
