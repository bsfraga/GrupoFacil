-- Grupos por missão: a lupa na lista de objetivos e no quest log, a janela de missões,
-- o sussurro de addon entre quem usa o GrupoFacil, criar/tirar listagem, convite e aceite
-- automáticos, missão concluída e as regras do jogo (um clique = uma ação protegida, bloqueio de chat).
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local ELITE = { id = 155, title = "The Defias Brotherhood", zone = "Westfall", level = 18, elite = true, size = 3, mapID = 1436 }
local PLAIN = { id = 184, title = "Furlbrow's Deed", zone = "Westfall", level = 14, mapID = 1436 }
local DUNGEON = { id = 214, title = "Red Silk Bandanas", zone = "Deadmines", level = 20 }
local OTHER = { id = 20, title = "Blackrock Menace", zone = "Redridge Mountains", level = 18, mapID = 1433 }

local function copy(q) local o = {}; for k, v in pairs(q) do o[k] = v end; return o end

local function world(cfg)
    cfg = cfg or {}
    if cfg.hardwareEvents == nil then cfg.hardwareEvents = true end
    return H.world(cfg)
end

local function login(w, name, quests, opts)
    opts = opts or {}
    opts.name = name
    opts.account = opts.account or name
    opts.level = opts.level or 18
    local c = H.login(w, opts)
    for _, q in ipairs(quests or {}) do c:addQuest(copy(q)) end
    w:advance(0.2)
    return c
end

local function qwin(c) return c.env.GrupoFacilQuestFrame end
-- as opções de missões ficam nas opções do addon, seção Missões
local function opt(c, key)
    local f = c.env.GrupoFacilOptionsFrame
    if not (f and c:isVisible(f)) then c:slash("/gf options quests") end
    H.ns(c).OptionsSection("quests")
    return c.env.GrupoFacilOptionsFrame.content[key]
end

-- linhas visíveis da janela de missões: { name, info, row }
local function qrows(c)
    local out = {}
    local win = qwin(c)
    if not (win and c.ui.visible(win)) then return out end
    for _, r in ipairs({ win.list:GetChildren() }) do
        if c.ui.visible(r) and r.entry then out[#out + 1] = { name = c:text(r.name), info = c:text(r.info), row = r } end
    end
    return out
end
local function rowOf(c, name)
    for _, r in ipairs(qrows(c)) do if r.name:find("^" .. name) then return r.row end end
end

-- clique na lupa da lista de objetivos e espera resultados + respostas dos líderes
local function magnify(w, c, questID)
    local b = c:trackerMagnifier(questID)
    T.ok(b, "lupa da missão " .. questID .. " na lista de objetivos")
    c:click(b)
    w:advance(1.5)
end

-- um líder com o GrupoFacil que criou a listagem pela janela, com a missão
local function listedLeader(w, name, quest)
    local lead = login(w, name, { quest })
    magnify(w, lead, quest.id)
    lead:click(qwin(lead).create)
    w:advance(0.5)
    return lead
end

local function noBlizzardWrites(w)
    local bad = {}
    for _, x in ipairs(w.blizzardWrites) do bad[#bad + 1] = x.frame .. "." .. tostring(x.key) .. " por " .. x.by end
    T.eq(#bad, 0, "o addon gravou em quadro da Blizzard:\n  " .. table.concat(bad, "\n  "))
end

describe("quest groups - a lupa", function()
    it("aparece em toda missão da lista de objetivos, ao lado do botão nativo da elite, sem gravar na Blizzard", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE, PLAIN, OTHER })
        for _, q in ipairs({ ELITE, PLAIN, OTHER }) do
            local b, block = c:trackerMagnifier(q.id)
            T.ok(b and c:isVisible(b), "lupa visível em " .. q.title)
            if q.elite then
                -- à esquerda do botão nativo, sem cobrir
                T.ok(c.ui.rect(b).r <= c.ui.rect(block.findGroup).l + 0.5, "lupa à esquerda do botão nativo")
            end
            local tip = c:hover(b)
            T.has(tip, q.title)
        end
        -- missão nova entra na lista: ganha a lupa; missão entregue sai: a lupa some junto
        c:addQuest(copy(DUNGEON))
        T.ok(c:isVisible((c:trackerMagnifier(DUNGEON.id))), "lupa da missão nova")
        local old = c:trackerMagnifier(PLAIN.id)
        c:turnInQuest(PLAIN.id)
        T.no(c:isVisible(old), "lupa da missão entregue escondida")
        noBlizzardWrites(w)
        T.clean(c)
    end)

    it("aparece nos detalhes da missão do quest log e na janela solta de detalhes", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE, PLAIN })
        c:openQuestDetails(PLAIN.id)
        local df = c.env.QuestMapFrame.DetailsFrame
        local b = H.find(c, df, "Find group", true)
        T.ok(b, "botão Find group nos detalhes")
        T.match(c:hover(b)[1], PLAIN.title)
        c:click(b)
        w:advance(1)
        T.ok(c:isVisible(qwin(c)), "janela de missões aberta")
        T.eq(c:text(qwin(c).quest), PLAIN.title)
        c.env.QuestMapFrame_CloseQuestDetails()
        T.no(c:isVisible(b), "botão some com os detalhes")
        c:openQuestPopup(ELITE.id)
        local pb = H.find(c, c.env.QuestLogPopupDetailFrame, "Find group", true)
        T.ok(pb, "botão na janela solta")
        T.match(c:hover(pb)[1], ELITE.title)
        noBlizzardWrites(w)
        T.clean(c)
    end)

    it("a opção desliga e religa a lupa", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        T.ok(opt(c, "magnifier"):GetChecked())
        c:click(opt(c, "magnifier"))
        T.eq(H.db(c).quest.magnifier, false)
        T.no(c:isVisible((c:trackerMagnifier(ELITE.id))), "escondida")
        c:updateTracker()
        T.no(c:isVisible((c:trackerMagnifier(ELITE.id))), "continua escondida depois do redesenho")
        c:click(opt(c, "magnifier"))
        T.ok(c:isVisible((c:trackerMagnifier(ELITE.id))), "de volta")
        T.clean(c)
    end)
end)

describe("quest groups - buscar e escolher o grupo", function()
    it("a lupa busca a zona da missão em Missões e Zonas com um único clique e ordena: faz a missão, tem a missão, mesma zona", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        -- outro usuário do GrupoFacil, com a missão no log, listado sem ela
        local amigo = login(w, "Amigo", { ELITE })
        w.lfg:add({ leader = "Amigo", activityIDs = { 20 }, members = { { name = "Amigo", level = 18, class = "PRIEST" },
            { name = "X", level = 18, class = "MAGE" } } })
        -- grupo sem o addon na mesma zona; grupo de masmorra (não entra)
        w.lfg:add({ leader = "Outro", activityIDs = { 20 }, members = { { name = "Outro", level = 17, class = "ROGUE" },
            { name = "Y", level = 17, class = "MAGE" } } })
        w.lfg:add({ leader = "Masmorra", activityIDs = { 1 } })
        local c = login(w, "Jogador", { ELITE, PLAIN })
        magnify(w, c, ELITE.id)
        T.eq(c.lastSearch.category, 116)
        T.eq(c.lastSearch.activities[1], 20)
        T.eq(#c.blocked, 0, "nada bloqueado pelo jogo")
        local rows = qrows(c)
        T.eq(#rows, 3)
        T.match(rows[1].name, "^Lider"); T.match(rows[1].info, "doing this quest")
        T.match(rows[2].name, "^Amigo"); T.match(rows[2].info, "has this quest")
        T.match(rows[3].name, "^Outro"); T.match(rows[3].info, "same zone")
        T.match(c:text(qwin(c).status), "3 groups in the zone, 1 doing this quest%. 2 use GrupoFacil")
        T.match(c:text(qwin(c).meta), "Westfall")
        T.match(c:text(qwin(c).meta), "Elite")
        -- só perguntou a quem estava nos resultados, por sussurro de addon (nunca canal)
        local asked = w.net:find(function(r) return r.prefix == "GFQ" and r.from == "Jogador" and r.msg == "?1" end)
        T.eq(#asked, 3)
        T.eq(#w.net:find(function(r) return r.prefix == "GFQ" and r.chatType end), 0, "nada em canal/grupo")
        T.clean(c); T.clean(lead); T.clean(amigo)
    end)

    it("missão de masmorra busca a masmorra; zona sem entrada no LFG avisa ao criar", function()
        local w = world()
        local c = login(w, "Jogador", { DUNGEON, { id = 99, title = "Lost Zone", zone = "Nowhere" } })
        magnify(w, c, DUNGEON.id)
        T.eq(c.lastSearch.category, 2)
        T.eq(c.lastSearch.activities[1], 1)
        w:advance(3)
        c.zone = "Nowhere"
        magnify(w, c, 99)
        T.eq(c.lastSearch.category, 116)
        T.eq(c.lastSearch.activities, nil, "sem atividade: a categoria toda")
        T.no(qwin(c).create:IsEnabled(), "sem atividade não cria")
        T.match(c:hover(qwin(c).create)[2], "no entry for this quest's zone")
        T.clean(c)
    end)

    it("só uma ação protegida por clique: chamar a busca fora de um clique o jogo bloqueia (o modelo funciona)", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        T.eq(#c.blocked, 0)
        w:advance(3)
        H.ns(c).Quest.Search(ELITE.id) -- fora de clique
        T.eq(#c.blocked, 1)
        T.eq(c.blocked[1].fn, "C_LFGList.Search")
    end)
end)

describe("quest groups - entrar no grupo", function()
    it("líder com o GrupoFacil: pedido em silêncio, líder convida pela janela, o convite é aceito sozinho", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        local row = rowOf(c, "Lider")
        T.match(c:hover(row.b1)[2], "uses GrupoFacil")
        c:click(row.b1)
        w:advance(0.5)
        T.eq(#c.data.whispersSent, 0, "nenhum sussurro de chat")
        T.has(lead:chatLines(), "Jogador wants to join your group for The Defias Brotherhood")
        T.has(c:chatLines(), "Lider got your request and will decide")
        local lw = qwin(lead)
        T.ok(lead:isVisible(lw.reqTitle), "pedido na janela do líder")
        local yes = H.find(lead, lw.reqBox, "^Invite$", true)
        lead:click(yes)
        w:advance(0.5)
        T.eq(c.data.accepted, 1, "aceito sozinho")
        T.eq(c.data.invitePopup, nil, "a janela de convite do jogo foi fechada")
        T.ok(c.data.inGroup and lead.data.inGroup and lead.data.leader)
        T.has(c:chatLines(), "joined Lider's group")
        T.eq(#c.blocked + #lead.blocked, 0)
        T.clean(c); T.clean(lead)
    end)

    it("líder sem o GrupoFacil: sussurro de chat com o nome da missão", function()
        local w = world()
        w.lfg:add({ leader = "Estranho", activityIDs = { 20 }, members = { { name = "Estranho", level = 18, class = "ROGUE" },
            { name = "Y", level = 17, class = "MAGE" } } })
        local stranger = login(w, "Estranho", {})
        stranger.prefixes.GFQ = nil -- sem o addon: o sussurro de addon não chega
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        local row = rowOf(c, "Estranho")
        T.match(c:hover(row.b1)[2], "Sends: .*%[The Defias Brotherhood%]")
        c:click(row.b1)
        w:advance(0.5)
        T.eq(#c.data.whispersSent, 1)
        T.match(c.data.whispersSent[1].msg, "also on %[The Defias Brotherhood%]%. Can I join%? %(via GrupoFacil%)$")
        T.eq(c:text(row.b1), "Sent")
        T.clean(c)
    end)

    it("aceite automático: só do líder a quem você pediu, por 2 minutos, e pode ser desligado", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local intruso = login(w, "Intruso", {})
        local c = login(w, "Jogador", { ELITE })
        -- convite de quem você não pediu: fica com você
        intruso.env.C_PartyInfo.InviteUnit("Jogador")
        w:advance(0.5)
        T.eq(c.data.accepted, nil)
        T.ok(c.data.invitePopup, "convite do jogo continua aberto")
        c.env.DeclineGroup()
        -- pediu, mas o convite veio depois de 2 minutos
        magnify(w, c, ELITE.id)
        c:click(rowOf(c, "Lider").b1)
        w:advance(125)
        lead.env.C_PartyInfo.InviteUnit("Jogador")
        w:advance(0.5)
        T.eq(c.data.accepted, nil, "fora da janela de 2 min")
        c.env.DeclineGroup()
        T.clean(c); T.clean(lead)
    end)

    it("aceite automático desligado: o convite pedido espera o jogador", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        c:click(opt(c, "autoAccept"))
        T.eq(H.db(c).quest.autoAccept, false)
        magnify(w, c, ELITE.id)
        c:click(rowOf(c, "Lider").b1)
        w:advance(0.5)
        lead:click(H.find(lead, qwin(lead).reqBox, "^Invite$", true))
        w:advance(0.5)
        T.eq(c.data.accepted, nil)
        T.ok(c.data.invitePopup)
        T.clean(c)
    end)

    it("convite automático do líder: desligado por padrão, só para a mesma missão, no máximo 6 em 10 min", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        T.eq(H.db(lead).quest.autoInvite, false, "desligado por padrão")
        lead:click(opt(lead, "autoInvite"))
        T.eq(H.db(lead).quest.autoInvite, true)
        local players = {}
        for i = 1, 7 do
            local p = login(w, "Jogador" .. i, { ELITE })
            H.db(p).quest = { autoAccept = false } -- não entram: o grupo não enche
            magnify(w, p, ELITE.id)
            p:click(rowOf(p, "Lider").b1)
            w:advance(0.5)
            players[i] = p
        end
        T.eq(#lead.data.invites, 6, "6 convites automáticos")
        T.eq(#lead.namespaces.GrupoFacil.Quest.Requests(), 1, "o 7º fica para o líder decidir")
        -- pedido por outra missão: não convida sozinho
        local other = login(w, "Outra", { PLAIN })
        H.ns(other).Quest.peers["lider"] = { gf = true, at = other.env.GetTime(), has = {} }
        w:advance(601)
        other.env.C_ChatInfo.SendAddonMessage("GFQ", "J1 184 14 MAGE d", "WHISPER", "Lider")
        w:advance(0.5)
        T.eq(#lead.data.invites, 6, "outra missão não é convidada sozinha")
        T.has(lead:chatLines(), "Outra wants to join your group for")
        T.clean(lead)
    end)

    it("bloqueio de chat do jogo (instância/encontro): nada sai por addon", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        local before = #w.net:find(function(r) return r.from == "Jogador" and r.prefix == "GFQ" end)
        c.chatLockdown = true
        H.ns(c).Quest.Send("?1", "Lider")
        H.ns(c).Quest.QueryLeaders()
        H.ns(c).RefreshQuest("t")
        w:advance(2)
        T.eq(#w.net:find(function(r) return r.from == "Jogador" and r.prefix == "GFQ" end), before)
        T.no(rowOf(c, "Lider") and rowOf(c, "Lider").b1:IsEnabled(), "Join desligado no bloqueio")
        T.clean(c)
    end)
end)

describe("quest groups - criar o grupo e terminar", function()
    it("criar grupo lista com a missão; quem busca a mesma missão acha primeiro; tirar a listagem", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local created = lead.data.createdListings[1]
        T.eq(created.activityIDs[1], 20)
        T.eq(created.questID, nil, "o botão do jogo não manda o ID da missão; o addon também não")
        T.eq(created.voiceMode, 0)
        T.has(lead:chatLines(), "your group is listed in Looking For Group for this quest")
        T.eq(lead:text(qwin(lead).create), "Remove listing")
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        T.match(qrows(c)[1].info, "doing this quest")
        lead:click(qwin(lead).create)
        w:advance(0.5)
        T.eq(lead.env.C_LFGList.HasActiveEntryInfo(), false)
        T.eq(lead:text(qwin(lead).create), "Create group")
        T.eq(#lead.blocked, 0)
        T.clean(lead); T.clean(c)
    end)

    it("o jogo recusa a listagem (resposta false ou evento de falha): avisa, sem ficar mudo", function()
        local w = world({ refuseListing = true })
        local lead = login(w, "Lider", { ELITE })
        magnify(w, lead, ELITE.id)
        lead:click(qwin(lead).create)
        w:advance(0.5)
        T.has(lead:chatLines(), "the game did not accept the listing")
        T.eq(lead:text(qwin(lead).create), "Create group")
        T.ok(qwin(lead).create:IsEnabled(), "dá para tentar de novo")
        T.clean(lead)
    end)

    it("missão concluída: oferece sair do grupo e tirar a listagem, sem fazer nada sozinho", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        c:click(rowOf(c, "Lider").b1)
        w:advance(0.5)
        lead:click(H.find(lead, qwin(lead).reqBox, "^Invite$", true))
        w:advance(0.5)
        T.ok(c.data.inGroup)
        c:completeQuest(ELITE.id)
        w:advance(1)
        local done = c.env.GrupoFacilQuestDone
        T.ok(c:isVisible(done), "aviso de missão concluída")
        T.match(c:text(done.text), "You finished The Defias Brotherhood")
        T.ok(c.data.inGroup, "continua no grupo até clicar")
        T.no(done.remove:IsEnabled(), "membro não tem listagem")
        c:click(done.leave)
        w:advance(0.5)
        T.no(c.data.inGroup)
        T.eq(c.data.left, 1)
        -- o líder: entregou a missão, tem grupo e listagem
        lead:turnInQuest(ELITE.id)
        w:advance(1)
        local ld = lead.env.GrupoFacilQuestDone
        T.ok(lead:isVisible(ld))
        lead:click(ld.remove)
        w:advance(0.5)
        T.eq(lead.env.C_LFGList.HasActiveEntryInfo(), false)
        -- só uma vez por missão
        lead:click(ld.later)
        lead:completeQuest(ELITE.id)
        w:advance(1)
        T.no(lead:isVisible(ld))
        T.eq(#c.blocked + #lead.blocked, 0)
        T.clean(c); T.clean(lead)
    end)

    it("aviso do limite do jogo de entradas em grupo por hora", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        local now = c.env.time()
        H.char(c).joins = {}
        for i = 1, 12 do H.char(c).joins[i] = now - i * 60 end
        c:slash("/gf quests")
        w:advance(0.3)
        T.match(c:text(qwin(c).warn), "You joined 12 groups in the last hour")
        T.clean(c)
    end)
end)

describe("quest groups - uma janela com abas", function()
    it("Masmorras e Missões são abas da mesma janela; /gf quests e a lupa abrem a aba Missões", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        local main = c.env.GrupoFacilFrame
        c:slash("/gf quests")
        T.ok(c:isVisible(main), "a janela é a principal")
        T.ok(c:isVisible(qwin(c)), "aba Missões")
        T.no(c:isVisible(main.dungeonPanel), "a aba Masmorras fica escondida, sem vazar por baixo")
        T.match(c:text(qwin(c).meta), "Click Find group on a quest")
        c:slash("/gf missoes")
        T.no(c:isVisible(main))
        c:slash("/gf")
        T.ok(c:isVisible(qwin(c)), "abre na última aba usada")
        T.has(c:hover(main.tabDungeons), "Dungeon groups")
        c:click(main.tabDungeons)
        T.ok(c:isVisible(main.dungeonPanel))
        T.no(c:isVisible(qwin(c)))
        T.has(c:hover(main.tabQuests), "Groups for the quests")
        c:click(main.tabQuests)
        T.ok(c:isVisible(qwin(c)))
        T.no(c:isVisible(main.dungeonPanel))
        main:Hide()
        c:click(c:trackerMagnifier(ELITE.id))
        w:advance(1)
        T.ok(c:isVisible(qwin(c)), "a lupa abre a janela na aba Missões")
        T.eq(c:text(qwin(c).quest), ELITE.title)
        T.ok(main.tabQuests:IsEnabled() and main.tabDungeons:IsEnabled())
        c:slash("/gf help")
        T.has(c:chatLines(), "/gf quests")
        T.clean(c)
    end)

    it("pedido de vaga com a aba Masmorras aberta: não troca de aba, a aba Missões mostra a contagem", function()
        local w = world()
        local lead = login(w, "Lider", { ELITE })
        lead:slash("/gf")
        lead:click(lead.env.GrupoFacilFrame.tabDungeons)
        H.ns(lead).Quest.OnAddonMessage("GFQ", "J1 155 18 MAGE d The Defias Brotherhood", "WHISPER", "Pedinte")
        w:advance(0.5)
        local main = lead.env.GrupoFacilFrame
        T.ok(lead:isVisible(main.dungeonPanel), "continua nas masmorras")
        T.eq(lead:text(main.tabQuests), "Quests (1)")
        lead:click(main.tabQuests)
        T.ok(H.find(lead, qwin(lead).reqBox, "Pedinte", true), "o pedido está na aba Missões")
        T.clean(lead)
    end)

    it("informações da missão do grupo (nome, objetivo, local) chegam pelo addon e aparecem na aba", function()
        local w = world()
        local q = copy(ELITE)
        q.objectives = { { text = "Edwin VanCleef slain: 0/1" } }
        local lead = listedLeader(w, "Lider", q)
        T.match(lead:text(qwin(lead).obj), "Objective: Edwin VanCleef slain: 0/1")
        local p = copy(PLAIN)
        local c = login(w, "Jogador", { p })
        magnify(w, c, PLAIN.id) -- outra missão da mesma zona: o líder está listado para a dele
        local row = rowOf(c, "Lider")
        T.ok(row, "grupo do Lider na lista")
        T.match(c:text(row.info), "Quest: The Defias Brotherhood")
        local tip = table.concat(c:hover(row), "\n")
        T.match(tip, "Objective: Edwin VanCleef slain: 0/1")
        T.match(tip, "Where: Westfall")
        T.clean(lead); T.clean(c)
    end)

    it("aberta junto com o Looking For Group: sempre na aba Masmorras", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        c.env.GrupoFacilFrame:Hide()
        H.ns(c).ShowPanel(true)
        T.ok(c:isVisible(c.env.GrupoFacilFrame.dungeonPanel))
        T.no(c:isVisible(qwin(c)))
        T.clean(c)
    end)
end)

-- Ajustes do teste do Fraga no jogo (26/11): Criar grupo mudo, descrição, botões de outros addons
-- e janelas sobrepostas.
local function overlapsRect(a, b)
    return a and b and math.min(a.r, b.r) - math.max(a.l, b.l) > 1 and math.min(a.t, b.t) - math.max(a.b, b.b) > 1
end

describe("quest groups - ajustes do teste no jogo", function()
    it("criar grupo manda o estilo de jogo (obrigatório no Forever), como o botão do jogo", function()
        local w = world()
        local q = copy(ELITE)
        q.objectives = { { text = "Edwin VanCleef slain: 0/1" } }
        local lead = login(w, "Lider", { q })
        magnify(w, lead, ELITE.id)
        lead:click(qwin(lead).create)
        w:advance(0.5)
        local created = lead.data.createdListings[1]
        T.eq(created.generalPlaystyle, 2, "Enum.LFGEntryGeneralPlaystyle.FunRelaxed")
        T.eq(lead.env.C_LFGList.HasActiveEntryInfo(), true)
        noBlizzardWrites(w)
        T.clean(lead)
    end)

    it("missão de masmorra cria grupo de masmorra (a masmorra da missão, sem o ID da missão)", function()
        local w = world()
        local q = copy(DUNGEON)
        q.zone = "The Deadmines" -- como o log do jogo chama
        local lead = login(w, "Lider", { q })
        magnify(w, lead, DUNGEON.id)
        T.eq(lead.lastSearch.category, 2)
        lead:click(qwin(lead).create)
        w:advance(0.5)
        local created = lead.data.createdListings[1]
        T.eq(created.activityIDs[1], 1, "Deadmines, em Masmorras")
        T.eq(created.questID, nil)
        T.eq(created.generalPlaystyle, 2)
        T.has(lead:chatLines(), "in Dungeons: Deadmines")
        T.clean(lead)
    end)

    it("o jogo não responde à criação: botão espera, avisa em 4 s e guarda o erro do jogo", function()
        local w = world({ silentListing = true })
        local lead = login(w, "Lider", { ELITE })
        magnify(w, lead, ELITE.id)
        lead:click(qwin(lead).create)
        w:advance(0.5)
        T.no(qwin(lead).create:IsEnabled(), "um clique por vez enquanto o jogo não responde")
        lead:click(qwin(lead).create)
        T.eq(#lead.data.createdListings, 1, "o segundo clique não chama o jogo de novo")
        lead:fireEvent("UI_ERROR_MESSAGE", 999, "You must enter a description")
        w:advance(4)
        T.has(lead:chatLines(), "Open Looking For Group to list by hand")
        T.no(lead.env.GrupoFacilQuestDesc, "sem janela de descrição: o jogo não deixa colar nem preencher")
        T.eq(lead:text(qwin(lead).create), "Create group")
        T.ok(qwin(lead).create:IsEnabled())
        local diag = {}
        for _, e in ipairs(H.db(lead).diag.trace) do diag[#diag + 1] = e.m end
        T.match(table.concat(diag, "\n"), "You must enter a description")
        T.clean(lead)
    end)

    it("sem o estilo de jogo o modelo do jogo não lista (garante que o teste acima vale)", function()
        local w = world()
        local lead = login(w, "Lider", { ELITE })
        lead.env.C_LFGList.CreateListing({ activityIDs = { 20 } })
        w:advance(1)
        T.eq(lead.env.C_LFGList.HasActiveEntryInfo(), false)
    end)

    it("o botão nos detalhes desvia de botões de outros addons (ex.: Play do Spoken)", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        local df = c.env.QuestMapFrame.DetailsFrame
        local back = df.BackFrame
        -- outro addon põe dois botões na faixa do Voltar: ao lado dele e no canto direito
        local play = c.env.CreateFrame("Button", "SpokenPlayButton", back)
        play:SetSize(60, 22); play:SetPoint("LEFT", back.BackButton, "RIGHT", 6, 0); play:Show()
        local other = c.env.CreateFrame("Button", nil, c.env.UIParent)
        other:SetSize(80, 22); other:SetPoint("RIGHT", back, "RIGHT", -8, 4); other:Show()
        c:openQuestDetails(ELITE.id)
        w:advance(1.5)
        local b = H.ns(c).QuestDetailsButtons[df]
        T.ok(b and c:isVisible(b), "botão Achar grupo visível")
        local function rs(r) return r and string.format("%.0f,%.0f-%.0f,%.0f", r.l, r.b, r.r, r.t) or "nil" end
        for i, f in ipairs({ play, other, back.BackButton }) do
            T.no(overlapsRect(c.ui.rect(b), c.ui.rect(f)),
                string.format("não cobre o botão %d (nosso %s, dele %s)", i, rs(c.ui.rect(b)), rs(c.ui.rect(f))))
        end
        noBlizzardWrites(w)
        T.clean(c)
    end)

    it("quadro proibido da Blizzard perto dos detalhes não dá erro (não pode nem ser lido)", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        local secure = c.env.CreateFrame("Button", nil, c.env.UIParent)
        secure:SetSize(40, 22); secure:Show()
        secure.IsForbidden = function() return true end
        secure.IsVisible = function() error("calling 'IsVisible' on bad self (Attempt to access forbidden object)") end
        secure.GetRect = secure.IsVisible
        c:openQuestDetails(ELITE.id)
        w:advance(1.5)
        local b = H.ns(c).QuestDetailsButtons[c.env.QuestMapFrame.DetailsFrame]
        T.ok(b and c:isVisible(b))
        T.clean(c)
    end)

    it("a lupa da lista de objetivos desvia de um botão de outro addon no título", function()
        local w = world()
        local c = login(w, "Jogador", { PLAIN })
        local _, block = c:trackerMagnifier(PLAIN.id)
        local mark = c.env.CreateFrame("Button", nil, block)
        mark:SetSize(16, 16); mark:SetPoint("TOPRIGHT", block, "TOPRIGHT", 0, 0); mark:Show()
        c:updateTracker()
        local b = H.ns(c).QuestTrackerButtons[block]
        T.ok(b and c:isVisible(b))
        T.no(overlapsRect(c.ui.rect(b), c.ui.rect(mark)), "lupa não cobre o botão do outro addon")
        T.clean(c)
    end)
end)

-- rodada 3 do teste no jogo (26/11): tirar a listagem, limpar a missão, a lista das suas missões
local function pickRowsOf(c)
    local out = {}
    for _, r in ipairs({ qwin(c).list:GetChildren() }) do
        if c.ui.visible(r) and r.go then out[#out + 1] = r end
    end
    return out
end

describe("quest groups - tirar a listagem e a lista das suas missões", function()
    it("Tirar listagem pelo GrupoFacil limpa a missão e volta para a lista das suas missões", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local Q = H.ns(lead).Quest
        T.eq(Q.myQuest, ELITE.id)
        T.match(lead:text(qwin(lead).group), "Your group is listed for The Defias Brotherhood")
        lead:click(qwin(lead).create)
        w:advance(3)
        T.eq(lead.env.C_LFGList.HasActiveEntryInfo(), false)
        T.eq(Q.myQuest, nil, "a missão do grupo foi limpa")
        T.eq(Q.current, nil, "a missão escolhida foi limpa")
        T.ok(qwin(lead).picking, "de volta para a lista das suas missões")
        T.no(lead:isVisible(qwin(lead).create), "sem Criar grupo na lista")
        T.eq(lead:text(qwin(lead).quest), "Your quests")
        T.no(lead:chatLines()[1] and lead:chatLines()[#lead:chatLines()]:find("did not take your group out"), "o jogo tirou")
        T.clean(lead)
    end)

    it("tirar a listagem no Looking For Group do jogo também limpa o GrupoFacil", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local Q = H.ns(lead).Quest
        w.lfg:removeActive(lead) -- o jogador clicou em "Remover listagem" na janela do jogo
        w:advance(2)
        T.eq(Q.myQuest, nil)
        T.eq(Q.current, nil)
        T.ok(qwin(lead).picking)
        T.no(Q.HasListing())
        -- um novo pedido de outro jogador não diz mais que o grupo é dessa missão
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        T.eq(rowOf(c, "Lider"), nil, "o grupo saiu da busca")
        T.clean(lead); T.clean(c)
    end)

    it("se o jogo não tirar a listagem, avisa em vez de ficar mudo", function()
        local w = world()
        local lead = listedLeader(w, "Lider", ELITE)
        local api = lead.env.C_LFGList
        api.RemoveListing = function() end -- o jogo ignora
        lead:click(qwin(lead).create)
        w:advance(3)
        T.has(lead:chatLines(), "the game did not take your group out of Looking For Group")
        T.eq(lead:text(qwin(lead).create), "Remove listing", "continua listado")
        T.clean(lead)
    end)

    it("a aba Missões começa pela lista das suas missões; Achar grupo busca a missão", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE, OTHER })
        c:slash("/gf quests")
        local win = qwin(c)
        T.ok(win.picking)
        T.eq(c:text(win.quest), "Your quests")
        T.eq(c:text(win.listTitle), "Your quests (2)")
        local rs = pickRowsOf(c)
        T.eq(#rs, 2)
        local target
        for _, r in ipairs(rs) do if r.questID == OTHER.id then target = r end end
        T.ok(target, "Blackrock Menace na lista")
        T.match(c:text(target.info), "Redridge")
        c:click(target.go)
        w:advance(1.5)
        T.no(win.picking)
        T.eq(c:text(win.quest), OTHER.title)
        T.ok(c:isVisible(win.create))
        T.match(c:text(win.listTitle), "Groups and players in Redridge")
        c:click(win.back)
        T.ok(win.picking, "o botão < Suas missões volta para a lista")
        T.clean(c)
    end)

    it("registro vazio: explica o que fazer", function()
        local w = world()
        local c = login(w, "Jogador", {})
        c:slash("/gf quests")
        T.ok(qwin(c).picking)
        T.match(c:text(qwin(c).empty), "Your quest log is empty")
        T.clean(c)
    end)

    it("as opções de missões ficam nas opções do addon; a engrenagem na aba Missões abre nessa seção", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        T.eq(qwin(c).opts, nil, "sem quadro de opções na aba")
        T.eq(qwin(c).optBtn, nil)
        local gear = c.env.GrupoFacilFrame.optionsButton
        T.ok(c:isVisible(gear))
        T.match(c:hover(gear)[1], "Options")
        c:click(gear)
        local f = c.env.GrupoFacilOptionsFrame
        T.ok(c:isVisible(f))
        T.eq(f.content.section, "quests")
        T.ok(c:isVisible(f.content.autoInvite)); T.ok(c:isVisible(f.content.autoAccept)); T.ok(c:isVisible(f.content.magnifier))
        T.no(c:isVisible(f.content.msg), "a mensagem fica em outra seção")
        c:click(gear)
        T.no(c:isVisible(f), "a engrenagem fecha")
        c:click(c.env.GrupoFacilFrame.tabDungeons)
        c:click(gear)
        T.eq(f.content.section, "quests", "abre na última seção usada")
        T.clean(c)
    end)
end)

describe("quest groups - um tour só, do addon inteiro", function()
    local function calloutTitle(c)
        local _, callout = H.ns(c).TourFrames()
        return c:isVisible(callout) and c:text(callout.title) or nil
    end

    it("passa pelas Masmorras e depois pelas Missões, trocando de aba sozinho; concluir marca como visto", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf")
        local banner = H.ns(c).TourFrames()
        T.ok(c:isVisible(banner))
        c:click(H.find(c, banner, "^Start tour$", true))
        T.match(calloutTitle(c), "^1/10  Pick what to list$")
        T.eq(H.ns(c).tab, "dungeons")
        local _, callout = H.ns(c).TourFrames()
        for _ = 1, 4 do c:click(callout.next) end
        T.match(calloutTitle(c), "^5/10  Your message$")
        c:click(callout.next)
        T.match(calloutTitle(c), "^6/10  Your quests$")
        T.eq(H.ns(c).tab, "quests", "o tour abriu a aba Missões")
        T.ok(H.ns(c).TourRunning(), "trocar de aba pelo tour não interrompe")
        local _, qsample = H.ns(c).QuestTourFrames()
        T.ok(c:isVisible(qsample.pick))
        c:click(callout.next)
        T.match(calloutTitle(c), "^7/10  Groups for the quest$")
        c:click(qsample.row.button); c:click(qsample.req.button)
        T.eq(H.ns(c).Quest.current, nil, "o exemplo não escolhe missão")
        T.eq(#c.data.whispersSent, 0, "nem sussurra ninguém")
        c:click(callout.back)
        T.match(calloutTitle(c), "^6/10")
        c:click(callout.next); c:click(callout.next); c:click(callout.next); c:click(callout.next)
        T.match(calloutTitle(c), "^10/10  Options$")
        T.no(c:isVisible(qsample), "o último passo aponta para a engrenagem de verdade")
        -- voltar do passo 6 para o 5 volta para a aba Masmorras
        for _ = 1, 5 do c:click(callout.back) end
        T.match(calloutTitle(c), "^5/10")
        T.eq(H.ns(c).tab, "dungeons")
        for _ = 1, 6 do c:click(callout.next) end
        T.no(H.ns(c).TourRunning())
        T.eq(H.db(c).tour.version, 2)
        c:slash("/gf"); c:slash("/gf")
        T.no(c:isVisible(banner), "não aparece de novo")
        c:slash("/gf quests")
        T.no(c:isVisible((H.ns(c).QuestTourFrames())), "nem na aba Missões")
        T.clean(c)
    end)

    it("quem viu o tour antigo (só Masmorras) ganha o convite nas duas abas; Agora não marca para as duas", function()
        local w = world()
        local c = login(w, "Jogador", {})
        H.db(c).tour = { version = 1, welcomed = true }
        c:slash("/gf")
        local banner = H.ns(c).TourFrames()
        T.ok(c:isVisible(banner))
        T.ok(H.find(c, banner, "covers the Quests tab too"))
        c:slash("/gf quests")
        local qbanner = H.ns(c).QuestTourFrames()
        T.ok(c:isVisible(qbanner))
        c:click(H.find(c, qbanner, "^No thanks$", true))
        T.eq(H.db(c).tour.version, 2)
        T.no(c:isVisible(qbanner))
        c:click(c.env.GrupoFacilFrame.tabDungeons)
        T.no(c:isVisible(banner), "a das masmorras também some")
        T.clean(c)
    end)

    it("/gf tour e Mostrar o tour nas opções começam do passo 1 em qualquer aba, mesmo já visto", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        H.db(c).tour = { version = 2, welcomed = true }
        c:slash("/gf quests")
        c:slash("/gf tour")
        T.match(calloutTitle(c), "^1/10  Pick what to list$")
        T.eq(H.ns(c).tab, "dungeons")
        -- trocar de aba à mão interrompe sem marcar
        c:click(c.env.GrupoFacilFrame.tabQuests)
        T.no(H.ns(c).TourRunning())
        c:slash("/gf options general")
        local f = c.env.GrupoFacilOptionsFrame
        c:click(f.content.tour)
        T.no(c:isVisible(f), "as opções fecham para o tour aparecer")
        T.match(calloutTitle(c), "^1/10  Pick what to list$")
        T.eq(H.db(c).tour.version, nil, "reiniciado: vale como não visto até concluir")
        local _, callout = H.ns(c).TourFrames()
        c:click(callout.skip)
        T.eq(H.db(c).tour.version, 2)
        T.clean(c)
    end)
end)

-- plano de adesão (26/11): indicar a um amigo e o TOC citando missões
describe("quest groups - indicar a um amigo", function()
    it("/gf share só põe a frase na caixa do chat: guilda se tiver, senão dizer; /gf share <nome> sussurra", function()
        local w = world()
        local c = login(w, "Jogador", {})
        c:slash("/gf share")
        T.match(c.data.chatInput, "^/s I use GrupoFacil, a free addon")
        T.match(c.data.chatInput, "curseforge%.com/wow/addons/grupofacil$")
        T.eq(#c.data.whispersSent, 0, "o addon não envia nada sozinho")
        c:slash("/gf share Bael Bagacera")
        T.match(c.data.chatInput, "^/w Bael Bagacera I use GrupoFacil", "nome completo, com sobrenome")
        T.eq(#c.data.whispersSent, 0)
        local g = login(w, "Guildeiro", {}, { guild = "Os Bons" })
        g:slash("/gf indicar")
        T.match(g.data.chatInput, "^/g I use GrupoFacil")
        T.eq(#g.data.whispersSent, 0)
        T.clean(c); T.clean(g)
    end)

    it("Convide um amigo: escolher guilda, grupo, dizer ou /1, /2...; sussurro pede o nome completo", function()
        local w = world()
        local c = login(w, "Jogador", {}, { guild = "Os Bons" })
        c:slash("/gf options invite")
        local f = c.env.GrupoFacilOptionsFrame
        local o = f.content
        T.ok(H.find(c, f, "^Invite a friend$", true), "área Convide um amigo")
        T.match(c:text(o.sharePreview), "I use GrupoFacil")
        T.eq(o.shareLink:GetText(), "https://www.curseforge.com/wow/addons/grupofacil")
        T.match(c:text(o.shareTarget), "^Guild", "com guilda, começa na guilda")
        T.no(c:isVisible(o.shareFriend), "nome do amigo só no sussurro")
        c:click(o.shareTarget)
        local m = c.env.GrupoFacilShareMenu
        T.ok(c:isVisible(m))
        for _, n in ipairs({ "^Whisper a friend$", "^Guild$", "^Say$", "^/1 General$", "^/2 Trade$", "^/4 LocalDefense$" }) do
            T.ok(H.find(c, m, n, true), n)
        end
        T.eq(H.find(c, m, "^Group$", true), nil, "sem grupo, sem Grupo")
        c:click(H.find(c, m, "^/2 Trade$", true))
        T.eq(H.db(c).share.target, "ch:2")
        c:click(o.share)
        T.match(c.data.chatInput, "^/2 I use GrupoFacil")
        -- sussurro: sem nome avisa; com nome vai para o amigo
        c:click(o.shareTarget)
        c:click(H.find(c, m, "^Whisper a friend$", true))
        T.ok(c:isVisible(o.shareFriend))
        c.data.chatInput = nil
        c:click(o.share)
        T.eq(c.data.chatInput, nil)
        T.has(c:chatLines(), "full character name")
        c:type(o.shareFriend, "  Amiga   Sobrenome ")
        c:press(o.shareFriend, "ENTER")
        T.match(c.data.chatInput, "^/w Amiga Sobrenome I use GrupoFacil")
        T.eq(#c.data.whispersSent, 0)
        -- o link para copiar não aceita edição
        c:type(o.shareLink, "xyz")
        T.eq(o.shareLink:GetText(), "https://www.curseforge.com/wow/addons/grupofacil")
        T.clean(c)
    end)

    it("destino salvo que não vale mais (saiu da guilda) cai para dizer", function()
        local w = world()
        local c = login(w, "Jogador", {})
        H.db(c).share = { target = "guild" }
        c:slash("/gf share")
        T.match(c.data.chatInput, "^/s ")
        c.data.channels = { { 1, "General" } }
        H.db(c).share = { target = "ch:5" }
        c:slash("/gf share")
        T.match(c.data.chatInput, "^/s ", "canal que o jogador deixou")
        T.clean(c)
    end)

    it("na aba Missões: Indicar a um amigo e o ícone i abrem o Convide um amigo", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        local b = qwin(c).share
        T.ok(c:isVisible(b))
        T.match(c:hover(b)[2], "Quest groups work better the more players use GrupoFacil")
        c:click(b)
        local f = c.env.GrupoFacilOptionsFrame
        T.ok(c:isVisible(f)); T.eq(f.content.section, "invite")
        f:Hide()
        local info = qwin(c).info
        T.ok(c:isVisible(info), "ícone i na lista das suas missões")
        local tip = c:hover(info)
        T.eq(tip[1], "How quest groups work")
        T.match(tip[2], "only works between players who use GrupoFacil")
        c:click(info)
        T.ok(c:isVisible(f)); T.eq(f.content.section, "invite")
        f:Hide()
        magnify(w, c, ELITE.id)
        T.ok(c:isVisible(info), "também com a missão escolhida")
        T.clean(c)
    end)

    it("Esc fecha a janela principal, as opções e a do link de apoio", function()
        local w = world()
        local c = login(w, "Jogador", {})
        c:slash("/gf options")
        c:click(H.find(c, c.env.GrupoFacilOptionsFrame, "^Sponsor on GitHub$", true))
        local special = {}
        for _, n in ipairs(c.env.UISpecialFrames) do special[n] = true end
        T.ok(special.GrupoFacilFrame, "janela principal")
        T.ok(special.GrupoFacilOptionsFrame, "opções")
        T.ok(special.GrupoFacilDonateFrame, "link de apoio")
        T.clean(c)
    end)

    it("em todo idioma a frase cabe numa mensagem do chat (255 bytes, com /g) e leva o link", function()
        for _, lang in ipairs({ "en", "pt", "es", "mx", "de", "fr" }) do
            local w = world()
            local c = login(w, "Jogador", {}, { guild = "G" })
            H.db(c).language = lang
            c:reload()
            w:advance(1)
            c:slash("/gf share")
            local t = c.data.chatInput or ""
            T.ok(#t <= 255, lang .. ": " .. #t .. " bytes")
            T.match(t, "^/g ")
            T.match(t, "curseforge%.com/wow/addons/grupofacil")
            if lang == "pt" then T.match(t, "^/g Uso o GrupoFacil", "frase traduzida") end
            if lang == "de" then T.match(t, "^/g Ich nutze GrupoFacil", "frase traduzida") end
            T.clean(c)
        end
    end)

    it("o TOC cita missões e usa a categoria Group Finder", function()
        local f = assert(io.open("GrupoFacil.toc", "r"))
        local toc = f:read("*a"); f:close()
        T.match(toc, "\n## Category: Group Finder\n")
        T.match(toc, "\n## Category%-enUS: Group Finder\n")
        T.match(toc, "\n## Notes: [^\n]*quests")
        T.match(toc, "\n## Notes%-ptBR: [^\n]*missões")
        for _, loc in ipairs({ "ptBR", "esES", "esMX", "deDE", "frFR" }) do
            T.match(toc, "\n## Notes%-" .. loc .. ": ", "Notes em " .. loc)
            T.match(toc, "\n## Category%-" .. loc .. ": ", "Category em " .. loc)
        end
    end)
end)

describe("quest groups - testar sem outro jogador com o addon", function()
    local function demoNet(w)
        local n = 0
        local fake = { "Aldren", "Brisa", "Corvo", "Duna", "Eira" }
        for _, r in ipairs(w.net.log) do
            for _, f in ipairs(fake) do if tostring(r.to):find("^" .. f) then n = n + 1 end end
        end
        return n
    end

    it("/gf debug demo: líderes falsos com o GrupoFacil na aba Missões, respostas simuladas, nada vai para o jogo", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf debug demo")
        w:advance(0.3)
        T.has(c:chatLines(), "demo on: fake players in the Quests tab")
        local win = qwin(c)
        T.ok(c:isVisible(win), "abre a aba Missões")
        T.match(c:text(win.status), "^.*Demo: fake players, nothing goes to the game%.")
        local names = {}
        for _, r in ipairs(qrows(c)) do names[#names + 1] = r.name end
        T.match(names[1], "^Aldren Ventobravo") -- faz a missão (listado) vem antes
        T.ok(rowOf(c, "Brisa Luzclara") and rowOf(c, "Corvo Pedranegra") and rowOf(c, "Duna Areiafina"), "os quatro jogadores falsos")
        -- tooltip do líder listado mostra a missão que veio "pelo addon"
        local tip = c:hover(rowOf(c, "Aldren Ventobravo"))
        T.has(tip, "uses GrupoFacil")
        T.has(tip, "Quest: The Defias Brotherhood")
        -- pedir vaga ao líder com o addon: resposta e convite simulados
        c:click(rowOf(c, "Aldren Ventobravo").b1)
        w:advance(1.5)
        T.has(c:chatLines(), "Aldren Ventobravo got your request and will decide")
        w:advance(2.5)
        T.has(c:chatLines(), "%[demo%] Aldren Ventobravo would invite you now")
        -- grupo cheio
        c:click(rowOf(c, "Brisa Luzclara").b1)
        w:advance(1.5)
        T.has(c:chatLines(), "Brisa Luzclara: the group is full")
        -- líder sem o addon: mostra o sussurro, não manda
        c:click(rowOf(c, "Duna Areiafina").b1)
        w:advance(0.3)
        T.has(c:chatLines(), "%[demo%] whisper that would go to Duna Areiafina: .*%(via GrupoFacil%)")
        T.eq(#c.data.whispersSent, 0, "nenhum sussurro de chat")
        -- alguém pede vaga a você; Convidar não convida ninguém de verdade
        T.has(c:chatLines(), "Eira Folhaverde wants to join your group for The Defias Brotherhood")
        local yes = H.find(c, win.reqBox, "^Invite$", true)
        c:click(yes)
        w:advance(0.3)
        T.has(c:chatLines(), "%[demo%] invite that would go to Eira Folhaverde %(simulated%)")
        T.eq(#c.data.invites, 0, "nenhum convite do jogo")
        T.eq(demoNet(w), 0, "nenhuma mensagem de addon para os jogadores falsos")
        -- desligar tira tudo
        c:slash("/gf debug demo off")
        w:advance(0.3)
        T.has(c:chatLines(), "demo off%.")
        T.eq(rowOf(c, "Aldren Ventobravo"), nil)
        T.ok(not c:text(win.status):find("Demo:"), "sem o aviso de demonstração")
        T.eq(#H.ns(c).Quest.Requests(), 0, "o pedido falso saiu")
        T.eq(#c.blocked, 0)
        T.clean(c)
    end)

    it("/gf debug demo sem missão no registro explica; com a lista aberta usa a primeira missão", function()
        local w = world()
        local c = login(w, "Jogador", {})
        c:slash("/gf debug demo")
        T.has(c:chatLines(), "pick up a quest first")
        T.eq(H.ns(c).Quest.demo, nil)
        c:addQuest(copy(PLAIN))
        w:advance(0.2)
        c:slash("/gf debug demo")
        w:advance(0.3)
        T.eq(H.ns(c).Quest.current.questID, PLAIN.id)
        T.ok(rowOf(c, "Aldren Ventobravo"))
        T.clean(c)
    end)

    it("/gf debug ping: a mensagem silenciosa vai e volta (você mesmo ou um amigo com o addon)", function()
        local w = world()
        local c = login(w, "Bael", {}, { surname = "Goldmaker" })
        c:slash("/gf debug ping")
        w:advance(1)
        T.has(c:chatLines(), "silent message sent to Bael Goldmaker")
        T.has(c:chatLines(), "the silent message came back from Bael Goldmaker in .* s: sending through the server works")
        local f = login(w, "Bagael", {}, { surname = "Bagacera" })
        c:slash("/gf debug ping Bagael Bagacera")
        w:advance(1)
        T.has(c:chatLines(), "came back from Bagael Bagacera")
        T.clean(c); T.clean(f)
    end)

    it("/gf debug ping sem volta (servidor não entrega, ou amigo sem o addon) avisa em 6 s", function()
        local w = world()
        local c = login(w, "Bael", {}, { surname = "Goldmaker" })
        w.net.dropFn = function() return true end
        c:slash("/gf debug selftest")
        w:advance(7)
        T.has(c:chatLines(), "did not come back from Bael Goldmaker in 6 s")
        T.has(c:chatLines(), "Test with a friend who has this version: /gf debug ping Name Surname")
        w.net.dropFn = nil
        local f = login(w, "Bagael", {}, { surname = "Bagacera" })
        f.prefixes.GFQ = nil
        c:slash("/gf debug ping Bagael Bagacera")
        w:advance(7)
        T.has(c:chatLines(), "did not come back from Bagael Bagacera in 6 s")
        T.clean(c); T.clean(f)
    end)
end)

describe("quest groups - a busca da lupa e a aba Masmorras", function()
    it("depois da lupa, Buscar de novo na aba Masmorras busca masmorras (não repete a missão) e explica", function()
        local w = world()
        H.sampleListings(w)
        w.lfg:add({ leader = "Zonal", activityIDs = { 20 }, members = { { name = "Zonal", level = 18, class = "ROGUE" } } })
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        T.eq(c.lastSearch.category, 116, "a lupa busca Missões e Zonas")
        local f = c.env.GrupoFacilFrame
        c:click(f.tabDungeons)
        w:advance(4)
        T.ok(H.find(c, f, "These are the results of a quest search%. Search again searches dungeons%.", true))
        c:click(H.find(c, f, "^Groups$", true)) -- como no print: modo Grupos, o jogador sozinho da zona sai
        w:advance(0.2)
        -- lista de masmorras vazia: explica, e o texto fica dentro da caixa
        c:click(H.find(c, f, "^All dungeons$", true))
        local m = c.env.GrupoFacilDungeonMenu
        local fs = H.find(c, m, "These results are from a quest search", true)
        T.ok(fs, "explica de onde vêm os resultados")
        local mr, tr = c.ui.rect(m), c.ui.rect(fs)
        T.ok(tr.r <= mr.r - 4 and tr.l >= mr.l + 4 and tr.b >= mr.b + 4, "o texto cabe na caixa")
        local br = c.ui.rect(m.all)
        T.ok(br.t <= mr.t - 4, "o botão Todas as masmorras não encosta na borda de cima")
        c:clickOutside() -- clique fora fecha a lista
        c:click(H.find(c, f, "^Search again$", true))
        w:advance(1)
        T.eq(c.lastSearch.category, 2, "Buscar de novo busca masmorras")
        T.eq(#c.lastSearch.activities, 5, "todas as masmorras")
        T.ok(not H.find(c, f, "quest search", true), "o aviso sai")
        c:click(H.find(c, f, "^All dungeons$", true))
        T.ok(H.find(c, m, "^Deadmines", true), "agora a lista tem masmorras")
        -- a lupa continua buscando a missão, e Buscar de novo nas masmorras continua nas masmorras
        w:advance(4)
        magnify(w, c, ELITE.id)
        T.eq(c.lastSearch.category, 116)
        w:advance(4)
        c:click(f.tabDungeons)
        c:click(H.find(c, f, "^Search again$", true))
        w:advance(1)
        T.eq(c.lastSearch.category, 2)
        T.clean(c)
    end)

    it("busca nativa de masmorra antes da lupa: Buscar de novo repete essa busca, não a da missão", function()
        local w = world()
        H.sampleListings(w)
        local c = login(w, "Jogador", { ELITE })
        H.search(w, c, 2, { 1, 2 })
        w:advance(4)
        magnify(w, c, ELITE.id)
        w:advance(4)
        local f = c.env.GrupoFacilFrame
        c:click(f.tabDungeons)
        c:click(H.find(c, f, "^Search again$", true))
        w:advance(1)
        T.eq(c.lastSearch.category, 2)
        T.eq(table.concat(c.lastSearch.activities, ","), "1,2")
        T.clean(c)
    end)

    it("Buscar de novo recusado aparece na janela, não só no chat", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf")
        local f = c.env.GrupoFacilFrame
        w:advance(4)
        c.chatLockdown = true
        H.ns(c).searchReadyAt = 0
        local sb = H.find(c, f, "^Search again$", true)
        c.ui.fire(sb, "OnClick")
        w:advance(0.2)
        T.ok(H.find(c, f, "chat restriction", true), "o motivo aparece na janela")
        T.clean(c)
    end)
end)

describe("quest groups - grupo ou listagem que não é de missão", function()
    -- listagem ativa que não veio da aba Missões (masmorra pelo Looking For Group do jogo, ou o grupo
    -- de outro líder em que você entrou: no jogo, os membros também veem a listagem)
    local function otherListing(w, c, activity)
        local l = { leader = c.name, members = { { name = c.name, level = 18, class = "HUNTER" } }, activityIDs = { activity or 1 }, owner = c, age = 0 }
        w.lfg:add(l)
        w.lfg.active[c] = l
        c:fireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", true)
        w:advance(2)
        return l
    end
    local function joinGroup(w, c, leader)
        c.data.inGroup, c.data.leader = true, leader or false
        c:fireEvent("GROUP_ROSTER_UPDATE")
        w:advance(0.5)
    end

    it("listado para masmorra como líder: a aba Missões não mostra grupo de missão nem tira a listagem", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        joinGroup(w, c, true)
        otherListing(w, c, 1)
        local win = qwin(c)
        T.ok(not c:text(win.group):find("Defias"), "não diz que o grupo é da missão: " .. c:text(win.group))
        T.match(c:text(win.group), "listed in Looking For Group for something else")
        T.eq(c:text(win.create), "Create group", "não oferece tirar a listagem da masmorra")
        T.no(win.create:IsEnabled())
        -- quem pergunta pelo addon não ouve que o grupo é da missão
        local other = login(w, "Outro", { ELITE })
        H.ns(other).Quest.Send("?1", "Jogador")
        w:advance(1)
        local p = H.ns(other).Quest.peers.jogador
        T.ok(p and p.gf, "respondeu")
        T.eq(p.listed, nil, "não anuncia a missão")
        -- a listagem da masmorra sai: a missão escolhida na aba continua (nada a limpar)
        w.lfg:removeActive(c)
        c:fireEvent("LFG_LIST_ACTIVE_ENTRY_UPDATE", false)
        w:advance(2)
        T.eq(H.ns(c).Quest.current.questID, ELITE.id)
        T.clean(c); T.clean(other)
    end)

    it("entrar num grupo que não foi pedido pela missão (mesmo depois de pedir vaga a outro): não é grupo de missão", function()
        local w = world()
        w.lfg:add({ leader = "Estranho", activityIDs = { 20 }, members = { { name = "Estranho", level = 18, class = "ROGUE" },
            { name = "Y", level = 17, class = "MAGE" } } })
        local stranger = login(w, "Estranho", {})
        stranger.prefixes.GFQ = nil
        local c = login(w, "Jogador", { ELITE })
        magnify(w, c, ELITE.id)
        c:click(rowOf(c, "Estranho").b1) -- pediu vaga por sussurro
        w:advance(0.5)
        -- entra noutro grupo, de masmorra, já listado pelo líder dele
        joinGroup(w, c, false)
        otherListing(w, c, 1)
        local win = qwin(c)
        T.ok(not c:text(win.group):find("Defias"), "não é grupo da missão: " .. c:text(win.group))
        T.eq(H.ns(c).Quest.myQuest, nil)
        T.eq(c:text(win.create), "Create group")
        T.clean(c)
    end)

    it("entrar pelo convite do líder a quem pediu vaga pela missão: é grupo de missão (aceite automático ou à mão)", function()
        for _, auto in ipairs({ true, false }) do
            local w = world()
            local lead = listedLeader(w, "Lider", ELITE)
            local c = login(w, "Jogador", { ELITE })
            if not auto then H.ns(c).Quest.DB().autoAccept = false end
            magnify(w, c, ELITE.id)
            c:click(rowOf(c, "Lider").b1)
            w:advance(0.5)
            lead:click(H.find(lead, qwin(lead).reqBox, "^Invite$", true))
            w:advance(0.5)
            if not auto then joinGroup(w, c, false) end
            T.eq(H.ns(c).Quest.myQuest, ELITE.id, "aceite " .. tostring(auto))
            T.match(c:text(qwin(c).group), "In a group for The Defias Brotherhood")
            T.clean(c); T.clean(lead)
        end
    end)

    it("listar para a missão, tirar e voltar para Masmorras: a aba busca as masmorras sozinha e a lista volta", function()
        local w = world()
        H.sampleListings(w)
        local c = login(w, "Jogador", { ELITE })
        H.search(w, c, 2, { 1, 2, 3, 4, 5 })
        w:advance(4)
        local f = c.env.GrupoFacilFrame
        magnify(w, c, ELITE.id)
        local win = qwin(c)
        c:click(win.create); w:advance(1)
        T.match(c:text(win.group), "Your group is listed for The Defias Brotherhood")
        c:click(win.create); w:advance(4)
        T.no(H.ns(c).Quest.HasListing())
        c:click(f.tabDungeons)
        w:advance(1)
        T.eq(c.lastSearch.category, 2, "o clique na aba buscou as masmorras")
        T.eq(table.concat(c.lastSearch.activities, ","), "1,2,3,4,5", "a mesma busca de antes")
        c:click(H.find(c, f, "^All dungeons$", true))
        T.ok(H.find(c, c.env.GrupoFacilDungeonMenu, "^Deadmines", true), "a lista de masmorras volta")
        T.eq(#c.blocked, 0, "uma ação protegida por clique")
        T.clean(c)
    end)

    it("a janela do jogo fica em Missões e Zonas depois de listar para missão: a aba Masmorras ainda busca masmorras", function()
        local w = world()
        H.sampleListings(w)
        local c = login(w, "Jogador", { ELITE })
        H.search(w, c, 2, { 1, 2, 3, 4, 5 })
        w:advance(4)
        local f = c.env.GrupoFacilFrame
        magnify(w, c, ELITE.id)
        local win = qwin(c)
        c:click(win.create); w:advance(1)
        c:click(win.create); w:advance(4)
        -- o jogo deixou a categoria da janela em Missões e Zonas e busca nela (como no print do Fraga)
        c:nativeSearch(116, { 20 })
        w:advance(4)
        T.eq(c.lastSearch.category, 116)
        c:click(f.tabDungeons)
        w:advance(1)
        T.eq(c.lastSearch.category, 2, "a aba buscou masmorras, não Missões e Zonas")
        T.eq(table.concat(c.lastSearch.activities, ","), "1,2,3,4,5")
        c:click(H.find(c, f, "^All dungeons$", true))
        T.ok(H.find(c, c.env.GrupoFacilDungeonMenu, "^Deadmines", true), "a lista de masmorras volta")
        c:clickOutside()
        -- já na aba Masmorras: outra busca nativa em Missões e Zonas; Buscar de novo volta às masmorras
        w:advance(4)
        c:nativeSearch(116, { 20 })
        w:advance(4)
        T.ok(H.find(c, f, "These are the results of a quest search", true))
        c:click(H.find(c, f, "^Search again$", true))
        w:advance(1)
        T.eq(c.lastSearch.category, 2)
        T.eq(#c.blocked, 0)
        T.clean(c)
    end)
end)
