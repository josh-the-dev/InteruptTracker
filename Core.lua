local addonName, ns = ...

-- Shared state: keyed by player GUID
-- { name, class, spellID, icon, cdEnd, lastTarget }
ns.trackedPlayers = {}

ns.ADDON_MSG_PREFIX = "IntTrack"
C_ChatInfo.RegisterAddonMessagePrefix(ns.ADDON_MSG_PREFIX)
