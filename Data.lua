local addonName, ns = ...

-- String spellID -> { cd (seconds), class }
-- Keys are strings so we can look up secret spellID values via ("" .. spellID)
ns.INTERRUPT_SPELLS = {
    ["2139"]   = { cd = 24, class = "MAGE" },          -- Counterspell
    ["6552"]   = { cd = 15, class = "WARRIOR" },        -- Pummel
    ["47528"]  = { cd = 15, class = "DEATHKNIGHT" },    -- Mind Freeze
    ["57994"]  = { cd = 12, class = "SHAMAN" },         -- Wind Shear
    ["96231"]  = { cd = 15, class = "PALADIN" },        -- Rebuke
    ["106839"] = { cd = 15, class = "DRUID" },          -- Skull Bash (Feral/Guardian/Resto)
    ["78675"]  = { cd = 60, class = "DRUID" },          -- Solar Beam (Balance)
    ["116705"] = { cd = 15, class = "MONK" },           -- Spear Hand Strike
    ["147362"] = { cd = 24, class = "HUNTER" },         -- Counter Shot (Beast Mastery/Marksmanship)
    ["187707"] = { cd = 15, class = "HUNTER" },         -- Muzzle (Survival)
    ["183752"] = { cd = 15, class = "DEMONHUNTER" },    -- Disrupt
    ["351338"] = { cd = 20, class = "EVOKER" },         -- Quell
    ["1766"]   = { cd = 15, class = "ROGUE" },          -- Kick
    ["19647"]  = { cd = 24, class = "WARLOCK" },        -- Spell Lock (Felhunter - Affliction/Destruction)
    ["119914"] = { cd = 30, class = "WARLOCK" },        -- Axe Toss (Felguard - Demonology)
    ["15487"]  = { cd = 45, class = "PRIEST" },         -- Silence
}

-- Primary interrupt spellID (string) per class, or function(specID) -> spellID for spec-dependent classes
ns.PRIMARY_INTERRUPT = {
    WARRIOR     = "6552",
    PALADIN     = "96231",
    HUNTER      = function(specID) return specID == 255 and "187707" or "147362" end, -- Survival(255) = Muzzle, else Counter Shot
    ROGUE       = "1766",
    PRIEST      = "15487",
    DEATHKNIGHT = "47528",
    SHAMAN      = "57994",
    MAGE        = "2139",
    WARLOCK     = function(specID) return specID == 266 and "119914" or "19647" end, -- Demonology(266) = Axe Toss, else Spell Lock
    MONK        = "116705",
    DRUID       = function(specID) return specID == 102 and "78675" or "106839" end, -- Balance(102) = Solar Beam, else Skull Bash
    DEMONHUNTER = "183752",
    EVOKER      = "351338",
}

ns.CLASS_COLORS = {
    WARRIOR     = { r=0.78, g=0.61, b=0.43 },
    PALADIN     = { r=0.96, g=0.55, b=0.73 },
    HUNTER      = { r=0.67, g=0.83, b=0.45 },
    ROGUE       = { r=1.00, g=0.96, b=0.41 },
    PRIEST      = { r=1.00, g=1.00, b=1.00 },
    DEATHKNIGHT = { r=0.77, g=0.12, b=0.23 },
    SHAMAN      = { r=0.00, g=0.44, b=0.87 },
    MAGE        = { r=0.41, g=0.80, b=0.94 },
    WARLOCK     = { r=0.58, g=0.51, b=0.79 },
    MONK        = { r=0.00, g=1.00, b=0.59 },
    DRUID       = { r=1.00, g=0.49, b=0.04 },
    DEMONHUNTER = { r=0.64, g=0.19, b=0.79 },
    EVOKER      = { r=0.20, g=0.58, b=0.50 },
}
