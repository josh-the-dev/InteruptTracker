local addonName, ns = ...

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
    local cdInfo    = ns.INTERRUPT_SPELLS["" .. spellID]
    local cd        = cdInfo and cdInfo.cd or 15
    local isNew     = not ns.trackedPlayers[srcGUID]
    local iconChanged = isNew or (ns.trackedPlayers[srcGUID] and ns.trackedPlayers[srcGUID].spellID ~= spellID)

    if isNew then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        ns.trackedPlayers[srcGUID] = {
            name    = srcName,
            class   = srcClass,
            spellID = spellID,
            icon    = spellInfo and spellInfo.iconID,
            cdEnd   = GetTime() + cd,
        }
        ns.LayoutRows()
        ns.InitRow(srcGUID)
    else
        local data = ns.trackedPlayers[srcGUID]
        if iconChanged then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            data.icon    = spellInfo and spellInfo.iconID
            data.spellID = spellID
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
    local channel = IsInRaid() and "RAID" or "PARTY"
    local guid    = UnitGUID("player")
    C_ChatInfo.SendAddonMessage(ns.ADDON_MSG_PREFIX, guid .. "|" .. spellID, channel)
end

------------------------------------------------------------------------
-- Event frame
------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function RegisterEvents()
    eventFrame:UnregisterAllEvents()
    eventFrame:RegisterEvent("CHAT_MSG_ADDON")
    eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
    eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    eventFrame:RegisterEvent("PLAYER_LOGIN")
    eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")

    eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player", "pet", "party1", "party2", "party3", "party4")
end

RegisterEvents()

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        local unit, _, spellID = ...
        if not ns.INTERRUPT_SPELLS["" .. spellID] then return end

        local srcGUID  = UnitGUID(unit)
        local srcName  = UnitName(unit)
        local srcClass = select(2, UnitClass(unit))

        -- If it's us and we're in a group, broadcast so others can pick it up
        if unit == "player" and IsInGroup() then
            BroadcastInterrupt(spellID)
        end

        RecordInterrupt(srcGUID, srcName, srcClass, spellID)

    elseif event == "CHAT_MSG_ADDON" then
        local prefix, msg = ...
        if prefix ~= ns.ADDON_MSG_PREFIX then return end

        local srcGUID, spellIDStr = strsplit("|", msg)
        local spellID = tonumber(spellIDStr)
        if not spellID or not srcGUID then return end

        -- Look up name/class by GUID
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
        -- Prune players no longer in group
        -- Collect removals first to avoid mutating the table mid-iteration
        local toRemove = {}
        for guid in pairs(ns.trackedPlayers) do
            local found = UnitGUID("player") == guid
            if not found then
                for i = 1, GetNumGroupMembers() do
                    local unit = (IsInRaid() and "raid" or "party") .. i
                    if UnitGUID(unit) == guid then found = true; break end
                end
            end
            if not found then
                toRemove[#toRemove + 1] = guid
            end
        end
        for _, guid in ipairs(toRemove) do
            ns.trackedPlayers[guid] = nil
            ns.RemoveRow(guid)
        end

        -- Init any new party members
        for i = 1, GetNumGroupMembers() do
            local unit = (IsInRaid() and "raid" or "party") .. i
            if UnitGUID(unit) and not ns.trackedPlayers[UnitGUID(unit)] then
                InitUnitRow(unit)
            end
        end

        ns.LayoutRows()
        RegisterEvents()
    end
end)
