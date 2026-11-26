-- Um cliente do jogo simulado: um personagem logado, com o próprio ambiente de globais
-- (sandbox Lua 5.1 só com o que o WoW expõe), os frames, os timers e os SavedVariables.
local Frames = require("sim.frames")
local SV = require("sim.serialize")

local Client = {}
Client.__index = Client

local KNOWN_EVENTS = {}
for _, e in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "VARIABLES_LOADED",
    "LFG_LIST_SEARCH_RESULTS_RECEIVED", "LFG_LIST_SEARCH_RESULT_UPDATED", "LFG_LIST_SEARCH_FAILED", "GROUP_ROSTER_UPDATE",
    "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_WHISPER", "CHAT_MSG_SYSTEM", "CHAT_MSG_ADDON", "CHAT_MSG_ADDON_LOGGED",
    "TRAIT_CONFIG_UPDATED", "PLAYER_LEVEL_UP", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN", "GUILD_ROSTER_UPDATE",
    "FRIENDLIST_UPDATE", "IGNORELIST_UPDATE", "BN_FRIEND_INFO_CHANGED", "WHO_LIST_UPDATE", "LFG_LIST_ROLE_UPDATE",
    "LUA_WARNING", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PARTY_INVITE_REQUEST", "ZONE_CHANGED_NEW_AREA",
    "QUEST_LOG_UPDATE", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_ACCEPTED", "GROUP_LEFT", "GROUP_JOINED",
    "LFG_LIST_ACTIVE_ENTRY_UPDATE", "LFG_LIST_ENTRY_CREATION_FAILED", "UI_ERROR_MESSAGE", "GLOBAL_MOUSE_DOWN" }) do
    KNOWN_EVENTS[e] = true
end

local CLASS_NAMES = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
    SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
local CLASS_COLORS = { WARRIOR = { 0.78, 0.61, 0.43 }, PALADIN = { 0.96, 0.55, 0.73 }, HUNTER = { 0.67, 0.83, 0.45 },
    ROGUE = { 1, 0.96, 0.41 }, PRIEST = { 1, 1, 1 }, SHAMAN = { 0, 0.44, 0.87 }, MAGE = { 0.25, 0.78, 0.92 },
    WARLOCK = { 0.53, 0.53, 0.93 }, DRUID = { 1, 0.49, 0.04 } }
Client.CLASS_NAMES = CLASS_NAMES

------------------------------------------------------------------------
-- valores secretos (regras do Midnight): opacos, qualquer uso dá erro
------------------------------------------------------------------------
local secretMeta = {
    __index = function() error("attempt to index a secret value", 2) end,
    __newindex = function() error("attempt to modify a secret value", 2) end,
    __concat = function() error("attempt to concatenate a secret value", 2) end,
    __lt = function() error("attempt to compare a secret value", 2) end,
    __le = function() error("attempt to compare a secret value", 2) end,
    __len = function() error("attempt to get length of a secret value", 2) end,
    __call = function() error("attempt to call a secret value", 2) end,
    __add = function() error("attempt to perform arithmetic on a secret value", 2) end,
    __sub = function() error("attempt to perform arithmetic on a secret value", 2) end,
    __tostring = function() return "<secret>" end,
}
local secrets = setmetatable({}, { __mode = "k" })
function Client.secret() local s = setmetatable({}, secretMeta); secrets[s] = true; return s end
function Client.isSecret(v) return type(v) == "table" and secrets[v] == true end

------------------------------------------------------------------------
-- funções de texto do WoW
------------------------------------------------------------------------
local function strsplit(delim, str, pieces)
    if type(str) ~= "string" then
        if type(str) == "number" then str = tostring(str) else error("bad argument #2 to 'strsplit' (string expected)", 2) end
    end
    local set = "[" .. delim:gsub("[%]%^%-%%]", "%%%0") .. "]"
    local out, start = {}, 1
    while true do
        if pieces and #out == pieces - 1 then out[#out + 1] = str:sub(start); break end
        local a, b = str:find(set, start)
        if not a then out[#out + 1] = str:sub(start); break end
        out[#out + 1] = str:sub(start, a - 1)
        start = b + 1
    end
    return unpack(out)
end
local function strtrim(s, chars)
    chars = chars and ("[" .. chars:gsub("[%]%^%-%%]", "%%%0") .. "]") or "[%s]"
    return (s:gsub("^" .. chars .. "+", ""):gsub(chars .. "+$", ""))
end
local function strjoin(d, ...) return table.concat({ ... }, d) end
local function wipe(t) for k in pairs(t) do t[k] = nil end return t end
local function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
string.split = string.split or strsplit
string.trim = string.trim or strtrim
string.join = string.join or strjoin

local function bitlib()
    local function band(a, b)
        local r, bit = 0, 1
        a, b = a % 4294967296, b % 4294967296
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then r = r + bit end
            a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
        end
        return r
    end
    local function bor(a, b)
        local r, bit = 0, 1
        a, b = a % 4294967296, b % 4294967296
        while a > 0 or b > 0 do
            if a % 2 == 1 or b % 2 == 1 then r = r + bit end
            a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
        end
        return r
    end
    local function bxor(a, b)
        local r, bit = 0, 1
        a, b = a % 4294967296, b % 4294967296
        while a > 0 or b > 0 do
            if (a % 2) ~= (b % 2) then r = r + bit end
            a, b, bit = math.floor(a / 2), math.floor(b / 2), bit * 2
        end
        return r
    end
    return { band = band, bor = bor, bxor = bxor,
        lshift = function(a, n) return (a * 2 ^ n) % 4294967296 end,
        rshift = function(a, n) return math.floor((a % 4294967296) / 2 ^ n) end,
        bnot = function(a) return 4294967295 - (a % 4294967296) end }
end

------------------------------------------------------------------------
-- construção
------------------------------------------------------------------------
-- opts: account, name, realm, class, level, faction, locale, race, guild, zone, subzone...
function Client.new(world, opts)
    local c = setmetatable({}, Client)
    c.world = world
    c.account = opts.account or opts.name
    c.name = opts.name
    c.realm = opts.realm or world.realm
    c.class = opts.class or "HUNTER"
    c.level = opts.level or 30
    c.faction = opts.faction or "Alliance"
    -- Forever: nome + sobrenome ("Bael Goldmaker"); UnitName devolve só o nome, o remetente de
    -- whisper vem "Nome Sobrenome" sem reino; cada regra (Normal, PvP, RP...) é um mundo à parte
    c.surname = opts.surname
    c.ruleset = opts.ruleset or "normal"
    c.locale = opts.locale or "enUS"
    c.zone = opts.zone or "Stormwind City"
    c.subzone = opts.subzone or ""
    c.opts = opts
    c.uptimeOffset = opts.uptimeOffset or (1000 + (#world.clients * 137.25))
    c.rngState = opts.seed or (12345 + #world.clients * 7919)
    c.state = "offline"
    c.errors = {}
    c.chat = {}
    c.blocked = {}
    c.log = {}
    -- dados do personagem que as APIs leem (editáveis pelos testes)
    c.data = {
        friends = {}, ignored = {}, guildMembers = {}, bnet = {}, who = {},
        roles = { tank = false, healer = false, dps = true },
        talents = opts.talents, inGroup = false, leader = false, assistant = false, inGuild = opts.guild ~= nil,
        inInstance = false, invites = {}, chatInput = nil, whispersSent = {}, legacyFriends = true,
    }
    return c
end

function Client:fullName()
    if self.surname then return self.name .. " " .. self.surname end
    return self.name .. "-" .. self.realm
end
function Client:now() return self.world.now + self.uptimeOffset end

function Client:random(m, n)
    -- LCG determinístico por cliente
    self.rngState = (self.rngState * 1103515245 + 12345) % 2147483648
    local r = self.rngState / 2147483648
    if m == nil then return r end
    if n == nil then m, n = 1, m end
    if m > n then error("bad argument #2 to 'random' (interval is empty)", 3) end
    return m + math.floor(r * (n - m + 1))
end

-- erro num script do jogo: vai para o errorhandler atual e o resto continua
function Client:protect(fn, ...)
    local args, n = { ... }, select("#", ...)
    local handler = self.errorHandler
    local function onErr(e)
        local tb = debug.traceback(tostring(e), 2)
        return { msg = e, tb = tb }
    end
    local res = { xpcall(function() return fn(unpack(args, 1, n)) end, onErr) }
    if not res[1] then
        local e = res[2]
        self:reportError(e.msg, e.tb)
        return false
    end
    return true, unpack(res, 2)
end

function Client:reportError(msg, tb)
    local h = self.errorHandler
    local rec = { msg = tostring(msg), tb = tb, at = self.world.now }
    self.errors[#self.errors + 1] = rec
    if self.world.verboseErrors then io.stderr:write("[" .. self.name .. "] " .. tostring(tb or msg) .. "\n") end
    if h and h ~= self.defaultHandler then pcall(h, msg) end
end

function Client:fireEvent(event, ...)
    if not self.ui then return end
    if not KNOWN_EVENTS[event] then error("evento desconhecido no simulador: " .. event) end
    self.ui.dispatch(event, ...)
end

function Client:print(kind, text)
    self.chat[#self.chat + 1] = { kind = kind, text = text, at = self.world.now }
end

-- linhas do chat sem códigos de cor
function Client:chatLines(kind)
    local out = {}
    for _, l in ipairs(self.chat) do
        if not kind or l.kind == kind then out[#out + 1] = Frames.visibleText(l.text) end
    end
    return out
end
function Client:chatHas(pattern, kind)
    for _, l in ipairs(self:chatLines(kind)) do if l:find(pattern) then return l end end
    return nil
end
function Client:clearChat() self.chat = {} end

------------------------------------------------------------------------
-- ambiente (API do WoW)
------------------------------------------------------------------------
function Client:buildEnv()
    local c = self
    local world = self.world
    local env = {}
    self.env = env
    env._G = env
    env._VERSION = "Lua 5.1"
    c.knownEvents = {}
    for k in pairs(KNOWN_EVENTS) do c.knownEvents[k] = true end
    for _, e in ipairs(world.config.missingEvents or {}) do c.knownEvents[e] = nil end

    -- Lua 5.1 como o WoW expõe (sem os, io, require, dofile, loadfile, package, debug)
    for _, k in ipairs({ "assert", "error", "ipairs", "next", "pairs", "pcall", "print", "rawequal", "rawget", "rawset",
        "select", "setmetatable", "getmetatable", "tonumber", "tostring", "type", "unpack", "xpcall", "loadstring",
        "setfenv", "getfenv", "collectgarbage", "gcinfo", "newproxy" }) do
        env[k] = _G[k]
    end
    local function copy(t) local o = {}; for k, v in pairs(t) do o[k] = v end; return o end
    env.string = copy(string)
    env.table = copy(table)
    env.math = copy(math)
    env.coroutine = copy(coroutine)
    env.bit = bitlib()
    env.math.random = function(m, n) return c:random(m, n) end
    env.math.randomseed = function() end
    -- atalhos globais do WoW
    env.strsplit, env.strjoin, env.strtrim = strsplit, strjoin, strtrim
    env.strlower, env.strupper, env.strlen, env.strsub, env.strfind, env.strmatch = string.lower, string.upper, string.len, string.sub, string.find, string.match
    env.strrep, env.strbyte, env.strchar, env.strrev, env.gsub, env.gmatch, env.format = string.rep, string.byte, string.char, string.reverse, string.gsub, string.gmatch, string.format
    env.strconcat = function(...) return table.concat({ ... }) end
    env.tostringall = function(...) local t = { ... }; for i = 1, select("#", ...) do t[i] = tostring(t[i]) end; return unpack(t, 1, select("#", ...)) end
    env.tinsert, env.tremove, env.sort, env.wipe, env.tContains = table.insert, table.remove, table.sort, wipe, tContains
    env.table.wipe = wipe
    env.tInvert = function(t) local o = {}; for k, v in pairs(t) do o[v] = k end; return o end
    env.CopyTable = function(t)
        local function cp(x) if type(x) ~= "table" then return x end local o = {}; for k, v in pairs(x) do o[k] = cp(v) end; return o end
        return cp(t)
    end
    env.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
    env.CreateFromMixins = function(...) return env.Mixin({}, ...) end
    env.floor, env.ceil, env.abs, env.max, env.min, env.sqrt, env.mod = math.floor, math.ceil, math.abs, math.max, math.min, math.sqrt, math.fmod
    env.random = env.math.random
    env.fastrandom = env.math.random
    env.date = function(fmt, t)
        t = t or env.time()
        fmt = fmt or "%c"
        if fmt:sub(1, 1) == "!" then fmt = fmt:sub(2) end
        return os.date("!" .. fmt, t)
    end
    env.time = function(t)
        if t then return os.time(t) end
        return world:epochNow()
    end
    env.GetTime = function() return c:now() end
    env.GetServerTime = env.time
    env.debugstack = function(start) return debug.traceback("", (start or 1) + 1) end
    env.debugprofilestop = function() return c:now() * 1000 end
    c.defaultHandler = function(msg) end
    c.errorHandler = c.defaultHandler
    env.geterrorhandler = function() return c.errorHandler end
    env.seterrorhandler = function(h) c.errorHandler = h end
    env.securecall = function(fn, ...)
        if type(fn) == "string" then fn = env[fn] end
        return select(2, c:protect(fn, ...))
    end
    env.issecurevariable = function(t, k)
        if k == nil then k, t = t, env end
        local by = world.taint and world.taint[t] and world.taint[t][k]
        if by then return false, by end
        return true, nil
    end
    env.hooksecurefunc = function(a, b, cfn)
        local tbl, key, hook
        if type(a) == "table" then tbl, key, hook = a, b, cfn else tbl, key, hook = env, a, b end
        local orig = tbl[key]
        if type(orig) ~= "function" then error("hooksecurefunc(): " .. tostring(key) .. " is not a function", 2) end
        local wrapped = function(...)
            local r = { n = select("#", ...), orig(...) }
            c:protect(hook, ...)
            return unpack(r, 1, #r)
        end
        world.secureHooks[wrapped] = orig
        rawset(tbl, key, wrapped)
    end
    env.issecretvalue = function(v) return Client.isSecret(v) end
    env.canaccessvalue = function(v) return not Client.isSecret(v) end
    env.canaccesstable = function(t) return not Client.isSecret(t) and not (world.inaccessible[t]) end

    -- saída no chat
    env.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
        c:print("print", table.concat(parts, " "))
    end

    -- frames
    local ui = Frames.new(c)
    c.ui = ui
    env.CreateFrame = function(kind, name, parent, template, id)
        local f = ui.CreateFrame(kind, name, parent, template)
        if id then f:SetID(id) end
        return f
    end
    local tip = ui.CreateFrame("GameTooltip", "GameTooltip", ui.UIParent)
    tip:Hide()
    local chatFrame = ui.CreateFrame("Frame", "DEFAULT_CHAT_FRAME", ui.UIParent)
    chatFrame.AddMessage = function(_, text) c:print("print", tostring(text)) end
    env.SELECTED_CHAT_FRAME = chatFrame
    local minimap = ui.CreateFrame("Frame", "Minimap", ui.UIParent)
    minimap:SetSize(140, 140)
    minimap:SetPoint("TOPRIGHT", ui.UIParent, "TOPRIGHT", -20, -20)
    env.GetMinimapShape = function() return world.config.minimapShape or "ROUND" end
    env.GetCursorPosition = function() return unpack(c.cursor or { 960, 540 }) end
    env.UISpecialFrames = {}
    env.SlashCmdList = {}
    env.SettingsPanel = ui.CreateFrame("Frame", "SettingsPanel", ui.UIParent)
    env.SettingsPanel:Hide()
    c.settingsCategories = {}
    env.Settings = {
        RegisterCanvasLayoutCategory = function(frame, name)
            local cat = { ID = name, name = name, frame = frame }
            cat.GetID = function(self) return self.ID end
            return cat
        end,
        RegisterAddOnCategory = function(cat) c.settingsCategories[#c.settingsCategories + 1] = cat end,
        OpenToCategory = function(id)
            c.openedCategory = id
            env.SettingsPanel:Show()
            for _, cat in ipairs(c.settingsCategories) do if cat.ID == id then cat.frame:Show() end end
        end,
    }
    env.InCombatLockdown = function() return c.inCombat == true end
    env.ReloadUI = function()
        if world.config.reloadUIBlocked then
            c:fireEvent("ADDON_ACTION_BLOCKED", c.loadingAddon or "GrupoFacil", "ReloadUI()")
            c.blocked[#c.blocked + 1] = { fn = "ReloadUI" }
            return
        end
        world:after(0, function() c:reload() end)
    end
    env.C_UI = { Reload = env.ReloadUI }

    -- texto e cores
    env.RAID_CLASS_COLORS, env.LOCALIZED_CLASS_NAMES_MALE, env.LOCALIZED_CLASS_NAMES_FEMALE, env.CLASS_ICON_TCOORDS = {}, {}, {}, {}
    local i = 0
    for k, col in pairs(CLASS_COLORS) do
        env.RAID_CLASS_COLORS[k] = { r = col[1], g = col[2], b = col[3], colorStr = "ff000000" }
        env.LOCALIZED_CLASS_NAMES_MALE[k] = CLASS_NAMES[k]
        env.LOCALIZED_CLASS_NAMES_FEMALE[k] = CLASS_NAMES[k]
        i = i + 1
        env.CLASS_ICON_TCOORDS[k] = { 0, 0.25, 0, 0.25 }
    end
    env.RETRIEVING_DATA = "Retrieving data"
    env.ERR_CHAT_PLAYER_NOT_FOUND_S = "No player named '%s' is currently playing."
    env.ERR_FRIEND_OFFLINE_S = "%s has gone offline."
    env.BNET_CLIENT_WOW = "WoW"
    env.WOW_PROJECT_ID = 2
    env.WOW_PROJECT_CLASSIC = 2
    env.CreateAtlasMarkup = function(atlas, w, h) return ("|A:%s:%d:%d|a"):format(atlas, w or 0, h or 0) end
    env.C_Texture = { GetAtlasInfo = function(a) if world.config.atlases ~= false and a and a:find("^roleicon") then return { width = 16, height = 16 } end end }
    env.Enum = {
        LFGEntryGeneralPlaystyle = { None = 0, Learning = 1, FunRelaxed = 2, FunSerious = 3, Expert = 4 },
        LFGEntryVoiceMode = { None = 0, Required = 1, Optional = 2 },
        SendAddonMessageResult = { Success = 0, InvalidPrefix = 1, InvalidMessage = 2, AddonMessageThrottle = 3, InvalidChatType = 4,
            NotInGroup = 5, TargetRequired = 6, InvalidChannel = 7, ChannelThrottle = 8, GeneralError = 9, NotInGuild = 10,
            AddOnMessageLockdown = 11, TargetOffline = 12 },
        RegisterAddonMessagePrefixResult = { Success = 0, DuplicatePrefix = 1, InvalidPrefix = 2, MaxPrefixes = 3 },
    }

    -- personagem
    -- Forever devolve o sobrenome no 2º valor (Fraga conferiu em 2026-11-25: "Bagael Bagacera").
    -- opts.unitNameSurname = false simula um cliente que só dá o primeiro nome.
    env.UnitName = function(u)
        if u == "player" then return c.name, (c.opts.unitNameSurname ~= false and c.surname) or nil end
        return nil
    end
    env.UnitFullName = function(u) if u == "player" then return c.name, c.realm end end
    env.GetRealmName = function() return c.realm end
    env.GetNormalizedRealmName = function() return (c.realm:gsub("[%s%-]", "")) end
    env.UnitClass = function(u) if u == "player" then return CLASS_NAMES[c.class], c.class, 1 end end
    env.UnitLevel = function(u) if u == "player" then return c.level end return 0 end
    env.UnitRace = function(u) if u == "player" then return "Human", "Human", 1 end end
    env.UnitFactionGroup = function(u) if u == "player" then return c.faction, c.faction end end
    env.UnitGUID = function(u) if u == "player" then return "Player-1-" .. c.name end end
    env.GetLocale = function() return c.locale end
    env.GetBuildInfo = function() return world.config.buildVersion or "1.60.1", "61234", "Nov 1 2026", world.config.toc or 16001 end
    env.GetZoneText = function() return c.zone end
    env.GetSubZoneText = function() return c.subzone end
    env.GetRealZoneText = function() return c.zone end
    env.IsInInstance = function() return c.data.inInstance, c.data.inInstance and "party" or "none" end
    env.IsInGroup = function() return c.data.inGroup end
    env.IsInRaid = function() return false end
    -- canais numerados em que o jogador está (id, nome, desativado, ...)
    env.GetChannelList = function()
        local out = {}
        for _, ch in ipairs(c.data.channels or { { 1, "General" }, { 2, "Trade" }, { 4, "LocalDefense" } }) do
            out[#out + 1] = ch[1]; out[#out + 1] = ch[2]; out[#out + 1] = ch[3] or false
        end
        return unpack(out)
    end
    env.GetNumGroupMembers = function() return c.data.inGroup and 2 or 0 end
    env.UnitIsGroupLeader = function(u) return u == "player" and c.data.leader end
    env.UnitIsGroupAssistant = function(u) return u == "player" and c.data.assistant end
    env.IsInGuild = function() return c.data.inGuild end
    env.GetGuildInfo = function(u) if u == "player" and c.data.inGuild then return c.opts.guild, "Member", 1 end end
    env.Ambiguate = function(name, ctx)
        if type(name) ~= "string" then return name end
        local n, realm = name:match("^([^%-]+)%-(.+)$")
        if not n then return name end
        if ctx == "none" or realm == c.realm or realm == (c.realm:gsub("[%s%-]", "")) then return n end
        return name
    end

    -- addons
    c.addonsLoaded = c.addonsLoaded or {}
    local function addonMeta(name, field)
        local toc = world.addons[name]
        if not toc then return nil end
        return toc.meta[field]
    end
    env.C_AddOns = {
        GetAddOnMetadata = addonMeta,
        IsAddOnLoaded = function(name) return c.addonsLoaded[name] == true, c.addonsLoaded[name] == true end,
        LoadAddOn = function(name) return c:loadBlizzard(name) end,
        GetNumAddOns = function() local n = 0; for _ in pairs(world.addons) do n = n + 1 end; return n end,
    }
    if not world.config.noLegacyAddonAPI then
        env.GetAddOnMetadata = addonMeta
        env.IsAddOnLoaded = env.C_AddOns.IsAddOnLoaded
    end

    -- chat e comunicação de addon
    c.prefixes = {}
    local net = world.net
    env.C_ChatInfo = {
        RegisterAddonMessagePrefix = function(prefix)
            if type(prefix) ~= "string" or #prefix == 0 or #prefix > 16 then return env.Enum.RegisterAddonMessagePrefixResult.InvalidPrefix end
            if c.prefixes[prefix] then return env.Enum.RegisterAddonMessagePrefixResult.DuplicatePrefix end
            c.prefixes[prefix] = true
            return env.Enum.RegisterAddonMessagePrefixResult.Success
        end,
        IsAddonMessagePrefixRegistered = function(p) return c.prefixes[p] == true end,
        GetRegisteredAddonMessagePrefixes = function() local o = {}; for p in pairs(c.prefixes) do o[#o + 1] = p end; return o end,
        SendAddonMessage = function(prefix, msg, chatType, target) return net:sendAddon(c, prefix, msg, chatType, target) end,
        SendAddonMessageLogged = function(prefix, msg, chatType, target) return net:sendAddon(c, prefix, msg, chatType, target) end,
        InChatMessagingLockdown = function() return c.chatLockdown == true end,
        SendChatMessage = function(msg, chatType, lang, target) return net:sendChat(c, msg, chatType, target) end,
    }
    if world.config.noCChatInfoSend then env.C_ChatInfo.SendAddonMessage = nil end
    if world.config.globalSendAddonMessage ~= false then
        env.SendAddonMessage = function(prefix, msg, chatType, target) return net:sendAddon(c, prefix, msg, chatType, target) end
    end
    env.SendChatMessage = function(msg, chatType, lang, target) return net:sendChat(c, msg, chatType, target) end
    c.chatFilters = {}
    local function addFilter(event, fn)
        c.chatFilters[event] = c.chatFilters[event] or {}
        table.insert(c.chatFilters[event], fn)
    end
    local function removeFilter(event, fn)
        for i, f in ipairs(c.chatFilters[event] or {}) do if f == fn then table.remove(c.chatFilters[event], i) return end end
    end
    env.ChatFrame_AddMessageEventFilter = addFilter
    env.ChatFrame_RemoveMessageEventFilter = removeFilter
    local function openChat(text) c.data.chatInput = text end
    env.ChatFrameUtil = {
        AddMessageEventFilter = addFilter,
        RemoveMessageEventFilter = removeFilter,
        OpenChat = openChat,
        SendTell = function(name) openChat("/w " .. name .. " ") end,
        SendTellWithMessage = function(name, msg) openChat("/w " .. name .. " " .. msg) end,
    }
    env.ChatFrame_OpenChat = openChat
    env.ChatFrame_SendTell = env.ChatFrameUtil.SendTell

    -- grupo
    env.C_PartyInfo = {
        InviteUnit = function(name)
            if c.chatLockdown then error("InviteUnit blocked", 2) end
            table.insert(c.data.invites, name)
            world:deliverInvite(c, name)
        end,
    }
    env.InviteUnit = env.C_PartyInfo.InviteUnit

    -- talentos (spec = árvore com mais pontos)
    env.C_ClassTalents = { GetActiveConfigID = function() if c.data.talents then return 1 end end }
    env.C_Traits = {
        GetConfigInfo = function(id) if id == 1 and c.data.talents then return { treeIDs = { 10 } } end end,
        GetGroupDisplayInfoByTreeID = function()
            local out = {}
            for i, t in ipairs(c.data.talents or {}) do out[i] = { groupID = 100 + i, displayName = t.name } end
            return out
        end,
        GetGroupCurrencyInfo = function(_, ids)
            local out = {}
            for i, gid in ipairs(ids) do
                local t = c.data.talents[gid - 100]
                out[i] = { traitNodeGroupID = gid, currencyInfos = { { spent = t and t.spent or 0 } } }
            end
            return out
        end,
    }
    env.C_LFGListRoles = { GetRoles = function()
        if c.data.rolesSecret then return Client.secret() end
        local r = c.data.roles
        return { tank = r.tank, healer = r.healer, dps = r.dps }
    end }

    -- amigos, ignorados, guilda, battle.net, /who
    local function lower(s) return type(s) == "string" and s:lower() or s end
    local function short(n) return type(n) == "string" and (n:match("^[^%-]+") or n):lower() or n end
    env.C_FriendList = {
        IsLegacyFriendSystemEnabled = function() return c.data.legacyFriends end,
        GetFriendInfo = function(name)
            for _, f in ipairs(c.data.friends) do if short(f) == short(name) then return { name = f, connected = true } end end
            return nil
        end,
        IsIgnored = function(name)
            for _, f in ipairs(c.data.ignored) do if short(f) == short(name) then return true end end
            return false
        end,
        GetNumWhoResults = function() return #c.data.who, #c.data.who end,
        GetWhoInfo = function(i) return c.data.who[i] end,
        SendWho = function() error("SendWho() is protected", 2) end,
    }
    env.IsIgnored = env.C_FriendList.IsIgnored
    env.C_GuildInfo = {
        MemberExistsByName = function(name)
            for _, m in ipairs(c.data.guildMembers) do if short(m) == short(name) then return true end end
            return false
        end,
        GuildRoster = function() c.guildRosterRequested = (c.guildRosterRequested or 0) + 1 end,
    }
    env.BNGetNumFriends = function() return #c.data.bnet, #c.data.bnet end
    env.C_BattleNet = {
        GetFriendNumGameAccounts = function(i) return c.data.bnet[i] and #c.data.bnet[i] or 0 end,
        GetFriendGameAccountInfo = function(i, j) return c.data.bnet[i] and c.data.bnet[i][j] end,
    }

    -- timers
    env.C_Timer = {
        After = function(sec, fn)
            if type(fn) ~= "function" then error("C_Timer.After: callback inválido", 2) end
            world:clientTimer(c, sec, fn)
        end,
        NewTimer = function(sec, fn) return world:clientTimer(c, sec, fn, 1) end,
        NewTicker = function(sec, fn, n) return world:clientTimer(c, sec, fn, n or math.huge) end,
    }

    -- Looking For Group
    env.C_LFGList = world.lfg:api(c)
    env.LFGUtil_GetFilteredActivities = function(category) return world.lfg:activitiesFor(category) end

    -- missões, rastreador, quest log, grupo (sim/quests.lua)
    require("sim.quests").install(c, env)
end

------------------------------------------------------------------------
-- carregar addons
------------------------------------------------------------------------
function Client:runFile(addon, path, ns)
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    local chunk, err = loadstring(text, "@Interface/AddOns/" .. addon .. "/" .. path:match("[^/]+$"))
    if not chunk then self:reportError(err); return end
    setfenv(chunk, self.env)
    self:protect(chunk, addon, ns)
end

function Client:loadAddon(name)
    local toc = self.world.addons[name]
    assert(toc, "addon desconhecido: " .. name)
    local ns = {}
    self.namespaces = self.namespaces or {}
    self.namespaces[name] = ns
    self.loadingAddon = name
    for _, file in ipairs(toc.files) do self:runFile(name, toc.dir .. "/" .. file, ns) end
    self.loadingAddon = nil
    -- ponto para o teste ajustar o addon antes do ADDON_LOADED (ex.: lista de admins)
    local hook = self.opts.beforeAddonLoaded or self.world.config.beforeAddonLoaded
    if hook then hook(self, ns, name) end
    -- SavedVariables entram depois dos arquivos e antes do ADDON_LOADED (ordem do cliente)
    local disk = self.world:diskFor(self.account)
    for _, var in ipairs(toc.savedVariables) do self.env[var] = nil end
    local ok, e = SV.load(disk.account[name], self.env)
    if not ok then self:reportError("SavedVariables: " .. tostring(e)) end
    ok, e = SV.load((disk.chars[self.name] or {})[name], self.env)
    if not ok then self:reportError("SavedVariablesPerCharacter: " .. tostring(e)) end
    self.addonsLoaded[name] = true
    self:fireEvent("ADDON_LOADED", name)
end

function Client:saveVariables()
    local disk = self.world:diskFor(self.account)
    for name, toc in pairs(self.world.addons) do
        if self.addonsLoaded[name] and toc.dir then
            disk.account[name] = SV.dump(toc.savedVariables, self.env)
            disk.chars[self.name] = disk.chars[self.name] or {}
            disk.chars[self.name][name] = SV.dump(toc.savedVariablesPerCharacter, self.env)
        end
    end
    disk.writes = (disk.writes or 0) + 1
end

-- Janela nativa do Looking For Group (carregada sob demanda no cliente real)
function Client:loadBlizzard(name)
    if name ~= "Blizzard_GroupFinder_VanillaStyle" then return false, "MISSING" end
    if self.addonsLoaded[name] then return true end
    local ui = self.ui
    local world = self.world
    local parent = ui.CreateFrame("Frame", "LFGParentFrame", ui.UIParent)
    parent:SetSize(384, 512)
    parent:SetPoint("TOPLEFT", ui.UIParent, "TOPLEFT", 16, -116)
    parent:Hide()
    local browse = ui.CreateFrame("Frame", "LFGBrowseFrame", parent)
    browse:SetAllPoints(parent)
    -- SetValue existe (é do mixin da Blizzard) só para o teste ver se o addon chamou: chamar contamina
    -- a busca que o jogo faz ao criar uma listagem (ADDON_ACTION_BLOCKED no BugSack do Fraga, 26/11)
    browse.CategoryDropdown = {
        GetValue = function() return self.nativeCategory end,
        SetValue = function(_, v) self.data.nativeCategorySets = (self.data.nativeCategorySets or 0) + 1; self.nativeCategory = v end,
    }
    browse.ActivityDropdown = { selectedValues = self.nativeActivities }
    -- grava quem escreve na janela da Blizzard (o addon nunca pode)
    world:watchWrites(self, parent, "LFGParentFrame")
    world:watchWrites(self, browse, "LFGBrowseFrame")
    self.addonsLoaded[name] = true
    self:fireEvent("ADDON_LOADED", name)
    return true
end

function Client:openLFG()
    self:loadBlizzard("Blizzard_GroupFinder_VanillaStyle")
    self.env.LFGParentFrame:Show()
end
function Client:closeLFG()
    if self.env.LFGParentFrame then self.env.LFGParentFrame:Hide() end
end

-- O jogador busca pela janela nativa (código da Blizzard chama C_LFGList.Search).
function Client:nativeSearch(category, activities)
    self:openLFG()
    self.nativeCategory = category or 2
    self.nativeActivities = activities or { 1 }
    local browse = self.env.LFGBrowseFrame
    browse.ActivityDropdown.selectedValues = self.nativeActivities
    self.world:blizzardWrite(browse, "searching", true)
    local hw = self.hw
    self.hw = { left = 1, native = true } -- código da Blizzard, do clique do jogador
    self.env.C_LFGList.Search(self.nativeCategory, 0, 0, nil, false, nil, self.nativeActivities)
    self.hw = hw
end

------------------------------------------------------------------------
-- ciclo de vida
------------------------------------------------------------------------
function Client:start(isReload)
    self.state = "loading"
    self:buildEnv()
    for _, name in ipairs(self.world.enabledAddons) do self:loadAddon(name) end
    self.state = "online"
    if self.opts.lfgLoadedAtLogin then self:loadBlizzard("Blizzard_GroupFinder_VanillaStyle") end
    self:fireEvent("VARIABLES_LOADED")
    self:fireEvent("PLAYER_LOGIN")
    self:fireEvent("PLAYER_ENTERING_WORLD", not isReload, isReload == true)
    if self.updateTracker then self:updateTracker() end
end

function Client:teardown()
    self.world:cancelTimers(self)
    self.ui = nil
    self.env = nil
    self.addonsLoaded = {}
    self.prefixes = {}
    self.inCombat = false
end

-- /reload: grava em disco, recarrega tudo. Mensagens que chegam no meio se perdem.
function Client:reload()
    assert(self.state == "online", "reload com o cliente " .. self.state)
    self:fireEvent("PLAYER_LOGOUT")
    self:saveVariables()
    self:teardown()
    self.state = "reloading"
    self.reloads = (self.reloads or 0) + 1
    local reloadTime = self.world.config.reloadTime or 0
    if reloadTime > 0 then
        self.world:after(reloadTime, function() self:start(true) end)
    else
        self:start(true)
    end
end

-- Logout ou saída normal: grava e fica offline.
function Client:logout()
    if self.state ~= "online" then return end
    self:fireEvent("PLAYER_LOGOUT")
    self:saveVariables()
    self:teardown()
    self.state = "offline"
    self.world:setOffline(self)
end

-- Crash/kill do processo: nada é gravado.
function Client:crash()
    self:teardown()
    self.state = "offline"
    self.world:setOffline(self)
end

------------------------------------------------------------------------
-- ações do jogador
------------------------------------------------------------------------
function Client:slash(line)
    local cmd, rest = line:match("^(/%S+)%s*(.-)$")
    assert(cmd, "comando inválido: " .. line)
    cmd = cmd:lower()
    if cmd == "/reload" or cmd == "/rl" then return self:reload() end
    for key, fn in pairs(self.env.SlashCmdList) do
        local i = 1
        while self.env["SLASH_" .. key .. i] do
            if self.env["SLASH_" .. key .. i]:lower() == cmd then
                local ok = self:protect(fn, rest, nil)
                return ok
            end
            i = i + 1
        end
    end
    self:print("system", "Type '/help' for a listing of a few commands.")
end

-- macro de um botão seguro (o único jeito seguro de /reload)
function Client:runMacro(text, secure)
    for line in (text .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then
            if line:lower():match("^/reload") then
                self.world:after(0, function() if self.state == "online" then self:reload() end end)
            else
                self:slash(line)
            end
        end
    end
end

-- Clique como no jogo: o mouse está sobre o quadro, o jogo avisa GLOBAL_MOUSE_DOWN e depois vem o OnClick.
function Client:click(f, mouse)
    assert(f, "click: frame nil")
    self.ui.mouseOver = f
    self:fireEvent("GLOBAL_MOUSE_DOWN", mouse or "LeftButton")
    f:Click(mouse)
    self.ui.mouseOver = nil
end
-- Clique fora de tudo (no mundo do jogo).
function Client:clickOutside(mouse)
    self.ui.mouseOver = nil
    self:fireEvent("GLOBAL_MOUSE_DOWN", mouse or "LeftButton")
end
-- Põe o mouse sobre o quadro e deixa ali (o tooltip fica aberto até o OnLeave).
function Client:mouseEnter(f)
    self.ui.mouseOver = f
    self.ui.fire(f, "OnEnter", true)
end
function Client:type(box, text) self.ui.type(box, text) end
function Client:press(box, key)
    local s = self.ui.state(box)
    if key == "ENTER" then self.ui.fire(box, "OnEnterPressed")
    elseif key == "ESCAPE" then self.ui.fire(box, "OnEscapePressed")
    elseif key == "TAB" then self.ui.fire(box, "OnTabPressed") end
end
-- Passa o mouse: devolve as linhas do GameTooltip.
function Client:hover(f)
    local s = self.ui.state(f)
    local tip = self.env.GameTooltip
    self.ui.state(tip).lines = {}
    if s.isFrame and s.enabled == false and not s.motionDisabled then return {} end
    self.ui.mouseOver = f
    self.ui.fire(f, "OnEnter", true)
    local lines = {}
    for i, l in ipairs(self.ui.state(tip).lines or {}) do lines[i] = Frames.visibleText(l.text) end
    self.ui.fire(f, "OnLeave", true)
    self.ui.mouseOver = nil
    return lines
end
function Client:enterCombat()
    self.inCombat = true
    self:fireEvent("PLAYER_REGEN_DISABLED")
end
function Client:leaveCombat()
    self.inCombat = false
    self:fireEvent("PLAYER_REGEN_ENABLED")
end

-- texto visível de um FontString/Button
function Client:text(o)
    if not o then return nil end
    local s = self.ui.state(o)
    local t
    if s.kind == "FontString" then t = s.text
    elseif s.kind == "EditBox" then t = s.text
    elseif s.fontString then t = self.ui.state(s.fontString).text end
    return t and Frames.visibleText(t) or nil
end
function Client:isVisible(o) return o ~= nil and self.ui.visible(o) end
function Client:frame(name) return self.ui.byName[name] end

-- erros de Lua do addon nesta sessão (o teste falha se houver)
function Client:luaErrors()
    local out = {}
    for _, e in ipairs(self.errors) do out[#out + 1] = e.tb or e.msg end
    return out
end

return Client
