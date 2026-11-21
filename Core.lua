-- Talentwarden: suggests where to spend your next talent point.
-- Core.lua holds the saved settings, small helpers and the event hub. The build data is in
-- DataA.lua / DataB.lua, the maths in Engine.lua and everything you see in UI.lua.
local ADDON_NAME, ns = ...
ns.name = ADDON_NAME
ns.Data = {}

local function IsSecret(v) return issecretvalue ~= nil and issecretvalue(v) end
ns.IsSecret = IsSecret

function ns.Print(msg) print("|cffffcc00Talentwarden:|r " .. tostring(msg)) end

ns.ICON = "Interface\\Icons\\Ability_Marksmanship"

ns.DEFAULTS = {
    custom = {},            -- custom[specKey] = { { name = "...", data = "tree|talent|points;..." }, ... }
    highlight = true,       -- glow on the next talent in the talent window
    glowColor = "gold",     -- a name from the list in UI.lua, or "custom" to use glowRGB
    glowRGB = nil,          -- { r, g, b } picked in the options
    glowSize = 1.5,
    glowPulse = true,
    glowSpeed = 0.7,        -- seconds for one pulse
    glowCount = 1,          -- how many of the next talents glow
    glowOnlyUnspent = false, -- only glow while you have a point to spend
    glowAllOnReset = true,  -- with every talent reset, glow the whole plan and number each talent with the points it should get
    glowNumbers = false,    -- put the step order on the glowing talents (1 = next, 2 = after that, ...)
    remind = true,          -- chat line when you have points to spend
    remindLogin = true,
    remindLevel = true,
    remindPick = false,     -- also after each pick you make
    warnOff = true,         -- chat line when you are off the build
    showDone = true,        -- show finished steps (greyed) in the list
    showIcons = true,
    showLevels = true,
    showOffLine = true,
    showUses = true,        -- [PvP], [Tank] ... tags next to build names
    listRows = 12,
    openWithTalents = false, -- open the window together with the talent window
    pos = nil,
    minimap = { show = true, angle = 200 },
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            if next(v) ~= nil then Merge(dst[k], v) end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
    return dst
end

---------------------------------------------------------------------------
-- Which spec guide and build each character follows is kept under TalentwardenDB.chars[character].
-- Options, looks and your own custom builds are shared. Code keeps using ns.db.spec, ns.db.build and so on;
-- this routes those to the character that is playing.
---------------------------------------------------------------------------
local PERCHAR = { spec = true, viewClass = true, defaultSpec = true, build = true }

local function CharName()
    local first, second = UnitName("player")
    if type(first) ~= "string" or first == "" or first == "Unknown" or first == _G.UNKNOWNOBJECT then return nil end
    -- some servers give characters two names; UnitName hands the last one back in the realm slot
    if type(second) == "string" and second ~= "" and not first:find(" ", 1, true) then
        local r1 = GetRealmName and GetRealmName()
        local r2 = GetNormalizedRealmName and GetNormalizedRealmName()
        if second ~= r1 and second ~= r2 then return first .. " " .. second end
    end
    return first
end

local scratch = { spec = "auto", viewClass = "mine", build = {} }
local mineKey
local function Mine()
    local db = TalentwardenDB
    if mineKey and db.chars and db.chars[mineKey] then return db.chars[mineKey] end
    local name = CharName()
    if not name then return scratch end
    local realm = GetRealmName and GetRealmName()
    if type(realm) == "string" and realm ~= "" then db.lastRealm = realm else realm = db.lastRealm or "" end
    local key = name .. "-" .. realm
    db.chars = db.chars or {}
    local c = db.chars[key]
    if not c then
        c = { spec = "auto", viewClass = "mine", build = {} }
        db.chars[key] = c
        -- choices saved before this was split by character go to the first character that plays
        if not db.perCharMoved then
            db.perCharMoved = true
            for k in pairs(PERCHAR) do
                local v = rawget(db, k)
                if v ~= nil then c[k] = v rawset(db, k, nil) end
            end
        end
    end
    mineKey = key
    return c
end
ns.Mine = Mine

local dbMeta = {
    __index = function(_, k) if PERCHAR[k] then return Mine()[k] end end,
    __newindex = function(t, k, v) if PERCHAR[k] then Mine()[k] = v else rawset(t, k, v) end end,
}

local hooks = {}
function ns.AddHook(name, fn) hooks[name] = hooks[name] or {} table.insert(hooks[name], fn) end
function ns.Fire(name, ...)
    for _, fn in ipairs(hooks[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then
            if ns.Issue then pcall(ns.Issue, "lua", name, tostring(err)) end
            ns.Print("|cffff5555error in " .. name .. ":|r " .. tostring(err))
        end
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, arg)
    if event == "ADDON_LOADED" and arg == ADDON_NAME then
        TalentwardenDB = TalentwardenDB or {}
        ns.db = Merge(TalentwardenDB, ns.DEFAULTS)
        for k in pairs(PERCHAR) do
            if TalentwardenDB.perCharMoved then rawset(TalentwardenDB, k, nil) end
        end
        setmetatable(TalentwardenDB, dbMeta)
        pcall(Mine)
    elseif event == "PLAYER_LOGIN" then
        pcall(Mine)
        ns.Fire("login")
    end
end)

function Talentwarden_OnAddonCompartmentClick() if ns.UI then ns.UI.Toggle() end end
