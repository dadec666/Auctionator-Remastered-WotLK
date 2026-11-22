-- Minimap launcher and offline-browser Interface options.
local settings = AuctionatorRemastered.Browser.Settings
local minimapButton
local minimapShapes = {
	ROUND = { true, true, true, true },
	SQUARE = { false, false, false, false },
	["CORNER-TOPLEFT"] = { true, false, false, false },
	["CORNER-TOPRIGHT"] = { false, false, true, false },
	["CORNER-BOTTOMLEFT"] = { false, true, false, false },
	["CORNER-BOTTOMRIGHT"] = { false, false, false, true },
	["SIDE-LEFT"] = { true, true, false, false },
	["SIDE-RIGHT"] = { false, false, true, true },
	["SIDE-TOP"] = { true, false, true, false },
	["SIDE-BOTTOM"] = { false, true, false, true },
	["TRICORNER-TOPLEFT"] = { true, true, true, false },
	["TRICORNER-TOPRIGHT"] = { true, false, true, true },
	["TRICORNER-BOTTOMLEFT"] = { true, true, false, true },
	["TRICORNER-BOTTOMRIGHT"] = { false, true, true, true },
}
function Atr_BrowserMinimapOffset(angle, width, height, shape)
	local x, y = math.cos(angle), math.sin(angle)
	local halfWidth = type(width) == "number" and width > 0 and width / 2 or 70
	local halfHeight = type(height) == "number" and height > 0 and height / 2 or 70
	local quadrant = 1
	if x < 0 then
		quadrant = quadrant + 1
	end
	if y > 0 then
		quadrant = quadrant + 2
	end
	local rounded = minimapShapes[shape] or minimapShapes.ROUND
	if rounded[quadrant] then
		return x * (halfWidth + 10), y * (halfHeight + 10)
	end
	local rx, ry = math.max(1, halfWidth - 7), math.max(1, halfHeight - 7)
	local distance = 1 / math.max(math.abs(x) / rx, math.abs(y) / ry)
	return x * distance, y * distance
end
local function positionIcon(angle)
	-- A collector owns the position while the button lives in its drawer.
	if minimapButton:GetParent() ~= Minimap then
		return
	end
	local x, y = Atr_BrowserMinimapOffset(
		angle,
		Minimap:GetWidth(),
		Minimap:GetHeight(),
		GetMinimapShape and GetMinimapShape() or "ROUND"
	)
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
local function createIcon()
	if minimapButton or not Minimap then
		return
	end
	-- Collectors such as IconBox display LibDBIcon-style names without this
	-- prefix. Retain the old global alias for existing addon integrations.
	minimapButton = CreateFrame("Button", "LibDBIcon10_Auctionator Remastered", Minimap)
	_G.Atr_BrowserMinimapButton = minimapButton
	minimapButton:SetSize(31, 31)
	minimapButton:SetFrameStrata("MEDIUM")
	local background = minimapButton:CreateTexture(nil, "BACKGROUND")
	background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	background:SetSize(20, 20)
	background:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 7, -5)
	local picture = minimapButton:CreateTexture(nil, "ARTWORK")
	picture:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
	picture:SetSize(18, 18)
	picture:SetPoint("CENTER", minimapButton, "CENTER", 1, 0)
	picture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	local border = minimapButton:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	-- TrackingBorder has transparent padding; use the standard minimap-button
	-- geometry rather than centering the artwork in the full texture rectangle.
	border:SetSize(54, 54)
	border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)
	minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	minimapButton:RegisterForDrag("LeftButton")
	minimapButton:SetScript("OnClick", function(self, button)
		if button == "RightButton" then
			if IsShiftKeyDown() then
				InterfaceOptionsFrame_OpenToCategory(Atr_ScanningOptionsFrame)
			end
		elseif button == "LeftButton" then
			Atr_ToggleOfflineBrowser()
		end
	end)
	minimapButton:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local x, y = GetCursorPosition()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = Minimap:GetCenter()
			local atan2 = math.atan2 or math.atan
			local angle = atan2(y / scale - cy, x / scale - cx)
			settings().angle = angle
			positionIcon(angle)
		end)
	end)
	minimapButton:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	minimapButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Auctionator Remastered - Browser")
		GameTooltip:AddLine("Left-click: browse saved AH prices", 1, 1, 1)
		GameTooltip:AddLine("Shift + right-click: database settings", 1, 1, 1)
		GameTooltip:AddLine("Drag to move. /atr minimap to hide or show.", 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end)
	minimapButton:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	positionIcon(tonumber(settings().angle) or math.rad(220))
	Minimap:HookScript("OnSizeChanged", function()
		positionIcon(tonumber(settings().angle) or math.rad(220))
	end)
	if settings().hide then
		minimapButton:Hide()
	end
end
function Atr_ToggleBrowserMinimap()
	createIcon()
	settings().hide = not settings().hide
	if minimapButton then
		if settings().hide then
			minimapButton:Hide()
		else
			minimapButton:Show()
		end
	end
end
local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
	createIcon()
	if InterfaceOptions_AddCategory then
		local options = CreateFrame("Frame", "Atr_OfflineBrowserOptions", UIParent)
		options.name = ZT and ZT("Offline Browser") or "Offline Browser"
		options.parent = "Auctionator"
		local title = options:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
		title:SetPoint("TOPLEFT", 16, -16)
		title:SetText(ZT and ZT("Offline Browser") or "Offline Browser")
		local choice = CreateFrame("CheckButton", "Atr_ShowIncompleteBrowserItems", options, "UICheckButtonTemplate")
		Atr_AnalysisSkin(choice, "CheckBox")
		choice:SetSize(24, 24)
		choice:SetPoint("TOPLEFT", 16, -54)
		_G[choice:GetName() .. "Text"]:SetText(ZT and ZT("Show incomplete items") or "Show incomplete items")
		local help = options:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		help:SetPoint("TOPLEFT", 20, -88)
		help:SetWidth(520)
		help:SetJustifyH("LEFT")
		help:SetText(
			ZT
					and ZT(
						"Show items with missing categories or equipment slots in the offline browser.\nHidden items keep their saved prices and history. Shopping lists are unaffected."
					)
				or "Show items with missing categories or equipment slots in the offline browser.\nHidden items keep their saved prices and history. Shopping lists are unaffected."
		)
		choice:SetScript("OnClick", function(self)
			settings().showIncompleteItems = self:GetChecked() and true or false
			Atr_RefreshOfflineBrowser()
		end)
		options:SetScript("OnShow", function()
			if Atr_LocalizeChildText then
				Atr_LocalizeChildText(options)
			end
			choice:SetChecked(settings().showIncompleteItems and true or false)
		end)
		InterfaceOptions_AddCategory(options)
		options:Hide()
	end
	SlashCmdList.AtrOfflineBrowser = function()
		Atr_ToggleOfflineBrowser()
	end
	SLASH_AtrOfflineBrowser1 = "/atrbrowse"
end)
