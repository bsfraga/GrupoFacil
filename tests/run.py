#!/usr/bin/env python3
"""Roda a suíte Lua com o Lua 5.1 embutido no lupa (para quem não tem lua5.1 instalado).

Uso, da raiz do repositório:  pip install lupa && python3 tests/run.py [filtro]
"""
import os
import sys

try:
    import lupa.lua51 as lupa
except ImportError:
    sys.exit("precisa do lupa com Lua 5.1: pip install lupa")

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(root)
lua = lupa.LuaRuntime(encoding="latin-1")
g = lua.globals()
g.arg = lua.table(*sys.argv[1:]) if len(sys.argv) > 1 else lua.table()
# os.exit dentro do lupa encerraria o Python sem o código certo: o runner devolve o resultado.
lua.execute("os.exit = nil")
with open("tests/run.lua", "r", encoding="latin-1") as f:
    ok = lua.execute(f.read())
sys.exit(0 if ok else 1)
