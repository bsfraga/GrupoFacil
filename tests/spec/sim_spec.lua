-- Testes do próprio simulador: se ele mentir, os outros testes mentem junto.
local T = require("t")
local H = require("helpers")
local World = require("sim.world")
local SV = require("sim.serialize")
local describe, it = T.describe, T.it

local function bare(config)
    local w = World.new(config) -- sem addons
    local c = w:login({ name = "Teste" })
    return w, c
end
local function run(c, code)
    local fn = assert(loadstring(code))
    setfenv(fn, c.env)
    return fn()
end

describe("simulador", function()
    it("ambiente igual ao do WoW: sem os, io, require, dofile; com strsplit, wipe, date, time", function()
        local w, c = bare()
        for _, k in ipairs({ "os", "io", "require", "dofile", "loadfile", "package", "debug" }) do
            T.eq(c.env[k], nil, k .. " não existe no cliente")
        end
        T.eq(run(c, "return select('#', strsplit('-', 'Nome-Reino-X'))"), 3)
        T.eq(run(c, "return (strsplit('-', 'Nome-Reino'))"), "Nome")
        T.eq(run(c, "local a, b = strsplit('~', 'a~~b'); return b"), "")
        T.eq(run(c, "return strtrim('  x  ')"), "x")
        T.eq(run(c, "local t = {1,2}; wipe(t); return #t"), 0)
        T.eq(run(c, "return type(time())"), "number")
        T.eq(run(c, "return _VERSION"), "Lua 5.1")
        T.eq(_VERSION, "Lua 5.1", "a suíte roda em Lua 5.1, a mesma linguagem do WoW")
    end)

    it("relógio controlado: GetTime, time e C_Timer andam juntos com o advance", function()
        local w, c = bare()
        local t0, e0 = run(c, "return GetTime()"), run(c, "return time()")
        run(c, "FIRED = {}; C_Timer.After(5, function() FIRED[#FIRED+1] = GetTime() end); TICK = 0; TK = C_Timer.NewTicker(1, function() TICK = TICK + 1 end, 3)")
        w:advance(4.9)
        T.eq(#c.env.FIRED, 0)
        T.eq(c.env.TICK, 3, "ticker com 3 iterações")
        w:advance(0.2)
        T.near(c.env.FIRED[1] - t0, 5, 1e-6)
        T.eq(run(c, "return time()") - e0, 5)
        run(c, "C = 0; local h = C_Timer.NewTicker(1, function(self) C = C + 1; if C == 2 then self:Cancel() end end)")
        w:advance(10)
        T.eq(c.env.C, 2, "Cancel dentro do callback")
    end)

    it("erros de script não param os outros frames e ficam registrados", function()
        local w, c = bare()
        run(c, [[
            local a = CreateFrame("Frame"); a:RegisterEvent("PLAYER_LEVEL_UP"); a:SetScript("OnEvent", function() error("boom") end)
            local b = CreateFrame("Frame"); b:RegisterEvent("PLAYER_LEVEL_UP"); b:SetScript("OnEvent", function() OK = true end)
        ]])
        c:fireEvent("PLAYER_LEVEL_UP")
        T.ok(c.env.OK)
        T.eq(#c:luaErrors(), 1)
        T.match(c:luaErrors()[1], "boom")
    end)

    it("como o cliente: método inexistente, script inexistente e evento desconhecido dão erro", function()
        local w, c = bare()
        T.no(pcall(run, c, "CreateFrame('Frame'):SetText('x')"), "Frame não tem SetText")
        T.no(pcall(run, c, "CreateFrame('Frame'):SetScript('OnClick', function() end)"), "Frame não tem OnClick")
        T.no(pcall(run, c, "CreateFrame('Frame'):RegisterEvent('NAO_EXISTE')"))
        T.no(pcall(run, c, "CreateFrame('Frame', nil, nil, 'TemplateQueNaoExiste')"))
    end)

    it("OnShow/OnHide seguem a visibilidade real (pai escondido esconde o filho)", function()
        local w, c = bare()
        run(c, [[
            LOG = {}
            P = CreateFrame("Frame"); K = CreateFrame("Frame", nil, P)
            K:SetScript("OnShow", function() LOG[#LOG+1] = "show" end)
            K:SetScript("OnHide", function() LOG[#LOG+1] = "hide" end)
            P:Hide(); P:Show(); K:Hide(); P:Hide(); P:Show(); K:Show()
        ]])
        T.eq(table.concat(c.env.LOG, ","), "hide,show,hide,show")
        T.ok(c.env.K:IsVisible())
        run(c, "P:Hide()")
        T.ok(c.env.K:IsShown())
        T.no(c.env.K:IsVisible())
    end)

    it("CheckButton troca antes do OnClick; botão desabilitado ignora clique", function()
        local w, c = bare()
        run(c, [[
            CB = CreateFrame("CheckButton", nil, UIParent, "UICheckButtonTemplate")
            CB:SetScript("OnClick", function(self) SEEN = self:GetChecked() end)
            B = CreateFrame("Button", nil, UIParent, "UIPanelButtonTemplate")
            B:SetScript("OnClick", function() CLICKED = true end)
            B:Disable()
        ]])
        c:click(c.env.CB)
        T.eq(c.env.SEEN, true)
        c:click(c.env.B)
        T.eq(c.env.CLICKED, nil)
    end)

    it("tamanho vem das âncoras quando não foi fixado", function()
        local w, c = bare()
        run(c, [[
            F = CreateFrame("Frame", nil, UIParent); F:SetSize(400, 600); F:SetPoint("CENTER")
            L = CreateFrame("Frame", nil, F); L:SetPoint("TOPLEFT", 10, -222); L:SetPoint("BOTTOMRIGHT", -10, 66)
        ]])
        T.eq(c.env.L:GetWidth(), 380)
        T.eq(c.env.L:GetHeight(), 600 - 222 - 66)
    end)

    it("frame protegido (e o pai dele) não muda em combate: ADDON_ACTION_BLOCKED", function()
        local w, c = bare()
        run(c, [[
            P = CreateFrame("Frame", "Pai", UIParent); P:Hide()
            S = CreateFrame("Button", "Seguro", P, "SecureActionButtonTemplate")
            EV = CreateFrame("Frame"); EV:RegisterEvent("ADDON_ACTION_BLOCKED"); EV:SetScript("OnEvent", function(_, _, who, fn) BLOCKED = fn end)
        ]])
        c:enterCombat()
        run(c, "P:Show()")
        T.no(c.env.P:IsShown(), "pai de frame protegido não abre em combate")
        T.match(c.env.BLOCKED, "Show")
        c:leaveCombat()
        run(c, "P:Show()")
        T.ok(c.env.P:IsShown())
    end)

    it("SavedVariables: só reload/logout gravam; crash perde; acentos e bytes sobrevivem", function()
        local w = H.world()
        local c = H.login(w, { name = "Gravador", account = "C" })
        c.env.GrupoFacilDB.teste = { texto = "ação ~|\n\0\255 fim", n = 1.5, lista = { 1, 2, 3 }, f = function() end, [true] = "sim" }
        c:reload()
        local t = c.env.GrupoFacilDB.teste
        T.eq(t.texto, "ação ~|\n\0\255 fim")
        T.eq(t.n, 1.5)
        T.eq(#t.lista, 3)
        T.eq(t.f, nil, "função não é gravada")
        T.eq(t[true], "sim")
        c.env.GrupoFacilDB.teste = "depois"
        c:crash()
        c = H.login(w, { name = "Gravador", account = "C" })
        T.eq(type(c.env.GrupoFacilDB.teste), "table", "crash não gravou 'depois'")
        c.env.GrupoFacilCharDB.meu = 1
        c:logout()
        local d = H.login(w, { name = "Outro", account = "C" })
        T.eq(type(d.env.GrupoFacilDB.teste), "table", "SavedVariables da conta é compartilhado")
        T.eq(d.env.GrupoFacilCharDB.meu, nil, "SavedVariablesPerCharacter não")
    end)

    it("ordem de carga do cliente: arquivos, depois SavedVariables, depois ADDON_LOADED", function()
        local w = H.world()
        local seen
        local c = H.login(w, { name = "Ordem", beforeAddonLoaded = function(cl) seen = cl.env.GrupoFacilDB end })
        T.eq(seen, nil, "SavedVariables ainda não existe quando os arquivos rodam")
        T.ok(c.env.GrupoFacilDB)
    end)

    it("rede: 255 bytes contando o prefixo, NUL proibido, prefixo registrado para receber", function()
        local w = World.new()
        local a = w:login({ name = "Ana" })
        local b = w:login({ name = "Beto" })
        local R = a.env.Enum.SendAddonMessageResult
        b.env.C_ChatInfo.RegisterAddonMessagePrefix("TESTE")
        run(b, "GOT = {}; local f = CreateFrame('Frame'); f:RegisterEvent('CHAT_MSG_ADDON'); f:SetScript('OnEvent', function(_, _, p, m, ch, s) GOT[#GOT+1] = s .. ':' .. m end)")
        local send = a.env.C_ChatInfo.SendAddonMessage
        T.eq(send("TESTE", ("x"):rep(250), "WHISPER", "Beto"), R.Success)
        T.eq(send("TESTE", ("x"):rep(251), "WHISPER", "Beto"), R.InvalidMessage, "250 + prefixo de 5 = 255")
        T.eq(send("TESTE", "a\0b", "WHISPER", "Beto"), R.InvalidMessage)
        T.eq(send(("P"):rep(17), "x", "WHISPER", "Beto"), R.InvalidPrefix)
        T.eq(send("OUTRO", "x", "WHISPER", "Beto"), R.Success)
        w:advance(1)
        T.eq(#b.env.GOT, 1, "só o prefixo registrado chega")
        T.eq(b.env.GOT[1], "Ana-Forever:" .. ("x"):rep(250), "remetente vem com o reino")
    end)

    it("rede: whisper para offline gera a linha de sistema; modo 12.x devolve TargetOffline", function()
        local w = World.new()
        local a = w:login({ name = "Ana" })
        a.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Ninguem")
        w:advance(1)
        T.has(a:chatLines("system"), "No player named 'Ninguem' is currently playing")
        local w2 = World.new({ offline = "enum" })
        local b = w2:login({ name = "Ana" })
        T.eq(b.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Ninguem"), b.env.Enum.SendAddonMessageResult.TargetOffline)
    end)

    it("rede: facção diferente não recebe whisper", function()
        local w = World.new()
        local a = w:login({ name = "Ana", faction = "Alliance" })
        local h = w:login({ name = "Orc", faction = "Horde" })
        h.env.C_ChatInfo.RegisterAddonMessagePrefix("TESTE")
        a.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Orc")
        w:advance(1)
        T.has(a:chatLines("system"), "No player named 'Orc'")
    end)

    it("rede: throttle por prefixo (10 de franquia, +1 por segundo) dentro de instância", function()
        local w = World.new()
        local a = w:login({ name = "Ana" })
        w:login({ name = "Beto" })
        a.data.inInstance = true
        local R = a.env.Enum.SendAddonMessageResult
        local ok = 0
        for _ = 1, 15 do if a.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Beto") == R.Success then ok = ok + 1 end end
        T.eq(ok, 10)
        w:advance(3)
        ok = 0
        for _ = 1, 5 do if a.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Beto") == R.Success then ok = ok + 1 end end
        T.eq(ok, 3)
        a.data.inInstance = false
        T.eq(a.env.C_ChatInfo.SendAddonMessage("TESTE", "x", "WHISPER", "Beto"), R.Success, "fora de instância whisper não tem throttle")
    end)

    it("valores secretos: issecretvalue reconhece e qualquer uso dá erro", function()
        local w, c = bare()
        local Client = require("sim.client")
        c.env.S = Client.secret()
        T.eq(run(c, "return issecretvalue(S)"), true)
        T.no(pcall(run, c, "return S .. 'x'"))
        T.no(pcall(run, c, "return S < 1"))
        T.no(pcall(run, c, "return S.campo"))
        T.eq(run(c, "return issecretvalue(1)"), false)
    end)

    it("serializador: arquivo gravado é Lua válido e relido igual", function()
        local env = { X = { a = { b = { "c" } }, ["chave com espaço"] = 1, [10] = true } }
        local text = SV.dump({ "X", "Y" }, env)
        local env2 = {}
        T.ok(SV.load(text, env2))
        T.deepEq(env2.X, env.X)
        T.eq(env2.Y, nil)
    end)
end)
