-- Looking For Group do servidor simulado: atividades, listagens e a C_LFGList de cada cliente.
-- Cada listagem é { leader = "Nome", members = { {name, level, class, role, roles, zone}, ... },
--   activityIDs = {...}, delisted, age, remaining = {tank, healer, dps}, secret = {campo = true},
--   secretInfo, pendingName (nome ainda não chegou) }.
local Client = require("sim.client")

local LFG = {}
LFG.__index = LFG

local ACTIVITIES = {
    [1] = { fullName = "Deadmines", shortName = "VC", maxNumPlayers = 5, minLevelSuggestion = 17, maxLevelSuggestion = 26, categoryID = 2 },
    [2] = { fullName = "Wailing Caverns", shortName = "WC", maxNumPlayers = 5, minLevelSuggestion = 17, maxLevelSuggestion = 24, categoryID = 2 },
    [3] = { fullName = "Scarlet Monastery: Library", shortName = "SM Lib", maxNumPlayers = 5, minLevelSuggestion = 33, maxLevelSuggestion = 39, categoryID = 2 },
    [4] = { fullName = "Shadowfang Keep", shortName = "SFK", maxNumPlayers = 5, minLevelSuggestion = 22, maxLevelSuggestion = 30, categoryID = 2 },
    [5] = { fullName = "Gnomeregan", shortName = "Gnomer", maxNumPlayers = 5, minLevelSuggestion = 29, maxLevelSuggestion = 38, categoryID = 2 },
    [9] = { fullName = "Questing", shortName = "Quest", maxNumPlayers = 5, minLevelSuggestion = 0, maxLevelSuggestion = 0, categoryID = 1 },
}
LFG.ACTIVITIES = ACTIVITIES

function LFG.new(world)
    return setmetatable({ world = world, listings = {}, nextID = 100, searches = {}, perClient = {} }, LFG)
end

-- adiciona uma listagem e devolve o id do resultado
function LFG:add(l)
    self.nextID = self.nextID + 1
    l.id = self.nextID
    l.members = l.members or { { name = l.leader, level = l.level or 30, class = l.class or "WARRIOR" } }
    l.activityIDs = l.activityIDs or { 1 }
    l.age = l.age or 60
    table.insert(self.listings, l)
    return l.id
end
function LFG:clear() self.listings = {} end
function LFG:get(id) for _, l in ipairs(self.listings) do if l.id == id then return l end end end

-- muda uma listagem e avisa quem já tem o resultado (LFG_LIST_SEARCH_RESULT_UPDATED)
function LFG:update(id, changes)
    local l = self:get(id)
    for k, v in pairs(changes) do l[k] = v end
    for _, c in ipairs(self.world.clients) do
        local mine = self.perClient[c]
        if c.state == "online" and mine and mine.has[id] then c:fireEvent("LFG_LIST_SEARCH_RESULT_UPDATED", id) end
    end
end

function LFG:activitiesFor(category)
    local out = {}
    for id, a in pairs(ACTIVITIES) do if a.categoryID == category then out[#out + 1] = id end end
    table.sort(out)
    return out
end

local function maybeSecret(l, field, v)
    if l.secret and l.secret[field] then return Client.secret() end
    return v
end

function LFG:api(c)
    local lfg = self
    local world = self.world
    local api = {}
    local function mine()
        local m = lfg.perClient[c]
        if not m then m = { ids = {}, has = {} }; lfg.perClient[c] = m end
        return m
    end
    function api.Search(category, filter, preferred, languages, crossFaction, advanced, activities)
        if c.chatLockdown and world.config.lfgBlockedInLockdown then error("C_LFGList.Search blocked", 2) end
        local now = world.now
        local recent = {}
        for _, t in ipairs(lfg.searches[c] or {}) do if now - t < world.config.lfgThrottle.window then recent[#recent + 1] = t end end
        recent[#recent + 1] = now
        lfg.searches[c] = recent
        local throttled = #recent >= world.config.lfgThrottle.count
        c.lastSearch = { category = category, activities = activities, at = now }
        if lfg.noAnswer then return end
        world:after(world.config.lfgLatency, function()
            if c.state ~= "online" then return end
            if c.env.LFGBrowseFrame then world:blizzardWrite(c.env.LFGBrowseFrame, "searching", false) end
            if throttled then c:fireEvent("LFG_LIST_SEARCH_FAILED", "throttled") return end
            local m = mine()
            m.ids, m.has = {}, {}
            for _, l in ipairs(lfg.listings) do
                local ok = true
                if activities and #activities > 0 then
                    ok = false
                    for _, a in ipairs(activities) do for _, b in ipairs(l.activityIDs) do if a == b then ok = true end end end
                end
                if ok then table.insert(m.ids, l.secretID and Client.secret() or l.id); m.has[l.id] = true end
            end
            c:fireEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
        end)
    end
    function api.GetFilteredSearchResults()
        local m = mine()
        local out = {}
        for i, id in ipairs(m.ids) do out[i] = id end
        return #out, out
    end
    api.GetSearchResults = api.GetFilteredSearchResults
    function api.GetSearchResultInfo(id)
        local l = lfg:get(id)
        if not l then return nil end
        if l.secretInfo then return Client.secret() end
        local acts = {}
        for i, a in ipairs(l.activityIDs) do acts[i] = a end
        return {
            searchResultID = id,
            activityIDs = maybeSecret(l, "activityIDs", acts),
            leaderName = maybeSecret(l, "leaderName", (not l.pendingName) and (l.leaderFull or l.leader) or nil),
            numMembers = maybeSecret(l, "numMembers", #l.members),
            isDelisted = maybeSecret(l, "isDelisted", l.delisted == true),
            age = maybeSecret(l, "age", l.age),
            hasSelf = maybeSecret(l, "hasSelf", l.hasSelf == true),
            name = "", comment = l.comment or "", voiceChat = "",
            requiredItemLevel = 0, isWarMode = false, autoAccept = false, newPlayerFriendly = false,
        }
    end
    local function player(l, m, isLeader)
        if not m then return nil end
        if m.secret then return Client.secret() end
        local roles = m.roles or { tank = m.role == "TANK", healer = m.role == "HEALER", dps = (m.role or "DAMAGER") == "DAMAGER" }
        return {
            name = m.name, level = maybeSecret(l, "level", m.level), classFilename = m.class,
            className = Client.CLASS_NAMES[m.class] or m.class,
            specName = m.spec or Client.CLASS_NAMES[m.class], assignedRole = m.role or "DAMAGER",
            lfgRoles = { tank = roles.tank == true, healer = roles.healer == true, dps = roles.dps == true },
            areaName = (isLeader or #l.members == 1) and (m.zone or "Elwynn Forest") or nil,
            isLeader = isLeader,
        }
    end
    function api.GetSearchResultPlayerInfo(id, i)
        local l = lfg:get(id)
        if not l then return nil end
        if l.memberError and l.memberError == i then error("member info failed") end
        return player(l, l.members[i], i == 1)
    end
    function api.GetSearchResultLeaderInfo(id)
        local l = lfg:get(id)
        return l and player(l, l.members[1], true)
    end
    function api.GetSearchResultMemberCounts(id)
        local l = lfg:get(id)
        if not l then return nil end
        local t = { TANK = 0, HEALER = 0, DAMAGER = 0, NOROLE = 0 }
        for _, m in ipairs(l.members) do local r = m.role or "DAMAGER"; t[r] = (t[r] or 0) + 1 end
        if l.remaining then
            t.TANK_REMAINING, t.HEALER_REMAINING, t.DAMAGER_REMAINING = l.remaining.tank, l.remaining.healer, l.remaining.dps
        end
        return t
    end
    function api.GetActivityInfoTable(id)
        local a = ACTIVITIES[id]
        if not a then return nil end
        local o = {}
        for k, v in pairs(a) do o[k] = v end
        o.minLevel = 0
        return o
    end
    function api.GetAvailableLanguageSearchFilter() return { "enUS", "ptBR" } end
    function api.GetDefaultLanguageSearchFilter() return { enUS = true } end
    function api.GetLanguageSearchFilter() return { enUS = true } end
    return api
end

return LFG
