-- Ações: pedir vaga (sussurro), modo preencher, convidar, sussurrar e /who.
local T = require("t")
local H = require("helpers")
local describe, it = T.describe, T.it

local function entryOf(ns, name)
    for _, id in ipairs(ns.order) do
        local e = ns.entries[id]
        if e and e.name == name then return e end
    end
end

local function setup(opts)
    local w = H.world(opts and opts.world)
    H.sampleListings(w)
    local leader = H.login(w, { name = "Lider", account = "L" })
    local c = H.login(w, { level = 25 })
    H.search(w, c)
    return w, c, H.ns(c), leader
end

describe("ações: pedir vaga, convidar, sussurrar", function()
    it("pedir vaga: sussurra o texto ao líder, o jogo confirma e bloqueia repetir por 5 min", function()
        local w, c, ns, leader = setup()
        local g = entryOf(ns, "Lider")
        ns.AskToJoin(g)
        w:advance(0.5)
        T.eq(#c.data.whispersSent, 1)
        T.eq(c.data.whispersSent[1].msg, ns.BuildMessage(g))
        T.has(c:chatLines(), "request sent to Lider")
        T.eq(ns.pending.lider, nil)
        local ok, why = ns.CanAskToJoin(g)
        T.eq(ok, false); T.match(why, "already sent recently")
        w:advance(301)
        T.eq((ns.CanAskToJoin(g)), true)
        T.clean(c)
    end)

    it("dois pedidos seguidos a grupos diferentes: o segundo espera 3 s", function()
        local w = H.world()
        w.lfg:add({ leader = "G1", members = { { name = "G1", level = 20 }, { name = "x", level = 20 } } })
        w.lfg:add({ leader = "G2", members = { { name = "G2", level = 20 }, { name = "y", level = 20 } } })
        H.login(w, { name = "G1" }); H.login(w, { name = "G2" })
        local c = H.login(w)
        H.search(w, c)
        local ns = H.ns(c)
        ns.AskToJoin(entryOf(ns, "G1"))
        ns.AskToJoin(entryOf(ns, "G2"))
        T.eq(#c.data.whispersSent, 1)
        T.has(c:chatLines(), "wait a few seconds between requests")
        w:advance(3.1)
        ns.AskToJoin(entryOf(ns, "G2"))
        T.eq(#c.data.whispersSent, 2)
    end)

    it("líder offline: o 'No player named' libera o pendente, sem aviso de 5 s", function()
        local w, c, ns, leader = setup()
        leader:logout()
        ns.AskToJoin(entryOf(ns, "Lider"))
        w:advance(0.5)
        T.eq(ns.pending.lider, nil)
        w:advance(6)
        T.hasnt(c:chatLines(), "did not confirm")
        T.clean(c)
    end)

    it("sem confirmação do jogo em 5 s: avisa e libera", function()
        local w, c, ns = setup()
        w.net.dropFn = function() return true end
        local orig = c.env.C_ChatInfo.SendChatMessage
        c.env.C_ChatInfo.SendChatMessage = function() end -- bloqueio silencioso
        ns.AskToJoin(entryOf(ns, "Lider"))
        w:advance(5.5)
        T.has(c:chatLines(), "did not confirm the request was sent")
        T.eq(ns.pending.lider, nil)
        c.env.C_ChatInfo.SendChatMessage = orig
    end)

    it("já em grupo, em restrição de chat ou jogador solo: não envia e explica", function()
        local w, c, ns = setup()
        local g = entryOf(ns, "Lider")
        c.data.inGroup = true
        ns.AskToJoin(g)
        T.has(c:chatLines(), "not sent: you are already in a group")
        c.data.inGroup = false
        c.chatLockdown = true
        ns.AskToJoin(g)
        T.has(c:chatLines(), "not sent: the game's chat restriction is active")
        c.chatLockdown = false
        T.eq((ns.CanAskToJoin(entryOf(ns, "Padre"))), false)
        T.eq(#c.data.whispersSent, 0)
        T.clean(c)
    end)

    it("modo preencher: só abre o chat com o texto", function()
        local w, c, ns = setup()
        c:slash("/gf mode prefill")
        T.has(c:chatLines(), "send mode: prefill")
        local g = entryOf(ns, "Lider")
        ns.AskToJoin(g)
        T.eq(#c.data.whispersSent, 0)
        T.eq(c.data.chatInput, "/w Lider " .. ns.BuildMessage(g))
        c:slash("/gf mode direct")
        T.eq(H.db(c).sendMode, "direto")
    end)

    it("convidar: só jogador solo; em grupo só líder ou assistente", function()
        local w, c, ns = setup()
        local p = entryOf(ns, "Padre")
        T.eq(ns.CanInvite(entryOf(ns, "Lider")), false)
        ns.Invite(p)
        T.eq(c.data.invites[1], "Padre")
        c.data.inGroup = true
        T.eq(ns.CanInvite(p), false)
        c.data.assistant = true
        T.eq(ns.CanInvite(p), true)
        c.chatLockdown = true
        ns.Invite(p)
        T.has(c:chatLines(), "invite blocked")
        T.eq(#c.data.invites, 1)
        T.clean(c)
    end)

    it("convite chega a quem está online", function()
        local w = H.world()
        w.lfg:add({ leader = "Solo", members = { { name = "Solo", level = 20, class = "MAGE", roles = { dps = true } } } })
        local solo = H.login(w, { name = "Solo" })
        local got
        local c = H.login(w)
        H.search(w, c)
        local ns = H.ns(c)
        local f = solo.env.CreateFrame("Frame")
        f:RegisterEvent("PARTY_INVITE_REQUEST")
        f:SetScript("OnEvent", function(_, _, from) got = from end)
        ns.Invite(entryOf(ns, "Solo"))
        w:advance(0.2)
        T.eq(got, "Jogador")
    end)

    it("sussurrar abre o chat; /who só escreve o comando (SendWho é protegido)", function()
        local w, c, ns = setup()
        local p = entryOf(ns, "Padre")
        ns.OpenWhisper(p)
        T.eq(c.data.chatInput, "/w Padre ")
        ns.PrefillWho(p)
        T.eq(c.data.chatInput, '/who "Padre"')
        T.clean(c)
    end)

    it("resposta do /who é guardada por 30 min (guilda, zona, level); valores secretos são ignorados", function()
        local w, c, ns = setup()
        local p = entryOf(ns, "Padre")
        c.data.who = { { fullName = "Padre", fullGuildName = "Luz", area = "Barrens", level = 23 },
            { fullName = "Arqueiro", fullGuildName = c.env.issecretvalue and nil, area = "", level = 30 } }
        c:fireEvent("WHO_LIST_UPDATE")
        local info = ns.WhoInfo(p)
        T.eq(info.guild, "Luz"); T.eq(info.zone, "Barrens"); T.eq(info.level, 23)
        T.eq(ns.WhoInfo(entryOf(ns, "Arqueiro")).zone, nil)
        w:advance(30 * 60 + 2)
        T.eq(ns.WhoInfo(p), nil)
        T.clean(c)
    end)
end)
