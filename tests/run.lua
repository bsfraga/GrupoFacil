-- Roda toda a suíte: lua5.1 tests/run.lua [filtro]   (ou: python3 tests/run.py [filtro])
-- Deve ser chamado da raiz do repositório.
package.path = "./tests/?.lua;./tests/lib/?.lua;" .. package.path
local T = require("t")
T.filter = (arg and arg[1]) or GF_TEST_FILTER
require("helpers").ROOT = "."

local SPECS = {
    "spec.sim_spec",        -- o próprio simulador (para confiar nele)
    "spec.load_spec",       -- carga, SavedVariables, migração, idiomas
    "spec.message_spec",    -- mensagem do pedido de vaga, spec, roles
    "spec.results_spec",    -- leitura dos resultados, valores secretos, bloqueio de chat
    "spec.filters_spec",    -- filtros, contagens, ordenação, esconder/bloquear
    "spec.actions_spec",    -- convidar, pedir vaga, sussurro, /who, busca de novo
    "spec.ui_spec",         -- janela principal e menus
    "spec.options_spec",    -- opções, minimapa, tour
    "spec.slash_spec",      -- comandos /gf
    "spec.diag_spec",       -- diagnóstico
    "spec.locale_spec",     -- traduções e chaves usadas
    "spec.bugchannel_spec", -- protocolo do canal de bug report
    "spec.bugui_spec",      -- janela de report e caixa de entrada do admin
    "spec.smoke_spec",      -- tudo junto em cada idioma, sem erro de Lua
}

local t0 = os.clock()
for _, name in ipairs(SPECS) do
    local ok, err = pcall(require, name)
    if not ok then
        if tostring(err):find("module '" .. name .. "' not found", 1, true) then
            io.write("\n(aviso: " .. name .. " ainda não existe)\n")
        else
            table.insert(T.results, { name = name .. " (carga)", ok = false, err = err })
        end
    end
end
local ok = T.summary()
io.write(string.format("tempo: %.1fs\n", os.clock() - t0))
if os.exit then os.exit(ok and 0 or 1) end
return ok
