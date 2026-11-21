-- Talentwarden engine: turns the build data into a list of steps, reads what you have spent in the game,
-- and works out the next point, what is behind, and what is off the build.
local ADDON_NAME, ns = ...
local E = {}
ns.Engine = E
local IsSecret = ns.IsSecret

local function Norm(s) return (tostring(s or ""):lower():gsub("[^%w]", "")) end
E.Norm = Norm

---------------------------------------------------------------------------
-- Parsing the data strings
---------------------------------------------------------------------------
local parsed = {}

-- "tree|talent|spellID|points;..." -> one step per point, in order; level = 10 for the first point
function E.LevelSteps(spec)
    local key = "L" .. spec
    if parsed[key] then return parsed[key] end
    local d = ns.Data[spec]
    local steps = {}
    if d and d.level then
        for tree, name, spell, n in d.level:gmatch("(%d+)|([^|;]+)|(%d+)|(%d+)") do
            for _ = 1, tonumber(n) do
                steps[#steps + 1] = { tree = tonumber(tree), name = name, spell = tonumber(spell), lvl = 9 + #steps + 1 }
            end
        end
    end
    parsed[key] = steps
    return steps
end

-- names of one class's talents -> spell id / tree, from every spec of that class (the builds only carry names)
local classMaps = {}
local function ClassMaps(class)
    if classMaps[class] then return classMaps[class] end
    local ids, trees, byId, names = {}, {}, {}, {}
    for spec, d in pairs(ns.Data) do
        if d.class == class then
            for treeS, name, spellS in (d.level or ""):gmatch("(%d+)|([^|;]+)|(%d+)|%d+") do
                ids[Norm(name)] = tonumber(spellS)
                trees[Norm(name)] = tonumber(treeS)
                byId[tonumber(spellS)] = Norm(name)
                names[Norm(name)] = name
            end
        end
    end
    -- talents that only show up in the endgame builds
    for spec, d in pairs(ns.Data) do
        if d.class == class then
            for _, raw in ipairs(d.builds or {}) do
                for treeS, name in raw:gmatch("(%d+)|([^|;~]+)|%d+") do
                    local k = Norm(name)
                    if trees[k] == nil then trees[k] = tonumber(treeS) end
                    names[k] = names[k] or name
                end
            end
        end
    end
    classMaps[class] = { ids = ids, trees = trees, byId = byId, names = names }
    return classMaps[class]
end
E.ClassMaps = ClassMaps

---------------------------------------------------------------------------
-- Classes, roles and your own builds
---------------------------------------------------------------------------
E.CLASSES = { "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }
E.CLASS_NAMES = { DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage", PALADIN = "Paladin", PRIEST = "Priest",
    ROGUE = "Rogue", SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior" }
E.CLASS_COLORS = { DRUID = "ff7d0a", HUNTER = "abd473", MAGE = "40c7eb", PALADIN = "f58cba", PRIEST = "ffffff",
    ROGUE = "fff569", SHAMAN = "0070de", WARLOCK = "8788ee", WARRIOR = "c79c6e" }

local ROLES = {
    ["protection-warrior"] = "Tank", ["protection-paladin"] = "Tank", ["feral-druid"] = "Tank / Melee",
    ["restoration-druid"] = "Healer", ["holy-paladin"] = "Healer", ["holy-priest"] = "Healer",
    ["discipline-priest"] = "Healer", ["restoration-shaman"] = "Healer",
}
function E.Role(spec) return ROLES[spec] or "Damage" end

-- tags from a build's name, so every build says what it is for
function E.Uses(title)
    local t = tostring(title or ""):lower()
    local out = {}
    local function add(s) out[#out + 1] = s end
    if t:find("leveling") then add("Leveling") end
    if t:find("pvp") then add("PvP") end
    if t:find("world") then add("World") end
    if t:find("raid") then add("Raid") end
    if t:find("dungeon") then add("Dungeon") end
    if t:find("solo") then add("Solo") end
    if t:find("tank") or t:find("mitigation") or t:find("bear") then add("Tank") end
    if t:find("heal") or t:find("light's vigil") then add("Healer") end
    if t:find("aoe") then add("AoE") end
    return out
end

function E.ViewClass()
    local own = E.ClassToken()
    local v = ns.db and ns.db.viewClass
    if v and v ~= "mine" and E.CLASS_NAMES[v] then return v end
    return own
end
function E.IsOwnClass(class) return class ~= nil and class == E.ClassToken() end

function E.Custom(spec)
    local c = ns.db and ns.db.custom
    if not c then return {} end
    c[spec] = c[spec] or {}
    return c[spec]
end

-- the talents you have now, as a build string "tree|talent|points;..." (trees by points, top row first)
function E.OwnedAsData(owned, class)
    owned = owned or E.ReadOwned()
    class = class or E.ClassToken()
    local maps = ClassMaps(class)
    local items = {}
    local function Add(k, rank)
        if items[k] then items[k].rank = math.max(items[k].rank, rank) return end
        items[k] = { key = k, rank = rank, name = (owned.names and owned.names[k]) or maps.names[k] or k,
            tree = maps.trees[k], pos = owned.pos and owned.pos[k] or 0 }
    end
    for k, r in pairs(owned.byName) do Add(k, r) end
    for id, r in pairs(owned.byID) do local k = maps.byId[id] if k then Add(k, r) end end
    local list = {}
    for _, it in pairs(items) do if it.tree then list[#list + 1] = it end end
    local total = {}
    for _, it in ipairs(list) do total[it.tree] = (total[it.tree] or 0) + it.rank end
    table.sort(list, function(a, b)
        if a.tree ~= b.tree then
            if total[a.tree] ~= total[b.tree] then return total[a.tree] > total[b.tree] end
            return a.tree < b.tree
        end
        if a.pos ~= b.pos then return a.pos < b.pos end
        return a.name < b.name
    end)
    local parts, pts = {}, 0
    for _, it in ipairs(list) do
        parts[#parts + 1] = ("%d|%s|%d"):format(it.tree, it.name, it.rank)
        pts = pts + it.rank
    end
    return table.concat(parts, ";"), pts
end

-- "tree|talent|points;..." from text typed or pasted; unknown talents are dropped, ranks are limited to 5
function E.CleanData(data, class)
    local maps = ClassMaps(class)
    local ordered = tostring(data or ""):sub(1, 1) == "!"
    local parts, dropped, pts = {}, {}, 0
    for treeS, name, ptsS in tostring(data or ""):gmatch("(%d+)|([^|;~]+)|(%d+)") do
        local k = Norm(name)
        if maps.names[k] then
            local p = math.min(tonumber(ptsS) or 0, 5)
            if p > 0 then
                parts[#parts + 1] = ("%d|%s|%d"):format(maps.trees[k] or tonumber(treeS) or 0, maps.names[k], p)
                pts = pts + p
            end
        else
            dropped[#dropped + 1] = name
        end
    end
    return (ordered and "!" or "") .. table.concat(parts, ";"), pts, dropped
end

-- "Name~tree|talent|points;..." with an optional "TW1:" in front; returns name, data
function E.ParseShare(text)
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", ""):gsub("^TW1:%s*", "")
    local name, data = text:match("^(.-)~(.*)$")
    if not name then return nil end
    return (name:gsub("^%s+", ""):gsub("%s+$", "")), data
end

-- "Title~tree|talent|points;..." -> title, steps (one per point). Trees are taken in order of points,
-- the biggest first, and within a tree in the order the guide lists them (top row to bottom row).
function E.RawBuild(spec, index)
    local d = ns.Data[spec]
    if type(index) == "string" and index:sub(1, 1) == "c" then
        local c = E.Custom(spec)[tonumber(index:sub(2))]
        if c then return c.name .. "~" .. c.data end
        return nil
    end
    return d and d.builds and d.builds[tonumber(index) or 0]
end

function E.BuildSteps(spec, index)
    local raw = E.RawBuild(spec, index)
    if not raw then return {}, "" end
    local key = "B" .. spec .. tostring(index) .. raw
    if parsed[key] then return parsed[key].steps, parsed[key].title end
    local d = ns.Data[spec]
    local title, body = raw:match("^(.-)~(.*)$")
    local maps = ClassMaps(d.class)
    local byTree, total, flat = {}, {}, {}
    local ordered = body:sub(1, 1) == "!"
    for treeS, name, ptsS in body:gmatch("(%d+)|([^|;]+)|(%d+)") do
        local tree, pts = tonumber(treeS), tonumber(ptsS)
        byTree[tree] = byTree[tree] or {}
        table.insert(byTree[tree], { name = name, pts = pts })
        flat[#flat + 1] = { tree = tree, name = name, pts = pts }
        total[tree] = (total[tree] or 0) + pts
    end
    if ordered then
        local steps = {}
        for _, it in ipairs(flat) do
            for _ = 1, it.pts do steps[#steps + 1] = { tree = it.tree, name = it.name, spell = maps.ids[Norm(it.name)], lvl = 9 + #steps + 1 } end
        end
        parsed[key] = { steps = steps, title = title }
        return steps, title
    end
    local order = {}
    for t in pairs(byTree) do order[#order + 1] = t end
    table.sort(order, function(a, b) if total[a] ~= total[b] then return total[a] > total[b] end return a < b end)
    local steps = {}
    for _, t in ipairs(order) do
        for _, it in ipairs(byTree[t]) do
            for _ = 1, it.pts do
                steps[#steps + 1] = { tree = t, name = it.name, spell = maps.ids[Norm(it.name)] }
            end
        end
    end
    parsed[key] = { steps = steps, title = title }
    return steps, title
end

---------------------------------------------------------------------------
-- Specs and builds
---------------------------------------------------------------------------
function E.ClassToken()
    local ok, _, token = pcall(UnitClass, "player")
    if ok and type(token) == "string" and not IsSecret(token) then return token end
end

function E.MainTree(spec)
    local c = {}
    for _, s in ipairs(E.LevelSteps(spec)) do c[s.tree] = (c[s.tree] or 0) + 1 end
    local best, bn = 0, -1
    for t, n in pairs(c) do if n > bn then best, bn = t, n end end
    return best
end

local function Title(s) return (s:gsub("(%a)([%w']*)", function(a, b) return a:upper() .. b end)) end

function E.SpecName(spec)
    local d = ns.Data[spec]
    if not d then return spec end
    local class = d.class:sub(1, 1) .. d.class:sub(2):lower()
    local base = spec:gsub("%-" .. class:lower() .. "$", ""):gsub("%-", " ")
    return Title(base)
end

-- the specs of one class, in tree order
function E.SpecsForClass(class)
    local list = {}
    for spec, d in pairs(ns.Data) do
        if d.class == class then list[#list + 1] = spec end
    end
    table.sort(list, function(a, b)
        local ta, tb = E.MainTree(a), E.MainTree(b)
        if ta ~= tb then return ta < tb end
        return a < b
    end)
    return list
end

function E.Builds(spec)
    local d = ns.Data[spec]
    local out = { { id = "level", name = "Leveling guide (levels 10 to 60)", uses = { "Leveling" } } }
    for i = 1, #(d and d.builds or {}) do
        local _, title = E.BuildSteps(spec, i)
        out[#out + 1] = { id = i, name = title, uses = E.Uses(title) }
    end
    for i, c in ipairs(E.Custom(spec)) do
        out[#out + 1] = { id = "c" .. i, name = c.name, custom = true, uses = { "Mine" } }
    end
    return out
end

-- the steps of one build of one spec
function E.Plan(spec, build)
    if build == nil or build == "level" then return E.LevelSteps(spec), "Leveling guide" end
    local steps, title = E.BuildSteps(spec, build)
    return steps, title
end

---------------------------------------------------------------------------
-- What you have spent now
---------------------------------------------------------------------------
local function SpellName(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.name and not IsSecret(info.name) then return info.name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" and not IsSecret(name) then return name end
    end
end
E.SpellName = SpellName

function E.SpellIcon(id)
    if not id then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, id)
        if ok and type(info) == "table" and info.iconID and not IsSecret(info.iconID) then return info.iconID end
    end
    if GetSpellTexture then
        local ok, t = pcall(GetSpellTexture, id)
        if ok and t and not IsSecret(t) then return t end
    end
end

-- owned.byID[spellID] = rank, owned.byName[normalized name] = rank, owned.total = points spent
function E.ReadOwned()
    local owned = { byID = {}, byName = {}, names = {}, pos = {}, total = 0, ok = false, configID = nil, treeIDs = nil }
    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    if not (C_Traits and configID and not IsSecret(configID)) then return owned end
    owned.configID = configID
    pcall(function()
        local info = C_Traits.GetConfigInfo(configID)
        if not info or not info.treeIDs then return end
        owned.treeIDs = info.treeIDs
        owned.ok = true
        owned.meta = {}
        for treeIdx, treeID in ipairs(info.treeIDs) do
            for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
                local node = C_Traits.GetNodeInfo(configID, nodeID)
                local rank = node and (node.ranksPurchased or node.currentRank or 0)
                if node and rank and not IsSecret(rank) then
                    local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
                    local entry = entryID and C_Traits.GetEntryInfo(configID, entryID)
                    local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID)
                    local spellID = def and def.spellID
                    if spellID and not IsSecret(spellID) then
                        local name = SpellName(spellID)
                        local py, px = tonumber(node.posY), tonumber(node.posX)
                        if name and py and px and not IsSecret(py) and not IsSecret(px) then
                            -- where every talent sits (its row), so the order of a plan can be checked
                            owned.meta[Norm(name)] = { y = py, tree = treeIdx - 1 }
                        end
                        if rank > 0 then
                            owned.byID[spellID] = rank
                            if name then
                                owned.byName[Norm(name)] = rank
                                owned.names[Norm(name)] = name
                                if py and px and not IsSecret(py) and not IsSecret(px) then owned.pos[Norm(name)] = py * 100000 + px end
                            end
                            owned.total = owned.total + rank
                        end
                    end
                end
            end
        end
    end)
    return owned
end

function E.RankOf(owned, step)
    local a = step.spell and owned.byID[step.spell] or 0
    local b = owned.byName[Norm(step.name)] or 0
    return math.max(a, b)
end

-- points you can still spend: the game's own count if it gives one, otherwise level - 9 - spent
function E.Unspent(owned)
    owned = owned or E.ReadOwned()
    if owned.configID and owned.treeIDs and C_Traits.GetTreeCurrencyInfo then
        for _, treeID in ipairs(owned.treeIDs) do
            local ok, cur = pcall(C_Traits.GetTreeCurrencyInfo, owned.configID, treeID, false)
            if ok and type(cur) == "table" and cur[1] and type(cur[1].quantity) == "number" and not IsSecret(cur[1].quantity) then
                return cur[1].quantity, owned
            end
        end
    end
    local lvl = UnitLevel and UnitLevel("player") or 0
    if type(lvl) ~= "number" or IsSecret(lvl) then lvl = 0 end
    return math.max(0, lvl - 9 - owned.total), owned
end

-- which spec you are: the tree you have the most points in (by the names in the data)
function E.DetectSpec(owned, class)
    owned = owned or E.ReadOwned()
    class = class or E.ClassToken()
    if not class then return nil end
    local specs = E.SpecsForClass(class)
    if #specs == 0 then return nil end
    local maps = ClassMaps(class)
    local perTree, best, bn = {}, nil, 0
    local ownedKey = {}
    for nameKey, rank in pairs(owned.byName) do ownedKey[nameKey] = rank end
    for id, rank in pairs(owned.byID) do
        local k = maps.byId[id]
        if k and rank > (ownedKey[k] or 0) then ownedKey[k] = rank end
    end
    for nameKey, rank in pairs(ownedKey) do
        local t = maps.trees[nameKey]
        if t then perTree[t] = (perTree[t] or 0) + rank end
    end
    for t, n in pairs(perTree) do if n > bn then best, bn = t, n end end
    if best then
        for _, spec in ipairs(specs) do if E.MainTree(spec) == best then return spec, true end end
    end
    return nil
end

-- the spec to show: your choice, or (for your own class) the detected one, or the default, or the first
function E.CurrentSpec(owned)
    local db = ns.db
    local class = E.ViewClass()
    if not class then return nil end
    if db.spec and db.spec ~= "auto" and ns.Data[db.spec] and ns.Data[db.spec].class == class then return db.spec, false end
    if E.IsOwnClass(class) then
        local spec, detected = E.DetectSpec(owned, class)
        if spec then return spec, true end
        if db.defaultSpec and ns.Data[db.defaultSpec] and ns.Data[db.defaultSpec].class == class then return db.defaultSpec, false end
    end
    return E.SpecsForClass(class)[1], false
end

function E.CurrentBuild(spec)
    local b = ns.db.build and ns.db.build[spec]
    if b == nil or b == "level" then return "level" end
    if type(b) == "string" and b:sub(1, 1) == "c" then
        if E.Custom(spec)[tonumber(b:sub(2))] then return b end
        return "level"
    end
    local n = tonumber(b)
    if n and ns.Data[spec] and ns.Data[spec].builds[n] then return n end
    return "level"
end

---------------------------------------------------------------------------
-- The answer
---------------------------------------------------------------------------
-- Walks the plan: for each step, how many points of that talent the plan wants by then, versus what you have.
-- Returns the full list of rows (with done flags), the next step, and the talents that are off the plan.
-- Puts the plan in an order the game lets you follow. A talent in a lower row needs 5 points spent in the rows above it
-- in its own tree; when a guide lists such a talent too early, the points it is waiting for are moved ahead of it.
-- Also numbers every point with the level you take it at (the first point is level 10). Needs the game's talent layout
-- (owned.meta); without it the plan is returned as written.
local legalCache = {}
function E.Legalize(steps, owned, key)
    local meta = owned and owned.meta
    if not (meta and next(meta)) then return steps, 0 end
    local sig = {}
    for i, st in ipairs(steps) do sig[i] = st.name end
    local ck = key .. "#" .. table.concat(sig, ",")
    if legalCache[ck] then return legalCache[ck].steps, legalCache[ck].moved end
    -- row number of each talent within its tree (0 = top row)
    local ys = {}
    for _, m in pairs(meta) do
        ys[m.tree] = ys[m.tree] or {}
        ys[m.tree][m.y] = true
    end
    local rowOf = {}
    for tree, set in pairs(ys) do
        local list = {}
        for y in pairs(set) do list[#list + 1] = y end
        table.sort(list)
        local idx = {}
        for i, y in ipairs(list) do idx[y] = i - 1 end
        rowOf[tree] = idx
    end
    local function Row(st)
        local m = meta[Norm(st.name)]
        return m and rowOf[m.tree] and rowOf[m.tree][m.y], m and m.tree
    end
    for _, st in ipairs(steps) do if not Row(st) then return steps, 0 end end   -- a talent the game does not know: leave it
    local left, out, spent, moved = {}, {}, {}, 0
    for i, st in ipairs(steps) do left[i] = st end
    while #left > 0 do
        local pick
        for i, st in ipairs(left) do
            local row, tree = Row(st)
            if (spent[tree] or 0) >= row * 5 then pick = i break end
        end
        if not pick then pick = 1 end   -- nothing fits: keep the guide's own order
        if pick ~= 1 then moved = moved + 1 end
        local st = table.remove(left, pick)
        local _, tree = Row(st)
        spent[tree] = (spent[tree] or 0) + 1
        out[#out + 1] = { tree = st.tree, name = st.name, spell = st.spell, lvl = 9 + #out + 1 }
    end
    legalCache[ck] = { steps = out, moved = moved }
    return out, moved
end

function E.Evaluate(spec, build, owned)
    owned = owned or E.ReadOwned()
    local foreign = not E.IsOwnClass(ns.Data[spec] and ns.Data[spec].class)
    if foreign then owned = { byID = {}, byName = {}, names = {}, pos = {}, total = 0, ok = false } end
    local steps = E.Plan(spec, build)
    local moved = 0
    if not foreign then steps, moved = E.Legalize(steps, owned, tostring(spec) .. "/" .. tostring(build)) end
    local need, rows, nextRow = {}, {}, nil
    local planTotal = {}
    for i, s in ipairs(steps) do
        local k = Norm(s.name)
        need[k] = (need[k] or 0) + 1
        planTotal[k] = need[k]
        local have = E.RankOf(owned, s)
        local row = { step = s, idx = i, want = need[k], have = math.min(have, need[k]), done = have >= need[k], lvl = s.lvl }
        rows[i] = row
        if not row.done and not nextRow then nextRow = row end
    end
    for _, row in ipairs(rows) do row.max = planTotal[Norm(row.step.name)] end
    local off = {}
    -- anything you have that the plan never uses, or more points than it wants
    local seen = {}
    local class = ns.Data[spec] and ns.Data[spec].class
    local maps = class and ClassMaps(class)
    local ownedKey = {}
    for nameKey, rank in pairs(owned.byName) do ownedKey[nameKey] = rank end
    if maps then
        for id, rank in pairs(owned.byID) do
            local k = maps.byId[id]
            if k and rank > (ownedKey[k] or 0) then ownedKey[k] = rank end
        end
    end
    for nameKey, rank in pairs(ownedKey) do
        local allowed = planTotal[nameKey] or 0
        if rank > allowed and maps and maps.trees[nameKey] ~= nil then
            off[#off + 1] = { key = nameKey, rank = rank, allowed = allowed }
        end
    end
    -- show real names
    for _, o in ipairs(off) do
        for _, s in ipairs(steps) do if Norm(s.name) == o.key then o.name = s.name break end end
        if not o.name then
            for sp, d in pairs(ns.Data) do
                if d.class == class then
                    for _, s in ipairs(E.LevelSteps(sp)) do if Norm(s.name) == o.key then o.name = s.name break end end
                end
                if o.name then break end
            end
        end
        o.name = o.name or o.key
    end
    table.sort(off, function(a, b) return a.name < b.name end)
    return { rows = rows, next = nextRow, off = off, owned = owned, spec = spec, build = build, total = #steps, foreign = foreign, moved = moved }
end

-- one-line summary for chat
function E.Summary(res)
    local n = res.next
    if not n then return nil end
    local where = n.lvl and (" (level " .. n.lvl .. " step)") or ""
    return ("next talent: |cffffd100%s|r, rank %d of %d%s"):format(n.step.name, n.have + 1, n.max, where)
end

-- the next talents to take: up to n different ones, each with its order number (1 = next)
function E.Upcoming(res, n)
    local out, seen = {}, {}
    if not res or res.foreign then return out end
    for _, row in ipairs(res.rows) do
        if not row.done then
            local k = E.Norm(row.step.name)
            if not seen[k] then
                seen[k] = true
                out[#out + 1] = { step = row.step, order = #out + 1, row = row }
                if #out >= n then break end
            end
        end
    end
    return out
end

-- the talents to take with the points you can spend now: each row is one point, grouped by talent, in order
function E.UpcomingPoints(res, points)
    local out, byKey, left = {}, {}, math.max(1, points or 1)
    if not res or res.foreign then return out end
    for _, row in ipairs(res.rows) do
        if not row.done then
            if left <= 0 then break end
            local k = E.Norm(row.step.name)
            local w = byKey[k]
            if not w then w = { step = row.step, order = #out + 1, row = row, pts = 0 } byKey[k] = w out[#out + 1] = w end
            w.pts = w.pts + 1
            left = left - 1
        end
    end
    return out
end

-- text to share one build: "TW1:Name~tree|talent|points;..."
function E.ExportText(spec, build)
    local d = ns.Data[spec]
    if build == nil or build == "level" then
        local parts = {}
        for tree, name, _, n in (d.level or ""):gmatch("(%d+)|([^|;]+)|(%d+)|(%d+)") do
            parts[#parts + 1] = tree .. "|" .. name .. "|" .. n
        end
        return "TW1:" .. E.SpecName(spec) .. " leveling~!" .. table.concat(parts, ";")
    end
    return "TW1:" .. (E.RawBuild(spec, build) or "")
end

-- add a build of your own to a spec; returns its id, or nil and why
function E.AddCustom(spec, name, data)
    local d = ns.Data[spec]
    if not d then return nil, "no such spec" end
    local clean, pts, dropped = E.CleanData(data, d.class)
    if pts == 0 then return nil, "no talents of " .. (E.CLASS_NAMES[d.class] or d.class) .. " found in it", dropped end
    name = tostring(name or ""):gsub("[~|;]", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then name = "My build" end
    local list = E.Custom(spec)
    for i, c in ipairs(list) do
        if c.name:lower() == name:lower() then c.data = clean return "c" .. i, nil, dropped, true end
    end
    list[#list + 1] = { name = name, data = clean }
    return "c" .. #list, nil, dropped
end

function E.DeleteCustom(spec, id)
    if type(id) ~= "string" or id:sub(1, 1) ~= "c" then return false end
    local list = E.Custom(spec)
    local n = tonumber(id:sub(2))
    if not (n and list[n]) then return false end
    table.remove(list, n)
    -- builds after it move up one place: fix what you were following
    local b = ns.db.build[spec]
    if b == id then ns.db.build[spec] = "level"
    elseif type(b) == "string" and b:sub(1, 1) == "c" and tonumber(b:sub(2)) > n then ns.db.build[spec] = "c" .. (tonumber(b:sub(2)) - 1) end
    return true
end
