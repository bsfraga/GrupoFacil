-- GrupoFacil: primeiro uso. Um aviso no chat uma vez por conta, uma faixa na janela
-- oferecendo o tour e o tour em si (balões dentro da janela do addon, nunca nos frames da Blizzard).
-- O tour não começa sozinho: a janela abre junto com o LFG, quando o jogador já quer usar o LFG.

local ADDON, NS = ...
local L = NS.L
local format = string.format

local TOUR_VERSION = 1   -- subir quando o tour mudar o bastante para valer mostrar de novo
local CALLOUT_W = 300

local function tourDB()
    local db = GrupoFacilDB
    if not db then return {} end
    if type(db.tour) ~= "table" then db.tour = {} end
    return db.tour
end

local function isDone() return (tourDB().version or 0) >= TOUR_VERSION end
local function markDone(how)
    tourDB().version = TOUR_VERSION
    NS.D.Trace("TOUR", "tour encerrado (%s)", how)
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
-- passos: área destacada e posição do balão, em coordenadas da janela (440x600)
------------------------------------------------------------------------
local STEPS = {
    {   title = "Pick what to list",
        body = function() return L["Players lists people looking for a group: use it when you lead. Groups lists groups looking for players: use it when you are solo. All shows both."] end,
        top = { 8, -24, 278, -58 }, callout = -64 },
    {   title = "Filter the list",
        body = function() return L["Type a level range or click Near me. Click the class icons to pick classes (none = all). Role filters by tank, healer or DPS; in Groups mode it becomes Needs: groups missing that role."] end,
        top = { 8, -52, 432, -150 }, callout = -156 },
    {   title = "Act on a row",
        body = function()
            return format(L["Invite asks a solo player into your group. Ask to join whispers the group leader your message:\n|cffffffff%s|r\nWhisper opens the chat to write your own."], NS.BuildMessage())
        end,
        top = { 8, -188, 432, -234 }, callout = -240, sampleRow = true },
    {   title = "Refresh the list",
        body = function() return L["GrupoFacil reads your Looking For Group search. Search again repeats the last one. The game only allows it from your click and refuses searches that come too fast."] end,
        top = { 302, -156, 432, -186 }, callout = -192 },
    {   title = "Your message and settings",
        body = function() return L["The bottom line shows the message leaders receive. Options changes it ({level}, {spec}, {class}, {name}), the send mode, the language and the minimap button. /gf tour shows this tour again."] end,
        bottom = { 8, 8, 432, 64 }, callout = 70 },
}
NS.TOUR_STEPS = STEPS -- para teste

local panel, banner, callout, highlight, sample
local step -- passo atual (nil = tour parado)

------------------------------------------------------------------------
-- construção (preguiçosa: só quando a janela do addon aparece)
------------------------------------------------------------------------
local function buildSampleRow(parent, level)
    local r = CF("Frame", nil, parent)
    r:SetFrameLevel(level)
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -192)
    r:SetSize(420, 38)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.08, 0.09, 0.12, 1)
    local icon = r:CreateTexture(nil, "ARTWORK")
    icon:SetSize(26, 26)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_GroupNeedMore")
    local name = r:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, 2)
    name:SetText(L["Example group"] .. "  |cffaaaaaaLvl 30|r")
    local info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
    info:SetText("3/5  T1 H0 D2")
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

local function build()
    if callout then return true end
    panel = _G.GrupoFacilFrame
    if not panel then return false end
    local base = (panel:GetFrameLevel() or 1) + 20

    -- faixa de convite (cobre o topo da lista enquanto está à mostra)
    banner = box(panel, 0.97)
    banner:SetFrameLevel(base)
    banner:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -192)
    banner:SetSize(420, 46)
    banner:EnableMouse(true)
    local bt = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bt:SetPoint("LEFT", 12, 0)
    bt:SetWidth(196)
    bt:SetJustifyH("LEFT")
    bt:SetText(L["New to GrupoFacil? Take a 30-second tour."])
    local no = button(banner, L["No thanks"], 90)
    no:SetPoint("RIGHT", -10, 0)
    no:SetScript("OnClick", function()
        markDone("recusado na faixa")
        banner:Hide()
        NS.Print(L["You can see the tour any time with /gf tour."])
    end)
    local go = button(banner, L["Start tour"], 100)
    go:SetPoint("RIGHT", no, "LEFT", -6, 0)
    go:SetScript("OnClick", function() NS.StartTour() end)
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
local function place(s)
    highlight:ClearAllPoints()
    callout:ClearAllPoints()
    if s.top then
        local x1, y1, x2, y2 = unpack(s.top)
        highlight:SetPoint("TOPLEFT", panel, "TOPLEFT", x1, y1)
        highlight:SetPoint("BOTTOMRIGHT", panel, "TOPLEFT", x2, y2)
        callout:SetPoint("TOP", panel, "TOP", 0, s.callout)
    else
        local x1, y1, x2, y2 = unpack(s.bottom)
        highlight:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", x1, y1)
        highlight:SetPoint("TOPRIGHT", panel, "BOTTOMLEFT", x2, y2)
        callout:SetPoint("BOTTOM", panel, "BOTTOM", 0, s.callout)
    end
end

function NS.TourGo(i)
    if not build() then return end
    if i < 1 then i = 1 end
    if i > #STEPS then
        NS.StopTour(true, "concluído")
        NS.Print(L["Tour finished. /gf tour shows it again."])
        return
    end
    step = i
    local s = STEPS[i]
    banner:Hide()
    sample:SetShown(s.sampleRow == true)
    place(s)
    highlight:Show()
    callout.title:SetText(format("%d/%d  %s", i, #STEPS, L[s.title]))
    callout.body:SetText(s.body())
    callout.back:SetEnabled(i > 1)
    callout.next:SetText(i == #STEPS and L["Finish"] or L["Next"])
    local h = (callout.body:GetStringHeight() or 60) + 76
    callout:SetHeight(h)
    callout:Show()
    NS.D.Trace("TOUR", "passo %d", i)
end

function NS.StartTour()
    if InCombatLockdown() then
        NS.Print(L["The tour is not available in combat."])
        return
    end
    if not (_G.GrupoFacilFrame and _G.GrupoFacilFrame:IsShown()) then
        if NS.ShowPanel then NS.ShowPanel(false) end
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
    if done then markDone(why or "?")
    elseif was then NS.D.Trace("TOUR", "tour interrompido (%s)", why or "?") end
end

function NS.TourRunning() return step ~= nil end
function NS.TourFrames() return banner, callout, highlight, sample end -- para diagnóstico e teste

-- chamado pela janela do addon (UI.lua)
function NS.OnPanelShown()
    if not build() then return end
    if step then return end
    banner:SetShown(not isDone() and not InCombatLockdown())
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
