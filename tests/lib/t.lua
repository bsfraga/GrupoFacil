-- Mini framework de testes (Lua 5.1, sem dependências).
local T = { results = {}, current = nil, filter = nil }

local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function T.describe(name, fn)
    local prev = T.current
    T.current = (prev and (prev .. " > ") or "") .. name
    fn()
    T.current = prev
end

function T.it(name, fn)
    local full = (T.current and (T.current .. " > ") or "") .. name
    if T.filter and not full:lower():find(T.filter:lower(), 1, true) then return end
    local t0 = os.clock()
    local ok, err = xpcall(fn, function(e) return debug.traceback(tostring(e), 2) end)
    table.insert(T.results, { name = full, ok = ok, err = err, time = os.clock() - t0 })
    io.write(ok and "." or "F")
    io.flush()
end

function T.fail(msg) error(msg, 2) end
function T.ok(v, msg) if not v then error(msg or "esperava verdadeiro", 2) end return v end
function T.no(v, msg) if v then error((msg or "esperava falso") .. " (veio " .. fmt(v) .. ")", 2) end end
function T.eq(a, b, msg)
    if a ~= b then error((msg and (msg .. ": ") or "") .. "esperava " .. fmt(b) .. ", veio " .. fmt(a), 2) end
end
function T.near(a, b, tol, msg)
    if type(a) ~= "number" or math.abs(a - b) > (tol or 1e-6) then error((msg or "") .. " esperava ~" .. fmt(b) .. ", veio " .. fmt(a), 2) end
end
function T.match(s, pat, msg)
    if type(s) ~= "string" or not s:find(pat) then error((msg and (msg .. ": ") or "") .. "esperava casar " .. fmt(pat) .. " em " .. fmt(s), 2) end
end
function T.nomatch(s, pat, msg)
    if type(s) == "string" and s:find(pat) then error((msg and (msg .. ": ") or "") .. "não esperava " .. fmt(pat) .. " em " .. fmt(s), 2) end
end
function T.has(list, pat, msg)
    for _, l in ipairs(list) do if type(l) == "string" and l:find(pat) then return l end end
    error((msg and (msg .. ": ") or "") .. "nenhuma linha casa " .. fmt(pat) .. "\n  linhas: " .. table.concat(list, "\n         "), 2)
end
function T.hasnt(list, pat, msg)
    for _, l in ipairs(list) do
        if type(l) == "string" and l:find(pat) then error((msg and (msg .. ": ") or "") .. "linha inesperada: " .. l, 2) end
    end
end
function T.deepEq(a, b, path)
    path = path or "valor"
    if type(a) ~= type(b) then error(path .. ": tipos diferentes " .. type(a) .. " vs " .. type(b), 2) end
    if type(a) ~= "table" then if a ~= b then error(path .. ": " .. fmt(a) .. " ~= " .. fmt(b), 2) end return end
    for k, v in pairs(a) do T.deepEq(v, b[k], path .. "." .. tostring(k)) end
    for k in pairs(b) do if a[k] == nil then error(path .. "." .. tostring(k) .. " faltando", 2) end end
end
-- nenhum erro de Lua no cliente (inclusive os capturados pelo /gf diag)
function T.clean(c, msg)
    local errs = c:luaErrors()
    if #errs > 0 then error((msg or ("erros de Lua em " .. c.name)) .. ":\n" .. table.concat(errs, "\n---\n"), 2) end
    local ns = c.namespaces and c.namespaces.GrupoFacil
    local db = c.env and c.env.GrupoFacilDB
    if db and db.diag and db.diag.errors and #db.diag.errors > 0 then
        local lines = {}
        for _, e in ipairs(db.diag.errors) do lines[#lines + 1] = tostring(e.msg) .. " @ " .. tostring(e.ctx) end
        error((msg or ("erros no diagnóstico de " .. c.name)) .. ":\n" .. table.concat(lines, "\n"), 2)
    end
end

function T.summary()
    local failed = {}
    local total = 0
    for _, r in ipairs(T.results) do
        total = total + 1
        if not r.ok then failed[#failed + 1] = r end
    end
    io.write("\n\n")
    for _, r in ipairs(failed) do
        io.write("FALHOU: " .. r.name .. "\n" .. tostring(r.err) .. "\n\n")
    end
    io.write(string.format("%d testes, %d passaram, %d falharam\n", total, total - #failed, #failed))
    return #failed == 0
end

return T
