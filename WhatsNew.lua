-- GrupoFacil: janela "Novidades" (What's New).
-- Abre sozinha toda vez que o addon carrega (login e /reload) até o jogador marcar, no fim da
-- lista, "Já li". A marcação vale por versão das notas (NEWS.version): na próxima versão volta.
-- O destaque da versão 0.13 é o bug report, com um botão que abre a janela de report.
-- Frame próprio, filho do UIParent, nada protegido; não abre no meio de um combate (espera sair).

local ADDON, NS = ...
local L = NS.L
local max = math.max

-- Notas da versão atual. Ao lançar outra versão: troque version e os textos (chaves novas em
-- todos os Locale_*.lua); quem marcou "Já li" na anterior volta a ver a janela.
local NEWS = {
    version = "0.13.0",
    highlight = {
        title = "New: report a problem to the author",
        body = "Found a bug, a wrong text or have an idea? Send it to the author from inside the game. The report waits on your computer and goes out by itself when the author is online. You can follow each report and you get a message when it is fixed.",
        where = "Where: the note icon next to the window title, the options or /gf bug.",
    },
    items = {
        "/gf bug <text> reports right from the chat; /gf bug list shows your reports.",
        "The list uses the whole window height the first time it opens.",
        "/gf spec with no talent points says so instead of showing the class name.",
        "A native search that gets no answer and a group member the game can't describe no longer count as errors in /gf diag.",
        "This window shows what changed in each version. Open it again any time with /gf news or from the options.",
    },
}
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

-- Layout encadeado e medido pelo texto traduzido (mesma regra da janela de report).
local function build()
    if frame then return frame end
    local f = CF("Frame", "GrupoFacilWhatsNew", UIParent, "BasicFrameTemplateWithInset")
    frame = f
    f:SetSize(W, 400)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local title = f.TitleText or text(f, "", "GameFontHighlight")
    if not f.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("GrupoFacil " .. NEWS.version .. " · " .. L["What's New"])
    if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilWhatsNew") end
    f:Hide()
    local used = 32

    -- destaque: o bug report, numa caixa com borda dourada e o botão que abre o report
    local hl = CF("Frame", nil, f, "BackdropTemplate")
    if hl.SetBackdrop then
        hl:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        hl:SetBackdropColor(0.25, 0.18, 0.02, 0.85)
        hl:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    hl:SetPoint("TOPLEFT", f, "TOPLEFT", PAD - 4, -32)
    hl:SetWidth(INNER + 8)
    local icon = hl:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOPLEFT", 12, -12)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    local tx = 12 + 36 + 10
    local tw = INNER + 8 - tx - 12
    local ht = text(hl, L[NEWS.highlight.title], "GameFontNormalLarge")
    ht:SetPoint("TOPLEFT", tx, -12)
    ht:SetWidth(tw)
    local hb = text(hl, L[NEWS.highlight.body], "GameFontHighlight")
    hb:SetPoint("TOPLEFT", ht, "BOTTOMLEFT", 0, -6)
    hb:SetWidth(tw)
    local hw = text(hl, L[NEWS.highlight.where], "GameFontHighlightSmall")
    hw:SetTextColor(1, 0.82, 0)
    hw:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 0, -6)
    hw:SetWidth(tw)
    f.report = button(hl, L["Report a problem"], 170, 24)
    f.report:SetPoint("TOPLEFT", hw, "BOTTOMLEFT", 0, -10)
    f.report:SetScript("OnClick", function()
        if NS.OpenBugReport then NS.OpenBugReport() end
    end)
    -- quem joga noutra regra (PvP, RP) ou facção não alcança o autor pelo jogo: link direto
    local lt = text(hl, L["Another ruleset (PvP, RP...) or faction? The game can't reach the author from there. Comment on CurseForge:"], "GameFontHighlightSmall")
    lt:SetPoint("TOPLEFT", f.report, "BOTTOMLEFT", 0, -10)
    lt:SetWidth(tw)
    f.link = NS.MakeLinkBox and NS.MakeLinkBox(hl, tw - 6, NS.BUG_COMMENTS_URL)
    if f.link then f.link:SetPoint("TOPLEFT", lt, "BOTTOMLEFT", 6, -4) end
    local hh = 12 + max(36, heightOf(ht) + 6 + heightOf(hb) + 6 + heightOf(hw) + 10 + 24 + 10 + heightOf(lt) + 4 + 20) + 12
    hl:SetHeight(hh)
    f.highlight = hl
    used = used + hh

    -- o resto da versão, em tópicos
    local al = text(f, L["Also in this version"], "GameFontNormal")
    al:SetPoint("TOPLEFT", hl, "BOTTOMLEFT", 4, -14)
    used = used + 14 + 12
    local prev, gap = al, 8
    f.items = {}
    for _, key in ipairs(NEWS.items) do
        local it = text(f, L[key], "GameFontHighlight")
        it:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", prev == al and 14 or 0, -gap)
        it:SetWidth(INNER - 18)
        local dot = text(f, "•", "GameFontHighlight")
        dot:SetPoint("TOPRIGHT", it, "TOPLEFT", -5, 0)
        f.items[#f.items + 1] = it
        used = used + gap + heightOf(it)
        prev, gap = it, 6
    end

    -- fim da lista: "Já li" (por versão) e o aviso de que a janela volta enquanto não marcar
    f.ack = CF("CheckButton", nil, f, "UICheckButtonTemplate")
    f.ack:SetSize(24, 24)
    local ackL = text(f, L["I've read it. Don't show again until the next version."], "GameFontNormal")
    ackL:SetWidth(INNER - 28)
    local ah = heightOf(ackL)
    local extra = max(0, (ah - 24) / 2)
    f.ack:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", -18, -(18 + extra))
    ackL:SetPoint("LEFT", f.ack, "RIGHT", 2, 0)
    f.ack:SetScript("OnClick", function(self)
        GrupoFacilDB.newsSeen = self:GetChecked() and NEWS.version or nil
        NS.D.Trace("NEWS", "novidades %s: %s", NEWS.version, GrupoFacilDB.newsSeen and "lidas" or "desmarcadas")
        refresh()
    end)
    used = used + 18 + max(24, ah)
    f.hint = text(f, L["While this is unchecked, this window opens every time the addon loads."], "GameFontDisableSmall")
    f.hint:SetPoint("TOPLEFT", f.ack, "BOTTOMLEFT", 4, -(4 + extra))
    f.hint:SetWidth(INNER - 8)
    used = used + 4 + extra + heightOf(f.hint)

    f.close = button(f, L["Close"], 100)
    f.close:SetPoint("BOTTOMRIGHT", -12, 12)
    f.close:SetScript("OnClick", function() f:Hide() end)
    used = used + 12 + 22 + 12

    f:SetHeight(used + 8)
    f:SetScript("OnShow", refresh)
    return f
end

function NS.OpenNews(why)
    if not GrupoFacilDB then return end
    build()
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
