-- Idiomas: toda chave usada existe em cada língua, os formatos (%d, %s, {var}) batem,
-- o espanhol latino herda do espanhol e cada língua desenha tudo sem erro.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local LANGS = { "pt", "es", "mx", "de", "fr" }
local SOURCES = { "Core.lua", "Diag.lua", "UI.lua", "Options.lua", "Minimap.lua", "Onboarding.lua", "BugReport.lua", "BugUI.lua", "BugChannel.lua", "Quest.lua", "QuestUI.lua" }

local function readFile(p)
    local f = assert(io.open(H.ROOT .. "/" .. p, "rb"))
    local s = f:read("*a"); f:close(); return s
end
local function unescape(s) return (s:gsub("\\(.)", { n = "\n", t = "\t", ["\\"] = "\\", ['"'] = '"' })) end

-- chaves literais L["..."] do código
local function literalKeys()
    local keys = {}
    for _, p in ipairs(SOURCES) do
        local s = readFile(p)
        for k in s:gmatch('L%[%s*"(.-[^\\])"%s*%]') do keys[unescape(k)] = p end
    end
    return keys
end

-- tabelas de tradução, já carregadas num cliente
local function locales()
    local w = H.world()
    local c = H.login(w)
    return H.ns(c).LOCALES, c
end

-- sequência de especificadores de formato e de variáveis {x}
local function shape(s)
    local out = {}
    for spec in s:gsub("%%%%", ""):gmatch("%%[%-%d%.]*[dsfxq]") do out[#out + 1] = spec:sub(-1) end
    local vars = {}
    for v in s:gmatch("{(%a+)}") do vars[#vars + 1] = v end
    table.sort(vars)
    return table.concat(out, ",") .. "|" .. table.concat(vars, ",")
end

-- botões visíveis que saem da própria janela (texto traduzido mais longo empurra o layout)
local function overflow(c, winName)
    local win = c.env[winName]
    if not (win and c.ui.visible(win)) then return {} end
    local wr = c.ui.rect(win)
    local out = {}
    local function walk(f)
        for _, ch in ipairs(c.ui.state(f).children or {}) do
            local st = c.ui.state(ch)
            if c.ui.visible(ch) and (st.kind == "Button" or st.kind == "CheckButton" or st.kind == "EditBox") then
                local r = c.ui.rect(ch)
                if r and (r.l < wr.l - 2 or r.r > wr.r + 2 or r.t > wr.t + 2 or r.b < wr.b - 2) then
                    out[#out + 1] = winName .. ": " .. tostring(c:text(ch) or st.kind)
                end
            end
            walk(ch)
        end
    end
    walk(win)
    return out
end

-- widgets e textos visíveis que se sobrepõem dentro da janela (ex.: botão por cima de um rótulo traduzido)
local function overlaps(c, winName)
    local win = c.env[winName]
    if not (win and c.ui.visible(win)) then return {} end
    local items = {}
    local function ancestor(a, b)
        local s = c.ui.state(b)
        while s and s.parent do
            if s.parent == a then return true end
            s = c.ui.state(s.parent)
        end
        return false
    end
    -- camadas sobrepostas de propósito (faixa do tour, linha de exemplo) ficam bem acima no nível
    local function lvl(f)
        local st = c.ui.state(f)
        if st.level then return st.level end
        if st.kind == "FontString" or not st.parent then return st.parent and lvl(st.parent) or 1 end
        return lvl(st.parent) + 1
    end
    local function ink(fs)
        local st = c.ui.state(fs)
        local r = c.ui.rect(fs)
        if not r or not st.text or st.text == "" then return nil end
        local tw = fs:GetStringWidth()
        local bw = r.r - r.l
        if tw < bw then
            local j = st.justifyH or "CENTER"
            if j == "LEFT" then r = { l = r.l, r = r.l + tw, t = r.t, b = r.b }
            elseif j == "RIGHT" then r = { l = r.r - tw, r = r.r, t = r.t, b = r.b }
            else local m = (r.l + r.r) / 2; r = { l = m - tw / 2, r = m + tw / 2, t = r.t, b = r.b } end
        end
        local h = fs:GetStringHeight()
        if h > 0 and h < r.t - r.b then
            local j = st.justifyV or "MIDDLE"
            if j == "TOP" then r.b = r.t - h elseif j == "BOTTOM" then r.t = r.b + h
            else local m = (r.t + r.b) / 2; r.t, r.b = m + h / 2, m - h / 2 end
        end
        return r
    end
    local function walk(f, inButton)
        local st = c.ui.state(f)
        for _, reg in ipairs(st.regions or {}) do
            local rs = c.ui.state(reg)
            if rs.kind == "FontString" and not inButton and c.ui.visible(reg) then
                local r = ink(reg)
                if r then items[#items + 1] = { o = reg, r = r, label = rs.text } end
            end
        end
        for _, ch in ipairs(st.children or {}) do
            local cs = c.ui.state(ch)
            if c.ui.visible(ch) then
                local btn = cs.kind == "Button" or cs.kind == "CheckButton" or cs.kind == "EditBox"
                if btn then
                    local r = c.ui.rect(ch)
                    if r then items[#items + 1] = { o = ch, r = r, label = tostring(c:text(ch) or cs.name or cs.kind) } end
                end
                walk(ch, inButton or (cs.kind == "Button" or cs.kind == "CheckButton"))
            end
        end
    end
    walk(win, false)
    local out = {}
    for i = 1, #items do
        for j = i + 1, #items do
            local a, b = items[i], items[j]
            local ow = math.min(a.r.r, b.r.r) - math.max(a.r.l, b.r.l)
            local oh = math.min(a.r.t, b.r.t) - math.max(a.r.b, b.r.b)
            if ow > 1 and oh > 1 and math.abs(lvl(a.o) - lvl(b.o)) < 10 and not ancestor(a.o, b.o) and not ancestor(b.o, a.o) then
                out[#out + 1] = winName .. ": [" .. a.label .. "] x [" .. b.label .. "]"
            end
        end
    end
    return out
end

-- uma sessão que passa por todas as telas, registrando cada chave pedida a L
local function exercise(lang, admin)
    local seen = {}
    local cfg = { beforeAddonLoaded = function(c, ns)
        if admin then ns.BUG_ADMINS = { "Jogador" } end
        local mt = getmetatable(ns.L)
        local orig = mt.__index
        mt.__index = function(t, k) seen[k] = true; return orig(t, k) end
    end }
    local w = H.world(cfg)
    H.sampleListings(w)
    -- grupos da zona de uma missão (janela de missões)
    w.lfg:add({ leader = "Zona", activityIDs = { 20 }, members = { { name = "Zona", level = 18, class = "PRIEST" },
        { name = "Z2", level = 18, class = "MAGE" } } })
    w.lfg:add({ leader = "Sozinho", activityIDs = { 20 }, members = { { name = "Sozinho", level = 18, class = "ROGUE" } } })
    local disk = w:diskFor("A")
    local c = H.login(w, { account = "A", level = 25 })
    H.db(c).language = lang
    c:reload()
    w:advance(8)
    H.search(w, c)
    w:advance(0.3)
    local ns = H.ns(c)
    local f = c.env.GrupoFacilFrame
    H.db(c).filters.mode = "all"; ns.Refresh("t"); w:advance(0.2)
    for _, child in ipairs({ f.list:GetChildren() }) do
        if c.ui.visible(child) and child.entry then c:hover(child); c:hover(child.b1); c:hover(child.b2) end
    end
    H.db(c).filters.mode = "groups"; ns.Refresh("t"); w:advance(0.2)
    H.db(c).filters.sort = "age"; ns.Refresh("t"); w:advance(0.2)
    H.db(c).filters.sort = "name"; ns.Refresh("t"); w:advance(0.2)
    for _, cmd in ipairs({ "/gf help", "/gf msg", "/gf mode", "/gf auto on", "/gf minimap", "/gf hook", "/gf blocked", "/gf unblock",
        "/gf unblock x", "/gf diag", "/gf diag snap", "/gf debug off", "/gf lang", "/gf spec", "/gf bug list" }) do c:slash(cmd) end
    local over = {}
    local function check(name)
        for _, x in ipairs(overflow(c, name)) do over[#over + 1] = x end
        for _, x in ipairs(overlaps(c, name)) do over[#over + 1] = x end
    end
    check("GrupoFacilFrame")
    -- grupos por missão: lupa, janela, pedido recebido, criar, missão concluída
    c:hover(f.tabDungeons); c:hover(f.tabQuests)
    c:addQuest({ id = 155, title = "The Defias Brotherhood", zone = "Westfall", level = 18, elite = true, size = 3, mapID = 1436 })
    w:advance(3)
    local mag = c:trackerMagnifier(155)
    c:hover(mag)
    c:click(mag)
    w:advance(1.5)
    ns.Quest.OnAddonMessage("GFQ", "J1 155 18 MAGE d The Defias Brotherhood", "WHISPER", "Pedinte Sobrenome")
    w:advance(0.3)
    local qf = c.env.GrupoFacilQuestFrame
    for _, child in ipairs({ qf.list:GetChildren() }) do
        if c.ui.visible(child) and child.entry then c:hover(child); c:hover(child.b1) end
    end
    for _, b in ipairs({ qf.search, qf.create, qf.dungeons, qf.autoInvite, qf.autoAccept, qf.magnifier }) do c:hover(b) end
    check("GrupoFacilQuestFrame")
    c:click(qf.create)
    w:advance(0.5)
    c:hover(qf.create)
    check("GrupoFacilQuestFrame")
    c:openQuestDetails(155)
    local fb = H.find(c, c.env.QuestMapFrame.DetailsFrame, ".", true)
    if fb then c:hover(fb) end
    ns.ShowQuestDone(155, "The Defias Brotherhood")
    for _, b in ipairs({ c.env.GrupoFacilQuestDone.leave, c.env.GrupoFacilQuestDone.remove, c.env.GrupoFacilQuestDone.later }) do c:hover(b) end
    check("GrupoFacilQuestDone")
    c:slash("/gf quests")
    c:slash("/gf options")
    check("GrupoFacilOptionsFrame")
    c:hover(c.env.GrupoFacilMinimapButton)
    c:slash("/gf tour")
    for _ = 1, 8 do
        local _, callout = ns.TourFrames()
        if callout and c.ui.visible(callout) then c:click(callout.next) end
    end
    c:slash("/gf news")
    check("GrupoFacilWhatsNew")
    -- uma página por versão: as outras também cabem
    local nf = c.env.GrupoFacilWhatsNew
    while nf.older:IsEnabled() do c:click(nf.older); check("GrupoFacilWhatsNew") end
    while nf.newer:IsEnabled() do c:click(nf.newer) end
    c:click(c.env.GrupoFacilWhatsNew.ack)
    c:click(c.env.GrupoFacilWhatsNew.close)
    c:slash("/gf bug")
    local bf = c.env.GrupoFacilBugFrame
    c:type(bf.note.box, "algo deu errado")
    c:click(bf.send)
    for _, k in ipairs(bf.kinds) do c:click(k) end
    w:advance(2)
    check("GrupoFacilBugFrame")
    if admin then
        c:slash("/gf bugs")
        c:slash("/gf bugs all")
        c:slash("/gf bugs list")
        local id = ns.MyBugReports()[1].id
        c:slash("/gf bugs show " .. id)
        H.ns(c).OpenBugInbox("all")
        w:advance(1.2)
        c:click(c.env.GrupoFacilBugInbox.rows[1]) -- com um report escolhido aparecem as ações
        w:advance(1.2)
        check("GrupoFacilBugInbox")
        c:slash("/gf bugs fix " .. id .. " ok")
        c:slash("/gf bugs flush")
    end
    return seen, c, over
end

describe("idiomas", function()
    it("toda chave literal do código existe em pt, es, de e fr", function()
        local LOC = locales()
        local missing = {}
        for k, file in pairs(literalKeys()) do
            for _, lang in ipairs({ "pt", "es", "de", "fr" }) do
                if rawget(LOC[lang], k) == nil then missing[#missing + 1] = lang .. ": " .. k .. "  (" .. file .. ")" end
            end
        end
        table.sort(missing)
        T.eq(#missing, 0, "faltam traduções:\n  " .. table.concat(missing, "\n  ", 1, math.min(#missing, 200)))
    end)

    it("traduções mantêm os mesmos %d/%s e {variáveis} da chave", function()
        local LOC = locales()
        local bad = {}
        for _, lang in ipairs(LANGS) do
            for k, v in pairs(LOC[lang]) do
                if type(v) ~= "string" then bad[#bad + 1] = lang .. ": valor não é texto: " .. k
                elseif shape(k) ~= shape(v) then bad[#bad + 1] = lang .. ": " .. k .. "  ->  " .. v end
            end
        end
        table.sort(bad)
        T.eq(#bad, 0, "formato diferente:\n  " .. table.concat(bad, "\n  ", 1, math.min(#bad, 30)))
    end)

    it("espanhol latino herda do espanhol e só sobrescreve o que muda", function()
        local LOC = locales()
        T.eq(LOC.mx["Hidden (%d)"], LOC.es["Hidden (%d)"])
        T.eq(rawget(LOC.mx, "Hidden (%d)"), nil)
        T.eq(LOC.mx["Guild: %s"], "Clan: %s")
    end)

    it("idioma do cliente escolhe o do addon; /gf lang troca e pede /reload pelo botão seguro", function()
        local w = H.world()
        local c = H.login(w, { locale = "esMX" })
        T.eq(H.ns(c).Language(), "mx")
        local b = H.login(w, { name = "Bruno", locale = "ptBR" })
        T.eq(H.ns(b).Language(), "pt")
        b:slash("/gf lang de")
        T.eq(H.db(b).language, "de")
        local prompt = b.env.GrupoFacilReloadButton -- já com o texto no idioma novo
        T.ok(prompt, "botão de recarregar")
        b:click(prompt)
        w:advance(1)
        T.eq(H.ns(b).Language(), "de")
        T.ok(H.find(b, b.env.GrupoFacilFrame, "^Spieler$") or H.find(b, b.env.GrupoFacilFrame, "Erneut suchen"), "janela em alemão")
        b:slash("/gf lang xx")
        T.has(b:chatLines(), "/gf lang")
        T.clean(b)
    end)

    for _, lang in ipairs(LANGS) do
        it("em " .. lang .. ": todas as telas, comandos e o tour pedem só chaves traduzidas, sem erro", function()
            local seen, c, over = exercise(lang, true)
            T.eq(#over, 0, lang .. ": botões fora da janela ou sobrepostos:\n  " .. table.concat(over, "\n  "))
            local LOC = H.ns(c).LOCALES
            local missing = {}
            for k in pairs(seen) do
                if type(k) == "string" and LOC[lang][k] == nil then missing[#missing + 1] = k end
            end
            table.sort(missing)
            T.eq(#missing, 0, lang .. " sem tradução (pedidas em tempo de execução):\n  " .. table.concat(missing, "\n  ", 1, math.min(#missing, 200)))
            T.clean(c)
        end)
    end

    it("em inglês nada falta e nada quebra", function()
        local _, c, over = exercise("en", true)
        T.eq(#over, 0, "en: botões fora da janela ou sobrepostos:\n  " .. table.concat(over, "\n  "))
        T.clean(c)
    end)
end)
