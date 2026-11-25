-- Filtros, ordenação, "precisa de você", esconder e bloquear.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local function names(ns)
    local out = {}
    for i, e in ipairs(ns.Visible()) do out[i] = e.name end
    return table.concat(out, ",")
end

local function setup(mode)
    local w = H.world()
    local ids = H.sampleListings(w)
    local c = H.login(w)
    H.db(c).filters.mode = mode or "all"
    H.search(w, c)
    return w, c, H.ns(c), H.db(c).filters, ids
end

describe("filtros e lista", function()
    it("modo: jogadores, grupos e todos; anunciado fora some por padrão", function()
        local _, c, ns, f = setup("players")
        T.eq(names(ns), "Tanque,Arqueiro,Padre", "por level, do maior")
        f.mode = "groups"
        T.eq(names(ns), "Cheio,Lider")
        f.mode = "all"
        T.eq(#ns.Visible(), 5)
        f.hideDelisted = false
        T.eq(#ns.Visible(), 6)
        T.clean(c)
    end)

    it("faixa de level e classes", function()
        local _, _, ns, f = setup("players")
        f.minLevel, f.maxLevel = 25, 32
        T.eq(names(ns), "Arqueiro")
        f.minLevel, f.maxLevel = nil, nil
        f.classes = { PRIEST = true, WARRIOR = true }
        T.eq(names(ns), "Tanque,Padre")
    end)

    it("role: solo pelas roles marcadas; grupo pelas vagas reais", function()
        local _, _, ns, f = setup("all")
        f.roles = { healer = true }
        T.eq(names(ns), "Lider,Padre")
        f.roles = { tank = true }
        T.eq(names(ns), "Tanque", "grupo cheio e sem vaga de tank não entram")
        local rc = ns.RoleCounts()
        T.eq(rc.healer, 2); T.eq(rc.dps, 3)
    end)

    it("vagas estimadas quando o jogo não manda REMAINING", function()
        local w = H.world()
        w.lfg:add({ leader = "SemTank", members = { { name = "SemTank", level = 20, class = "MAGE", role = "DAMAGER" },
            { name = "H", level = 20, class = "PRIEST", role = "HEALER" } } })
        local c = H.login(w)
        H.search(w, c)
        local ns = H.ns(c)
        local e
        for _, x in pairs(ns.entries) do e = x end
        T.eq(ns.GroupNeeds(e, "tank"), true)
        T.eq(ns.GroupNeeds(e, "healer"), false)
        T.eq(ns.GroupNeeds(e, "dps"), true)
    end)

    it("masmorra: filtra e a lista de masmorras conta pelos outros filtros", function()
        local _, _, ns, f = setup("all")
        f.activities = { [1] = true }
        T.eq(names(ns), "Arqueiro,Lider")
        local acts = ns.ActivitiesPresent()
        T.eq(acts[1].name, "Deadmines", "ordenado pelo level sugerido")
        local byName = {}
        for _, a in ipairs(acts) do byName[a.name] = a.count end
        T.eq(byName.Deadmines, 2); T.eq(byName["Wailing Caverns"], 1)
        f.activities = { [5] = true }
        local found
        for _, a in ipairs(ns.ActivitiesPresent()) do if a.name == "Gnomeregan" then found = a end end
        T.ok(found, "marcada continua na lista"); T.eq(found.count, 0)
    end)

    it("ordenação: amigos primeiro; level, nome ou idade; desempate estável", function()
        local w = H.world()
        w.lfg:add({ leader = "Bia", level = 20, age = 10 })
        w.lfg:add({ leader = "Ana", level = 20, age = 300 })
        w.lfg:add({ leader = "Caio", level = 40, age = 50 })
        w.lfg:add({ leader = "Zeca", level = 10, age = 500 })
        local c = H.login(w)
        c.data.friends = { "Zeca" }
        H.search(w, c)
        local ns, f = H.ns(c), H.db(c).filters
        T.eq(names(ns), "Zeca,Caio,Ana,Bia")
        f.sort = "name"
        T.eq(names(ns), "Zeca,Ana,Bia,Caio")
        f.sort = "age"
        T.eq(names(ns), "Zeca,Bia,Caio,Ana")
    end)

    it("precisa de você: grupo com vaga na sua role marcada", function()
        local _, c, ns = setup("groups")
        c.data.roles = { tank = false, healer = true, dps = false }
        local vis = ns.Visible()
        local byName = {}
        for _, e in ipairs(vis) do byName[e.name] = e.needsMe end
        T.eq(byName.Lider, "healer"); T.eq(byName.Cheio, nil)
        c.data.roles = { tank = true, healer = false, dps = false }
        for _, e in ipairs(ns.Visible()) do T.eq(e.needsMe, nil) end
    end)

    it("esconder nesta sessão: some, conta como escondido, volta com Undismiss e some no /reload", function()
        local _, c, ns = setup("players")
        local e = ns.Visible()[1]
        ns.Dismiss(e)
        T.eq(names(ns), "Arqueiro,Padre")
        T.eq(ns.hiddenCount, 1)
        T.eq(ns.HiddenList()[1].kind, "session")
        ns.Undismiss(e.key)
        T.eq(names(ns), "Tanque,Arqueiro,Padre")
        ns.Dismiss(e)
        c:reload()
        T.eq(next(H.ns(c).dismissed), nil)
    end)

    it("bloquear: persiste no disco, /gf unblock aceita começo do nome e avisa ambiguidade", function()
        local w, c, ns = setup("players")
        local function byName(n) for _, e in ipairs(ns.Visible()) do if e.name == n then return e end end end
        ns.Block(byName("Tanque"))
        T.has(c:chatLines(), "Tanque blocked")
        T.eq(H.db(c).blocked.tanque, "Tanque")
        c:reload()
        H.search(w, c)
        ns = H.ns(c)
        T.eq(names(ns), "Arqueiro,Padre")
        H.db(c).blocked.tanquinho = "Tanquinho"
        c:slash("/gf unblock tanq")
        T.has(c:chatLines(), "more than one blocked player matches; type the full name: Tanque, Tanquinho")
        c:slash("/gf unblock Tanque")
        T.has(c:chatLines(), "Tanque unblocked")
        c:slash("/gf unblock ninguem")
        T.has(c:chatLines(), "not in the blocked list: ninguem")
        c:slash("/gf unblock all")
        T.eq(next(H.db(c).blocked), nil)
        T.clean(c)
    end)

    it("ignorado do jogo some da lista", function()
        local w = H.world()
        H.sampleListings(w)
        local c = H.login(w)
        c.data.ignored = { "Padre" }
        H.search(w, c)
        T.eq(names(H.ns(c)), "Tanque,Arqueiro")
    end)

    it("listagem que sai (isDelisted por atualização) some da lista", function()
        local w = H.world()
        local ids = H.sampleListings(w)
        local c = H.login(w)
        H.search(w, c)
        w.lfg:update(ids.soloPriest, { delisted = true })
        w:advance(0.2)
        T.eq(names(H.ns(c)), "Tanque,Arqueiro")
        T.clean(c)
    end)
end)
