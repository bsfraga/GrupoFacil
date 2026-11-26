-- GrupoFacil: opções. O mesmo conteúdo é montado em dois lugares:
--  * a página em Options > AddOns > GrupoFacil (Settings API)
--  * a janela própria do addon, aberta pelo botão Opções, pelo minimapa e por /gf options
-- Uma mudança em qualquer um dos dois atualiza o outro.

local ADDON, NS = ...
local L = NS.L
local format = string.format

-- Link de apoio (GitHub Sponsors, pedido do Fraga 26/11). Vazio = o botão não aparece.
NS.DONATE_URL = "https://github.com/sponsors/bsfraga"

local ALLIANCE_ICON = "|TInterface\\TargetingFrame\\UI-PVP-Alliance:16:16:0:0:64:64:0:40:0:40|t"
NS.AUTHOR_LINE = "Authored by Bael (Bagael Bagacera " .. ALLIANCE_ICON .. ")"

-- Mesmo cuidado do UI.lua: todo script passa pelo diagnóstico.
local n = 0
local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    n = n + 1
    local tag = "Options:" .. (name or kind) .. "#" .. n
    local orig = f.SetScript
    f.SetScript = function(self, script, fn)
        if type(fn) == "function" then fn = NS.D.Wrap(tag .. "." .. script, fn) end
        return orig(self, script, fn)
    end
    return f
end

local function text(parent, str, font)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetText(str or "")
    fs:SetJustifyH("LEFT")
    return fs
end

local function editBox(parent, width)
    local e = CF("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    return e
end

local function check(parent, label, tip)
    local c = CF("CheckButton", nil, parent, "UICheckButtonTemplate")
    c:SetSize(26, 26)
    c.label = text(parent, label, "GameFontHighlight")
    c.label:SetPoint("LEFT", c, "RIGHT", 2, 0)
    if tip then
        c:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        c:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return c
end

local function button(parent, label, w)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(label)
    -- traduções podem ser mais longas: cresce para caber o texto
    local fs = b.GetFontString and b:GetFontString()
    local tw = fs and fs:GetStringWidth()
    if tw and tw + 22 > w then b:SetWidth(tw + 22) end
    return b
end

-- Salva o campo com Enter ou ao sair dele; Esc desfaz.
local function bindSave(box, save, current)
    box:SetScript("OnEnterPressed", function(self) save(self:GetText()); self:ClearFocus() end)
    box:SetScript("OnEditFocusLost", function(self) save(self:GetText()) end)
    box:SetScript("OnEscapePressed", function(self) self:SetText(current() or ""); self:ClearFocus() end)
end

------------------------------------------------------------------------
-- doação: janelinha com o link selecionado para Ctrl+C
------------------------------------------------------------------------
local donateFrame
function NS.ShowDonate()
    local url = NS.DONATE_URL
    if not url or url == "" then return end
    if not donateFrame then
        local f = CF("Frame", "GrupoFacilDonateFrame", UIParent, "BasicFrameTemplateWithInset")
        donateFrame = f
        f:SetSize(460, 120)
        f:SetPoint("CENTER", 0, 120)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        local title = f.TitleText or text(f, "", "GameFontHighlight")
        if not f.TitleText then title:SetPoint("TOP", 0, -5) end
        title:SetText(L["Support the addon"])
        local hint = text(f, L["Press Ctrl+C to copy the link, then paste it in your browser."], "GameFontHighlight")
        hint:SetPoint("TOP", 0, -34)
        f.box = editBox(f, 400)
        f.box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
        -- só leitura: qualquer edição volta ao link
        f.box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then self:SetText(NS.DONATE_URL); self:HighlightText() end
        end)
        f.box:SetScript("OnEscapePressed", function() f:Hide() end)
        f.box:SetScript("OnEnterPressed", function() f:Hide() end)
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilDonateFrame") end -- Esc fecha
        f:Hide()
    end
    donateFrame.box:SetText(url)
    donateFrame:Show()
    donateFrame.box:SetFocus()
    donateFrame.box:HighlightText()
    NS.D.Trace("DOACAO", "janela do link aberta")
end

------------------------------------------------------------------------
-- pedido de /reload depois de trocar o idioma: o botão é seguro (macro /reload),
-- porque o jogo pode bloquear ReloadUI() chamado direto pelo addon
------------------------------------------------------------------------
local reloadPrompt
-- msg (opcional): texto da pergunta; sem ele, o aviso da troca de idioma.
function NS.ShowReloadPrompt(msg)
    msg = msg or L["Language changed. Reload the interface to apply it."]
    if InCombatLockdown() then
        NS.Print(msg .. " (/reload)")
        return
    end
    if not reloadPrompt then
        local f = CF("Frame", "GrupoFacilReloadPrompt", UIParent, "BackdropTemplate")
        reloadPrompt = f
        f:SetSize(360, 110)
        f:SetPoint("CENTER", 0, 160)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            f:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
            f:SetBackdropBorderColor(1, 0.82, 0, 1)
        end
        f.msg = text(f, "", "GameFontHighlight")
        f.msg:SetPoint("TOPLEFT", 16, -16)
        f.msg:SetPoint("TOPRIGHT", -16, -16)
        f.msg:SetJustifyH("CENTER")
        -- botão seguro: o clique roda a macro /reload pelo caminho do próprio jogo
        local go = CreateFrame("Button", "GrupoFacilReloadButton", f, "SecureActionButtonTemplate,UIPanelButtonTemplate")
        go:SetSize(150, 24)
        go:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
        go:RegisterForClicks("AnyUp", "AnyDown")
        go:SetAttribute("type", "macro")
        go:SetAttribute("macrotext", "/reload")
        f.go = go
        local later = button(f, "", 150)
        later:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
        later:SetScript("OnClick", function() f:Hide() end)
        f.later = later
        f:Hide()
    end
    local f = reloadPrompt
    f.msg:SetText(msg)
    f.go:SetText(L["Reload now"])
    f.later:SetText(L["Later"])
    f:Show()
end

------------------------------------------------------------------------
-- lista de idiomas (uma só, aberta debaixo do botão que foi clicado)
------------------------------------------------------------------------
local langMenu
function NS.ToggleLanguageMenu(owner)
    if not langMenu then
        local m = CF("Frame", "GrupoFacilLanguageMenu", UIParent, "BackdropTemplate")
        langMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            m:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        end
        m.items = {}
        for i, lang in ipairs(NS.LANGUAGES) do
            local b = CF("Button", nil, m, "UIPanelButtonTemplate")
            b:SetSize(200, 22)
            b:SetPoint("TOP", 0, -8 - (i - 1) * 24)
            b:SetText(lang.name)
            b:SetScript("OnClick", function()
                m:Hide()
                if lang.code ~= NS.Language() or GrupoFacilDB.language ~= lang.code then NS.SetLanguage(lang.code) end
            end)
            m.items[i] = { button = b, code = lang.code }
        end
        m:SetSize(216, 16 + #NS.LANGUAGES * 24)
        -- Esc fecha a lista (frame do próprio addon)
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilLanguageMenu") end
        m:Hide()
    end
    if langMenu:IsShown() and langMenu.owner == owner then langMenu:Hide() return end
    langMenu.owner = owner
    for _, it in ipairs(langMenu.items) do
        if it.code == NS.Language() then it.button:LockHighlight() else it.button:UnlockHighlight() end
    end
    langMenu:ClearAllPoints()
    langMenu:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
    langMenu:Show()
end

------------------------------------------------------------------------
-- destino da indicação: lista montada na hora (guilda, grupo e canais mudam)
------------------------------------------------------------------------
local shareMenu
function NS.ToggleShareMenu(owner, onPick)
    if not shareMenu then
        local m = CF("Frame", "GrupoFacilShareMenu", UIParent, "BackdropTemplate")
        shareMenu = m
        m:SetFrameStrata("FULLSCREEN_DIALOG")
        m:EnableMouse(true)
        m:SetClampedToScreen(true)
        if m.SetBackdrop then
            m:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
            m:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        end
        m.items = {}
        if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilShareMenu") end
        m:Hide()
    end
    local m = shareMenu
    if m:IsShown() and m.owner == owner then m:Hide() return end
    m.owner = owner
    local targets = NS.ShareTargets()
    local cur = NS.ShareTarget()
    for i, t in ipairs(targets) do
        local b = m.items[i]
        if not b then
            b = CF("Button", nil, m, "UIPanelButtonTemplate")
            b:SetSize(200, 22)
            b:SetPoint("TOP", 0, -8 - (i - 1) * 24)
            m.items[i] = b
        end
        b:SetText(t.label)
        b:SetScript("OnClick", function() m:Hide(); NS.SetShareTarget(t.key); if onPick then onPick(t) end end)
        if cur and cur.key == t.key then b:LockHighlight() else b:UnlockHighlight() end
        b:Show()
    end
    for i = #targets + 1, #m.items do m.items[i]:Hide() end
    m:SetSize(216, 16 + #targets * 24)
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    m:Show()
end

------------------------------------------------------------------------
-- conteúdo das opções (montado uma vez por lugar)
------------------------------------------------------------------------
local instances = {}

-- Seções (pedido do Fraga, 26/11): cada contexto na sua página, escolhida pelos botões do topo.
local SECTIONS = {
    { key = "general", label = "General" },
    { key = "messages", label = "Messages" },
    { key = "quests", label = "Quests" },
    { key = "invite", label = "Invite a friend" },
    { key = "help", label = "Help" },
}
NS.OPTION_SECTIONS = SECTIONS -- para teste
local lastSection = "general"

local function showSection(w, key)
    if not w.sections[key] then key = "general" end
    w.section = key
    lastSection = key
    for k, f in pairs(w.sections) do f:SetShown(k == key) end
    for k, b in pairs(w.secButtons) do
        if k == key then b:LockHighlight() else b:UnlockHighlight() end
        local fs = b.GetFontString and b:GetFontString()
        if fs then
            if k == key then fs:SetTextColor(1, 1, 1) else fs:SetTextColor(1, 0.82, 0) end
        end
    end
end

local function refreshOne(w)
    local db, char = GrupoFacilDB, GrupoFacilCharDB or {}
    if not w.msg:HasFocus() then w.msg:SetText(db.template or "") end
    w.preview:SetText(L["Goes out as: "] .. "|cffffffff" .. NS.BuildMessage() .. "|r")
    if not w.spec:HasFocus() then w.spec:SetText(char.spec or "") end
    if not w.class:HasFocus() then w.class:SetText(char.classe or "") end
    w.specHint:SetText(format(L["Empty = detect from talents (now: %s)"], NS.DetectedSpec() or L["no points"]))
    w.classHint:SetText(format(L["Empty = game name (%s)"], tostring((UnitClass("player")))))
    w.direct:SetChecked(db.sendMode ~= "preencher")
    w.prefill:SetChecked(db.sendMode == "preencher")
    w.auto:SetChecked(db.autoOpen)
    w.dock:SetChecked(db.docked)
    w.minimap:SetChecked(NS.IsMinimapButtonShown and NS.IsMinimapButtonShown())
    w.hook:SetChecked(db.hookSearch ~= false)
    w.debug:SetChecked(db.debug)
    local q = NS.Quest and NS.Quest.DB and NS.Quest.DB() or {}
    w.autoInvite:SetChecked(q.autoInvite == true)
    w.autoAccept:SetChecked(q.autoAccept ~= false)
    w.magnifier:SetChecked(q.magnifier ~= false)
    w.sharePreview:SetText("|cffffffff" .. (NS.ShareText and NS.ShareText() or "") .. "|r")
    local st = NS.ShareTarget and NS.ShareTarget()
    w.shareTarget:SetText(((st and st.label) or "") .. "  |cffffd200v|r")
    local whisper = st and st.key == "whisper"
    w.shareFriend:SetShown(whisper)
    w.shareFriendL:SetShown(whisper)
    w.lang:SetText(NS.LanguageName(NS.Language()) .. "  |cffffd200v|r")
    w.donate:SetShown(NS.DONATE_URL ~= nil and NS.DONATE_URL ~= "")
    local nb = NS.BlockedCount and NS.BlockedCount() or 0
    w.blockedLabel:SetText(format(L["Blocked players: %d"], nb))
    w.unblock:SetEnabled(nb > 0)
    w.bugInbox:SetShown(NS.bugAdmin == true)
    if NS.bugAdmin and NS.BugInbox then w.bugInbox:SetText(format(L["Bug reports (new: %d)"], #NS.BugInbox("new"))) end
end

local function refresh()
    for _, w in ipairs(instances) do
        if w.root:IsShown() then refreshOne(w) end
    end
end
NS.RefreshOptions = refresh

local function tipOn(b, title, body)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        if body then GameTooltip:AddLine(body, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function buildContent(root)
    local w = { root = root, sections = {}, secButtons = {} }
    instances[#instances + 1] = w

    local title = text(root, "GrupoFacil", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local ver = text(root, format(L["version %s  ·  /gf opens the window"], NS.VERSION), "GameFontDisableSmall")
    -- embaixo do título: na mesma linha encostava no seletor de idioma
    ver:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)

    -- idioma (na linha do título): uma lista com as línguas; trocar recarrega a interface
    w.lang = button(root, "", 200)
    w.lang:SetPoint("TOPRIGHT", -16, -14)
    w.lang:SetScript("OnClick", function(self) NS.ToggleLanguageMenu(self) end)
    w.lang:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(L["Language"])
        GameTooltip:AddLine(L["Changing the language reloads the interface."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    w.lang:SetScript("OnLeave", function() GameTooltip:Hide() end)
    local langL = text(root, L["Language"] .. ":", "GameFontNormal")
    langL:SetPoint("RIGHT", w.lang, "LEFT", -6, 0)

    -- botões das seções
    local prev
    for _, sec in ipairs(SECTIONS) do
        local b = button(root, L[sec.label], 104)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 14, -56) end
        b:SetScript("OnClick", function() showSection(w, sec.key); refreshOne(w) end)
        w.secButtons[sec.key] = b
        prev = b
        local f = CF("Frame", nil, root)
        f:SetPoint("TOPLEFT", 0, -84)
        f:SetPoint("BOTTOMRIGHT", 0, 44)
        f:Hide()
        w.sections[sec.key] = f
    end
    local line = root:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetHeight(1)
    line:SetPoint("TOPLEFT", 14, -82)
    line:SetPoint("TOPRIGHT", -14, -82)

    ------------------------------------------------------------------
    -- Mensagens: o pedido de vaga, como você se apresenta, como sai
    ------------------------------------------------------------------
    local S = w.sections.messages
    local h1 = text(S, L["Join request message"], "GameFontNormal")
    h1:SetPoint("TOPLEFT", 16, -10)
    w.msg = editBox(S, 470)
    w.msg:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 6, -6)
    w.msg:SetMaxLetters(240)
    bindSave(w.msg, function(t) NS.SetTemplate(t); refresh() end, function() return GrupoFacilDB.template end)
    local reset = button(S, L["Default"], 80)
    reset:SetPoint("LEFT", w.msg, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        NS.SetTemplate(nil)
        w.msg:SetText("")
        w.msg:ClearFocus()
        refresh()
    end)
    local hint = text(S, L["Use {class}, {spec}, {level}, {name}, {role} (your Looking For Group roles) and {activity} (the group's dungeon). Empty = English default: "] .. NS.DEFAULT_TEMPLATE)
    hint:SetPoint("TOPLEFT", w.msg, "BOTTOMLEFT", -4, -6)
    hint:SetWidth(560)
    w.preview = text(S, "")
    w.preview:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    w.preview:SetWidth(560)

    local h2 = text(S, L["How you introduce yourself (this character only)"], "GameFontNormal")
    h2:SetPoint("TOPLEFT", w.preview, "BOTTOMLEFT", 0, -20)
    local specL = text(S, L["Spec"], "GameFontHighlight")
    specL:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -12)
    w.spec = editBox(S, 180)
    w.spec:SetPoint("LEFT", specL, "LEFT", 120, 0)
    bindSave(w.spec, function(t)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        GrupoFacilCharDB.spec = (t ~= "") and t or nil
        NS.InvalidateSpec()
        NS.Refresh("options")
        refresh()
    end, function() return GrupoFacilCharDB.spec end)
    w.specHint = text(S, "")
    w.specHint:SetPoint("LEFT", w.spec, "RIGHT", 10, 0)
    local classL = text(S, L["Class name"], "GameFontHighlight")
    classL:SetPoint("TOPLEFT", specL, "BOTTOMLEFT", 0, -16)
    w.class = editBox(S, 180)
    w.class:SetPoint("LEFT", classL, "LEFT", 120, 0)
    bindSave(w.class, function(t)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        GrupoFacilCharDB.classe = (t ~= "") and t or nil
        NS.Refresh("options")
        refresh()
    end, function() return GrupoFacilCharDB.classe end)
    w.classHint = text(S, "")
    w.classHint:SetPoint("LEFT", w.class, "RIGHT", 10, 0)

    local h3 = text(S, L["Ask to join button"], "GameFontNormal")
    h3:SetPoint("TOPLEFT", classL, "BOTTOMLEFT", 0, -24)
    w.direct = check(S, L["Send the whisper straight to the leader"])
    w.direct:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", -4, -4)
    w.prefill = check(S, L["Only open the chat with the text (you press Enter)"])
    w.prefill:SetPoint("TOPLEFT", w.direct, "BOTTOMLEFT", 0, -2)
    w.direct:SetScript("OnClick", function() GrupoFacilDB.sendMode = "direto"; refresh() end)
    w.prefill:SetScript("OnClick", function() GrupoFacilDB.sendMode = "preencher"; refresh() end)

    ------------------------------------------------------------------
    -- Geral: janela, minimapa, tour, bloqueados, avançado
    ------------------------------------------------------------------
    S = w.sections.general
    local h4 = text(S, L["Window"], "GameFontNormal")
    h4:SetPoint("TOPLEFT", 16, -10)
    w.auto = check(S, L["Open together with Looking For Group"])
    w.auto:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", -4, -4)
    w.auto:SetScript("OnClick", function(self) GrupoFacilDB.autoOpen = self:GetChecked() and true or false; refresh() end)
    w.dock = check(S, L["Dock next to Looking For Group"], L["Unchecked, the window stays where you drag it."])
    w.dock:SetPoint("TOPLEFT", w.auto, "BOTTOMLEFT", 0, -2)
    w.dock:SetScript("OnClick", function(self)
        GrupoFacilDB.docked = self:GetChecked() and true or false
        if NS.Dock then NS.Dock() end
        refresh()
    end)
    w.minimap = check(S, L["Show minimap button"], L["Left-click opens the window, right-click opens these options. Drag it around the minimap."])
    w.minimap:SetPoint("TOPLEFT", w.dock, "BOTTOMLEFT", 0, -2)
    w.minimap:SetScript("OnClick", function(self) NS.SetMinimapButtonShown(self:GetChecked() and true or false); refresh() end)
    local open = button(S, L["Open GrupoFacil"], 150)
    open:SetPoint("TOPLEFT", w.minimap, "BOTTOMLEFT", 4, -8)
    open:SetScript("OnClick", function() if NS.ShowPanel then NS.ShowPanel(false) end end)

    local h4b = text(S, L["Tour"], "GameFontNormal")
    h4b:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -18)
    local tour = button(S, L["Show the tour"], 150)
    tour:SetPoint("TOPLEFT", h4b, "BOTTOMLEFT", 0, -6)
    tour:SetScript("OnClick", function()
        -- fecha a janela de opções própria para o tour aparecer por cima da janela principal
        local own = _G.GrupoFacilOptionsFrame
        if own and own:IsShown() then own:Hide() end
        if NS.RestartTour then NS.RestartTour("opções") end
        -- a janela de Options do jogo fica por cima; fechá-la por código arrisca taint
        local sp = _G.SettingsPanel
        if sp and sp:IsShown() then NS.Print(L["Close the game options to see the tour."]) end
    end)
    tipOn(tour, L["Show the tour"], L["Starts the tour of the whole addon again, from the first step: the Dungeons tab, then the Quests tab."])
    w.tour = tour

    local h4c = text(S, L["Blocked players"], "GameFontNormal")
    h4c:SetPoint("TOPLEFT", tour, "BOTTOMLEFT", 0, -18)
    w.unblock = button(S, L["Unblock all"], 150)
    w.unblock:SetPoint("TOPLEFT", h4c, "BOTTOMLEFT", 0, -6)
    w.unblock:SetScript("OnClick", function()
        NS.Unblock("all")
        NS.Print(L["blocked list cleared."])
        refresh()
    end)
    w.unblock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(format(L["Blocked players: %d"], NS.BlockedCount and NS.BlockedCount() or 0))
        GameTooltip:AddLine(L["Right-click a row in the list to block a player. /gf blocked lists them; /gf unblock <name> unblocks one."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    w.unblock:SetScript("OnLeave", function() GameTooltip:Hide() end)
    w.blockedLabel = text(S, "", "GameFontDisableSmall")
    w.blockedLabel:SetPoint("LEFT", w.unblock, "RIGHT", 8, 0)

    local h5 = text(S, L["Advanced"], "GameFontNormal")
    h5:SetPoint("TOPLEFT", w.unblock, "BOTTOMLEFT", 0, -18)
    w.hook = check(S, L["Capture the native search (applies after /reload)"],
        L["Keeps the category and activities of the last search for the Search again button. Turn off if the native search gets stuck on Searching... with the addon on."])
    w.hook:SetPoint("TOPLEFT", h5, "BOTTOMLEFT", -4, -4)
    w.hook:SetScript("OnClick", function(self)
        GrupoFacilDB.hookSearch = self:GetChecked() and true or false
        NS.D.Trace("CONFIG", "hook da busca %s (após /reload)", GrupoFacilDB.hookSearch and "ligado" or "desligado")
        refresh()
    end)

    ------------------------------------------------------------------
    -- Missões: o que antes ficava escondido na aba Missões
    ------------------------------------------------------------------
    S = w.sections.quests
    local h6 = text(S, L["Quest groups"], "GameFontNormal")
    h6:SetPoint("TOPLEFT", 16, -10)
    w.autoInvite = check(S, L["Auto-invite players who ask for the same quest"],
        L["Only players who use GrupoFacil and asked to join for a quest you also have. At most 6 invites every 10 minutes. Off by default."])
    w.autoInvite:SetPoint("TOPLEFT", h6, "BOTTOMLEFT", -4, -4)
    w.autoInvite:SetScript("OnClick", function(self)
        NS.Quest.DB().autoInvite = self:GetChecked() and true or false
        refresh()
    end)
    w.autoAccept = check(S, L["Auto-accept the invite from a leader I asked"], L["Only the leader you asked to join, for 2 minutes after asking."])
    w.autoAccept:SetPoint("TOPLEFT", w.autoInvite, "BOTTOMLEFT", 0, -2)
    w.autoAccept:SetScript("OnClick", function(self)
        NS.Quest.DB().autoAccept = self:GetChecked() and true or false
        refresh()
    end)
    w.magnifier = check(S, L["Magnifier next to quests"], L["Shows the magnifier in the objective list and in the quest details."])
    w.magnifier:SetPoint("TOPLEFT", w.autoAccept, "BOTTOMLEFT", 0, -2)
    w.magnifier:SetScript("OnClick", function(self)
        NS.Quest.DB().magnifier = self:GetChecked() and true or false
        if NS.RefreshMagnifiers then NS.RefreshMagnifiers() end
        refresh()
    end)
    local qopen = button(S, L["Open the Quests tab"], 160)
    qopen:SetPoint("TOPLEFT", w.magnifier, "BOTTOMLEFT", 4, -10)
    qopen:SetScript("OnClick", function() if NS.ShowQuestWindow then NS.ShowQuestWindow(true) end end)

    ------------------------------------------------------------------
    -- Convide um amigo (pedido do Fraga, 26/11): quanto mais gente com o addon, mais grupos se acham
    ------------------------------------------------------------------
    S = w.sections.invite
    local h7 = text(S, L["Invite a friend"], "GameFontNormal")
    h7:SetPoint("TOPLEFT", 16, -10)
    local why = text(S, L["Quest groups and the quiet addon messages only work between players who have GrupoFacil. The more friends and guildmates use it, the more groups you find."], "GameFontHighlight")
    why:SetPoint("TOPLEFT", h7, "BOTTOMLEFT", 0, -8)
    why:SetWidth(590)
    local h7b = text(S, L["Ready message"], "GameFontNormal")
    h7b:SetPoint("TOPLEFT", why, "BOTTOMLEFT", 0, -16)
    w.sharePreview = text(S, "")
    w.sharePreview:SetPoint("TOPLEFT", h7b, "BOTTOMLEFT", 0, -6)
    w.sharePreview:SetWidth(590)
    -- para onde vai: sussurro (com o nome completo do amigo), guilda, grupo, dizer, /1, /2...
    local toL = text(S, L["Send to:"], "GameFontHighlight")
    toL:SetPoint("TOPLEFT", w.sharePreview, "BOTTOMLEFT", 0, -16)
    w.shareTarget = button(S, "", 180)
    w.shareTarget:SetPoint("LEFT", toL, "LEFT", 80, 0)
    w.shareTarget:SetScript("OnClick", function(self)
        NS.ToggleShareMenu(self, function(t)
            refreshOne(w)
            if t.key == "whisper" then w.shareFriend:SetFocus() end
        end)
    end)
    tipOn(w.shareTarget, L["Send to:"], L["Whisper a friend, your guild, your group, say, or a numbered channel like /1 or /2."])
    w.shareFriendL = text(S, L["Friend:"], "GameFontHighlight")
    w.shareFriendL:SetPoint("LEFT", w.shareTarget, "RIGHT", 12, 0)
    w.shareFriend = editBox(S, 170)
    w.shareFriend:SetPoint("LEFT", w.shareFriendL, "RIGHT", 8, 0)
    w.shareFriend:SetMaxLetters(48)
    w.shareFriend:SetScript("OnEnterPressed", function(self) self:ClearFocus(); NS.RecommendAddon("opções", self:GetText()) end)
    w.shareFriend:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    tipOn(w.shareFriend, L["Friend:"], L["The full character name, with the surname (for example: Bael Bagacera)."])
    w.share = button(S, L["Recommend to a friend"], 180)
    w.share:SetPoint("TOPLEFT", toL, "BOTTOMLEFT", 0, -14)
    w.share:SetScript("OnClick", function()
        local st = NS.ShareTarget()
        NS.RecommendAddon("opções", st and st.key == "whisper" and w.shareFriend:GetText() or nil)
    end)
    tipOn(w.share, L["Recommend to a friend"], L["Puts the ready message in the chat box, already on the channel you picked. Press Enter to send it."])
    local shareHint = text(S, L["Nothing is sent until you press Enter. The message is in the language you use in GrupoFacil."], "GameFontDisableSmall")
    shareHint:SetPoint("TOPLEFT", w.share, "BOTTOMLEFT", 0, -6)
    shareHint:SetWidth(590)
    local h7c = text(S, L["Link to share outside the game"], "GameFontNormal")
    h7c:SetPoint("TOPLEFT", shareHint, "BOTTOMLEFT", 0, -16)
    local url = "https://www." .. (NS.SHARE_URL or "curseforge.com/wow/addons/grupofacil")
    w.shareLink = editBox(S, 420)
    w.shareLink:SetPoint("TOPLEFT", h7c, "BOTTOMLEFT", 6, -6)
    w.shareLink:SetText(url)
    w.shareLink:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    w.shareLink:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    w.shareLink:SetScript("OnTextChanged", function(self, user) if user then self:SetText(url); self:HighlightText() end end)
    w.shareLink:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    w.shareLink:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    tipOn(w.shareLink, L["Link to share outside the game"], L["Click the link, then Ctrl+C to copy it. Paste it in Discord, WhatsApp or wherever your friends are."])

    ------------------------------------------------------------------
    -- Ajuda: report, novidades, diagnóstico
    ------------------------------------------------------------------
    S = w.sections.help
    local h8 = text(S, L["Problems and ideas"], "GameFontNormal")
    h8:SetPoint("TOPLEFT", 16, -10)
    -- bug report: todos podem reportar; só o admin vê a caixa de entrada
    local bug = button(S, L["Report a problem"], 150)
    bug:SetPoint("TOPLEFT", h8, "BOTTOMLEFT", 0, -6)
    bug:SetScript("OnClick", function() if NS.OpenBugReport then NS.OpenBugReport() end end)
    w.bugInbox = button(S, L["Bug reports"], 150)
    w.bugInbox:SetPoint("LEFT", bug, "RIGHT", 8, 0)
    w.bugInbox:SetScript("OnClick", function() if NS.OpenBugInbox then NS.OpenBugInbox() end end)
    local news = button(S, L["What's New"], 150)
    news:SetPoint("TOPLEFT", bug, "BOTTOMLEFT", 0, -8)
    news:SetScript("OnClick", function() if NS.OpenNews then NS.OpenNews("opções") end end)
    local h9 = text(S, L["Diagnostics"], "GameFontNormal")
    h9:SetPoint("TOPLEFT", news, "BOTTOMLEFT", 0, -18)
    local diag = button(S, L["Diagnostics in chat"], 150)
    diag:SetPoint("TOPLEFT", h9, "BOTTOMLEFT", 0, -6)
    diag:SetScript("OnClick", function() NS.D.PrintSummary() end)
    local clear = button(S, L["Clear diagnostics"], 150)
    clear:SetPoint("LEFT", diag, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function() NS.D.Clear(); NS.Print(L["diagnostics cleared."]) end)
    w.debug = check(S, L["Show the diagnostic trace in chat"])
    w.debug:SetPoint("TOPLEFT", diag, "BOTTOMLEFT", -4, -6)
    w.debug:SetScript("OnClick", function(self) GrupoFacilDB.debug = self:GetChecked() and true or false; refresh() end)

    -- rodapé (todas as seções): autoria e doação
    local author = text(root, NS.AUTHOR_LINE, "GameFontNormal")
    author:SetPoint("BOTTOMLEFT", 16, 16)
    w.donate = button(root, L["Sponsor on GitHub"], 150)
    w.donate:SetPoint("LEFT", author, "RIGHT", 16, 0)
    w.donate:SetScript("OnClick", function() NS.ShowDonate() end)
    w.donate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Support the addon"])
        GameTooltip:AddLine(L["Shows the GitHub Sponsors link to copy. GrupoFacil is free and always will be."], 1, 1, 1, true)
        GameTooltip:AddLine(NS.DONATE_URL or "", 0.7, 0.7, 0.7, true)
        GameTooltip:Show()
    end)
    w.donate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    showSection(w, "general")
    root:SetScript("OnShow", function() refreshOne(w) end)
    return w
end

-- Mostra uma seção nas opções já montadas (janela própria e página do jogo).
function NS.OptionsSection(key)
    for _, w in ipairs(instances) do showSection(w, key); if w.root:IsShown() then refreshOne(w) end end
end
function NS.CurrentOptionsSection()
    local w = instances[#instances]
    return w and w.section
end

------------------------------------------------------------------------
-- 1) página em Options > AddOns
------------------------------------------------------------------------
local panel
function NS.BuildOptions()
    if panel then return end
    panel = CF("Frame", "GrupoFacilOptionsPanel")
    panel.name = "GrupoFacil"
    panel:Hide()
    buildContent(panel)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, "GrupoFacil")
        Settings.RegisterAddOnCategory(category)
        NS.settingsCategory = category
        NS.D.Trace("OPCOES", "registrado em Options > AddOns (Settings API)")
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
        NS.D.Trace("OPCOES", "registrado via InterfaceOptions_AddCategory")
    else
        NS.D.Trace("OPCOES", "nenhuma API de opções disponível")
    end
end

------------------------------------------------------------------------
-- 2) janela própria (botão Opções, minimapa, /gf options)
------------------------------------------------------------------------
local optWindow
local function buildWindow()
    local f = CF("Frame", "GrupoFacilOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
    optWindow = f
    f:SetSize(640, 520)
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
    title:SetText("GrupoFacil · " .. L["Options"])
    local content = CF("Frame", nil, f)
    content:SetPoint("TOPLEFT", 4, -22)
    content:SetPoint("BOTTOMRIGHT", -4, 4)
    f.content = buildContent(content)
    if UISpecialFrames then tinsert(UISpecialFrames, "GrupoFacilOptionsFrame") end -- Esc fecha
    f:SetScript("OnHide", function()
        if langMenu then langMenu:Hide() end
        if shareMenu then shareMenu:Hide() end
    end)
    f:Hide()
    NS.D.Trace("OPCOES", "janela de opções própria criada")
end

-- Abre (ou fecha) as opções na janela do addon, ao lado da janela principal se ela estiver aberta.
-- section (opcional): abre nessa seção; com a janela aberta em outra seção, só troca.
function NS.OpenOptions(section)
    if not optWindow then buildWindow() end
    if optWindow:IsShown() then
        if section and optWindow.content.section ~= section then
            showSection(optWindow.content, section); refreshOne(optWindow.content)
            return
        end
        optWindow:Hide()
        return
    end
    showSection(optWindow.content, section or lastSection)
    optWindow:ClearAllPoints()
    local main = _G.GrupoFacilFrame
    if main and main:IsShown() then
        optWindow:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else
        optWindow:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    end
    optWindow:Show()
end

-- Abre a página do menu do jogo (Options > AddOns > GrupoFacil).
function NS.OpenGameOptions()
    if InCombatLockdown and InCombatLockdown() then
        NS.Print(L["open the options after combat."])
        return
    end
    if NS.settingsCategory and Settings and Settings.OpenToCategory then
        local id = NS.settingsCategory.GetID and NS.settingsCategory:GetID() or NS.settingsCategory.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory and panel then
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        NS.Print(L["could not find the options screen; use the /gf commands."])
    end
end

-- Menu de addons (o botão do minimapa): esquerdo abre a janela, direito abre as opções.
function GrupoFacil_OnAddonCompartmentClick(_, mouse)
    NS.D.Call("AddonCompartment", function()
        if mouse == "RightButton" then NS.OpenOptions() else NS.TogglePanel() end
    end)
end

function GrupoFacil_OnAddonCompartmentEnter(_, menuButton)
    GameTooltip:SetOwner(menuButton, "ANCHOR_LEFT")
    GameTooltip:SetText("GrupoFacil")
    GameTooltip:AddLine(L["Click: open or close the window"], 1, 1, 1)
    GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
    GameTooltip:Show()
end

function GrupoFacil_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end
