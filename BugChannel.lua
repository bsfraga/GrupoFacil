-- BugChannel.lua  v1  (módulo genérico de bug report persistente; protocolo 1)
-- Colar igual em cada addon. Só muda o que é passado a BC.Init(cfg).
-- Carregue no .toc ANTES do arquivo que chama BC.Init, e declare o SavedVariables do addon.
local ADDON, ns = ...
ns = ns or {}
local BC = { VERSION = 1 }
ns.BugChannel = BC

local PROTO, SEP = 1, "~"
local CHUNK       = 170    -- bytes ESCAPADOS de dados por pacote (prefixo+cabeçalho+dados < 255)
local ACK_WAIT    = 20     -- s sem A1 depois do último pacote -> volta p/ "queued"
local ADMIN_TTL   = 300    -- s que um PONG vale
local STATUS_EVERY= 60     -- s entre consultas S de reports em "received"
local MAX_BODY, MAX_QUEUE, MAX_INBOX, MAX_PER_HOUR = 8000, 50, 500, 20
local STUB_DAYS   = 30

local cfg, db
local rt = { recentTo = {}, pauseUntil = 0, r = {}, asm = {}, rate = {}, durable = {}, discBackoff = 30, discNext = 0, statusAt = 0 }
local outq = {}

---------------------------------------------------------------- utilidades
local function isSecret(v)
  if issecretvalue then return issecretvalue(v) == true end
  if canaccessvalue then return not canaccessvalue(v) end
  return false
end
local function short(n)
  if type(n) ~= "string" or isSecret(n) or n == "" then return nil end
  return (strsplit("-", n))
end
local function esc(s)   -- só ASCII imprimível sem % ~ | passa; o resto vira %XX
  return (tostring(s):gsub("[%%~|%c\128-\255]", function(c) return ("%%%02X"):format(c:byte()) end))
end
-- Nota do desfecho (F): corta por caractere UTF-8 inteiro, até 120 bytes do texto e 180 bytes
-- já escapados, para a mensagem caber em 255 bytes com cabeçalho e prefixo.
-- [GrupoFacil] correção: antes era esc(note:sub(1, 120)); com acentos o escape triplica o tamanho
-- (120 bytes -> até 360) e o F passava de 255 bytes, falhava 5 vezes e era descartado.
local NOTE_RAW, NOTE_ESC = 120, 180
local function noteEsc(note)
  local out, raw, size = {}, 0, 0
  for ch in tostring(note or ""):gmatch("[%z\1-\127\192-\255][\128-\191]*") do
    local e = esc(ch)
    if raw + #ch > NOTE_RAW or size + #e > NOTE_ESC then break end
    out[#out + 1] = e
    raw, size = raw + #ch, size + #e
  end
  return table.concat(out)
end
local function unesc(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end
local function split(s, n)   -- corta o texto já escapado sem partir um %XX
  local out, i, len = {}, 1, #s
  while i <= len do
    local j = math.min(i + n - 1, len)
    if j < len then
      if s:sub(j, j) == "%" then j = j - 1
      elseif j - 1 >= i and s:sub(j - 1, j - 1) == "%" then j = j - 2 end
    end
    out[#out + 1] = s:sub(i, j)
    i = j + 1
  end
  return out
end
local function adler(s)
  local a, b = 1, 0
  for i = 1, #s do a = (a + s:byte(i)) % 65521; b = (b + a) % 65521 end
  return b * 65536 + a
end
local function isAdmin(n)
  if not n then return false end
  n = n:lower()
  for _, a in ipairs(cfg.admins) do if a:lower() == n then return true end end
  return false
end
local function say(m) if cfg.say then cfg.say(m) else print("|cff9d7be0" .. cfg.addon .. ":|r " .. m) end end
BC._esc, BC._unesc, BC._split, BC._adler = esc, unesc, split, adler   -- p/ testes

---------------------------------------------------------------- transporte
local function enqueue(target, ...)
  local parts = { PROTO }
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  outq[#outq + 1] = { target = target, msg = table.concat(parts, SEP) }
end
local function sendNow(item)
  rt.recentTo[item.target:lower()] = GetTime()
  local fn = (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
  local ok, res = pcall(fn, cfg.prefix, item.msg, "WHISPER", item.target)
  if not ok then return false end
  if res == nil or res == true then return true end
  local S = Enum and Enum.SendAddonMessageResult
  return (S and res == S.Success) and true or false
end
local function drain()
  if GetTime() < rt.pauseUntil then return end
  local item = table.remove(outq, 1)
  if not item then return end
  if not sendNow(item) then
    item.fails = (item.fails or 0) + 1
    if item.fails < 5 then table.insert(outq, 1, item); rt.pauseUntil = GetTime() + 2 end
  end
end

---------------------------------------------------------------- lado jogador
local function getParts(e)
  local s = esc(e.body)
  return split(s, CHUNK), s
end
local function sendChunks(e, only)   -- only = conjunto de índices (nil = todos)
  if not rt.admin then e.state = "queued"; return end
  local parts, s = getParts(e)
  local n = #parts
  for i, p in ipairs(parts) do
    if not only or only[i] then enqueue(rt.admin, "D", e.id, i, n, p) end
  end
  enqueue(rt.admin, "E", e.id, n, #s, adler(s))
  local r = rt.r[e.id] or {}; rt.r[e.id] = r
  r.deadline = GetTime() + ACK_WAIT + #parts * 0.4
  e.state = "sent"
end
local function discover()
  if GetTime() < rt.discNext then return end
  rt.discNext = GetTime() + rt.discBackoff
  rt.discBackoff = math.min(rt.discBackoff * 2, 900)
  for _, a in ipairs(cfg.admins) do enqueue(a, "PING") end
end
local function pump()
  if not db or rt.iAmAdmin or GetTime() < (rt.startAt or 0) then return end
  local list, active, stubs = {}, false, false
  for _, e in pairs(db.bugs) do list[#list + 1] = e end
  table.sort(list, function(a, b) return a.ts < b.ts end)
  for _, e in ipairs(list) do
    if e.state ~= "done" then active = true elseif not e.resolved then stubs = true end
  end
  if not (active or (stubs and not rt.polledStubs)) then return end
  if not (rt.admin and GetTime() - rt.adminAt < ADMIN_TTL) then rt.admin = nil; return discover() end
  local inflight, ids = false, {}
  for _, e in ipairs(list) do
    local r = rt.r[e.id] or {}; rt.r[e.id] = r
    if e.state == "queued" then
      if not inflight and GetTime() >= (r.nextTry or 0) then sendChunks(e); inflight = true end
    elseif e.state == "sent" then
      inflight = true
      if GetTime() > r.deadline then
        e.state, e.tries = "queued", (e.tries or 0) + 1
        r.nextTry = GetTime() + math.min(900, 15 * 2 ^ e.tries)
        rt.admin = nil                              -- redescobrir quem está online
      end
    elseif e.state == "received" then ids[#ids + 1] = e.id
    elseif e.state == "done" and not e.resolved and not rt.polledStubs then ids[#ids + 1] = e.id end
  end
  -- [GrupoFacil] correção: "and rt.admin". Se um envio expirou neste mesmo pump, rt.admin virou
  -- nil logo acima; o S ia para um alvo nil e sendNow dava erro de Lua (item.target:lower()).
  if #ids > 0 and rt.admin and (GetTime() - rt.statusAt >= STATUS_EVERY or not rt.polledStubs) then
    rt.statusAt, rt.polledStubs = GetTime(), true
    for i = 1, #ids, 6 do enqueue(rt.admin, "S", table.concat(ids, ",", i, math.min(i + 5, #ids))) end
  end
end

function BC.Report(note)
  if not db then return nil, "addon não pronto" end
  local n = 0; for _ in pairs(db.bugs) do n = n + 1 end
  if n >= MAX_QUEUE then return nil, "fila cheia" end
  local id = ("%x-%x-%04x"):format(time(), math.floor(GetTime() * 1000) % 0xFFFFFF, math.random(0, 0xFFFF))
  local body = (cfg.collect and cfg.collect(note) or ("note=" .. tostring(note) .. "\n")):sub(1, MAX_BODY)
  local e = { id = id, ts = time(), state = "queued", body = body, tries = 0 }
  db.bugs[id] = e
  if rt.iAmAdmin then   -- admin reportando: vai direto para a própria caixa de entrada
    db.inbox[id] = { id = id, from = short(UnitName("player")), recvAt = time(), status = "new", body = body, proto = PROTO }
    e.state, e.body, e.doneAt = "done", nil, time()
    say("report " .. id .. " guardado na caixa de entrada (faça /reload para gravar em disco)")
  else
    say("report " .. id .. " na fila; será enviado quando o admin estiver online")
    rt.startAt = math.min(rt.startAt or 0, GetTime() + 1)
    pump()
  end
  return id
end

---------------------------------------------------------------- lado admin
local function reply(to, ...) enqueue(to, ...) end
local function rateOK(from)
  local r = rt.rate[from]
  if not r or GetTime() - r.t0 > 3600 then r = { t0 = GetTime(), n = 0 }; rt.rate[from] = r end
  r.n = r.n + 1
  return r.n <= MAX_PER_HOUR
end
local function inboxCount() local n = 0; for _ in pairs(db.inbox) do n = n + 1 end; return n end

local function adminHandle(from, v, cmd, a1, a2, a3, a4)
  local inbox = db.inbox
  if cmd == "PING" then
    reply(from, "P", db.acceptReports ~= false and 1 or 0)
  elseif cmd == "D" then
    local id, i, n = a1, tonumber(a2), tonumber(a3)
    if not id or not i or not n or n < 1 or n > 200 or i < 1 or i > n or not a4 then return end
    local key = from .. "|" .. id
    local a = rt.asm[key] or { parts = {} }
    rt.asm[key] = a
    a.n, a.at = n, GetTime()
    a.parts[i] = a4
  elseif cmd == "E" then
    local id, n, len, sum = a1, tonumber(a2), tonumber(a3), tonumber(a4)
    if not id or not n or n < 1 or n > 200 then return end
    if inbox[id] then return reply(from, rt.durable[id] and "A2" or "A1", id) end   -- duplicado: só reconfirma
    local key = from .. "|" .. id
    local a, miss = rt.asm[key], {}
    for i = 1, n do if not (a and a.parts[i]) then miss[#miss + 1] = i end end
    if #miss > 0 then
      while #miss > 40 do miss[#miss] = nil end
      return reply(from, "N", id, table.concat(miss, ","))
    end
    local s = table.concat(a.parts, "", 1, n)
    rt.asm[key] = nil
    if #s ~= len or adler(s) ~= sum then return reply(from, "N", id, "all") end
    if inboxCount() >= MAX_INBOX then return reply(from, "R", id, "FULL") end
    if not rateOK(from) then return reply(from, "R", id, "RATE") end
    inbox[id] = { id = id, from = from, recvAt = time(), status = "new", body = unesc(s), proto = v }
    reply(from, "A1", id)
    if cfg.onReceived then cfg.onReceived(inbox[id]) end
  elseif cmd == "S" then
    local k = 0
    for id in tostring(a1 or ""):gmatch("[^,]+") do
      k = k + 1; if k > 8 then break end
      local e = inbox[id]
      if not e then reply(from, "U", id)
      else
        reply(from, rt.durable[id] and "A2" or "A1", id)
        if rt.durable[id] and e.status ~= "new" then reply(from, "F", id, e.status, noteEsc(e.note)) end
      end
    end
  end
end

function BC.Resolve(id, status, note)   -- status: triaged|fixed|wontfix|dup
  local e = db.inbox[id]; if not e then return false end
  e.status, e.note, e.resolvedAt = status, note, time()
  if status ~= "triaged" then enqueue(e.from, "F", id, status, noteEsc(note)) end
  return true
end
function BC.ImportResolutions(tbl)      -- tabela vinda de BugResolutions.lua (ver spec §9)
  for id, r in pairs(tbl or {}) do
    local e = db.inbox[id]
    if e and (e.status ~= r.status or e.note ~= r.note) then BC.Resolve(id, r.status, r.note) end
  end
end
function BC.List(status)
  local out = {}
  for _, e in pairs(db.inbox) do if not status or e.status == status then out[#out + 1] = e end end
  table.sort(out, function(a, b) return a.recvAt < b.recvAt end)
  return out
end
function BC.Flush() ReloadUI() end      -- grava SavedVariables em disco (torna os reports "duráveis")

---------------------------------------------------------------- recepção
local function onAddon(prefix, text, channel, sender)
  if prefix ~= cfg.prefix or isSecret(text) or isSecret(sender) then return end
  local from = short(sender)
  if not from or from:lower() == (short(UnitName("player")) or ""):lower() then return end
  local v, cmd, a1, a2, a3, a4 = strsplit(SEP, text)
  v = tonumber(v)
  if not v or not cmd then return end
  if cmd == "X" then   -- peer diz que não entende nossa versão
    if isAdmin(from) and not rt.warnedX then rt.warnedX = true; say("o admin usa o protocolo " .. tostring(a1) .. ": atualize o addon.") end
    return
  end
  if v ~= PROTO then
    if (rt.xAt or {})[from] == nil or GetTime() - rt.xAt[from] > 60 then
      rt.xAt = rt.xAt or {}; rt.xAt[from] = GetTime(); enqueue(from, "X", PROTO)
    end
    return
  end
  if rt.iAmAdmin then return adminHandle(from, v, cmd, a1, a2, a3, a4) end
  if not isAdmin(from) then return end                      -- só aceitamos respostas dos admins
  local e = a1 and db.bugs[a1]
  if cmd == "P" then
    if a1 == "1" then rt.admin, rt.adminAt, rt.discBackoff, rt.discNext = from, GetTime(), 30, 0; pump() end
  elseif cmd == "A1" and e and e.state ~= "done" then e.state = "received"
  elseif cmd == "A2" and e then
    if e.state ~= "done" then say("report " .. e.id .. " recebido e salvo pelo admin. Obrigado!") end
    e.state, e.body, e.doneAt = "done", nil, e.doneAt or time()
  elseif cmd == "U" and e and e.state ~= "done" then
    e.state = "queued"; (rt.r[e.id] or {}).nextTry = 0; pump()
  elseif cmd == "N" and e and e.state ~= "done" then
    if a2 == "all" then e.state = "queued"
    else
      local only = {}
      for i in tostring(a2):gmatch("%d+") do only[tonumber(i)] = true end
      sendChunks(e, only)
    end
  elseif cmd == "R" and e and e.state ~= "done" then
    e.state = "queued"; rt.r[e.id] = rt.r[e.id] or {}; rt.r[e.id].nextTry = GetTime() + 900
  elseif cmd == "F" and e then
    e.resolved = { status = a2, note = unesc(a3 or ""), at = time() }
    say(("seu report %s: %s %s"):format(e.id, tostring(a2), e.resolved.note))
  end
end
BC._onAddon = onAddon

---------------------------------------------------------------- inicialização
function BC.Init(c)
  cfg = c
  local sv = c.db()                       -- tabela SavedVariables do addon (conta inteira)
  db = sv
  db.bugs, db.inbox = db.bugs or {}, db.inbox or {}
  db.bugSchema = "bugq/1"
  rt.iAmAdmin = isAdmin(short(UnitName("player")))
  rt.startAt = GetTime() + 12
  for id, e in pairs(db.bugs) do
    if e.state == "sending" or e.state == "sent" then e.state = "queued" end
    if e.state == "done" and e.doneAt and time() - e.doneAt > STUB_DAYS * 86400 then db.bugs[id] = nil end
  end
  for id in pairs(db.inbox) do rt.durable[id] = true end   -- o que já estava no disco ao carregar
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then pcall(C_ChatInfo.RegisterAddonMessagePrefix, cfg.prefix) end
  -- esconde "No player named X is currently playing" de quem acabamos de consultar
  local tmpl = type(ERR_CHAT_PLAYER_NOT_FOUND_S) == "string" and ERR_CHAT_PLAYER_NOT_FOUND_S or "No player named '%s' is currently playing."
  local pat = "^" .. tmpl:gsub("([%(%)%.%[%]%*%+%-%?%^%$])", "%%%1"):gsub("%%s", "(.-)") .. "$"
  local addFilter = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if addFilter then
    addFilter("CHAT_MSG_SYSTEM", function(_, _, msg)
      if type(msg) ~= "string" or isSecret(msg) then return false end
      local n = msg:match(pat)
      local t = n and rt.recentTo[n:lower()]
      return (t and GetTime() - t < 10) and true or false
    end)
  end
  local f = CreateFrame("Frame")
  f:RegisterEvent("CHAT_MSG_ADDON")
  f:SetScript("OnEvent", function(_, e, ...) if e == "CHAT_MSG_ADDON" then onAddon(...) end end)
  local k = 0
  C_Timer.NewTicker(0.25, function()
    drain(); k = k + 1
    if k % 20 == 0 then
      pump()
      for key, a in pairs(rt.asm) do if GetTime() - a.at > 120 then rt.asm[key] = nil end end
    end
  end)
  if rt.iAmAdmin and c.resolutions then BC.ImportResolutions(c.resolutions()) end
end
