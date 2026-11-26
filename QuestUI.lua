-- GrupoFacil: a lupa ao lado da missão e a janela de grupos por missão.
-- A lupa aparece na lista de objetivos (abaixo do minimapa) e nos detalhes da missão do quest log.
-- Os botões são filhos dos quadros da Blizzard (somem junto com eles), mas nada é gravado neles:
-- a missão de cada botão fica numa tabela própria do addon.

local ADDON, NS = ...
local L = NS.L
local D = NS.D
local Trace = D.Trace
local Q = NS.Quest
local format, max, min, floor = string.format, math.max, math.min, math.floor

local ICON = "Interface\\Common\\UI-Searchbox-Icon"
local ROW_H = 34
local REQ_ROWS = 3

local scriptN = 0
local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    scriptN = scriptN + 1
    local tag = (name or ("quest" .. kind)) .. "#" .. scriptN
    local orig = f.SetScript
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then fn = D.Wrap(tag .. "." .. script, fn) end
        return orig(self, script, fn)
    end
    return f
end

local function tooltip(owner, title, line)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title(self) or title)
        local l = type(line) == "function" and line(self) or line
        if l and l ~= "" then GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if owner.SetMotionScriptsWhileDisabled then owner:SetMotionScriptsWhileDisabled(true) end
end

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetText(text or "")
    return fs
end

local function fitWidth(b, minW, texts)
    local fs = b.GetFontString and b:GetFontString()
    local w = minW
    if fs then
        local old = fs:GetText()
        for _, t in ipairs(texts) do fs:SetText(t); w = max(w, (fs:GetStringWidth() or 0) + 22) end
        fs:SetText(old)
    end
    b:SetWidth(w)
end

local function button(parent, text, w, h, more)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    fitWidth(b, w, more or { text })
    return b
end

local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function setClassIcon(tex, class)
    if class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        return
    end
    tex:SetTexCoord(0, 1, 0, 1)
    tex:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
end

local function className(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

------------------------------------------------------------------------
-- clique na lupa: uma busca (a única ação protegida do clique) e a janela
------------------------------------------------------------------------
function NS.QuestMagnifierClick(questID)
    if NS.ShowQuestWindow then NS.ShowQuestWindow(true) end
    if NS.QuestPick then NS.QuestPick(false) end
    local ok, why = Q.Search(questID)
    if not ok and why then
        Q.status = why
        NS.Print(format(L["not searched: %s."], why))
    else
        Q.status = nil
    end
    NS.RefreshQuest("magnifier")
end

local function magnifierTip(self)
    local q = self.questID and Q.Info(self.questID)
    return q and q.title or L["Find a group for this quest"]
end
local function magnifierLine()
    return L["Searches Looking For Group for groups in this quest's zone. Groups doing this quest come first. No group? Create one in the window that opens."]
end

local mine = setmetatable({}, { __mode = "k" }) -- botões do GrupoFacil (nunca contam como obstáculo)

local function newMagnifier(parent, size)
    local b = CF("Button", nil, parent)
    b:SetSize(size, size)
    b:SetNormalTexture(ICON)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 5)
    b:SetScript("OnClick", function(self) if self.questID then NS.QuestMagnifierClick(self.questID) end end)
    tooltip(b, function(self) return format(L["Find a group: %s"], magnifierTip(self)) end, magnifierLine)
    mine[b] = true
    return b
end

------------------------------------------------------------------------
-- não cobrir botões de outros addons (pedido do Fraga, 26/11: o "Play" do Spoken ficava por baixo)
-- Cada botão nosso tenta lugares em ordem e fica no primeiro onde não cobre nenhum botão ou quadro
-- pequeno de outro addon (nem da Blizzard). Só lemos posições; nada é mudado nos quadros dos outros.
------------------------------------------------------------------------
local function rectOf(f)
    if not (f and f.GetRect) then return nil end
    if f.IsForbidden and f:IsForbidden() then return nil end
    local ok, l, b, w, h = pcall(f.GetRect, f)
    if not ok or type(l) ~= "number" or NS.isSecret(l) or not w or w <= 0 or h <= 0 then return nil end
    return { l = l, r = l + w, b = b, t = b + h }
end

local function overlaps(a, b)
    return a and b and math.min(a.r, b.r) - math.max(a.l, b.l) > 1 and math.min(a.t, b.t) - math.max(a.b, b.b) > 1
end

local CLICKABLE = { Button = true, CheckButton = true, EditBox = true }
-- quadros que podem estar onde queremos pôr o botão: clicáveis ou pequenos com mouse, visíveis
local function collectObstacles(roots, depth)
    local out, seen = {}, {}
    local function walk(f, d)
        if not f or seen[f] or mine[f] then return end
        seen[f] = true
        local ok, kids = pcall(function() return { f:GetChildren() } end)
        if not ok then return end
        for _, ch in ipairs(kids) do
            -- quadros proibidos (seguros da Blizzard) não podem nem ser lidos por addon: pula
            -- (erro "calling 'IsVisible' on bad self" no teste do Fraga, 26/11)
            local forbidden = type(ch) ~= "table" or (ch.IsForbidden and ch:IsForbidden())
            if not forbidden and not mine[ch] then
                local okv, vis = pcall(ch.IsVisible, ch)
                if okv and vis then
                    local r = rectOf(ch)
                    local okk, kind = pcall(ch.GetObjectType, ch)
                    local okm, mouse = pcall(ch.IsMouseEnabled, ch)
                    local small = r and (r.r - r.l) <= 220 and (r.t - r.b) <= 60
                    if r and small and ((okk and CLICKABLE[kind]) or (okm and mouse)) then out[#out + 1] = { f = ch, r = r } end
                    if d < depth then walk(ch, d + 1) end
                end
            end
        end
    end
    -- raiz pode vir como { quadro, profundidade } (o UIParent só no primeiro nível: é grande)
    for _, root in ipairs(roots) do
        if type(root) == "table" and root[1] then
            local d0 = depth - (root[2] or depth) + 1
            walk(root[1], d0)
        else
            walk(root, 1)
        end
    end
    return out
end

-- place(btn) aplica um lugar; devolve o índice do primeiro lugar livre, ou nil se todos cobrem algo.
-- bounds (opcional): o botão precisa caber dentro desse quadro.
local function placeFree(btn, places, roots, depth, bounds)
    local obstacles = collectObstacles(roots, depth or 3)
    local box = bounds and rectOf(bounds)
    for i, place in ipairs(places) do
        btn:ClearAllPoints()
        place(btn)
        local r = rectOf(btn)
        local free = true
        if r and box and (r.l < box.l - 1 or r.r > box.r + 1 or r.b < box.b - 1 or r.t > box.t + 1) then free = false end
        if r and free then
            for _, o in ipairs(obstacles) do
                if o.f ~= btn and overlaps(r, o.r) then free = false break end
            end
        end
        if free then return i end
    end
    return nil
end
NS.QuestPlaceFree = placeFree

------------------------------------------------------------------------
-- lista de objetivos (QuestObjectiveTracker e o de campanhas, quando houver)
------------------------------------------------------------------------
local trackerButtons = setmetatable({}, { __mode = "k" }) -- [bloco da Blizzard] = botão
local hooked = {}
NS.QuestTrackerButtons = trackerButtons

local function shown() return Q.DB().magnifier ~= false end

local function decorateTracker(tracker)
    if not tracker or type(tracker.usedBlocks) ~= "table" then return end
    local used = {}
    local on = shown()
    for _, blocks in pairs(tracker.usedBlocks) do
        if type(blocks) == "table" then
            for id, block in pairs(blocks) do
                local questID = (type(block) == "table" and type(block.id) == "number" and block.id) or (type(id) == "number" and id) or nil
                if questID and questID > 0 and type(block) == "table" and block.GetObjectType then
                    used[block] = true
                    local b = trackerButtons[block]
                    if on then
                        if not b then b = newMagnifier(block, 14); trackerButtons[block] = b end
                        b.questID = questID
                        b.tracker = tracker
                        b:Show()
                        local edge = block.rightEdgeFrame
                        if not (edge and edge.IsShown and edge:IsShown()) then edge = nil end
                        -- ao lado do botão nativo (ou no canto do título); ocupado: mais à esquerda
                        local function at(dx)
                            return function(x)
                                if edge then x:SetPoint("RIGHT", edge, "LEFT", -2 - dx, 0)
                                else x:SetPoint("TOPRIGHT", block, "TOPRIGHT", -dx, 0) end
                            end
                        end
                        -- sem lugar livre: escondida, nunca por cima do botão de outro addon
                        if not placeFree(b, { at(0), at(18), at(36) }, { block }, 2) then b:Hide() end
                    elseif b then
                        b:Hide()
                    end
                end
            end
        end
    end
end

-- botões cujo bloco saiu da lista: escondidos na próxima passada de cada rastreador
local function hideUnused(tracker)
    if not tracker or type(tracker.usedBlocks) ~= "table" then return end
    local live = {}
    for _, blocks in pairs(tracker.usedBlocks) do
        if type(blocks) == "table" then for _, block in pairs(blocks) do live[block] = true end end
    end
    for block, b in pairs(trackerButtons) do
        if not live[block] and b.tracker == tracker then b:Hide() end
    end
end

local TRACKERS = { "QuestObjectiveTracker", "CampaignQuestObjectiveTracker" }

local function installTrackers()
    for _, name in ipairs(TRACKERS) do
        local t = rawget(_G, name)
        if not hooked[name] and type(t) == "table" and type(t.Update) == "function" then
            hooked[name] = true
            hooksecurefunc(t, "Update", D.Wrap("lupa:" .. name, function(self)
                decorateTracker(self)
                hideUnused(self)
            end))
            Trace("CARGA", "lupa na lista de objetivos: %s", name)
            decorateTracker(t)
        end
    end
end

function NS.RefreshMagnifiers()
    for _, name in ipairs(TRACKERS) do
        local t = rawget(_G, name)
        if hooked[name] and t then decorateTracker(t); hideUnused(t) end
    end
    if NS.UpdateDetailsMagnifier then NS.UpdateDetailsMagnifier() end
end

------------------------------------------------------------------------
-- detalhes da missão no quest log (mapa) e a janela solta de detalhes
------------------------------------------------------------------------
local details = {} -- [quadro da Blizzard] = botão
local detailsQuest = {} -- [quadro] = questID mostrado
NS.QuestDetailsButtons = details

local function detailsButton(frame, anchor)
    local b = details[frame]
    if b then return b end
    b = CF("Button", nil, frame, "UIPanelButtonTemplate")
    mine[b] = true
    b:SetHeight(22)
    b:SetText(L["Find group"])
    fitWidth(b, 96, { L["Find group"] })
    b:SetWidth(b:GetWidth() + 14)
    local icon = b:CreateTexture(nil, "OVERLAY")
    icon:SetTexture(ICON)
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", 6, 0)
    local base = anchor or frame
    b:SetFrameLevel((base.GetFrameLevel and base:GetFrameLevel() or 1) + 5)
    b.wide = b:GetWidth()
    b.icon = icon
    b:SetScript("OnClick", function(self) if self.questID then NS.QuestMagnifierClick(self.questID) end end)
    tooltip(b, function(self) return format(L["Find a group: %s"], magnifierTip(self)) end, magnifierLine)
    details[frame] = b
    return b
end

-- Lugares do botão nos detalhes, em ordem: ao lado do Voltar; deslizando pela faixa do Voltar até achar
-- um vão; no canto direito da faixa; no canto do quadro; os mesmos só com a lupa (sem texto). Outros
-- addons (ex.: o "Play" do Spoken) põem botões nessa faixa: o nosso desvia, e se não houver lugar livre
-- nenhum ele fica escondido (a lupa da lista de objetivos e /gf quests continuam), nunca por cima.
local function placeDetails(b, frame, anchor)
    if not b.want then return end
    b:Show()
    local back = anchor and anchor.BackButton
    local function wide(on)
        if on then b:SetWidth(b.wide); b:SetText(L["Find group"]); b.icon:ClearAllPoints(); b.icon:SetPoint("LEFT", 6, 0)
        else b:SetWidth(26); b:SetText(""); b.icon:ClearAllPoints(); b.icon:SetPoint("CENTER", 0, 0) end
    end
    local places = {}
    local function add(isWide, fn) places[#places + 1] = function(x) wide(isWide); fn(x) end end
    for _, isWide in ipairs({ true, false }) do
        if back then
            for dx = 6, 246, 12 do add(isWide, function(x) x:SetPoint("LEFT", back, "RIGHT", dx, 0) end) end
        end
        if anchor then add(isWide, function(x) x:SetPoint("RIGHT", anchor, "RIGHT", -8, 4) end) end
        add(isWide, function(x) x:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -6) end)
    end
    local roots = { frame }
    local parent = frame.GetParent and frame:GetParent()
    if parent then roots[#roots + 1] = parent end
    roots[#roots + 1] = { UIParent, 1 } -- botões de outros addons presos ao UIParent e ancorados aqui
    local i = placeFree(b, places, roots, 4, frame)
    if not i then b:Hide() end
    Trace("MISSAO", "botão Achar grupo: %s", i and format("lugar %d de %d", i, #places) or "sem lugar livre, escondido")
end

local function showDetails(frame, anchor, questID)
    if not frame then return end
    detailsQuest[frame] = questID
    local b = detailsButton(frame, anchor)
    b.questID = questID
    b.want = shown() and type(questID) == "number" and questID > 0
    b:SetShown(b.want)
    placeDetails(b, frame, anchor)
    -- outros addons podem pôr o botão deles depois do nosso: confere de novo
    C_Timer.After(0.2, function() if detailsQuest[frame] == questID then placeDetails(b, frame, anchor) end end)
    C_Timer.After(1, function() if detailsQuest[frame] == questID then placeDetails(b, frame, anchor) end end)
end

function NS.UpdateDetailsMagnifier()
    for frame, b in pairs(details) do
        local q = detailsQuest[frame]
        b.want = shown() and type(q) == "number" and q > 0
        b:SetShown(b.want)
        if b.want then placeDetails(b, frame, frame.BackFrame) end
    end
end

local function readQuestID(v)
    if type(v) == "number" and not NS.isSecret(v) then return v end
    return nil
end

local function installDetails()
    if not hooked.mapDetails and type(rawget(_G, "QuestMapFrame_ShowQuestDetails")) == "function" then
        hooked.mapDetails = true
        hooksecurefunc("QuestMapFrame_ShowQuestDetails", D.Wrap("lupa:detalhes", function(questID)
            local df = QuestMapFrame and QuestMapFrame.DetailsFrame
            if not df then return end
            local back = df.BackFrame
            showDetails(df, back, readQuestID(questID) or readQuestID(df.questID))
        end))
        Trace("CARGA", "lupa nos detalhes da missão (quest log)")
    end
    local popup = rawget(_G, "QuestLogPopupDetailFrame")
    if not hooked.popup and popup and popup.HookScript then
        hooked.popup = true
        popup:HookScript("OnShow", D.Wrap("lupa:popup", function(self)
            showDetails(self, nil, readQuestID(self.questID))
        end))
        Trace("CARGA", "lupa na janela solta de detalhes")
    end
end

local function install()
    installTrackers()
    installDetails()
end
NS.InstallMagnifiers = install

local loader = CF("Frame", nil, UIParent)
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function() install() end)

------------------------------------------------------------------------
-- janela de grupos por missão
------------------------------------------------------------------------
local win, rows, reqRows = nil, {}, {}

local WHY = {
    listed = function() return "|cff55ff55" .. L["doing this quest"] .. "|r" end,
    gf = function() return "|cff55ff55" .. L["doing this quest"] .. "|r" end,
    has = function() return "|cffffd200" .. L["has this quest"] .. "|r" end,
}

local function membersText(e)
    if e.solo then return L["looking for a group"] end
    local s = e.maxPlayers and format("%d/%d", e.numMembers, e.maxPlayers) or format(L["%d members"], e.numMembers)
    if e.counts and NS.RoleIcon then
        s = s .. format("  %s%d %s%d %s%d", NS.RoleIcon("tank"), e.counts.tank, NS.RoleIcon("healer"), e.counts.healer,
            NS.RoleIcon("dps"), e.counts.dps)
    end
    return s
end

-- Convidar ou pedir vaga? Sozinho com o GrupoFacil e você sem grupo: pedir (ele convida, e o
-- convite é aceito sozinho). Sozinho sem o addon, ou você já num grupo: convidar.
local function invites(e)
    return e.solo and (IsInGroup() or not e.qPeer)
end

local function makeRow(parent, i)
    local r = CF("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(24, 24)
    r.icon:SetPoint("LEFT", 6, 0)
    r.name = label(r, "", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 1)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = label(r, "", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)
    r.b1 = button(r, L["Join"], 80, 20, { L["Join"], L["Invite"], L["Sent"] })
    r.b1:SetPoint("RIGHT", -4, 0)
    -- borda direita pela quina de cima (RIGHT junto com TOPLEFT deixa a altura ambígua)
    r.name:SetPoint("TOPRIGHT", r.b1, "TOPLEFT", -6, 3)
    r.info:SetPoint("TOPRIGHT", r.name, "BOTTOMRIGHT", 0, -3)
    r.b1:SetScript("OnClick", function()
        local e = r.entry
        if not e then return end
        if invites(e) then Q.Invite(e) else Q.Join(e) end
        NS.RefreshQuest("click")
    end)
    tooltip(r.b1, function()
        local e = r.entry
        if e and invites(e) then return L["Invite to group"] end
        return L["Ask the leader to join"]
    end, function()
        local e = r.entry
        if not e then return "" end
        if invites(e) then
            return NS.CanInvite(e) and "" or L["You can only invite when you are solo or the leader/assistant."]
        end
        local ok, why = Q.CanJoin(e)
        if not ok then return L["Unavailable: "] .. why end
        if e.qPeer then return L["The leader uses GrupoFacil: the request goes silently and the leader decides (or the addon invites you)."] end
        return L["Sends: "] .. Q.BuildMessage(Q.current and Q.current.info and Q.current.info.title)
    end)
    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(e.name or RETRIEVING_DATA or "...", classColor(e.class))
        if e.activity and e.activity ~= "" then GameTooltip:AddLine(e.activity, 0.8, 0.8, 0.8, true) end
        GameTooltip:AddLine(membersText(e), 0.8, 0.8, 0.8)
        local why = e.qWhy and WHY[e.qWhy]
        if why then GameTooltip:AddLine(why(), 1, 1, 1) else GameTooltip:AddLine(L["same zone (quest not confirmed)"], 0.7, 0.7, 0.7) end
        if e.qPeer then GameTooltip:AddLine(L["uses GrupoFacil"], 0.5, 0.8, 1) end
        local info = e.qPeer and e.qPeer.info
        if info then
            GameTooltip:AddLine(" ")
            if info.title then GameTooltip:AddLine(format(L["Quest: %s"], info.title), 1, 0.82, 0, true) end
            if info.objective then GameTooltip:AddLine(L["Objective: "] .. info.objective, 1, 1, 1, true) end
            if info.zone then GameTooltip:AddLine(format(L["Where: %s"], info.zone), 0.8, 0.8, 0.8, true) end
        end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    return r
end

local function makeReqRow(parent, i)
    local r = CF("Frame", nil, parent)
    r:SetHeight(24)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * 26)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * 26)
    r.text = label(r, "", "GameFontHighlightSmall")
    r.text:SetPoint("LEFT", 6, 0)
    r.text:SetJustifyH("LEFT")
    r.text:SetWordWrap(false)
    r.no = button(r, L["Ignore"], 70, 20)
    r.no:SetPoint("RIGHT", -4, 0)
    r.yes = button(r, L["Invite"], 70, 20)
    r.yes:SetPoint("RIGHT", r.no, "LEFT", -3, 0)
    r.yes:SetScript("OnClick", function() if r.req then Q.InviteRequest(r.req) end end)
    r.no:SetScript("OnClick", function() if r.req then Q.DismissRequest(r.req) end end)
    tooltip(r.yes, L["Invite to group"], L["Invites this player, who asked through GrupoFacil."])
    tooltip(r.no, L["Ignore"], L["Removes the request. The player is not told."])
    r:Hide()
    return r
end

-- A aba Missões da janela do GrupoFacil (pedido do Fraga, 26/11: uma janela só, com abas). É um
-- quadro do tamanho da janela principal; NS.SelectTab mostra uma aba e esconde a outra.
function NS.QuestPanel() return win end

function NS.BuildQuestUI()
    if win then return end
    if not GrupoFacilFrame and NS.BuildUI then NS.BuildUI() end
    local main = GrupoFacilFrame
    if not main then return end
    win = CF("Frame", "GrupoFacilQuestFrame", main)
    win:SetAllPoints(main)
    win:Hide()
    win:SetScript("OnSizeChanged", function() NS.RefreshQuest("size") end)

    -- Layout (rodada 3 do Fraga, 26/11: "interface de missões não é intuitiva"), de cima para baixo:
    --  1. barra: "< Suas missões" (volta à lista) e "Buscar de novo"
    --  2. a missão escolhida: nome, zona/level/elite, objetivo
    --  3. a ação principal: Criar grupo / Tirar listagem, com o estado do seu grupo ao lado
    --  4. pedidos de vaga (quando há)
    --  5. grupos e jogadores da zona (ou, sem missão escolhida, a lista das suas missões)
    --  6. rodapé: contagem, páginas e "Opções" (as três opções ficam recolhidas)
    win.back = button(win, L["< Your quests"], 120, 22)
    win.back:SetPoint("TOPLEFT", 12, -30)
    win.back:SetScript("OnClick", function() NS.QuestPick(true); NS.RenderQuest() end)
    tooltip(win.back, L["Your quests"], L["Back to the list of the quests in your log."])
    win.search = button(win, L["Search again"], 110)
    -- "i": por que a aba depende de mais gente com o addon (pedido do Fraga, 26/11)
    win.info = CF("Button", nil, win)
    win.info:SetSize(20, 20)
    win.info:SetPoint("TOPRIGHT", -12, -31)
    win.info:SetNormalTexture("Interface\\FriendsFrame\\InformationIcon")
    win.info:SetHighlightTexture("Interface\\FriendsFrame\\InformationIcon", "ADD")
    win.info:SetScript("OnClick", function() if NS.OpenOptions then NS.OpenOptions("invite") end end)
    tooltip(win.info, L["How quest groups work"], L["GrupoFacil searches Looking For Group and also talks quietly with other players who have the addon, to learn which quest each group is doing. That only works between players who use GrupoFacil: the more people have it, the more groups it finds for your quest. Click to invite a friend."])
    win.search:SetPoint("RIGHT", win.info, "LEFT", -6, 0)
    win.search:SetScript("OnClick", function()
        local ok, why = Q.SearchAgain()
        Q.status = (not ok) and why or nil
        NS.RefreshQuest("search")
    end)
    tooltip(win.search, L["Search again"], L["Searches again for the same quest."])

    -- 2. a missão
    win.quest = label(win, "", "GameFontNormalLarge")
    win.quest:SetPoint("TOPLEFT", 14, -60)
    win.quest:SetPoint("TOPRIGHT", win, "TOPRIGHT", -14, -60)
    win.quest:SetJustifyH("LEFT")
    win.quest:SetWordWrap(false)
    win.meta = label(win, "", "GameFontHighlightSmall")
    win.meta:SetPoint("TOPLEFT", win.quest, "BOTTOMLEFT", 0, -4)
    win.meta:SetPoint("TOPRIGHT", win.quest, "BOTTOMRIGHT", 0, -4)
    win.meta:SetJustifyH("LEFT")
    win.meta:SetWordWrap(false)
    -- objetivo da missão (o Looking For Group não aceita descrição: a informação fica aqui)
    win.obj = label(win, "", "GameFontHighlightSmall")
    win.obj:SetPoint("TOPLEFT", win.meta, "BOTTOMLEFT", 0, -4)
    win.obj:SetPoint("TOPRIGHT", win.meta, "BOTTOMRIGHT", 0, -4)
    win.obj:SetJustifyH("LEFT")
    win.obj:SetWordWrap(false)
    win.obj:SetTextColor(0.85, 0.85, 0.85)

    -- 3. ação principal e o estado do seu grupo
    win.create = button(win, L["Create group"], 130, 24, { L["Create group"], L["Remove listing"] })
    win.create:SetPoint("TOPLEFT", 12, -114)
    win.create:SetScript("OnClick", function()
        if Q.QuestListing() then Q.RemoveListing() else Q.Create() end
        NS.RefreshQuest("create")
    end)
    tooltip(win.create, function() return Q.QuestListing() and L["Remove listing"] or L["Create group"] end, function()
        if Q.QuestListing() then return L["Takes your group out of Looking For Group."] end
        local ok, why = Q.CanCreate()
        if not ok then return L["Unavailable: "] .. why end
        local act = Q.current and Q.current.activity
        return format(L["Lists you in Looking For Group (%s) with this quest. Players who click the magnifier on the same quest find you first."],
            act and (act.label or act.name) or "?")
    end)
    win.group = label(win, "", "GameFontHighlightSmall")
    win.group:SetPoint("TOPLEFT", win.create, "TOPRIGHT", 10, 0)
    win.group:SetPoint("TOPRIGHT", win, "TOPRIGHT", -14, -114)
    win.group:SetJustifyH("LEFT")
    win.group:SetWordWrap(true)
    win.group:SetHeight(24)

    -- 4. pedidos recebidos (você lidera)
    win.reqTitle = label(win, L["Asked to join your group"], "GameFontNormal")
    win.reqTitle:SetJustifyH("LEFT")
    win.reqBox = CF("Frame", nil, win)
    win.reqBox:SetHeight(REQ_ROWS * 26)
    for i = 1, REQ_ROWS do reqRows[i] = makeReqRow(win.reqBox, i) end

    -- 5. resultados (ou a lista das suas missões)
    win.listTitle = label(win, "", "GameFontNormal")
    win.listTitle:SetJustifyH("LEFT")
    win.listTitle:SetWordWrap(false)
    win.list = CF("Frame", nil, win)
    win.list:EnableMouseWheel(true)
    win.offset = 0
    win.list:SetScript("OnMouseWheel", function(_, delta)
        win.offset = max(0, win.offset - delta * 2)
        NS.RenderQuest()
    end)
    win.empty = label(win.list, "", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 6, -8)
    win.empty:SetPoint("TOPRIGHT", win.list, "TOPRIGHT", -6, -8)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetJustifyV("TOP")
    win.empty:SetHeight(60)

    -- 6. rodapé
    win.status = label(win, "", "GameFontNormalSmall")
    win.status:SetPoint("BOTTOMLEFT", 14, 44)
    win.status:SetJustifyH("LEFT")
    win.status:SetWordWrap(false)
    win.pageFS = label(win, "", "GameFontDisableSmall")
    win.pageFS:SetPoint("BOTTOMRIGHT", -16, 44)
    win.pageFS:SetJustifyH("RIGHT")
    win.status:SetPoint("BOTTOMRIGHT", win.pageFS, "BOTTOMLEFT", -8, 0)
    -- quanto mais gente com o addon, mais grupos por missão se acham: indicar fica à mão aqui
    win.share = button(win, L["Recommend to a friend"], 150, 22)
    win.share:SetPoint("BOTTOMRIGHT", -24, 12)
    win.share:SetScript("OnClick", function() if NS.OpenOptions then NS.OpenOptions("invite") end end)
    tooltip(win.share, L["Recommend to a friend"], L["Quest groups work better the more players use GrupoFacil. Opens Invite a friend in the options: pick a friend or a channel, and the ready message goes to your chat box."])
    win.warn = label(win, "", "GameFontNormalSmall")
    win.warn:SetPoint("BOTTOMLEFT", 14, 18)
    win.warn:SetPoint("BOTTOMRIGHT", win.share, "BOTTOMLEFT", -8, 6)
    win.warn:SetJustifyH("LEFT")
    win.warn:SetWordWrap(false)
    win.warn:SetTextColor(1, 0.53, 0)

    win:SetScript("OnShow", function() NS.RenderQuest() end)
    NS.QuestRefs = { back = win.back, search = win.search, quest = win.quest, obj = win.obj, create = win.create,
        group = win.group, list = win.list, listTitle = win.listTitle, share = win.share, info = win.info, panel = win }
    Trace("CARGA", "janela de missões criada")
end

-- Lista das suas missões (sem missão escolhida, ou depois de "< Suas missões")
local pickRows = {}
local function makePickRow(parent, i)
    local r = CF("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(18, 18)
    r.icon:SetPoint("LEFT", 8, 0)
    r.icon:SetTexture(ICON)
    r.name = label(r, "", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 10, 4)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.info = label(r, "", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)
    r.go = button(r, L["Find group"], 96, 20)
    r.go:SetPoint("RIGHT", -4, 0)
    r.name:SetPoint("TOPRIGHT", r.go, "TOPLEFT", -6, 3)
    r.info:SetPoint("TOPRIGHT", r.name, "BOTTOMRIGHT", 0, -3)
    -- clique do jogador: a busca (ação protegida) pode sair daqui
    local function go() if r.questID then NS.QuestMagnifierClick(r.questID) end end
    r.go:SetScript("OnClick", go)
    r:SetScript("OnClick", go)
    tooltip(r.go, L["Find group"], magnifierLine)
    r:Hide()
    return r
end

-- picking: true mostra a lista das suas missões; false, a missão escolhida
function NS.QuestPick(on)
    if win then win.picking = on and true or false; win.offset = 0 end
end

local function layoutList(nReq, top0)
    local top = top0
    win.reqTitle:ClearAllPoints()
    win.reqTitle:SetPoint("TOPLEFT", 14, -top)
    win.reqTitle:SetShown(nReq > 0)
    win.reqBox:ClearAllPoints()
    win.reqBox:SetPoint("TOPLEFT", 10, -(top + 18))
    win.reqBox:SetPoint("TOPRIGHT", -10, -(top + 18))
    if nReq > 0 then top = top + 18 + nReq * 26 + 8 end
    win.listTitle:ClearAllPoints()
    win.listTitle:SetPoint("TOPLEFT", 14, -top)
    win.listTitle:SetPoint("TOPRIGHT", -14, -top)
    top = top + 18
    win.list:ClearAllPoints()
    win.list:SetPoint("TOPLEFT", 10, -top)
    win.list:SetPoint("BOTTOMRIGHT", -10, 62)
    local h = (win:GetHeight() or 540) - top - 62
    return max(2, floor(h / ROW_H))
end

local function questMeta(q, cur)
    local meta = {}
    if q.zone then meta[#meta + 1] = q.zone end
    if q.level then meta[#meta + 1] = format(L["Lvl %d"], q.level) end
    if q.elite then meta[#meta + 1] = "|cffff8000" .. L["Elite"] .. "|r" end
    if q.size then meta[#meta + 1] = format(L["Group: %d"], q.size) end
    if q.complete then meta[#meta + 1] = "|cff55ff55" .. L["complete"] .. "|r" end
    if cur and cur.activity then
        meta[#meta + 1] = "|cff999999" .. format(L["Looking For Group: %s"], cur.activity.label or cur.activity.name or "?") .. "|r"
    end
    return table.concat(meta, "  ·  ")
end

-- estado do seu grupo, ao lado do Criar grupo
local function groupLine(cur)
    if Q.pendingCreate then return "|cffaaaaaa" .. L["Listing your group..."] .. "|r" end
    local qg = Q.QuestGroup()
    if qg and Q.HasListing() then
        local q = Q.Info(qg)
        return "|cff55ff55" .. format(L["Your group is listed for %s."], (q and q.title) or L["this quest"]) .. "|r"
    end
    if qg then
        local q = Q.Info(qg)
        return format(L["In a group for %s."], (q and q.title) or L["this quest"])
    end
    -- listado para masmorra, ou num grupo que outro líder listou: não é grupo de missão
    if Q.HasListing() then return "|cff999999" .. L["Your group is listed in Looking For Group for something else, not for a quest."] .. "|r" end
    local ok, why = Q.CanCreate()
    if not ok then return "|cff999999" .. why .. "|r" end
    return L["No group? List yours: players who click the magnifier on this quest find you."]
end

local function renderPicker(n)
    for _, r in ipairs(rows) do r:Hide() end
    local quests = Q.LogQuests()
    local total = #quests
    win.offset = max(0, min(win.offset, max(0, total - n)))
    for i = 1, n do if not pickRows[i] then pickRows[i] = makePickRow(win.list, i) end end
    for i = n + 1, #pickRows do pickRows[i]:Hide() end
    for i = 1, n do
        local r, q = pickRows[i], quests[win.offset + i]
        r.questID = q and q.id
        if q then
            r.name:SetText(q.title or "")
            r.info:SetText(questMeta(q))
            r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
            r.go:SetEnabled(not NS.InLockdown())
            r:Show()
        else
            r:Hide()
        end
    end
    -- o título de cima já diz "Suas missões": com a contagem ali, a lista não repete o título
    win.quest:SetText(format(L["Your quests (%d)"], total))
    win.listTitle:SetText("")
    if total == 0 then
        win.empty:SetText(L["Your quest log is empty. Pick up a quest and come back, or click the magnifier next to a quest."])
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.pageFS:SetText(total > n and format(L["%d-%d of %d"], win.offset + 1, min(total, win.offset + n), total) or "")
    win.status:SetText(L["Pick a quest: GrupoFacil searches its zone in Looking For Group."])
end

function NS.RenderQuest()
    if not win or not win:IsShown() then return end

    local cur = Q.current
    if not cur then win.picking = true end
    local picking = win.picking
    win.back:SetShown(not picking)
    win.search:SetShown(not picking)
    win.create:SetShown(not picking)
    win.group:SetShown(not picking)
    win.obj:SetShown(not picking)
    if picking then
        win.quest:SetText(L["Your quests"])
        win.meta:SetText(L["Click Find group on a quest, or the magnifier next to it in the objective list or the quest log."])
    else
        local q = Q.Info(cur.questID) or cur.info
        cur.info = q
        win.quest:SetText(q.title or "")
        win.meta:SetText(questMeta(q, cur))
        local obj = Q.Objective(cur.questID)
        win.obj:SetText(obj and (L["Objective: "] .. obj) or "")
        win.group:SetText(groupLine(cur))
    end

    -- pedidos recebidos (nos dois modos: quem lidera precisa ver)
    local reqs = Q.Requests()
    NS.UpdateQuestTab()
    local nReq = min(REQ_ROWS, #reqs)
    for i = 1, REQ_ROWS do
        local r, req = reqRows[i], reqs[i]
        r.req = req
        if req then
            local qi = Q.Info(req.questID)
            local who = Q.Display(req.name) .. (req.level and ("  |cffaaaaaa" .. format(L["Lvl %d"], req.level) .. "|r") or "")
            if req.class then who = who .. " " .. (className(req.class) or "") end
            local what = (qi and qi.inLog and qi.title) or req.title or tostring(req.questID)
            r.text:SetText(who .. "  ·  " .. (req.same and ("|cff55ff55" .. what .. "|r") or what))
            r.text:SetPoint("RIGHT", r.yes, "LEFT", -6, 0)
            r:Show()
        else
            r:Hide()
        end
    end
    local n = layoutList(nReq, picking and 96 or 150)
    win.warn:SetText(Q.JoinWarning() or "")

    if picking then
        renderPicker(n)
        return
    end
    for _, r in ipairs(pickRows) do r:Hide() end
    for i = 1, n do if not rows[i] then rows[i] = makeRow(win.list, i) end end
    for i = n + 1, #rows do rows[i]:Hide() end

    local list = Q.Results()
    local total = #list
    local zone = (cur.activity and (cur.activity.label or cur.activity.name)) or (cur.info and cur.info.zone) or "?"
    win.listTitle:SetText(format(L["Groups and players in %s"], zone))
    win.offset = max(0, min(win.offset, max(0, total - n)))
    for i = 1, n do
        local r, e = rows[i], list[win.offset + i]
        r.entry = e
        if not e then
            r:Hide()
        else
            r:Show()
            setClassIcon(r.icon, e.class)
            r.icon:SetDesaturated(not e.solo)
            local lvl = e.level and ("  |cffaaaaaa" .. format(L["Lvl %d"], e.level) .. "|r") or ""
            r.name:SetText((e.name or RETRIEVING_DATA or "...") .. lvl)
            r.name:SetTextColor(classColor(e.class))
            local why = e.qWhy and WHY[e.qWhy]
            local first = why and why() or ("|cff999999" .. L["same zone"] .. "|r")
            -- líder com o GrupoFacil, listado para outra missão: mostra qual (veio pelo I1)
            local info = e.qPeer and e.qPeer.info
            if info and info.title and e.qScore ~= 3 then first = "|cffffd200" .. format(L["Quest: %s"], info.title) .. "|r" end
            local parts = { first, membersText(e) }
            r.info:SetText(table.concat(parts, "  ·  "))
            if e.qScore == 3 then r.bg:SetColorTexture(0.33, 1, 0.33, 0.08)
            elseif e.qScore == 2 then r.bg:SetColorTexture(1, 0.82, 0, 0.06)
            else r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0) end
            if invites(e) then
                r.b1:SetText(L["Invite"])
                r.b1:SetEnabled(NS.CanInvite(e) and not NS.InLockdown())
            else
                local asked = e.key and Q.asked[e.key]
                r.b1:SetText(asked and L["Sent"] or L["Join"])
                r.b1:SetEnabled((Q.CanJoin(e)))
            end
        end
    end
    if total == 0 then
        win.empty:SetText(NS.searching and L["Searching..."]
            or L["No group for this quest yet. Create one: players who click the magnifier on the same quest find you."])
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.pageFS:SetText(total > n and format(L["%d-%d of %d"], win.offset + 1, min(total, win.offset + n), total) or "")

    local status
    if Q.status then status = "|cffff8800" .. Q.status .. "|r"
    elseif NS.searching then status = L["Searching..."]
    else
        local doing, peers = 0, 0
        for _, e in ipairs(list) do
            if e.qScore == 3 then doing = doing + 1 end
            if e.qPeer then peers = peers + 1 end
        end
        -- singular e plural separados ("1 grupos na zona" lia errado)
        local function n(count, one, many) return count == 1 and L[one] or format(L[many], count) end
        status = n(total, "1 group in the zone", "%d groups in the zone") .. ", "
            .. n(doing, "1 doing this quest.", "%d doing this quest.") .. " "
            .. n(peers, "1 uses GrupoFacil.", "%d use GrupoFacil.")
    end
    -- o aviso da demonstração vai na linha de baixo (a do aviso laranja), que quase sempre está
    -- vazia: na mesma linha da contagem, o rodapé passava da largura e cortava
    local demo = Q.demo and ("|cff66ccff" .. L["Demo: fake players, nothing is sent."] .. "|r") or nil
    local warn = Q.JoinWarning()
    if demo and not warn then win.warn:SetText(demo)
    elseif demo then status = demo .. "  " .. status end
    win.status:SetText(status)

    win.search:SetEnabled(GetTime() >= NS.searchReadyAt and not NS.searching and not NS.InLockdown())
    local has = Q.QuestListing()
    win.create:SetText(has and L["Remove listing"] or L["Create group"])
    -- esperando o jogo responder à criação: um clique por vez (no teste, 9 cliques seguidos)
    win.create:SetEnabled(not Q.pendingCreate and (has or (Q.CanCreate())))
end

local queued = false
function NS.RefreshQuest(reason)
    if queued then return end
    queued = true
    C_Timer.After(0.1, function()
        queued = false
        NS.GuardTag("RenderQuest", NS.RenderQuest)
        NS.GuardTag("RenderQuestDone", NS.RenderQuestDone)
    end)
end

-- byClick: aberta pela lupa ou pelo botão (true); aberta por um pedido que chegou (false)
-- byClick: aberta pela lupa, pela aba ou por /gf quests (true); por um pedido que chegou (false).
-- Pedido que chega com a janela aberta noutra aba não troca de aba: a aba Missões mostra a contagem.
function NS.ShowQuestWindow(byClick)
    if not win then NS.BuildQuestUI() end
    if not win then return end
    local main = GrupoFacilFrame
    if not byClick and main:IsShown() then
        NS.UpdateQuestTab()
        NS.RefreshQuest("show")
        return
    end
    NS.ShowPanel(false, "quests")
    NS.RefreshQuest("show")
end

function NS.ToggleQuestWindow()
    if not win then NS.BuildQuestUI() end
    if not win then return end
    if win:IsVisible() then GrupoFacilFrame:Hide() else NS.ShowQuestWindow(true) end
end

-- texto da aba: "Missões (2)" quando há pedidos de vaga esperando
function NS.UpdateQuestTab()
    local main = GrupoFacilFrame
    local t = main and main.tabQuests
    if not t then return end
    local n = #Q.Requests()
    t:SetText(n > 0 and format(L["Quests (%d)"], n) or L["Quests"])
end

------------------------------------------------------------------------
-- missão concluída: oferecer sair do grupo e tirar a listagem
------------------------------------------------------------------------
local done

local function buildDone()
    done = CF("Frame", "GrupoFacilQuestDone", UIParent, "BasicFrameTemplateWithInset")
    done:SetSize(380, 130)
    done:SetPoint("TOP", UIParent, "TOP", 0, -180)
    done:SetFrameStrata("DIALOG")
    NS.Toplevel(done)
    done:SetClampedToScreen(true)
    done:SetMovable(true)
    done:EnableMouse(true)
    done:RegisterForDrag("LeftButton")
    done:SetScript("OnDragStart", done.StartMoving)
    done:SetScript("OnDragStop", done.StopMovingOrSizing)
    done:Hide()
    local title = done.TitleText or label(done, "", "GameFontHighlight")
    title:SetText(L["Quest complete"])
    done.text = label(done, "", "GameFontHighlight")
    done.text:SetPoint("TOPLEFT", 14, -32)
    done.text:SetPoint("TOPRIGHT", done, "TOPRIGHT", -14, -32)
    done.text:SetJustifyH("LEFT")
    done.text:SetJustifyV("TOP")
    done.text:SetHeight(44)
    done.leave = button(done, L["Leave group"], 104)
    done.leave:SetPoint("BOTTOMLEFT", 12, 12)
    done.leave:SetScript("OnClick", function() Q.LeaveGroup(); NS.RefreshQuest("done") end)
    done.remove = button(done, L["Remove listing"], 110)
    done.remove:SetPoint("LEFT", done.leave, "RIGHT", 6, 0)
    done.remove:SetScript("OnClick", function() Q.RemoveListing(); NS.RefreshQuest("done") end)
    done.later = button(done, L["Not now"], 80)
    done.later:SetPoint("BOTTOMRIGHT", -12, 12)
    done.later:SetScript("OnClick", function() done:Hide() end)
    -- traduções longas: a janela cresce para os três botões caberem
    done:SetWidth(max(380, done.leave:GetWidth() + done.remove:GetWidth() + done.later:GetWidth() + 48))
    tooltip(done.leave, L["Leave group"], L["Leaves the group. The addon never leaves on its own."])
    tooltip(done.remove, L["Remove listing"], L["Takes your group out of Looking For Group."])
end

function NS.RenderQuestDone()
    if not done or not done:IsShown() then return end
    local inGroup = IsInGroup() and true or false
    local has = Q.HasListing()
    done.leave:SetEnabled(inGroup)
    done.remove:SetEnabled(has)
    if not inGroup and not has then done:Hide() end
end

function NS.ShowQuestDone(questID, title)
    if not done then buildDone() end
    done.questID = questID
    done.text:SetText(format(L["You finished %s. Leave the group or take it out of Looking For Group?"], title or tostring(questID)))
    done:Show()
    NS.RenderQuestDone()
end
