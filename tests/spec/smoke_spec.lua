-- Fumaça: o caminho feliz completo, de ponta a ponta, em variações do cliente.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local VARIANTS = {
    { name = "cliente padrão" },
    { name = "mensagem longa dá erro Lua (tooLong=error)", world = { tooLong = "error" } },
    { name = "SendAddonMessage devolve booleano (cliente antigo)", world = { addonReturn = "bool" } },
    { name = "SendAddonMessage sem retorno", world = { addonReturn = "nil" } },
    { name = "offline responde TargetOffline (12.x)", world = { offline = "enum" } },
    { name = "throttle também em whisper fora de instância", world = { throttle = { bucket = 10, regen = 1, whispers = "always" } } },
    { name = "latência alta (1,5 s)", world = { latency = 1.5 } },
    { name = "sem a API antiga GetAddOnMetadata", world = { noLegacyAddonAPI = true } },
    { name = "minimapa quadrado e sem atlas de role", world = { minimapShape = "SQUARE", atlases = false } },
}

local function happyPath(cfg)
    cfg = cfg or {}
    cfg.beforeAddonLoaded = function(_, ns) ns.BUG_ADMINS = { "Bael" } end
    local w = H.world(cfg)
    H.sampleListings(w)
    local leader = H.login(w, { name = "Lider", account = "L" })
    local admin = H.login(w, { name = "Bael", account = "AUTOR" })
    local c = H.login(w, { account = "J", level = 25 })
    w:advance(8)
    -- busca, filtros, pedido de vaga
    H.search(w, c)
    w:advance(0.3)
    T.ok(H.shown(c, c.env.GrupoFacilFrame), "abriu junto com o LFG")
    H.db(c).filters.mode = "groups"
    H.ns(c).Refresh("t"); w:advance(0.2)
    local row
    for _, ch in ipairs({ c.env.GrupoFacilFrame.list:GetChildren() }) do
        if c.ui.visible(ch) and ch.entry and ch.entry.name == "Lider" then row = ch end
    end
    T.ok(row, "linha do Lider")
    c:click(row.b1)
    w:advance(2)
    T.has(c:chatLines(), "request sent to Lider")
    -- report de bug pela janela
    c:slash("/gf bug")
    local bf = c.env.GrupoFacilBugFrame
    c:type(bf.note.box, "Teste de fumaça: a lista piscou")
    c:click(bf.send)
    local id = H.ns(c).MyBugReports()[1].id
    w:advance(60)
    T.ok(H.db(admin).inbox[id], "chegou ao admin")
    admin:reload()
    w:advance(60)
    T.eq(H.ns(c).MyBugReports()[1].state, "done", "confirmado pelo autor depois de gravar no disco")
    T.has(c:chatLines(), "received and saved by the author")
    -- reload e logout do jogador sem perder nada
    c:reload(); w:advance(2)
    c:logout(); c = H.login(w, { name = "Jogador", account = "J" }); w:advance(2)
    T.clean(c); T.clean(admin)
    return w
end

describe("fumaça", function()
    for _, v in ipairs(VARIANTS) do
        it("caminho feliz completo: " .. v.name, function() happyPath(v.world) end)
    end

    for _, lang in ipairs({ "en", "pt", "es", "mx", "de", "fr" }) do
        it("login e janela em " .. lang .. " sem erro", function()
            local w = H.world()
            H.sampleListings(w)
            local c = H.login(w)
            H.db(c).language = lang
            c:reload()
            H.search(w, c); w:advance(0.3)
            c:slash("/gf options"); c:slash("/gf bug"); c:slash("/gf tour")
            w:advance(2)
            T.clean(c)
        end)
    end
end)
