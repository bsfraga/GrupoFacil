-- O "mundo": relógio controlado, rede entre clientes (addon whisper e whisper de chat),
-- disco (SavedVariables por conta e por personagem) e o Looking For Group do servidor.
local Client = require("sim.client")

local World = {}
World.__index = World

local function parseToc(dir, name)
    local f = assert(io.open(dir .. "/" .. name .. ".toc", "rb"))
    local toc = { dir = dir, meta = {}, files = {}, savedVariables = {}, savedVariablesPerCharacter = {} }
    for line in f:lines() do
        line = line:gsub("\r$", "")
        local k, v = line:match("^##%s*([^:]+):%s*(.-)%s*$")
        if k then
            toc.meta[k] = v
            if k == "SavedVariables" then for n in v:gmatch("[^,%s]+") do table.insert(toc.savedVariables, n) end end
            if k == "SavedVariablesPerCharacter" then for n in v:gmatch("[^,%s]+") do table.insert(toc.savedVariablesPerCharacter, n) end end
        elseif line:match("%S") and not line:match("^#") then
            table.insert(toc.files, (line:gsub("\\", "/"):gsub("%s+$", "")))
        end
    end
    f:close()
    return toc
end
World.parseToc = parseToc

-- config: ver DEFAULTS abaixo; cada teste pode mudar o que precisar.
local DEFAULTS = {
    latency = 0.08,              -- s entre enviar e chegar (whisper/addon)
    frameTime = 1 / 30,          -- duração de um quadro quando há OnUpdate
    reloadTime = 0,              -- s em que o cliente fica fora durante o /reload
    -- SendAddonMessage
    addonReturn = "enum",        -- "enum" (12.x), "bool" (antigo), "nil" (sem retorno), "wrapped" (true + enum)
    maxMessage = 255,            -- bytes por mensagem
    prefixCounts = true,         -- o prefixo conta no limite (pior caso; não confirmado no 1.60.1)
    tooLong = "enum",            -- "enum" (InvalidMessage), "error" (erro Lua) ou "truncate"
    offline = "system",          -- "system" (sucesso + "No player named..."), "enum" (TargetOffline, 12.0)
    throttle = { bucket = 10, regen = 1, whispers = "instance" }, -- "always", "instance" (doc atual) ou "never"
    reloadUIBlocked = true,      -- ReloadUI() chamado pelo addon é bloqueado (visto no Forever)
    lfgLatency = 0.3,            -- s até chegar o resultado da busca
    lfgThrottle = { count = 3, window = 2 }, -- 3 buscas em 2 s -> "throttled"
}

function World.new(config)
    local w = setmetatable({}, World)
    w.config = {}
    for k, v in pairs(DEFAULTS) do w.config[k] = v end
    for k, v in pairs(config or {}) do w.config[k] = v end
    w.now = 0
    w.epoch0 = config and config.epoch or 1795000000 -- ~2026-11-17
    w.realm = (config and config.realm) or "Forever"
    w.clients = {}
    w.online = {}       -- [nome em minúsculas] = cliente
    w.disk = {}         -- [conta] = { account = {[addon]=texto}, chars = {[char]={[addon]=texto}} }
    w.queue = {}        -- eventos do mundo {t, seq, fn}
    w.seq = 0
    w.timers = {}       -- {t, seq, client, fn, interval, left, handle}
    w.secureHooks = setmetatable({}, { __mode = "k" })
    w.inaccessible = setmetatable({}, { __mode = "k" })
    w.taint = {}
    w.blizzardWrites = {}
    w.addons = {}
    w.enabledAddons = {}
    w.netLog = {}
    w.net = require("sim.net").new(w)
    w.lfg = require("sim.lfg").new(w)
    return w
end

function World:addAddon(dir, name)
    self.addons[name] = parseToc(dir, name)
    table.insert(self.enabledAddons, name)
end

function World:epochNow() return self.epoch0 + math.floor(self.now) end
function World:diskFor(account)
    local d = self.disk[account]
    if not d then d = { account = {}, chars = {} }; self.disk[account] = d end
    return d
end

------------------------------------------------------------------------ agenda
function World:after(dt, fn)
    self.seq = self.seq + 1
    table.insert(self.queue, { t = self.now + math.max(0, dt), seq = self.seq, fn = fn })
end

function World:clientTimer(c, sec, fn, iterations)
    self.seq = self.seq + 1
    sec = math.max(0, tonumber(sec) or 0)
    local handle = { cancelled = false }
    function handle:Cancel() self.cancelled = true end
    function handle:IsCancelled() return self.cancelled end
    local t = { t = self.now + sec, seq = self.seq, client = c, fn = fn, interval = sec, left = iterations, handle = handle,
        nextFrame = sec == 0 }
    table.insert(self.timers, t)
    if iterations then return handle end
end

function World:cancelTimers(c)
    for i = #self.timers, 1, -1 do if self.timers[i].client == c then table.remove(self.timers, i) end end
end

local function earliest(list)
    local best, bi
    for i, e in ipairs(list) do
        if not best or e.t < best.t or (e.t == best.t and e.seq < best.seq) then best, bi = e, i end
    end
    return best, bi
end

local function anyOnUpdate(self)
    for _, c in ipairs(self.clients) do
        if c.state == "online" and c.ui and c.ui.hasOnUpdate() then return true end
    end
    return false
end

-- Avança o relógio rodando timers, entregas e OnUpdate na ordem certa.
function World:advance(seconds)
    local target = self.now + seconds
    local guard = 0
    while true do
        guard = guard + 1
        if guard > 2000000 then error("advance: laço sem fim") end
        local q = earliest(self.queue)
        local tm = earliest(self.timers)
        local nextT = target
        if q and q.t < nextT then nextT = q.t end
        if tm and tm.t < nextT then nextT = tm.t end
        local stepping = anyOnUpdate(self)
        local frameEnd = self.now + self.config.frameTime
        if stepping and frameEnd < nextT then nextT = frameEnd end
        if nextT > target then nextT = target end
        local elapsed = nextT - self.now
        self.now = nextT
        -- eventos do mundo vencidos
        while true do
            local e, i = earliest(self.queue)
            if not e or e.t > self.now + 1e-9 then break end
            table.remove(self.queue, i)
            e.fn()
        end
        while true do
            local t, i = earliest(self.timers)
            if not t or t.t > self.now + 1e-9 then break end
            if t.handle.cancelled or t.client.state ~= "online" then
                table.remove(self.timers, i)
            else
                t.left = t.left and (t.left - 1)
                if t.left and t.left > 0 then
                    self.seq = self.seq + 1
                    t.t, t.seq = self.now + math.max(t.interval, 0.001), self.seq
                else
                    table.remove(self.timers, i)
                end
                local h = t.handle
                if t.left ~= nil then t.client:protect(t.fn, h) else t.client:protect(t.fn) end
            end
        end
        if stepping or elapsed > 0 then
            for _, c in ipairs(self.clients) do
                if c.state == "online" and c.ui then c.ui.tick(elapsed) end
            end
        end
        if self.now >= target - 1e-9 then break end
    end
    self.now = target
end

------------------------------------------------------------------------ personagens
function World:login(opts)
    assert(opts.name, "login sem nome")
    -- Forever: dois "Bagael" convivem se o sobrenome muda; a chave é o nome inteiro
    local key = (opts.surname and (opts.name .. " " .. opts.surname) or opts.name):lower()
    local c = self.online[key]
    if c then error("personagem já está online: " .. opts.name) end
    for _, old in ipairs(self.clients) do
        if old.name == opts.name and old.surname == opts.surname and old.state == "offline" then c = old end
    end
    if c then
        for k, v in pairs(opts) do c.opts[k] = v end
    else
        c = Client.new(self, opts)
        table.insert(self.clients, c)
    end
    self.online[key] = c
    c:start(false)
    return c
end

function World:setOffline(c)
    local key = (c.surname and (c.name .. " " .. c.surname) or c.name):lower()
    if self.online[key] == c then self.online[key] = nil end
end

-- quem recebe mensagens agora (cliente carregado e não recarregando)
-- Com sobrenome (Forever) o alvo precisa ser "Nome Sobrenome"; só o nome não acha ninguém
-- (o modelo mais estrito: um addon que manda o nome completo funciona dos dois jeitos).
function World:reachable(name)
    local short = tostring(name):match("^[^%-]+") or name
    local first, last = short:match("^(%S+)%s+(.+)$")
    local c = self.online[short:lower()] -- "nome sobrenome" casa direto com a chave
    if c and c.surname and not last then c = nil end
    if not c then return nil, "offline" end
    return c, c.state
end

function World:deliverInvite(from, name)
    local c = self:reachable(name)
    if c and c.state == "online" then
        self:after(self.config.latency, function()
            if c.state == "online" then c:fireEvent("PARTY_INVITE_REQUEST", from.name) end
        end)
    end
end

------------------------------------------------------------------------ taint da janela nativa
-- Os frames da Blizzard ficam atrás de um proxy: escrita vinda de arquivo do addon é registrada.
function World:watchWrites(c, frame, label)
    local fields = {}
    for k, v in pairs(frame) do fields[k] = v; frame[k] = nil end
    local world = self
    local mt = getmetatable(frame)
    local methods = mt.__index
    setmetatable(frame, {
        __index = function(_, k) local v = fields[k]; if v ~= nil then return v end; return methods[k] end,
        __newindex = function(_, k, v)
            if not world.allowBlizzardWrite then
                local src = debug.getinfo(2, "S")
                local who = src and src.source or "?"
                if who:find("Interface/AddOns/", 1, true) then
                    table.insert(world.blizzardWrites, { frame = label, key = k, by = who })
                    world.taint[frame] = world.taint[frame] or {}
                    world.taint[frame][k] = who:match("AddOns/([^/]+)") or who
                end
            end
            fields[k] = v
        end,
    })
end
function World:blizzardWrite(frame, k, v)
    self.allowBlizzardWrite = true
    frame[k] = v
    self.allowBlizzardWrite = false
end

return World
