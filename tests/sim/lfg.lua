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
    -- "Missões e Zonas" (categoria 116 no Forever): uma atividade por zona
    [20] = { fullName = "Westfall", shortName = "Westfall", maxNumPlayers = 5, minLevelSuggestion = 10, maxLevelSuggestion = 20, categoryID = 116, mapID = 1436 },
    [21] = { fullName = "Elwynn Forest", shortName = "Elwynn", maxNumPlayers = 5, minLevelSuggestion = 1, maxLevelSuggestion = 10, categoryID = 116, mapID = 1429 },
    [22] = { fullName = "Redridge Mountains", shortName = "Redridge", maxNumPlayers = 5, minLevelSuggestion = 15, maxLevelSuggestion = 25, categoryID = 116, mapID = 1433 },
}
LFG.ACTIVITIES = ACTIVITIES

function LFG.new(world)
    return setmetatable({ world = world, listings = {}, nextID = 100, searches = {}, perClient = {},
        active = setmetatable({}, { __mode = "k" }) }, LFG)
end

-- tira a listagem própria do cliente (RemoveListing, ou o líder saiu do grupo)
function LFG:removeActive(c)
    local l = self.active[c]
    if not l then return end
    self.active[c] = nil
    for i, x in ipairs(self.listings) do if x == l then table.remove(self.listings, i) break end end
    self.world:after(self.world.config.lfgLatency, function()
        if c.state == "online" then c:fireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE") end
    end)
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
    -- HasRestrictions: só de um clique, uma por clique (config.hardwareEvents liga a regra)
    local function protected(fn)
        if not world.config.hardwareEvents then return true end
        local hw = c.hw
        if hw and hw.left > 0 then hw.left = hw.left - 1 return true end
        c.blocked[#c.blocked + 1] = { fn = "C_LFGList." .. fn }
        c:fireEvent("ADDON_ACTION_BLOCKED", "GrupoFacil", "C_LFGList." .. fn .. "()")
        return false
    end
    api.protectedCalls = protected
    function api.Search(category, filter, preferred, languages, crossFaction, advanced, activities)
        if not protected("Search") then return end
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
            hasSelf = maybeSecret(l, "hasSelf", l.hasSelf == true or l.owner == c),
            questID = l.questID,
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
    function api.GetAvailableActivities(category)
        if category == nil then return nil end
        return lfg:activitiesFor(category)
    end
    function api.HasActiveEntryInfo() return lfg.active[c] ~= nil end
    function api.GetActiveEntryInfo()
        local l = lfg.active[c]
        if not l then return nil end
        return { activityIDs = { l.activityIDs[1] }, questID = l.questID, newPlayerFriendly = false, autoAccept = false }
    end
    function api.CreateListing(data)
        if not protected("CreateListing") then return false end
        if type(data) ~= "table" or type(data.activityIDs) ~= "table" or not ACTIVITIES[data.activityIDs[1]] then
            error("Usage: C_LFGList.CreateListing(createData)", 2)
        end
        if lfg.active[c] then return false end
        if c.data.inGroup and not c.data.leader then return false end
        c.data.createdListings = c.data.createdListings or {}
        table.insert(c.data.createdListings, data)
        -- Forever: sem estilo de jogo o jogo aceita a chamada e não cria nada, sem evento nenhum
        -- (o "Criar grupo não faz nada" do teste do Fraga, 26/11)
        if world.config.requirePlaystyle ~= false and data.generalPlaystyle == nil then return end
        if world.config.silentListing then return end
        if data.questID and world.config.rejectListingQuestID then
            world:after(world.config.lfgLatency, function()
                if c.state == "online" then c:fireEvent("LFG_LIST_ENTRY_CREATION_FAILED") end
            end)
            return true
        end
        local members = { { name = c.surname and c:fullName() or c.name, level = c.level, class = c.class, zone = c.zone } }
        for i = 2, (c.data.inGroup and math.max(2, c.data.groupSize or 2) or 1) do
            members[#members + 1] = { name = "Membro" .. i, level = c.level, class = "MAGE", role = "DAMAGER" }
        end
        local l = { leader = members[1].name, members = members, activityIDs = { data.activityIDs[1] },
            questID = data.questID, owner = c, age = 0 }
        lfg:add(l)
        lfg.active[c] = l
        world:after(world.config.lfgLatency, function()
            if c.state == "online" then c:fireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", true) end
        end)
        return true
    end
    function api.RemoveListing()
        if not protected("RemoveListing") then return end
        lfg:removeActive(c)
    end
    function api.GetAvailableLanguageSearchFilter() return { "enUS", "ptBR" } end
    function api.GetDefaultLanguageSearchFilter() return { enUS = true } end
    function api.GetLanguageSearchFilter() return { enUS = true } end
    return api
end

return LFG
