-- Widgets do cliente simulado: Frame, Button, CheckButton, EditBox, ScrollFrame, Slider,
-- GameTooltip, FontString e Texture. O estado interno fica fora da tabela do frame (como no
-- jogo, onde ele fica no userdata), então o addon só enxerga os campos que ele mesmo grava.
--
-- Fidelidade que importa para os testes:
--  * método inexistente dá erro ("attempt to call method"), igual ao cliente;
--  * SetScript com um script que o tipo não tem dá erro;
--  * RegisterEvent com evento desconhecido dá erro;
--  * OnShow/OnHide seguem a visibilidade real (pai escondido esconde os filhos);
--  * CheckButton troca o estado antes do OnClick; botão desabilitado ignora Click();
--  * tamanho e posição saem das âncoras (SetPoint) quando o tamanho não foi fixado;
--  * frame protegido (template Secure*) não pode ser mostrado/escondido/movido em combate
--    (ADDON_ACTION_BLOCKED), e um frame com filho protegido também fica protegido.
local M = {}

local SCRIPTS = {
    Frame = { OnEvent = 1, OnUpdate = 1, OnShow = 1, OnHide = 1, OnEnter = 1, OnLeave = 1, OnMouseDown = 1,
        OnMouseUp = 1, OnMouseWheel = 1, OnDragStart = 1, OnDragStop = 1, OnSizeChanged = 1, OnLoad = 1,
        OnKeyDown = 1, OnKeyUp = 1, OnReceiveDrag = 1, OnAttributeChanged = 1 },
}
SCRIPTS.Button = setmetatable({ OnClick = 1, PreClick = 1, PostClick = 1, OnDoubleClick = 1 }, { __index = SCRIPTS.Frame })
SCRIPTS.CheckButton = SCRIPTS.Button
SCRIPTS.EditBox = setmetatable({ OnTextChanged = 1, OnEnterPressed = 1, OnEscapePressed = 1, OnEditFocusLost = 1,
    OnEditFocusGained = 1, OnTabPressed = 1, OnChar = 1, OnCursorChanged = 1, OnTextSet = 1, OnSpacePressed = 1 },
    { __index = SCRIPTS.Frame })
SCRIPTS.ScrollFrame = setmetatable({ OnVerticalScroll = 1, OnHorizontalScroll = 1, OnScrollRangeChanged = 1 }, { __index = SCRIPTS.Frame })
SCRIPTS.Slider = setmetatable({ OnValueChanged = 1, OnMinMaxChanged = 1 }, { __index = SCRIPTS.Frame })
SCRIPTS.GameTooltip = SCRIPTS.Frame

local POINTS = {
    TOPLEFT = { "L", "T" }, TOP = { "C", "T" }, TOPRIGHT = { "R", "T" },
    LEFT = { "L", "M" }, CENTER = { "C", "M" }, RIGHT = { "R", "M" },
    BOTTOMLEFT = { "L", "B" }, BOTTOM = { "C", "B" }, BOTTOMRIGHT = { "R", "B" },
}

-- Largura aproximada do texto: 6 px por caractere visível, 14 px por ícone |T|t ou |A|a.
-- (Para os testes, os ícones de role viram {tank}, {healer} e {dps}.)
function M.visibleText(s, keepIcons)
    s = tostring(s or "")
    s = s:gsub("||", "\1")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    if keepIcons then s = s:gsub("|T.-|t", "\2"):gsub("|A.-|a", "\2") end
    s = s:gsub("|A:roleicon%-tiny%-(%a+):.-|a", "{%1}")
    s = s:gsub("|TInterface\\LFGFrame\\UI%-LFG%-ICON%-PORTRAITROLES:%d+:%d+:0:0:64:64:0:19:22:41|t", "{tank}")
    s = s:gsub("|TInterface\\LFGFrame\\UI%-LFG%-ICON%-PORTRAITROLES:%d+:%d+:0:0:64:64:20:39:1:20|t", "{healer}")
    s = s:gsub("|TInterface\\LFGFrame\\UI%-LFG%-ICON%-PORTRAITROLES:%d+:%d+:0:0:64:64:20:39:22:41|t", "{dps}")
    s = s:gsub("|T.-|t", "\2"):gsub("|A.-|a", "\2")
    s = s:gsub("|H.-|h(.-)|h", "%1")
    s = s:gsub("\1", "|")
    return s
end
-- largura média por caractere, medida em capturas do cliente (UI scale 1):
-- GameFontNormal/Highlight ~6,5 px, as "Small" ~5,5 px, Large/Huge ~8 px
local function charWidth(template)
    template = tostring(template or "")
    if template:find("Small") then return 5.5 end
    if template:find("Large") or template:find("Huge") then return 8 end
    return 6.5
end
M.charWidth = charWidth
local function textWidth(s, cw)
    local v = M.visibleText(s, true)
    local icons = select(2, v:gsub("\2", ""))
    v = v:gsub("\2", "")
    local longest = 0
    for line in (v .. "\n"):gmatch("(.-)\n") do
        local _, n = line:gsub("[^\128-\191]", "")
        if n > longest then longest = n end
    end
    return longest * (cw or 6.5) + icons * 14
end
M.textWidth = textWidth

function M.new(client)
    local ui = { client = client, all = {}, byName = {}, events = {}, eventOrder = {}, onUpdate = {}, focus = nil }
    local S = setmetatable({}, { __mode = "k" }) -- estado interno de cada objeto
    ui.S = S
    local methods = {}
    local regionM, frameM = {}, {}

    local function err(msg) error(msg, 3) end
    local function st(self)
        local s = S[self]
        if not s then error("objeto inválido (não é um widget)", 3) end
        return s
    end
    ui.state = function(f) return S[f] end

    -- chama um script do frame com o tratamento de erro do jogo (o erro não para o resto)
    local function fire(self, script, ...)
        local s = S[self]
        local fn = s and s.scripts[script]
        if fn then client:protect(fn, self, ...) end
        local hooks = s and s.hooks[script]
        if hooks then for _, h in ipairs(hooks) do client:protect(h, self, ...) end end
    end
    ui.fire = fire

    ------------------------------------------------------------------ geometria
    local function resolveFrame(rel, self)
        if rel == nil then return S[self].parent or ui.UIParent end
        if type(rel) == "string" then return client.env[rel] end
        return rel
    end

    local rectOf
    local function edgeOf(f, col, axis, guard, memo)
        local r = rectOf(f, guard, memo)
        if not r then return nil end
        if axis == "x" then
            if col == "L" then return r.l elseif col == "R" then return r.r else return (r.l + r.r) / 2 end
        else
            if col == "T" then return r.t elseif col == "B" then return r.b else return (r.t + r.b) / 2 end
        end
    end

    -- memo: uma medição só por chamada de fora (cadeias longas de âncoras ficavam exponenciais)
    rectOf = function(f, guard, memo)
        local s = S[f]
        if not s then return nil end
        if s.fixedRect then return s.fixedRect end
        memo = memo or {}
        local m = memo[f]
        if m ~= nil then return m or nil end
        guard = guard or {}
        if guard[f] then return nil end
        guard[f] = true
        local L, R, CX, T, B, CY
        for _, p in ipairs(s.points) do
            local rel = p.rel
            local pc = POINTS[p.point]
            local rc = POINTS[p.relPoint]
            if rel and S[rel] then
                local vx = edgeOf(rel, rc[1], "x", guard, memo)
                local vy = edgeOf(rel, rc[2], "y", guard, memo)
                if vx then
                    vx = vx + (p.x or 0)
                    if pc[1] == "L" then L = vx elseif pc[1] == "R" then R = vx else CX = vx end
                end
                if vy then
                    vy = vy + (p.y or 0)
                    if pc[2] == "T" then T = vy elseif pc[2] == "B" then B = vy else CY = vy end
                end
            end
        end
        guard[f] = nil
        -- filho de rolagem sem âncoras: o ScrollFrame põe no canto de cima, deslocado pela rolagem
        if #s.points == 0 and s.parent and S[s.parent] and S[s.parent].scrollChild == f then
            local pr = rectOf(s.parent, guard, memo)
            if pr then L, T = pr.l, pr.t + (S[s.parent].vscroll or 0) end
        end
        local w = s.width
        local h = s.height
        if (not w or w == 0) and s.kind == "FontString" then w = textWidth(s.text, charWidth(s.template or s.fontObject)) end
        if (not h or h == 0) and s.kind == "FontString" then -- linhas de ~12 px, contando a quebra automática
            h = math.max(12, f:GetStringHeight())
        end
        if not (L and R) then
            if w then
                if L then R = L + w elseif R then L = R - w elseif CX then L, R = CX - w / 2, CX + w / 2 end
            end
        end
        if not (T and B) then
            if h then
                if T then B = T - h elseif B then T = B + h elseif CY then T, B = CY + h / 2, CY - h / 2 end
            end
        end
        local out = (L and R and T and B) and { l = L, r = R, t = T, b = B } or nil
        memo[f] = out or false
        return out
    end
    ui.rect = function(f) return rectOf(f) end

    function regionM:SetPoint(point, a, b, c, d)
        local s = st(self)
        if not POINTS[point] then err("SetPoint: ponto inválido " .. tostring(point)) end
        local rel, relPoint, x, y
        if type(a) == "number" or a == nil and b == nil then
            rel, relPoint, x, y = nil, point, a, b
        elseif type(b) == "number" then
            rel, relPoint, x, y = a, point, b, c
        else
            rel, relPoint, x, y = a, b or point, c, d
        end
        if type(rel) == "string" then rel = client.env[rel] end
        if rel == nil then rel = s.parent or ui.UIParent end
        if rel == self then err("SetPoint: frame ancorado em si mesmo") end
        if not POINTS[relPoint] then err("SetPoint: ponto relativo inválido " .. tostring(relPoint)) end
        if ui.blockedInCombat(self, "SetPoint") then return end
        for i, p in ipairs(s.points) do
            if p.point == point then table.remove(s.points, i) break end
        end
        s.points[#s.points + 1] = { point = point, rel = rel, relPoint = relPoint, x = x or 0, y = y or 0 }
    end
    function regionM:SetAllPoints(rel)
        local s = st(self)
        rel = resolveFrame(rel, self)
        s.points = {}
        self:SetPoint("TOPLEFT", rel, "TOPLEFT", 0, 0)
        self:SetPoint("BOTTOMRIGHT", rel, "BOTTOMRIGHT", 0, 0)
    end
    function regionM:ClearAllPoints()
        local s = st(self)
        if ui.blockedInCombat(self, "ClearAllPoints") then return end
        s.points = {}
    end
    function regionM:GetNumPoints() return #st(self).points end
    function regionM:GetPoint(i)
        local p = st(self).points[i or 1]
        if not p then return nil end
        return p.point, p.rel, p.relPoint, p.x, p.y
    end
    local function sizeChanged(self, ow, oh)
        local s = S[self]
        if (s.width or 0) ~= (ow or 0) or (s.height or 0) ~= (oh or 0) then fire(self, "OnSizeChanged", s.width or 0, s.height or 0) end
    end
    function regionM:SetWidth(w) local s = st(self); local ow, oh = s.width, s.height; s.width = w; if s.isFrame then sizeChanged(self, ow, oh) end end
    function regionM:SetHeight(h) local s = st(self); local ow, oh = s.width, s.height; s.height = h; if s.isFrame then sizeChanged(self, ow, oh) end end
    function regionM:SetSize(w, h) local s = st(self); local ow, oh = s.width, s.height; s.width, s.height = w, h; if s.isFrame then sizeChanged(self, ow, oh) end end
    function regionM:GetWidth()
        local r = rectOf(self)
        if r then return r.r - r.l end
        local s = st(self)
        if s.kind == "FontString" and not s.width then return textWidth(s.text, charWidth(s.template or s.fontObject)) end
        return s.width or 0
    end
    function regionM:GetHeight()
        local r = rectOf(self)
        if r then return r.t - r.b end
        return st(self).height or 0
    end
    function regionM:GetSize() return self:GetWidth(), self:GetHeight() end
    function regionM:GetLeft() local r = rectOf(self); return r and r.l end
    function regionM:GetRight() local r = rectOf(self); return r and r.r end
    function regionM:GetTop() local r = rectOf(self); return r and r.t end
    function regionM:GetBottom() local r = rectOf(self); return r and r.b end
    function regionM:GetCenter() local r = rectOf(self); if r then return (r.l + r.r) / 2, (r.t + r.b) / 2 end end
    function regionM:GetRect() local r = rectOf(self); if r then return r.l, r.b, r.r - r.l, r.t - r.b end end

    ------------------------------------------------------------------ visibilidade
    local function visible(f)
        local s = S[f]
        while s do
            if not s.shown then return false end
            if not s.parent then return true end
            s = S[s.parent]
        end
        return true
    end
    ui.visible = visible
    local function propagate(f, nowVisible)
        local s = S[f]
        if s.isFrame then fire(f, nowVisible and "OnShow" or "OnHide") end
        if not nowVisible and ui.focus == f then ui.clearFocus() end
        for _, c in ipairs(s.children) do
            if S[c].shown then propagate(c, nowVisible) end
        end
    end
    local function setShown(self, v, fn)
        local s = st(self)
        v = v and true or false
        if s.shown == v then return end
        if ui.blockedInCombat(self, fn) then return end
        local before = visible(self)
        s.shown = v
        local after = visible(self)
        if before ~= after then propagate(self, after) end
    end
    function regionM:Show() setShown(self, true, "Show") end
    function regionM:Hide() setShown(self, false, "Hide") end
    function regionM:SetShown(v) setShown(self, v, "SetShown") end
    function regionM:IsShown() return st(self).shown end
    function regionM:IsVisible() return visible(self) end
    function regionM:SetAlpha(a) st(self).alpha = a end
    function regionM:GetAlpha() return st(self).alpha or 1 end
    function regionM:GetParent() return st(self).parent end
    function regionM:GetName() return st(self).name end
    function regionM:GetObjectType() return st(self).kind end
    function regionM:IsObjectType(t)
        local k = st(self).kind
        if k == t then return true end
        if t == "Frame" and st(self).isFrame then return true end
        if t == "Region" then return true end
        if t == "Button" and k == "CheckButton" then return true end
        return false
    end
    function regionM:SetDrawLayer(l) st(self).layer = l end
    function regionM:GetDrawLayer() return st(self).layer end
    function regionM:SetScale(v) st(self).scale = v end
    function regionM:GetScale() return st(self).scale or 1 end
    function regionM:GetEffectiveScale() return st(self).scale or 1 end
    -- como no jogo: o mouse sobre um filho também está sobre o pai (a área do pai contém o filho)
    function regionM:IsMouseOver()
        local f = ui.mouseOver
        for _ = 1, 30 do
            if not f then return false end
            if f == self then return true end
            f = st(f).parent
        end
        return false
    end
    function regionM:SetIgnoreParentAlpha() end
    function regionM:SetIgnoreParentScale() end

    ------------------------------------------------------------------ Texture
    local textureM = setmetatable({}, { __index = regionM })
    function textureM:SetTexture(t) local s = st(self); s.texture = t; s.atlas = nil; return true end
    function textureM:GetTexture() return st(self).texture end
    function textureM:SetAtlas(a) local s = st(self); s.atlas = a; s.texture = nil end
    function textureM:GetAtlas() return st(self).atlas end
    function textureM:SetTexCoord(...) st(self).texCoord = { ... } end
    function textureM:GetTexCoord() return unpack(st(self).texCoord or { 0, 1, 0, 1 }) end
    function textureM:SetColorTexture(r, g, b, a) st(self).color = { r, g, b, a } end
    function textureM:SetVertexColor(r, g, b, a) st(self).vertex = { r, g, b, a } end
    function textureM:SetDesaturated(v) st(self).desaturated = v and true or false end
    function textureM:IsDesaturated() return st(self).desaturated or false end
    function textureM:SetBlendMode(m) st(self).blend = m end
    function textureM:SetGradient() end
    function textureM:SetRotation(r) st(self).rotation = r end
    function textureM:SetHorizTile() end
    function textureM:SetVertTile() end
    methods.Texture = textureM

    ------------------------------------------------------------------ FontString
    local fontM = setmetatable({}, { __index = regionM })
    function fontM:SetText(t)
        local s = st(self)
        if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then err("SetText: texto inválido (" .. type(t) .. ")") end
        s.text = t ~= nil and tostring(t) or nil
    end
    function fontM:SetFormattedText(fmt, ...) self:SetText(string.format(fmt, ...)) end
    function fontM:GetText() return st(self).text end
    function fontM:SetFont(...) st(self).font = { ... }; return true end
    function fontM:GetFont() return unpack(st(self).font or { "Fonts\\FRIZQT__.TTF", 12, "" }) end
    function fontM:SetFontObject(o) st(self).fontObject = o end
    function fontM:GetFontObject() return st(self).fontObject end
    function fontM:SetTextColor(r, g, b, a) st(self).textColor = { r, g, b, a } end
    function fontM:GetTextColor() return unpack(st(self).textColor or { 1, 1, 1, 1 }) end
    function fontM:SetJustifyH(v) st(self).justifyH = v end
    function fontM:SetJustifyV(v) st(self).justifyV = v end
    function fontM:SetWordWrap(v) st(self).wordWrap = v and true or false end
    function fontM:CanWordWrap() local w = st(self).wordWrap; return w == nil or w end
    function fontM:SetNonSpaceWrap() end
    function fontM:SetMaxLines(n) st(self).maxLines = n end
    function fontM:SetSpacing(n) st(self).spacing = n end
    function fontM:SetShadowColor() end
    function fontM:SetShadowOffset() end
    function fontM:SetIndentedWordWrap() end
    local function fw(self) local s = st(self); return textWidth(s.text, charWidth(s.template or s.fontObject)) end
    function fontM:GetStringWidth() return fw(self) end
    function fontM:GetUnboundedStringWidth() return fw(self) end
    function fontM:GetStringHeight()
        local s = st(self)
        local text = s.text or ""
        if text == "" then return 0 end
        local lines = select(2, text:gsub("\n", "")) + 1
        local w = s.width
        if w and w > 0 and s.wordWrap ~= false then
            local need = fw(self)
            lines = math.max(lines, math.ceil(need / w))
        end
        return lines * 12 + (lines - 1) * (s.spacing or 0)
    end
    function fontM:IsTruncated()
        local s = st(self)
        local w = s.width
        if not w or w <= 0 then return false end
        return s.wordWrap == false and fw(self) > w
    end
    methods.FontString = fontM

    ------------------------------------------------------------------ Frame
    setmetatable(frameM, { __index = regionM })
    function frameM:SetScript(script, fn)
        local s = st(self)
        if not SCRIPTS[s.kind][script] then err(s.kind .. " doesn't have a \"" .. tostring(script) .. "\" script") end
        if fn ~= nil and type(fn) ~= "function" then err("SetScript: função inválida") end
        s.scripts[script] = fn
        if script == "OnUpdate" then ui.onUpdate[self] = fn and true or nil end
    end
    function frameM:GetScript(script)
        local s = st(self)
        if not SCRIPTS[s.kind][script] then err(s.kind .. " doesn't have a \"" .. tostring(script) .. "\" script") end
        return s.scripts[script]
    end
    function frameM:HasScript(script) return SCRIPTS[st(self).kind][script] ~= nil end
    function frameM:HookScript(script, fn)
        local s = st(self)
        if not SCRIPTS[s.kind][script] then err(s.kind .. " doesn't have a \"" .. tostring(script) .. "\" script") end
        s.hooks[script] = s.hooks[script] or {}
        table.insert(s.hooks[script], fn)
        if script == "OnUpdate" then ui.onUpdate[self] = true end
    end
    function frameM:RegisterEvent(event)
        if not client.knownEvents[event] then err("Attempt to register unknown event \"" .. tostring(event) .. "\"") end
        local list = ui.events[event]
        if not list then list = {}; ui.events[event] = list end
        for _, f in ipairs(list) do if f == self then return end end
        list[#list + 1] = self
    end
    function frameM:UnregisterEvent(event)
        local list = ui.events[event]
        if not list then return end
        for i, f in ipairs(list) do if f == self then table.remove(list, i) return end end
    end
    function frameM:UnregisterAllEvents()
        for _, list in pairs(ui.events) do
            for i = #list, 1, -1 do if list[i] == self then table.remove(list, i) end end
        end
    end
    function frameM:IsEventRegistered(event)
        for _, f in ipairs(ui.events[event] or {}) do if f == self then return true end end
        return false
    end
    function frameM:CreateTexture(name, layer) return ui.newRegion("Texture", name, self, layer) end
    function frameM:CreateFontString(name, layer, template) local fs = ui.newRegion("FontString", name, self, layer); S[fs].template = template; return fs end
    function frameM:GetChildren() return unpack(st(self).children) end
    function frameM:GetNumChildren() return #st(self).children end
    function frameM:GetRegions() return unpack(st(self).regions) end
    function frameM:GetNumRegions() return #st(self).regions end
    function frameM:SetParent(p)
        local s = st(self)
        if s.parent then
            local list = S[s.parent].children
            for i, c in ipairs(list) do if c == self then table.remove(list, i) break end end
        end
        s.parent = p
        if p then table.insert(S[p].children, self) end
    end
    function frameM:SetFrameStrata(v) st(self).strata = v end
    function frameM:GetFrameStrata() return st(self).strata or "MEDIUM" end
    function frameM:SetFrameLevel(v) st(self).level = v end
    function frameM:GetFrameLevel() return st(self).level or 1 end
    -- Raise: o quadro (e os filhos, que contam a partir dele) vai para cima de tudo no strata
    function frameM:SetToplevel(v) st(self).toplevel = v and true or false end
    function frameM:IsToplevel() return st(self).toplevel or false end
    function frameM:Raise()
        ui.raiseTop = (ui.raiseTop or 100) + 50
        st(self).level = ui.raiseTop
    end
    function frameM:Lower() end
    function frameM:SetClampedToScreen(v) st(self).clamped = v end
    function frameM:SetClampRectInsets() end
    function frameM:SetMovable(v) st(self).movable = v end
    function frameM:IsMovable() return st(self).movable or false end
    function frameM:SetResizable(v) st(self).resizable = v end
    function frameM:IsResizable() return st(self).resizable or false end
    function frameM:SetResizeBounds(a, b, c, d) st(self).bounds = { a, b, c, d } end
    function frameM:EnableMouse(v) st(self).mouse = v end
    function frameM:IsMouseEnabled() return st(self).mouse or false end
    function frameM:EnableMouseWheel(v) st(self).wheel = v end
    function frameM:EnableKeyboard(v) st(self).keyboard = v end
    function frameM:SetPropagateKeyboardInput() end
    function frameM:SetHitRectInsets() end
    function frameM:RegisterForDrag(...) st(self).drag = { ... } end
    function frameM:StartMoving() st(self).moving = true end
    function frameM:StartSizing(p) st(self).sizing = p end
    function frameM:StopMovingOrSizing() local s = st(self); s.moving, s.sizing = nil, nil end
    function frameM:SetUserPlaced() end
    function frameM:SetID(id) st(self).id = id end
    function frameM:GetID() return st(self).id or 0 end
    function frameM:SetBackdrop(b) st(self).backdrop = b end
    function frameM:SetBackdropColor(...) st(self).backdropColor = { ... } end
    function frameM:SetBackdropBorderColor(...) st(self).backdropBorder = { ... } end
    function frameM:ApplyBackdrop() end
    function frameM:SetAttribute(k, v)
        local s = st(self)
        if ui.blockedInCombat(self, "SetAttribute") then return end
        s.attributes[k] = v
        fire(self, "OnAttributeChanged", k, v)
    end
    function frameM:GetAttribute(k) return st(self).attributes[k] end
    function frameM:IsProtected()
        local function prot(f)
            local s = S[f]
            if s.protected then return true end
            for _, c in ipairs(s.children) do if S[c].isFrame and prot(c) then return true end end
            return false
        end
        local p = prot(self)
        return p, st(self).protected or false
    end
    function frameM:IsForbidden() return false end
    function frameM:SetDontSavePosition() end
    methods.Frame = frameM

    ------------------------------------------------------------------ Button / CheckButton
    local buttonM = setmetatable({}, { __index = frameM })
    local function fontOf(self)
        local s = st(self)
        if not s.fontString then
            s.fontString = ui.newRegion("FontString", nil, self, "OVERLAY")
            S[s.fontString].points = {}
            s.fontString:SetPoint("CENTER", self, "CENTER", 0, 0)
        end
        return s.fontString
    end
    function buttonM:SetText(t) fontOf(self):SetText(t) end
    function buttonM:GetText() local s = st(self); return s.fontString and s.fontString:GetText() end
    function buttonM:SetFormattedText(...) fontOf(self):SetFormattedText(...) end
    function buttonM:GetFontString() return st(self).fontString end
    function buttonM:SetFontString(fs) st(self).fontString = fs end
    function buttonM:GetTextWidth() return fontOf(self):GetStringWidth() end
    function buttonM:SetNormalFontObject() end
    function buttonM:SetHighlightFontObject() end
    function buttonM:SetDisabledFontObject() end
    function buttonM:SetEnabled(v) st(self).enabled = v and true or false end
    function buttonM:Enable() st(self).enabled = true end
    function buttonM:Disable() st(self).enabled = false end
    function buttonM:IsEnabled() return st(self).enabled end
    function buttonM:RegisterForClicks(...) st(self).clicks = { ... } end
    function buttonM:SetMotionScriptsWhileDisabled(v) st(self).motionDisabled = v end
    function buttonM:LockHighlight() st(self).highlightLocked = true end
    function buttonM:UnlockHighlight() st(self).highlightLocked = false end
    function buttonM:SetButtonState(v) st(self).buttonState = v end
    for _, which in ipairs({ "Normal", "Pushed", "Highlight", "Disabled", "Checked", "DisabledChecked" }) do
        buttonM["Set" .. which .. "Texture"] = function(self, tex)
            local s = st(self)
            local t = s["tex" .. which]
            if not t then t = ui.newRegion("Texture", nil, self, "ARTWORK"); s["tex" .. which] = t end
            if type(tex) == "string" or type(tex) == "number" then t:SetTexture(tex) end
        end
        buttonM["Get" .. which .. "Texture"] = function(self)
            local s = st(self)
            if not s["tex" .. which] then buttonM["Set" .. which .. "Texture"](self, nil) end
            return s["tex" .. which]
        end
        buttonM["Set" .. which .. "Atlas"] = function(self, a) buttonM["Set" .. which .. "Texture"](self, nil); st(self)["tex" .. which]:SetAtlas(a) end
    end
    function buttonM:Click(mouse, down)
        local s = st(self)
        if not s.enabled then return end
        if not visible(self) and not ui.allowHiddenClick then return end
        mouse = mouse or "LeftButton"
        if s.kind == "CheckButton" then s.checked = not s.checked end
        -- clique dentro de uma janela "toplevel": ela vem para a frente (como no jogo)
        local anc = self
        while anc do
            local as = S[anc]
            if as and as.toplevel then anc:Raise() break end
            anc = as and as.parent
        end
        -- evento de hardware: o clique libera UMA ação protegida (busca, criar/tirar listagem)
        local hw = client.hw
        client.hw = { left = 1 }
        fire(self, "PreClick", mouse, down or false)
        fire(self, "OnClick", mouse, down or false)
        client.hw = hw
        if s.protected and s.attributes.type == "macro" and s.attributes.macrotext then
            client:runMacro(s.attributes.macrotext, true)
        end
        fire(self, "PostClick", mouse, down or false)
    end
    methods.Button = buttonM
    local checkM = setmetatable({}, { __index = buttonM })
    function checkM:SetChecked(v) st(self).checked = v and true or false end
    function checkM:GetChecked() return st(self).checked or false end
    methods.CheckButton = checkM

    ------------------------------------------------------------------ EditBox
    local editM = setmetatable({}, { __index = frameM })
    local function utf8len(s) local _, n = s:gsub("[^\128-\191]", ""); return n end
    local function utf8cut(s, n)
        local count, i = 0, 1
        while i <= #s do
            local c = s:byte(i)
            local len = c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1
            count = count + 1
            if count > n then return s:sub(1, i - 1) end
            i = i + len
        end
        return s
    end
    ui.utf8len, ui.utf8cut = utf8len, utf8cut
    local function cleanText(s, text)
        text = tostring(text or "")
        if s.numeric then text = text:gsub("%D", "") end
        if not s.multiLine then text = text:gsub("\n", "") end
        if s.maxLetters and s.maxLetters > 0 then text = utf8cut(text, s.maxLetters) end
        if s.maxBytes and s.maxBytes > 0 then text = text:sub(1, s.maxBytes) end
        return text
    end
    function editM:SetText(text)
        local s = st(self)
        if text ~= nil and type(text) ~= "string" and type(text) ~= "number" then err("SetText: texto inválido") end
        s.text = cleanText(s, text)
        s.cursor = #s.text
        fire(self, "OnTextSet")
        fire(self, "OnTextChanged", false)
    end
    function editM:GetText() return st(self).text or "" end
    function editM:GetNumber() return tonumber(st(self).text) or 0 end
    function editM:SetNumber(n) self:SetText(tostring(n)) end
    function editM:Insert(t) local s = st(self); self:SetText((s.text or "") .. t) end
    function editM:SetNumeric(v) st(self).numeric = v end
    function editM:IsNumeric() return st(self).numeric or false end
    function editM:SetMaxLetters(n) st(self).maxLetters = n end
    function editM:GetMaxLetters() return st(self).maxLetters or 0 end
    function editM:SetMaxBytes(n) st(self).maxBytes = n end
    function editM:SetMultiLine(v) st(self).multiLine = v end
    function editM:IsMultiLine() return st(self).multiLine or false end
    function editM:SetAutoFocus(v) st(self).autoFocus = v end
    function editM:SetFocus()
        if ui.focus == self then return end
        ui.clearFocus()
        ui.focus = self
        fire(self, "OnEditFocusGained")
    end
    function editM:ClearFocus() if ui.focus == self then ui.clearFocus() end end
    function editM:HasFocus() return ui.focus == self end
    function editM:HighlightText(a, b) st(self).highlight = { a or 0, b or -1 } end
    function editM:SetCursorPosition(n) st(self).cursor = n end
    function editM:GetCursorPosition() return st(self).cursor or 0 end
    function editM:SetTextInsets() end
    function editM:SetTextColor(...) st(self).textColor = { ... } end
    function editM:SetFontObject() end
    function editM:SetFont() end
    function editM:SetJustifyH() end
    function editM:SetCountInvisibleLetters() end
    function editM:SetHistoryLines() end
    function editM:SetAltArrowKeyMode() end
    function editM:SetEnabled(v) st(self).enabled = v and true or false end
    function editM:Enable() st(self).enabled = true end
    function editM:Disable() st(self).enabled = false end
    function editM:IsEnabled() return st(self).enabled end
    function editM:GetNumLetters() return utf8len(st(self).text or "") end
    methods.EditBox = editM
    function ui.clearFocus()
        local f = ui.focus
        if not f then return end
        ui.focus = nil
        fire(f, "OnEditFocusLost")
    end
    -- O jogador digita: o texto passa pelos limites da caixa e OnTextChanged vem com userInput = true.
    function ui.type(box, text, append)
        local s = S[box]
        assert(s and s.kind == "EditBox", "type: não é EditBox")
        assert(visible(box), "type: a caixa não está visível")
        if s.enabled == false then return end
        box:SetFocus()
        local new = append and ((s.text or "") .. text) or text
        s.text = cleanText(s, new)
        s.cursor = #s.text
        fire(box, "OnTextChanged", true)
    end

    ------------------------------------------------------------------ ScrollFrame / Slider
    local scrollM = setmetatable({}, { __index = frameM })
    function scrollM:SetScrollChild(c) st(self).scrollChild = c end
    function scrollM:GetScrollChild() return st(self).scrollChild end
    function scrollM:SetVerticalScroll(v) st(self).vscroll = v; fire(self, "OnVerticalScroll", v) end
    function scrollM:GetVerticalScroll() return st(self).vscroll or 0 end
    function scrollM:SetHorizontalScroll(v) st(self).hscroll = v end
    function scrollM:GetHorizontalScroll() return st(self).hscroll or 0 end
    function scrollM:GetVerticalScrollRange()
        local c = st(self).scrollChild
        if not c then return 0 end
        return math.max(0, (c:GetHeight() or 0) - (self:GetHeight() or 0))
    end
    function scrollM:UpdateScrollChildRect() end
    methods.ScrollFrame = scrollM
    local sliderM = setmetatable({}, { __index = frameM })
    function sliderM:SetMinMaxValues(a, b) local s = st(self); s.min, s.max = a, b end
    function sliderM:GetMinMaxValues() local s = st(self); return s.min or 0, s.max or 0 end
    function sliderM:SetValue(v)
        local s = st(self)
        v = math.max(s.min or 0, math.min(s.max or 0, v))
        if s.value ~= v then s.value = v; fire(self, "OnValueChanged", v, false) end
    end
    function sliderM:GetValue() return st(self).value or 0 end
    function sliderM:SetValueStep(v) st(self).step = v end
    function sliderM:SetObeyStepOnDrag() end
    function sliderM:SetOrientation() end
    function sliderM:SetThumbTexture() end
    function sliderM:SetEnabled(v) st(self).enabled = v and true or false end
    function sliderM:Enable() st(self).enabled = true end
    function sliderM:Disable() st(self).enabled = false end
    methods.Slider = sliderM

    ------------------------------------------------------------------ GameTooltip
    local tipM = setmetatable({}, { __index = frameM })
    function tipM:SetOwner(owner, anchor)
        local s = st(self)
        s.owner, s.anchor, s.lines = owner, anchor, {}
    end
    function tipM:GetOwner() return st(self).owner end
    function tipM:IsOwned(o) return st(self).owner == o end
    function tipM:ClearLines() st(self).lines = {} end
    function tipM:SetText(t, r, g, b)
        local s = st(self)
        if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then err("GameTooltip:SetText: texto inválido") end
        s.lines = { { text = t ~= nil and tostring(t) or "", r = r, g = g, b = b } }
    end
    function tipM:AddLine(t, r, g, b, wrap)
        local s = st(self)
        if t ~= nil and type(t) ~= "string" and type(t) ~= "number" then err("GameTooltip:AddLine: texto inválido") end
        s.lines[#s.lines + 1] = { text = t ~= nil and tostring(t) or "", r = r, g = g, b = b, wrap = wrap }
    end
    function tipM:AddDoubleLine(a, b) local s = st(self); s.lines[#s.lines + 1] = { text = tostring(a) .. "\t" .. tostring(b) } end
    function tipM:NumLines() return #st(self).lines end
    function tipM:SetMinimumWidth() end
    function tipM:SetPadding() end
    methods.GameTooltip = tipM

    ------------------------------------------------------------------ criação
    local templates = {}
    ui.templates = templates
    local nextLevel = 0
    function ui.newRegion(kind, name, parent, layer)
        local o = {}
        S[o] = { kind = kind, name = name, parent = parent, shown = true, points = {}, layer = layer, children = {}, scripts = {}, hooks = {} }
        if parent then table.insert(S[parent].regions, o) end
        setmetatable(o, { __index = methods[kind] })
        if name then client.env[name] = o; ui.byName[name] = o end
        return o
    end
    function ui.CreateFrame(kind, name, parent, template)
        if type(kind) ~= "string" or not methods[kind] or kind == "Texture" or kind == "FontString" then
            err("CreateFrame: tipo desconhecido " .. tostring(kind))
        end
        if name ~= nil and type(name) ~= "string" then err("CreateFrame: nome inválido") end
        if type(parent) == "string" then parent = client.env[parent] end
        if parent ~= nil and not (S[parent] and S[parent].isFrame) then err("CreateFrame: pai inválido") end
        local f = {}
        nextLevel = nextLevel + 1
        S[f] = { kind = kind, name = name, parent = parent, shown = true, points = {}, children = {}, scripts = {}, hooks = {},
            isFrame = true, enabled = true, attributes = {}, created = nextLevel, template = template, addon = client.loadingAddon, regions = {} }
        if parent then table.insert(S[parent].children, f) end
        setmetatable(f, { __index = methods[kind] })
        if name then client.env[name] = f; ui.byName[name] = f end
        ui.all[#ui.all + 1] = f
        if template then
            for t in tostring(template):gmatch("[^,%s]+") do
                local apply = templates[t]
                if not apply then err("CreateFrame: template desconhecido \"" .. t .. "\"") end
                apply(f, S[f])
            end
        end
        return f
    end

    -- frames protegidos não podem mudar em combate (o cliente bloqueia e avisa)
    function ui.blockedInCombat(self, fn)
        local s = S[self]
        if not (s and s.isFrame) or not client.inCombat then return false end
        if not self:IsProtected() then return false end
        if client.secureCall then return false end
        client:fireEvent("ADDON_ACTION_BLOCKED", s.addon or client.loadingAddon or "?", (s.name or "frame") .. ":" .. tostring(fn) .. "()")
        client.blocked[#client.blocked + 1] = { frame = s.name, fn = fn }
        return true
    end

    ------------------------------------------------------------------ templates
    local function titled(f, s)
        f.TitleText = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.TitleText:SetPoint("TOP", f, "TOP", 0, -5)
        local close = ui.CreateFrame("Button", nil, f)
        close:SetSize(24, 24)
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        close:SetScript("OnClick", function() f:Hide() end)
        f.CloseButton = close
    end
    templates.BasicFrameTemplate = titled
    templates.BasicFrameTemplateWithInset = titled
    templates.ButtonFrameTemplate = titled
    templates.PortraitFrameTemplate = titled
    templates.BackdropTemplate = function() end
    templates.TooltipBackdropTemplate = function() end
    templates.UIPanelButtonTemplate = function(f, s)
        if s.kind ~= "Button" and s.kind ~= "CheckButton" then error("UIPanelButtonTemplate em " .. s.kind) end
        f:SetText("")
        f.Left, f.Middle, f.Right = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
    end
    templates.UIPanelCloseButton = function() end
    templates.UICheckButtonTemplate = function(f, s)
        if s.kind ~= "CheckButton" then error("UICheckButtonTemplate em " .. s.kind) end
        f.Text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        f.Text:SetPoint("LEFT", f, "RIGHT", 0, 1)
        f.text = f.Text
    end
    templates.InputBoxTemplate = function(f, s)
        if s.kind ~= "EditBox" then error("InputBoxTemplate em " .. s.kind) end
        f.Left, f.Middle, f.Right = f:CreateTexture(), f:CreateTexture(), f:CreateTexture()
    end
    templates.InputBoxInstructionsTemplate = templates.InputBoxTemplate
    templates.UIPanelScrollFrameTemplate = function(f, s)
        if s.kind ~= "ScrollFrame" then error("UIPanelScrollFrameTemplate em " .. s.kind) end
        local bar = ui.CreateFrame("Slider", nil, f)
        bar:SetWidth(16)
        bar:SetPoint("TOPLEFT", f, "TOPRIGHT", 6, -16)
        bar:SetPoint("BOTTOMLEFT", f, "BOTTOMRIGHT", 6, 16)
        f.ScrollBar = bar
    end
    templates.ScrollFrameTemplate = templates.UIPanelScrollFrameTemplate
    templates.SecureActionButtonTemplate = function(f, s)
        if s.kind ~= "Button" and s.kind ~= "CheckButton" then error("SecureActionButtonTemplate em " .. s.kind) end
        s.protected = true
    end
    templates.SecureHandlerBaseTemplate = function(_, s) s.protected = true end
    templates.GameTooltipTemplate = function() end

    ------------------------------------------------------------------ eventos e quadros
    function ui.dispatch(event, ...)
        local list = ui.events[event]
        if not list then return end
        local copy = {}
        for i, f in ipairs(list) do copy[i] = f end
        for _, f in ipairs(copy) do fire(f, "OnEvent", event, ...) end
    end
    function ui.tick(elapsed)
        local list = {}
        for f in pairs(ui.onUpdate) do
            if visible(f) then list[#list + 1] = f end
        end
        table.sort(list, function(a, b) return S[a].created < S[b].created end)
        for _, f in ipairs(list) do
            local s = S[f]
            if s.scripts.OnUpdate or s.hooks.OnUpdate then fire(f, "OnUpdate", elapsed) end
        end
    end
    function ui.hasOnUpdate()
        for f in pairs(ui.onUpdate) do
            local s = S[f]
            if (s.scripts.OnUpdate or s.hooks.OnUpdate) and visible(f) then return true end
        end
        return false
    end

    -- UIParent: a tela inteira (1920x1080)
    local root = {}
    S[root] = { kind = "Frame", name = "UIParent", shown = true, points = {}, children = {}, scripts = {}, hooks = {},
        isFrame = true, enabled = true, attributes = {}, created = 0, fixedRect = { l = 0, r = 1920, t = 1080, b = 0 }, regions = {} }
    setmetatable(root, { __index = frameM })
    ui.UIParent = root
    client.env.UIParent = root
    ui.byName.UIParent = root
    return ui
end

return M
