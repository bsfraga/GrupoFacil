-- Diagnóstico: rastro, erros agrupados com contexto e estado, limites, sessão e comandos.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

describe("diagnóstico", function()
    it("erro dentro de uma chamada protegida é guardado com contexto, estado e contagem; avisa uma vez", function()
        local w = H.world()
        local c = H.login(w)
        local ns = H.ns(c)
        for _ = 1, 3 do ns.GuardTag("teste", function() error("falhou de propósito") end) end
        local errs = H.db(c).diag.errors
        T.eq(#errs, 1, "agrupado")
        T.eq(errs[1].count, 3)
        T.eq(errs[1].ctx, "teste")
        T.match(errs[1].msg, "falhou de propósito")
        T.eq(type(errs[1].state), "table")
        T.eq(errs[1].state.v, "dev")
        local n = 0
        for _, l in ipairs(c:chatLines()) do if l:find("logged an error") then n = n + 1 end end
        T.eq(n, 1, "um aviso por sessão")
        H.db(c).diag.errors = {}
    end)

    it("um erro num script de frame não derruba nada e vai para o diagnóstico", function()
        local w = H.world()
        local c = H.login(w)
        local ns = H.ns(c)
        local f = c.env.CreateFrame("Frame")
        f:SetScript("OnShow", ns.D.Wrap("frame de teste", function() error("x") end))
        f:Hide(); f:Show()
        T.eq(H.db(c).diag.errors[1].ctx, "frame de teste")
        T.eq(#c:luaErrors(), 0, "nenhum erro escapou para o jogo")
        H.db(c).diag.errors = {}
    end)

    it("rastro tem limite de 500 linhas e erros de 60; sobrevive ao /reload e conta sessões", function()
        local w = H.world()
        local c = H.login(w)
        local ns = H.ns(c)
        for i = 1, 600 do ns.D.Trace("T", "linha %d", i) end
        for i = 1, 70 do ns.GuardTag("e", function() error("erro " .. i) end) end
        local d = H.db(c).diag
        T.eq(#d.trace <= 500, true)
        T.eq(#d.errors, 60)
        local s = d.session
        c:reload()
        T.eq(H.db(c).diag.session, s + 1)
        T.eq(#H.db(c).diag.errors, 60, "erros ficam no disco")
        c:slash("/gf diag clear")
        T.eq(#H.db(c).diag.errors, 0)
        T.has(c:chatLines(), "diagnostics cleared")
    end)

    it("crash antes do /reload perde o rastro da sessão (o jogo só grava no reload ou logout)", function()
        local w = H.world()
        local c = H.login(w)
        H.ns(c).D.Trace("T", "antes do crash")
        c:crash()
        c = H.login(w)
        local found
        for _, t in ipairs(H.db(c).diag.trace) do if t.m == "antes do crash" then found = true end end
        T.no(found)
    end)

    it("/gf diag resume erros e últimos eventos; /gf diag snap grava um retrato", function()
        local w = H.world()
        local c = H.login(w)
        H.ns(c).GuardTag("x", function() error("visível no resumo") end)
        c:clearChat()
        c:slash("/gf diag")
        T.has(c:chatLines(), "distinct errors")
        T.has(c:chatLines(), "visível no resumo")
        T.has(c:chatLines(), "latest events")
        c:slash("/gf diag snap")
        T.ok(H.db(c).diag.snapshot.manual)
        T.has(c:chatLines(), "snapshot saved")
        H.db(c).diag.errors = {}
    end)

    it("busca nativa presa em Searching só vai para o rastro, com contador (não é erro do addon)", function()
        local w = H.world()
        local c = H.login(w)
        w.lfg.noAnswer = true
        c:nativeSearch(2)
        w:advance(13)
        T.eq(#H.db(c).diag.errors, 0)
        T.eq(H.db(c).diag.nativeStuck, 1)
        local found
        for _, t in ipairs(H.db(c).diag.trace) do if t.m:find("presa em Searching") then found = true end end
        T.ok(found, "no rastro")
        T.hasnt(c:chatLines(), "logged an error")
    end)

    it("amostras dos resultados crus são guardadas (até 16) para análise", function()
        local w = H.world()
        H.sampleListings(w)
        local c = H.login(w)
        for _ = 1, 8 do H.search(w, c); w:advance(3) end
        local s = H.db(c).diag.samples
        T.ok(#s > 0)
        T.ok(#s <= 16)
        T.clean(c)
    end)

    it("ADDON_ACTION_BLOCKED de outro addon só vai para o rastro; do GrupoFacil vira erro", function()
        local w = H.world()
        local c = H.login(w)
        c:fireEvent("ADDON_ACTION_BLOCKED", "OutroAddon", "CastSpell()")
        T.eq(#H.db(c).diag.errors, 0)
        c:fireEvent("ADDON_ACTION_BLOCKED", "GrupoFacil", "ReloadUI()")
        T.eq(#H.db(c).diag.errors, 1)
        H.db(c).diag.errors = {}
    end)

    it("valores secretos no rastro não dão erro", function()
        local w = H.world()
        local c = H.login(w)
        local s = c.env.issecretvalue and require("sim.client").secret()
        H.ns(c).D.Trace("S", "valor %s", H.ns(c).D.str(s))
        H.ns(c).D.Trace("S", s)
        T.clean(c)
    end)
end)
