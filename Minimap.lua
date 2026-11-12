-- GrupoFacil: botão no minimapa (próprio, sem bibliotecas). Arrasta pela borda do mapa.
-- Clique esquerdo abre/fecha a janela; direito abre as opções.

local ADDON, NS = ...
local L = NS.L
local rad, deg, cos, sin, atan2, sqrt, max, min = math.rad, math.deg, math.cos, math.sin, math.atan2, math.sqrt, math.max, math.min

NS.MINIMAP_ICON = "Interface\\Icons\\INV_Misc_GroupNeedMore"
local DEFAULT_ANGLE = 210

local button

local function settings()
    local db = GrupoFacilDB
    db.minimap = db.minimap or {}
    if db.minimap.angle == nil then db.minimap.angle = DEFAULT_ANGLE end
    return db.minimap
end

-- Posição na borda; em minimapa quadrado, o botão corre pelo contorno do quadrado.
local function place()
    if not button then return end
    local a = rad(settings().angle)
    local x, y = cos(a), sin(a)
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local k = 1 / max(math.abs(x), math.abs(y))
        x, y = x * k * 0.98, y * k * 0.98
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * w, y * h)
end
NS.PlaceMinimapButton = place

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    cx, cy = cx / scale, cy / scale
    settings().angle = deg(atan2(cy - my, cx - mx)) % 360
    place()
end

function NS.BuildMinimapButton()
    if button or not Minimap then return end
    local b = CreateFrame("Button", "GrupoFacilMinimapButton", Minimap)
    button = b
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(NS.MINIMAP_ICON)
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    b.icon = icon

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", NS.D.Wrap("MinimapButton.OnClick", function(_, mouse)
        if mouse == "RightButton" then
            if NS.OpenOptions then NS.OpenOptions() end
        elseif NS.TogglePanel then
            NS.TogglePanel()
        end
    end))
    b:SetScript("OnDragStart", NS.D.Wrap("MinimapButton.OnDragStart", function(self)
        self.icon:SetTexCoord(0, 1, 0, 1)
        self:SetScript("OnUpdate", NS.D.Wrap("MinimapButton.OnUpdate", onDragUpdate))
        GameTooltip:Hide()
    end))
    b:SetScript("OnDragStop", NS.D.Wrap("MinimapButton.OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
        NS.D.Trace("MINIMAPA", "botão movido para %d graus", math.floor(settings().angle))
    end))
    b:SetScript("OnEnter", NS.D.Wrap("MinimapButton.OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("GrupoFacil")
        GameTooltip:AddLine(L["Click: open or close the window"], 1, 1, 1)
        GameTooltip:AddLine(L["Right-click: options"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move the button"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end))
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    place()
    NS.UpdateMinimapButton()
    NS.D.Trace("MINIMAPA", "botão criado; ângulo=%d, visível=%s", math.floor(settings().angle), tostring(not settings().hide))
end

function NS.UpdateMinimapButton()
    if not button then return end
    if settings().hide then button:Hide() else button:Show(); place() end
end

function NS.SetMinimapButtonShown(show)
    settings().hide = not show or nil
    NS.UpdateMinimapButton()
end

function NS.IsMinimapButtonShown()
    return not settings().hide
end
