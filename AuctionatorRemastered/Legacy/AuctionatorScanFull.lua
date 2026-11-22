-- Original full-scan window layout only; lifecycle lives in Remastered/Integration/FullScan.lua.
local _,gCanQueryAll

function Atr_ShowFullScanFrame()

	Atr_FullScanHTML:Show();
	Atr_FullScanResults:Hide();
	
	if (AuctionFrame and Atr_Mask and Atr_FullScanFrame) then
		Atr_Mask:SetPoint("TOPLEFT", AuctionFrame, "TOPLEFT", 12, 0)
		Atr_FullScanFrame:SetPoint("TOPLEFT", Atr_Mask, "TOPLEFT", 140, -24)
	end
	
	Atr_FullScanFrame:Show();
	Atr_FullScanFrame:SetBackdropColor(0,0,0,100);
	
	Atr_UpdateFullScanFrame();
	Atr_FullScanStatus:SetText ("");

	local expText = "<html><body>"
					.."<p>"
					..ZT("SCAN_EXPLANATION")
					.."</p>"
					.."</body></html>"
					;



	Atr_FullScanHTML:SetText (expText);
	Atr_FullScanHTML:SetSpacing (3);
end

-----------------------------------------

function Atr_UpdateFullScanFrame()

	Atr_FullScanDBsize:SetText (Atr_GetDBsize());
	
	local health=Atr_GetDatabaseHealth and Atr_GetDatabaseHealth()
	local lastScan=health and health.lastScan and health.lastScan.finished
	if not health then lastScan=AUCTIONATOR_LAST_SCAN_TIME end
	if (lastScan) then
		Atr_FullScanDBwhen:SetText (date ("%A, %B %d at %I:%M %p", lastScan));
	else
		Atr_FullScanDBwhen:SetText (ZT("Never"));
	end

	_, gCanQueryAll = CanSendAuctionQuery();

	if (gCanQueryAll) then
		Atr_FullScanStatus:SetText ("");
		Atr_FullScanStartButton:Enable();
		Atr_FullScanNext:SetText(ZT("Now"));
	else	
		Atr_FullScanStartButton:Disable();

		if (AUCTIONATOR_LAST_SCAN_TIME) then
			local when = 15*60 - (time() - AUCTIONATOR_LAST_SCAN_TIME);
		
			when = math.floor (when/60);
		
			if (when == 0) then
				Atr_FullScanNext:SetText (ZT("in less than a minute"));
			elseif (when == 1) then
				Atr_FullScanNext:SetText (ZT("in about one minute"));
			elseif (when > 0) then
				Atr_FullScanNext:SetText (string.format (ZT("in about %d minutes"), when));
			else
				Atr_FullScanNext:SetText (ZT("unknown"));
			end
		else
			Atr_FullScanNext:SetText (ZT("unknown"));
		end
	end
end

-----------------------------------------

