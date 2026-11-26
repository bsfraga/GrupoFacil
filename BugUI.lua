-- GrupoFacil: janelas do bug report.
--  * Reportar um problema (todos): tipo, texto, diagnóstico opcional e a lista dos seus reports.
--  * Caixa de entrada (só admin): lista, detalhe com o texto completo, desfecho e exportar.
-- Frames próprios, filhos do UIParent; nada protegido (abre e fecha em combate). O /reload sai
-- do prompt seguro de Options.lua (NS.ShowReloadPrompt).

local ADDON, NS = ...
local L = NS.L
local format, max, min = string.format, math.max, math.min

local n = 0
local function CF(kind, name, parent, template)
    local f = CreateFrame(kind, name, parent, template)
    n = n + 1
    local tag = "Bug:" .. (name or kind) .. "#" .. n
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

local function button(parent, label, w, h)
    local b = CF("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, h or 22)
    b:SetText(label)
    local fs = b.GetFontString and b:GetFontString()
    local tw = fs and fs:GetStringWidth()
    if tw and tw + 22 > w then b:SetWidth(tw + 22) end
    return b
end

local function tooltip(owner, title, line)
    owner:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(type(title) == "function" and title() or title)
        local l = type(line) == "function" and line() or line
        if l and l ~= "" then GameTooltip:AddLine(l, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    owner:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if owner.SetMotionScriptsWhileDisabled then owner:SetMotionScriptsWhileDisabled(true) end
end

local function window(name, w, h, title)
    local f = CF("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("DIALOG")
    NS.Toplevel(f)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    local t = f.TitleText or text(f, "", "GameFontHighlight")
    if not f.TitleText then t:SetPoint("TOP", 0, -5) end
    t:SetText(title)
    if UISpecialFrames then tinsert(UISpecialFrames, name) end -- Esc fecha
    f:Hide()
    return f
end

-- caixa de texto com várias linhas dentro de uma moldura com rolagem
local function multiLine(parent, w, h)
    local bg = CF("Frame", nil, parent, "BackdropTemplate")
    bg:SetSize(w, h)
    if bg.SetBackdrop then
        bg:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
        bg:SetBackdropColor(0, 0, 0, 0.6)
    end
    local scroll = CF("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)
    local box = CF("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject("ChatFontNormal")
    box:SetWidth(w - 36)
    box:SetHeight(h - 12)
    box:SetScript("OnEscapePressed", box.ClearFocus)
    scroll:SetScrollChild(box)
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() box:SetFocus() end)
    bg.box, bg.scroll = box, scroll
    return bg
end

-- Link para copiar (o jogo não abre o navegador): caixa de uma linha, texto fixo, seleciona tudo
-- ao clicar; Ctrl+C copia. Também usada pela janela de Novidades.
function NS.MakeLinkBox(parent, w, url)
    local e = CF("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetText(url)
    e:SetCursorPosition(0)
    e:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    e:SetScript("OnMouseUp", function(self) self:SetFocus(); self:HighlightText() end)
    e:SetScript("OnTextChanged", function(self, user) if user then self:SetText(url); self:HighlightText() end end)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnEnterPressed", e.ClearFocus)
    e:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(L["Comments on CurseForge"])
        GameTooltip:AddLine(L["Click the link, then Ctrl+C to copy it and open it in your browser."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    e:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return e
end

-- O estado dos reports muda com a rede (A1, A2, F): a janela aberta se atualiza a cada 1 s.
local function autoRefresh(f, fn)
    local acc = 0
    f:SetScript("OnUpdate", function(_, elapsed)
        acc = acc + (elapsed or 0)
        if acc >= 1 then acc = 0; fn() end
    end)
end

local function fmtDate(t) return t and date("%Y-%m-%d %H:%M", t) or "" end
local function escBars(s) return (tostring(s or ""):gsub("|", "||")) end

------------------------------------------------------------------------
-- janela 1: reportar um problema
------------------------------------------------------------------------
local report
local KINDS = { { key = "bug", label = "Something is broken" }, { key = "text", label = "Wrong text or translation" }, { key = "idea", label = "Idea" } }
local MY_ROWS = 4

local function refreshReport()
    local f = report
    if not f or not f:IsShown() then return end
    local text = f.note.box:GetText() or ""
    local len = NS.Utf8Len and NS.Utf8Len(text) or #text
    f.counter:SetText(format("%d/%d", len, NS.BUG_NOTE_MAX))
    f.send:SetEnabled(text:match("%S") ~= nil and NS.bugReady == true)
    for _, k in ipairs(f.kinds) do k:SetChecked(k.key == f.kind) end
    f.diag:SetChecked(f.includeDiag)
    -- seus reports
    local list = NS.MyBugReports()
    for i = 1, MY_ROWS do
        local row, e = f.rows[i], list[i]
        if e then
            local note = NS.BugSnippetOf(e)
            local color = e.resolved and "|cff55ff55" or (e.state == "done" and "|cff88ccff" or "|cffffd200")
            row:SetText(format("|cff999999%s|r  %s%s|r%s", date("%d/%m %H:%M", e.ts), color, NS.BugStateText(e),
                note ~= "" and ("  |cff777777" .. escBars(NS.Utf8Sub(note, 40)) .. "|r") or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    f.empty:SetShown(#list == 0)
    f.more:SetShown(#list > MY_ROWS)
    if #list > MY_ROWS then f.more:SetText(format(L["+%d more: /gf bug list"], #list - MY_ROWS)) end
    -- o report só está garantido em disco depois de /reload ou logout
    f.save:SetShown(GrupoFacilDB.bugPendingSave == true)
    -- o jogo não alcança o admin (outra regra ou facção?): aviso em destaque com o link
    local reach, r = NS.BugReach()
    local unlikely = reach == "unlikely" and NS.HasPendingBugs()
    if unlikely then
        f.linkText:SetText("|cffff9933" .. format(L["Your game has not reached the author yet (tried on %d days). The author plays on the Normal (PvE) ruleset, Alliance. From another ruleset (PvP, RP...) or faction the game can't deliver it: your report stays saved, but please also leave a comment on CurseForge:"],
            math.max(1, r.missDays or 0)) .. "|r")
    else
        f.linkText:SetText(L["Playing on another ruleset (PvP, RP...) or faction? The game can't deliver reports there. Leave a comment on CurseForge:"])
    end
    f.linkWarn:SetShown(unlikely)
    -- admin: atalho para a caixa de entrada
    if NS.bugAdmin then
        f.inbox:SetText(format(L["Inbox (new: %d)"], #NS.BugInbox("new")))
        local fs = f.inbox.GetFontString and f.inbox:GetFontString()
        local tw = fs and fs:GetStringWidth()
        if tw then f.inbox:SetWidth(max(140, tw + 22)) end
        f.inbox:Show()
    else
        f.inbox:Hide()
    end
end

-- Layout: tudo encadeado de cima para baixo e medido pelo texto já traduzido. Rótulos longos
-- (alemão, francês) quebram em mais linhas e empurram o resto para baixo em vez de se sobrepor;
-- os tipos passam para a linha de baixo quando não cabem; a janela cresce até caber o conteúdo.
local W, PAD = 540, 16
local INNER = W - 2 * PAD

local function heightOf(fs, minH)
    local h = fs.GetStringHeight and fs:GetStringHeight() or 0
    return max(minH or 12, h or 0)
end

local function buildReport()
    local f = window("GrupoFacilBugFrame", W, 500, "GrupoFacil · " .. L["Report a problem"])
    report = f
    f.kind, f.includeDiag = "bug", true
    local used = 32 -- barra de título

    local intro = text(f, L["Tell the author what went wrong. The report stays saved on your computer and goes to the author the next time you are both online. It is only deleted after the author confirms it was saved."])
    intro:SetPoint("TOPLEFT", PAD, -32)
    intro:SetWidth(INNER)
    intro:SetJustifyV("TOP")
    local ih = heightOf(intro)
    used = used + ih

    -- tipo: rótulo e as três opções em fluxo; o que não cabe na linha desce para a próxima
    local kl = text(f, L["What kind?"], "GameFontNormal")
    kl:SetPoint("TOPLEFT", intro, "BOTTOMLEFT", 0, -14)
    used = used + 14
    f.kinds, f.kindLabels = {}, {}
    local x, row = (kl:GetStringWidth() or 0) + 8, 0
    for _, k in ipairs(KINDS) do
        local c = CF("CheckButton", nil, f, "UICheckButtonTemplate")
        c:SetSize(24, 24)
        c.key = k.key
        local l = text(f, L[k.label], "GameFontHighlightSmall")
        local need = 24 + (l:GetStringWidth() or 0)
        if x > 0 and x + need > INNER then row, x = row + 1, 0 end
        c:SetPoint("LEFT", kl, "LEFT", x - 4, -row * 24)
        l:SetPoint("LEFT", c, "RIGHT", 0, 0)
        c:SetScript("OnClick", function() f.kind = k.key; refreshReport() end)
        f.kinds[#f.kinds + 1] = c
        f.kindLabels[#f.kindLabels + 1] = l
        x = x + need + 14
    end
    used = used + 12 + row * 24 + 6

    local nl = text(f, L["What happened? What did you expect? Steps help a lot."], "GameFontNormal")
    nl:SetPoint("TOPLEFT", kl, "BOTTOMLEFT", 0, -(row * 24 + 6 + 12))
    nl:SetWidth(INNER)
    local nh = heightOf(nl)
    used = used + 12 + nh
    f.note = multiLine(f, INNER, 140)
    f.note:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", 0, -6)
    f.note.box:SetMaxLetters(NS.BUG_NOTE_MAX)
    f.note.box:SetScript("OnTextChanged", function() refreshReport() end)
    f.counter = text(f, "", "GameFontDisableSmall")
    f.counter:SetPoint("TOPRIGHT", f.note, "BOTTOMRIGHT", 0, -4)
    used = used + 6 + 140

    -- diagnóstico: o texto pode quebrar em 2 ou 3 linhas; o botão Enviar vem depois da mais baixa
    f.diag = CF("CheckButton", nil, f, "UICheckButtonTemplate")
    f.diag:SetSize(24, 24)
    local dl = text(f, L["Include the addon version, settings and recent addon events (no other players' names)"], "GameFontHighlightSmall")
    dl:SetWidth(INNER - 28)
    local dh = heightOf(dl)
    local extra = max(0, (dh - 24) / 2)
    f.diag:SetPoint("TOPLEFT", f.note, "BOTTOMLEFT", -4, -(20 + extra))
    dl:SetPoint("LEFT", f.diag, "RIGHT", 0, 0)
    f.diag:SetScript("OnClick", function(self) f.includeDiag = self:GetChecked() and true or false; refreshReport() end)
    used = used + 20 + max(24, dh)

    f.send = button(f, L["Send report"], 140)
    f.send:SetPoint("TOPLEFT", f.diag, "BOTTOMLEFT", 4, -(10 + extra))
    f.send:SetScript("OnClick", function()
        local id, why = NS.SubmitBug(f.note.box:GetText(), f.kind, f.includeDiag)
        if id and NS.MaybeWarnBugReach then NS.MaybeWarnBugReach() end
        if id then
            f.note.box:SetText("")
            f.note.box:ClearFocus()
            f.status:SetText("|cff55ff55" .. format(L["Report %s created."], id) .. "|r")
            GrupoFacilDB.bugIntroSeen = true
        else
            f.status:SetText("|cffff6060" .. tostring(why) .. "|r")
        end
        refreshReport()
    end)
    tooltip(f.send, L["Send report"], L["The report is queued and sent automatically when the author is online. You don't need to keep this window open."])
    f.status = text(f, "", "GameFontHighlightSmall")
    -- um ponto só (LEFT + RIGHT na janela puxava o texto para a altura do meio da janela)
    f.status:SetPoint("LEFT", f.send, "RIGHT", 10, 0)
    f.status:SetWidth(INNER - f.send:GetWidth() - 10)
    f.status:SetWordWrap(false)
    used = used + 10 + 22

    f.save = button(f, L["Save now (/reload)"], 150)
    f.save:SetPoint("TOPLEFT", f.send, "BOTTOMLEFT", 0, -6)
    f.save:SetScript("OnClick", function()
        NS.ShowReloadPrompt(L["The game writes your report to disk only when the interface reloads or you log out. Reload now?"])
    end)
    tooltip(f.save, L["Save now (/reload)"], L["If the game crashes before a reload or logout, a new report is lost. Reloading now writes it to disk."])
    used = used + 6 + 22

    -- "Seus reports"; o admin tem o atalho da caixa de entrada à direita desta mesma linha
    local yl = text(f, L["Your reports"], "GameFontNormal")
    yl:SetPoint("TOPLEFT", f.save, "BOTTOMLEFT", 0, -16)
    f.inbox = button(f, format(L["Inbox (new: %d)"], 0), 140, 20)
    -- largura pelo texto já na criação ("Reports de bug (novos: 0)" passava do botão de 140)
    local ifs = f.inbox.GetFontString and f.inbox:GetFontString()
    local itw = ifs and ifs:GetStringWidth()
    if itw then f.inbox:SetWidth(max(140, itw + 22)) end
    f.inbox:SetPoint("RIGHT", yl, "LEFT", INNER, 0)
    f.inbox:SetScript("OnClick", function() NS.OpenBugInbox() end)
    f.inbox:Hide()
    used = used + 16 + 12
    f.rows = {}
    for i = 1, MY_ROWS do
        local r = text(f, "", "GameFontHighlightSmall")
        r:SetPoint("TOPLEFT", yl, "BOTTOMLEFT", 4, -10 - (i - 1) * 16)
        r:SetWidth(INNER - 8)
        r:SetWordWrap(false)
        f.rows[i] = r
    end
    f.empty = text(f, L["None yet."], "GameFontDisableSmall")
    f.empty:SetPoint("TOPLEFT", yl, "BOTTOMLEFT", 4, -10)
    f.more = text(f, "", "GameFontDisableSmall")
    f.more:SetPoint("TOPLEFT", f.rows[MY_ROWS], "BOTTOMLEFT", 0, -2)
    used = used + 10 + MY_ROWS * 16 + 2 + 12

    -- caminho alternativo: comentários no CurseForge (sempre à mostra; em destaque quando o jogo
    -- nunca alcançou o admin). A altura reservada é a do texto mais longo dos dois.
    f.linkText = text(f, "", "GameFontHighlightSmall")
    f.linkText:SetPoint("TOPLEFT", yl, "BOTTOMLEFT", 0, -(10 + MY_ROWS * 16 + 2 + 12 + 12))
    f.linkText:SetWidth(INNER)
    f.linkText:SetJustifyV("TOP")
    local lh = 0
    for _, s in ipairs({ L["Playing on another ruleset (PvP, RP...) or faction? The game can't deliver reports there. Leave a comment on CurseForge:"],
        format(L["Your game has not reached the author yet (tried on %d days). The author plays on the Normal (PvE) ruleset, Alliance. From another ruleset (PvP, RP...) or faction the game can't deliver it: your report stays saved, but please also leave a comment on CurseForge:"], 99) }) do
        f.linkText:SetText(s)
        lh = max(lh, heightOf(f.linkText))
    end
    f.linkText:SetHeight(lh)
    f.link = NS.MakeLinkBox(f, INNER - 6, NS.BUG_COMMENTS_URL)
    f.link:SetPoint("TOPLEFT", f.linkText, "BOTTOMLEFT", 6, -4)
    f.linkWarn = f:CreateTexture(nil, "BACKGROUND")
    f.linkWarn:SetColorTexture(0.6, 0.3, 0, 0.25)
    f.linkWarn:SetPoint("TOPLEFT", f.linkText, "TOPLEFT", -6, 4)
    f.linkWarn:SetPoint("BOTTOMRIGHT", f.link, "BOTTOMRIGHT", 4, -4)
    f.linkWarn:Hide()
    used = used + 12 + lh + 4 + 20

    f:SetHeight(max(460, used + 16))
    f:SetScript("OnShow", function() refreshReport() end)
    autoRefresh(f, refreshReport)
end

function NS.OpenBugReport()
    if not report then buildReport() end
    if report:IsShown() then report:Raise() return end
    report:ClearAllPoints()
    local main = _G.GrupoFacilFrame
    if main and main:IsShown() then report:SetPoint("TOPLEFT", main, "TOPRIGHT", 4, 0)
    else report:SetPoint("CENTER", UIParent, "CENTER", 0, 40) end
    report:Show()
    report.note.box:SetFocus()
    GrupoFacilDB.bugWindowOpened = true -- apaga o brilho do ícone na janela principal
    NS.D.Trace("BUG", "janela de report aberta")
end
function NS.BugReportFrame() return report end

------------------------------------------------------------------------
-- janela 2: caixa de entrada do admin
------------------------------------------------------------------------
local inbox
local IN_ROWS = 12
local STATUS_COLOR = { new = "|cffffd200", triaged = "|cff88ccff", fixed = "|cff55ff55", wontfix = "|cffaaaaaa", dup = "|cffaaaaaa" }

local function selected() return inbox.selected and GrupoFacilDB.inbox[inbox.selected] end

local function showDetail()
    local f = inbox
    local e = selected()
    if f.exporting then
        f.head:SetText(L["Export: every new report, oldest first. Ctrl+A, Ctrl+C and paste it in your conversation with Claude."])
        f.body.box:SetText(escBars(NS.BugExportText("new")))
        f.body.box.readOnly = f.body.box:GetText()
        for _, b in ipairs(f.actions) do b:SetEnabled(false) end
        f.noteBox:SetEnabled(false)
        return
    end
    if not e then
        f.head:SetText(L["Pick a report on the left."])
        f.body.box:SetText("")
        f.body.box.readOnly = ""
        for _, b in ipairs(f.actions) do b:SetEnabled(false) end
        f.noteBox:SetEnabled(false)
        return
    end
    local onDisk = NS.bugDurable and NS.bugDurable[e.id]
    f.head:SetText(format("%s  ·  %s  ·  %s  ·  %s%s|r%s", e.id, escBars(e.from), fmtDate(e.recvAt), STATUS_COLOR[e.status] or "",
        NS.BugStatusText(e.status), onDisk and "" or ("  |cffff8800" .. L["(not on disk yet)"] .. "|r")))
    local body = escBars(e.body)
    if e.note and e.note ~= "" then body = body .. "\n--- " .. L["your note"] .. ": " .. escBars(e.note) end
    f.body.box:SetText(body)
    f.body.box.readOnly = body
    f.body.scroll:SetVerticalScroll(0)
    for _, b in ipairs(f.actions) do b:SetEnabled(true) end
    f.noteBox:SetEnabled(true)
    if not f.noteBox:HasFocus() then f.noteBox:SetText(e.note or "") end
end

local function refreshInbox()
    local f = inbox
    if not f or not f:IsShown() then return end
    local list = NS.BugInbox(f.filter == "new" and "new" or nil)
    f.list = list
    f.offset = max(0, min(f.offset or 0, max(0, #list - IN_ROWS)))
    f.newBtn:SetText(format(L["New (%d)"], #NS.BugInbox("new")))
    f.allBtn:SetText(format(L["All (%d)"], #NS.BugInbox()))
    if f.filter == "new" then f.newBtn:LockHighlight(); f.allBtn:UnlockHighlight() else f.allBtn:LockHighlight(); f.newBtn:UnlockHighlight() end
    for i = 1, IN_ROWS do
        local r, e = f.rows[i], list[f.offset + i]
        r.id = e and e.id
        if e then
            local note = NS.BugNoteOf(e.body)
            r.label:SetText(format("%s%s|r  %s  |cff999999%s|r\n|cffcccccc%s|r", STATUS_COLOR[e.status] or "", NS.BugStatusText(e.status),
                escBars(e.from), date("%d/%m %H:%M", e.recvAt), escBars(note ~= "" and NS.Utf8Sub(note, 50) or ("(" .. L["no text"] .. ")"))))
            if e.id == f.selected and not f.exporting then r:LockHighlight() else r:UnlockHighlight() end
            r:Show()
        else
            r:Hide()
        end
    end
    f.emptyFS:SetShown(#list == 0)
    f.page:SetText(#list > 0 and format(L["%d-%d of %d"], f.offset + 1, min(#list, f.offset + IN_ROWS), #list) or "")
    local nd = NS.BugNotOnDisk()
    f.disk:SetText(nd > 0 and ("|cffff8800" .. format(L["%d not on disk yet: players keep them until you reload."], nd) .. "|r") or ("|cff55ff55" .. L["All saved on disk."] .. "|r"))
    f.flush:SetEnabled(nd > 0)
    f.accept:SetChecked(GrupoFacilDB.acceptReports ~= false)
    showDetail()
end

local ACTIONS = { { "fixed", "Fixed" }, { "wontfix", "Won't fix" }, { "dup", "Duplicate" }, { "triaged", "Triaged" } }

local function buildInbox()
    local f = window("GrupoFacilBugInbox", 780, 520, "GrupoFacil · " .. L["Bug reports"])
    inbox = f
    f.filter, f.offset = "new", 0

    f.newBtn = button(f, L["New (%d)"], 90, 20)
    f.newBtn:SetPoint("TOPLEFT", 12, -30)
    f.newBtn:SetScript("OnClick", function() f.filter = "new"; f.offset = 0; refreshInbox() end)
    f.allBtn = button(f, L["All (%d)"], 90, 20)
    f.allBtn:SetPoint("LEFT", f.newBtn, "RIGHT", 4, 0)
    f.allBtn:SetScript("OnClick", function() f.filter = "all"; f.offset = 0; refreshInbox() end)
    f.export = button(f, L["Export new"], 110, 20)
    f.export:SetPoint("LEFT", f.allBtn, "RIGHT", 12, 0)
    f.export:SetScript("OnClick", function()
        f.exporting = not f.exporting
        refreshInbox()
        if f.exporting then f.body.box:SetFocus(); f.body.box:HighlightText() end
    end)
    tooltip(f.export, L["Export new"], L["Shows every new report as text to copy and paste in a conversation with Claude."])

    f.accept = CF("CheckButton", nil, f, "UICheckButtonTemplate")
    f.accept:SetSize(24, 24)
    f.accept:SetPoint("TOPRIGHT", -190, -28)
    local al = text(f, L["Accept new reports"], "GameFontHighlightSmall")
    al:SetPoint("LEFT", f.accept, "RIGHT", 0, 0)
    f.accept:SetScript("OnClick", function(self) GrupoFacilDB.acceptReports = self:GetChecked() and true or false; refreshInbox() end)
    tooltip(f.accept, L["Accept new reports"], L["Unchecked, players keep their reports queued and try again later."])

    -- lista
    f.rows = {}
    for i = 1, IN_ROWS do
        local r = CF("Button", nil, f)
        r:SetSize(300, 32)
        r:SetPoint("TOPLEFT", 12, -58 - (i - 1) * 34)
        r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        r.label = text(r, "", "GameFontHighlightSmall")
        r.label:SetPoint("TOPLEFT", 4, -2)
        r.label:SetPoint("BOTTOMRIGHT", -4, 2)
        r.label:SetWordWrap(true)
        r:SetScript("OnClick", function(self)
            f.exporting = false
            f.selected = self.id
            f.noteBox:SetText((selected() or {}).note or "")
            refreshInbox()
        end)
        f.rows[i] = r
    end
    f.emptyFS = text(f, L["No reports here."], "GameFontDisableSmall")
    f.emptyFS:SetPoint("TOPLEFT", 16, -62)
    local up = button(f, "<", 26, 20)
    up:SetPoint("BOTTOMLEFT", 12, 40)
    up:SetScript("OnClick", function() f.offset = f.offset - IN_ROWS; refreshInbox() end)
    local down = button(f, ">", 26, 20)
    down:SetPoint("LEFT", up, "RIGHT", 2, 0)
    down:SetScript("OnClick", function() f.offset = f.offset + IN_ROWS; refreshInbox() end)
    f.up, f.down = up, down
    f.page = text(f, "", "GameFontHighlightSmall")
    f.page:SetPoint("LEFT", down, "RIGHT", 8, 0)

    -- detalhe
    f.head = text(f, "", "GameFontNormal")
    f.head:SetPoint("TOPLEFT", 324, -58)
    f.head:SetWidth(440)
    f.head:SetWordWrap(true)
    f.body = multiLine(f, 444, 300)
    f.body:SetPoint("TOPLEFT", 322, -92)
    -- só leitura: qualquer edição volta ao texto (Ctrl+C continua funcionando)
    f.body.box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and self.readOnly then self:SetText(self.readOnly) end
    end)
    local nl = text(f, L["Note to the player (optional):"], "GameFontHighlightSmall")
    nl:SetPoint("TOPLEFT", f.body, "BOTTOMLEFT", 2, -8)
    f.noteBox = CF("EditBox", nil, f, "InputBoxTemplate")
    -- o rótulo traduzido pode ser longo: a caixa fica com o resto da largura (até 250)
    f.noteBox:SetSize(math.max(120, math.min(250, 780 - 18 - 324 - 8 - (nl:GetStringWidth() or 0))), 20)
    f.noteBox:SetAutoFocus(false)
    f.noteBox:SetMaxLetters(120)
    f.noteBox:SetPoint("LEFT", nl, "RIGHT", 8, 0)
    f.noteBox:SetScript("OnEnterPressed", f.noteBox.ClearFocus)
    f.noteBox:SetScript("OnEscapePressed", f.noteBox.ClearFocus)
    f.actions = {}
    local prev
    for _, a in ipairs(ACTIONS) do
        local b = button(f, L[a[2]], 100, 22)
        if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", nl, "BOTTOMLEFT", -2, -10) end
        b.status = a[1]
        b:SetScript("OnClick", function()
            local e = selected()
            if not e then return end
            NS.ResolveBug(e.id, a[1], f.noteBox:GetText())
            f.noteBox:ClearFocus()
            refreshInbox()
        end)
        f.actions[#f.actions + 1] = b
        prev = b
    end
    tooltip(f.actions[1], L["Fixed"], L["Marks the report and tells the player (now if online, or the next time you are both online)."])
    tooltip(f.actions[4], L["Triaged"], L["Only for you: the player is not told."])

    f.disk = text(f, "", "GameFontHighlightSmall")
    f.disk:SetPoint("BOTTOMLEFT", 12, 16)
    f.disk:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -190, 16)
    f.disk:SetWordWrap(false)
    f.flush = button(f, L["Save to disk (/reload)"], 170, 22)
    f.flush:SetPoint("BOTTOMRIGHT", -12, 12)
    f.flush:SetScript("OnClick", function()
        NS.ShowReloadPrompt(L["Reload the interface to write the bug reports to disk? Players are told only after that."])
    end)
    tooltip(f.flush, L["Save to disk (/reload)"], L["A player deletes a report only after it survived a reload on your side. Reloading confirms everything received so far."])

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) f.offset = f.offset - delta * 3; refreshInbox() end)
    f:SetScript("OnShow", function() refreshInbox() end)
    autoRefresh(f, function() if not f.body.box:HasFocus() and not f.noteBox:HasFocus() then refreshInbox() end end)
end

function NS.OpenBugInbox(mode)
    if not NS.bugAdmin then return end
    if not inbox then buildInbox() end
    inbox.exporting = (mode == "export")
    if not inbox:IsShown() then
        inbox:ClearAllPoints()
        inbox:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
        inbox:Show()
    else
        refreshInbox()
    end
    if inbox.exporting then inbox.body.box:SetFocus(); inbox.body.box:HighlightText() end
end
function NS.BugInboxFrame() return inbox end

function NS.RefreshBugUI()
    refreshReport()
    refreshInbox()
    if NS.RefreshOptions then NS.RefreshOptions() end
end

function NS.Utf8Len(s) local _, c = tostring(s or ""):gsub("[^\128-\191]", ""); return c end
