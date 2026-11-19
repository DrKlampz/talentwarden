-- Talentwarden window, talent-window highlight, minimap button and slash commands.
-- Colors, fonts, background, scale and the rest of the look are in Look.lua / LookSetup.lua (Alt-click the minimap button).
local ADDON_NAME, ns = ...
local UI = {}
ns.UI = UI
local E = ns.Engine
local IsSecret = ns.IsSecret

local COLORS = {
    gold   = { 1.0, 0.82, 0.1, "Gold" },
    green  = { 0.3, 1.0, 0.4, "Green" },
    cyan   = { 0.3, 0.9, 1.0, "Cyan" },
    blue   = { 0.35, 0.55, 1.0, "Blue" },
    purple = { 0.75, 0.45, 1.0, "Purple" },
    pink   = { 1.0, 0.45, 0.85, "Pink" },
    orange = { 1.0, 0.55, 0.15, "Orange" },
    white  = { 1.0, 1.0, 1.0, "White" },
    red    = { 1.0, 0.3, 0.3, "Red" },
}
UI.COLOR_CHOICES = {
    { "gold", "Gold" }, { "green", "Green" }, { "cyan", "Cyan" }, { "blue", "Blue" }, { "purple", "Purple" },
    { "pink", "Pink" }, { "orange", "Orange" }, { "white", "White" }, { "red", "Red" }, { "custom", "My own color (pick below)" },
}
local function GlowColor()
    if ns.db.glowColor == "custom" and type(ns.db.glowRGB) == "table" then
        local c = ns.db.glowRGB
        return c[1] or 1, c[2] or 1, c[3] or 1
    end
    local c = COLORS[ns.db.glowColor] or COLORS.gold
    return c[1], c[2], c[3]
end

local function ClassLabel(class)
    local nm = E.CLASS_NAMES[class] or tostring(class)
    return "|cff" .. (E.CLASS_COLORS[class] or "ffffff") .. nm .. "|r"
end

---------------------------------------------------------------------------
-- The current answer, shared by the window, the highlight and the chat lines
---------------------------------------------------------------------------
local cache
function UI.Current(force)
    local now = GetTime()
    if cache and not force and now - cache.at < 0.5 then return cache end
    local owned = E.ReadOwned()
    local spec, detected = E.CurrentSpec(owned)
    if not spec then cache = nil return nil end
    local build = E.CurrentBuild(spec)
    local res = E.Evaluate(spec, build, owned)
    res.detected = detected
    res.unspent = E.Unspent(owned)
    res.at = now
    cache = res
    return res
end

---------------------------------------------------------------------------
-- Chat lines
---------------------------------------------------------------------------
local lastLine
function UI.Remind(why)
    if not ns.db.remind then return end
    if why == "login" and not ns.db.remindLogin then return end
    if why == "level" and not ns.db.remindLevel then return end
    if why == "pick" and not ns.db.remindPick then return end
    local res = UI.Current(true)
    if not res or res.foreign or not res.owned.ok then return end
    if (res.unspent or 0) <= 0 then return end
    local line = E.Summary(res)
    if not line then return end
    line = ("%d point%s to spend. %s"):format(res.unspent, res.unspent == 1 and "" or "s", line)
    if line == lastLine and why ~= "login" and why ~= "manual" then return end
    lastLine = line
    ns.Print(line)
end

local warned = {}
function UI.WarnOff()
    if not ns.db.warnOff then return end
    local res = UI.Current(true)
    if not res or res.foreign or not res.owned.ok or #res.off == 0 then return end
    local names = {}
    for i = 1, math.min(#res.off, 4) do names[#names + 1] = res.off[i].name end
    local line = table.concat(names, ", ") .. (#res.off > 4 and (" and " .. (#res.off - 4) .. " more") or "")
    if warned[line] then return end
    warned[line] = true
    ns.Print(("not on the %s build for %s: |cffff9955%s|r"):format(
        res.build == "level" and "leveling" or "chosen", E.SpecName(res.spec), line))
end

---------------------------------------------------------------------------
-- Highlight in the talent window
---------------------------------------------------------------------------
local ROOT_NAMES = { "PlayerSpellsFrame", "ClassTalentFrame", "PlayerTalentFrame", "TalentFrame", "ClassTalentsFrame" }
local glows = setmetatable({}, { __mode = "k" })
local scanned = {}      -- debug: what the last scan found

local function ButtonSpell(btn)
    local id
    if btn.GetSpellID then
        local ok, v = pcall(btn.GetSpellID, btn)
        if ok and type(v) == "number" and not IsSecret(v) then id = v end
    end
    if not id and type(btn.spellID) == "number" and not IsSecret(btn.spellID) then id = btn.spellID end
    if not id and btn.GetNodeInfo then
        local ok, info = pcall(btn.GetNodeInfo, btn)
        if ok and type(info) == "table" then
            local cfg = E.ReadOwned().configID
            local entryID = (info.activeEntry and info.activeEntry.entryID) or (info.entryIDs and info.entryIDs[1])
            if cfg and entryID then
                local ok2, entry = pcall(C_Traits.GetEntryInfo, cfg, entryID)
                local def = ok2 and entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                id = def and def.spellID
            end
        end
    end
    if not id and btn.nodeInfo and btn.nodeInfo.activeEntry and btn.nodeInfo.activeEntry.entryID then
        local cfg = E.ReadOwned().configID
        if cfg then
            local ok2, entry = pcall(C_Traits.GetEntryInfo, cfg, btn.nodeInfo.activeEntry.entryID)
            local def = ok2 and entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
            id = def and def.spellID
        end
    end
    return id
end

local function MakeGlow(btn)
    local g = glows[btn]
    if g then return g end
    g = btn:CreateTexture(nil, "OVERLAY")
    g:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    g:SetBlendMode("ADD")
    g:SetPoint("CENTER", btn, "CENTER", 0, 0)
    g:Hide()
    local ag = g:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local a = ag:CreateAnimation("Alpha")
    a:SetFromAlpha(1) a:SetToAlpha(0.3) a:SetDuration(0.7)
    g.pulse = ag
    g.anim = a
    local n = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    n:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
    n:Hide()
    g.num = n
    glows[btn] = g
    return g
end

local function HideGlows()
    for _, g in pairs(glows) do
        g:Hide()
        if g.pulse then g.pulse:Stop() end
        if g.num then g.num:Hide() end
    end
end

local function EachFrame(f, depth, fn)
    fn(f)
    if depth <= 0 then return end
    local n = f.GetNumChildren and f:GetNumChildren() or 0
    for i = 1, n do
        local c = select(i, f:GetChildren())
        if c then EachFrame(c, depth - 1, fn) end
    end
end

function UI.Highlight()
    HideGlows()
    if not ns.db.highlight then return end
    local res = UI.Current()
    if not res or res.foreign then return end
    if ns.db.glowOnlyUnspent and (res.unspent or 0) <= 0 then return end
    local want = E.Upcoming(res, math.max(1, math.floor(ns.db.glowCount or 1)))
    -- everything reset: glow the whole plan (as many points as you can spend) and show how many points each talent gets
    local overview = false
    if ns.db.glowAllOnReset ~= false and res.owned and res.owned.ok and (res.owned.total or 0) == 0 then
        local cap = tonumber(res.unspent) or 0
        if cap <= 0 then cap = #res.rows end
        local byKey, list = {}, {}
        for i = 1, math.min(cap, #res.rows) do
            local step = res.rows[i].step
            local k = E.Norm(step.name)
            local w = byKey[k]
            if not w then
                w = { step = step, order = #list + 1, pts = 0 }
                byKey[k] = w
                list[#list + 1] = w
            end
            w.pts = w.pts + 1
        end
        if #list > 0 then want, overview = list, true end
    end
    if #want == 0 then return end
    scanned = { roots = {}, buttons = 0, matched = 0 }
    for _, rn in ipairs(ROOT_NAMES) do
        local root = _G[rn]
        if root and root.IsShown and root:IsShown() then
            scanned.roots[#scanned.roots + 1] = rn
            EachFrame(root, 9, function(f)
                if f.IsObjectType and f:IsObjectType("Button") and f ~= root then
                    local id = ButtonSpell(f)
                    if id then
                        scanned.buttons = scanned.buttons + 1
                        local nm = E.SpellName(id)
                        local nk = nm and E.Norm(nm)
                        for _, w in ipairs(want) do
                            if (w.step.spell and id == w.step.spell) or (nk and nk == E.Norm(w.step.name)) then
                                scanned.matched = scanned.matched + 1
                                local g = MakeGlow(f)
                                local size = (f:GetWidth() or 40) * (ns.db.glowSize or 1.5)
                                g:SetSize(size, size)
                                local r, gg, b = GlowColor()
                                g:SetVertexColor(r, gg, b)
                                g:SetAlpha((overview or w.order == 1) and 1 or 0.65)
                                g:Show()
                                if g.anim then g.anim:SetDuration(math.max(0.2, ns.db.glowSpeed or 0.7)) end
                                if ns.db.glowPulse then g.pulse:Play() else g.pulse:Stop() end
                                if overview then
                                    g.num:SetText(tostring(w.pts))
                                    g.num:SetTextColor(1, 1, 1)
                                    g.num:Show()
                                elseif ns.db.glowNumbers and #want > 1 then
                                    g.num:SetText(tostring(w.order))
                                    g.num:SetTextColor(r, gg, b)
                                    g.num:Show()
                                else
                                    g.num:Hide()
                                end
                                break
                            end
                        end
                    end
                end
            end)
        end
    end
end

local hooked = {}
local function HookRoots()
    for _, rn in ipairs(ROOT_NAMES) do
        local root = _G[rn]
        if root and root.HookScript and not hooked[rn] then
            hooked[rn] = true
            root:HookScript("OnShow", function()
                if ns.db.openWithTalents then UI.Show() end
                C_Timer.After(0.3, UI.Refresh)
                C_Timer.After(1.2, UI.Refresh)
            end)
            root:HookScript("OnHide", HideGlows)
        end
    end
end

-- some frames load on demand (Blizzard_*Talent*): look again whenever an add-on finishes loading
local ticker
local function EnsureTicker()
    if ticker then return end
    ticker = CreateFrame("Frame")
    local acc = 0
    ticker:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 1.5 then return end
        acc = 0
        local any = false
        for _, rn in ipairs(ROOT_NAMES) do
            local root = _G[rn]
            if root and root.IsShown and root:IsShown() then any = true end
        end
        if any then UI.Refresh() end
    end)
end

---------------------------------------------------------------------------
-- Popups: name a build, paste one in, copy one out, delete one
---------------------------------------------------------------------------
local function EditOf(popup) return popup.editBox or popup.EditBox or (popup.GetName and _G[popup:GetName() .. "EditBox"]) end

local function Ask(which, text, data)
    if StaticPopup_Show then StaticPopup_Show(which, text, nil, data) end
end

StaticPopupDialogs["TALENTWARDEN_NAME"] = {
    text = "%s", button1 = ACCEPT or "OK", button2 = CANCEL or "Cancel", hasEditBox = 1, maxLetters = 60, editBoxWidth = 260,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local eb = EditOf(self)
        if eb then eb:SetText(data and data.default or "") eb:HighlightText() eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = EditOf(self)
        if data and data.fn and eb then data.fn(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local data = p.data
        if data and data.fn then data.fn(self:GetText()) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["TALENTWARDEN_IMPORT"] = {
    text = "%s", button1 = "Add", button2 = CANCEL or "Cancel", hasEditBox = 1, maxLetters = 6000, editBoxWidth = 330,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self)
        local eb = EditOf(self)
        if eb then if eb.SetMaxLetters then eb:SetMaxLetters(6000) end eb:SetText("") eb:SetFocus() end
    end,
    OnAccept = function(self, data)
        local eb = EditOf(self)
        if data and data.fn and eb then data.fn(eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
        local p = self:GetParent()
        local data = p.data
        if data and data.fn then data.fn(self:GetText()) end
        p:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["TALENTWARDEN_EXPORT"] = {
    text = "%s", button1 = CLOSE or "Close", hasEditBox = 1, maxLetters = 6000, editBoxWidth = 330,
    timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnShow = function(self, data)
        local eb = EditOf(self)
        if eb then
            if eb.SetMaxLetters then eb:SetMaxLetters(6000) end
            eb:SetText(data and data.text or "")
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["TALENTWARDEN_DELETE"] = {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No", timeout = 0, whileDead = 1, hideOnEscape = 1,
    OnAccept = function(self, data) if data and data.fn then data.fn() end end,
}

---------------------------------------------------------------------------
-- The window
---------------------------------------------------------------------------
local W
local ROWH = 18
local TOP_LIST = 218     -- distance from the top of the window to the first list row
local MAXROWS = 24

local function Btn(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 20)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

local function ApplyLook()
    if not W then return end
    local rows = math.min(MAXROWS, math.max(4, math.floor(ns.db.listRows or 12)))
    W:SetHeight(TOP_LIST + rows * ROWH + 74)
    for i = 1, MAXROWS do
        local r = W.rows[i]
        if r then r:SetWidth(W:GetWidth() - 28) end
    end
end
UI.ApplyLook = ApplyLook

local function SpecText(res)
    local spec = res.spec
    local s = E.SpecName(spec)
    return s .. ((not res.foreign and ns.db.spec == "auto") and (res.detected and "  |cff88ff88(auto)|r" or "  |cffaaaaaa(auto: none spent yet)|r") or "")
end

local function BuildLabel(res)
    for _, b in ipairs(E.Builds(res.spec)) do
        if b.id == res.build then return b end
    end
end

function UI.Refresh()
    local res = UI.Current(true)
    if W and W:IsShown() then
        local class = E.ViewClass()
        W.class:SetText(class and (ClassLabel(class) .. (E.IsOwnClass(class) and "  |cff88ff88(you)|r" or "")) or "No class")
        if not res then
            W.spec:SetText("No guide for this class")
            W.build:SetText("")
            W.uses:SetText("")
            W.nextText:SetText("")
            W.nextSub:SetText("")
            W.icon:Hide()
            W.info:SetText("")
            W.off:SetText("")
            for _, r in ipairs(W.rows) do r:Hide() end
        else
            W.spec:SetText(SpecText(res))
            local b = BuildLabel(res)
            W.build:SetText(b and b.name or "Leveling guide")
            local tags = {}
            if ns.db.showUses and b and b.uses then for _, u in ipairs(b.uses) do tags[#tags + 1] = u end end
            W.uses:SetText(("|cffaaaaaaRole:|r %s%s"):format(E.Role(res.spec), #tags > 0 and ("     |cffaaaaaaFor:|r " .. table.concat(tags, ", ")) or ""))
            local n = res.next
            local d = ns.Data[res.spec]
            if n then
                local icon = E.SpellIcon(n.step.spell)
                if icon then W.icon:SetTexture(icon) W.icon:Show() else W.icon:Hide() end
                W.nextText:SetText(("|cffffd100%s|r  rank %d of %d"):format(n.step.name, n.have + 1, n.max))
                W.nextSub:SetText(("%s tree%s"):format(d and d.trees[n.step.tree + 1] or "?", n.lvl and ("  |  level " .. n.lvl .. " step") or ""))
                W.nextLabel:SetText(res.foreign and "First talent point" or "Next talent point")
            else
                W.icon:Hide()
                W.nextLabel:SetText("")
                W.nextText:SetText("|cff55ff55Build complete|r")
                W.nextSub:SetText("Every talent in this build is taken.")
            end
            if res.foreign then
                W.nextLabel:SetText("First talent point")
                W.info:SetText(("Reading the %s guide. |cffaaaaaaNothing is compared with your own talents.|r"):format(ClassLabel(E.ViewClass())))
            else
                W.info:SetText(("Unspent points: |cffffffff%d|r     Spent: |cffffffff%d|r of %d in this build%s"):format(
                    res.unspent or 0, res.owned.total or 0, res.total, res.owned.ok and "" or "   |cffff9955(can't read talents yet)|r"))
            end
            -- the step list
            local rows = res.rows
            local nrows = math.min(MAXROWS, math.max(4, math.floor(ns.db.listRows or 12)))
            local first = 1
            if not ns.db.showDone and not res.foreign then
                for i, r in ipairs(rows) do if not r.done then first = i break end end
            end
            local maxOff = math.max(0, #rows - first - (nrows - 1))
            W.offset = math.min(math.max(W.offset or 0, 0), maxOff)
            for i = 1, MAXROWS do
                local r = W.rows[i]
                local row = i <= nrows and rows[first + W.offset + i - 1] or nil
                if row then
                    local s = row.step
                    local lab = ""
                    if ns.db.showLevels then lab = (row.lvl and ("Lv " .. row.lvl) or ("#" .. row.idx)) .. "   " end
                    local color = row.done and "|cff777777" or ((res.next == row) and "|cffffd100" or "|cffffffff")
                    r.text:SetText(("%s%s%s  (%d/%d)|r"):format(color, lab, s.name, row.want, row.max))
                    if ns.db.showIcons then
                        local ic = E.SpellIcon(s.spell)
                        if ic then r.icon:SetTexture(ic) r.icon:SetDesaturated(row.done and true or false) r.icon:Show() else r.icon:Hide() end
                        r.text:ClearAllPoints() r.text:SetPoint("LEFT", 20, 0)
                    else
                        r.icon:Hide()
                        r.text:ClearAllPoints() r.text:SetPoint("LEFT", 0, 0)
                    end
                    r:Show()
                else
                    r:Hide()
                end
            end
            -- off the build
            if res.foreign or not ns.db.showOffLine then
                W.off:SetText("")
            elseif #res.off > 0 then
                local t = {}
                for i = 1, math.min(#res.off, 6) do t[#t + 1] = res.off[i].name end
                W.off:SetText("|cffff9955Off the build:|r " .. table.concat(t, ", ") .. (#res.off > 6 and " ..." or ""))
            else
                W.off:SetText("|cff55ff55On the build.|r")
            end
            -- buttons that only make sense sometimes
            local mine = b and b.custom
            if W.del then W.del:SetEnabled(mine and true or false) end
            if W.saveMine then W.saveMine:SetEnabled((not res.foreign) and res.owned.ok and res.owned.total > 0) end
        end
    end
    UI.Highlight()
end

local function ChangeClass(dir)
    local cur = E.ViewClass() or E.CLASSES[1]
    local idx = 1
    for i, c in ipairs(E.CLASSES) do if c == cur then idx = i end end
    idx = ((idx - 1 + dir) % #E.CLASSES) + 1
    local class = E.CLASSES[idx]
    ns.db.viewClass = E.IsOwnClass(class) and "mine" or class
    ns.db.spec = "auto"
    if W then W.offset = 0 end
    UI.Refresh()
end

local function CycleSpec(dir)
    local res = UI.Current(true)
    if not res then return end
    local class = E.ViewClass()
    local specs = E.SpecsForClass(class)
    local list = {}
    if E.IsOwnClass(class) then list[1] = "auto" end
    for _, s in ipairs(specs) do list[#list + 1] = s end
    local cur = ns.db.spec
    local idx = 1
    for i, v in ipairs(list) do if v == cur then idx = i end end
    if cur == "auto" and not E.IsOwnClass(class) then idx = 0 end
    idx = ((idx - 1 + dir) % #list) + 1
    ns.db.spec = list[idx]
    if ns.db.spec ~= "auto" and E.IsOwnClass(class) then ns.db.defaultSpec = ns.db.spec end
    if W then W.offset = 0 end
    UI.Refresh()
end

local function CycleBuild(dir)
    local res = UI.Current(true)
    if not res then return end
    local builds = E.Builds(res.spec)
    local idx = 1
    for i, b in ipairs(builds) do if b.id == res.build then idx = i end end
    idx = ((idx - 1 + dir) % #builds) + 1
    ns.db.build[res.spec] = builds[idx].id
    if W then W.offset = 0 end
    UI.Refresh()
end
UI.CycleBuild = CycleBuild

-- your own builds ----------------------------------------------------------
local function Report(id, err, dropped, replaced)
    if not id then ns.Print("could not add it: " .. tostring(err)) return end
    if dropped and #dropped > 0 then
        ns.Print(("left out %d talent%s that are not in this class: %s"):format(#dropped, #dropped == 1 and "" or "s", table.concat(dropped, ", ")))
    end
    local res = UI.Current(true)
    if res then ns.db.build[res.spec] = id end
    ns.Print((replaced and "updated and following: " or "saved and following: ") .. (E.Custom(res and res.spec or "")[tonumber(id:sub(2))] or { name = id }).name)
    UI.Refresh()
end

function UI.SaveMine()
    local res = UI.Current(true)
    if not res or res.foreign then ns.Print("save your own talents while you are looking at your own class.") return end
    if not res.owned.ok or res.owned.total == 0 then ns.Print("no talents to save yet.") return end
    local data = E.OwnedAsData(res.owned)
    local spec = res.spec
    Ask("TALENTWARDEN_NAME", "Name for this build (the talents you have now):", { default = "My " .. E.SpecName(spec) .. " build",
        fn = function(name) Report(E.AddCustom(spec, name, data)) end })
end

function UI.CopyBuild()
    local res = UI.Current(true)
    if not res then return end
    local spec, build = res.spec, res.build
    local text = E.ExportText(spec, build)
    local name, data = E.ParseShare(text)
    Ask("TALENTWARDEN_NAME", "Name for your copy of this build:", { default = (name or "My build") .. " (mine)",
        fn = function(nm) Report(E.AddCustom(spec, nm, data)) end })
end

function UI.Import()
    local res = UI.Current(true)
    if not res then return end
    local spec = res.spec
    Ask("TALENTWARDEN_IMPORT", "Paste a shared build for " .. E.SpecName(spec) .. " " .. (E.CLASS_NAMES[ns.Data[spec].class] or "") .. ":", {
        fn = function(text)
            local name, data = E.ParseShare(text)
            if not name then ns.Print("that is not a Talentwarden build (it should look like TW1:Name~0|Talent|5;...).") return end
            Report(E.AddCustom(spec, name, data))
        end })
end

function UI.Export()
    local res = UI.Current(true)
    if not res then return end
    Ask("TALENTWARDEN_EXPORT", "Copy this build (Ctrl+C) to share it:", { text = E.ExportText(res.spec, res.build) })
end

function UI.DeleteBuild()
    local res = UI.Current(true)
    if not res or type(res.build) ~= "string" or res.build:sub(1, 1) ~= "c" then return end
    local spec, id = res.spec, res.build
    local b = BuildLabel(res)
    Ask("TALENTWARDEN_DELETE", ("Delete your build \"%s\"?"):format(b and b.name or id), { fn = function()
        E.DeleteCustom(spec, id)
        UI.Refresh()
    end })
end

local function OpenOptions()
    if ns.WinLook then ns.WinLook.Toggle() else ns.Print("options are not available.") end
end
UI.OpenOptions = OpenOptions

local function BuildWindow()
    W = CreateFrame("Frame", "TalentwardenFrame", UIParent, "BackdropTemplate")
    W:SetSize(380, 470)
    W:SetFrameStrata("DIALOG")
    W:SetToplevel(true)
    W:SetClampedToScreen(true)
    W:EnableMouse(true)
    W:SetMovable(true)
    if W.SetBackdrop then
        W:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        W:SetBackdropColor(0.06, 0.06, 0.08, 0.96)
        W:SetBackdropBorderColor(1, 0.82, 0.1, 0.8)
    end
    local p = ns.db.pos
    if p then W:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else W:SetPoint("CENTER", UIParent, "CENTER", 300, 0) end
    W:RegisterForDrag("LeftButton")
    W:SetScript("OnDragStart", function(self) self:StartMoving() end)
    W:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local a, _, b, x, y = self:GetPoint()
        ns.db.pos = { a, b, x, y }
    end)
    W:Hide()
    tinsert(UISpecialFrames, "TalentwardenFrame")

    W.titleFS = W:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    W.titleFS:SetPoint("TOPLEFT", 12, -10)
    W.titleFS:SetText("Talentwarden")
    local close = CreateFrame("Button", nil, W, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- class, spec and build selectors
    local function Selector(label, y, onLeft, onRight)
        local lbl = W:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("TOPLEFT", 12, y - 4) lbl:SetText(label)
        local l = Btn(W, "<", 22, onLeft) l:SetPoint("TOPLEFT", 52, y)
        local r = Btn(W, ">", 22, onRight) r:SetPoint("TOPRIGHT", -12, y)
        local fs = W:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("LEFT", l, "RIGHT", 6, 0) fs:SetPoint("RIGHT", r, "LEFT", -6, 0)
        fs:SetJustifyH("CENTER")
        return fs
    end
    W.class = Selector("Class", -34, function() ChangeClass(-1) end, function() ChangeClass(1) end)
    W.spec = Selector("Spec", -58, function() CycleSpec(-1) end, function() CycleSpec(1) end)
    W.build = Selector("Build", -82, function() CycleBuild(-1) end, function() CycleBuild(1) end)
    W.uses = W:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.uses:SetPoint("TOPLEFT", 12, -108)

    -- next talent
    local box = CreateFrame("Frame", nil, W, "BackdropTemplate")
    box:SetPoint("TOPLEFT", 10, -126) box:SetPoint("TOPRIGHT", -10, -126) box:SetHeight(64)
    if box.SetBackdrop then
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        box:SetBackdropColor(0.12, 0.12, 0.16, 1)
        box:SetBackdropBorderColor(1, 0.82, 0.1, 0.5)
    end
    W.icon = box:CreateTexture(nil, "ARTWORK")
    W.icon:SetSize(44, 44) W.icon:SetPoint("LEFT", 10, 0)
    W.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    W.nextLabel = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.nextLabel:SetPoint("TOPLEFT", W.icon, "TOPRIGHT", 10, -2)
    W.nextText = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    W.nextText:SetPoint("TOPLEFT", W.nextLabel, "BOTTOMLEFT", 0, -3)
    W.nextSub = box:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.nextSub:SetPoint("TOPLEFT", W.nextText, "BOTTOMLEFT", 0, -2)

    W.info = W:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.info:SetPoint("TOPLEFT", 12, -198)

    -- step list
    W.rows = {}
    W.offset = 0
    for i = 1, MAXROWS do
        local r = CreateFrame("Frame", nil, W)
        r:SetSize(350, ROWH)
        r:SetPoint("TOPLEFT", 14, -TOP_LIST - (i - 1) * ROWH)
        r.icon = r:CreateTexture(nil, "ARTWORK")
        r.icon:SetSize(16, 16) r.icon:SetPoint("LEFT", 0, 0)
        r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        r.text:SetPoint("LEFT", 20, 0)
        W.rows[i] = r
    end
    W:EnableMouseWheel(true)
    W:SetScript("OnMouseWheel", function(self, delta)
        self.offset = (self.offset or 0) - delta * 3
        UI.Refresh()
    end)

    W.off = W:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    W.off:SetPoint("BOTTOMLEFT", 12, 54) W.off:SetWidth(356) W.off:SetJustifyH("LEFT")

    -- buttons
    W.saveMine = Btn(W, "Save my talents", 112, UI.SaveMine) W.saveMine:SetPoint("BOTTOMLEFT", 10, 28)
    local cp = Btn(W, "Copy build", 84, UI.CopyBuild) cp:SetPoint("LEFT", W.saveMine, "RIGHT", 4, 0)
    local im = Btn(W, "Import", 60, UI.Import) im:SetPoint("LEFT", cp, "RIGHT", 4, 0)
    local ex = Btn(W, "Export", 60, UI.Export) ex:SetPoint("LEFT", im, "RIGHT", 4, 0)
    W.del = Btn(W, "Delete mine", 84, UI.DeleteBuild) W.del:SetPoint("BOTTOMLEFT", 10, 6)
    local op = Btn(W, "Options", 70, OpenOptions) op:SetPoint("LEFT", W.del, "RIGHT", 4, 0)
    local rf = Btn(W, "Refresh", 62, function() UI.Refresh() end) rf:SetPoint("LEFT", op, "RIGHT", 4, 0)

    ApplyLook()
    W:SetScript("OnShow", function() ApplyLook() UI.Refresh() end)
    if ns.WinLook then pcall(ns.WinLook.Attach, "main", W) end
end

function UI.Toggle()
    if not W then BuildWindow() end
    if W:IsShown() then W:Hide() else W:Show() end
end
function UI.Show() if not W then BuildWindow() end W:Show() end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
local mini
local function PlaceMini()
    local a = math.rad(ns.db.minimap.angle or 200)
    local r = ((Minimap and Minimap:GetWidth() or 140) / 2) + 6
    mini:ClearAllPoints()
    mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
end

local function BuildMini()
    if not Minimap then return end
    mini = CreateFrame("Button", "TalentwardenMinimapButton", Minimap)
    mini:SetSize(31, 31)
    mini:SetFrameStrata("MEDIUM")
    mini:SetFrameLevel(8)
    mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mini:RegisterForDrag("LeftButton")
    mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local icon = mini:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20) icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture(ns.ICON) icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    local border = mini:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53) border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    mini:SetScript("OnClick", function(_, btn)
        if IsAltKeyDown() then
            OpenOptions()
        elseif btn == "RightButton" then
            -- right-click: next build for the spec you are looking at
            local res = UI.Current(true)
            if res then
                local builds = E.Builds(res.spec)
                local idx = 1
                for i, b in ipairs(builds) do if b.id == res.build then idx = i end end
                idx = (idx % #builds) + 1
                ns.db.build[res.spec] = builds[idx].id
                ns.Print("following: " .. builds[idx].name)
                UI.Refresh()
            end
        elseif IsShiftKeyDown() then
            UI.Remind("manual")
        else
            UI.Toggle()
        end
    end)
    mini:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            ns.db.minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMini()
        end)
    end)
    mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    mini:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Talentwarden", 1, 0.8, 0)
        local res = UI.Current()
        if res and res.next and not res.foreign then
            GameTooltip:AddLine("Next: " .. res.next.step.name, 1, 1, 1)
        end
        GameTooltip:AddLine("Left-click: open the window.", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Right-click: switch to the next build.", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Shift-click: say the next talent in chat.", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Alt-click: options (look, glow, chat, window).", 0.85, 0.85, 0.85)
        GameTooltip:AddLine("Drag: move this button.", 0.85, 0.85, 0.85)
        GameTooltip:Show()
    end)
    mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMini()
end

function UI.UpdateMinimap()
    if not mini then BuildMini() end
    if mini then mini:SetShown(ns.db.minimap.show and true or false) end
end

---------------------------------------------------------------------------
-- Events and slash command
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_TALENT_UPDATE",
    "ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED", "ADDON_LOADED" }) do
    pcall(ev.RegisterEvent, ev, e)
end
local pending = false
ev:SetScript("OnEvent", function(_, event)
    if event == "ADDON_LOADED" then HookRoots() return end
    if pending then return end
    pending = true
    C_Timer.After(0.6, function()
        pending = false
        HookRoots()
        UI.Refresh()
        if event == "PLAYER_LEVEL_UP" then UI.Remind("level")
        elseif event == "TRAIT_NODE_CHANGED" or event == "PLAYER_TALENT_UPDATE" then UI.Remind("pick") UI.WarnOff()
        else UI.WarnOff() end
    end)
end)

ns.AddHook("login", function()
    UI.UpdateMinimap()
    EnsureTicker()
    C_Timer.After(4, function()
        HookRoots()
        UI.Remind("login")
        UI.WarnOff()
    end)
end)

local function Help()
    ns.Print("/talentwarden  (or /tw) opens the window; Alt-click the minimap button for the options.")
    ns.Print("/tw next  says your next talent in chat.")
    ns.Print("/tw class <name> | mine  reads another class's guides (for example: /tw class mage).")
    ns.Print("/tw spec auto | <spec>  chooses a spec (for example: /tw spec destruction).")
    ns.Print("/tw builds  lists the builds; /tw build <number>  follows one (0 = leveling guide).")
    ns.Print("/tw save <name>  saves the talents you have now as a build of your own.")
    ns.Print("/tw scan  tells me what it can see in the talent window (for fixing the glow).")
    ns.Print("/tw minimap  shows or hides the minimap button.")
end

local function FindClass(want)
    want = want:lower()
    if want == "" then return nil end
    for _, c in ipairs(E.CLASSES) do
        if c:lower():find(want, 1, true) or E.CLASS_NAMES[c]:lower():find(want, 1, true) then return c end
    end
end

SLASH_TALENTWARDEN1 = "/talentwarden"
SLASH_TALENTWARDEN2 = "/tw"
SlashCmdList["TALENTWARDEN"] = function(msg)
    local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "" then UI.Toggle()
    elseif cmd == "options" or cmd == "look" then OpenOptions()
    elseif cmd == "next" then
        local res = UI.Current(true)
        if not res or res.foreign then ns.Print("no guide for your class.") return end
        ns.Print(E.Summary(res) or "this build is complete.")
    elseif cmd == "class" then
        if rest:lower() == "mine" or rest == "" then ns.db.viewClass = "mine" ns.db.spec = "auto" UI.Refresh() ns.Print("reading your own class.") return end
        local c = FindClass(rest)
        if not c then ns.Print("no such class. Use one of: " .. table.concat(E.CLASSES, ", "):lower()) return end
        ns.db.viewClass = E.IsOwnClass(c) and "mine" or c
        ns.db.spec = "auto"
        UI.Refresh()
        ns.Print("reading the " .. E.CLASS_NAMES[c] .. " guides.")
    elseif cmd == "spec" then
        local want = rest:lower()
        local class = E.ViewClass()
        if want == "auto" then ns.db.spec = "auto" UI.Refresh() ns.Print("spec: automatic.") return end
        for _, s in ipairs(E.SpecsForClass(class)) do
            if s:find(want, 1, true) and want ~= "" then
                ns.db.spec = s
                if E.IsOwnClass(class) then ns.db.defaultSpec = s end
                UI.Refresh() ns.Print("spec: " .. E.SpecName(s)) return
            end
        end
        ns.Print("no such spec. These: " .. table.concat(E.SpecsForClass(class), ", "))
    elseif cmd == "builds" then
        local res = UI.Current(true)
        if not res then return end
        for i, b in ipairs(E.Builds(res.spec)) do
            ns.Print(("%d%s  %s"):format(i - 1, b.id == res.build and " *" or "", b.name))
        end
    elseif cmd == "build" then
        local res = UI.Current(true)
        if not res then return end
        local n = tonumber(rest)
        local builds = E.Builds(res.spec)
        if n and builds[n + 1] then ns.db.build[res.spec] = builds[n + 1].id
        else ns.Print("use /tw builds to see the numbers.") return end
        UI.Refresh()
        ns.Print("following: " .. builds[n + 1].name)
    elseif cmd == "save" then
        local res = UI.Current(true)
        if not res or res.foreign then ns.Print("save your own talents while you are looking at your own class.") return end
        if not res.owned.ok or res.owned.total == 0 then ns.Print("no talents to save yet.") return end
        Report(E.AddCustom(res.spec, rest ~= "" and rest or ("My " .. E.SpecName(res.spec) .. " build"), (E.OwnedAsData(res.owned))))
    elseif cmd == "scan" then
        UI.Refresh()
        local res = UI.Current()
        local owned = res and res.owned
        ns.Print(("talents read: %s, points spent %s"):format(owned and tostring(owned.ok) or "?", owned and owned.total or "?"))
        ns.Print(("talent windows open: %s; buttons seen: %s; glowing: %s"):format(
            scanned.roots and #scanned.roots > 0 and table.concat(scanned.roots, ",") or "none",
            tostring(scanned.buttons or 0), tostring(scanned.matched or 0)))
        for _, rn in ipairs(ROOT_NAMES) do ns.Print(rn .. ": " .. (_G[rn] and "exists" or "no")) end
    elseif cmd == "minimap" then
        ns.db.minimap.show = not ns.db.minimap.show
        UI.UpdateMinimap()
    else
        Help()
    end
end
