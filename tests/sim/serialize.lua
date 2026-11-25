-- Grava e lê SavedVariables do jeito do cliente: um arquivo Lua com "Nome = valor".
-- Só string, número, booleano e tabela sobrevivem (função, userdata e thread somem, como no jogo).
-- Tabelas repetidas viram cópias; ciclos são cortados (o cliente também não grava referência).
local M = {}

local function quote(s)
    return (string.format("%q", s):gsub("\\\n", "\\n"):gsub("\r", "\\r"):gsub("%z", "\\0"))
end

local function num(n)
    if n ~= n then return "0/0" end
    if n == math.huge then return "math.huge" end
    if n == -math.huge then return "-math.huge" end
    if n == math.floor(n) and math.abs(n) < 2 ^ 53 then return string.format("%d", n) end
    return string.format("%.17g", n)
end

local function keyText(k)
    local t = type(k)
    if t == "string" then return "[" .. quote(k) .. "]" end
    if t == "number" then return "[" .. num(k) .. "]" end
    if t == "boolean" then return "[" .. tostring(k) .. "]" end
    return nil
end

local function value(v, indent, seen, out)
    local t = type(v)
    if t == "string" then out[#out + 1] = quote(v)
    elseif t == "number" then out[#out + 1] = num(v)
    elseif t == "boolean" then out[#out + 1] = tostring(v)
    elseif t == "table" then
        if seen[v] then out[#out + 1] = "nil"; return end
        seen[v] = true
        out[#out + 1] = "{\n"
        local keys = {}
        for k in pairs(v) do if keyText(k) then keys[#keys + 1] = k end end
        table.sort(keys, function(a, b)
            local ta, tb = type(a), type(b)
            if ta ~= tb then return ta < tb end
            if ta == "boolean" then return (a and 1 or 0) < (b and 1 or 0) end
            return a < b
        end)
        for _, k in ipairs(keys) do
            local x = v[k]
            local tx = type(x)
            if tx == "string" or tx == "number" or tx == "boolean" or tx == "table" then
                out[#out + 1] = indent .. "\t" .. keyText(k) .. " = "
                value(x, indent .. "\t", seen, out)
                out[#out + 1] = ",\n"
            end
        end
        out[#out + 1] = indent .. "}"
        seen[v] = nil
    else
        out[#out + 1] = "nil"
    end
end

-- names: lista de nomes de variáveis globais; env: tabela de globais do cliente.
function M.dump(names, env)
    local out = {}
    for _, name in ipairs(names) do
        local v = env[name]
        out[#out + 1] = "\n" .. name .. " = "
        local t = type(v)
        if t == "string" or t == "number" or t == "boolean" or t == "table" then
            value(v, "", {}, out)
        else
            out[#out + 1] = "nil"
        end
        out[#out + 1] = "\n"
    end
    return table.concat(out)
end

-- Executa o texto gravado dentro do ambiente do cliente (é assim que o jogo carrega).
function M.load(text, env)
    if not text or text == "" then return true end
    local fn, err = loadstring(text, "=SavedVariables")
    if not fn then return false, err end
    setfenv(fn, env)
    return pcall(fn)
end

return M
