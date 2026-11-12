-- GrupoFacil: lê os resultados do Looking For Group do Forever, filtra por level,
-- classe e role e manda uma mensagem pronta ao líder de um grupo.
--
-- Regras de segurança (taint e secret values do Forever, que usa as regras do Midnight):
--  * Nunca escreve em frames, campos ou controles da janela da Blizzard
--    (LFGBrowseFrame, LFGParentFrame) e nunca chama LFGBrowse_* nem ShowSearchForActivities.
--    Só lê e usa hooksecurefunc/HookScript.
--  * C_LFGList.Search só é chamado dentro do OnClick de um botão do addon (exige clique).
--  * Com o bloqueio de chat do jogo ativo (C_ChatInfo.InChatMessagingLockdown), não lê
--    resultados nem envia mensagens; todo campo lido passa por issecretvalue.

local ADDON, NS = ...
-- A versão vem do TOC. No pacote publicado o empacotador troca @project-version@ pela tag;
-- numa cópia de desenvolvimento ela aparece como "dev".
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local v = getMeta and getMeta(ADDON, "Version")
    if type(v) ~= "string" or v == "" or v:find("@", 1, true) then v = "dev" end
    NS.VERSION = v
end
local L = NS.L

local GetTime, time, type, tostring, tonumber, pairs, ipairs = GetTime, time, type, tostring, tonumber, pairs, ipairs
local format, gsub, lower = string.format, string.gsub, string.lower

------------------------------------------------------------------------
-- configuração
------------------------------------------------------------------------
-- Padrão em inglês. GrupoFacilDB.template só existe quando o jogador define um texto próprio.
NS.DEFAULT_TEMPLATE = "Hi, I'm a level {level} {spec} {class}, can I join your group?"
local OLD_PT_DEFAULT = "Olá, sou {classe} {spec} {level}, posso me juntar a vocês?" -- padrão da 0.1/0.2

local DEFAULTS = {
    sendMode = "direto",      -- "direto" envia o sussurro; "preencher" só abre o chat com o texto
    autoOpen = true,          -- abre junto com a janela do Looking For Group
    docked = true,            -- encaixado à direita da janela do Looking For Group
    debug = false,
    filters = {
        mode = "players",     -- "players", "groups" ou "all"
        minLevel = nil,
        maxLevel = nil,
        classes = {},         -- [classFilename] = true; vazio = todas
        roles = {},           -- tank/healer/dps = true; vazio = todas
        hideDelisted = true,
        sort = "level",       -- "level", "name" ou "age"
    },
}

local function copyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            copyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

------------------------------------------------------------------------
-- utilidades
------------------------------------------------------------------------
local PREFIX = "|cff33ccffGrupoFacil|r: "
function NS.Print(msg) print(PREFIX .. tostring(msg)) end

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end
NS.isSecret = isSecret

local function anySecret(t, ...)
    for i = 1, select("#", ...) do
        if isSecret(t[select(i, ...)]) then return true end
    end
    return false
end

function NS.InLockdown()
    if C_ChatInfo and C_ChatInfo.InChatMessagingLockdown then
        local ok, r = pcall(C_ChatInfo.InChatMessagingLockdown)
        return ok and r == true
    end
    return false
end

-- Erros vão para o diagnóstico (Diag.lua): GrupoFacilDB.diag.errors, com stack e contexto.
local D = NS.D
local Trace = D.Trace

function NS.Guard(fn, ...)
    return D.Call(nil, fn, ...)
end

-- Igual ao Guard, mas o nome entra no contexto do erro.
function NS.GuardTag(tag, fn, ...)
    return D.Call(tag, fn, ...)
end

local function normName(name)
    if type(name) ~= "string" or isSecret(name) then return nil end
    if Ambiguate then name = Ambiguate(name, "none") end
    return lower(name)
end
NS.normName = normName

------------------------------------------------------------------------
-- dados do próprio jogador
------------------------------------------------------------------------
-- Spec no Forever: os talentos são árvores do C_Traits; a spec é o grupo com mais pontos.
local function specFromTraits()
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then return nil end
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end
    local config = C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil end
    local groups = C_Traits.GetGroupDisplayInfoByTreeID(treeID)
    if type(groups) ~= "table" or #groups == 0 then return nil end
    local ids, names = {}, {}
    for i, g in ipairs(groups) do
        ids[i] = g.groupID
        names[g.groupID] = g.displayName
    end
    local infos = C_Traits.GetGroupCurrencyInfo(configID, ids)
    if type(infos) ~= "table" then return nil end
    local best, bestSpent = nil, 0
    for _, info in ipairs(infos) do
        local c = info.currencyInfos and info.currencyInfos[1]
        local spent = c and c.spent or 0
        if spent > bestSpent and names[info.traitNodeGroupID] then
            best, bestSpent = names[info.traitNodeGroupID], spent
        end
    end
    return best
end

-- A spec detectada fica em cache; é recalculada quando os talentos ou o level mudam.
local specCache -- nil = não calculado; false = sem spec
function NS.InvalidateSpec() specCache = nil end

-- Spec pelos talentos, ignorando a escolhida nas opções.
function NS.DetectedSpec()
    if specCache == nil then
        local ok, spec = NS.Guard(specFromTraits)
        specCache = (ok and type(spec) == "string" and spec ~= "") and spec or false
    end
    return specCache or nil
end

function NS.PlayerSpec()
    local char = GrupoFacilCharDB
    if char and char.spec and char.spec ~= "" then return char.spec end
    return NS.DetectedSpec()
end

function NS.PlayerClass()
    local char = GrupoFacilCharDB
    if char and char.classe and char.classe ~= "" then return char.classe end
    return (UnitClass("player"))
end

function NS.GetTemplate()
    local t = GrupoFacilDB and GrupoFacilDB.template
    if type(t) == "string" and t:match("%S") then return t, true end
    return NS.DEFAULT_TEMPLATE, false
end

-- Texto vazio ou nil volta ao padrão em inglês.
function NS.SetTemplate(text)
    if type(text) == "string" then text = text:gsub("^%s+", ""):gsub("%s+$", "") end
    if text == "" or text == NS.DEFAULT_TEMPLATE then text = nil end
    GrupoFacilDB.template = text
    if NS.D then NS.D.Trace("CONFIG", "mensagem %s", text and "personalizada" or "padrão (inglês)") end
    if NS.Refresh then NS.Refresh("template") end
end

function NS.BuildMessage()
    local text = NS.GetTemplate()
    local class = NS.PlayerClass() or ""
    local name = UnitName("player") or ""
    local vars = {
        class = class, classe = class,
        spec = NS.PlayerSpec() or "",
        level = tostring(UnitLevel("player") or ""),
        name = name, nome = name,
    }
    text = gsub(text, "{(%a+)}", function(k) return vars[k] or ("{" .. k .. "}") end)
    text = gsub(text, "%s+([,%.!%?])", "%1") -- "sou Hunter  , posso" -> "sou Hunter, posso"
    text = gsub(text, "%s%s+", " ")
    text = gsub(text, "^%s+", "")
    text = gsub(text, "%s+$", "")
    return text
end

------------------------------------------------------------------------
-- última busca (para o botão "Buscar de novo")
------------------------------------------------------------------------
NS.lastSearch = nil   -- { category, filter, preferred, language, crossFaction, advanced, activities }
NS.searching = false

local function copyList(t)
    if type(t) ~= "table" or isSecret(t) then return nil end
    local out = {}
    for i, v in ipairs(t) do
        if isSecret(v) then return nil end
        out[i] = v
    end
    return out
end

local function rememberSearch(category, filter, preferred, language, crossFaction, advanced, activities)
    if isSecret(category) or type(category) ~= "number" or category <= 0 then return end
    NS.lastSearch = {
        category = category,
        filter = (not isSecret(filter) and filter) or 0,
        preferred = (not isSecret(preferred) and preferred) or 0,
        language = (not isSecret(language)) and language or nil,
        crossFaction = (not isSecret(crossFaction)) and crossFaction or false,
        activities = copyList(activities),
    }
    Trace("BUSCA", "origem=%s categoria=%s atividades=%s", NS.addonSearching and "addon" or "nativa",
        tostring(category), D.str(NS.lastSearch.activities))
end

-- Fallback: só lê (nunca escreve) os dropdowns da janela nativa.
local function searchFromBlizzardDropdowns()
    local browse = _G.LFGBrowseFrame
    if not (browse and browse.CategoryDropdown and browse.CategoryDropdown.GetValue) then return nil end
    local category = browse.CategoryDropdown:GetValue()
    if type(category) ~= "number" or isSecret(category) or category <= 0 then return nil end
    local acts = browse.ActivityDropdown and copyList(browse.ActivityDropdown.selectedValues)
    if (not acts or #acts == 0) and LFGUtil_GetFilteredActivities then
        acts = copyList(LFGUtil_GetFilteredActivities(category))
    end
    return { category = category, filter = 0, preferred = 0, language = nil, crossFaction = false, activities = acts }
end

function NS.GetSearchArgs()
    if NS.lastSearch then return NS.lastSearch end
    local ok, s = NS.Guard(searchFromBlizzardDropdowns)
    if ok and s then return s end
    return nil
end

-- O servidor responde "throttled" a buscas muito seguidas (visto no jogo: 3 buscas em ~2 s).
-- O intervalo conta a partir de QUALQUER busca, inclusive a da janela nativa.
local SEARCH_COOLDOWN = 3
local THROTTLE_PAUSE = 6
local SEARCH_TIMEOUT = 10
NS.searchReadyAt = 0
NS.searchStartedAt = 0

local function holdSearch(seconds)
    local untilT = GetTime() + seconds
    if untilT > NS.searchReadyAt then NS.searchReadyAt = untilT end
    C_Timer.After(seconds + 0.05, function() NS.Refresh("cooldown") end)
end
NS.HoldSearch = holdSearch

-- Uma busca que nunca responde não pode deixar o painel preso em "Buscando...".
function NS.MarkSearching()
    NS.searching = true
    NS.status = L["Searching..."]
    local started = GetTime()
    NS.searchStartedAt = started
    holdSearch(SEARCH_COOLDOWN)
    C_Timer.After(SEARCH_TIMEOUT, function()
        if NS.searching and NS.searchStartedAt == started then
            NS.searching = false
            NS.status = L["The search got no answer. Try again."]
            Trace("BUSCA", "sem resposta em %ds", SEARCH_TIMEOUT)
            NS.Refresh("timeout")
        end
    end)
    D.ProbeNativeSearch(SEARCH_TIMEOUT + 2)
    NS.Refresh("search")
end

-- Chamar SOMENTE de dentro de um OnClick (a busca exige clique do jogador).
function NS.SearchAgain()
    if GetTime() < NS.searchReadyAt then
        return false, format(L["wait %d s (the game limits back-to-back searches)"], math.ceil(NS.searchReadyAt - GetTime()))
    end
    if NS.InLockdown() then return false, L["the game's chat restriction is active"] end
    local s = NS.GetSearchArgs()
    if not s then return false, L["search in the Looking For Group window first"] end
    local acts = copyList(s.activities)
    Trace("BUSCA", "botão Buscar de novo: categoria=%s atividades=%s (args de %s)", tostring(s.category),
        D.str(acts), NS.lastSearch and "hook" or "dropdowns")
    NS.addonSearching = true
    local ok = NS.GuardTag("C_LFGList.Search", C_LFGList.Search, s.category, s.filter or 0, s.preferred or 0, s.language,
        s.crossFaction or false, nil, acts)
    NS.addonSearching = false
    if not ok then return false, L["the search failed (see /gf diag)"] end
    if not NS.searching then NS.MarkSearching() end -- com o hook desligado
    return true
end

------------------------------------------------------------------------
-- leitura dos resultados
------------------------------------------------------------------------
NS.entries = {}        -- [resultID] = entry
NS.order = {}          -- resultIDs na ordem que o jogo devolveu
NS.status = nil -- a janela mostra a dica inicial
NS.stale = false

local activityCache = {}   -- [activityID] = { name, maxPlayers }
local function activityInfo(activityID)
    if not activityID or isSecret(activityID) then return "", nil end
    local cached = activityCache[activityID]
    if cached then return cached[1], cached[2] end
    local info = C_LFGList.GetActivityInfoTable(activityID)
    local name = info and (info.fullName or info.shortName)
    if type(name) ~= "string" or isSecret(name) then return "", nil end
    local maxPlayers = info.maxNumPlayers
    if type(maxPlayers) ~= "number" or isSecret(maxPlayers) or maxPlayers <= 0 then maxPlayers = nil end
    activityCache[activityID] = { name, maxPlayers }
    return name, maxPlayers
end
local function activityName(activityID) return (activityInfo(activityID)) end

local function readPlayer(p, e)
    if type(p) ~= "table" or isSecret(p) then return end
    if canaccesstable and not canaccesstable(p) then return end
    if not isSecret(p.level) and type(p.level) == "number" then e.level = p.level end
    if not isSecret(p.classFilename) and type(p.classFilename) == "string" then e.class = p.classFilename end
    if not isSecret(p.className) and type(p.className) == "string" then e.className = p.className end
    -- No Forever o servidor manda em specName só o nome da classe ("Priest"); aí não é spec.
    if not isSecret(p.specName) and type(p.specName) == "string" and p.specName ~= ""
        and p.specName ~= e.className and lower(p.specName) ~= lower(e.class or "") then
        e.specName = p.specName
    end
    if not isSecret(p.assignedRole) and type(p.assignedRole) == "string" then e.assignedRole = p.assignedRole end
    local r = p.lfgRoles
    if type(r) == "table" and not isSecret(r) then
        e.roles = {
            tank = (not isSecret(r.tank)) and r.tank == true,
            healer = (not isSecret(r.healer)) and r.healer == true,
            dps = (not isSecret(r.dps)) and r.dps == true,
        }
    end
end

local function readResult(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    if info == nil then return nil, "info nil" end
    if type(info) ~= "table" or isSecret(info) then return nil, "info secreta" end
    if canaccesstable and not canaccesstable(info) then return nil, "info inacessível" end
    if anySecret(info, "numMembers", "hasSelf", "isDelisted", "leaderName", "age", "activityIDs") then return nil, "campo secreto" end
    if info.hasSelf then return nil, "própria listagem" end

    local e = {
        id = id,
        name = info.leaderName,                 -- pode vir nil até o servidor mandar os dados
        key = normName(info.leaderName),
        numMembers = info.numMembers or 0,
        delisted = info.isDelisted == true,
        age = info.age,
    }
    e.solo = e.numMembers <= 1

    local acts = info.activityIDs
    if type(acts) == "table" and #acts > 0 then
        local _, maxPlayers = activityInfo(acts[1])
        e.maxPlayers = maxPlayers
        if #acts == 1 then
            e.activity = activityName(acts[1])
        else
            local first = activityName(acts[1])
            e.activity = first ~= "" and format("%s +%d", first, #acts - 1) or format("%d atividades", #acts)
        end
    else
        e.activity = ""
    end

    if e.solo then
        readPlayer(C_LFGList.GetSearchResultPlayerInfo(id, 1), e)
    else
        readPlayer(C_LFGList.GetSearchResultLeaderInfo(id), e)
        if C_LFGList.GetSearchResultMemberCounts then
            local c = C_LFGList.GetSearchResultMemberCounts(id)
            if type(c) == "table" and not isSecret(c) and not anySecret(c, "TANK", "HEALER", "DAMAGER") then
                e.counts = { tank = c.TANK or 0, healer = c.HEALER or 0, dps = c.DAMAGER or 0 }
            end
        end
    end
    return e
end

local function safeRead(id)
    local ok, e, why = NS.GuardTag("readResult", readResult, id)
    if ok then return e, why end
    return nil, "erro"
end

-- Amostra a forma crua dos dados (para o diagnóstico) dos primeiros resultados.
local function sampleRaw(id)
    local info = C_LFGList.GetSearchResultInfo(id)
    local solo = type(info) == "table" and not isSecret(info) and not isSecret(info.numMembers)
        and (info.numMembers or 0) <= 1
    local player
    if solo then player = C_LFGList.GetSearchResultPlayerInfo(id, 1) else player = C_LFGList.GetSearchResultLeaderInfo(id) end
    local counts = (not solo and C_LFGList.GetSearchResultMemberCounts) and C_LFGList.GetSearchResultMemberCounts(id) or nil
    D.Sample(id, info, player, counts)
end

local wasLockdown = false
local function checkLockdown()
    local now = NS.InLockdown()
    if now ~= wasLockdown then
        wasLockdown = now
        Trace("LOCKDOWN", now and "restrição de chat ATIVA" or "restrição de chat terminou")
    end
    return now
end
NS.CheckLockdown = checkLockdown

NS.updatesSinceRebuild = 0

function NS.RebuildAll(reason)
    if checkLockdown() then
        NS.stale = true
        NS.status = L["Game chat restriction active: list frozen."]
        Trace("RESULTADOS", "não lidos (%s): restrição de chat ativa", tostring(reason))
        return
    end
    local ok, total, results = NS.GuardTag("GetFilteredSearchResults", C_LFGList.GetFilteredSearchResults)
    if not ok or type(results) ~= "table" or isSecret(results) then
        NS.status = L["Could not read the results."]
        Trace("RESULTADOS", "falha ao ler (%s): ok=%s total=%s results=%s", tostring(reason), tostring(ok),
            D.str(total), isSecret(results) and "SECRET" or type(results))
        return
    end
    wipe(NS.entries)
    wipe(NS.order)
    local read, skipped, secretIds, players, groups = 0, {}, 0, 0, 0
    for i, id in ipairs(results) do
        if isSecret(id) then
            secretIds = secretIds + 1
        else
            NS.order[#NS.order + 1] = id
            local e, why = safeRead(id)
            NS.entries[id] = e
            if e then
                read = read + 1
                if e.solo then players = players + 1 else groups = groups + 1 end
            else
                skipped[why or "?"] = (skipped[why or "?"] or 0) + 1
            end
            if i <= 3 and reason == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then NS.GuardTag("sampleRaw", sampleRaw, id) end
        end
    end
    NS.stale = false
    NS.status = format(L["%d results in total."], #NS.order)
    Trace("RESULTADOS", "%s: total=%s ids=%d lidos=%d (jogadores=%d grupos=%d) descartados=%s idsSecretos=%d updatesAntes=%d",
        tostring(reason), D.str(total), #results, read, players, groups, D.str(skipped), secretIds, NS.updatesSinceRebuild)
    NS.updatesSinceRebuild = 0
end

function NS.UpdateOne(id)
    if isSecret(id) or not NS.entries[id] and not tContains(NS.order, id) then return end
    if checkLockdown() then NS.stale = true return end
    NS.updatesSinceRebuild = NS.updatesSinceRebuild + 1
    NS.entries[id] = safeRead(id)
end

------------------------------------------------------------------------
-- filtros
------------------------------------------------------------------------
local function hasAny(set)
    for _, v in pairs(set) do if v then return true end end
    return false
end

-- Vaga por role, pelo tamanho da atividade (maxNumPlayers): falta tank se não tem tank;
-- falta healer se não tem healer; cabe dps se há vaga e menos de (tamanho - 2) dps.
-- Sem o tamanho da atividade, não dá para calcular e o grupo não passa no filtro.
local function groupNeeds(e, role)
    local size = e.maxPlayers
    if not e.counts or not size or e.numMembers >= size then return false end
    if role == "tank" then return e.counts.tank == 0 end
    if role == "healer" then return e.counts.healer == 0 end
    if role == "dps" then return e.counts.dps < math.max(1, size - 2) end
    return false
end

function NS.Matches(e, f)
    if not e then return false end
    if f.hideDelisted and e.delisted then return false end
    if f.mode == "players" and not e.solo then return false end
    if f.mode == "groups" and e.solo then return false end

    if f.minLevel or f.maxLevel then
        if not e.level then return false end
        if f.minLevel and e.level < f.minLevel then return false end
        if f.maxLevel and e.level > f.maxLevel then return false end
    end

    if hasAny(f.classes) then
        if not e.class or not f.classes[e.class] then return false end
    end

    if hasAny(f.roles) then
        local ok = false
        for role, on in pairs(f.roles) do
            if on then
                if e.solo then
                    if e.roles and e.roles[role] then ok = true end
                elseif groupNeeds(e, role) then
                    ok = true
                end
            end
        end
        if not ok then return false end
    end
    return true
end

function NS.Visible()
    local f = GrupoFacilDB.filters
    local list = {}
    for _, id in ipairs(NS.order) do
        local e = NS.entries[id]
        if NS.Matches(e, f) then list[#list + 1] = e end
    end
    local sort = f.sort
    table.sort(list, function(a, b)
        if sort == "name" then
            return (a.key or "~") < (b.key or "~")
        elseif sort == "age" then
            return (a.age or 1e9) < (b.age or 1e9)
        end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return (a.key or "~") < (b.key or "~")
    end)
    return list
end

------------------------------------------------------------------------
-- ações: convidar, sussurrar, pedir vaga
------------------------------------------------------------------------
function NS.CanInvite(e)
    if not e or not e.solo or e.delisted or not e.name then return false end
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

function NS.Invite(e)
    if not NS.CanInvite(e) then return end
    if NS.InLockdown() then NS.Print(L["game chat restriction active; invite blocked."]) return end
    local fn = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
    local ok = NS.GuardTag("InviteUnit", fn, e.name)
    Trace("CONVITE", "convite a jogador lvl %s %s: ok=%s", tostring(e.level), tostring(e.class), tostring(ok))
end

function NS.OpenWhisper(e, text)
    if not e or not e.name then return end
    local how, ok
    if text and ChatFrameUtil and ChatFrameUtil.SendTellWithMessage then
        how = "SendTellWithMessage"
        ok = NS.GuardTag(how, ChatFrameUtil.SendTellWithMessage, e.name, text)
    elseif ChatFrameUtil and ChatFrameUtil.SendTell then
        how = "SendTell"
        ok = NS.GuardTag(how, ChatFrameUtil.SendTell, e.name)
    elseif ChatFrame_SendTell then
        how = "ChatFrame_SendTell"
        ok = NS.GuardTag(how, ChatFrame_SendTell, e.name)
    else
        how = "nenhuma função de chat"
    end
    Trace("CHAT", "abrir sussurro via %s: ok=%s", how, tostring(ok))
end

local SEND_INTERVAL = 3          -- segundos entre dois pedidos de vaga quaisquer
local RESEND_BLOCK = 300         -- segundos antes de pedir de novo ao mesmo líder
NS.sendReadyAt = 0
NS.pending = {}                  -- [key] = GetTime() do envio, até o jogo confirmar
NS.sent = {}                     -- [key] = time() da confirmação

function NS.CanAskToJoin(e)
    if not e or e.solo or e.delisted or not e.name or not e.key then return false, L["no leader data yet"] end
    if IsInGroup() then return false, L["you are already in a group"] end
    if NS.InLockdown() then return false, L["the game's chat restriction is active"] end
    local sentAt = NS.sent[e.key]
    if sentAt and time() - sentAt < RESEND_BLOCK then return false, L["already sent recently"] end
    return true
end

function NS.AskToJoin(e)
    local ok, why = NS.CanAskToJoin(e)
    if not ok then
        NS.Print(format(L["not sent: %s."], why))
        Trace("PEDIDO", "bloqueado pelo addon: %s", why)
        return
    end
    if GetTime() < NS.sendReadyAt then NS.Print(L["wait a few seconds between requests."]) return end
    local text = NS.BuildMessage()
    NS.sendReadyAt = GetTime() + SEND_INTERVAL
    if GrupoFacilDB.sendMode == "preencher" then
        Trace("PEDIDO", "modo preencher, grupo de %d", e.numMembers)
        NS.OpenWhisper(e, text)
        return
    end
    local useC = C_ChatInfo and C_ChatInfo.SendChatMessage
    local send = useC or SendChatMessage
    local key = e.key
    NS.pending[key] = GetTime()
    local sent = NS.GuardTag("SendChatMessage", send, text, "WHISPER", nil, e.name)
    Trace("PEDIDO", "sussurro via %s, grupo de %d, %d caracteres: chamada ok=%s",
        useC and "C_ChatInfo.SendChatMessage" or "SendChatMessage", e.numMembers, #text, tostring(sent))
    -- Sem confirmação do jogo em 5 s: provável bloqueio silencioso ou líder offline.
    C_Timer.After(5, function()
        if NS.pending[key] then
            NS.pending[key] = nil
            Trace("PEDIDO", "SEM confirmação do jogo em 5s (bloqueio silencioso ou jogador offline)")
            NS.Print(L["the game did not confirm the request was sent. See /gf diag."])
            NS.Refresh("whisper-timeout")
        end
    end)
end

-- O jogo confirma o sussurro enviado com CHAT_MSG_WHISPER_INFORM.
function NS.OnWhisperInform(target)
    local key = normName(target)
    if not key or not NS.pending[key] then return end
    NS.pending[key] = nil
    NS.sent[key] = time()
    Trace("PEDIDO", "confirmado pelo jogo (CHAT_MSG_WHISPER_INFORM)")
    NS.Print(format(L["request sent to %s."], target))
end

------------------------------------------------------------------------
-- eventos
------------------------------------------------------------------------
local renderQueued = false
function NS.Refresh(reason)
    if renderQueued then return end
    renderQueued = true
    C_Timer.After(0.1, function()
        renderQueued = false
        if NS.Render then NS.GuardTag("Render", NS.Render) end
    end)
end

local function hookBlizzardLFG()
    if NS.hookedBlizzard or not _G.LFGParentFrame then return end
    NS.hookedBlizzard = true
    -- Só mostra/esconde o frame do addon; nada é chamado ou escrito no frame da Blizzard.
    _G.LFGParentFrame:HookScript("OnShow", D.Wrap("LFGParentFrame.OnShow", function()
        Trace("JANELA", "Looking For Group aberto")
        if GrupoFacilDB.autoOpen and NS.ShowPanel then NS.ShowPanel(true) end
    end))
    _G.LFGParentFrame:HookScript("OnHide", D.Wrap("LFGParentFrame.OnHide", function()
        if NS.HidePanelIfDocked then NS.HidePanelIfDocked() end
    end))
    Trace("HOOK", "LFGParentFrame OnShow/OnHide instalados; taint=%s", D.str(D.TaintReport()))
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("LFG_LIST_SEARCH_RESULTS_RECEIVED")
ev:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
ev:RegisterEvent("LFG_LIST_SEARCH_FAILED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("TRAIT_CONFIG_UPDATED")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("ADDON_ACTION_BLOCKED")
ev:RegisterEvent("ADDON_ACTION_FORBIDDEN")

local function onEvent(_, event, ...)
    if event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            GrupoFacilDB = GrupoFacilDB or {}
            GrupoFacilCharDB = GrupoFacilCharDB or {}
            copyDefaults(GrupoFacilDB, DEFAULTS)
            -- 0.1/0.2 gravavam o padrão em português; quem não personalizou passa ao padrão em inglês.
            if GrupoFacilDB.template == OLD_PT_DEFAULT then GrupoFacilDB.template = nil end
            D.Init()
            -- Captura os argumentos de cada busca (a nativa ou a do addon) sem alterar a chamada.
            -- /gf hook off desliga este hook (vale após /reload); aí o addon só lê os dropdowns.
            if GrupoFacilDB.hookSearch ~= false and C_LFGList and C_LFGList.Search then
                local ok = NS.GuardTag("hooksecurefunc(C_LFGList.Search)", hooksecurefunc, C_LFGList, "Search",
                    D.Wrap("hook C_LFGList.Search", function(...)
                        rememberSearch(...)
                        NS.MarkSearching()
                    end))
                Trace("HOOK", "hook em C_LFGList.Search: ok=%s", tostring(ok))
            else
                Trace("HOOK", "hook em C_LFGList.Search DESLIGADO (/gf hook)")
            end
            if NS.BuildUI then NS.GuardTag("BuildUI", NS.BuildUI) end
            if NS.BuildOptions then NS.GuardTag("BuildOptions", NS.BuildOptions) end
            if NS.BuildMinimapButton then NS.GuardTag("BuildMinimapButton", NS.BuildMinimapButton) end
        elseif name == "Blizzard_GroupFinder_VanillaStyle" then
            Trace("CARGA", "Blizzard_GroupFinder_VanillaStyle carregado")
            hookBlizzardLFG()
        end
    elseif event == "PLAYER_LOGIN" then
        if C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("Blizzard_GroupFinder_VanillaStyle") then
            hookBlizzardLFG()
        end
        -- Retrato do ambiente alguns segundos depois do login (talentos já carregados).
        C_Timer.After(5, D.Wrap("snapshot", function() D.Snapshot("login") end))
    elseif event == "LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        NS.searching = false
        NS.RebuildAll(event)
        NS.Refresh(event)
    elseif event == "LFG_LIST_SEARCH_RESULT_UPDATED" then
        local id = ...
        NS.UpdateOne(id)
        NS.Refresh(event)
    elseif event == "LFG_LIST_SEARCH_FAILED" then
        NS.searching = false
        local reason = ...
        if reason == "throttled" then
            -- A lista anterior continua na tela; só a busca nova foi recusada.
            holdSearch(THROTTLE_PAUSE)
            NS.status = format(L["Too many searches in a row; the game refused. Wait %d s."], THROTTLE_PAUSE)
        else
            NS.status = L["The search failed"] .. ((reason and not isSecret(reason)) and (": " .. tostring(reason)) or ".")
        end
        Trace("BUSCA", "LFG_LIST_SEARCH_FAILED reason=%s", D.str(reason))
        NS.Refresh(event)
    elseif event == "GROUP_ROSTER_UPDATE" then
        NS.Refresh(event)
    elseif event == "CHAT_MSG_WHISPER_INFORM" then
        local _, target = ...
        if not isSecret(target) then NS.OnWhisperInform(target) end
        NS.Refresh(event)
    elseif event == "CHAT_MSG_SYSTEM" then
        -- "Nenhum jogador chamado X": libera o pendente para não ficar marcado.
        local msg = ...
        if isSecret(msg) or type(msg) ~= "string" or not ERR_CHAT_PLAYER_NOT_FOUND_S then return end
        for key in pairs(NS.pending) do
            if msg:lower():find(key, 1, true) then
                NS.pending[key] = nil
                Trace("PEDIDO", "jogo respondeu que o jogador não está online")
            end
        end
    elseif event == "TRAIT_CONFIG_UPDATED" or event == "PLAYER_LEVEL_UP" then
        NS.InvalidateSpec()
        NS.Refresh(event)
    elseif event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN" then
        -- Registra de qualquer addon: ajuda a ver taint vindo de outro addon no LFG.
        local who, fn = ...
        Trace("BLOQUEIO", "%s: addon=%s função=%s", event, D.str(who), D.str(fn))
        if who == ADDON then D.OnError(event .. ": " .. tostring(fn)) end
    elseif event == "LUA_WARNING" then
        local _, text = ...
        if type(text) == "string" and not isSecret(text) and text:find(ADDON, 1, true) then
            Trace("LUA_WARNING", text)
        end
    end
end

ev:SetScript("OnEvent", function(self, event, ...)
    D.Call(event, onEvent, self, event, ...)
end)
pcall(ev.RegisterEvent, ev, "LUA_WARNING") -- pode não existir neste cliente

------------------------------------------------------------------------
-- comandos (nomes em inglês; os antigos em português continuam valendo)
------------------------------------------------------------------------
local HELP = {
    "/gf - open or close the window",
    "/gf options - open the options (also in Options > AddOns > GrupoFacil)",
    "/gf tour - show the quick tour of the window",
    "/gf lang en | pt | es | mx | de | fr - addon language (reloads the UI)",
    "/gf msg - show the join request text and how it goes out now",
    "/gf msg <text> - change the text; use {class} {spec} {level} {name}",
    "/gf msg default - back to the default text (English)",
    "/gf spec <name> | /gf spec auto - set or detect this character's spec",
    "/gf class <name> | /gf class auto - set or detect the class name",
    "/gf mode direct | prefill - send the whisper or only open the chat with the text",
    "/gf auto on | off - open together with Looking For Group",
    "/gf dock - attach the window next to Looking For Group again",
    "/gf minimap on | off - show or hide the minimap button",
    "/gf hook on | off - capture the native search (turn off if the native search gets stuck; applies after /reload)",
    "/gf diag - error and trace summary; /gf diag snap - save a snapshot now; /gf diag clear",
    "/gf debug on | off - show the trace in chat as it happens",
}

local ALIAS = {
    opcoes = "options", ["opções"] = "options", config = "options",
    tutorial = "tour", ajuda = "help",
    classe = "class", modo = "mode", minimapa = "minimap", encaixar = "dock", erros = "diag", idioma = "lang", language = "lang",
}
local ON_OFF = function(v) return v and L["on"] or L["off"] end

SLASH_GRUPOFACIL1 = "/gf"
SLASH_GRUPOFACIL2 = "/grupofacil"
SlashCmdList.GRUPOFACIL = function(input)
    input = input or ""
    local cmd, rest = input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd = lower(cmd or "")
    cmd = ALIAS[cmd] or cmd
    local l = lower(rest or "")
    local db, char = GrupoFacilDB, GrupoFacilCharDB
    if cmd == "" then
        if NS.TogglePanel then NS.TogglePanel() end
    elseif cmd == "options" then
        if NS.OpenOptions then NS.OpenOptions() end
    elseif cmd == "tour" then
        if NS.StartTour then NS.StartTour() end
    elseif cmd == "lang" then
        if l == "" or not NS.SetLanguage(l) then -- recarrega a interface quando troca
            NS.Print(format(L["language: %s (use /gf lang followed by en, pt, es, mx, de or fr)"], NS.LanguageName(NS.Language())))
        end
    elseif cmd == "msg" then
        if rest == "" then
            local t, custom = NS.GetTemplate()
            NS.Print((custom and L["text (custom): %s"] or L["text (English default): %s"]):format(t))
            NS.Print(format(L["goes out as: %s"], NS.BuildMessage()))
        elseif l == "padrao" or l == "padrão" or l == "default" then
            NS.SetTemplate(nil)
            NS.Print(format(L["default text (English): %s"], NS.BuildMessage()))
        else
            NS.SetTemplate(rest)
            NS.Print(format(L["new text: %s"], NS.BuildMessage()))
        end
    elseif cmd == "spec" or cmd == "class" then
        local key = (cmd == "spec") and "spec" or "classe" -- chave salva por personagem
        if rest == "" or l == "auto" then char[key] = nil else char[key] = rest end
        NS.InvalidateSpec()
        local v = (cmd == "spec") and NS.PlayerSpec() or NS.PlayerClass()
        NS.Print(format("%s: %s", cmd, tostring(v or L["(no talent points)"])))
    elseif cmd == "mode" then
        if l == "direct" or l == "direto" then db.sendMode = "direto"
        elseif l == "prefill" or l == "preencher" then db.sendMode = "preencher" end
        NS.Print(format(L["send mode: %s"], db.sendMode == "preencher" and L["prefill"] or L["direct"]))
    elseif cmd == "auto" then
        db.autoOpen = (l ~= "off")
        NS.Print(format(L["open together with Looking For Group: %s"], ON_OFF(db.autoOpen)))
    elseif cmd == "minimap" then
        if l == "on" or l == "off" then NS.SetMinimapButtonShown(l == "on") end
        NS.Print(format(L["minimap button: %s"], ON_OFF(NS.IsMinimapButtonShown())))
    elseif cmd == "dock" then
        db.docked = true
        if NS.Dock then NS.Dock() end
    elseif cmd == "hook" then
        if l == "on" or l == "off" then
            db.hookSearch = (l == "on")
            NS.Print(format(L["search hook %s; applies after /reload."], ON_OFF(db.hookSearch)))
        else
            NS.Print(format(L["search hook: %s"], ON_OFF(db.hookSearch ~= false)))
        end
    elseif cmd == "diag" then
        if l == "limpar" or l == "clear" then
            D.Clear()
            NS.Print(L["diagnostics cleared."])
        elseif l == "snap" then
            D.Snapshot("manual")
            Trace("SNAP", "retrato manual; estado=%s", D.str(D.State()))
            NS.Print(L["snapshot saved. /reload to write it to disk."])
        else
            D.PrintSummary()
        end
    elseif cmd == "debug" then
        db.debug = (l == "on")
        NS.Print(format(L["debug: %s"], db.debug and L["on (trace in chat)"] or L["off"]))
    else
        for _, line in ipairs(HELP) do print(L[line]) end
    end
end
SlashCmdList.GRUPOFACIL = D.Wrap("/gf", SlashCmdList.GRUPOFACIL)
