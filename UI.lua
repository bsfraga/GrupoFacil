-- GrupoFacil: janela própria (filho do UIParent, nunca da janela da Blizzard).

local ADDON, NS = ...
local L = NS.L
local format, lower, floor, max, min = string.format, string.lower, math.floor, math.max, math.min

local ROW_H, MAX_ROWS = 38, 30
local MIN_W, MIN_H, MAX_W, MAX_H = 440, 420, 1000, 1200
local LIST_TOP, LIST_BOTTOM = 222, 66 -- distância da lista ao topo e ao pé da janela
local LIST_TOP_COMPACT = 92            -- com os filtros recolhidos
local STATUS_Y, STATUS_Y_COMPACT = -192, -62
NS.rowsVisible = 9
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
-- Rótulos resolvidos na hora (o idioma só é conhecido depois do SavedVariables carregar).
local MODE_LABEL = setmetatable({}, { __index = function(_, k) return L[({ players = "Players", groups = "Groups", all = "All" })[k] or k] end })
local SORT_NEXT = { level = "name", name = "age", age = "level" }
local SORT_LABEL = setmetatable({}, { __index = function(_, k) return L[({ level = "Level", name = "Name", age = "Newest" })[k] or k] end })

local frame
NS.offset = 0

-- Todo frame do addon nasce por aqui: cada SetScript fica protegido pelo diagnóstico,
-- e um erro num clique ou tooltip vai para /gf diag com o nome do script.
local scriptN = 0
local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    scriptN = scriptN + 1
    local tag = (name or kind) .. "#" .. scriptN
    local orig = f.SetScript
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then fn = NS.D.Wrap(tag .. "." .. script, fn) end
        return orig(self, script, fn)
    end
    return f
end

------------------------------------------------------------------------
-- utilidades visuais
------------------------------------------------------------------------
local function classColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 1, 0.82, 0
end

local function className(class)
    return (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class
end

local function setClassIcon(tex, class)
    if class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class] then
        tex:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        tex:SetTexCoord(unpack(CLASS_ICON_TCOORDS[class]))
        return
    end
    tex:SetTexCoord(0, 1, 0, 1)
    if class and pcall(tex.SetAtlas, tex, "classicon-" .. lower(class)) then return end
    tex:SetTexture("Interface\\Icons\\INV_Misc_GroupLooking")
end

local function ageText(sec)
    if type(sec) ~= "number" then return "" end
    if sec < 60 then return L["now"] end
    if sec < 3600 then return format("%d min", floor(sec / 60)) end
    return format("%dh", floor(sec / 3600))
end

-- Ícones de role: atlas do cliente quando existe; senão a textura clássica do LFG.
local ROLE_ATLAS = { tank = "roleicon-tiny-tank", healer = "roleicon-tiny-healer", dps = "roleicon-tiny-dps" }
local ROLE_COORDS = { tank = "0:19:22:41", healer = "20:39:1:20", dps = "20:39:22:41" }
local roleIconCache = {}
local function roleIcon(role, size)
    size = size or 14
    local key = role .. size
    if roleIconCache[key] then return roleIconCache[key] end
    local s
    local atlas = ROLE_ATLAS[role]
    if CreateAtlasMarkup and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        s = CreateAtlasMarkup(atlas, size, size)
    else
        s = format("|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:%d:%d:0:0:64:64:%s|t", size, size, ROLE_COORDS[role])
    end
    roleIconCache[key] = s
    return s
end
NS.RoleIcon = roleIcon
local ROLE_COLOR = { tank = "|cff4fa3ff", healer = "|cff55ff55", dps = "|cffff6060" }
local ROLE_KEY = { tank = "Tank", healer = "Healer", dps = "DPS" }
local ASSIGNED = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }
local function roleWithIcon(role) return roleIcon(role) .. " " .. ROLE_COLOR[role] .. L[ROLE_KEY[role]] .. "|r" end

-- amigo / guilda ao lado do nome
local RELATION_ICON = {
    friend = "|TInterface\\FriendsFrame\\UI-Toast-FriendOnlineIcon:14:14:0:0|t",
    guild = "|TInterface\\GossipFrame\\TabardGossipIcon:14:14:0:0|t",
}

local function levelRange(minL, maxL)
    if minL and maxL then return format("%d-%d", minL, maxL) end
    if minL then return format("%d+", minL) end
    return nil
end

local function rolesText(e)
    if e.solo then
        if not e.roles then return "" end
        local t = {}
        for _, r in ipairs({ "tank", "healer", "dps" }) do
            if e.roles[r] then t[#t + 1] = roleIcon(r) end
        end
        return table.concat(t, " ")
    end
    local s = e.maxPlayers and format("%d/%d", e.numMembers, e.maxPlayers) or format(L["%d members"], e.numMembers)
    if e.counts then
        s = s .. format("  %s%d %s%d %s%d", roleIcon("tank"), e.counts.tank, roleIcon("healer"), e.counts.healer, roleIcon("dps"), e.counts.dps)
    end
    return s
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

-- Largura que cabe o texto (as traduções podem ser mais longas que o inglês).
local function textWidth(b, text)
    local fs = b.GetFontString and b:GetFontString()
    if not fs then return 0 end
    local old = fs:GetText()
    fs:SetText(text)
    local w = fs:GetStringWidth() or 0
    fs:SetText(old)
    return w
end

local function fitWidth(b, minW, texts)
    local w = minW
    for _, t in ipairs(texts) do w = max(w, textWidth(b, t) + 22) end
    b:SetWidth(w)
end

local function button(parent, text, w, h)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
    fitWidth(b, w, { text })
    return b
end

local function label(parent, text, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontNormalSmall")
    fs:SetText(text or "")
    return fs
end

------------------------------------------------------------------------
-- construção
------------------------------------------------------------------------
local modeButtons, classButtons, roleChecks, roleLabels, rows = {}, {}, {}, {}, {}
local minBox, maxBox, sortBtn, statusFS, searchBtn, pageFS, previewFS, hideDelistedCheck, roleLabel
local dungeonBtn, compactBtn, hiddenBtn
local filterWidgets = {} -- tudo que some no modo compacto

local function filters() return GrupoFacilDB.filters end

local function onFilterChanged()
    NS.offset = 0
    if NS.CloseRowMenu then NS.CloseRowMenu() end
    NS.Refresh("filter")
end

local function readLevelBox(box)
    local n = tonumber(box:GetText())
    if n and n >= 1 then return floor(n) end
    return nil
end

local function makeRow(parent, i)
    local r = CF("Button", nil, parent)
    r:SetHeight(ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetPoint("TOPRIGHT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bgAlpha = (i % 2 == 0) and 0.04 or 0
    r.bg:SetColorTexture(1, 1, 1, r.bgAlpha)
    -- faixa verde à esquerda: o grupo tem vaga para uma role sua
    r.need = r:CreateTexture(nil, "ARTWORK")
    r.need:SetPoint("TOPLEFT", 0, -2)
    r.need:SetPoint("BOTTOMLEFT", 0, 2)
    r.need:SetWidth(3)
    r.need:SetColorTexture(0.33, 1, 0.33, 0.9)
    r.need:Hide()

    r.icon = r:CreateTexture(nil, "ARTWORK")
    r.icon:SetSize(26, 26)
    r.icon:SetPoint("LEFT", 6, 0)

    r.name = label(r, "", "GameFontNormal")
    r.name:SetPoint("TOPLEFT", r.icon, "TOPRIGHT", 8, 2)
    r.name:SetWidth(200)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)

    r.info = label(r, "", "GameFontHighlightSmall")
    r.info:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -3)
    r.info:SetWidth(205)
    r.info:SetJustifyH("LEFT")
    r.info:SetWordWrap(false)

    r.b2 = button(r, L["Whisper"], 74, 20)
    r.b2:SetPoint("RIGHT", -4, 0)
    r.b1 = button(r, L["Invite"], 82, 20)
    r.b1:SetPoint("RIGHT", r.b2, "LEFT", -3, 0)
    fitWidth(r.b1, 82, { L["Invite"], L["Ask to join"], L["Sent"] })

    r.b1:SetScript("OnClick", function(self)
        local e = r.entry
        if not e then return end
        if e.solo then NS.Invite(e) else NS.AskToJoin(e) end
        NS.Refresh("click")
    end)
    r.b2:SetScript("OnClick", function()
        if r.entry then NS.OpenWhisper(r.entry) end
    end)
    tooltip(r.b1, function()
        local e = r.entry
        if not e then return "" end
        return e.solo and L["Invite to group"] or L["Ask the leader to join"]
    end, function()
        local e = r.entry
        if not e then return "" end
        if e.solo then
            return NS.CanInvite(e) and "" or L["You can only invite when you are solo or the leader/assistant."]
        end
        local ok, why = NS.CanAskToJoin(e)
        local msg = NS.BuildMessage(e)
        if GrupoFacilDB.sendMode == "preencher" then msg = msg .. "\n" .. L["(prefill mode: opens the chat, you press Enter)"] end
        return ok and (L["Sends: "] .. msg) or (L["Unavailable: "] .. why)
    end)
    tooltip(r.b2, L["Whisper"], L["Opens the chat so you can write to the player."])

    -- clique direito: esconder nesta sessão ou bloquear
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    r:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" and self.entry then NS.ShowRowMenu(self) end
    end)

    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(e.name or RETRIEVING_DATA or "...", classColor(e.class))
        if e.relation == "friend" then GameTooltip:AddLine(RELATION_ICON.friend .. " " .. L["Friend"], 0.4, 0.8, 1)
        elseif e.relation == "guild" then GameTooltip:AddLine(RELATION_ICON.guild .. " " .. L["Guild member"], 0.25, 1, 0.25) end
        if e.level or e.className then
            GameTooltip:AddLine(format(L["Level %s %s %s"], tostring(e.level or "?"), e.specName or "", e.className or className(e.class) or ""), 1, 1, 1)
        end
        if e.activity ~= "" then
            local range = levelRange(e.actMin, e.actMax)
            GameTooltip:AddLine(e.activity .. (range and ("  |cff999999(" .. range .. ")|r") or ""), 0.8, 0.8, 0.8, true)
        end
        if e.zone then
            GameTooltip:AddLine(format(e.solo and L["Zone: %s"] or L["Leader's zone: %s"], e.zone), 0.8, 0.8, 0.8, true)
        end
        if not e.solo then
            GameTooltip:AddLine(L["Members: "] .. rolesText(e), 0.8, 0.8, 0.8)
            -- composição: role, classe e level de cada membro
            for _, m in ipairs(e.members or {}) do
                local role = ASSIGNED[m.role or ""]
                local icon = role and roleIcon(role) or "   "
                local cname = m.className or className(m.class) or "?"
                local cr, cg, cb = classColor(m.class)
                local lvl = m.level and format(L["Lvl %d"], m.level) or ""
                GameTooltip:AddLine(format("%s %s  |cffaaaaaa%s|r%s", icon, cname, lvl, m.leader and ("  |cffffd200" .. L["leader"] .. "|r") or ""),
                    cr, cg, cb)
            end
            if e.remaining then
                local open = {}
                for _, role in ipairs({ "tank", "healer", "dps" }) do
                    if (e.remaining[role] or 0) > 0 then open[#open + 1] = format("%s%d", roleIcon(role), e.remaining[role]) end
                end
                GameTooltip:AddLine(L["Open spots: "] .. (#open > 0 and table.concat(open, "  ") or L["none"]), 0.8, 0.8, 0.8)
            end
            if e.needsMe and not IsInGroup() then
                GameTooltip:AddLine(format(L["Needs your role: %s"], L[ROLE_KEY[e.needsMe]]), 0.33, 1, 0.33)
            end
        end
        if e.delisted then GameTooltip:AddLine(L["Left the list"], 1, 0.3, 0.3) end
        if e.key then GameTooltip:AddLine(L["Right-click: hide or block"], 0.5, 0.5, 0.5) end
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function() GameTooltip:Hide() end)
    r:Hide()
    return r
end

function NS.BuildUI()
    if frame then return end
    local db = GrupoFacilDB
    frame = CF("Frame", "GrupoFacilFrame", UIParent, "BasicFrameTemplateWithInset")
    local size = type(db.size) == "table" and db.size or {}
    frame:SetSize(min(MAX_W, max(MIN_W, size[1] or MIN_W)), min(MAX_H, max(MIN_H, size[2] or 600)))
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif frame.SetMinResize then
        frame:SetMinResize(MIN_W, MIN_H)
        frame:SetMaxResize(MAX_W, MAX_H)
    end
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        GrupoFacilDB.docked = false
        local p, _, rp, x, y = self:GetPoint(1)
        GrupoFacilDB.pos = { p, rp, x, y }
    end)
    frame:Hide()

    local title = frame.TitleText or label(frame, "", "GameFontHighlight")
    if not frame.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("GrupoFacil")
    title:ClearAllPoints()
    title:SetPoint("TOPLEFT", 12, -5)
    -- autoria na barra de título (à direita, antes do X)
    local by = label(frame, NS.AUTHOR_LINE or "", "GameFontDisableSmall")
    by:SetPoint("TOPRIGHT", -30, -6)

    -- linha 1: modo e ordem
    local prevMode
    for _, mode in ipairs({ "players", "groups", "all" }) do
        local b = button(frame, MODE_LABEL[mode], 84)
        if prevMode then b:SetPoint("LEFT", prevMode, "RIGHT", 2, 0) else b:SetPoint("TOPLEFT", 12, -30) end
        b:SetScript("OnClick", function()
            filters().mode = mode
            onFilterChanged()
        end)
        modeButtons[mode] = b
        prevMode = b
    end
    sortBtn = button(frame, "", 140)
    sortBtn:SetPoint("TOPRIGHT", -12, -30)
    fitWidth(sortBtn, 120, { L["Sort: "] .. L["Level"], L["Sort: "] .. L["Name"], L["Sort: "] .. L["Newest"] })
    sortBtn:SetScript("OnClick", function()
        filters().sort = SORT_NEXT[filters().sort] or "level"
        onFilterChanged()
    end)

    -- linha 2: level
    local lvl = label(frame, L["Level"], "GameFontNormal")
    lvl:SetPoint("TOPLEFT", 14, -64)
    minBox = CF("EditBox", nil, frame, "InputBoxTemplate")
    minBox:SetSize(32, 20)
    minBox:SetPoint("LEFT", lvl, "RIGHT", 10, 0)
    minBox:SetAutoFocus(false)
    minBox:SetNumeric(true)
    minBox:SetMaxLetters(2)
    local dash = label(frame, L["to"], "GameFontNormal")
    dash:SetPoint("LEFT", minBox, "RIGHT", 6, 0)
    maxBox = CF("EditBox", nil, frame, "InputBoxTemplate")
    maxBox:SetSize(32, 20)
    maxBox:SetPoint("LEFT", dash, "RIGHT", 10, 0)
    maxBox:SetAutoFocus(false)
    maxBox:SetNumeric(true)
    maxBox:SetMaxLetters(2)
    for _, box in ipairs({ minBox, maxBox }) do
        box:SetScript("OnTextChanged", function(self, userInput)
            if not userInput then return end
            filters().minLevel = readLevelBox(minBox)
            filters().maxLevel = readLevelBox(maxBox)
            onFilterChanged()
        end)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        box:SetScript("OnEscapePressed", box.ClearFocus)
    end
    local near = button(frame, L["Near me"], 96, 20)
    near:SetPoint("LEFT", maxBox, "RIGHT", 10, 0)
    near:SetScript("OnClick", function()
        local me = UnitLevel("player") or 1
        filters().minLevel = max(1, me - 3)
        filters().maxLevel = me + 3
        onFilterChanged()
    end)
    tooltip(near, L["Near me"], L["Your level, 3 below to 3 above."])
    hideDelistedCheck = CF("CheckButton", nil, frame, "UICheckButtonTemplate")
    hideDelistedCheck:SetSize(24, 24)
    hideDelistedCheck:SetPoint("LEFT", near, "RIGHT", 8, 0)
    local hdl = label(frame, L["Hide delisted"], "GameFontHighlightSmall")
    hdl:SetPoint("LEFT", hideDelistedCheck, "RIGHT", 0, 0)
    hideDelistedCheck:SetScript("OnClick", function(self)
        filters().hideDelisted = self:GetChecked() and true or false
        onFilterChanged()
    end)
    for _, w in ipairs({ lvl, minBox, dash, maxBox, near, hideDelistedCheck, hdl }) do filterWidgets[#filterWidgets + 1] = w end

    -- linha 3: classes
    local cl = label(frame, L["Class"], "GameFontNormal")
    cl:SetPoint("TOPLEFT", 14, -98)
    local prev
    for _, class in ipairs(CLASSES) do
        local b = CF("Button", nil, frame)
        b:SetSize(26, 26)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("LEFT", cl, "RIGHT", 10, 0) end
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.tex:SetAllPoints()
        setClassIcon(b.tex, class)
        b.sel = b:CreateTexture(nil, "OVERLAY")
        b.sel:SetPoint("TOPLEFT", -3, 3)
        b.sel:SetPoint("BOTTOMRIGHT", 3, -3)
        b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight")
        b.sel:SetBlendMode("ADD")
        b:SetScript("OnClick", function()
            local c = filters().classes
            c[class] = (not c[class]) or nil
            onFilterChanged()
        end)
        tooltip(b, className(class), L["Click to toggle. None selected = all."])
        classButtons[class] = b
        filterWidgets[#filterWidgets + 1] = b
        prev = b
    end
    filterWidgets[#filterWidgets + 1] = cl

    -- linha 4: roles
    roleLabel = label(frame, L["Role"], "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", 14, -132)
    prev = roleLabel
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local c = CF("CheckButton", nil, frame, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("LEFT", prev, "RIGHT", prev == roleLabel and 6 or 2, 0)
        local l = label(frame, roleWithIcon(role), "GameFontHighlightSmall")
        l:SetPoint("LEFT", c, "RIGHT", 0, 0)
        c:SetScript("OnClick", function(self)
            filters().roles[role] = self:GetChecked() and true or nil
            onFilterChanged()
        end)
        roleChecks[role] = c
        roleLabels[role] = l
        filterWidgets[#filterWidgets + 1] = c
        filterWidgets[#filterWidgets + 1] = l
        prev = l
    end
    filterWidgets[#filterWidgets + 1] = roleLabel

    -- linha 5: dungeon e limpar filtros
    local dl = label(frame, L["Dungeon"], "GameFontNormal")
    dl:SetPoint("TOPLEFT", 14, -166)
    dungeonBtn = button(frame, "", 220, 20)
    dungeonBtn:SetPoint("LEFT", dl, "RIGHT", 10, 0)
    do -- nome longo de masmorra não vaza do botão
        local fs = dungeonBtn:GetFontString()
        if fs then fs:SetWidth(204); fs:SetWordWrap(false) end
    end
    dungeonBtn:SetScript("OnClick", function(self) NS.ToggleDungeonMenu(self) end)
    tooltip(dungeonBtn, L["Dungeon"], L["Show only these dungeons. The list has the dungeons in the current results, with their suggested level."])
    local clear = button(frame, L["Clear filters"], 110, 20)
    clear:SetPoint("TOPRIGHT", -12, -164)
    clear:SetScript("OnClick", function()
        local f = filters()
        f.minLevel, f.maxLevel = nil, nil
        wipe(f.classes)
        wipe(f.roles)
        wipe(f.activities)
        onFilterChanged()
    end)
    for _, w in ipairs({ dl, dungeonBtn, clear }) do filterWidgets[#filterWidgets + 1] = w end

    -- linha 6: status e busca (sobe no modo compacto, ver NS.ApplyCompact)
    searchBtn = button(frame, L["Search again"], 120)
    searchBtn:SetScript("OnClick", function()
        local ok, why = NS.SearchAgain()
        if not ok then NS.Print(why .. ".") end
        NS.Refresh("search")
    end)
    tooltip(searchBtn, L["Search again"], L["Repeats the last Looking For Group search (same category and activities)."])
    statusFS = label(frame, "", "GameFontHighlightSmall")
    statusFS:SetJustifyH("LEFT")
    statusFS:SetWordWrap(false)

    -- escondidos nesta sessão e bloqueados: só aparece quando há algum
    hiddenBtn = button(frame, format(L["Hidden (%d)"], 0), 100)
    hiddenBtn:SetPoint("RIGHT", searchBtn, "LEFT", -6, 0)
    fitWidth(hiddenBtn, 100, { format(L["Hidden (%d)"], 99) })
    hiddenBtn:SetScript("OnClick", function(self) NS.ToggleHiddenMenu(self) end)
    tooltip(hiddenBtn, L["Hidden players"], L["Players and groups you hid or blocked. Click to show them again. Players on your game ignore list stay hidden; change that in the game's ignore list."])
    hiddenBtn:Hide()

    -- lista (as âncoras de cima ficam em NS.ApplyCompact)
    local list = CF("Frame", nil, frame)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        NS.CloseRowMenu()
        NS.offset = NS.offset - delta * 3
        NS.Refresh("scroll")
    end)
    frame.list = list

    -- rodapé
    local up = button(frame, "<", 26, 20)
    up:SetPoint("BOTTOMLEFT", 12, 38)
    up:SetScript("OnClick", function() NS.CloseRowMenu(); NS.offset = NS.offset - NS.rowsVisible; NS.Refresh("page") end)
    local down = button(frame, ">", 26, 20)
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    down:SetScript("OnClick", function() NS.CloseRowMenu(); NS.offset = NS.offset + NS.rowsVisible; NS.Refresh("page") end)
    pageFS = label(frame, "", "GameFontHighlightSmall")
    pageFS:SetPoint("LEFT", down, "RIGHT", 8, 0)
    pageFS:SetJustifyH("LEFT")
    pageFS:SetWordWrap(false)
    previewFS = label(frame, "", "GameFontDisableSmall")
    previewFS:SetPoint("BOTTOMLEFT", 14, 14)
    previewFS:SetPoint("BOTTOMRIGHT", -26, 14) -- deixa o canto livre para a alça de tamanho
    previewFS:SetJustifyH("LEFT")
    previewFS:SetWordWrap(false)

    -- opções (mensagem, spec, modo de envio etc.) ficam em Options > AddOns > GrupoFacil
    local opts = button(frame, L["Options"], 80, 20)
    opts:SetPoint("BOTTOMRIGHT", -12, 38)
    opts:SetScript("OnClick", function() if NS.OpenOptions then NS.OpenOptions() end end)
    tooltip(opts, L["Options"], L["Join request message, spec, send mode, window and language. Also in Options > AddOns > GrupoFacil."])

    -- modo compacto: recolhe os filtros e a lista ganha o espaço (os filtros continuam valendo)
    compactBtn = button(frame, L["Hide filters"], 100, 20)
    compactBtn:SetPoint("RIGHT", opts, "LEFT", -4, 0)
    fitWidth(compactBtn, 100, { L["Hide filters"], L["Show filters"] })
    compactBtn:SetScript("OnClick", function()
        if NS.TourRunning and NS.TourRunning() then return end -- o tour aponta para os filtros
        NS.SetCompact(not GrupoFacilDB.compact)
    end)
    -- o texto da página termina antes do botão (as traduções são longas)
    pageFS:SetPoint("RIGHT", compactBtn, "LEFT", -6, 0)
    tooltip(compactBtn, function() return GrupoFacilDB.compact and L["Show filters"] or L["Hide filters"] end,
        L["Compact mode: hides the filter rows so more of the list fits. The filters keep working."])

    -- alça de tamanho no canto inferior direito
    local grip = CF("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -4, 4)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, mouse)
        if mouse == "LeftButton" then frame:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        GrupoFacilDB.size = { floor((frame:GetWidth() or MIN_W) + 0.5), floor((frame:GetHeight() or 600) + 0.5) }
        -- StopMovingOrSizing pode soltar a âncora do encaixe; refaz a posição
        if GrupoFacilDB.docked then
            NS.Dock()
        else
            local p, _, rp, x, y = frame:GetPoint(1)
            GrupoFacilDB.pos = { p, rp, x, y }
        end
        NS.Layout()
    end)
    tooltip(grip, L["Drag to resize the window."])
    frame:SetScript("OnSizeChanged", function() NS.Layout() end)

    -- referências para o tour (Onboarding.lua)
    NS.UIRefs = { modeFirst = modeButtons.players, modeLast = modeButtons.all, level = lvl, clear = clear,
        search = searchBtn, list = list, pageUp = up, preview = previewFS, options = opts }

    NS.ApplyCompact()

    frame:SetScript("OnShow", function()
        NS.RequestGuildRoster() -- a guilda só é reconhecida depois que o roster chega
        if not NS.searching then NS.RebuildAll("janela aberta") end
        NS.Refresh("show")
        if NS.OnPanelShown then NS.OnPanelShown() end -- primeiro uso (Onboarding.lua)
    end)
    frame:SetScript("OnHide", function()
        NS.CloseDungeonMenu()
        if NS.CloseRowMenu then NS.CloseRowMenu() end
        NS.CloseHiddenMenu()
        if NS.OnPanelHidden then NS.OnPanelHidden() end
    end)
end

------------------------------------------------------------------------
-- modo compacto
------------------------------------------------------------------------
-- O status termina antes do botão Escondidos (quando ele aparece) ou de Buscar de novo.
local statusAnchoredTo
function NS.AnchorStatus()
    local target = hiddenBtn:IsShown() and hiddenBtn or searchBtn
    if statusAnchoredTo == target and NS.statusAnchoredY == NS.statusY then return end
    statusAnchoredTo, NS.statusAnchoredY = target, NS.statusY
    statusFS:ClearAllPoints()
    statusFS:SetPoint("LEFT", frame, "TOPLEFT", 14, (NS.statusY or STATUS_Y) - 11)
    statusFS:SetPoint("RIGHT", target, "LEFT", -8, 0)
end

------------------------------------------------------------------------
-- lista de escondidos (botão Escondidos)
------------------------------------------------------------------------
local hiddenMenu
function NS.CloseHiddenMenu()
    if hiddenMenu then hiddenMenu:Hide() end
end

local HIDDEN_MAX = 30
local function fillHiddenMenu()
    local m = hiddenMenu
    local list = NS.HiddenList()
    if #list == 0 then m:Hide() return end
    local shown = math.min(#list, HIDDEN_MAX)
    local width = 260
    for i = 1, shown do
        local it = m.items[i]
        if not it then
            it = CF("Frame", nil, m)
            it:SetSize(240, 22)
            it:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 24)
            it:SetPoint("RIGHT", m, "RIGHT", -8, 0)
            it.btn = button(it, L["Show"], 90, 20)
            it.btn:SetPoint("RIGHT", 0, 0)
            fitWidth(it.btn, 90, { L["Show"], L["Unblock"] })
            it.text = label(it, "", "GameFontHighlightSmall")
            it.text:SetPoint("LEFT", 4, 0)
            it.text:SetPoint("RIGHT", it.btn, "LEFT", -6, 0)
            it.text:SetJustifyH("LEFT")
            it.text:SetWordWrap(false)
            it.btn:SetScript("OnClick", function(self)
                local x = self:GetParent().data
                if not x then return end
                if x.kind == "blocked" then NS.Unblock(x.name) else NS.Undismiss(x.key) end
                fillHiddenMenu()
            end)
            m.items[i] = it
        end
        local x = list[i]
        it.data = x
        local tag = x.kind == "blocked" and ("|cffff6060" .. L["blocked"] .. "|r") or ("|cff999999" .. L["this session"] .. "|r")
        it.text:SetText(x.name .. "  " .. tag)
        it.btn:SetText(x.kind == "blocked" and L["Unblock"] or L["Show"])
        it:Show()
        local tw = (it.text.GetUnboundedStringWidth and it.text:GetUnboundedStringWidth()) or it.text:GetStringWidth() or 0
        width = max(width, tw + it.btn:GetWidth() + 36)
    end
    for i = shown + 1, #m.items do m.items[i]:Hide() end
    m.more:SetShown(#list > shown)
    if #list > shown then m.more:SetText(format(L["+%d more: use /gf blocked and /gf unblock."], #list - shown)) end
    m:SetSize(min(width, 420), 44 + shown * 24 + (#list > shown and 18 or 0))
end

function NS.ToggleHiddenMenu(owner)
    if not hiddenMenu then
        local m = CF("Frame", "GrupoFacilHiddenMenu", UIParent, "BackdropTemplate")
        hiddenMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            m:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        end
        m.all = button(m, L["Show all"], 120, 20)
        m.all:SetPoint("TOPLEFT", 8, -8)
        m.all:SetScript("OnClick", function()
            NS.UnhideAll()
            m:Hide()
        end)
        tooltip(m.all, L["Show all"], L["Shows everyone you hid this session and unblocks everyone you blocked."])
        m.more = label(m, "", "GameFontDisableSmall")
        m.more:SetPoint("BOTTOMLEFT", 12, 10)
        m.more:SetPoint("BOTTOMRIGHT", -10, 10)
        m.more:SetJustifyH("LEFT")
        m.more:SetWordWrap(false)
        m.items = {}
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilHiddenMenu") end
        m:Hide()
    end
    if hiddenMenu:IsShown() then hiddenMenu:Hide() return end
    hiddenMenu:ClearAllPoints()
    hiddenMenu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    hiddenMenu:Show()
    fillHiddenMenu()
end
NS.FillHiddenMenu = function() if hiddenMenu and hiddenMenu:IsShown() then fillHiddenMenu() end end

-- Durante o tour os filtros aparecem sem mudar a preferência salva.
NS.forceFilters = false
function NS.ApplyCompact()
    if not frame then return end
    local compact = GrupoFacilDB.compact == true and not NS.forceFilters
    for _, w in ipairs(filterWidgets) do w:SetShown(not compact) end
    local y = compact and STATUS_Y_COMPACT or STATUS_Y
    searchBtn:ClearAllPoints()
    searchBtn:SetPoint("TOPRIGHT", -12, y)
    NS.statusY = y
    NS.AnchorStatus()
    frame.list:ClearAllPoints()
    frame.list:SetPoint("TOPLEFT", 10, -(compact and LIST_TOP_COMPACT or LIST_TOP))
    frame.list:SetPoint("BOTTOMRIGHT", -10, LIST_BOTTOM)
    compactBtn:SetText(compact and L["Show filters"] or L["Hide filters"])
    if NS.CloseDungeonMenu then NS.CloseDungeonMenu() end
    NS.Layout()
end

function NS.SetCompact(on)
    GrupoFacilDB.compact = on and true or nil
    NS.D.Trace("CONFIG", "modo compacto %s", on and "ligado" or "desligado")
    NS.ApplyCompact()
end

-- algum filtro além do modo está ativo? (para avisar quando estão recolhidos)
local function filtersActive()
    local f = filters()
    return f.minLevel or f.maxLevel or next(f.classes) ~= nil or next(f.roles) ~= nil
        or next(f.activities or {}) ~= nil
end

------------------------------------------------------------------------
-- lista de dungeons (filtro)
------------------------------------------------------------------------
local dungeonMenu
function NS.CloseDungeonMenu()
    if dungeonMenu then dungeonMenu:Hide() end
end

local function dungeonButtonText()
    local set = filters().activities
    local n, only = 0, nil
    for a, on in pairs(set) do if on then n = n + 1; only = a end end
    if n == 0 then return L["All dungeons"] end
    if n == 1 then
        local name = NS.ActivityInfo(only)
        return (name and name ~= "") and name or L["Dungeon"]
    end
    return format(L["%d dungeons"], n)
end

local MENU_MAX = 30
local function fillDungeonMenu()
    local m = dungeonMenu
    local all = NS.ActivitiesPresent()
    local set = filters().activities
    -- as marcadas vêm primeiro: nunca somem do corte, sempre dá para desmarcar
    local list = {}
    for _, a in ipairs(all) do if set[a.id] then list[#list + 1] = a end end
    for _, a in ipairs(all) do if not set[a.id] then list[#list + 1] = a end end
    local shown = math.min(#list, MENU_MAX)
    for i = 1, shown do
        local it = m.items[i]
        if not it then
            it = CF("CheckButton", nil, m, "UICheckButtonTemplate")
            it:SetSize(22, 22)
            it:SetPoint("TOPLEFT", 8, -34 - (i - 1) * 22)
            it.text = label(m, "", "GameFontHighlightSmall")
            it.text:SetPoint("LEFT", it, "RIGHT", 2, 0)
            it.text:SetPoint("RIGHT", m, "RIGHT", -10, 0)
            it.text:SetJustifyH("LEFT")
            it.text:SetWordWrap(false)
            it:SetScript("OnClick", function(self)
                filters().activities[self.activityID] = self:GetChecked() and true or nil
                onFilterChanged()
                fillDungeonMenu()
            end)
            m.items[i] = it
        end
        local a = list[i]
        it.activityID = a.id
        it:SetChecked(set[a.id] == true)
        local range = levelRange(a.min, a.max)
        it.text:SetText(a.name .. (range and ("  |cff999999" .. range .. "|r") or "") .. "  |cff777777(" .. a.count .. ")|r")
        it:Show()
        it.text:Show()
    end
    for i = shown + 1, #m.items do m.items[i]:Hide(); m.items[i].text:Hide() end
    local width = 220
    for i = 1, shown do
        local fs = m.items[i].text
        local tw = (fs.GetUnboundedStringWidth and fs:GetUnboundedStringWidth()) or fs:GetStringWidth() or 0
        width = max(width, tw + 50)
    end
    m.empty:SetShown(shown == 0)
    m.more:SetShown(#list > shown)
    if #list > shown then m.more:SetText(format(L["+%d more: pick a level range to narrow the list."], #list - shown)) end
    m:SetSize(min(width, 420), 44 + max(1, shown) * 22 + (#list > shown and 18 or 0))
    dungeonBtn:SetText(dungeonButtonText())
end
NS.FillDungeonMenu = function() if dungeonMenu and dungeonMenu:IsShown() then fillDungeonMenu() end end

function NS.ToggleDungeonMenu(owner)
    if not dungeonMenu then
        local m = CF("Frame", "GrupoFacilDungeonMenu", UIParent, "BackdropTemplate")
        dungeonMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            m:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        end
        m.all = button(m, L["All dungeons"], 120, 20)
        m.all:SetPoint("TOPLEFT", 8, -8)
        m.all:SetScript("OnClick", function()
            wipe(filters().activities)
            onFilterChanged()
            fillDungeonMenu()
        end)
        m.empty = label(m, L["No dungeons in the results yet. Search first."], "GameFontDisableSmall")
        m.empty:SetPoint("TOPLEFT", 12, -38)
        m.more = label(m, "", "GameFontDisableSmall")
        m.more:SetPoint("BOTTOMLEFT", 12, 10)
        m.more:SetPoint("BOTTOMRIGHT", -10, 10)
        m.more:SetJustifyH("LEFT")
        m.more:SetWordWrap(false)
        m.items = {}
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilDungeonMenu") end
        m:Hide()
    end
    if dungeonMenu:IsShown() then dungeonMenu:Hide() return end
    fillDungeonMenu()
    dungeonMenu:ClearAllPoints()
    dungeonMenu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    dungeonMenu:Show()
end

------------------------------------------------------------------------
-- menu do clique direito numa linha
------------------------------------------------------------------------
local rowMenu
function NS.CloseRowMenu()
    if rowMenu then rowMenu:Hide() end
end

function NS.ShowRowMenu(row)
    local e = row.entry
    if not e or not e.key then return end
    if not rowMenu then
        local m = CF("Frame", "GrupoFacilRowMenu", UIParent, "BackdropTemplate")
        rowMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            m:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        end
        m.title = label(m, "", "GameFontNormal")
        m.title:SetPoint("TOPLEFT", 12, -10)
        m.title:SetPoint("TOPRIGHT", -12, -10)
        m.title:SetJustifyH("LEFT")
        m.title:SetWordWrap(false)
        m.dismiss = button(m, L["Hide for this session"], 200, 22)
        m.dismiss:SetPoint("TOPLEFT", 8, -28)
        m.dismiss:SetScript("OnClick", function() m:Hide(); NS.Dismiss(m.entry) end)
        tooltip(m.dismiss, L["Hide for this session"], L["Hidden until you reload the interface."])
        m.block = button(m, L["Block this player"], 200, 22)
        m.block:SetPoint("TOPLEFT", m.dismiss, "BOTTOMLEFT", 0, -4)
        m.block:SetScript("OnClick", function() m:Hide(); NS.Block(m.entry) end)
        tooltip(m.block, L["Block this player"], L["Their listings stay hidden, even after a reload. Undo it in the options or with /gf unblock."])
        m.cancel = button(m, L["Cancel"], 200, 22)
        m.cancel:SetPoint("TOPLEFT", m.block, "BOTTOMLEFT", 0, -4)
        m.cancel:SetScript("OnClick", function() m:Hide() end)
        local w = max(m.dismiss:GetWidth(), m.block:GetWidth(), m.cancel:GetWidth())
        for _, b in ipairs({ m.dismiss, m.block, m.cancel }) do b:SetWidth(w) end
        m:SetSize(w + 16, 36 + 3 * 26)
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilRowMenu") end
        m:Hide()
    end
    rowMenu.entry = e
    rowMenu.title:SetText(e.name or "")
    rowMenu.block:SetEnabled(e.name ~= nil)
    rowMenu:ClearAllPoints()
    rowMenu:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)
    rowMenu:Show()
end

------------------------------------------------------------------------
-- tamanho: quantas linhas cabem e a largura do texto de cada linha
------------------------------------------------------------------------
function NS.Layout()
    if not frame or not frame.list then return end
    local list = frame.list
    local h = list:GetHeight() or (ROW_H * 9)
    local w = list:GetWidth() or 420
    local n = max(3, min(MAX_ROWS, floor(h / ROW_H)))
    NS.rowsVisible = n
    for i = 1, n do
        if not rows[i] then rows[i] = makeRow(list, i) end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    for i = 1, #rows do
        local r = rows[i]
        local bw = (r.b1:GetWidth() or 82) + (r.b2:GetWidth() or 74) + 7
        local tw = max(120, w - 40 - bw - 10)
        r.name:SetWidth(tw)
        r.info:SetWidth(tw)
    end
    NS.Render()
end

------------------------------------------------------------------------
-- posição e visibilidade
------------------------------------------------------------------------
function NS.Dock()
    if not frame then return end
    frame:ClearAllPoints()
    local lfg = _G.LFGParentFrame
    if GrupoFacilDB.docked and lfg and lfg:IsShown() then
        frame:SetPoint("TOPLEFT", lfg, "TOPRIGHT", 4, 0)
    elseif GrupoFacilDB.pos then
        local p = GrupoFacilDB.pos
        frame:SetPoint(p[1], UIParent, p[2], p[3], p[4])
    else
        frame:SetPoint("CENTER", UIParent, "CENTER", 250, 0)
    end
end

function NS.ShowPanel(fromLFG)
    if not frame then return end
    NS.openedWithLFG = fromLFG and true or false
    NS.Dock()
    frame:Show()
end

function NS.HidePanelIfDocked()
    if frame and frame:IsShown() and NS.openedWithLFG then frame:Hide() end
end

function NS.TogglePanel()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else NS.ShowPanel(false) end
end

------------------------------------------------------------------------
-- desenho
------------------------------------------------------------------------
local function renderControls()
    local f = filters()
    for mode, b in pairs(modeButtons) do
        if f.mode == mode then b:LockHighlight() else b:UnlockHighlight() end
        b:SetText(f.mode == mode and ("|cffffffff" .. MODE_LABEL[mode] .. "|r") or MODE_LABEL[mode])
    end
    sortBtn:SetText(L["Sort: "] .. (SORT_LABEL[f.sort] or "Level"))
    if not minBox:HasFocus() then minBox:SetText(f.minLevel and tostring(f.minLevel) or "") end
    if not maxBox:HasFocus() then maxBox:SetText(f.maxLevel and tostring(f.maxLevel) or "") end
    hideDelistedCheck:SetChecked(f.hideDelisted)
    local anyClass = next(f.classes) ~= nil
    for class, b in pairs(classButtons) do
        local on = f.classes[class] == true
        b.sel:SetShown(on)
        b.tex:SetDesaturated(anyClass and not on)
        b:SetAlpha((anyClass and not on) and 0.45 or 1)
    end
    for role, c in pairs(roleChecks) do c:SetChecked(f.roles[role] == true) end
    roleLabel:SetText(f.mode == "groups" and L["Needs"] or L["Role"])
    -- quantos resultados servem para cada role, com os outros filtros aplicados
    local counts = NS.RoleCounts()
    for role, l in pairs(roleLabels) do
        l:SetText(roleWithIcon(role) .. " |cff999999" .. counts[role] .. "|r")
    end
    dungeonBtn:SetText(dungeonButtonText())
    NS.FillDungeonMenu() -- menu aberto acompanha uma busca nova
end

function NS.Render()
    if not frame or not frame:IsShown() then return end
    renderControls()

    local list = NS.Visible()
    local total = #list
    local ROWS = NS.rowsVisible
    NS.offset = max(0, min(NS.offset, max(0, total - ROWS)))

    for i = 1, ROWS do
        local r = rows[i]
        local e = list[NS.offset + i]
        r.entry = e
        if not e then
            r:Hide()
        else
            r:Show()
            setClassIcon(r.icon, e.class)
            if e.solo then r.icon:SetDesaturated(e.delisted) else r.icon:SetDesaturated(true) end
            local lvl = e.level and ("  |cffaaaaaa" .. format(L["Lvl %d"], e.level) .. "|r") or ""
            local need = (e.needsMe and not IsInGroup()) and e.needsMe or nil
            local needTxt = need and ("  " .. roleIcon(need, 12) .. " |cff55ff55" .. L["needs you"] .. "|r") or ""
            local rel = e.relation and (RELATION_ICON[e.relation] .. " ") or ""
            local base = rel .. (e.name or RETRIEVING_DATA or "...") .. lvl
            r.name:SetText(base .. needTxt)
            -- sem espaço para o rótulo inteiro: fica só o ícone da role (a faixa verde continua)
            if need and r.name.IsTruncated and r.name:IsTruncated() then
                r.name:SetText(base .. "  " .. roleIcon(need, 12))
            end
            r.need:SetShown(need ~= nil)
            if need then r.bg:SetColorTexture(0.33, 1, 0.33, 0.07) else r.bg:SetColorTexture(1, 1, 1, r.bgAlpha) end
            if e.delisted then r.name:SetTextColor(0.5, 0.5, 0.5) else r.name:SetTextColor(classColor(e.class)) end
            local parts = {}
            if e.activity ~= "" then parts[#parts + 1] = e.activity end
            local rt = rolesText(e)
            if rt ~= "" then parts[#parts + 1] = rt end
            local age = ageText(e.age)
            if age ~= "" then parts[#parts + 1] = "|cff888888" .. age .. "|r" end
            r.info:SetText(table.concat(parts, "  ·  "))

            if e.solo then
                r.b1:SetText(L["Invite"])
                r.b1:SetEnabled(NS.CanInvite(e) and not NS.InLockdown())
            else
                local sentAt = e.key and NS.sent[e.key]
                r.b1:SetText((sentAt and time() - sentAt < 300) and L["Sent"] or L["Ask to join"])
                r.b1:SetEnabled((NS.CanAskToJoin(e)))
            end
            r.b2:SetEnabled(e.name ~= nil and not e.delisted)
        end
    end

    local status = NS.status or L["Search in the Looking For Group window."]
    if NS.searching then status = L["Searching..."] end
    if NS.stale then status = "|cffff8800" .. status .. "|r" end
    if GrupoFacilDB.compact and filtersActive() then status = status .. "  |cffffd200" .. L["(filters on)"] .. "|r" end
    -- botão Escondidos: escondidos nesta sessão + bloqueados (os ignorados do jogo não entram)
    local nHidden = #NS.HiddenList()
    hiddenBtn:SetShown(nHidden > 0)
    if nHidden > 0 then hiddenBtn:SetText(format(L["Hidden (%d)"], nHidden)) else NS.CloseHiddenMenu() end
    NS.AnchorStatus()
    NS.FillHiddenMenu()
    statusFS:SetText(status .. (total > 0 and ("  |cffffffff" .. format(L["Showing %d."], total) .. "|r") or ""))
    searchBtn:SetEnabled(GetTime() >= NS.searchReadyAt and not NS.searching and not NS.InLockdown())
    if total == 0 then
        pageFS:SetText(#NS.order == 0 and L["No results. Search in Looking For Group."] or L["No result passes the filters."])
    else
        pageFS:SetText(format(L["%d-%d of %d"], NS.offset + 1, min(total, NS.offset + ROWS), total))
    end
    previewFS:SetText(L["Join request: "] .. NS.BuildMessage())
end
