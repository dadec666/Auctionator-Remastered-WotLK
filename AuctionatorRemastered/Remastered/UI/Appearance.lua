-- AH placement and Interface options; independent of the Deals view.
function AuctionatorRemastered.UI.IsValidPosition(config)
    return type(config)=='table' and type(config.x)=='number' and type(config.y)=='number'
        and config.x==config.x and config.y==config.y and math.abs(config.x)<100000 and math.abs(config.y)<100000
end
function AuctionatorRemastered.UI.SetupAppearance(mover,positionDetails,settings)
    settings() -- Ensure saved variables exist before any option callbacks.
    local originalPoints={}
    for i=1,AuctionFrame:GetNumPoints() do originalPoints[i]={AuctionFrame:GetPoint(i)} end
    if #originalPoints==0 then originalPoints[1]={'TOPLEFT',UIParent,'TOPLEFT',16,-116} end
    local function saveAuctionPosition()
        local scale=AuctionFrame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        local x,y=AuctionFrame:GetLeft(),AuctionFrame:GetBottom()
        if x and y then AUCTIONATOR_SAVEDVARS.auctionFramePosition={x=x*scale,y=y*scale} end
    end
    local function restoreAuctionPosition()
        local config=AUCTIONATOR_SAVEDVARS.auctionFramePosition
        if not AuctionatorRemastered.UI.IsValidPosition(config) then return end
        local scale=AuctionFrame:GetEffectiveScale()/UIParent:GetEffectiveScale()
        AuctionFrame:ClearAllPoints()
        AuctionFrame:SetPoint('BOTTOMLEFT',UIParent,'BOTTOMLEFT',config.x/scale,config.y/scale)
        AuctionFrame:SetClampedToScreen(true)
    end
    local function resetAuctionPosition()
        AUCTIONATOR_SAVEDVARS.auctionFramePosition=nil
        AuctionFrame:StopMovingOrSizing();AuctionFrame:ClearAllPoints()
        for _,point in ipairs(originalPoints) do AuctionFrame:SetPoint(unpack(point)) end
    end
    local function resetDetailsPosition()
        AUCTIONATOR_SAVEDVARS.dealsDetailPosition=nil
        positionDetails()
    end
    -- Restore after Blizzard/skin OnShow handlers finish positioning the panel.
    local driver=CreateFrame('Frame','Atr_AuctionPositionRestore',UIParent)
    driver:Hide()
    driver:SetScript('OnUpdate',function(self) self:Hide();restoreAuctionPosition() end)
    AuctionFrame:HookScript('OnShow',function() driver:Show() end)
    AuctionFrame:HookScript('OnHide',saveAuctionPosition)
    if AuctionFrame:IsShown() then driver:Show() end
    mover:SetScript('OnDragStart',function()
        if AUCTIONATOR_SAVEDVARS.moveAuctionFrame==false then return end
        AuctionFrame:SetMovable(true);AuctionFrame:SetClampedToScreen(true);AuctionFrame:StartMoving()
    end)
    mover:SetScript('OnDragStop',function() AuctionFrame:StopMovingOrSizing();saveAuctionPosition() end)
    mover:EnableMouse(AUCTIONATOR_SAVEDVARS.moveAuctionFrame~=false)
    Atr_DealsDetailsReset:SetScript('OnClick',resetDetailsPosition)

    local appearance=CreateFrame('Frame','Atr_AppearanceOptions',UIParent)
    appearance.name='Appearance';appearance.parent='Auctionator'
    local function Z(s) return ZT and ZT(s) or s end
    local function text(label,x,y,font,width,height)
        local t=appearance:CreateFontString(nil,'OVERLAY',font)
        t:SetPoint('TOPLEFT',appearance,'TOPLEFT',x,y)
        if width then t:SetWidth(width);t:SetHeight(height);t:SetJustifyH('LEFT') end
        t:SetText(label);return t
    end
    text(Z('Appearance'),16,-16,'GameFontNormalLarge')
    text(Z('Window positions are saved automatically when you move or close the auction house.'),16,-48,'GameFontHighlightSmall',550,32)
    local choice=CreateFrame('CheckButton','Atr_AllowAuctionMovement',appearance,'UICheckButtonTemplate')
    Atr_AnalysisSkin(choice,'CheckBox');choice:SetSize(24,24);choice:SetPoint('TOPLEFT',appearance,'TOPLEFT',16,-90)
    _G[choice:GetName()..'Text']:SetText(Z('Allow moving the auction window'))
    choice:SetScript('OnClick',function(self)
        local enabled=self:GetChecked() and true or false
        AUCTIONATOR_SAVEDVARS.moveAuctionFrame=enabled
        AuctionFrame:StopMovingOrSizing();AuctionFrame:SetMovable(enabled);mover:EnableMouse(enabled)
    end)
    appearance:SetScript('OnShow',function() choice:SetChecked(AUCTIONATOR_SAVEDVARS.moveAuctionFrame~=false) end)
    text(Z('Drag the auction title to move AH. Drag Deal details to detach it from AH.'),20,-126,'GameFontHighlightSmall',550,30)
    local function button(name,label,y,callback)
        local b=CreateFrame('Button',name,appearance,'UIPanelButtonTemplate')
        Atr_AnalysisSkin(b,'Button');b:SetSize(200,24);b:SetPoint('TOPLEFT',appearance,'TOPLEFT',20,y)
        b:SetText(label);b:SetScript('OnClick',callback)
    end
    button('Atr_ResetAuctionPosition',Z('Reset auction window'),-180,resetAuctionPosition)
    button('Atr_ResetDetailsPosition',Z('Reset Deal details'),-220,resetDetailsPosition)
    text(Z('Reset Deal details places it beside AH and makes it follow the auction window again.'),236,-220,'GameFontHighlightSmall',310,42)
    text('Changes apply immediately. Shopping lists, prices and scan data are kept.',20,-284,'GameFontDisableSmall',550,30)
    if InterfaceOptions_AddCategory then InterfaceOptions_AddCategory(appearance) end
    appearance:Hide()
end
