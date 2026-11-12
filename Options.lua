-- GrupoFacil: opções. O mesmo conteúdo é montado em dois lugares:
--  * a página em Options > AddOns > GrupoFacil (Settings API)
--  * a janela própria do addon, aberta pelo botão Opções, pelo minimapa e por /gf options
-- Uma mudança em qualquer um dos dois atualiza o outro.

local ADDON, NS = ...
local L = NS.L
local format = string.format

-- Link de doação. Vazio = o botão Donate não aparece.
NS.DONATE_URL = ""

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
        f:Hide()
    end
    donateFrame.box:SetText(url)
    donateFrame:Show()
    donateFrame.box:SetFocus()
    donateFrame.box:HighlightText()
    NS.D.Trace("DOACAO", "janela do link aberta")
end

------------------------------------------------------------------------
-- conteúdo das opções (montado uma vez por lugar)
------------------------------------------------------------------------
local instances = {}

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
    w.langEN:SetChecked(NS.Language() == "en")
    w.langPT:SetChecked(NS.Language() == "pt")
    w.donate:SetShown(NS.DONATE_URL ~= nil and NS.DONATE_URL ~= "")
end

local function refresh()
    for _, w in ipairs(instances) do
        if w.root:IsShown() then refreshOne(w) end
    end
end
NS.RefreshOptions = refresh

local function buildContent(root)
    local w = { root = root }
    instances[#instances + 1] = w

    local title = text(root, "GrupoFacil", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    local ver = text(root, format(L["version %s  ·  /gf opens the window"], NS.VERSION), "GameFontDisableSmall")
    ver:SetPoint("LEFT", title, "RIGHT", 10, 0)

    -- idioma (na linha do título): trocar recarrega a interface
    w.langPT = check(root, "Português (Brasil)", L["Changing the language reloads the interface."])
    w.langPT:SetPoint("TOPRIGHT", -170, -10)
    w.langEN = check(root, "English", L["Changing the language reloads the interface."])
    w.langEN:SetPoint("RIGHT", w.langPT, "LEFT", -80, 0)
    local langL = text(root, L["Language"] .. ":", "GameFontNormal")
    langL:SetPoint("RIGHT", w.langEN, "LEFT", -4, 0)
    w.langEN:SetScript("OnClick", function(self)
        if NS.Language() == "en" then self:SetChecked(true) return end
        NS.SetLanguage("en")
    end)
    w.langPT:SetScript("OnClick", function(self)
        if NS.Language() == "pt" then self:SetChecked(true) return end
        NS.SetLanguage("pt")
    end)

    -- mensagem
    local h1 = text(root, L["Join request message"], "GameFontNormal")
    h1:SetPoint("TOPLEFT", 16, -56)
    w.msg = editBox(root, 470)
    w.msg:SetPoint("TOPLEFT", h1, "BOTTOMLEFT", 6, -6)
    w.msg:SetMaxLetters(240)
    bindSave(w.msg, function(t) NS.SetTemplate(t); refresh() end, function() return GrupoFacilDB.template end)
    local reset = button(root, L["Default"], 80)
    reset:SetPoint("LEFT", w.msg, "RIGHT", 8, 0)
    reset:SetScript("OnClick", function()
        NS.SetTemplate(nil)
        w.msg:SetText("")
        w.msg:ClearFocus()
        refresh()
    end)
    local hint = text(root, L["Use {class}, {spec}, {level} and {name}. Empty = English default: "] .. NS.DEFAULT_TEMPLATE)
    hint:SetPoint("TOPLEFT", w.msg, "BOTTOMLEFT", -4, -6)
    hint:SetWidth(560)
    w.preview = text(root, "")
    w.preview:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -6)
    w.preview:SetWidth(560)

    -- spec e classe (por personagem)
    local h2 = text(root, L["How you introduce yourself (this character only)"], "GameFontNormal")
    h2:SetPoint("TOPLEFT", w.preview, "BOTTOMLEFT", 0, -20)
    local specL = text(root, "Spec", "GameFontHighlight")
    specL:SetPoint("TOPLEFT", h2, "BOTTOMLEFT", 0, -12)
    w.spec = editBox(root, 180)
    w.spec:SetPoint("LEFT", specL, "LEFT", 120, 0)
    bindSave(w.spec, function(t)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        GrupoFacilCharDB.spec = (t ~= "") and t or nil
        NS.InvalidateSpec()
        NS.Refresh("options")
        refresh()
    end, function() return GrupoFacilCharDB.spec end)
    w.specHint = text(root, "")
    w.specHint:SetPoint("LEFT", w.spec, "RIGHT", 10, 0)

    local classL = text(root, L["Class name"], "GameFontHighlight")
    classL:SetPoint("TOPLEFT", specL, "BOTTOMLEFT", 0, -16)
    w.class = editBox(root, 180)
    w.class:SetPoint("LEFT", classL, "LEFT", 120, 0)
    bindSave(w.class, function(t)
        t = t:gsub("^%s+", ""):gsub("%s+$", "")
        GrupoFacilCharDB.classe = (t ~= "") and t or nil
        NS.Refresh("options")
        refresh()
    end, function() return GrupoFacilCharDB.classe end)
    w.classHint = text(root, "")
    w.classHint:SetPoint("LEFT", w.class, "RIGHT", 10, 0)

    -- envio
    local h3 = text(root, L["Ask to join button"], "GameFontNormal")
    h3:SetPoint("TOPLEFT", classL, "BOTTOMLEFT", 0, -24)
    w.direct = check(root, L["Send the whisper straight to the leader"])
    w.direct:SetPoint("TOPLEFT", h3, "BOTTOMLEFT", -4, -4)
    w.prefill = check(root, L["Only open the chat with the text (you press Enter)"])
    w.prefill:SetPoint("TOPLEFT", w.direct, "BOTTOMLEFT", 0, -2)
    w.direct:SetScript("OnClick", function() GrupoFacilDB.sendMode = "direto"; refresh() end)
    w.prefill:SetScript("OnClick", function() GrupoFacilDB.sendMode = "preencher"; refresh() end)

    -- janela
    local h4 = text(root, L["Window"], "GameFontNormal")
    h4:SetPoint("TOPLEFT", w.prefill, "BOTTOMLEFT", 4, -14)
    w.auto = check(root, L["Open together with Looking For Group"])
    w.auto:SetPoint("TOPLEFT", h4, "BOTTOMLEFT", -4, -4)
    w.auto:SetScript("OnClick", function(self) GrupoFacilDB.autoOpen = self:GetChecked() and true or false; refresh() end)
    w.dock = check(root, L["Dock next to Looking For Group"], L["Unchecked, the window stays where you drag it."])
    w.dock:SetPoint("TOPLEFT", w.auto, "BOTTOMLEFT", 0, -2)
    w.dock:SetScript("OnClick", function(self)
        GrupoFacilDB.docked = self:GetChecked() and true or false
        if NS.Dock then NS.Dock() end
        refresh()
    end)
    w.minimap = check(root, L["Show minimap button"], L["Left-click opens the window, right-click opens these options. Drag it around the minimap."])
    w.minimap:SetPoint("LEFT", w.auto, "RIGHT", 300, 0)
    w.minimap:SetScript("OnClick", function(self) NS.SetMinimapButtonShown(self:GetChecked() and true or false); refresh() end)

    -- avançado
    local h5 = text(root, L["Advanced"], "GameFontNormal")
    h5:SetPoint("TOPLEFT", w.dock, "BOTTOMLEFT", 4, -14)
    w.hook = check(root, L["Capture the native search (applies after /reload)"],
        L["Keeps the category and activities of the last search for the Search again button. Turn off if the native search gets stuck on Searching... with the addon on."])
    w.hook:SetPoint("TOPLEFT", h5, "BOTTOMLEFT", -4, -4)
    w.hook:SetScript("OnClick", function(self)
        GrupoFacilDB.hookSearch = self:GetChecked() and true or false
        NS.D.Trace("CONFIG", "hook da busca %s (após /reload)", GrupoFacilDB.hookSearch and "ligado" or "desligado")
        refresh()
    end)
    w.debug = check(root, L["Show the diagnostic trace in chat"])
    w.debug:SetPoint("TOPLEFT", w.hook, "BOTTOMLEFT", 0, -2)
    w.debug:SetScript("OnClick", function(self) GrupoFacilDB.debug = self:GetChecked() and true or false; refresh() end)

    local open = button(root, L["Open GrupoFacil"], 150)
    open:SetPoint("TOPLEFT", w.debug, "BOTTOMLEFT", 4, -16)
    open:SetScript("OnClick", function() if NS.ShowPanel then NS.ShowPanel(false) end end)
    local diag = button(root, L["Diagnostics in chat"], 150)
    diag:SetPoint("LEFT", open, "RIGHT", 8, 0)
    diag:SetScript("OnClick", function() NS.D.PrintSummary() end)
    local clear = button(root, L["Clear diagnostics"], 150)
    clear:SetPoint("LEFT", diag, "RIGHT", 8, 0)
    clear:SetScript("OnClick", function() NS.D.Clear(); NS.Print(L["diagnostics cleared."]) end)

    -- autoria e doação
    local author = text(root, NS.AUTHOR_LINE, "GameFontNormal")
    author:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -22)
    w.donate = button(root, L["Donate"], 110)
    w.donate:SetPoint("LEFT", author, "RIGHT", 16, 0)
    w.donate:SetScript("OnClick", function() NS.ShowDonate() end)
    w.donate:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Support the addon"])
        GameTooltip:AddLine(NS.DONATE_URL or "", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    w.donate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    root:SetScript("OnShow", function() refreshOne(w) end)
    return w
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
    f:SetSize(640, 600)
    f:SetFrameStrata("DIALOG")
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
    buildContent(content)
    f:Hide()
    NS.D.Trace("OPCOES", "janela de opções própria criada")
end

-- Abre (ou fecha) as opções na janela do addon, ao lado da janela principal se ela estiver aberta.
function NS.OpenOptions()
    if not optWindow then buildWindow() end
    if optWindow:IsShown() then optWindow:Hide() return end
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
