-- Rede do servidor simulado: addon messages e whispers de chat entre personagens.
-- Modela: limite de 255 bytes, prefixo de até 16, NUL proibido, prefixo registrado para receber,
-- throttle por prefixo (10 de franquia, +1/s), whisper para offline (linha de sistema ou
-- TargetOffline), facção, perda e atraso de pacotes, e as várias formas de retorno da API.
local Net = {}
Net.__index = Net

local R = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
    NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10,
    AddOnMessageLockdown = 11, TargetOffline = 12 }
Net.R = R

function Net.new(world)
    return setmetatable({ world = world, log = {}, sent = 0, delivered = 0, dropped = 0, buckets = {}, lastAt = {} }, Net)
end

-- Mensagem de sistema: passa pelos filtros do chat; só aparece se nenhum filtro esconder.
local function systemMessage(c, text)
    if c.state ~= "online" then return end
    c:fireEvent("CHAT_MSG_SYSTEM", text, "", "", "", "", "", 0, 0, "", 0, 0, nil, 0)
    for _, fn in ipairs(c.chatFilters[("CHAT_MSG_SYSTEM")] or {}) do
        local ok, hide = c:protect(fn, c.env.DEFAULT_CHAT_FRAME, "CHAT_MSG_SYSTEM", text)
        if ok and hide then
            c.hiddenSystem = (c.hiddenSystem or 0) + 1
            return
        end
    end
    c:print("system", text)
end
Net.systemMessage = systemMessage

local function result(world, code)
    local mode = world.config.addonReturn
    if mode == "enum" then return code end
    if mode == "bool" then return code == R.Success end
    if mode == "wrapped" then return code == R.Success, code end
    return nil
end

local function bucketFor(self, c, prefix)
    local key = c.name .. "|" .. prefix
    local b = self.buckets[key]
    local cfg = self.world.config.throttle
    if not b then b = { tokens = cfg.bucket, at = self.world.now }; self.buckets[key] = b end
    local gained = (self.world.now - b.at) * cfg.regen
    b.tokens = math.min(cfg.bucket, b.tokens + gained)
    b.at = self.world.now
    return b
end

function Net:sendAddon(c, prefix, msg, chatType, target)
    local world = self.world
    local cfg = world.config
    if type(prefix) ~= "string" or type(msg) ~= "string" then
        error("Usage: C_ChatInfo.SendAddonMessage(prefix, message [, chatType [, target]])", 3)
    end
    if #prefix == 0 or #prefix > 16 then return result(world, R.InvalidPrefix) end
    local size = #msg + (cfg.prefixCounts and #prefix or 0)
    if size > cfg.maxMessage then
        self.tooLong = (self.tooLong or 0) + 1
        table.insert(self.log, { from = c.name, to = target, prefix = prefix, msg = msg, status = "too-long" })
        if cfg.tooLong == "error" then error("SendAddonMessage: message too long", 3) end
        if cfg.tooLong == "truncate" then msg = msg:sub(1, cfg.maxMessage - (cfg.prefixCounts and #prefix or 0))
        else return result(world, R.InvalidMessage) end
    end
    if msg:find("%z") then return result(world, R.InvalidMessage) end
    chatType = chatType or "PARTY"
    if chatType ~= "WHISPER" then
        if chatType == "PARTY" or chatType == "RAID" or chatType == "INSTANCE_CHAT" then
            if not c.data.inGroup then return result(world, R.NotInGroup) end
        elseif chatType == "GUILD" or chatType == "OFFICER" then
            if not c.data.inGuild then return result(world, R.NotInGuild) end
        elseif chatType ~= "SAY" and chatType ~= "YELL" and chatType ~= "CHANNEL" then
            return result(world, R.InvalidChatType)
        end
        table.insert(self.log, { from = c.name, prefix = prefix, msg = msg, chatType = chatType, status = "group" })
        return result(world, R.Success)
    end
    if type(target) ~= "string" or target == "" then return result(world, R.TargetRequired) end
    if c.addonLockdown then return result(world, R.AddOnMessageLockdown) end
    -- throttle por prefixo
    local th = cfg.throttle
    local throttled = th.whispers == "always" or (th.whispers == "instance" and c.data.inInstance)
    if throttled then
        local b = bucketFor(self, c, prefix)
        if b.tokens < 1 then
            self.throttled = (self.throttled or 0) + 1
            table.insert(self.log, { from = c.name, to = target, prefix = prefix, msg = msg, status = "throttled", at = world.now })
            return result(world, R.AddonMessageThrottle)
        end
        b.tokens = b.tokens - 1
    end
    self.sent = self.sent + 1
    local rec = { from = c.name, to = target, prefix = prefix, msg = msg, at = world.now, status = "sent" }
    table.insert(self.log, rec)
    local dest, st = world:reachable(target)
    if dest and dest.faction ~= c.faction then dest = nil end
    if not dest then
        rec.status = "offline"
        if cfg.offline == "enum" then return result(world, R.TargetOffline) end
        local name = target
        world:after(cfg.latency, function()
            systemMessage(c, c.env and c.env.ERR_CHAT_PLAYER_NOT_FOUND_S:format(name) or "")
        end)
        return result(world, R.Success)
    end
    -- perda e corrupção injetadas pelos testes
    if self.dropFn and self.dropFn(rec) then
        rec.status = "dropped"
        self.dropped = self.dropped + 1
        return result(world, R.Success)
    end
    if self.mangleFn then msg = self.mangleFn(rec) or msg end
    -- entrega em ordem por par remetente/destino
    local pair = c.name .. ">" .. dest.name
    local at = math.max(world.now + cfg.latency, (self.lastAt[pair] or 0) + 0.001)
    self.lastAt[pair] = at
    local senderFull = c:fullName()
    world:after(at - world.now, function()
        if dest.state ~= "online" then rec.status = "lost-reloading"; return end
        if not dest.prefixes[prefix] then rec.status = "unregistered"; return end
        rec.status = "delivered"
        self.delivered = self.delivered + 1
        dest:fireEvent("CHAT_MSG_ADDON", prefix, msg, "WHISPER", senderFull, dest:fullName(), 0, 0, "", 0)
    end)
    return result(world, R.Success)
end

-- whisper de chat (pedido de vaga do addon)
function Net:sendChat(c, msg, chatType, target)
    local world = self.world
    if c.chatLockdown then error("SendChatMessage blocked: chat messaging lockdown", 3) end
    if type(msg) ~= "string" then error("Usage: SendChatMessage(text [, chatType [, languageID [, target]]])", 3) end
    if #msg > 255 then error("SendChatMessage: message too long", 3) end
    if msg:find("\n") then error("SendChatMessage: invalid escape/newline", 3) end
    if chatType ~= "WHISPER" then
        table.insert(c.data.whispersSent, { msg = msg, chatType = chatType })
        return
    end
    table.insert(c.data.whispersSent, { msg = msg, to = target, at = world.now })
    local dest = world:reachable(target)
    if dest and dest.faction ~= c.faction then dest = nil end
    world:after(world.config.latency, function()
        if c.state ~= "online" then return end
        if not dest or dest.state == "offline" then
            systemMessage(c, c.env.ERR_CHAT_PLAYER_NOT_FOUND_S:format(target))
            return
        end
        c:fireEvent("CHAT_MSG_WHISPER_INFORM", msg, dest:fullName(), "", "", dest:fullName(), "", 0, 0, "", 0, 0, "")
        if dest.state == "online" then
            dest:fireEvent("CHAT_MSG_WHISPER", msg, c:fullName(), "", "", c:fullName(), "", 0, 0, "", 0, 0, "")
        end
    end)
end

-- mensagens que chegaram a algum lugar, filtradas
function Net:find(fn)
    local out = {}
    for _, r in ipairs(self.log) do if fn(r) then out[#out + 1] = r end end
    return out
end

return Net
