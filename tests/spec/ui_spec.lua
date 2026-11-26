-- Janela principal, usada como o jogador usa: cliques, digitação, tooltips, menus, tamanho e posição.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local function open(opts)
    local w = H.world(opts and opts.world)
    local ids = H.sampleListings(w)
    local leader = H.login(w, { name = "Lider", account = "L" })
    local c = H.login(w, { level = 25 })
    H.search(w, c) -- abre o Looking For Group, e o GrupoFacil abre junto
    w:advance(0.2)
    return w, c, c.env.GrupoFacilFrame, ids, leader
end
local function btn(c, f, pat) return H.find(c, f, pat, true) end
local function rowOf(c, name)
    for _, child in ipairs({ c.env.GrupoFacilFrame.list:GetChildren() }) do
        if c.ui.visible(child) and child.name and (c:text(child.name) or ""):find(name, 1, true) then return child end
    end
end

describe("janela principal", function()
    it("mostra os jogadores com level, atividade e roles; status e paginação", function()
        local w, c, f = open()
        local rows = H.rows(c)
        T.eq(#rows, 3)
        T.match(rows[1], "^Tanque  Lvl 35 | Scarlet Monastery: Library")
        T.match(rows[3], "Padre.*Wailing Caverns.*{healer}")
        T.has({ c:text(f) or "" }, "") -- não quebra ao ler texto do frame
        T.ok(H.find(c, f, "6 results in total%.  Showing 3%.", true), "status")
        T.ok(H.find(c, f, "^1%-3 of 3$", true), "paginação")
        T.ok(H.find(c, f, "^Join request: Hi, I'm a level 25 Hunter", true), "prévia da mensagem")
        T.clean(c)
    end)

    it("botões de modo, ordem, level, Perto de mim, classe e role filtram a lista", function()
        local w, c, f = open()
        c:click(btn(c, f, "^Groups$")); w:advance(0.2)
        T.eq(#H.rows(c), 2)
        T.ok(btn(c, f, "^Needs$"), "rótulo vira 'Needs' no modo grupos")
        c:click(btn(c, f, "^Players$")); w:advance(0.2)
        c:click(btn(c, f, "^Sort: Level$")); w:advance(0.2)
        T.match(H.rows(c)[1], "^Arqueiro", "ordem por nome")
        local boxes = {}
        for _, ch in ipairs({ f.dungeonPanel:GetChildren() }) do if c.ui.state(ch).kind == "EditBox" then boxes[#boxes + 1] = ch end end
        c:type(boxes[1], "30"); w:advance(0.2)
        T.eq(#H.rows(c), 2)
        c:type(boxes[1], "abc"); T.eq(c:text(boxes[1]), "", "caixa numérica")
        c:click(btn(c, f, "^Near me$")); w:advance(0.2)
        T.eq(H.db(c).filters.minLevel, 22); T.eq(H.db(c).filters.maxLevel, 28)
        T.eq(#H.rows(c), 1)
        c:click(btn(c, f, "^Clear filters$")); w:advance(0.2)
        T.eq(#H.rows(c), 3)
        T.clean(c)
    end)

    it("tooltip da linha: nível, zona, ação e menu; tooltip do botão mostra o texto que sai", function()
        local w, c, f = open()
        c:click(btn(c, f, "^All$")); w:advance(0.2)
        local r = rowOf(c, "Lider")
        local tip = c:hover(r)
        T.has(tip, "^Lider$")
        T.has(tip, "Level 25")
        T.has(tip, "Leader's zone: Westfall")
        T.has(tip, "Open spots: {healer}1  {dps}1")
        T.has(tip, "Right%-click: hide, block or /who")
        local bt = c:hover(r.b1)
        T.has(bt, "^Ask the leader to join$")
        T.has(bt, "Sends: Hi, I'm a level 25 Hunter, can I join your group%?")
        T.clean(c)
    end)

    it("Pedir vaga pelo botão: vira 'Sent' e desabilita", function()
        local w, c, f = open()
        c:click(btn(c, f, "^All$")); w:advance(0.2)
        local r = rowOf(c, "Lider")
        T.eq(c:text(r.b1), "Ask to join")
        c:click(r.b1)
        w:advance(0.5)
        r = rowOf(c, "Lider")
        T.eq(c:text(r.b1), "Sent")
        T.no(r.b1:IsEnabled())
        T.clean(c)
    end)

    it("clique direito: esconder, bloquear e /who; botão Escondidos mostra e desfaz", function()
        local w, c, f = open()
        c:click(rowOf(c, "Padre"), "RightButton")
        local menu = c.env.GrupoFacilRowMenu
        T.ok(H.shown(c, menu))
        c:click(btn(c, menu, "^Hide for this session$")); w:advance(0.2)
        T.eq(#H.rows(c), 2)
        local hidden = btn(c, f, "^Hidden %(1%)$")
        T.ok(hidden)
        c:click(rowOf(c, "Arqueiro"), "RightButton")
        c:click(btn(c, menu, "^Block this player$")); w:advance(0.2)
        T.ok(btn(c, f, "^Hidden %(2%)$"))
        c:click(btn(c, f, "^Hidden %(2%)$"))
        local hm = c.env.GrupoFacilHiddenMenu
        T.ok(H.shown(c, hm))
        T.ok(H.find(c, hm, "Arqueiro  blocked", true))
        c:click(btn(c, hm, "^Unblock$")); w:advance(0.2)
        T.eq(H.db(c).blocked.arqueiro, nil)
        c:click(btn(c, hm, "^Show all$")); w:advance(0.2)
        T.eq(#H.rows(c), 3)
        c:click(rowOf(c, "Tanque"), "RightButton")
        c:click(btn(c, menu, "^Who is this%? %(/who%)$"))
        T.eq(c.data.chatInput, '/who "Tanque"')
        T.clean(c)
    end)

    it("menu de masmorras: lista as presentes com contagem e filtra", function()
        local w, c, f = open()
        c:click(btn(c, f, "^All dungeons$"))
        local m = c.env.GrupoFacilDungeonMenu
        T.ok(H.shown(c, m))
        local dm = H.find(c, m, "^Deadmines  17%-26  %(1%)$", true)
        T.ok(dm, "Deadmines com faixa e contagem")
        local check
        for _, ch in ipairs({ m:GetChildren() }) do if ch.text == dm then check = ch end end
        c:click(check); w:advance(0.2)
        T.eq(#H.rows(c), 1)
        T.ok(btn(c, f, "^Deadmines$"), "botão mostra a masmorra escolhida")
        T.clean(c)
    end)

    it("modo compacto esconde os filtros, avisa que estão ligados e persiste", function()
        local w, c, f = open()
        H.db(c).filters.minLevel = 20
        c:click(btn(c, f, "^Hide filters$")); w:advance(0.2)
        T.no(btn(c, f, "^Near me$"), "filtros recolhidos")
        T.ok(H.find(c, f, "%(filters on%)", true))
        c:reload()
        c:slash("/gf"); w:advance(0.2)
        T.ok(btn(c, c.env.GrupoFacilFrame, "^Show filters$"))
        T.clean(c)
    end)

    it("arrastar desencaixa e grava a posição; /gf dock encaixa de novo", function()
        local w, c, f = open()
        T.eq(select(2, f:GetPoint(1)), c.env.LFGParentFrame)
        c.ui.fire(f, "OnDragStart")
        f:ClearAllPoints(); f:SetPoint("TOPLEFT", c.env.UIParent, "TOPLEFT", 300, -200)
        c.ui.fire(f, "OnDragStop")
        T.eq(H.db(c).docked, false)
        T.deepEq(H.db(c).pos, { "TOPLEFT", "TOPLEFT", 300, -200 })
        c:slash("/gf dock")
        T.eq(select(2, f:GetPoint(1)), c.env.LFGParentFrame)
        T.clean(c)
    end)

    it("redimensionar: mais linhas cabem, tamanho é gravado e respeita os limites", function()
        local w, c, f = open()
        for i = 1, 30 do w.lfg:add({ leader = "S" .. i, members = { { name = "S" .. i, level = 20 + (i % 10), class = "MAGE", roles = { dps = true } } } }) end
        w:advance(4)
        H.search(w, c); w:advance(0.2)
        local before = H.ns(c).rowsVisible
        f:SetSize(f:GetWidth(), 900)
        c.ui.fire(f.list, "OnSizeChanged")
        c.ui.fire(f, "OnSizeChanged"); w:advance(0.2)
        T.ok(H.ns(c).rowsVisible > before, "mais linhas")
        local grip
        for _, ch in ipairs({ f:GetChildren() }) do if c.ui.state(ch).scripts and c.ui.state(ch).scripts.OnMouseUp then grip = ch end end
        c.ui.fire(grip, "OnMouseUp", "LeftButton")
        T.eq(H.db(c).size[2], 900)
        T.clean(c)
    end)

    it("rolar a lista e páginas < >", function()
        local w, c, f = open()
        for i = 1, 30 do w.lfg:add({ leader = "S" .. i, members = { { name = "S" .. i, level = 20, class = "MAGE", roles = { dps = true } } } }) end
        w:advance(4)
        H.search(w, c); w:advance(0.2)
        local n = H.ns(c).rowsVisible
        c:click(btn(c, f, "^>$")); w:advance(0.2)
        T.ok(H.find(c, f, "^" .. (n + 1) .. "%-", true), "página 2")
        c.ui.fire(f.list, "OnMouseWheel", 1); w:advance(0.2)
        T.ok(H.find(c, f, "^" .. (n - 2) .. "%-", true), "rolou 3 para cima")
        T.clean(c)
    end)

    it("Buscar de novo: busca, desabilita durante o intervalo, explica quando recusa", function()
        local w, c, f = open()
        w:advance(4)
        local sb = btn(c, f, "^Search again$")
        T.ok(sb:IsEnabled())
        c:click(sb)
        w:advance(0.2)
        T.no(sb:IsEnabled(), "desabilitado durante a busca")
        w:advance(4)
        T.ok(sb:IsEnabled())
        T.clean(c)
    end)

    it("restrição de chat: lista congelada em laranja, botões desligados", function()
        local w, c, f = open()
        c:click(btn(c, f, "^All$")); w:advance(0.2)
        c.chatLockdown = true
        w:advance(4)
        H.search(w, c); w:advance(0.2)
        T.ok(H.find(c, f, "list frozen", true))
        T.no(rowOf(c, "Lider").b1:IsEnabled())
        T.no(btn(c, f, "^Search again$"):IsEnabled())
        c.chatLockdown = false
    end)

    it("abrir e fechar a janela em combate não dá erro", function()
        local w, c, f = open()
        c:enterCombat()
        c:slash("/gf"); c:slash("/gf")
        c:leaveCombat()
        T.clean(c)
    end)

    it("Escape fecha os menus (UISpecialFrames)", function()
        local w, c, f = open()
        c:click(rowOf(c, "Padre"), "RightButton")
        local special = {}
        for _, n in ipairs(c.env.UISpecialFrames) do special[n] = true end
        T.ok(special.GrupoFacilRowMenu)
        f:Hide()
        T.no(H.shown(c, c.env.GrupoFacilRowMenu), "fechar a janela fecha o menu")
    end)
end)

-- Fraga, 26/11: uma lista de escolha ficou aberta ao trocar de seção e um tooltip ficou preso.
-- Toda lista do addon fecha com Esc, clique fora, troca de aba/seção e ao fechar a janela;
-- clicar dentro dela não fecha; o tooltip de um botão do addon some quando o botão some.
describe("listas de escolha e tooltips", function()
    local function special(c)
        local s = {}
        for _, n in ipairs(c.env.UISpecialFrames) do s[n] = true end
        return s
    end

    -- abre cada lista do addon e devolve { nome, quadro, dono, reabrir }
    local function menusOf(w, c, f)
        local out = {}
        local function add(name, owner, opener)
            opener()
            out[#out + 1] = { name = name, m = c.env[name], owner = owner, open = opener }
        end
        local dungeonBtn = btn(c, f, "^All dungeons$")
        add("GrupoFacilDungeonMenu", dungeonBtn, function() c:click(dungeonBtn) end)
        c:click(rowOf(c, "Padre"), "RightButton")
        c:click(btn(c, c.env.GrupoFacilRowMenu, "^Hide for this session$"))
        w:advance(0.2)
        local hiddenBtn = btn(c, f, "^Hidden %(1%)$")
        add("GrupoFacilHiddenMenu", hiddenBtn, function() c:click(hiddenBtn) end)
        local row = rowOf(c, "Arqueiro")
        add("GrupoFacilRowMenu", row, function() c:click(row, "RightButton") end)
        return out
    end

    it("listas da janela: clique fora, troca de aba, fechar a janela e Esc fecham; clicar dentro não", function()
        local w, c, f = open()
        local all = menusOf(w, c, f)
        T.eq(#all, 3)
        for _, x in ipairs(all) do
            if not H.shown(c, x.m) then x.open() end
            T.ok(H.shown(c, x.m), x.name .. " abriu")
            T.ok(special(c)[x.name], x.name .. " fecha com Esc")
            -- clicar num filho da lista (o mouse está sobre ela) não fecha pelo clique fora
            c.ui.mouseOver = x.m
            c:fireEvent("GLOBAL_MOUSE_DOWN", "LeftButton")
            c.ui.mouseOver = nil
            T.ok(H.shown(c, x.m), x.name .. " continua aberta com clique dentro")
            c:clickOutside()
            T.no(H.shown(c, x.m), x.name .. " fecha com clique fora")
            x.open()
            c:click(f.tabQuests)
            T.no(H.shown(c, x.m), x.name .. " fecha ao trocar de aba")
            c:click(f.tabDungeons)
            w:advance(0.2)
        end
        -- o botão que abriu a lista fecha a lista (não reabre no mesmo clique)
        local d = all[1]
        d.open()
        T.ok(H.shown(c, d.m))
        c:click(d.owner)
        T.no(H.shown(c, d.m), "o mesmo botão fecha")
        d.open()
        f:Hide()
        T.no(H.shown(c, d.m), "fechar a janela fecha a lista")
        T.clean(c)
    end)

    it("listas das opções (idioma e destino da indicação): trocar de seção, clique fora, fechar e Esc", function()
        local w, c = open()
        c:slash("/gf options invite")
        local of = c.env.GrupoFacilOptionsFrame
        local o = of.content
        local lists = {
            { name = "GrupoFacilShareMenu", owner = o.shareTarget },
            { name = "GrupoFacilLanguageMenu", owner = o.lang },
        }
        for _, x in ipairs(lists) do
            H.ns(c).OptionsSection("invite")
            c:click(x.owner)
            local m = c.env[x.name]
            T.ok(H.shown(c, m), x.name .. " abriu")
            T.ok(special(c)[x.name], x.name .. " fecha com Esc")
            c:click(H.find(c, of, "^Help$", true))
            T.no(H.shown(c, m), x.name .. " fecha ao trocar de seção")
            H.ns(c).OptionsSection("invite")
            c:click(x.owner)
            c:clickOutside()
            T.no(H.shown(c, m), x.name .. " fecha com clique fora")
            c:click(x.owner)
            c:click(x.owner)
            T.no(H.shown(c, m), x.name .. " o mesmo botão fecha")
            c:click(x.owner)
            of:Hide()
            T.no(H.shown(c, m), x.name .. " fecha com a janela de opções")
            c:slash("/gf options invite")
        end
        T.clean(c)
    end)

    it("tooltip de um botão do addon some quando o botão some (troca de aba, de seção ou janela fechada)", function()
        local w, c, f = open()
        local tip = c.env.GameTooltip
        local search = btn(c, f, "^Search again$")
        c:mouseEnter(search)
        T.ok(tip:IsOwned(search))
        T.ok(c.ui.visible(tip), "tooltip aberto")
        c:click(f.tabQuests) -- a aba Masmorras some com o botão embaixo do mouse
        T.no(c.ui.visible(tip), "o tooltip do Buscar de novo não fica preso")
        c:click(f.tabDungeons)
        c:mouseEnter(search)
        f:Hide()
        T.no(c.ui.visible(tip), "fechar a janela também fecha o tooltip")
        -- opções: tooltip de uma seção não fica sobre outra
        c:slash("/gf options invite")
        local o = c.env.GrupoFacilOptionsFrame.content
        c:mouseEnter(o.share)
        T.ok(c.ui.visible(tip))
        H.ns(c).OptionsSection("help")
        T.no(c.ui.visible(tip), "trocar de seção fecha o tooltip")
        -- tooltip de quadro de outro addon não é tocado
        local other = c.env.CreateFrame("Button", "OutroAddonBotao", c.env.UIParent)
        tip:SetOwner(other, "ANCHOR_RIGHT"); tip:Show()
        other:Hide()
        T.ok(c.ui.visible(tip), "quadro alheio: o addon não mexe")
        tip:Hide()
        T.clean(c)
    end)
end)
