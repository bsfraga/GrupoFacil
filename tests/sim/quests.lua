-- Missões, rastreador de objetivos, quest log, grupo e listagem própria do cliente simulado.
-- Modela o que a lupa do GrupoFacil usa:
--  * C_QuestLog com cabeçalhos por zona (como o log do jogo agrupa), elite, tamanho sugerido, concluída.
--  * QuestObjectiveTracker com usedBlocks[template][questID] e Update(); blocos de missão elite
--    ganham o botão nativo de procurar grupo à direita (rightEdgeFrame).
--  * QuestMapFrame.DetailsFrame (com BackFrame) e QuestMapFrame_ShowQuestDetails; QuestLogPopupDetailFrame.
--  * Grupo: convite -> AcceptGroup junta os dois (líder e membro), LeaveParty sai; GROUP_* disparam.
--  * Listagem própria: CreateListing/RemoveListing/HasActiveEntryInfo; o jogo pode recusar o questID.
-- Os quadros da Blizzard ficam atrás do proxy de escrita: o addon não pode gravar campo neles.
local Q = {}

local TRACKER_TEMPLATE = "QuestObjectiveTrackerBlockTemplate"

function Q.install(c, env)
    local world = c.world
    local ui = c.ui
    c.data.quests = c.data.quests or {}
    c.data.groupSize = c.data.groupSize or 0

    -- log: cabeçalho por zona, missões na ordem em que entraram
    local function entries()
        local out, zones, byZone = {}, {}, {}
        for _, q in ipairs(c.data.quests) do
            local z = q.zone or "Elwynn Forest"
            if not byZone[z] then byZone[z] = {}; zones[#zones + 1] = z end
            table.insert(byZone[z], q)
        end
        for _, z in ipairs(zones) do
            out[#out + 1] = { title = z, isHeader = true }
            for _, q in ipairs(byZone[z]) do out[#out + 1] = { quest = q } end
        end
        return out
    end
    local function find(id)
        for _, q in ipairs(c.data.quests) do if q.id == id then return q end end
    end
    local function indexOf(id)
        for i, e in ipairs(entries()) do if e.quest and e.quest.id == id then return i end end
    end
    env.C_QuestLog = {
        GetNumQuestLogEntries = function() local n = #entries(); return n, #c.data.quests end,
        GetInfo = function(i)
            local e = entries()[i]
            if not e then return nil end
            if e.isHeader then return { title = e.title, isHeader = true, questID = 0, level = 0 } end
            local q = e.quest
            return { title = q.title, isHeader = false, questID = q.id, level = q.level or 20, difficultyLevel = q.level or 20,
                suggestedGroup = q.size or 0, isOnMap = true, hasLocalPOI = false, frequency = 0 }
        end,
        GetLogIndexForQuestID = function(id) return indexOf(id) end,
        GetQuestIDForLogIndex = function(i) local e = entries()[i]; return e and e.quest and e.quest.id or 0 end,
        GetHeaderIndexForQuest = function(id)
            local idx = indexOf(id)
            if not idx then return nil end
            local list = entries()
            for i = idx, 1, -1 do if list[i].isHeader then return i end end
        end,
        GetTitleForQuestID = function(id) local q = find(id); return q and q.title or nil end,
        IsEliteQuest = function(id) local q = find(id); return q and q.elite == true or false end,
        GetSuggestedGroupSize = function(id) local q = find(id); return q and q.size or 0 end,
        IsComplete = function(id) local q = find(id); return q and q.complete == true or false end,
        ReadyForTurnIn = function(id) local q = find(id); return q and q.complete == true or false end,
        IsOnQuest = function(id) return find(id) ~= nil end,
        GetQuestObjectives = function(id)
            local q = find(id)
            if not q then return {} end
            local out = {}
            for _, o in ipairs(q.objectives or {}) do
                out[#out + 1] = { text = o.text, finished = o.finished == true, type = "monster" }
            end
            return out
        end,
    }
    env.GetQuestUiMapID = function(id) local q = find(id); return q and q.mapID or 0 end

    -- rastreador de objetivos
    if world.config.tracker ~= false then
        local tracker = ui.CreateFrame("Frame", "QuestObjectiveTracker", ui.UIParent)
        tracker:SetSize(260, 500)
        tracker:SetPoint("TOPRIGHT", ui.UIParent, "TOPRIGHT", -60, -260)
        local pool = {}
        tracker.usedBlocks = {}
        tracker.Update = function(self)
            local used = {}
            local y = 0
            for _, q in ipairs(c.data.quests) do
                if q.tracked ~= false then
                    local b = pool[q.id]
                    if not b then
                        b = ui.CreateFrame("Frame", nil, tracker)
                        b:SetSize(240, 40)
                        b.HeaderText = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
                        b.HeaderText:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
                        b.HeaderText:SetPoint("RIGHT", b, "RIGHT", 0, 0)
                        b.findGroup = ui.CreateFrame("Button", nil, b)
                        b.findGroup:SetSize(20, 20)
                        world:watchWrites(c, b, "QuestObjectiveTracker.block")
                        pool[q.id] = b
                    end
                    world:blizzardWrite(b, "id", q.id)
                    b.HeaderText:SetText(q.title)
                    b:ClearAllPoints()
                    b:SetPoint("TOPLEFT", tracker, "TOPLEFT", 0, -y)
                    y = y + 44
                    if q.elite then
                        b.findGroup:ClearAllPoints()
                        b.findGroup:SetPoint("TOPRIGHT", b, "TOPRIGHT", 0, 0)
                        b.findGroup:Show()
                        world:blizzardWrite(b, "rightEdgeFrame", b.findGroup)
                    else
                        b.findGroup:Hide()
                        world:blizzardWrite(b, "rightEdgeFrame", nil)
                    end
                    b:Show()
                    used[q.id] = b
                end
            end
            for id, b in pairs(pool) do if not used[id] then b:Hide() end end
            world:blizzardWrite(self, "usedBlocks", { [TRACKER_TEMPLATE] = used })
        end
        world:watchWrites(c, tracker, "QuestObjectiveTracker")
    end

    -- quest log (mapa) e janela solta de detalhes
    local qmf = ui.CreateFrame("Frame", "QuestMapFrame", ui.UIParent)
    qmf:SetSize(330, 500)
    qmf:SetPoint("TOPLEFT", ui.UIParent, "TOPLEFT", 400, -100)
    qmf:Hide()
    local df = ui.CreateFrame("Frame", nil, qmf)
    df:SetAllPoints(qmf)
    df:Hide()
    local back = ui.CreateFrame("Frame", nil, df)
    back:SetPoint("TOPLEFT", df, "TOPLEFT", 0, 0)
    back:SetPoint("TOPRIGHT", df, "TOPRIGHT", 0, 0)
    back:SetHeight(30)
    back.BackButton = ui.CreateFrame("Button", nil, back)
    back.BackButton:SetSize(60, 22)
    back.BackButton:SetPoint("LEFT", back, "LEFT", 11, 0)
    df.BackFrame = back
    qmf.DetailsFrame = df
    world:watchWrites(c, qmf, "QuestMapFrame")
    world:watchWrites(c, df, "QuestMapFrame.DetailsFrame")
    env.QuestMapFrame_ShowQuestDetails = function(questID)
        world:blizzardWrite(df, "questID", questID)
        qmf:Show()
        df:Show()
    end
    env.QuestMapFrame_CloseQuestDetails = function()
        world:blizzardWrite(df, "questID", nil)
        df:Hide()
    end
    local popup = ui.CreateFrame("Frame", "QuestLogPopupDetailFrame", ui.UIParent)
    popup:SetSize(340, 480)
    popup:SetPoint("CENTER", ui.UIParent, "CENTER", -300, 0)
    popup:Hide()
    world:watchWrites(c, popup, "QuestLogPopupDetailFrame")
    env.QuestLogPopupDetailFrame_Show = function(index)
        local e = env.C_QuestLog.GetInfo(index)
        world:blizzardWrite(popup, "questID", e and e.questID or nil)
        popup:Show()
    end

    -- grupo
    env.GetNumGroupMembers = function()
        if not c.data.inGroup then return 0 end
        return math.max(2, c.data.groupSize or 0)
    end
    local function join(leader)
        local function into(x, isLeader)
            local was = x.data.inGroup
            x.data.inGroup = true
            if isLeader and not was then x.data.leader = true end
            x.data.groupSize = math.max(2, (x.data.groupSize or 0) + (was and 1 or 2))
            if x.state == "online" then
                x:fireEvent("GROUP_ROSTER_UPDATE")
                if not was then x:fireEvent("GROUP_JOINED") end
            end
        end
        into(leader, true)
        into(c, false)
        c.data.groupLeader = leader
        world.groupJoins = (world.groupJoins or 0) + 1
    end
    env.AcceptGroup = function()
        local from = c.data.pendingInvite
        if not from then return end
        c.data.pendingInvite = nil
        c.data.invitePopup = nil
        c.data.accepted = (c.data.accepted or 0) + 1
        world:after(world.config.latency, function() join(from) end)
    end
    env.DeclineGroup = function() c.data.pendingInvite = nil; c.data.invitePopup = nil end
    env.StaticPopup_Hide = function(which) if which == "PARTY_INVITE" then c.data.invitePopup = nil end end
    env.LeaveParty = function()
        if not c.data.inGroup then return end
        c.data.inGroup, c.data.leader, c.data.groupSize = false, false, 0
        c.data.left = (c.data.left or 0) + 1
        if world.lfg.active[c] then world.lfg:removeActive(c) end
        c:fireEvent("GROUP_LEFT")
        c:fireEvent("GROUP_ROSTER_UPDATE")
    end
    env.C_PartyInfo.LeaveParty = env.LeaveParty
end

------------------------------------------------------------------------
-- ações dos testes
------------------------------------------------------------------------
local Client = require("sim.client")

-- q = { id, title, zone, level, elite, size, mapID, complete, tracked, objectives = { {text, finished} } }
function Client:addQuest(q)
    table.insert(self.data.quests, q)
    if self.state == "online" then
        self:fireEvent("QUEST_ACCEPTED", q.id)
        self:fireEvent("QUEST_LOG_UPDATE")
        self:updateTracker()
    end
    return q
end

function Client:completeQuest(id)
    for _, q in ipairs(self.data.quests) do if q.id == id then q.complete = true end end
    self:fireEvent("QUEST_LOG_UPDATE")
    self:updateTracker()
end

function Client:turnInQuest(id)
    for i, q in ipairs(self.data.quests) do
        if q.id == id then table.remove(self.data.quests, i) break end
    end
    self:fireEvent("QUEST_TURNED_IN", id, 0, 0)
    self:fireEvent("QUEST_REMOVED", id)
    self:fireEvent("QUEST_LOG_UPDATE")
    self:updateTracker()
end

-- o jogo redesenha a lista de objetivos (código da Blizzard)
function Client:updateTracker()
    local t = self.env and self.env.QuestObjectiveTracker
    if t and t.Update then self:protect(t.Update, t) end
end

function Client:openQuestDetails(id)
    self.env.QuestMapFrame_ShowQuestDetails(id)
end

function Client:openQuestPopup(id)
    self.env.QuestLogPopupDetailFrame_Show(self.env.C_QuestLog.GetLogIndexForQuestID(id))
end

-- botão da lupa (do addon) num bloco da lista de objetivos
function Client:trackerMagnifier(questID)
    local t = self.env.QuestObjectiveTracker
    local blocks = t and t.usedBlocks and t.usedBlocks[TRACKER_TEMPLATE]
    local b = blocks and blocks[questID]
    if not b then return nil end
    for _, ch in ipairs(self.ui.state(b).children) do
        if ch ~= b.findGroup then return ch, b end
    end
    return nil, b
end

return Q
