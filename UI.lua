-- GrupoFacil: janela própria (filho do UIParent, nunca da janela da Blizzard).

local ADDON, NS = ...
local L = NS.L
local format, lower, floor, max, min = string.format, string.lower, math.floor, math.max, math.min

local ROW_H, ROWS = 38, 9
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

local ROLE_TXT = {
    tank = "|cff4fa3ffTank|r",
    healer = "|cff55ff55Healer|r",
    dps = "|cffff6060DPS|r",
}

local function rolesText(e)
    if e.solo then
        if not e.roles then return "" end
        local t = {}
        for _, r in ipairs({ "tank", "healer", "dps" }) do
            if e.roles[r] then t[#t + 1] = ROLE_TXT[r] end
        end
        return table.concat(t, " ")
    end
    local s = e.maxPlayers and format("%d/%d", e.numMembers, e.maxPlayers) or format(L["%d members"], e.numMembers)
    if e.counts then
        s = s .. format("  T%d H%d D%d", e.counts.tank, e.counts.healer, e.counts.dps)
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

local function button(parent, text, w, h)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(text)
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
local modeButtons, classButtons, roleChecks, rows = {}, {}, {}, {}
local minBox, maxBox, sortBtn, statusFS, searchBtn, pageFS, previewFS, hideDelistedCheck, roleLabel

local function filters() return GrupoFacilDB.filters end

local function onFilterChanged()
    NS.offset = 0
    NS.Refresh("filter")
end

local function readLevelBox(box)
    local n = tonumber(box:GetText())
    if n and n >= 1 then return floor(n) end
    return nil
end

local function makeRow(parent, i)
    local r = CF("Button", nil, parent)
    r:SetSize(parent:GetWidth(), ROW_H)
    r:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    r.bg = r:CreateTexture(nil, "BACKGROUND")
    r.bg:SetAllPoints()
    r.bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)

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
        local msg = NS.BuildMessage()
        if GrupoFacilDB.sendMode == "preencher" then msg = msg .. "\n" .. L["(prefill mode: opens the chat, you press Enter)"] end
        return ok and (L["Sends: "] .. msg) or (L["Unavailable: "] .. why)
    end)
    tooltip(r.b2, L["Whisper"], L["Opens the chat so you can write to the player."])

    r:SetScript("OnEnter", function(self)
        local e = self.entry
        if not e then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(e.name or RETRIEVING_DATA or "...", classColor(e.class))
        if e.level or e.className then
            GameTooltip:AddLine(format("Level %s %s %s", tostring(e.level or "?"), e.specName or "", e.className or className(e.class) or ""), 1, 1, 1)
        end
        if e.activity ~= "" then GameTooltip:AddLine(e.activity, 0.8, 0.8, 0.8, true) end
        if not e.solo then GameTooltip:AddLine(L["Members: "] .. rolesText(e), 0.8, 0.8, 0.8) end
        if e.delisted then GameTooltip:AddLine(L["Left the list"], 1, 0.3, 0.3) end
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
    frame:SetSize(440, 600)
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
    local x = 12
    for _, mode in ipairs({ "players", "groups", "all" }) do
        local b = button(frame, MODE_LABEL[mode], 84)
        b:SetPoint("TOPLEFT", x, -30)
        b:SetScript("OnClick", function()
            filters().mode = mode
            onFilterChanged()
        end)
        modeButtons[mode] = b
        x = x + 86
    end
    sortBtn = button(frame, "", 140)
    sortBtn:SetPoint("TOPRIGHT", -12, -30)
    sortBtn:SetScript("OnClick", function()
        filters().sort = SORT_NEXT[filters().sort] or "level"
        onFilterChanged()
    end)

    -- linha 2: level
    local lvl = label(frame, "Level", "GameFontNormal")
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
        prev = b
    end

    -- linha 4: roles
    roleLabel = label(frame, L["Role"], "GameFontNormal")
    roleLabel:SetPoint("TOPLEFT", 14, -132)
    prev = roleLabel
    for _, role in ipairs({ "tank", "healer", "dps" }) do
        local c = CF("CheckButton", nil, frame, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c:SetPoint("LEFT", prev, "RIGHT", prev == roleLabel and 6 or 2, 0)
        local l = label(frame, ROLE_TXT[role], "GameFontHighlightSmall")
        l:SetPoint("LEFT", c, "RIGHT", 0, 0)
        c:SetScript("OnClick", function(self)
            filters().roles[role] = self:GetChecked() and true or nil
            onFilterChanged()
        end)
        roleChecks[role] = c
        prev = l
    end
    local clear = button(frame, L["Clear filters"], 110, 20)
    clear:SetPoint("TOPRIGHT", -12, -132)
    clear:SetScript("OnClick", function()
        local f = filters()
        f.minLevel, f.maxLevel = nil, nil
        wipe(f.classes)
        wipe(f.roles)
        onFilterChanged()
    end)

    -- linha 5: status e busca
    searchBtn = button(frame, L["Search again"], 120)
    searchBtn:SetPoint("TOPRIGHT", -12, -160)
    searchBtn:SetScript("OnClick", function()
        local ok, why = NS.SearchAgain()
        if not ok then NS.Print(why .. ".") end
        NS.Refresh("search")
    end)
    tooltip(searchBtn, L["Search again"], L["Repeats the last Looking For Group search (same category and activities)."])
    statusFS = label(frame, "", "GameFontHighlightSmall")
    statusFS:SetPoint("LEFT", frame, "TOPLEFT", 14, -171)
    statusFS:SetPoint("RIGHT", searchBtn, "LEFT", -8, 0)
    statusFS:SetJustifyH("LEFT")
    statusFS:SetWordWrap(false)

    -- lista
    local list = CF("Frame", nil, frame)
    list:SetPoint("TOPLEFT", 10, -192)
    list:SetSize(420, ROW_H * ROWS)
    list:EnableMouseWheel(true)
    list:SetScript("OnMouseWheel", function(_, delta)
        NS.offset = NS.offset - delta * 3
        NS.Refresh("scroll")
    end)
    for i = 1, ROWS do rows[i] = makeRow(list, i) end

    -- rodapé
    local up = button(frame, "<", 26, 20)
    up:SetPoint("BOTTOMLEFT", 12, 38)
    up:SetScript("OnClick", function() NS.offset = NS.offset - ROWS; NS.Refresh("page") end)
    local down = button(frame, ">", 26, 20)
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    down:SetScript("OnClick", function() NS.offset = NS.offset + ROWS; NS.Refresh("page") end)
    pageFS = label(frame, "", "GameFontHighlightSmall")
    pageFS:SetPoint("LEFT", down, "RIGHT", 8, 0)
    previewFS = label(frame, "", "GameFontDisableSmall")
    previewFS:SetPoint("BOTTOMLEFT", 14, 14)
    previewFS:SetPoint("BOTTOMRIGHT", -14, 14)
    previewFS:SetJustifyH("LEFT")
    previewFS:SetWordWrap(false)

    -- opções (mensagem, spec, modo de envio etc.) ficam em Options > AddOns > GrupoFacil
    local opts = button(frame, L["Options"], 80, 20)
    opts:SetPoint("BOTTOMRIGHT", -12, 38)
    opts:SetScript("OnClick", function() if NS.OpenOptions then NS.OpenOptions() end end)
    tooltip(opts, L["Options"], L["Join request message, spec, send mode, window and language. Also in Options > AddOns > GrupoFacil."])

    frame:SetScript("OnShow", function()
        if not NS.searching then NS.RebuildAll("janela aberta") end
        NS.Refresh("show")
    end)
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
end

function NS.Render()
    if not frame or not frame:IsShown() then return end
    renderControls()

    local list = NS.Visible()
    local total = #list
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
            local lvl = e.level and format("  |cffaaaaaaLvl %d|r", e.level) or ""
            r.name:SetText((e.name or RETRIEVING_DATA or "...") .. lvl)
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
    statusFS:SetText(status .. (total > 0 and ("  |cffffffff" .. format(L["Showing %d."], total) .. "|r") or ""))
    searchBtn:SetEnabled(GetTime() >= NS.searchReadyAt and not NS.searching and not NS.InLockdown())
    if total == 0 then
        pageFS:SetText(#NS.order == 0 and L["No results. Search in Looking For Group."] or L["No result passes the filters."])
    else
        pageFS:SetText(format(L["%d-%d of %d"], NS.offset + 1, min(total, NS.offset + ROWS), total))
    end
    previewFS:SetText(L["Join request: "] .. NS.BuildMessage())
end
