-- Shared Browse-style presentation. Both panels retain their own data/actions.
function Atr_AnalysisSkin(control, kind)
	if not control then
		return
	end
	local engine = type(ElvUI) == "table" and ElvUI[1]
	if engine and type(engine.GetModule) == "function" then
		local ok, skins = pcall(engine.GetModule, engine, "Skins", true)
		local method = ok and skins and skins["Handle" .. kind]
		if type(method) == "function" then
			pcall(method, skins, control)
		end
		return
	end

	local dui = _G.DragonUI
	local F = dui and dui.ForeverUI
	if F then
		if (kind == "Button" or kind == "CloseButton") and F.SkinButton then
			pcall(F.SkinButton, control)
		elseif kind == "EditBox" and F.SkinEditBox then
			pcall(F.SkinEditBox, control)
		elseif kind == "CheckBox" and F.SkinCheckButton then
			pcall(F.SkinCheckButton, control)
		elseif kind == "ScrollBar" and F.SkinScrollBar then
			pcall(F.SkinScrollBar, control)
		end
	end
end

local function GetDragonUIDarkTint()
	local dui = _G.DragonUI
	if not dui or not dui.IsModuleEnabled or not dui:IsModuleEnabled("darkmode") then
		return nil
	end
	local config = dui.GetModuleConfig and dui:GetModuleConfig("darkmode")
	if config and config.use_custom_color and config.custom_color then
		local c = config.custom_color
		return { c.r or 0.15, c.g or 0.15, c.b or 0.15 }
	end
	local presets = { [1] = 0.50, [2] = 0.30, [3] = 0.15 }
	local preset = config and config.intensity_preset or 3
	local val = presets[preset] or 0.15
	return { val, val, val }
end

-- Native-only palette; ElvUI keeps its existing backdrops and colours.
function Atr_NativeSurface(frame, role, alpha)
	if type(ElvUI) == "table" then
		return false
	end
	if _G.DragonUI then
		local colors = {
			shell = { 0.10, 0.095, 0.105 },
			body = { 0.12, 0.115, 0.125 },
			sidebar = { 0.14, 0.135, 0.145 },
			heading = { 0.16, 0.155, 0.165 },
			tab = { 0.15, 0.145, 0.155 },
		}
		local color = colors[role] or colors.body
		local tint = GetDragonUIDarkTint()
		local r = tint and (color[1] * tint[1] / 0.15) or color[1]
		local g = tint and (color[2] * tint[2] / 0.15) or color[2]
		local b = tint and (color[3] * tint[3] / 0.15) or color[3]
		frame:SetBackdrop({
			bgFile = "Interface\\Buttons\\WHITE8X8",
			edgeFile = "Interface\\Buttons\\WHITE8X8",
			edgeSize = 2,
			insets = { left = 2, right = 2, top = 2, bottom = 2 },
		})
		frame:SetBackdropColor(r, g, b, alpha or 1)
		if frame.SetBackdropBorderColor then
			local br, bg, bb = 0.25, 0.25, 0.27
			if tint then
				br, bg, bb = br * (tint[1] / 0.15), bg * (tint[2] / 0.15), bb * (tint[3] / 0.15)
			end
			frame:SetBackdropBorderColor(br, bg, bb, 1)
		end
		return true
	end
	if role == "shell" then
		frame:SetBackdrop({
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
			edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
			tile = true,
			tileSize = 32,
			edgeSize = 32,
			insets = { left = 11, right = 12, top = 12, bottom = 11 },
		})
		frame:SetBackdropColor(1, 1, 1, alpha or 1)
		if frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(1, 1, 1, 1)
		end
	else
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true,
			tileSize = 16,
			edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		})
		frame:SetBackdropColor(0.06, 0.06, 0.06, alpha or 0.85)
		if frame.SetBackdropBorderColor then
			frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
		end
	end
	return true
end
function Atr_AnalysisBackdrop(frame, alpha, role)
	if Atr_NativeSurface(frame, role, alpha) then
		return
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true,
		tileSize = 16,
		edgeSize = 16,
		insets = { left = 4, right = 4, top = 4, bottom = 4 },
	})
	frame:SetBackdropColor(0.06, 0.06, 0.06, alpha or 0.85)
	if frame.SetBackdropBorderColor then
		frame:SetBackdropBorderColor(0.55, 0.55, 0.55, 0.9)
	end
end
-- Put arrows and track in a dedicated gutter, outside the content border.
-- FauxScrollFrame retains all range, offset and visibility handling.
function Atr_StyleAnalysisScroll(scroll, content)
	local name = scroll:GetName()
	local bar = scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
	if not bar then
		return
	end
	Atr_AnalysisSkin(bar, "ScrollBar")
	bar:ClearAllPoints()
	bar:SetWidth(18)
	bar:SetPoint("TOPLEFT", content, "TOPRIGHT", 3, -19)
	bar:SetPoint("BOTTOMLEFT", content, "BOTTOMRIGHT", 3, 19)
	local barName = bar:GetName()
	local up = barName and (_G[barName .. "ScrollUpButton"] or _G[barName .. "UpButton"])
	local down = barName and (_G[barName .. "ScrollDownButton"] or _G[barName .. "DownButton"])
	if up then
		up:ClearAllPoints()
		up:SetSize(18, 18)
		up:SetPoint("BOTTOM", bar, "TOP", 0, 1)
	end
	if down then
		down:ClearAllPoints()
		down:SetSize(18, 18)
		down:SetPoint("TOP", bar, "BOTTOM", 0, -1)
	end
end

-- Fit to the visible ElvUI shell, whose left/bottom insets differ from the
-- original AuctionFrame. All inner list margins then share one coordinate space.
function Atr_AnalysisFit(panel)
	local skinned = AuctionFrameBrowse and AuctionFrameBrowse.RightBackground and AuctionFrame.backdrop
	local base = skinned or AuctionFrame
	local inset = 0
	if AuctionFrameTab1 then
		local bottom, top = base:GetBottom(), AuctionFrameTab1:GetTop()
		if bottom and top then
			local scale = base:GetEffectiveScale()
			-- Native tab artwork has transparent padding above its visible rim.
			-- Cover that seam without changing the already aligned ElvUI edge.
			local overlap = skinned and 1 or 4
			inset = (top * AuctionFrameTab1:GetEffectiveScale() - bottom * scale - overlap) / panel:GetEffectiveScale()
		end
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", base, "TOPLEFT", 0, 0)
	panel:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", 0, inset)
end
function Atr_AnalysisBegin(panel)
	local hidden, seen = {}, {}
	local function hide(region)
		if region and not seen[region] then
			seen[region] = true
			hidden[#hidden + 1] = { region = region, shown = region:IsShown() }
			region:Hide()
		end
	end
	local skinned = AuctionFrameBrowse and AuctionFrameBrowse.RightBackground and AuctionFrame.backdrop
	if skinned then
		panel:SetBackdrop(nil)
	else
		-- The vanilla atlas includes a permanent left divider and money recess.
		-- Replace that artwork only while an analysis tab is open.
		for _, region in ipairs({ AuctionFrame:GetRegions() }) do
			if region:IsObjectType("Texture") then
				hide(region)
			end
		end
		for _, suffix in ipairs({ "TopLeft", "BotLeft", "Top", "TopRight", "Bot", "BotRight" }) do
			hide(_G["AuctionFrame" .. suffix])
		end
		Atr_AnalysisBackdrop(panel, 1, "shell")
		-- Reuse the real AH close action, above all three stock overlay panels.
		local close = AuctionFrameCloseButton
		if close then
			local saved = { region = close, level = close:GetFrameLevel(), shown = close:IsShown(), points = {} }
			for i = 1, close:GetNumPoints() do
				saved.points[i] = { close:GetPoint(i) }
			end
			hidden[#hidden + 1] = saved
			close:ClearAllPoints()
			close:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
			close:SetFrameLevel(math.max(close:GetFrameLevel(), panel:GetFrameLevel() + 5))
			close:Show()
		end
	end
	hide(AuctionFrameTitleText)
	hide(AuctionPortraitTexture)
	hide(AuctionFramePortrait)
	hide(AuctionFramePortraitTexture)
	-- Selected vanilla tabs project slightly above the normal tabs. Let their
	-- artwork overlap the panel edge rather than covering it with the backdrop.
	for i = 1, (AuctionFrame.numTabs or 0) do
		local tab = _G["AuctionFrameTab" .. i]
		if tab then
			hidden[#hidden + 1] = { region = tab, level = tab:GetFrameLevel() }
			tab:SetFrameLevel(math.max(tab:GetFrameLevel(), panel:GetFrameLevel() + 1))
		end
	end
	return hidden
end
function Atr_AnalysisEnd(hidden)
	for _, saved in ipairs(hidden or {}) do
		if saved.points then
			saved.region:ClearAllPoints()
			for _, point in ipairs(saved.points) do
				saved.region:SetPoint(unpack(point))
			end
		end
		if saved.level then
			saved.region:SetFrameLevel(saved.level)
		end
		if saved.shown ~= nil then
			if saved.shown then
				saved.region:Show()
			else
				saved.region:Hide()
			end
		end
	end
end

-- Use the same live shell/result colors as Logs, including before the first
-- AH visit when only ElvUI's theme colors are available.
function Atr_StyleOfflineBrowser(frame, body, transparent)
	if Atr_NativeSurface(frame, body and "body" or "shell", transparent and 0.8 or 1) then
		return
	end
	local source = body and AuctionFrameBrowse and AuctionFrameBrowse.RightBackground
		or (AuctionFrame and AuctionFrame.backdrop)
	local r, g, b, alpha = 0.025, 0.025, 0.025, 1
	if source and source.GetBackdrop and source:GetBackdrop() then
		frame:SetBackdrop(source:GetBackdrop())
		r, g, b, alpha = source:GetBackdropColor()
		if source.GetBackdropBorderColor then
			frame:SetBackdropBorderColor(source:GetBackdropBorderColor())
		end
	else
		Atr_AnalysisBackdrop(frame, 1)
		local engine = type(ElvUI) == "table" and ElvUI[1]
		local color = engine and engine.media and engine.media.backdropfadecolor
		if type(color) == "table" and color[1] then
			r, g, b, alpha = color[1], color[2], color[3], color[4] or 0.8
		end
	end
	-- Change only the background opacity, never the text, icons or controls.
	if transparent ~= nil then
		alpha = transparent and 0.8 or 1
	end
	frame:SetBackdropColor(r, g, b, alpha)
end
function Atr_CreateBackgroundCheckbox(parent, name, checked, onChange)
	local choice = CreateFrame("CheckButton", name, parent, "UICheckButtonTemplate")
	Atr_AnalysisSkin(choice, "CheckBox")
	choice:SetPoint("TOPLEFT", parent, "TOPLEFT", 24, -10)
	choice:SetSize(22, 22)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	label:SetPoint("LEFT", choice, "RIGHT", 4, 0)
	label:SetText(ZT and ZT("Transparent background") or "Transparent background")
	choice:SetChecked(checked)
	choice:SetScript("OnClick", function(self)
		onChange(self:GetChecked() and true or false)
	end)
	return choice
end

-- Keep native AH tabs at their inactive height: the selected template otherwise
-- projects through the bottom border. Indicate selection with its blue highlight.
local function styleNativeAuctionTabs(frame)
	if frame ~= AuctionFrame or type(ElvUI) == "table" or _G.DragonUI then
		return
	end
	local selected = PanelTemplates_GetSelectedTab(frame)
	for i = 1, (frame.numTabs or 0) do
		local tab = _G["AuctionFrameTab" .. i]
		if tab then
			if i == selected then
				PanelTemplates_DeselectTab(tab)
				tab:LockHighlight()
			else
				tab:UnlockHighlight()
			end
		end
	end
end
hooksecurefunc("PanelTemplates_UpdateTabs", styleNativeAuctionTabs)
