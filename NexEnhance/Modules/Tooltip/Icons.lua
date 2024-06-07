local NexEnhance, NE_TooltipIcons = ...

local gsub, unpack, select = gsub, unpack, select
local GetSpellTexture = GetSpellTexture
local C_MountJournal_GetMountInfoByID = C_MountJournal.GetMountInfoByID
local newString = "0:0:64:64:5:59:5:59"

function NE_TooltipIcons:SetupTooltipIcon(icon)
	local title = icon and _G[self:GetName() .. "TextLeft1"]
	local titleText = title and title:GetText()
	if titleText and not strfind(titleText, ":16:16:") then
		title:SetFormattedText("|T%s:16:16:" .. newString .. ":%d|t %s", icon, 16, titleText)
	end

	for i = 2, self:NumLines() do
		local line = _G[self:GetName() .. "TextLeft" .. i]
		if not line then
			break
		end
		local text = line:GetText()
		if text and text ~= " " then
			local newText, count = gsub(text, "|T([^:]-):[%d+:]+|t", "|T%1:12:12:" .. newString .. "|t")
			if count > 0 then
				line:SetText(newText)
			end
		end
	end
end

function NE_TooltipIcons:HookTooltipCleared()
	self.tipModified = false
end

function NE_TooltipIcons:HookTooltipMethod()
	self:HookScript("OnTooltipCleared", NE_TooltipIcons.HookTooltipCleared)
end

local GetTooltipTextureByType = {
	[Enum.TooltipDataType.Item] = function(id)
		return C_Item.GetItemIconByID(id)
	end,
	[Enum.TooltipDataType.Toy] = function(id)
		return C_Item.GetItemIconByID(id)
	end,
	[Enum.TooltipDataType.Spell] = function(id)
		return GetSpellTexture(id)
	end,
	[Enum.TooltipDataType.Mount] = function(id)
		return select(3, C_MountJournal_GetMountInfoByID(id))
	end,
}

function NE_TooltipIcons:PLAYER_LOGIN()
	-- Add Icons
	NE_TooltipIcons.HookTooltipMethod(GameTooltip)
	NE_TooltipIcons.HookTooltipMethod(ItemRefTooltip)

	for tooltipType, getTex in next, GetTooltipTextureByType do
		TooltipDataProcessor.AddTooltipPostCall(tooltipType, function(self)
			if self == GameTooltip or self == ItemRefTooltip then
				local data = self:GetTooltipData()
				local id = data and data.id
				if id then
					NE_TooltipIcons.SetupTooltipIcon(self, getTex(id))
				end
			end
		end)
	end

	-- Cut Icons
	hooksecurefunc(GameTooltip, "SetUnitAura", function(self)
		NE_TooltipIcons.SetupTooltipIcon(self)
	end)

	hooksecurefunc(GameTooltip, "SetAzeriteEssence", function(self)
		NE_TooltipIcons.SetupTooltipIcon(self)
	end)
	hooksecurefunc(GameTooltip, "SetAzeriteEssenceSlot", function(self)
		NE_TooltipIcons.SetupTooltipIcon(self)
	end)
end
