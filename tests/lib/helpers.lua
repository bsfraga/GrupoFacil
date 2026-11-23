-- Atalhos para os testes: mundo com o GrupoFacil carregado, personagens e listagens.
local World = require("sim.world")
local H = {}

H.ROOT = H.ROOT or "."

function H.world(config)
    local w = World.new(config)
    w:addAddon(H.ROOT, "GrupoFacil")
    return w
end

-- um personagem logado, com o tempo correndo até o fim dos avisos de login
function H.login(w, opts)
    opts = opts or {}
    opts.name = opts.name or "Jogador"
    local c = w:login(opts)
    return c
end

function H.ns(c) return c.namespaces.GrupoFacil end
function H.db(c) return c.env.GrupoFacilDB end
function H.char(c) return c.env.GrupoFacilCharDB end

-- abre a janela nativa, busca (por padrão todas as masmorras) e espera os resultados chegarem
function H.search(w, c, category, activities)
    c:nativeSearch(category or 2, activities or { 1, 2, 3, 4, 5 })
    w:advance(1)
end

-- listagens prontas para testes de filtro
function H.sampleListings(w)
    local L = w.lfg
    local ids = {}
    ids.soloHunter = L:add({ leader = "Arqueiro", members = { { name = "Arqueiro", level = 30, class = "HUNTER", roles = { dps = true } } }, activityIDs = { 1 } })
    ids.soloPriest = L:add({ leader = "Padre", members = { { name = "Padre", level = 22, class = "PRIEST", roles = { healer = true, dps = true } } }, activityIDs = { 2 } })
    ids.soloWarrior = L:add({ leader = "Tanque", members = { { name = "Tanque", level = 35, class = "WARRIOR", roles = { tank = true } } }, activityIDs = { 3 } })
    ids.groupNeedsHeal = L:add({ leader = "Lider", activityIDs = { 1 }, remaining = { tank = 0, healer = 1, dps = 1 }, members = {
        { name = "Lider", level = 25, class = "WARRIOR", role = "TANK", zone = "Westfall" },
        { name = "Mago", level = 24, class = "MAGE", role = "DAMAGER" },
        { name = "Ladino", level = 26, class = "ROGUE", role = "DAMAGER" } } })
    ids.groupFull = L:add({ leader = "Cheio", activityIDs = { 4 }, remaining = { tank = 0, healer = 0, dps = 0 }, members = {
        { name = "Cheio", level = 28, class = "PALADIN", role = "TANK" }, { name = "A", level = 28, class = "PRIEST", role = "HEALER" },
        { name = "B", level = 28, class = "MAGE", role = "DAMAGER" }, { name = "C", level = 28, class = "MAGE", role = "DAMAGER" },
        { name = "D", level = 28, class = "MAGE", role = "DAMAGER" } } })
    ids.delisted = L:add({ leader = "Saiu", delisted = true, members = { { name = "Saiu", level = 30, class = "ROGUE", roles = { dps = true } } } })
    return ids
end

-- procura, entre os descendentes de root, o widget cujo texto casa com pat (Button/FontString)
function H.find(c, root, pat, visibleOnly)
    local function walk(f)
        local st = c.ui.state(f)
        local t = c:text(f)
        if t and t:find(pat) and (not visibleOnly or c.ui.visible(f)) then return f end
        for _, r in ipairs(st.regions or {}) do
            local rt = c:text(r)
            if rt and rt:find(pat) and (not visibleOnly or c.ui.visible(r)) then return r end
        end
        for _, ch in ipairs(st.children or {}) do
            local hit = walk(ch)
            if hit then return hit end
        end
    end
    return walk(root)
end

-- visível na tela?
function H.shown(c, f) return f ~= nil and c.ui.visible(f) end

-- texto de todas as linhas visíveis da lista principal
function H.rows(c)
    local out = {}
    local frame = c.env.GrupoFacilFrame
    local list = frame and frame.list
    if not list then return out end
    for _, child in ipairs({ list:GetChildren() }) do
        local s = c.ui.state(child)
        if c.ui.visible(child) and child.name then
            out[#out + 1] = c:text(child.name) .. " | " .. (c:text(child.info) or "")
        end
    end
    return out
end

return H
