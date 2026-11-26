-- GrupoFacil: janela "Novidades" (What's New).
-- Abre sozinha toda vez que o addon carrega (login e /reload) até o jogador marcar, no fim da
-- lista, "Já li". A marcação vale por versão das notas (NEWS.version): na próxima versão volta.
-- Uma página por versão (a mais nova primeiro). Cada página: o destaque da versão (só funcionalidades) e
-- os tópicos. Só a primeira página tem, embaixo, a caixa própria de report (bugs, feedback, ideias) com o
-- botão e o link do CurseForge, e o "Já li" (pedidos do Fraga, 26/11: reforçar o report sem misturar com
-- as novidades; paginar por versão para o report ficar sempre à vista na primeira).
-- Frame próprio, filho do UIParent, nada protegido; não abre no meio de um combate (espera sair).

local ADDON, NS = ...
local L = NS.L
local max, format = math.max, string.format

-- Notas, uma por versão, da mais nova para a mais velha. Ao lançar outra versão: ponha a nova no topo
-- (chaves novas em todos os Locale_*.lua); quem marcou "Já li" na anterior volta a ver a janela.
local PAGES = {
    {
        version = "0.14.0",
        highlight = {
            title = "New: groups for your quests",
            body = "A magnifier next to each quest in the objective list and in the quest details. Click it: GrupoFacil searches Looking For Group in the quest's zone and shows first the groups doing that quest. No group? Create one with one click. Players who also use GrupoFacil find each other's quests silently, and the invite from the leader you asked is accepted by itself.",
            where = "Where: the magnifier next to a quest, the Quests tab of the window or /gf quests.",
            icon = "Interface\\Common\\UI-Searchbox-Icon",
            button = "Open quest groups",
            open = function() if NS.ShowQuestWindow then NS.ShowQuestWindow(true) end end,
        },
        items = {
            "Leaders can turn on auto-invite for players who ask for the same quest (off by default, at most 6 invites every 10 minutes).",
            "When the quest is done, the addon offers to leave the group and take it out of Looking For Group. It never does it on its own.",
            "A warning when you get close to the game's limit of about 16 groups joined per hour.",
            "Dungeons and Quests are tabs of the same window. The Quests tab starts with the quests in your log and has its own tour (/gf tour).",
            "Recommend to a friend (Quests tab, options or /gf share) puts a ready message in your chat box: quest groups work better the more players use GrupoFacil.",
        },
    },
    {
        version = "0.13.0",
        highlight = {
            title = "New: report a problem to the author",
            body = "Found a bug, a wrong text or have an idea? Send it to the author from inside the game. The report waits on your computer and goes out by itself when the author is online. You can follow each report and you get a message when it is fixed.",
            where = "Where: the note icon next to the window title, the options or /gf bug.",
            icon = "Interface\\Icons\\INV_Misc_Note_01",
        },
        items = {
            "/gf bug <text> reports right from the chat; /gf bug list shows your reports.",
            "The list uses the whole window height the first time it opens.",
            "/gf spec with no talent points says so instead of showing the class name.",
            "A native search that gets no answer and a group member the game can't describe no longer count as errors in /gf diag.",
            "This window shows what changed in each version. Open it again any time with /gf news or from the options.",
        },
    },
}
local NEWS = PAGES[1]
NS.NEWS_VERSION = NEWS.version

local W, PAD = 520, 16
local INNER = W - 2 * PAD
local DELAY = 3 -- segundos depois de entrar no mundo (deixa a tela de carregamento sumir)

local n = 0
local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    n = n + 1
    local tag = "News:" .. (name or kind) .. "#" .. n
    local orig = f.SetScript
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then fn = NS.D.Wrap(tag .. "." .. script, fn) end
        return orig(self, script, fn)
    end
    return f
end

local function text(parent, str, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetText(str or "")
    fs:SetJustifyH("LEFT")
    fs:SetJustifyV("TOP")
    return fs
end

local function button(parent, label, w, h)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(label)
    local fs = b.GetFontString and b:GetFontString()
    local tw = fs and fs:GetStringWidth()
    if tw and tw + 22 > w then b:SetWidth(tw + 22) end
    return b
end

local function heightOf(fs) return max(12, fs:GetStringHeight() or 0) end

function NS.NewsSeen() return GrupoFacilDB and GrupoFacilDB.newsSeen == NEWS.version end

local frame
local function refresh()
    if not frame then return end
    local seen = NS.NewsSeen()
    frame.ack:SetChecked(seen)
    frame.hint:SetShown(not seen)
end

local function showPage(i)
    local f = frame
    i = math.min(math.max(1, i or 1), #PAGES)
    f.page = i
    for k, p in ipairs(f.pages) do p:SetShown(k == i) end
    local page = PAGES[i]
    f.titleFS:SetText("GrupoFacil " .. page.version .. " · " .. L["What's New"])
    f.pageFS:SetText(format(L["Version %s · page %d of %d"], page.version, i, #PAGES))
    f.newer:SetEnabled(i > 1)
    f.older:SetEnabled(i < #PAGES)
    f:SetHeight(32 + f.pages[i].h + 14 + 22 + 12 + 8)
    f.action = f.pages[i].action
end
NS.NewsPage = function(i) if frame and i then showPage(i) end return frame and frame.page end

-- Layout encadeado e medido pelo texto traduzido (mesma regra da janela de report).
local function build()
    if frame then return frame end
    local f = CF("Frame", "GrupoFacilWhatsNew", UIParent, "BasicFrameTemplateWithInset")
    frame = f
    f:SetSize(W, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    NS.Toplevel(f)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f.TitleText or text(f, "", "GameFontHighlight")
    if not f.TitleText then title:SetPoint("TOP", 0, -5) end
    f.titleFS = title
    if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilWhatsNew") end
    f:Hide()

    -- caixa com borda colorida, ícone, título, texto, "onde" e um botão opcional (destaque e report)
    local function box(parent, anchorTop, dx, color, bg, iconTex, titleKey, bodyKey, whereKey, btnKey, onClick, gap)
        local b = CF("Frame", nil, parent, "BackdropTemplate")
        if b.SetBackdrop then
            b:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            b:SetBackdropColor(bg[1], bg[2], bg[3], 0.85)
            b:SetBackdropBorderColor(color[1], color[2], color[3], 1)
        end
        if anchorTop then b:SetPoint("TOPLEFT", anchorTop, "BOTTOMLEFT", dx, -(gap or 14))
        else b:SetPoint("TOPLEFT", parent, "TOPLEFT", -4, 0) end
        b:SetWidth(INNER + 8)
        local icon = b:CreateTexture(nil, "ARTWORK")
        icon:SetSize(36, 36)
        icon:SetPoint("TOPLEFT", 12, -12)
        icon:SetTexture(iconTex)
        local tx = 12 + 36 + 10
        local tw = INNER + 8 - tx - 12
        local ht = text(b, L[titleKey], "GameFontNormalLarge")
        ht:SetPoint("TOPLEFT", tx, -12)
        ht:SetWidth(tw)
        local hb = text(b, L[bodyKey], "GameFontHighlight")
        hb:SetPoint("TOPLEFT", ht, "BOTTOMLEFT", 0, -6)
        hb:SetWidth(tw)
        local hw = text(b, L[whereKey], "GameFontHighlightSmall")
        hw:SetTextColor(color[1], color[2], color[3])
        hw:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -6)
        hw:SetWidth(tw)
        b.h = heightOf(ht) + 6 + heightOf(hb) + 6 + heightOf(hw)
        b.last = hw
        if btnKey then
            local btn = button(b, L[btnKey], 170, 24)
            btn:SetPoint("TOPLEFT", hw, "BOTTOMLEFT", 0, -10)
            btn:SetScript("OnClick", onClick)
            b.button = btn
            b.last = btn
            b.h = b.h + 10 + 24
        end
        b.title, b.tw = ht, tw
        return b
    end

    f.pages = {}
    for pi, news in ipairs(PAGES) do
        local pg = CF("Frame", nil, f)
        pg:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -32)
        pg:SetWidth(INNER)
        local used = 0

        -- 1) o que é novo nesta versão (só funcionalidades)
        local hl = box(pg, nil, 0, { 1, 0.82, 0 }, { 0.25, 0.18, 0.02 }, news.highlight.icon or "Interface\\Icons\\INV_Misc_Note_01",
            news.highlight.title, news.highlight.body, news.highlight.where, news.highlight.button,
            news.highlight.open and function() news.highlight.open() end)
        pg.action = hl.button
        local hh = 12 + max(36, hl.h) + 12
        hl:SetHeight(hh)
        pg.highlight = hl
        used = used + hh

        -- o resto da versão, em tópicos
        local al = text(pg, L["Also in this version"], "GameFontNormal")
        al:SetPoint("TOPLEFT", hl, "BOTTOMLEFT", 4, -14)
        used = used + 14 + 12
        local prev, gap = al, 8
        pg.items = {}
        for _, key in ipairs(news.items) do
            local it = text(pg, L[key], "GameFontHighlight")
            it:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == al and 14 or 0, -gap)
            it:SetWidth(INNER - 18)
            local dot = text(pg, "•", "GameFontHighlight")
            dot:SetPoint("TOPRIGHT", it, "TOPLEFT", -5, 0)
            pg.items[#pg.items + 1] = it
            used = used + gap + heightOf(it)
            prev, gap = it, 6
        end

        if pi == 1 then
            -- 2) report: caixa própria, fixa na primeira página, separada das novidades
            local rp = box(pg, prev, -18, { 1, 0.35, 0.3 }, { 0.22, 0.05, 0.04 }, "Interface\\Icons\\INV_Misc_Note_01",
                "Bugs, feedback or ideas? Tell the author",
                "Found a bug, a wrong text or have an idea? Send it to the author from inside the game. The report waits on your computer and goes out by itself when the author is online. You can follow each report and you get a message when it is fixed.",
                "Where: the note icon next to the window title, the options or /gf bug.", "Report a problem",
                function() if NS.OpenBugReport then NS.OpenBugReport() end end, 16)
            f.report = rp.button
            f.reportBox = rp
            -- quem joga noutra regra (PvP, RP) ou facção não alcança o autor pelo jogo: link direto
            local lt = text(rp, L["Another ruleset (PvP, RP...) or faction? The game can't reach the author from there. Comment on CurseForge:"], "GameFontHighlightSmall")
            lt:SetPoint("TOPLEFT", f.report, "BOTTOMLEFT", 0, -10)
            lt:SetWidth(rp.tw)
            f.link = NS.MakeLinkBox and NS.MakeLinkBox(rp, rp.tw - 6, NS.BUG_COMMENTS_URL)
            if f.link then f.link:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 6, -4) end
            local rh = 12 + max(36, rp.h + 10 + heightOf(lt) + 4 + 20) + 12
            rp:SetHeight(rh)
            used = used + 16 + rh

            -- "Já li" (por versão) e o aviso de que a janela volta enquanto não marcar
            f.ack = CF("CheckButton", nil, pg, "UICheckButtonTemplate")
            f.ack:SetSize(24, 24)
            local ackL = text(pg, L["I've read it. Don't show again until the next version."], "GameFontNormal")
            ackL:SetWidth(INNER - 28)
            local ah = heightOf(ackL)
            local extra = max(0, (ah - 24) / 2)
            f.ack:SetPoint("TOPLEFT", rp, "BOTTOMLEFT", 4, -(18 + extra))
            ackL:SetPoint("LEFT", f.ack, "RIGHT", 2, 0)
            f.ack:SetScript("OnClick", function(self)
                GrupoFacilDB.newsSeen = self:GetChecked() and NEWS.version or nil
                NS.D.Trace("NEWS", "novidades %s: %s", NEWS.version, GrupoFacilDB.newsSeen and "lidas" or "desmarcadas")
                refresh()
            end)
            used = used + 18 + max(24, ah)
            f.hint = text(pg, L["While this is unchecked, this window opens every time the addon loads."], "GameFontDisableSmall")
            f.hint:SetPoint("TOPLEFT", f.ack, "BOTTOMLEFT", 4, -(4 + extra))
            f.hint:SetWidth(INNER - 8)
            used = used + 4 + extra + heightOf(f.hint)
        end
        pg.h = used
        pg:SetHeight(used)
        f.pages[pi] = pg
    end

    -- rodapé: páginas (uma por versão) e fechar
    f.newer = button(f, L["< Newer"], 90)
    f.newer:SetPoint("BOTTOMLEFT", 12, 12)
    f.newer:SetScript("OnClick", function() showPage(f.page - 1) end)
    f.older = button(f, L["Older >"], 90)
    f.older:SetPoint("LEFT", f.newer, "RIGHT", 6, 0)
    f.older:SetScript("OnClick", function() showPage(f.page + 1) end)
    f.close = button(f, L["Close"], 100)
    f.close:SetPoint("BOTTOMRIGHT", -12, 12)
    f.close:SetScript("OnClick", function() f:Hide() end)
    f.pageFS = text(f, "", "GameFontDisableSmall")
    f.pageFS:SetPoint("LEFT", f.older, "RIGHT", 8, 0)
    f.pageFS:SetPoint("RIGHT", f.close, "LEFT", -8, 0)
    f.pageFS:SetJustifyH("CENTER")
    f.pageFS:SetWordWrap(false)

    f:SetScript("OnShow", refresh)
    showPage(1)
    return f
end

function NS.OpenNews(why)
    if not GrupoFacilDB then return end
    build()
    showPage(1) -- sempre abre na versão atual, com o report à vista
    refresh()
    frame:Show()
    frame:Raise()
    NS.D.Trace("NEWS", "novidades %s abertas (%s)", NEWS.version, why or "?")
end
function NS.NewsFrame() return frame end -- para teste e diagnóstico

------------------------------------------------------------------------
-- abre sozinha a cada carga (login e /reload) enquanto "Já li" não estiver marcado
------------------------------------------------------------------------
local waitingCombat = false
local function autoOpen()
    if NS.NewsSeen() then return end
    if InCombatLockdown() then
        waitingCombat = true -- não aparece no meio da luta; abre ao sair do combate
        return
    end
    NS.OpenNews("carga")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", NS.D.Wrap("news.OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD") -- só a primeira vez de cada carga, não a cada portal
        C_Timer.After(DELAY, NS.D.Wrap("news.auto", autoOpen))
    elseif event == "PLAYER_REGEN_ENABLED" and waitingCombat then
        waitingCombat = false
        autoOpen()
    end
end))
