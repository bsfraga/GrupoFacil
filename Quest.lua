-- GrupoFacil: grupos por missão.
-- A lupa ao lado da missão (QuestUI.lua) busca, na categoria "Missões e Zonas" do Looking For Group,
-- os grupos da zona da missão. Quem também usa o GrupoFacil responde em silêncio (sussurro de addon,
-- SendAddonMessage com WHISPER) quais missões o grupo faz; esses grupos sobem para o topo.
-- Sem grupo para a missão, o jogador cria a listagem nativa com um clique.
--
-- Regras (pesquisa de 26/11/2026, ver o README):
--  * Busca, criação e remoção da listagem só saem de um clique, e uma por clique (o Forever deixa
--    uma ação protegida por evento de hardware).
--  * Nunca usa canal de chat: os reinos ao vivo recusam addon em canal e já desativaram canal de
--    conta. Só sussurro de addon, que funciona entre estranhos.
--  * Convite automático do líder: desligado por padrão, só para quem pediu pela mesma missão, no
--    máximo INVITE_CAP convites a cada INVITE_WINDOW segundos.
--  * Aceite automático: só o convite do líder a quem você pediu vaga, por ACCEPT_FOR segundos.
--  * Com o bloqueio de chat do jogo ativo (instâncias, encontros), nada é enviado.

local ADDON, NS = ...
local L = NS.L
local D = NS.D
local Trace = D.Trace
local format, lower, gsub = string.format, string.lower, string.gsub
local GetTime, time, type, tostring, tonumber, pairs, ipairs = GetTime, time, type, tostring, tonumber, pairs, ipairs

local Q = {}
NS.Quest = Q

Q.PREFIX = "GFQ"
Q.CATEGORY = 116           -- "Quests & Zones" no Forever (LFGVanilla_Constants, ramo forever)
Q.DUNGEON_CATEGORY = 2
Q.PROTO = "1"

local QUERY_TTL = 120      -- s que a resposta de um líder vale
local QUERY_MAX = 20       -- líderes perguntados por busca
local BURST, REGEN = 8, 1  -- envio: 8 de uma vez, depois 1 por segundo (o jogo dá 10 por prefixo)
local INVITE_CAP, INVITE_WINDOW = 6, 600
local REINVITE_WAIT = 60
local ACCEPT_FOR = 120
local JOIN_WINDOW, JOIN_WARN = 3600, 12 -- o jogo recusa a 17ª entrada em grupo numa hora (LayerSwap, 25/11/2026)
local MAX_LOG_IDS = 30
local REQUEST_TTL = 300
local CREATE_WAIT = 4      -- s para o jogo responder à criação da listagem
local PLAYSTYLE_FUN_RELAXED = 2 -- Enum.LFGEntryGeneralPlaystyle.FunRelaxed, se o Enum não existir

local function isSecret(v) return NS.isSecret(v) end
local function num(v) if type(v) == "number" and not isSecret(v) then return v end end
local function str(v) if type(v) == "string" and not isSecret(v) and v ~= "" then return v end end

-- nome normalizado (minúsculas, sem reino); o Forever manda "Nome Sobrenome"
local function key(name) return NS.normName(name) end
-- nome para mostrar (sem o reino que o simulador e alguns clientes põem)
local function display(name)
    if type(name) ~= "string" then return tostring(name) end
    local fn = rawget(_G, "Ambiguate")
    if fn then local ok, v = pcall(fn, name, "none"); if ok and type(v) == "string" then return v end end
    return name
end
Q.Display = display

local function firstName(k) return k and (k:match("^(%S+)") or k) end

-- Os dois nomes são a mesma pessoa? Com e sem sobrenome conta (um lado pode vir só com o nome).
local function sameName(a, b)
    if not a or not b then return false end
    if a == b then return true end
    local fa, fb = firstName(a), firstName(b)
    if fa ~= fb then return false end
    return (a == fa) or (b == fb)
end
Q.SameName = sameName

function Q.DB()
    local db = GrupoFacilDB
    db.quest = db.quest or {}
    local q = db.quest
    if q.autoInvite == nil then q.autoInvite = false end
    if q.autoAccept == nil then q.autoAccept = true end
    if q.magnifier == nil then q.magnifier = true end
    return q
end

------------------------------------------------------------------------
-- a missão: título, zona, elite, tamanho de grupo sugerido
------------------------------------------------------------------------
local function questLog() return C_QuestLog end

local function call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b = pcall(fn, ...)
    if not ok then return nil end
    return a, b
end

-- cabeçalho (zona) da missão no log: o próprio jogo agrupa as missões por zona
local function headerFor(ql, questID, index)
    local h = call(ql.GetHeaderIndexForQuest, questID)
    if num(h) then
        local info = call(ql.GetInfo, h)
        if type(info) == "table" and not isSecret(info) and info.isHeader and str(info.title) then return info.title end
    end
    if not num(index) then return nil end
    for i = index - 1, 1, -1 do
        local info = call(ql.GetInfo, i)
        if type(info) == "table" and not isSecret(info) and info.isHeader then return str(info.title) end
    end
    return nil
end

function Q.Info(questID)
    local ql = questLog()
    questID = num(questID)
    if not (ql and questID and questID > 0) then return nil end
    local q = { id = questID }
    q.title = str(call(ql.GetTitleForQuestID, questID))
    local index = num(call(ql.GetLogIndexForQuestID, questID))
    q.inLog = index ~= nil
    if index then
        local info = call(ql.GetInfo, index)
        if type(info) == "table" and not isSecret(info) then
            q.title = q.title or str(info.title)
            q.level = num(info.level) or num(info.difficultyLevel)
            q.suggested = num(info.suggestedGroup)
        end
    end
    q.zone = headerFor(ql, questID, index)
    q.elite = call(ql.IsEliteQuest, questID) == true
    q.size = num(call(ql.GetSuggestedGroupSize, questID)) or q.suggested
    if q.size and q.size <= 1 then q.size = nil end
    q.complete = call(ql.IsComplete, questID) == true or call(ql.ReadyForTurnIn, questID) == true
    if not q.title then q.title = format(L["Quest %d"], questID) end
    return q
end

-- IDs das missões do log (sem cabeçalhos e sem as já concluídas), para responder aos outros
function Q.LogQuestIDs(limit)
    local ql = questLog()
    local out = {}
    if not ql then return out end
    local n = num(call(ql.GetNumQuestLogEntries)) or 0
    for i = 1, math.min(n, 60) do
        local info = call(ql.GetInfo, i)
        if type(info) == "table" and not isSecret(info) and not info.isHeader then
            local id = num(info.questID) or num(call(ql.GetQuestIDForLogIndex, i))
            if id and id > 0 and not (call(ql.IsComplete, id) == true) then
                out[#out + 1] = id
                if #out >= (limit or MAX_LOG_IDS) then break end
            end
        end
    end
    return out
end

function Q.OnQuest(questID)
    local ql = questLog()
    if not (ql and num(questID)) then return false end
    if call(ql.IsOnQuest, questID) == true then return true end
    return num(call(ql.GetLogIndexForQuestID, questID)) ~= nil
end

------------------------------------------------------------------------
-- atividade do Looking For Group para a zona da missão
------------------------------------------------------------------------
local actCache = {}  -- [categoria] = { {id, name, mapID}, ... }

local function norm(s)
    if type(s) ~= "string" or isSecret(s) then return nil end
    s = lower(s):gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function activities(category)
    if actCache[category] then return actCache[category] end
    local ids
    if C_LFGList and C_LFGList.GetAvailableActivities then ids = call(C_LFGList.GetAvailableActivities, category) end
    if type(ids) ~= "table" and LFGUtil_GetFilteredActivities then ids = call(LFGUtil_GetFilteredActivities, category) end
    local list = {}
    if type(ids) == "table" and not isSecret(ids) then
        for _, a in ipairs(ids) do
            if num(a) then
                local info = call(C_LFGList.GetActivityInfoTable, a)
                if type(info) == "table" and not isSecret(info) then
                    list[#list + 1] = { id = a, name = norm(info.fullName or info.shortName), label = str(info.fullName or info.shortName), mapID = num(info.mapID),
                        min = num(info.minLevelSuggestion), max = num(info.maxLevelSuggestion), size = num(info.maxNumPlayers) }
                end
            end
        end
    end
    if #list > 0 then actCache[category] = list end
    return list
end
Q.Activities = activities
function Q.ResetActivityCache() actCache = {} end

-- "The Deadmines" (cabeçalho do log) e "Deadmines" (atividade) são o mesmo lugar
local function bare(s)
    s = norm(s)
    if not s then return nil end
    s = s:gsub("^the%s+", ""):gsub("[%p]", ""):gsub("%s+", " ")
    return s
end

local function findActivity(category, zone, mapID)
    local z, zb = norm(zone), bare(zone)
    local list = activities(category)
    for _, a in ipairs(list) do
        if (z and a.name == z) or (mapID and a.mapID == mapID) then return a end
    end
    if zb and zb ~= "" then
        for _, a in ipairs(list) do if bare(a.name) == zb then return a end end
    end
    return nil
end

local function questMapID(questID)
    local fn = rawget(_G, "GetQuestUiMapID")
    local m = fn and num(call(fn, questID))
    if m and m > 0 then return m end
    return nil
end

-- Devolve a atividade (ou nil para a categoria toda), a categoria e de onde veio a zona.
function Q.ActivityFor(q)
    if not q then return nil, Q.CATEGORY, nil end
    local mapID = questMapID(q.id)
    -- uma missão de masmorra pede o grupo da masmorra (busca e criação vão para Masmorras, pedido do
    -- Fraga, 26/11): pelo cabeçalho do log ou, se o jogo der, pelo mapa da missão
    local a = findActivity(Q.DUNGEON_CATEGORY, q.zone, nil) or (mapID and findActivity(Q.DUNGEON_CATEGORY, nil, mapID))
    if a then return a, Q.DUNGEON_CATEGORY, "dungeon" end
    a = findActivity(Q.CATEGORY, q.zone, mapID)
    if a then return a, Q.CATEGORY, "quest" end
    -- missão de outra zona no log (cabeçalho diferente): a zona onde você está
    local here = str(call(rawget(_G, "GetRealZoneText"))) or str(call(rawget(_G, "GetZoneText")))
    local hereMap = C_Map and C_Map.GetBestMapForUnit and num(call(C_Map.GetBestMapForUnit, "player"))
    a = findActivity(Q.CATEGORY, here, hereMap)
    if a then return a, Q.CATEGORY, "here" end
    return nil, Q.CATEGORY, nil
end

------------------------------------------------------------------------
-- estado
------------------------------------------------------------------------
Q.current = nil     -- { questID, info, activity, category, at }
Q.peers = {}        -- [key] = { listed = questID|nil, has = {[questID]=true}, at, gf = true }
Q.asked = {}        -- [key] = { at, questID, name } pedidos de vaga feitos por você
Q.requests = {}     -- pedidos recebidos (você é o líder): { key, name, questID, level, class, roles, at }
Q.invitedAt = {}    -- [key] = GetTime() do último convite automático
Q.inviteTimes = {}  -- horários dos convites automáticos (limite)
Q.myQuest = nil     -- missão do seu grupo (criou a listagem ou entrou por ela)
Q.answers = {}      -- [key] = { code, at } resposta do líder ao seu pedido
Q.prompted = {}     -- [questID] = true: já ofereceu sair/tirar a listagem
Q.queue = {}
Q.tokens = BURST
Q.tokensAt = 0

local function refresh(reason)
    if NS.RefreshQuest then NS.RefreshQuest(reason) end
end

------------------------------------------------------------------------
-- sussurro de addon (fila com limite próprio)
------------------------------------------------------------------------
local function regen()
    local now = GetTime()
    Q.tokens = math.min(BURST, Q.tokens + (now - Q.tokensAt) * REGEN)
    Q.tokensAt = now
end

local function rawSend(msg, target)
    if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
    local ok, res = pcall(C_ChatInfo.SendAddonMessage, Q.PREFIX, msg, "WHISPER", target)
    if not ok then Trace("MISSAO", "envio falhou: %s", tostring(res)) return false end
    if res ~= nil and not isSecret(res) and type(res) == "number" and res ~= 0 then
        Trace("MISSAO", "envio recusado pelo jogo: %s", tostring(res))
        return res == 3 and "throttle" or false
    end
    return true
end

local pumping = false
local function pump()
    if pumping then return end
    pumping = true
    local function step()
        regen()
        while #Q.queue > 0 and Q.tokens >= 1 do
            if NS.InLockdown() then break end
            local item = table.remove(Q.queue, 1)
            local r = rawSend(item.msg, item.to)
            if r == "throttle" then table.insert(Q.queue, 1, item); Q.tokens = 0; break end
            Q.tokens = Q.tokens - 1
        end
        if #Q.queue > 0 then
            C_Timer.After(1, step)
        else
            pumping = false
        end
    end
    step()
end

function Q.Send(msg, target)
    if type(target) ~= "string" or isSecret(target) or target == "" then return false end
    if NS.InLockdown() then Trace("MISSAO", "não enviado: restrição de chat") return false end
    if #msg > 250 then msg = msg:sub(1, 250) end
    Q.queue[#Q.queue + 1] = { msg = msg, to = target }
    pump()
    return true
end

------------------------------------------------------------------------
-- busca (só de um clique)
------------------------------------------------------------------------
-- Chamar SOMENTE de dentro de um OnClick: é a única ação protegida desse clique.
function Q.Search(questID)
    local info = Q.Info(questID)
    if not info then return false, L["this quest is not in your quest log"] end
    local act, category, from = Q.ActivityFor(info)
    Q.current = { questID = info.id, info = info, activity = act, category = category, from = from, at = GetTime() }
    refresh("quest")
    if GetTime() < NS.searchReadyAt then
        return false, format(L["wait %d s (the game limits back-to-back searches)"], math.ceil(NS.searchReadyAt - GetTime()))
    end
    if NS.InLockdown() then return false, L["the game's chat restriction is active"] end
    Trace("MISSAO", "busca: missão=%d categoria=%d atividade=%s zona=%s (%s)", info.id, category,
        tostring(act and act.id), tostring(info.zone), tostring(from))
    NS.addonSearching = true
    local ok = NS.GuardTag("C_LFGList.Search(quest)", C_LFGList.Search, category, 0, 0, nil, false, nil, act and { act.id } or nil)
    NS.addonSearching = false
    if not ok then return false, L["the search failed (see /gf diag)"] end
    if not NS.searching then NS.MarkSearching() end
    Q.searchedAt = GetTime()
    Q.queried = false
    return true
end

-- Mesma missão de antes, outra busca (botão "Buscar de novo" da janela de missões).
function Q.SearchAgain()
    if not Q.current then return false, L["click the magnifier next to a quest first"] end
    return Q.Search(Q.current.questID)
end

------------------------------------------------------------------------
-- resultados para a missão atual
------------------------------------------------------------------------
local function inActivity(e, act)
    if not act then return true end
    for _, a in ipairs(e.activityIDs or {}) do if a == act.id then return true end end
    return false
end

-- quão bem o grupo serve para a missão: 3 = faz a missão, 2 = tem a missão, 1 = mesma zona
function Q.Match(e, questID)
    if not e then return 0, nil end
    if e.questID and e.questID == questID then return 3, "listed" end
    local p = e.key and Q.peers[e.key]
    if p and p.listed == questID then return 3, "gf" end
    if p and p.has and p.has[questID] then return 2, "has" end
    return 1, nil
end

function Q.Results()
    local cur = Q.current
    local out = {}
    if not cur then return out end
    for _, id in ipairs(NS.order) do
        local e = NS.entries[id]
        if e and not e.delisted and not NS.IsHiddenByPlayer(e) and inActivity(e, cur.activity) then
            local score, why = Q.Match(e, cur.questID)
            e.qScore, e.qWhy = score, why
            e.qPeer = e.key and Q.peers[e.key] or nil
            out[#out + 1] = e
        end
    end
    table.sort(out, function(a, b)
        if a.qScore ~= b.qScore then return a.qScore > b.qScore end
        if a.solo ~= b.solo then return not a.solo end -- grupos antes de jogadores sozinhos
        if (a.relation ~= nil) ~= (b.relation ~= nil) then return a.relation ~= nil end
        if (a.age or 1e9) ~= (b.age or 1e9) then return (a.age or 1e9) < (b.age or 1e9) end
        return (a.id or 0) < (b.id or 0)
    end)
    return out
end

-- Pergunta em silêncio aos líderes dos resultados (quem tem o GrupoFacil responde).
function Q.QueryLeaders()
    local cur = Q.current
    if not cur or NS.InLockdown() then return 0 end
    local now = GetTime()
    local n = 0
    for _, e in ipairs(Q.Results()) do
        if n >= QUERY_MAX then break end
        local p = e.key and Q.peers[e.key]
        if e.name and e.key and not (p and now - p.at < QUERY_TTL) and not (e.qAskedAt and now - e.qAskedAt < QUERY_TTL) then
            e.qAskedAt = now
            Q.Send("?" .. Q.PROTO, e.name)
            n = n + 1
        end
    end
    Trace("MISSAO", "perguntou a %d líder(es)", n)
    return n
end

------------------------------------------------------------------------
-- entrar num grupo
------------------------------------------------------------------------
NS.QUEST_TEMPLATE = "Hi, I'm a level {level} {spec} {class}, also on {quest}. Can I join?"

function Q.BuildMessage(questTitle)
    local text = NS.QUEST_TEMPLATE
    local class = NS.PlayerClass() or ""
    local vars = { level = tostring(UnitLevel("player") or ""), spec = NS.PlayerSpec() or "", class = class,
        quest = questTitle and ("[" .. questTitle .. "]") or "" }
    text = gsub(text, "{(%a+)}", function(k) return vars[k] or ("{" .. k .. "}") end)
    text = gsub(text, "%s%s+", " ")
    -- divulga o addon para quem não usa (pedido do Fraga, 26/11; não vai nas Novidades)
    return text .. " (via GrupoFacil)"
end

local function rolesCode()
    local r = NS.MyRoles() or {}
    local s = (r.tank and "t" or "") .. (r.healer and "h" or "") .. (r.dps and "d" or "")
    return s ~= "" and s or "-"
end

function Q.CanJoin(e)
    if not e or not e.name or not e.key then return false, L["no leader data yet"] end
    if e.delisted then return false, L["Left the list"] end
    if IsInGroup() then return false, L["you are already in a group"] end
    if NS.InLockdown() then return false, L["the game's chat restriction is active"] end
    local a = Q.asked[e.key]
    if a and GetTime() - a.at < ACCEPT_FOR then return false, L["request already sent"] end
    if e.maxPlayers and (e.numMembers or 0) >= e.maxPlayers then return false, L["the group is full"] end
    return true
end

-- Clique em "Entrar": quem tem o GrupoFacil recebe o pedido em silêncio; os outros, um sussurro pronto.
function Q.Join(e)
    local cur = Q.current
    local ok, why = Q.CanJoin(e)
    if not ok then NS.Print(format(L["not sent: %s."], why)) return false end
    local questID = cur and cur.questID or 0
    local title = cur and cur.info and cur.info.title
    Q.asked[e.key] = { at = GetTime(), questID = questID, name = e.name }
    local p = Q.peers[e.key]
    if p and p.gf then
        local _, classFile = UnitClass("player")
        -- o título vai junto: o líder pode não ter a missão no log
        local t = (title or ""):gsub("[%c|]", "")
        Q.Send(format("J%s %d %d %s %s %s", Q.PROTO, questID, UnitLevel("player") or 0, classFile or "-", rolesCode(), t), e.name)
        Trace("MISSAO", "pedido de vaga por addon (missão %d)", questID)
        NS.Print(format(L["request sent to %s."], e.name))
    else
        NS.AskToJoin(e, Q.BuildMessage(title))
        Trace("MISSAO", "pedido de vaga por sussurro (líder sem GrupoFacil), missão %d", questID)
    end
    Q.myQuest = questID ~= 0 and questID or Q.myQuest
    refresh("join")
    return true
end

-- Convidar um jogador sozinho da lista (você está sozinho ou é o líder).
function Q.Invite(e)
    if not NS.CanInvite(e) then return false end
    NS.Invite(e)
    if Q.current then Q.myQuest = Q.current.questID end
    return true
end

------------------------------------------------------------------------
-- criar e tirar a listagem (só de um clique)
------------------------------------------------------------------------
function Q.HasListing()
    if not (C_LFGList and C_LFGList.HasActiveEntryInfo) then return false end
    local ok, v = pcall(C_LFGList.HasActiveEntryInfo)
    return ok and v == true
end

function Q.CanCreate()
    local cur = Q.current
    if not cur then return false, L["click the magnifier next to a quest first"] end
    if IsInGroup() and not UnitIsGroupLeader("player") then return false, L["only the group leader can list the group"] end
    if Q.HasListing() then return false, L["you already have a listing"] end
    if not cur.activity then return false, L["the Looking For Group has no entry for this quest's zone"] end
    if NS.InLockdown() then return false, L["the game's chat restriction is active"] end
    return true
end

-- Chamar SOMENTE de dentro de um OnClick.
function Q.Create()
    local ok, why = Q.CanCreate()
    if not ok then NS.Print(format(L["not listed: %s."], why)) return false end
    local cur = Q.current
    -- Exatamente os campos que o botão "Listar" do Looking For Group do Forever manda
    -- (Blizzard_LFGVanilla_Listing.lua, CreateOrUpdateListing): atividades, novato, estilo de jogo
    -- (obrigatório: "Select Playstyle (required)") e voz. O ID da missão (questID) ficou de fora: no
    -- teste do Fraga (26/11) toda chamada com ele foi aceita e nada foi listado. Quem usa o GrupoFacil
    -- acha a missão do grupo pelo sussurro de addon, não pela listagem.
    local styles = Enum and Enum.LFGEntryGeneralPlaystyle
    local voice = Enum and Enum.LFGEntryVoiceMode
    local data = {
        activityIDs = { cur.activity.id },
        newPlayerFriendly = false,
        generalPlaystyle = (styles and styles.FunRelaxed) or PLAYSTYLE_FUN_RELAXED,
    }
    if voice and voice.None then data.voiceMode = voice.None end
    local db = Q.DB()
    local dungeon = cur.category == Q.DUNGEON_CATEGORY
    if db.listWithQuestID and not dungeon then data.questID = cur.questID end -- só para teste
    local p = { questID = cur.questID, at = GetTime(), withQuest = data.questID ~= nil,
        dungeon = dungeon and (cur.activity.label or cur.activity.name) or nil, errors = {} }
    Q.pendingCreate = p
    local called, created = NS.GuardTag("C_LFGList.CreateListing", C_LFGList.CreateListing, data)
    local cat = C_LFGList.GetLfgCategoryInfo and select(2, pcall(C_LFGList.GetLfgCategoryInfo, cur.category))
    local auth = C_LFGList.IsPlayerAuthenticatedForLFG and select(2, pcall(C_LFGList.IsPlayerAuthenticatedForLFG, cur.category))
    Trace("MISSAO", "criar listagem: missão=%d categoria=%d atividade=%d comID=%s estilo=%s voz=%s chamada=%s resposta=%s autoEscolha=%s autenticado=%s",
        cur.questID, cur.category or 0, cur.activity.id, tostring(data.questID ~= nil), tostring(data.generalPlaystyle),
        tostring(data.voiceMode), tostring(called), tostring(created),
        tostring(type(cat) == "table" and cat.autoChooseActivity), tostring(auth))
    if not called or created == false then
        Q.pendingCreate = nil
        NS.Print(L["the game did not accept the listing. Send /gf diag to the author."])
        refresh("create-refused")
        return false
    end
    Q.myQuest = cur.questID
    -- Sem resposta do jogo (nem criada nem recusada) em CREATE_WAIT s: avisa em vez de ficar mudo e
    -- guarda no /gf diag as mensagens de erro do jogo que vieram nesse tempo.
    C_Timer.After(CREATE_WAIT, function()
        if Q.pendingCreate ~= p then return end
        Q.pendingCreate = nil
        if Q.HasListing() then return end
        if not IsInGroup() then Q.myQuest = nil end
        NS.Print(L["the game did not create the listing. Open Looking For Group to list by hand, and send /gf diag to the author."])
        Trace("MISSAO", "listagem sem resposta do jogo em %ds (com ID=%s) erros do jogo: %s", CREATE_WAIT, tostring(p.withQuest),
            #p.errors > 0 and table.concat(p.errors, " / ") or "nenhum")
        refresh("create-timeout")
    end)
    refresh("create")
    return true
end

-- Descrição da listagem: o addon NÃO consegue preencher. A caixa de descrição do Looking For Group
-- é uma referência segura da Blizzard (Blizzard_LFGVanilla_Listing.xml: StoreSecureReference,
-- SetSecurityDisableSetText e SetSecurityDisablePaste): addon não escreve nela, nem colar o jogo deixa.
-- O jogo a lê direto da caixa na hora de criar; CreateListing não tem campo de texto. Pesquisa de 26/11.
-- No lugar dela, o GrupoFacil mostra na aba Missões o nome, o objetivo e o local da missão, e passa
-- isso a quem também usa o addon pelo sussurro de addon (I1, ver o protocolo).

-- primeiro objetivo ainda não feito (ou o primeiro), em texto
function Q.Objective(questID)
    local ql = questLog()
    local list = ql and questID and call(ql.GetQuestObjectives, questID)
    if type(list) ~= "table" or isSecret(list) then return nil end
    for _, o in ipairs(list) do
        local t = type(o) == "table" and str(o.text)
        if t and not o.finished then return t end
    end
    local first = list[1]
    return type(first) == "table" and str(first.text) or nil
end

function Q.RemoveListing()
    if not Q.HasListing() then return false end
    local ok = NS.GuardTag("C_LFGList.RemoveListing", C_LFGList.RemoveListing)
    Trace("MISSAO", "tirar listagem: %s", tostring(ok))
    -- confere: se o jogo não tirou, avisa em vez de a janela mostrar uma coisa e o jogo outra
    C_Timer.After(2, function()
        if Q.HasListing() then
            NS.Print(L["the game did not take your group out of Looking For Group. Remove it there, and send /gf diag to the author."])
            Trace("MISSAO", "listagem continua 2 s depois de tirar")
        end
        Q.CheckListing("tirar+2")
        refresh("remove-check")
    end)
    refresh("remove")
    return ok
end

-- Estado da sua listagem: quando ela some (tirada pelo GrupoFacil, pelo Looking For Group do jogo ou
-- porque o grupo acabou), a missão do grupo e as informações dela são limpas (pedido do Fraga, 26/11):
-- a aba Missões volta para a lista das suas missões e ninguém mais recebe a missão como sua.
Q.wasListed = false
function Q.CheckListing(why)
    local has = Q.HasListing()
    if has then Q.wasListed = true return end
    if not Q.wasListed then return end
    Q.wasListed = false
    Trace("MISSAO", "listagem saiu (%s): limpa a missão do grupo", tostring(why))
    if not IsInGroup() or UnitIsGroupLeader("player") then Q.myQuest = nil end
    Q.current = nil
    Q.status = nil
    if NS.QuestPick then NS.QuestPick(true) end
    refresh("delisted")
end

-- todas as missões do log (para a lista da aba Missões), na ordem do log
function Q.LogQuests()
    local ql = questLog()
    local out = {}
    if not ql then return out end
    local n = num(call(ql.GetNumQuestLogEntries)) or 0
    for i = 1, math.min(n, 80) do
        local info = call(ql.GetInfo, i)
        if type(info) == "table" and not isSecret(info) and not info.isHeader then
            local id = num(info.questID) or num(call(ql.GetQuestIDForLogIndex, i))
            local q = id and id > 0 and Q.Info(id)
            if q then out[#out + 1] = q end
        end
    end
    return out
end

function Q.LeaveGroup()
    if not IsInGroup() then return false end
    local fn = (C_PartyInfo and C_PartyInfo.LeaveParty) or rawget(_G, "LeaveParty")
    local ok = fn and NS.GuardTag("LeaveParty", fn)
    Trace("MISSAO", "sair do grupo: %s", tostring(ok))
    Q.myQuest = nil
    refresh("leave")
    return ok
end

------------------------------------------------------------------------
-- protocolo: ?1 (que missões?), Q1 (resposta), I1 (missão do grupo listado: nome, objetivo, local),
-- J1 (pedido de vaga), R1 (resposta ao pedido)
------------------------------------------------------------------------
local function groupFull()
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    return IsInGroup() and n >= 5
end

local function canLead()
    return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function replyQuests(sender)
    local ids = Q.LogQuestIDs(MAX_LOG_IDS)
    local listed = (Q.myQuest and (Q.HasListing() or IsInGroup())) and Q.myQuest or 0
    Q.Send(format("Q%s %d %s", Q.PROTO, listed, table.concat(ids, ",")), sender)
    -- grupo listado para uma missão: nome, objetivo e local, no lugar da descrição que o jogo não deixa
    -- o addon escrever (I1 <id> <nome>~<objetivo>~<local>)
    if listed > 0 then
        local q = Q.Info(listed)
        if q and q.title then
            local function clean(v) return (tostring(v or ""):gsub("[~\r\n|]", " ")) end
            local zone = q.zone or ""
            local cur = Q.current
            if cur and cur.questID == listed and cur.activity and cur.activity.label then zone = cur.activity.label end
            local msg = format("I%s %d %s~%s~%s", Q.PROTO, listed, clean(q.title), clean(Q.Objective(listed)), clean(zone))
            if #msg > 250 then msg = msg:sub(1, 250) end
            Q.Send(msg, sender)
        end
    end
end

local function onInfo(sender, rest)
    local k = key(sender)
    if not k then return end
    local id, title, obj, zone = rest:match("^(%d+)%s+([^~]*)~([^~]*)~?(.*)$")
    id = tonumber(id)
    if not id then return end
    local function nz(v) v = v and v:gsub("^%s+", ""):gsub("%s+$", "") return v ~= "" and v or nil end
    local info = { questID = id, title = nz(title), objective = nz(obj), zone = nz(zone) }
    for pk, p in pairs(Q.peers) do
        if pk == k or sameName(pk, k) then p.info = info end
    end
    refresh("info")
end

local function onAnswer(sender, rest)
    local k = key(sender)
    if not k then return end
    local listed, list = rest:match("^(%d+)%s*(.*)$")
    local p = { gf = true, at = GetTime(), listed = tonumber(listed), has = {} }
    if p.listed == 0 then p.listed = nil end
    for id in (list or ""):gmatch("%d+") do p.has[tonumber(id)] = true end
    -- a entrada da lista pode ter o nome sem sobrenome (ou com): guarda nos dois jeitos que casam
    Q.peers[k] = p
    for _, e in pairs(NS.entries) do
        if e and e.key and e.key ~= k and sameName(e.key, k) then Q.peers[e.key] = p end
    end
    refresh("answer")
end

local function pruneInvites(now)
    for i = #Q.inviteTimes, 1, -1 do
        if now - Q.inviteTimes[i] > INVITE_WINDOW then table.remove(Q.inviteTimes, i) end
    end
end

function Q.InvitesLeft()
    pruneInvites(GetTime())
    return INVITE_CAP - #Q.inviteTimes
end

local function inviteName(name)
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or rawget(_G, "InviteUnit")
    return fn and NS.GuardTag("InviteUnit(quest)", fn, name)
end

local function onJoinRequest(sender, rest)
    local k = key(sender)
    if not k then return end
    local qid, level, class, roles, title = rest:match("^(%d+)%s+(%d+)%s+(%S+)%s+(%S+)%s?(.*)$")
    qid = tonumber(qid)
    if not qid then return end
    if NS.IsHiddenByPlayer({ key = k }) or (GrupoFacilDB.blocked and GrupoFacilDB.blocked[k]) then
        Trace("MISSAO", "pedido de jogador bloqueado ignorado")
        return
    end
    if not canLead() then Q.Send("R" .. Q.PROTO .. " no", sender) return end
    if groupFull() then Q.Send("R" .. Q.PROTO .. " full", sender) return end
    local now = GetTime()
    local same = (Q.myQuest == qid) or Q.OnQuest(qid)
    local db = Q.DB()
    if db.autoInvite and same and Q.InvitesLeft() > 0 and not (Q.invitedAt[k] and now - Q.invitedAt[k] < REINVITE_WAIT) then
        Q.invitedAt[k] = now
        Q.inviteTimes[#Q.inviteTimes + 1] = now
        local ok = inviteName(sender)
        Trace("MISSAO", "convite automático (missão %d): %s; restam %d", qid, tostring(ok), Q.InvitesLeft())
        Q.myQuest = Q.myQuest or qid
        Q.Send("R" .. Q.PROTO .. " inv", sender)
        NS.Print(format(L["%s asked to join for %s: invited."], display(sender), (Q.Info(qid) or {}).title or title or tostring(qid)))
        return
    end
    -- fica na janela para você decidir (um pedido por jogador)
    for i = #Q.requests, 1, -1 do if Q.requests[i].key == k then table.remove(Q.requests, i) end end
    if title == "" then title = nil end
    Q.requests[#Q.requests + 1] = { key = k, name = sender, questID = qid, level = tonumber(level), class = class ~= "-" and class or nil,
        roles = roles, at = now, same = same, title = title }
    Q.Send("R" .. Q.PROTO .. " wait", sender)
    local qi = Q.Info(qid)
    NS.Print(format(L["%s wants to join your group for %s. Open the quest window to invite: /gf quests"], display(sender),
        (qi and qi.inLog and qi.title) or title or (qi and qi.title) or tostring(qid)))
    Trace("MISSAO", "pedido de vaga recebido (missão %d, mesma=%s)", qid, tostring(same))
    if NS.ShowQuestWindow then NS.ShowQuestWindow(false) end
    refresh("request")
end

local function onJoinReply(sender, rest)
    local k = key(sender)
    if not k then return end
    local code = rest:match("^(%a+)")
    local mine
    for ak in pairs(Q.asked) do if sameName(ak, k) then mine = ak end end
    if not mine then return end
    Q.answers[mine] = { code = code, at = GetTime() }
    if code == "full" then NS.Print(format(L["%s: the group is full."], display(sender)))
    elseif code == "no" then NS.Print(format(L["%s is not the group leader."], display(sender)))
    elseif code == "wait" then NS.Print(format(L["%s got your request and will decide."], display(sender))) end
    refresh("reply")
end

-- Convidar, da janela, um pedido recebido (clique).
function Q.InviteRequest(r)
    if not r then return false end
    if not canLead() then NS.Print(L["only the group leader can invite."]) return false end
    local ok = inviteName(r.name)
    for i = #Q.requests, 1, -1 do if Q.requests[i] == r then table.remove(Q.requests, i) end end
    Q.myQuest = Q.myQuest or r.questID
    Trace("MISSAO", "convite a pedido recebido: %s", tostring(ok))
    refresh("invite")
    return ok
end

function Q.DismissRequest(r)
    for i = #Q.requests, 1, -1 do if Q.requests[i] == r then table.remove(Q.requests, i) end end
    refresh("dismiss")
end

function Q.Requests()
    local now = GetTime()
    for i = #Q.requests, 1, -1 do
        if now - Q.requests[i].at > REQUEST_TTL then table.remove(Q.requests, i) end
    end
    return Q.requests
end

function Q.OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= Q.PREFIX or isSecret(msg) or isSecret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    if channel ~= "WHISPER" then return end
    local kind, ver, rest = msg:match("^(%a?%??)(%d)%s?(.*)$")
    if not kind or ver ~= Q.PROTO then return end
    if kind == "?" then replyQuests(sender)
    elseif kind == "Q" then onAnswer(sender, rest)
    elseif kind == "J" then onJoinRequest(sender, rest)
    elseif kind == "R" then onJoinReply(sender, rest)
    elseif kind == "I" then onInfo(sender, rest) end
end

------------------------------------------------------------------------
-- convite que chega: aceita sozinho se foi pedido por você há pouco
------------------------------------------------------------------------
function Q.OnInvite(name)
    if type(name) ~= "string" or isSecret(name) then return end
    local k = key(name)
    local now = GetTime()
    local hit
    for ak, a in pairs(Q.asked) do
        if now - a.at <= ACCEPT_FOR and sameName(ak, k) then hit = ak end
    end
    if not hit then return end
    local a = Q.asked[hit]
    Q.asked[hit] = nil
    if not Q.DB().autoAccept then
        Trace("MISSAO", "convite do líder pedido; aceite automático desligado")
        return
    end
    local accept = rawget(_G, "AcceptGroup")
    local ok = accept and NS.GuardTag("AcceptGroup", accept)
    if ok and StaticPopup_Hide then pcall(StaticPopup_Hide, "PARTY_INVITE") end
    Q.myQuest = a.questID ~= 0 and a.questID or Q.myQuest
    Trace("MISSAO", "convite aceito sozinho (pedido há %.0f s): %s", now - a.at, tostring(ok))
    if ok then NS.Print(format(L["joined %s's group (you asked to join)."], display(name))) end
    refresh("accept")
end

------------------------------------------------------------------------
-- entradas em grupo por hora (o jogo limita)
------------------------------------------------------------------------
function Q.JoinsLastHour()
    local char = GrupoFacilCharDB
    local list = char and char.joins
    if type(list) ~= "table" then return 0 end
    local now = time()
    for i = #list, 1, -1 do if now - list[i] > JOIN_WINDOW then table.remove(list, i) end end
    return #list
end

function Q.JoinWarning()
    local n = Q.JoinsLastHour()
    if n >= JOIN_WARN then return format(L["You joined %d groups in the last hour. The game allows about 16 per hour."], n) end
    return nil
end

local wasInGroup = false
function Q.OnRoster()
    local now = IsInGroup()
    if now and not wasInGroup then
        local char = GrupoFacilCharDB
        if char then
            char.joins = type(char.joins) == "table" and char.joins or {}
            char.joins[#char.joins + 1] = time()
            Q.JoinsLastHour()
        end
    elseif not now and wasInGroup then
        if not Q.HasListing() then Q.myQuest = nil end
    end
    wasInGroup = now
    refresh("roster")
end

------------------------------------------------------------------------
-- missão concluída: oferecer sair do grupo e tirar a listagem
------------------------------------------------------------------------
function Q.CheckDone(questID, turnedIn)
    local qid = questID or Q.myQuest
    if not qid or qid ~= Q.myQuest or Q.prompted[qid] then return end
    if not (IsInGroup() or Q.HasListing()) then return end
    local done = turnedIn
    if not done then
        local ql = questLog()
        done = ql and (call(ql.ReadyForTurnIn, qid) == true or call(ql.IsComplete, qid) == true)
    end
    if not done then return end
    Q.prompted[qid] = true
    local info = Q.Info(qid)
    Q.doneTitle = (info and info.title) or Q.doneTitle or tostring(qid)
    Trace("MISSAO", "missão %d concluída: oferecendo sair/tirar listagem", qid)
    if NS.ShowQuestDone then NS.ShowQuestDone(qid, Q.doneTitle) end
end

------------------------------------------------------------------------
-- eventos
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
for _, e in ipairs({ "CHAT_MSG_ADDON", "PARTY_INVITE_REQUEST", "GROUP_ROSTER_UPDATE", "LFG_LIST_SEARCH_RESULTS_RECEIVED",
    "PLAYER_LOGIN" }) do
    pcall(ev.RegisterEvent, ev, e)
end
for _, e in ipairs({ "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "QUEST_LOG_UPDATE", "QUEST_TURNED_IN",
    "QUEST_REMOVED", "GROUP_LEFT", "UI_ERROR_MESSAGE", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    if not pcall(ev.RegisterEvent, ev, e) then Trace("CARGA", "evento %s indisponível", e) end
end

local doneQueued = false
local function onEvent(_, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, Q.PREFIX) end
        Q.DB()
        wasInGroup = IsInGroup() and true or false
    elseif event == "CHAT_MSG_ADDON" then
        Q.OnAddonMessage(...)
    elseif event == "PARTY_INVITE_REQUEST" then
        Q.OnInvite((...))
    elseif event == "GROUP_ROSTER_UPDATE" or event == "GROUP_LEFT" then
        Q.OnRoster()
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        -- só a busca da lupa pergunta aos líderes (a nativa não tem missão)
        if Q.current and Q.searchedAt and GetTime() - Q.searchedAt < 15 and not Q.queried then
            Q.queried = true
            C_Timer.After(0.2, function() Q.QueryLeaders(); refresh("results") end)
        end
        refresh("results")
    elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
        local p = Q.pendingCreate
        if p and Q.HasListing() then
            Q.pendingCreate = nil
            if p.dungeon then
                NS.Print(format(L["your group is listed in Looking For Group, in Dungeons: %s."], p.dungeon))
            else
                NS.Print(L["your group is listed in Looking For Group for this quest."])
            end
            Trace("MISSAO", "listagem criada (com ID da missão=%s)", tostring(p.withQuest))
        end
        Q.CheckListing("evento")
        -- o jogo pode avisar antes de atualizar o estado da listagem: confere de novo logo depois
        C_Timer.After(0.5, function() Q.CheckListing("evento+0.5") end)
        C_Timer.After(1.5, function() Q.CheckListing("evento+1.5") end)
        refresh("entry")
    elseif event == "LFG_LIST_ENTRY_CREATION_FAILED" then
        local p = Q.pendingCreate
        Q.pendingCreate = nil
        if p and p.withQuest then
            -- o jogo pode não aceitar o ID da missão nesta categoria: a próxima tentativa vai sem ele
            Q.DB().noQuestIDListing = true
            NS.Print(L["the game refused the listing with the quest. Click Create group again (it goes without the quest)."])
        else
            NS.Print(L["the game refused the listing."])
        end
        Trace("MISSAO", "criação da listagem recusada (com ID=%s)", tostring(p and p.withQuest))
        refresh("entry-failed")
    elseif event == "UI_ERROR_MESSAGE" or event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- só enquanto espera a criação da listagem: o motivo de o jogo não listar vai para o /gf diag
        local p = Q.pendingCreate
        if p then
            local a, b = ...
            local txt = event == "UI_ERROR_MESSAGE" and (str(b) or tostring(a)) or (event .. " " .. tostring(a) .. " " .. tostring(b))
            if not isSecret(txt) then p.errors[#p.errors + 1] = txt end
            Trace("MISSAO", "durante a criação: %s", isSecret(txt) and "(segredo)" or txt)
        end
    elseif event == "QUEST_TURNED_IN" then
        local qid = ...
        Q.CheckDone(num(qid), true)
    elseif event == "QUEST_LOG_UPDATE" or event == "QUEST_REMOVED" then
        if Q.myQuest and not doneQueued then
            doneQueued = true
            C_Timer.After(0.5, function() doneQueued = false; Q.CheckDone(nil, false) end)
        end
        refresh("questlog")
    end
end
ev:SetScript("OnEvent", function(self, event, ...) D.Call("quest:" .. event, onEvent, self, event, ...) end)
