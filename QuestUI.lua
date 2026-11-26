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
local W, H = 470, 540
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

local function check(parent, text, tip)
    local c = CF("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(22, 22)
    local t = c.Text or c.text or label(c, "", "GameFontHighlightSmall")
    if not (c.Text or c.text) then t:SetPoint("LEFT", c, "RIGHT", 2, 1) end
    t:SetText(text)
    t:SetWidth(W - 60)
    t:SetJustifyH("LEFT")
    t:SetWordWrap(false)
    c.label = t
    tooltip(c, text, tip)
    return c
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
            if not mine[ch] and ch.IsVisible and ch:IsVisible() then
                local r = rectOf(ch)
                local kind = ch.GetObjectType and ch:GetObjectType()
                local small = r and (r.r - r.l) <= 220 and (r.t - r.b) <= 60
                local mouse = ch.IsMouseEnabled and ch:IsMouseEnabled()
                if r and small and (CLICKABLE[kind] or mouse) then out[#out + 1] = { f = ch, r = r } end
                if d < depth then walk(ch, d + 1) end
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

local function savePos(self)
    self:StopMovingOrSizing()
    local p, _, rp, x, y = self:GetPoint(1)
    Q.DB().pos = { p, rp, x, y }
end

function NS.BuildQuestUI()
    if win then return end
    win = CF("Frame", "GrupoFacilQuestFrame", UIParent, "BasicFrameTemplateWithInset")
    win:SetSize(W, H)
    win:SetFrameStrata("HIGH")
    NS.Toplevel(win)
    win:SetClampedToScreen(true)
    win:SetMovable(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", savePos)
    win:Hide()
    local pos = Q.DB().pos
    if type(pos) == "table" and pos[1] then
        win:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    else
        win:SetPoint("CENTER", UIParent, "CENTER", -260, 40)
    end
    local title = win.TitleText or label(win, "", "GameFontHighlight")
    title:SetText(L["GrupoFacil: quest groups"])
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", 12, -5)

    -- ir para a janela das masmorras (a principal)
    win.dungeons = button(win, L["Dungeons"], 90, 20)
    win.dungeons:SetPoint("TOPRIGHT", -30, -1)
    win.dungeons:SetScript("OnClick", function() if NS.ShowPanel then NS.ShowPanel(false) end end)
    tooltip(win.dungeons, L["Dungeons"], L["Opens the main GrupoFacil window (dungeon groups and players)."])

    -- a missão
    win.quest = label(win, "", "GameFontNormalLarge")
    win.quest:SetPoint("TOPLEFT", 14, -32)
    win.quest:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.quest:SetJustifyH("LEFT")
    win.quest:SetWordWrap(false)
    win.meta = label(win, "", "GameFontHighlightSmall")
    win.meta:SetPoint("TOPLEFT", win.quest, "BOTTOMLEFT", 0, -4)
    win.meta:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.meta:SetJustifyH("LEFT")
    win.meta:SetWordWrap(false)
    win.status = label(win, "", "GameFontNormalSmall")
    win.status:SetPoint("TOPLEFT", win.meta, "BOTTOMLEFT", 0, -6)
    win.status:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.status:SetJustifyH("LEFT")
    win.status:SetWordWrap(false)
    win.warn = label(win, "", "GameFontNormalSmall")
    win.warn:SetPoint("TOPLEFT", win.status, "BOTTOMLEFT", 0, -4)
    win.warn:SetPoint("RIGHT", win, "RIGHT", -14, 0)
    win.warn:SetJustifyH("LEFT")
    win.warn:SetWordWrap(false)
    win.warn:SetTextColor(1, 0.53, 0)

    -- pedidos recebidos (você lidera)
    win.reqTitle = label(win, L["Asked to join your group"], "GameFontNormal")
    win.reqTitle:SetPoint("TOPLEFT", 14, -110)
    win.reqTitle:SetJustifyH("LEFT")
    win.reqBox = CF("Frame", nil, win)
    win.reqBox:SetPoint("TOPLEFT", 10, -128)
    win.reqBox:SetPoint("RIGHT", win, "RIGHT", -10, 0)
    win.reqBox:SetHeight(REQ_ROWS * 26)
    for i = 1, REQ_ROWS do reqRows[i] = makeReqRow(win.reqBox, i) end

    -- resultados
    win.list = CF("Frame", nil, win)
    win.list:SetPoint("BOTTOMRIGHT", -10, 104)
    win.list:EnableMouseWheel(true)
    win.offset = 0
    win.list:SetScript("OnMouseWheel", function(_, delta)
        win.offset = max(0, win.offset - delta * 2)
        NS.RenderQuest()
    end)
    win.empty = label(win.list, "", "GameFontDisable")
    win.empty:SetPoint("TOPLEFT", 6, -8)
    win.empty:SetPoint("RIGHT", win.list, "RIGHT", -6, 0)
    win.empty:SetJustifyH("LEFT")
    win.empty:SetJustifyV("TOP")
    win.empty:SetHeight(60)

    -- ações
    win.search = button(win, L["Search again"], 110)
    win.search:SetPoint("BOTTOMLEFT", 12, 76)
    win.search:SetScript("OnClick", function()
        local ok, why = Q.SearchAgain()
        Q.status = (not ok) and why or nil
        NS.RefreshQuest("search")
    end)
    tooltip(win.search, L["Search again"], L["Searches again for the same quest."])
    win.create = button(win, L["Create group"], 120, 22, { L["Create group"], L["Remove listing"] })
    win.create:SetPoint("LEFT", win.search, "RIGHT", 6, 0)
    win.create:SetScript("OnClick", function()
        if Q.HasListing() then Q.RemoveListing() else Q.Create() end
        NS.RefreshQuest("create")
    end)
    tooltip(win.create, function() return Q.HasListing() and L["Remove listing"] or L["Create group"] end, function()
        if Q.HasListing() then return L["Takes your group out of Looking For Group."] end
        local ok, why = Q.CanCreate()
        if not ok then return L["Unavailable: "] .. why end
        local act = Q.current and Q.current.activity
        return format(L["Lists you in Looking For Group (%s) with this quest. Players who click the magnifier on the same quest find you first."],
            act and (act.label or act.name) or "?")
    end)
    win.desc = button(win, L["Description"], 100)
    win.desc:SetPoint("LEFT", win.create, "RIGHT", 6, 0)
    win.desc:SetScript("OnClick", function() if Q.current then NS.ShowQuestDescription(Q.current.questID) end end)
    tooltip(win.desc, L["Description for the listing"],
        L["Text with the quest, the objective, the zone and GrupoFacil, to paste in the description of your Looking For Group listing. The game does not let addons fill it in."])
    win.pageFS = label(win, "", "GameFontDisableSmall")
    win.pageFS:SetPoint("BOTTOMRIGHT", -16, 82)
    win.pageFS:SetJustifyH("RIGHT")

    win.autoInvite = check(win, L["Auto-invite players who ask for the same quest"],
        L["Only players who use GrupoFacil and asked to join for a quest you also have. At most 6 invites every 10 minutes. Off by default."])
    win.autoInvite:SetPoint("BOTTOMLEFT", 12, 50)
    win.autoInvite:SetScript("OnClick", function(self) Q.DB().autoInvite = self:GetChecked() and true or false end)
    win.autoAccept = check(win, L["Auto-accept the invite from a leader I asked"],
        L["Only the leader you asked to join, for 2 minutes after asking."])
    win.autoAccept:SetPoint("BOTTOMLEFT", 12, 28)
    win.autoAccept:SetScript("OnClick", function(self) Q.DB().autoAccept = self:GetChecked() and true or false end)
    win.magnifier = check(win, L["Magnifier next to quests"], L["Shows the magnifier in the objective list and in the quest details."])
    win.magnifier:SetPoint("BOTTOMLEFT", 12, 6)
    win.magnifier:SetScript("OnClick", function(self)
        Q.DB().magnifier = self:GetChecked() and true or false
        NS.RefreshMagnifiers()
    end)

    win:SetScript("OnShow", function() NS.RenderQuest() end)
    Trace("CARGA", "janela de missões criada")
end

local function layoutList(nReq)
    local top = nReq > 0 and (128 + nReq * 26 + 6) or 108
    win.reqTitle:SetShown(nReq > 0)
    win.list:ClearAllPoints()
    win.list:SetPoint("TOPLEFT", 10, -top)
    win.list:SetPoint("BOTTOMRIGHT", -10, 104)
    local h = H - top - 104
    local n = max(2, floor(h / ROW_H))
    for i = 1, n do if not rows[i] then rows[i] = makeRow(win.list, i) end end
    for i = n + 1, #rows do rows[i]:Hide() end
    return n
end

function NS.RenderQuest()
    if not win or not win:IsShown() then return end
    local db = Q.DB()
    win.autoInvite:SetChecked(db.autoInvite)
    win.autoAccept:SetChecked(db.autoAccept)
    win.magnifier:SetChecked(db.magnifier ~= false)

    local cur = Q.current
    if cur and cur.info then
        local q = Q.Info(cur.questID) or cur.info
        cur.info = q
        win.quest:SetText(q.title or "")
        local meta = {}
        if q.zone then meta[#meta + 1] = q.zone end
        if q.level then meta[#meta + 1] = format(L["Lvl %d"], q.level) end
        if q.elite then meta[#meta + 1] = "|cffff8000" .. L["Elite"] .. "|r" end
        if q.size then meta[#meta + 1] = format(L["Group: %d"], q.size) end
        if q.complete then meta[#meta + 1] = "|cff55ff55" .. L["complete"] .. "|r" end
        if cur.activity then
            meta[#meta + 1] = "|cff999999" .. format(L["Looking For Group: %s"], cur.activity.label or cur.activity.name or "?") .. "|r"
        end
        win.meta:SetText(table.concat(meta, "  ·  "))
    else
        win.quest:SetText(L["No quest chosen"])
        win.meta:SetText(L["Click the magnifier next to a quest in the objective list or in the quest log."])
    end

    -- pedidos recebidos
    local reqs = Q.Requests()
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
    local n = layoutList(nReq)

    local list = Q.Results()
    local total = #list
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
            local parts = { why and why() or ("|cff999999" .. L["same zone"] .. "|r"), membersText(e) }
            r.info:SetText(table.concat(parts, "  ·  "))
            r.name:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
            r.info:SetPoint("RIGHT", r.b1, "LEFT", -6, 0)
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
        win.empty:SetText(cur and (NS.searching and L["Searching..."]
            or L["No group for this quest yet. Create one: players who click the magnifier on the same quest find you."]) or "")
        win.empty:Show()
    else
        win.empty:Hide()
    end
    win.pageFS:SetText(total > n and format(L["%d-%d of %d"], win.offset + 1, min(total, win.offset + n), total) or "")

    local status
    if Q.status then status = "|cffff8800" .. Q.status .. "|r"
    elseif not cur then status = ""
    elseif NS.searching then status = L["Searching..."]
    else
        local doing, peers = 0, 0
        for _, e in ipairs(list) do
            if e.qScore == 3 then doing = doing + 1 end
            if e.qPeer then peers = peers + 1 end
        end
        status = format(L["%d groups in the zone, %d doing this quest. %d use GrupoFacil."], total, doing, peers)
    end
    win.status:SetText(status)
    win.warn:SetText(Q.JoinWarning() or "")

    win.search:SetEnabled(cur ~= nil and GetTime() >= NS.searchReadyAt and not NS.searching and not NS.InLockdown())
    local has = Q.HasListing()
    win.create:SetText(has and L["Remove listing"] or L["Create group"])
    win.create:SetEnabled(has or (Q.CanCreate()))
    win.desc:SetEnabled(cur ~= nil)
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
function NS.ShowQuestWindow(byClick)
    if not win then NS.BuildQuestUI() end
    if not win then return end
    if not byClick and win:IsShown() then NS.RefreshQuest("show") return end
    win:Show()
    NS.RefreshQuest("show")
end

function NS.ToggleQuestWindow()
    if not win then NS.BuildQuestUI() end
    if win:IsShown() then win:Hide() else NS.ShowQuestWindow(true) end
end

------------------------------------------------------------------------
-- descrição sugerida para a listagem (o jogador copia e cola no Looking For Group)
------------------------------------------------------------------------
local desc

local function descText()
    return desc and desc.questID and Q.Description(desc.questID, desc.mine:GetChecked() and true or false) or ""
end

local function buildDesc()
    desc = CF("Frame", "GrupoFacilQuestDesc", UIParent, "BasicFrameTemplateWithInset")
    desc:SetSize(460, 150)
    desc:SetPoint("TOP", UIParent, "TOP", 0, -140)
    desc:SetFrameStrata("DIALOG")
    NS.Toplevel(desc)
    desc:SetClampedToScreen(true)
    desc:SetMovable(true)
    desc:EnableMouse(true)
    desc:RegisterForDrag("LeftButton")
    desc:SetScript("OnDragStart", desc.StartMoving)
    desc:SetScript("OnDragStop", desc.StopMovingOrSizing)
    desc:Hide()
    local title = desc.TitleText or label(desc, "", "GameFontHighlight")
    title:SetText(L["Description for the listing"])
    desc.text = label(desc, L["Click the text, Ctrl+C to copy, then paste it (Ctrl+V) in the description of your listing in Looking For Group."], "GameFontHighlightSmall")
    desc.text:SetPoint("TOPLEFT", 14, -32)
    desc.text:SetPoint("RIGHT", desc, "RIGHT", -14, 0)
    desc.text:SetJustifyH("LEFT")
    desc.text:SetJustifyV("TOP")
    desc.text:SetHeight(30)
    local e = CF("EditBox", nil, desc, "InputBoxTemplate")
    e:SetSize(420, 20)
    e:SetPoint("TOPLEFT", 22, -66)
    e:SetAutoFocus(false)
    e:SetMaxLetters(255)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(descText()); self:HighlightText() end end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus(); desc:Hide() end)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    desc.box = e
    desc.mine = check(desc, L["In my language (English reaches more players)"], L["The description goes in English by default, which every player on the server reads."])
    desc.mine.label:SetWidth(300)
    desc.mine:SetPoint("BOTTOMLEFT", 12, 12)
    desc.mine:SetScript("OnClick", function(self)
        Q.DB().descTranslated = self:GetChecked() and true or false
        NS.RenderQuestDescription()
    end)
    desc.close = button(desc, L["Close"], 80)
    desc.close:SetPoint("BOTTOMRIGHT", -12, 12)
    desc.close:SetScript("OnClick", function() desc:Hide() end)
end

function NS.RenderQuestDescription()
    if not desc or not desc:IsShown() then return end
    local t = descText()
    desc.box:SetText(t)
    desc.box:SetCursorPosition(0)
    desc.box:SetFocus()
    desc.box:HighlightText()
end

function NS.ShowQuestDescription(questID)
    if not questID then return end
    if not desc then buildDesc() end
    desc.questID = questID
    -- cliente em inglês: a opção "no meu idioma" não muda nada
    local english = (GetLocale and GetLocale() or "enUS"):match("^en") ~= nil
    desc.mine:SetShown(not english)
    desc.mine:SetChecked((not english) and Q.DB().descTranslated == true)
    desc:Show()
    NS.RenderQuestDescription()
    Trace("MISSAO", "descrição sugerida aberta: missão=%d", questID)
end

-- a listagem saiu: oferece a descrição na hora, que é quando o jogador vai querer colar
function NS.OnQuestListed(questID)
    NS.ShowQuestDescription(questID)
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
    done.text:SetPoint("RIGHT", done, "RIGHT", -14, 0)
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
