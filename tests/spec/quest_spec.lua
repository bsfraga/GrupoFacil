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
        local win = qwin(c)
        T.ok(win.magnifier:GetChecked())
        c:click(win.magnifier)
        T.eq(H.db(c).quest.magnifier, false)
        T.no(c:isVisible((c:trackerMagnifier(ELITE.id))), "escondida")
        c:updateTracker()
        T.no(c:isVisible((c:trackerMagnifier(ELITE.id))), "continua escondida depois do redesenho")
        c:click(win.magnifier)
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
        T.match(c.data.whispersSent[1].msg, "also on %[The Defias Brotherhood%]%. Can I join%?")
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
        c:click(qwin(c).autoAccept)
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
        lead:click(qwin(lead).autoInvite)
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

describe("quest groups - janelas", function()
    it("/gf quests, o botão na janela principal e o botão Dungeons ligam as duas janelas", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        T.ok(c:isVisible(qwin(c)))
        T.match(c:text(qwin(c).meta), "Click the magnifier")
        c:slash("/gf missoes")
        T.no(c:isVisible(qwin(c)))
        c:slash("/gf")
        local main = c.env.GrupoFacilFrame
        T.has(c:hover(main.questButton), "Quest groups")
        c:click(main.questButton)
        T.ok(c:isVisible(qwin(c)))
        main:Hide()
        c:click(qwin(c).dungeons)
        T.ok(c:isVisible(main))
        c:slash("/gf help")
        T.has(c:chatLines(), "/gf quests")
        T.clean(c)
    end)

    it("a posição da janela fica salva entre sessões", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf quests")
        local win = qwin(c)
        win:ClearAllPoints()
        win:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 100, -100)
        c.ui.fire(win, "OnDragStop")
        c:reload()
        w:advance(0.5)
        c:slash("/gf quests")
        local p = H.db(c).quest.pos
        T.eq(p[1], "TOPLEFT"); T.eq(p[3], 100)
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

    it("janelas do GrupoFacil sobrepostas: a que abriu ou foi clicada fica na frente", function()
        local w = world()
        local c = login(w, "Jogador", { ELITE })
        c:slash("/gf")
        local main = c.env.GrupoFacilFrame
        c:click(main.questButton)
        local qw = qwin(c)
        T.ok(main:IsToplevel() and qw:IsToplevel(), "as duas janelas vêm para a frente quando clicadas")
        T.ok(qw:GetFrameLevel() > main:GetFrameLevel(), "a de missões, aberta por último, na frente")
        c:click(main.questButton) -- fecha
        c:click(main.questButton) -- abre de novo
        c:click(H.find(c, main, "^Options$", true) or main.questButton)
        T.ok(main:GetFrameLevel() > qw:GetFrameLevel() or not c:isVisible(qw), "clicar na principal traz ela para a frente")
        T.clean(c)
    end)
end)
