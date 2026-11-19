local ADDON_NAME, ns = ...
-- Window customization (see Look.lua). Opens from the minimap button (Alt-click) or /talentwarden options.
if not ns.WinLook then return end

local function Options()
    local L = ns.WinLook
    local db = function() return ns.db end
    local mmdb = function() return ns.db.minimap end
    local function refresh() if ns.UI then ns.UI.Refresh() end end
    local function relayout() if ns.UI then ns.UI.ApplyLook() ns.UI.Refresh() end end
    local classChoices = { { "mine", "My own class" } }
    for _, c in ipairs(ns.Engine.CLASSES) do classChoices[#classChoices + 1] = { c, ns.Engine.CLASS_NAMES[c] } end
    return { sections = {
        { id = "glow", title = "Glow in the talent window", open = true, rows = {
            L.Kon("Glow the next talent", db, "highlight", refresh),
            L.Choice("Glow color", db, "glowColor", ns.UI.COLOR_CHOICES, refresh),
            L.Color("My own glow color", db, "glowRGB", { 1, 0.82, 0.1 }, function() ns.db.glowColor = "custom" refresh() end),
            L.Slider("Glow size", db, "glowSize", 1, 2.5, 0.1, nil, refresh),
            L.Kon("Pulse", db, "glowPulse", refresh),
            L.Slider("Pulse speed (seconds)", db, "glowSpeed", 0.3, 1.6, 0.1, nil, refresh),
            L.Choice("Glow this many of the next talents", db, "glowCount", { { 1, "Just the next one" }, { 2, "The next 2" }, { 3, "The next 3" }, { 5, "The next 5" }, { 8, "The next 8" } }, refresh),
            L.Koff("Number the glowing talents (1 = first)", db, "glowNumbers", refresh),
            L.Koff("Only glow while I have a point to spend", db, "glowOnlyUnspent", refresh),
            L.Note("Only your own class glows. If nothing glows, open the talent window and type /tw scan."),
        } },
        { id = "chat", title = "Chat reminders", open = true, rows = {
            L.Kon("Tell me my next talent when I have points to spend", db, "remind"),
            L.Kon("...when I log in", db, "remindLogin"),
            L.Kon("...when I level up", db, "remindLevel"),
            L.Koff("...after each talent I pick", db, "remindPick"),
            L.Kon("Warn when I am off the build", db, "warnOff"),
        } },
        { id = "window", title = "Window", rows = {
            L.Slider("Steps shown in the list", db, "listRows", 6, 24, 1, nil, relayout),
            L.Kon("Show steps I have already taken (greyed)", db, "showDone", refresh),
            L.Kon("Show talent icons in the list", db, "showIcons", refresh),
            L.Kon("Show level numbers", db, "showLevels", refresh),
            L.Kon("Show the off-the-build line", db, "showOffLine", refresh),
            L.Kon("Show what each build is for (Leveling, PvP, Tank ...)", db, "showUses", refresh),
            L.Koff("Open with the talent window", db, "openWithTalents"),
            L.Kon("Show the minimap button", mmdb, "show", function() if ns.UI then ns.UI.UpdateMinimap() end end),
            L.Note("Colors, fonts, background, border, scale and opacity of the window are in the Main window tab."),
        } },
        { id = "builds", title = "Classes and builds", rows = {
            L.Choice("Read the guides of", db, "viewClass", classChoices, function() ns.db.spec = "auto" refresh() end),
            L.Button("Save the talents I have now as a build", function() ns.UI.SaveMine() end, 260),
            L.Button("Copy the build on screen to my own builds", function() ns.UI.CopyBuild() end, 260),
            L.Button("Paste in a shared build", function() ns.UI.Import() end, 260),
            L.Button("Share the build on screen (copy text)", function() ns.UI.Export() end, 260),
            L.Button("Delete the build of mine on screen", function() ns.UI.DeleteBuild() end, 260),
            L.Note("All nine classes and all 27 specs are in. Other classes can be read, but only your own is compared with your talents."),
        } },
    } }
end

ns.WinLook.Setup({
    options = Options,
    title = "Talentwarden",
    slash = "talentwardenlook",
    syncDefault = false,
    media = "Interface\\AddOns\\Talentwarden\\Media\\",
    db = function() return TalentwardenDB end,
    windows = {
        { id = "main", name = "Main window", global = "TalentwardenFrame", strip = "backdrop", defaultOn = true, title = function(f) return f.titleFS end },
    },
})
