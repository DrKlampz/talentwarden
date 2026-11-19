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
    spec = "auto",          -- "auto" = the spec you have the most points in, or a spec key such as "affliction-warlock"
    viewClass = "mine",     -- "mine" or a class token: read the guides of another class (nothing is compared or glowed)
    defaultSpec = nil,      -- used by "auto" while you have no points spent yet
    build = {},             -- build[specKey] = "level", a number, or "c1".."cN" (your own builds)
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
    elseif event == "PLAYER_LOGIN" then
        ns.Fire("login")
    end
end)

function Talentwarden_OnAddonCompartmentClick() if ns.UI then ns.UI.Toggle() end end
