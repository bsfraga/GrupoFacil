-- GrupoFacil: integração do canal de bug report (BugChannel.lua, protocolo 1, prefixo GFBUG).
-- O jogador escreve o report (janela em BugUI.lua ou /gf bug <texto>); ele fica guardado no
-- SavedVariables da conta até um admin confirmar que gravou em disco. O admin recebe na caixa
-- de entrada (/gf bugs) e registra o desfecho em BugResolutions.lua ou pelo jogo.

local ADDON, NS = ...
local L = NS.L
local format = string.format

------------------------------------------------------------------------
-- ÚNICO lugar a editar: personagens admin (sem o reino), iguais nos addons do autor.
-- Nome entre < > é marcador: enquanto não houver nome real, ninguém é admin e os reports
-- ficam guardados no cliente de cada jogador até uma versão com os nomes chegar.
------------------------------------------------------------------------
NS.BUG_ADMINS = NS.BUG_ADMINS or { "<ADMIN_1>", "<ADMIN_2>" }

NS.BUG_PREFIX = "GFBUG"
NS.BUG_NOTE_MAX = 1000     -- caracteres do texto escrito pelo jogador
local LOG_LINES = 40       -- últimas linhas do rastro do /gf diag
local ERR_LINES = 5
local BODY_BUDGET = 7800   -- o módulo corta em 8000; o rastro entra até aqui

local BC -- ns.BugChannel, depois do Init

local function realAdmins()
    local out = {}
    for _, n in ipairs(NS.BUG_ADMINS or {}) do
        if type(n) == "string" and n ~= "" and not n:find("^<") then out[#out + 1] = n end
    end
    return out
end
NS.BugAdmins = realAdmins

function NS.IsBugAdmin()
    local me = (UnitName("player") or ""):lower()
    for _, a in ipairs(realAdmins()) do if a:lower() == me then return true end end
    return false
end

-- Report com corpo em texto: uma chave por linha, depois blocos livres (spec §4.3).
local function oneLine(s) return (tostring(s or ""):gsub("\r", ""):gsub("\n", "\\n")) end

local function collect(note)
    if type(note) ~= "table" then note = { text = tostring(note or ""), kind = "bug", diag = true } end
    local _, build, _, toc = GetBuildInfo()
    local db = GrupoFacilDB or {}
    local f = db.filters or {}
    local lines = {
        "addon=" .. ADDON,
        "ver=" .. tostring(NS.VERSION),
        "toc=" .. tostring(toc), "build=" .. tostring(build),
        "locale=" .. tostring(GetLocale()),
        "lang=" .. tostring(NS.Language and NS.Language() or "?"),
        -- no Forever GetRealmName() vem vazio (visto em 2026-11-23): sem o "-" pendurado
        "char=" .. tostring(UnitName("player")) .. (((GetRealmName() or "") ~= "") and ("-" .. GetRealmName()) or ""),
        "class=" .. tostring(select(2, UnitClass("player"))), "level=" .. tostring(UnitLevel("player")),
        "zone=" .. tostring(GetZoneText() or "") .. "/" .. tostring(GetSubZoneText() or ""),
        "kind=" .. tostring(note.kind or "bug"),
        "note=" .. oneLine(note.text),
    }
    if note.diag ~= false then
        lines[#lines + 1] = format("settings=mode=%s sort=%s send=%s hook=%s docked=%s compact=%s auto=%s results=%s lockdown=%s",
            tostring(f.mode), tostring(f.sort), tostring(db.sendMode), tostring(db.hookSearch ~= false), tostring(db.docked),
            tostring(db.compact == true), tostring(db.autoOpen), tostring(NS.order and #NS.order or 0),
            tostring(NS.InLockdown and NS.InLockdown() or false))
        local d = db.diag or {}
        local errs = d.errors or {}
        if #errs > 0 then
            lines[#lines + 1] = "---errors"
            for i = math.max(1, #errs - ERR_LINES + 1), #errs do
                local e = errs[i]
                lines[#lines + 1] = format("[%dx] %s @ %s (%s)", e.count or 1, oneLine((e.msg or ""):match("^[^\n]*")), tostring(e.ctx or ""), tostring(e.last or ""))
            end
        end
        lines[#lines + 1] = "---log"
        local head = table.concat(lines, "\n")
        local trace, log, size = d.trace or {}, {}, #head
        for i = #trace, math.max(1, #trace - LOG_LINES + 1), -1 do
            local t = trace[i]
            local l = format("%s %s %s", tostring(t.d or ""), tostring(t.k or ""), oneLine(t.m))
            if size + #l + 1 > BODY_BUDGET then break end
            table.insert(log, 1, l)
            size = size + #l + 1
        end
        for _, l in ipairs(log) do lines[#lines + 1] = l end
    end
    return table.concat(lines, "\n") .. "\n"
end
NS.CollectBugBody = collect

------------------------------------------------------------------------
-- mensagens do módulo (em português no BugChannel.lua) no idioma do addon
------------------------------------------------------------------------
local SAY = {
    { "^report (%S+) guardado na caixa de entrada", function(id) return format(L["report %s saved in your own inbox (/reload to write it to disk)."], id) end },
    { "^report (%S+) na fila", function(id) return format(L["report %s queued. It goes to the author the next time you are both online."], id) end },
    { "^o admin usa o protocolo (%S+):", function() return L["the author uses a newer bug report version: update GrupoFacil."] end },
    { "^report (%S+) recebido e salvo pelo admin", function(id) return format(L["report %s was received and saved by the author. Thank you!"], id) end },
    { "^seu report (%S+): (%S+) ?(.*)$", function(id, status, note)
        return format(L["your report %s: %s"], id, NS.BugStatusText(status) .. ((note and note ~= "") and (" - " .. note) or ""))
    end },
}
local function say(m)
    m = tostring(m)
    local text = m
    for _, s in ipairs(SAY) do
        local a, b, c = m:match(s[1])
        if a then text = s[2](a, b, c); break end
    end
    if NS.Print then NS.Print(text) end
    if NS.D then NS.D.Trace("BUG", "%s", (m:gsub("|", "||"))) end
    if NS.RefreshBugUI then NS.RefreshBugUI() end
end

local STATUS_KEY = { fixed = "fixed", wontfix = "won't fix", dup = "duplicate", triaged = "triaged", new = "new" }
function NS.BugStatusText(status) return L[STATUS_KEY[status] or tostring(status)] end

------------------------------------------------------------------------
-- início (chamado pelo ADDON_LOADED do Core, depois do SavedVariables existir)
------------------------------------------------------------------------
function NS.InitBugReports()
    BC = NS.BugChannel
    if not BC or NS.bugReady then return end
    GrupoFacilDB = GrupoFacilDB or {}
    local admins = realAdmins()
    NS.bugAdmin = NS.IsBugAdmin()
    -- carregou do disco: o que estava pendente de gravação já foi gravado
    GrupoFacilDB.bugPendingSave = nil
    -- o que já estava na caixa ao carregar veio do disco (mesma regra do rt.durable do módulo)
    NS.bugDurable = {}
    for id in pairs(type(GrupoFacilDB.inbox) == "table" and GrupoFacilDB.inbox or {}) do NS.bugDurable[id] = true end
    BC.Init({
        prefix = NS.BUG_PREFIX, addon = ADDON, admins = admins,
        db = function() return GrupoFacilDB end,
        collect = collect,
        resolutions = function() return GF_BugResolutions end,
        say = say,
        onReceived = function(e)
            NS.Print(format(L["new bug report from %s (%s). Type /gf bugs to read it."], tostring(e.from), tostring(e.id)))
            if NS.D then NS.D.Trace("BUG", "report recebido (%d bytes)", #(e.body or "")) end
            if NS.RefreshBugUI then NS.RefreshBugUI() end
        end,
    })
    NS.bugReady = true
    if NS.D then NS.D.Trace("BUG", "canal %s pronto: admin=%s admins=%d", NS.BUG_PREFIX, tostring(NS.bugAdmin), #admins) end
end

------------------------------------------------------------------------
-- dados para a janela e o chat
------------------------------------------------------------------------
-- Reports do jogador, do mais novo ao mais velho.
function NS.MyBugReports()
    local out = {}
    local db = GrupoFacilDB
    for _, e in pairs(db and db.bugs or {}) do out[#out + 1] = e end
    table.sort(out, function(a, b) if a.ts ~= b.ts then return a.ts > b.ts end return a.id > b.id end)
    return out
end

-- Estado de um report do jogador, em texto para a interface.
function NS.BugStateText(e)
    if e.resolved then
        local r = e.resolved
        return NS.BugStatusText(r.status) .. ((r.note and r.note ~= "") and (": " .. r.note) or "")
    end
    if e.state == "queued" then
        if (e.tries or 0) > 0 then return format(L["waiting for the author (try %d)"], e.tries + 1) end
        return L["waiting for the author to be online"]
    elseif e.state == "sent" then return L["sending..."]
    elseif e.state == "received" then return L["received; waiting for the author to save it"]
    elseif e.state == "done" then return L["delivered"] end
    return tostring(e.state)
end

-- primeira linha do texto escrito (para listas)
function NS.BugNoteOf(body)
    local n = tostring(body or ""):match("\nnote=([^\n]*)") or tostring(body or ""):match("^note=([^\n]*)") or ""
    return (n:gsub("\\n", " "))
end
-- corta em n caracteres sem partir um caractere acentuado (UTF-8) ao meio
function NS.Utf8Sub(str, n)
    str = tostring(str or "")
    local count, i = 0, 1
    while i <= #str do
        count = count + 1
        if count > n then return str:sub(1, i - 1) end
        local b = str:byte(i)
        i = i + (b >= 240 and 4 or b >= 224 and 3 or b >= 192 and 2 or 1)
    end
    return str
end
-- trecho do texto para as listas: o corpo some depois de entregue, o trecho fica
function NS.BugSnippetOf(e)
    if e.snip and e.snip ~= "" then return e.snip end
    return e.body and NS.BugNoteOf(e.body) or ""
end
function NS.BugKindOf(body) return tostring(body or ""):match("\nkind=([^\n]*)") or "bug" end

-- Caixa de entrada do admin. status = nil (todos) ou "new"... Mais novos primeiro.
function NS.BugInbox(status)
    local out = {}
    local db = GrupoFacilDB
    for _, e in pairs(db and db.inbox or {}) do
        if not status or e.status == status then out[#out + 1] = e end
    end
    table.sort(out, function(a, b) if a.recvAt ~= b.recvAt then return a.recvAt > b.recvAt end return a.id > b.id end)
    return out
end

-- Quantos itens da caixa ainda não passaram por um /reload (o jogador não apaga esses).
function NS.BugNotOnDisk()
    local n = 0
    local durable = NS.bugDurable or {}
    for id in pairs(GrupoFacilDB and GrupoFacilDB.inbox or {}) do
        if not durable[id] then n = n + 1 end
    end
    return n
end

-- Acha um id pelo começo (o id inteiro é longo para digitar).
local function findId(tbl, s)
    if not s or s == "" then return nil end
    if tbl[s] then return s end
    local hit
    for id in pairs(tbl) do
        if id:sub(1, #s) == s then
            if hit then return nil, "ambiguous" end
            hit = id
        end
    end
    return hit
end
NS.FindBugId = findId

-- Cria e enfileira um report. Devolve o id ou nil e o motivo.
function NS.SubmitBug(text, kind, includeDiag)
    if not NS.bugReady then return nil, L["the bug channel is not ready"] end
    text = tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil, L["write what happened first"] end
    local ok, id, why = NS.GuardTag("BugChannel.Report", NS.BugChannel.Report,
        { text = text:sub(1, NS.BUG_NOTE_MAX * 4), kind = kind or "bug", diag = includeDiag ~= false })
    if not ok then return nil, L["could not create the report (see /gf diag)"] end
    if not id then return nil, why == "fila cheia" and L["too many reports waiting; wait until the author receives them"] or tostring(why) end
    GrupoFacilDB.bugPendingSave = true
    local e = GrupoFacilDB.bugs and GrupoFacilDB.bugs[id]
    if e then e.snip = NS.Utf8Sub((text:gsub("%s+", " ")), 60) end
    if NS.D then NS.D.Trace("BUG", "report criado (%s, %d caracteres)", tostring(kind or "bug"), #text) end
    if NS.RefreshBugUI then NS.RefreshBugUI() end
    return id
end

-- Desfecho dado pelo admin (manda F ao jogador).
function NS.ResolveBug(id, status, note)
    if not NS.bugReady or not NS.bugAdmin then return false end
    note = note and tostring(note):gsub("^%s+", ""):gsub("%s+$", "") or nil
    if note == "" then note = nil end
    local ok, r = NS.GuardTag("BugChannel.Resolve", NS.BugChannel.Resolve, id, status, note)
    if NS.RefreshBugUI then NS.RefreshBugUI() end
    return ok and r
end

-- Texto de todos os reports novos, para colar numa conversa com o Claude.
function NS.BugExportText(status)
    local parts = {}
    local list = NS.BugInbox(status)
    table.sort(list, function(a, b) return a.recvAt < b.recvAt end)
    for _, e in ipairs(list) do
        parts[#parts + 1] = format("=== %s from=%s recvAt=%s status=%s", e.id, tostring(e.from), date("%Y-%m-%d %H:%M", e.recvAt), tostring(e.status))
        parts[#parts + 1] = tostring(e.body or "")
    end
    return table.concat(parts, "\n")
end

------------------------------------------------------------------------
-- /gf bug e /gf bugs
------------------------------------------------------------------------
local function firstUse()
    local db = GrupoFacilDB
    if db.bugIntroSeen then return end
    db.bugIntroSeen = true
    NS.Print(L["your text goes to the author of GrupoFacil. It stays saved on your computer until the author confirms they got it."])
end

local function printMine()
    local list = NS.MyBugReports()
    if #list == 0 then NS.Print(L["you have no bug reports."]) return end
    NS.Print(format(L["your bug reports (%d):"], #list))
    for i = 1, math.min(#list, 15) do
        local e = list[i]
        local snip = NS.BugSnippetOf(e)
        print(format("  %s  %s  %s%s", e.id, date("%Y-%m-%d", e.ts), NS.BugStateText(e),
            snip ~= "" and ("  |cff777777" .. NS.Utf8Sub(snip, 40):gsub("|", "||") .. "|r") or ""))
    end
end

local function printInbox(status)
    local list = NS.BugInbox(status)
    NS.Print(format(L["bug reports: %d (new: %d). /gf bugs show <id>"], #NS.BugInbox(), #NS.BugInbox("new")))
    for i = 1, math.min(#list, 20) do
        local e = list[i]
        print(format("  %s  %s  %s  %s", e.id:sub(1, 8), tostring(e.from), NS.BugStatusText(e.status), (NS.Utf8Sub(NS.BugNoteOf(e.body), 60):gsub("|", "||"))))
    end
end

local RESOLVE = { fix = "fixed", fixed = "fixed", wontfix = "wontfix", dup = "dup", triage = "triaged", triaged = "triaged" }

function NS.BugCommand(cmd, rest)
    rest = rest or ""
    local sub, arg = rest:match("^%s*(%S*)%s*(.-)%s*$")
    local lsub = (sub or ""):lower()
    if not NS.bugReady then NS.Print(L["the bug channel is not ready"]) return end
    if cmd == "bug" then
        if rest == "" then
            if NS.OpenBugReport then NS.OpenBugReport() end
        elseif lsub == "list" or lsub == "lista" then
            printMine()
        else
            firstUse()
            local id, why = NS.SubmitBug(rest, "bug", true)
            if not id then NS.Print(format(L["report not created: %s."], why)) end
        end
        return
    end
    -- bugs: só para o admin
    if not NS.bugAdmin then NS.Print(L["only the addon's author receives bug reports. To send one: /gf bug"]) return end
    if lsub == "" then
        if NS.OpenBugInbox then NS.OpenBugInbox() else printInbox() end
    elseif lsub == "list" or lsub == "all" then
        printInbox(nil)
    elseif lsub == "new" then
        printInbox("new")
    elseif lsub == "show" then
        local id, amb = findId(GrupoFacilDB.inbox, arg)
        local e = id and GrupoFacilDB.inbox[id]
        if not e then NS.Print(amb and L["more than one report starts like that; type more of the id."] or format(L["no report with id %s."], arg)) return end
        NS.Print(format("%s  %s  %s  %s", e.id, tostring(e.from), date("%Y-%m-%d %H:%M", e.recvAt), NS.BugStatusText(e.status)))
        for line in (tostring(e.body or "") .. "\n"):gmatch("(.-)\n") do print("  " .. line:gsub("|", "||")) end
    elseif lsub == "export" then
        if NS.OpenBugInbox then NS.OpenBugInbox("export") else NS.Print(NS.BugExportText("new")) end
    elseif RESOLVE[lsub] then
        local idText, note = arg:match("^(%S+)%s*(.-)$")
        local id, amb = findId(GrupoFacilDB.inbox, idText)
        if not id then NS.Print(amb and L["more than one report starts like that; type more of the id."] or format(L["no report with id %s."], tostring(idText))) return end
        NS.ResolveBug(id, RESOLVE[lsub], note)
        NS.Print(format(L["report %s marked as %s. The player is told the next time you are both online."], id, NS.BugStatusText(RESOLVE[lsub])))
    elseif lsub == "flush" or lsub == "save" then
        if NS.ShowReloadPrompt then NS.ShowReloadPrompt(L["Reload the interface to write the bug reports to disk? Players are told only after that."]) end
    elseif lsub == "accept" then
        local v = arg:lower()
        if v == "on" or v == "off" then GrupoFacilDB.acceptReports = (v == "on") end
        NS.Print(format(L["accepting new reports: %s"], (GrupoFacilDB.acceptReports ~= false) and L["on"] or L["off"]))
        if NS.RefreshBugUI then NS.RefreshBugUI() end
    else
        NS.Print(L["/gf bugs [new | show <id> | export | fix|wontfix|dup|triage <id> [note] | flush | accept on|off]"])
    end
end
