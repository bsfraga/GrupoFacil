-- GrupoFacil: primeiro uso. Um aviso no chat uma vez por conta, uma faixa na janela
-- oferecendo o tour e o tour em si (balões dentro da janela do addon, nunca nos frames da Blizzard).
-- O tour não começa sozinho: a janela abre junto com o LFG, quando o jogador já quer usar o LFG.

local ADDON, NS = ...
local L = NS.L
local format = string.format

local TOUR_VERSION = 1   -- subir quando o tour mudar o bastante para valer mostrar de novo
local QUEST_TOUR_VERSION = 1 -- tour da aba Missões (visto à parte: quem já viu o das masmorras também vê este)
local CALLOUT_W = 300

local function tourDB()
    local db = GrupoFacilDB
    if not db then return {} end
    if type(db.tour) ~= "table" then db.tour = {} end
    return db.tour
end

-- cada aba tem o seu tour e o seu "já visto"
local FIELD = { dungeons = "version", quests = "quests" }
local VERSION = { dungeons = TOUR_VERSION, quests = QUEST_TOUR_VERSION }
local function isDone(key)
    key = key or "dungeons"
    return (tonumber(tourDB()[FIELD[key]]) or 0) >= VERSION[key]
end
local function markDone(key, how)
    key = key or "dungeons"
    tourDB()[FIELD[key]] = VERSION[key]
    NS.D.Trace("TOUR", "tour %s encerrado (%s)", key, how)
end

local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    local orig = f.SetScript
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then fn = NS.D.Wrap("tour." .. script, fn) end
        return orig(self, script, fn)
    end
    return f
end

local function button(parent, text, w)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    -- traduções podem ser mais longas: cresce para caber o texto
    local fs = b.GetFontString and b:GetFontString()
    local tw = fs and fs:GetStringWidth()
    if tw and tw + 22 > w then b:SetWidth(tw + 22) end
    return b
end

local function box(parent, alpha)
    local f = CF("Frame", nil, parent, "BackdropTemplate")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 },
        })
        f:SetBackdropColor(0.04, 0.05, 0.09, alpha)
        f:SetBackdropBorderColor(1, 0.82, 0, 1)
    end
    return f
end

------------------------------------------------------------------------
-- passos: a moldura se prende aos controles reais (NS.UIRefs), então acompanha o tamanho da janela
------------------------------------------------------------------------
local STEPS = {
    {   title = "Pick what to list",
        body = function() return L["Players lists people looking for a group: use it when you lead. Groups lists groups looking for players: use it when you are solo. All shows both."] end,
        from = { "modeFirst", "TOPLEFT", -6, 6 }, to = { "modeLast", "BOTTOMRIGHT", 6, -6 }, below = "LEFT" },
    {   title = "Filter the list",
        body = function() return L["Type a level range or click Near me. Click the class icons to pick classes (none = all). Role filters by tank, healer or DPS; in Groups mode it becomes Needs: groups missing that role."]
            .. " " .. L["Dungeon picks which dungeons to show, and Hide filters gives the list more room."] end,
        from = { "level", "TOPLEFT", -8, 8 }, to = { "clear", "BOTTOMRIGHT", 6, -6 }, below = "LEFT" },
    {   title = "Act on a row",
        body = function()
            return format(L["Invite asks a solo player into your group. Ask to join whispers the group leader your message:\n|cffffffff%s|r\nWhisper opens the chat to write your own."], NS.BuildMessage())
        end,
        from = { "sample", "TOPLEFT", -2, 2 }, to = { "sample", "BOTTOMRIGHT", 2, -2 }, below = "LEFT", sampleRow = true },
    {   title = "Refresh the list",
        body = function() return L["GrupoFacil reads your Looking For Group search. Search again repeats the last one. The game only allows it from your click and refuses searches that come too fast."] end,
        from = { "search", "TOPLEFT", -6, 6 }, to = { "search", "BOTTOMRIGHT", 6, -6 }, below = "RIGHT" },
    {   title = "Your message and settings",
        body = function() return L["The bottom line shows the message leaders receive. Options changes it ({level}, {spec}, {class}, {name}), the send mode, the language and the minimap button. /gf tour shows this tour again."] end,
        from = { "pageUp", "TOPLEFT", -6, 6 }, to = { "panel", "BOTTOMRIGHT", -8, 8 }, above = "LEFT" },
}
NS.TOUR_STEPS = STEPS -- para teste

-- Tour da aba Missões (pedido do Fraga, 26/11). Aponta para um exemplo desenhado por cima da aba,
-- então funciona com ou sem missão no registro e não mexe na missão escolhida.
local QSTEPS = {
    {   title = "Your quests",
        body = function() return L["The Quests tab starts with the quests in your log. Find group searches the quest's zone in Looking For Group. The magnifier next to a quest in the objective list or in the quest details does the same."] end,
        from = { "q:pick", "TOPLEFT", -4, 4 }, to = { "q:pick", "BOTTOMRIGHT", 4, -4 }, below = "LEFT", sample = "pick" },
    {   title = "Groups for the quest",
        body = function() return L["Groups doing the same quest come first. Join whispers the leader; when the leader also uses GrupoFacil, the invite is accepted by itself. < Your quests goes back to the list."] end,
        from = { "q:row", "TOPLEFT", -4, 4 }, to = { "q:row", "BOTTOMRIGHT", 4, -4 }, above = "LEFT", sample = "quest" },
    {   title = "No group? Create one",
        body = function() return L["Create group lists your group in Looking For Group for this quest; a dungeon quest goes to Dungeons. The line beside it shows how your group is. Remove listing takes it out, and taking it out in the game's window also clears it here."] end,
        from = { "q:create", "TOPLEFT", -4, 4 }, to = { "q:create", "BOTTOMRIGHT", 4, -4 }, below = "LEFT", sample = "quest" },
    {   title = "Requests",
        body = function() return L["Players who ask through GrupoFacil show up here, with Invite and Ignore. The tab shows how many are waiting, like Quests (1)."] end,
        from = { "q:req", "TOPLEFT", -4, 4 }, to = { "q:req", "BOTTOMRIGHT", 4, -4 }, below = "LEFT", sample = "quest" },
    {   title = "Options",
        body = function() return L["Auto-invite players who ask for the same quest, auto-accept the invite from a leader you asked, and the magnifier next to quests. /gf tour on this tab shows this tour again."] end,
        from = { "q:options", "TOPLEFT", -4, 4 }, to = { "q:options", "BOTTOMRIGHT", 4, -4 }, above = "LEFT" },
}
NS.QUEST_TOUR_STEPS = QSTEPS -- para teste
local TOURS = { dungeons = STEPS, quests = QSTEPS }

local panel, banner, callout, highlight, sample
local qbanner, qsample -- da aba Missões (construídos quando a aba existe)
local step -- passo atual (nil = tour parado)
local tourKey = "dungeons" -- tour em andamento

------------------------------------------------------------------------
-- construção (preguiçosa: só quando a janela do addon aparece)
------------------------------------------------------------------------
local function buildSampleRow(parent, level)
    local r = CF("Frame", nil, parent)
    r:SetFrameLevel(level)
    local list = NS.UIRefs and NS.UIRefs.list or panel
    r:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    r:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    r:SetHeight(38)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.09, 0.12, 1)
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    local name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
    name:SetText(L["Example group"] .. "  |cffaaaaaa" .. format(L["Lvl %d"], 30) .. "|r")
    local info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    local ri = NS.RoleIcon or function() return "" end
    info:SetText(format("3/5  %s1 %s0 %s2", ri("tank"), ri("healer"), ri("dps")))
    local b2 = button(r, L["Whisper"], 74)
    b2:SetHeight(20)
    b2:SetPoint("RIGHT", -4, 0)
    local b1 = button(r, L["Ask to join"], 82)
    b1:SetHeight(20)
    b1:SetPoint("RIGHT", b2, "LEFT", -3, 0)
    -- botões de exemplo: não fazem nada
    b1:SetScript("OnClick", function() end)
    b2:SetScript("OnClick", function() end)
    r:Hide()
    return r
end

local build -- definido abaixo

-- exemplo da aba Missões: duas páginas (lista das suas missões; uma missão escolhida)
local function fakeButton(parent, text, w)
    local b = button(parent, text, w)
    b:SetHeight(20)
    b:SetScript("OnClick", function() end) -- exemplo: não faz nada
    return b
end
local function sampleLine(parent, top, title, info, btnText, btnW)
    local r = CF("Frame", nil, parent)
    r:SetPoint("TOPLEFT", 0, top)
    r:SetPoint("TOPRIGHT", 0, top)
    r:SetHeight(34)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.09, 0.12, 1)
    local b = fakeButton(r, btnText, btnW)
    b:SetPoint("RIGHT", -4, 0)
    local n = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    n:SetPoint("TOPLEFT", 8, -4)
    n:SetPoint("RIGHT", b, "LEFT", -6, 0)
    n:SetJustifyH("LEFT")
    n:SetWordWrap(false)
    n:SetText(title)
    local i = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    i:SetPoint("TOPLEFT", n, "BOTTOMLEFT", 0, -3)
    i:SetPoint("RIGHT", b, "LEFT", -6, 0)
    i:SetJustifyH("LEFT")
    i:SetWordWrap(false)
    i:SetText(info)
    r.button = b
    return r
end

local function buildQuestSample(qp, level)
    local s = CF("Frame", nil, qp)
    s:SetFrameLevel(level)
    s:SetPoint("TOPLEFT", qp, "TOPLEFT", 8, -26)
    s:SetPoint("BOTTOMRIGHT", qp, "BOTTOMRIGHT", -8, 40)
    s:EnableMouse(true)
    local bg = s:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.03, 0.04, 0.07, 1)
    local where = format("Westfall · %s", format(L["Lvl %d"], 18))

    -- página 1: a lista das suas missões
    s.pick = CF("Frame", nil, s)
    s.pick:SetPoint("TOPLEFT", 4, -36)
    s.pick:SetPoint("RIGHT", -4, 0)
    s.pick:SetHeight(72)
    local pt = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    pt:SetPoint("BOTTOMLEFT", s.pick, "TOPLEFT", 4, 8)
    pt:SetText(L["Your quests"])
    s.pickTitle = pt
    sampleLine(s.pick, 0, L["Example quest"], where, L["Find group"], 96)
    sampleLine(s.pick, -38, L["Another quest"], where, L["Find group"], 96)

    -- página 2: uma missão escolhida
    s.quest = CF("Frame", nil, s)
    s.quest:SetAllPoints()
    local back = fakeButton(s.quest, L["< Your quests"], 120)
    back:SetPoint("TOPLEFT", 4, -4)
    local qt = s.quest:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    qt:SetPoint("TOPLEFT", 6, -34)
    qt:SetText(L["Example quest"])
    local qm = s.quest:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    qm:SetPoint("TOPLEFT", qt, "BOTTOMLEFT", 0, -4)
    qm:SetText(where)
    s.create = CF("Frame", nil, s.quest)
    s.create:SetPoint("TOPLEFT", 4, -76)
    s.create:SetPoint("RIGHT", -4, 0)
    s.create:SetHeight(26)
    local cb = fakeButton(s.create, L["Create group"], 130)
    cb:SetHeight(24)
    cb:SetPoint("LEFT", 0, 0)
    local cs = s.create:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cs:SetPoint("LEFT", cb, "RIGHT", 8, 0)
    cs:SetPoint("RIGHT", 0, 0)
    cs:SetJustifyH("LEFT")
    cs:SetWordWrap(false)
    cs:SetText(L["No group? List yours: players who click the magnifier on this quest find you."])
    s.req = sampleLine(s.quest, -110, L["Example player"] .. "  |cffaaaaaa" .. format(L["Lvl %d"], 18) .. "|r", "|cff55ff55" .. L["Example quest"] .. "|r", L["Invite"], 70)
    s.row = sampleLine(s.quest, -150, L["Example group"] .. "  |cffaaaaaa" .. format(L["Lvl %d"], 18) .. "|r", "|cff55ff55" .. L["Example quest"] .. "|r  3/5", L["Join"], 80)
    s:Hide()
    return s
end

local function buildQuestBanner(qp, level)
    local b = box(qp, 0.97)
    b:SetFrameLevel(level)
    b:SetPoint("TOPLEFT", qp, "TOPLEFT", 8, -26)
    b:SetPoint("TOPRIGHT", qp, "TOPRIGHT", -8, -26)
    b:SetHeight(50)
    b:EnableMouse(true)
    local t = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    t:SetJustifyH("LEFT")
    t:SetText(L["New: the Quests tab. Take a 20-second tour."])
    local no = button(b, L["No thanks"], 90)
    no:SetPoint("RIGHT", -10, 0)
    no:SetScript("OnClick", function()
        markDone("quests", "recusado na faixa")
        b:Hide()
        NS.Print(L["You can see the tour any time with /gf tour."])
    end)
    local go = button(b, L["Start tour"], 100)
    go:SetPoint("RIGHT", no, "LEFT", -6, 0)
    go:SetScript("OnClick", function() NS.StartTour("quests") end)
    t:SetPoint("LEFT", 12, 0)
    t:SetPoint("RIGHT", go, "LEFT", -8, 0)
    b:Hide()
    return b
end

-- a aba Missões é construída depois da janela: monta a faixa e o exemplo quando ela existir
local function buildQuest()
    if qsample then return true end
    if not build() then return false end
    local qp = NS.QuestPanel and NS.QuestPanel()
    if not qp then return false end
    local base = (panel:GetFrameLevel() or 1) + 20
    qbanner = buildQuestBanner(qp, base)
    qsample = buildQuestSample(qp, base + 2)
    return true
end

function build()
    if callout then return true end
    panel = _G.GrupoFacilFrame
    if not panel then return false end
    local base = (panel:GetFrameLevel() or 1) + 20

    -- faixa de convite (cobre o topo da lista enquanto está à mostra)
    banner = box(panel.dungeonPanel or panel, 0.97) -- só na aba Masmorras
    banner:SetFrameLevel(base)
    local list = NS.UIRefs and NS.UIRefs.list or panel
    banner:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    banner:SetHeight(50)
    banner:EnableMouse(true)
    local bt = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bt:SetJustifyH("LEFT")
    bt:SetText(L["New to GrupoFacil? Take a 30-second tour."])
    local no = button(banner, L["No thanks"], 90)
    no:SetPoint("RIGHT", -10, 0)
    no:SetScript("OnClick", function()
        markDone("dungeons", "recusado na faixa")
        banner:Hide()
        NS.Print(L["You can see the tour any time with /gf tour."])
    end)
    local go = button(banner, L["Start tour"], 100)
    go:SetPoint("RIGHT", no, "LEFT", -6, 0)
    go:SetScript("OnClick", function() NS.StartTour("dungeons") end)
    bt:SetPoint("LEFT", 12, 0)
    bt:SetPoint("RIGHT", go, "LEFT", -8, 0)
    banner:Hide()

    highlight = box(panel, 0)
    highlight:SetFrameLevel(base + 1)
    highlight:Hide()

    sample = buildSampleRow(panel, base + 2)

    callout = box(panel, 0.97)
    callout:SetFrameLevel(base + 5)
    callout:SetWidth(CALLOUT_W)
    callout:EnableMouse(true)
    callout.title = callout:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    callout.title:SetPoint("TOPLEFT", 14, -12)
    callout.title:SetPoint("TOPRIGHT", -14, -12)
    callout.title:SetJustifyH("LEFT")
    callout.body = callout:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    callout.body:SetPoint("TOPLEFT", callout.title, "BOTTOMLEFT", 0, -6)
    callout.body:SetWidth(CALLOUT_W - 28)
    callout.body:SetJustifyH("LEFT")
    callout.body:SetSpacing(2)
    callout.next = button(callout, L["Next"], 80)
    callout.next:SetPoint("BOTTOMRIGHT", -12, 10)
    callout.next:SetScript("OnClick", function() NS.TourGo(step + 1) end)
    callout.back = button(callout, L["Back"], 70)
    callout.back:SetPoint("RIGHT", callout.next, "LEFT", -4, 0)
    callout.back:SetScript("OnClick", function() NS.TourGo(step - 1) end)
    callout.skip = button(callout, L["Skip tour"], 90)
    callout.skip:SetPoint("BOTTOMLEFT", 12, 10)
    callout.skip:SetScript("OnClick", function()
        NS.StopTour(true, "pulado")
        NS.Print(L["You can see the tour any time with /gf tour."])
    end)
    callout:Hide()
    return true
end

------------------------------------------------------------------------
-- tour
------------------------------------------------------------------------
local function ref(name)
    if name == "panel" then return panel end
    if name == "sample" then return sample end
    local q = name:match("^q:(.+)$")
    if q then
        if qsample and qsample[q] then return qsample[q] end
        return NS.QuestRefs and NS.QuestRefs[q] or panel
    end
    return NS.UIRefs and NS.UIRefs[name] or panel
end

local function place(s)
    highlight:ClearAllPoints()
    callout:ClearAllPoints()
    local f, t = s.from, s.to
    highlight:SetPoint("TOPLEFT", ref(f[1]), f[2], f[3], f[4])
    highlight:SetPoint("BOTTOMRIGHT", ref(t[1]), t[2], t[3], t[4])
    if s.below then
        callout:SetPoint("TOP" .. s.below, highlight, "BOTTOM" .. s.below, 0, -4)
    else
        callout:SetPoint("BOTTOM" .. s.above, highlight, "TOP" .. s.above, 0, 4)
    end
end

function NS.TourGo(i)
    if not build() then return end
    if i < 1 then i = 1 end
    local steps = TOURS[tourKey]
    if i > #steps then
        NS.StopTour(true, "concluído")
        NS.Print(L["Tour finished. /gf tour shows it again."])
        return
    end
    step = i
    local s = steps[i]
    banner:Hide()
    if qbanner then qbanner:Hide() end
    sample:SetShown(s.sampleRow == true)
    if qsample then
        qsample:SetShown(s.sample ~= nil)
        qsample.pick:SetShown(s.sample == "pick")
        qsample.pickTitle:SetShown(s.sample == "pick")
        qsample.quest:SetShown(s.sample == "quest")
    end
    place(s)
    highlight:Show()
    callout.title:SetText(format("%d/%d  %s", i, #steps, L[s.title]))
    callout.body:SetText(s.body())
    callout.back:SetEnabled(i > 1)
    callout.next:SetText(i == #steps and L["Finish"] or L["Next"])
    local h = (callout.body:GetStringHeight() or 60) + 76
    callout:SetHeight(h)
    callout:Show()
    NS.D.Trace("TOUR", "%s passo %d", tourKey, i)
end

-- key: "dungeons" ou "quests"; sem key, o tour da aba aberta (/gf tour)
function NS.StartTour(key)
    if InCombatLockdown() then
        NS.Print(L["The tour is not available in combat."])
        return
    end
    if key ~= "dungeons" and key ~= "quests" then
        key = (NS.CurrentTab and NS.CurrentTab()) or "dungeons"
    end
    if step then NS.StopTour(false, "outro tour") end
    if not (_G.GrupoFacilFrame and _G.GrupoFacilFrame:IsShown()) then
        if NS.ShowPanel then NS.ShowPanel(false, key) end
    end
    tourKey = key
    if NS.SelectTab then NS.SelectTab(key) end
    if key == "quests" then
        if not buildQuest() then return end
    else
        -- o tour aponta para os filtros: no modo compacto eles aparecem só durante o tour
        if GrupoFacilDB.compact and NS.ApplyCompact then NS.forceFilters = true; NS.ApplyCompact() end
    end
    NS.TourGo(1)
end

-- done = true marca como visto (Concluir/Pular); false só interrompe (janela fechou, combate).
function NS.StopTour(done, why)
    local was = step ~= nil
    step = nil
    if callout then
        callout:Hide()
        highlight:Hide()
        sample:Hide()
    end
    if qsample then qsample:Hide() end
    if done then markDone(tourKey, why or "?")
    elseif was then NS.D.Trace("TOUR", "tour interrompido (%s)", why or "?") end
    -- volta ao modo compacto, se era a preferência
    if NS.forceFilters then
        NS.forceFilters = false
        if NS.ApplyCompact then NS.ApplyCompact() end
    end
end

function NS.TourRunning() return step ~= nil end
function NS.TourKey() return step and tourKey or nil end
function NS.TourFrames() return banner, callout, highlight, sample end -- para diagnóstico e teste
function NS.QuestTourFrames() buildQuest(); return qbanner, qsample end -- para teste

-- chamado pela janela do addon (UI.lua) ao abrir e ao trocar de aba
function NS.OnPanelShown()
    if not build() then return end
    if step then return end
    local combat = InCombatLockdown()
    banner:SetShown(not isDone("dungeons") and not combat)
    if NS.QuestPanel and NS.QuestPanel() and buildQuest() then
        qbanner:SetShown(not isDone("quests") and not combat)
    end
end

function NS.OnPanelHidden()
    if step then NS.StopTour(false, "janela fechada") end
end

------------------------------------------------------------------------
-- aviso no chat (uma vez por conta, alguns segundos depois de entrar no mundo)
------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:SetScript("OnEvent", NS.D.Wrap("tour.OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        if step then NS.StopTour(false, "combate") end
        if banner then banner:Hide() end
        if qbanner then qbanner:Hide() end
    elseif event == "PLAYER_ENTERING_WORLD" then
        ev:UnregisterEvent("PLAYER_ENTERING_WORLD")
        if tourDB().welcomed then return end
        C_Timer.After(7, NS.D.Wrap("tour.welcome", function()
            local t = tourDB()
            if t.welcomed then return end
            t.welcomed = true
            NS.Print(L["ready. Open Looking For Group or type /gf. New here? /gf tour shows a quick tour."])
        end))
    end
end))
