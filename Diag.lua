-- GrupoFacil: diagnóstico. Carrega antes do resto.
--
-- Guarda em GrupoFacilDB.diag (gravado no disco no /reload, no logout ou ao sair do jogo):
--  * errors   : erros do addon, sem repetir, com stack, contexto (evento/botão), estado e contagem
--  * trace    : rastro dos últimos eventos relevantes (buscas, resultados, envios, bloqueios)
--  * snapshot : retrato do ambiente no login (build, APIs presentes, taint, addons de LFG)
--  * samples  : forma dos dados que o servidor mandou (tipos, nil, SECRET), sem nomes de jogadores
-- Relatório fora do jogo: grupofacil_tools/gf_report.lua.

local ADDON, NS = ...
local D = {}
NS.D = D
local L = NS.L

local MAX_TRACE = 500
local MAX_ERRORS = 60
local MAX_SAMPLES = 8
local floor, format, tostring, type, pairs, ipairs, select = math.floor, string.format, tostring, type, pairs, ipairs, select

local pending = {}      -- registros feitos antes do SavedVariables carregar
local ctx = {}          -- pilha de contexto: evento ou script em execução
local erroredThisSession = false
D.session = 0

local function isSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) == true
end

local function store()
    local db = GrupoFacilDB
    if type(db) ~= "table" then return nil end
    local d = db.diag
    if type(d) ~= "table" then d = {}; db.diag = d end
    d.trace = d.trace or {}
    d.errors = d.errors or {}
    d.samples = d.samples or {}
    d.snapshot = d.snapshot or {}
    return d
end

-- Converte qualquer valor em texto curto, sem tocar em valores secretos.
local function str(v, depth)
    if isSecret(v) then return "<SECRET>" end
    local t = type(v)
    if t == "string" then return v end
    if t ~= "table" then return tostring(v) end
    depth = depth or 0
    if depth > 1 then return "{...}" end
    if canaccesstable and not canaccesstable(v) then return "<tabela inacessível>" end
    local parts, n = {}, 0
    for k, x in pairs(v) do
        n = n + 1
        if n > 12 then parts[#parts + 1] = "..."; break end
        parts[#parts + 1] = tostring(k) .. "=" .. str(x, depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end
D.str = str

local function now()
    local t = GetTime and GetTime() or 0
    return floor(t * 1000 + 0.5) / 1000
end

local function push(list, item, cap)
    list[#list + 1] = item
    while #list > cap do table.remove(list, 1) end
end

------------------------------------------------------------------------
-- rastro
------------------------------------------------------------------------
function D.Trace(kind, ...)
    local n = select("#", ...)
    local msg
    if n == 0 then
        msg = ""
    elseif n == 1 then
        msg = str((...))
    else
        local ok, r = pcall(format, ...)
        msg = ok and r or str({ ... })
    end
    local entry = { s = D.session, t = now(), d = date("%H:%M:%S"), k = kind, m = msg }
    local d = store()
    if d then push(d.trace, entry, MAX_TRACE) else push(pending, entry, MAX_TRACE) end
    if GrupoFacilDB and GrupoFacilDB.debug then
        print(format("|cff888888GF %s|r %s %s", entry.d, kind, msg))
    end
end

------------------------------------------------------------------------
-- estado atual (vai junto com cada erro)
------------------------------------------------------------------------
function D.State()
    local db = GrupoFacilDB or {}
    local f = db.filters or {}
    local s = {
        v = NS.VERSION,
        ctx = table.concat(ctx, ">"),
        searching = NS.searching,
        stale = NS.stale,
        results = NS.order and #NS.order or nil,
        lockdown = NS.InLockdown and NS.InLockdown() or nil,
        inGroup = IsInGroup and IsInGroup() or nil,
        combat = InCombatLockdown and InCombatLockdown() or nil,
        sendMode = db.sendMode,
        hookSearch = db.hookSearch ~= false,
        mode = f.mode, minLevel = f.minLevel, maxLevel = f.maxLevel, sort = f.sort,
        panel = _G.GrupoFacilFrame and _G.GrupoFacilFrame:IsShown() or false,
        lfgShown = _G.LFGParentFrame and _G.LFGParentFrame:IsShown() or false,
    }
    if NS.lastSearch then
        s.lastCategory = NS.lastSearch.category
        s.lastActivities = NS.lastSearch.activities and #NS.lastSearch.activities or 0
    end
    return s
end

------------------------------------------------------------------------
-- erros
------------------------------------------------------------------------
local function errorKey(msg)
    -- tira endereços e números variáveis para agrupar o mesmo erro
    local first = msg:match("^[^\n]*") or msg
    first = first:gsub("0x%x+", "0x"):gsub("table: %x+", "table")
    return first
end

function D.OnError(err)
    local msg = isSecret(err) and "<erro com valor SECRET>" or tostring(err)
    local stack = debugstack and debugstack(2, 20, 0) or ""
    local here = table.concat(ctx, ">")
    local key = here .. " | " .. errorKey(msg)
    local d = store()
    local list = d and d.errors or pending
    local found
    for _, e in ipairs(list) do
        if e.key == key then found = e; break end
    end
    if found then
        found.count = (found.count or 1) + 1
        found.last = date("%Y-%m-%d %H:%M:%S")
        found.lastSession = D.session
    else
        push(list, {
            key = key, msg = msg, stack = stack, ctx = here, count = 1,
            first = date("%Y-%m-%d %H:%M:%S"), last = date("%Y-%m-%d %H:%M:%S"),
            session = D.session, lastSession = D.session, state = D.State(),
        }, MAX_ERRORS)
    end
    -- No rastro, só as primeiras repetições (e depois 1 a cada 25) para não afogar os outros eventos.
    local count = found and found.count or 1
    if count <= 3 or count % 25 == 0 then
        D.Trace("ERRO", "[%dx] %s | %s", count, here, (msg:match("^[^\n]*") or msg))
    end
    if not erroredThisSession then
        erroredThisSession = true
        print("|cff33ccffGrupoFacil|r: |cffff5555" .. L["logged an error."] .. "|r " .. L["Use /gf diag to see it; then /reload to save the report."])
    end
    return msg
end

-- Executa fn protegido. tag (opcional) entra no contexto do erro.
function D.Call(tag, fn, ...)
    local n, args = select("#", ...), { ... }
    if tag then ctx[#ctx + 1] = tag end
    local function pack(...) return { n = select("#", ...), ... } end
    local r = pack(xpcall(function() return fn(unpack(args, 1, n)) end, D.OnError))
    if tag then ctx[#ctx] = nil end
    return unpack(r, 1, r.n)
end

-- Devolve uma função protegida para usar em SetScript/HookScript/eventos.
function D.Wrap(tag, fn)
    return function(...) return select(2, D.Call(tag, fn, ...)) end
end

------------------------------------------------------------------------
-- retrato do ambiente
------------------------------------------------------------------------
local API_CHECKS = {
    "C_LFGList.Search", "C_LFGList.GetFilteredSearchResults", "C_LFGList.GetSearchResults",
    "C_LFGList.GetSearchResultInfo", "C_LFGList.GetSearchResultPlayerInfo", "C_LFGList.GetSearchResultLeaderInfo",
    "C_LFGList.GetSearchResultMemberCounts", "C_LFGList.GetActivityInfoTable",
    "C_ChatInfo.SendChatMessage", "C_ChatInfo.InChatMessagingLockdown", "SendChatMessage",
    "C_PartyInfo.InviteUnit", "ChatFrameUtil.SendTell", "ChatFrameUtil.SendTellWithMessage", "ChatFrame_SendTell",
    "C_ClassTalents.GetActiveConfigID", "C_Traits.GetConfigInfo", "C_Traits.GetGroupDisplayInfoByTreeID",
    "C_Traits.GetGroupCurrencyInfo", "GetTalentTabInfo",
    "issecretvalue", "canaccesstable", "canaccessvalue", "issecurevariable", "Ambiguate",
    "LFGUtil_GetFilteredActivities", "LFGVanilla_ToggleFrame", "LFGBrowse_DoSearch",
    "CLASS_ICON_TCOORDS", "RAID_CLASS_COLORS", "LOCALIZED_CLASS_NAMES_MALE",
}

local function resolve(path)
    local cur = _G
    for part in path:gmatch("[^%.]+") do
        if type(cur) ~= "table" then return nil end
        cur = cur[part]
    end
    return cur
end

-- issecurevariable diz se uma variável foi contaminada (taint) e por quem.
local function taintOf(tbl, key)
    if not (issecurevariable and tbl) then return "n/d" end
    local ok, secure, by = pcall(issecurevariable, tbl, key)
    if not ok then return "erro" end
    return secure and "seguro" or ("TAINT:" .. tostring(by))
end

function D.TaintReport()
    local browse = _G.LFGBrowseFrame
    return {
        ["C_LFGList.Search"] = taintOf(C_LFGList, "Search"),
        ["LFGBrowseFrame.searching"] = browse and taintOf(browse, "searching") or "sem frame",
        ["LFGBrowseFrame.results"] = browse and taintOf(browse, "results") or "sem frame",
        ["LFGBrowseFrame.totalResults"] = browse and taintOf(browse, "totalResults") or "sem frame",
        ["LFGBrowse_DoSearch"] = taintOf(_G, "LFGBrowse_DoSearch"),
    }
end

function D.Snapshot(reason)
    local d = store()
    if not d then return end
    local version, build, buildDate, toc = "?", "?", "?", "?"
    if GetBuildInfo then version, build, buildDate, toc = GetBuildInfo() end
    local apis = {}
    for _, path in ipairs(API_CHECKS) do apis[path] = type(resolve(path)) end
    local addons = {}
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        for _, name in ipairs({ "Blizzard_GroupFinder_VanillaStyle", "OakLFGSorterForever", "LFGForever",
            "NaowhForever_QoL", "ForeverDungeonJournal", "LFGBulletinBoard" }) do
            local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, name)
            addons[name] = ok and loaded or false
        end
    end
    d.snapshot[reason] = {
        when = date("%Y-%m-%d %H:%M:%S"), session = D.session, addonVersion = NS.VERSION,
        client = format("%s (%s) %s toc=%s", tostring(version), tostring(build), tostring(buildDate), tostring(toc)),
        project = tostring(WOW_PROJECT_ID), locale = GetLocale and GetLocale() or "?",
        player = format("%s %s lvl %s", tostring(select(2, UnitClass("player"))), tostring(NS.PlayerSpec and NS.PlayerSpec() or "?"), tostring(UnitLevel("player"))),
        apis = apis, addons = addons, taint = D.TaintReport(),
        lockdown = NS.InLockdown and NS.InLockdown() or nil,
    }
end

------------------------------------------------------------------------
-- forma dos dados recebidos (tipos, nil e SECRET; sem nomes)
------------------------------------------------------------------------
local INFO_FIELDS = { "numMembers", "hasSelf", "isDelisted", "leaderName", "age", "activityIDs", "generalPlaystyle", "newPlayerFriendly" }
local PLAYER_FIELDS = { "name", "level", "classFilename", "className", "specName", "assignedRole", "lfgRoles", "areaName", "isLeader" }
local SHOW_VALUE = { numMembers = true, hasSelf = true, isDelisted = true, age = true, level = true,
    classFilename = true, specName = true, assignedRole = true, generalPlaystyle = true, newPlayerFriendly = true, isLeader = true }

local function shape(t, fields)
    if t == nil then return "nil" end
    if isSecret(t) then return "SECRET(tabela)" end
    if type(t) ~= "table" then return type(t) end
    if canaccesstable and not canaccesstable(t) then return "inacessível" end
    local out = {}
    for _, k in ipairs(fields) do
        local v = t[k]
        if isSecret(v) then out[#out + 1] = k .. "=SECRET"
        elseif v == nil then out[#out + 1] = k .. "=nil"
        elseif SHOW_VALUE[k] then out[#out + 1] = k .. "=" .. str(v)
        elseif type(v) == "table" then out[#out + 1] = k .. "=" .. ((k == "lfgRoles" or k == "activityIDs") and str(v) or "table")
        else out[#out + 1] = k .. "=" .. type(v) end
    end
    return table.concat(out, " ")
end

-- Guarda a forma dos primeiros resultados de cada busca.
function D.Sample(id, info, player, counts)
    local d = store()
    if not d then return end
    push(d.samples, {
        when = date("%H:%M:%S"), session = D.session, id = str(id),
        info = shape(info, INFO_FIELDS),
        player = shape(player, PLAYER_FIELDS),
        counts = counts == nil and "nil" or str(counts),
    }, MAX_SAMPLES)
end

------------------------------------------------------------------------
-- busca nativa presa
------------------------------------------------------------------------
-- Depois de uma busca, confere se a janela da Blizzard ficou presa em "Searching..."
-- (só lê o campo; nunca escreve).
function D.ProbeNativeSearch(delay)
    if not C_Timer then return end
    C_Timer.After(delay or 12, function()
        local browse = _G.LFGBrowseFrame
        if not browse then return end
        local searching = browse.searching
        if isSecret(searching) then
            D.Trace("NATIVA", "LFGBrowseFrame.searching é SECRET")
        elseif searching == true then
            D.Trace("NATIVA", "LFGBrowseFrame presa em Searching há %ds; taint=%s", delay or 12, str(D.TaintReport()))
            D.OnError("busca nativa presa em Searching (LFGBrowseFrame.searching=true)")
        end
    end)
end

------------------------------------------------------------------------
-- início e comandos
------------------------------------------------------------------------
function D.Init()
    local d = store()
    d.session = (d.session or 0) + 1
    D.session = d.session
    for _, entry in ipairs(pending) do
        if entry.key then push(d.errors, entry, MAX_ERRORS) else entry.s = D.session; push(d.trace, entry, MAX_TRACE) end
    end
    wipe(pending)
    D.Trace("SESSAO", "início da sessão %d, versão %s", D.session, tostring(NS.VERSION))
end

function D.PrintSummary()
    local d = store()
    if not d then return end
    local errs = d.errors
    print("|cff33ccffGrupoFacil diag|r: " .. format(L["session %d, %d distinct errors, %d trace lines."], D.session, #errs, #d.trace))
    for i = math.max(1, #errs - 4), #errs do
        local e = errs[i]
        print(format("  |cffff5555[%dx]|r %s |cff888888(%s, %s)|r", e.count or 1, (e.msg or ""):match("^[^\n]*") or "", e.ctx or "", e.last or ""))
    end
    print("  " .. L["latest events:"])
    for i = math.max(1, #d.trace - 7), #d.trace do
        local t = d.trace[i]
        print(format("  |cff888888%s|r %s %s", t.d or "", t.k or "", t.m or ""))
    end
    print("  " .. L["To have it analyzed: /reload (writes the file)."])
end

function D.Clear()
    local d = store()
    if not d then return end
    wipe(d.errors); wipe(d.trace); wipe(d.samples)
    D.Trace("SESSAO", "diagnóstico limpo")
end
