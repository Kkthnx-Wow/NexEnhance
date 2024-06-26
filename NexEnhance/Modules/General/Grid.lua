-- Grid module
local _, Module = ...

-- Variables
local gridFrame
local boxSize = 32
local isAligning = false

-- Function to create the grid
local function CreateGrid()
	gridFrame = CreateFrame("Frame", nil, UIParent)
	gridFrame.boxSize = boxSize
	gridFrame:SetAllPoints(UIParent)

	local size = 2
	local width = GetScreenWidth()
	local ratio = width / GetScreenHeight()
	local height = GetScreenHeight() * ratio

	local wStep = width / boxSize
	local hStep = height / boxSize

	-- Vertical lines
	for i = 0, boxSize do
		local texture = gridFrame:CreateTexture(nil, "BACKGROUND")
		if i == boxSize / 2 then
			texture:SetColorTexture(1, 0, 0, 0.5) -- Red color for center line
		else
			texture:SetColorTexture(0, 0, 0, 0.5) -- Black color for other lines
		end
		texture:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", i * wStep - (size / 2), 0)
		texture:SetPoint("BOTTOMRIGHT", gridFrame, "BOTTOMLEFT", i * wStep + (size / 2), 0)
	end
	height = GetScreenHeight()

	-- Horizontal lines
	-- Center line
	do
		local texture = gridFrame:CreateTexture(nil, "BACKGROUND")
		texture:SetColorTexture(1, 0, 0, 0.5) -- Red color for center line
		texture:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(height / 2) + (size / 2))
		texture:SetPoint("BOTTOMRIGHT", gridFrame, "TOPRIGHT", 0, -(height / 2 + size / 2))
	end

	-- Other lines above and below center
	for i = 1, math.floor((height / 2) / hStep) do
		local texture1 = gridFrame:CreateTexture(nil, "BACKGROUND")
		local texture2 = gridFrame:CreateTexture(nil, "BACKGROUND")

		texture1:SetColorTexture(0, 0, 0, 0.5)
		texture1:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(height / 2 + i * hStep) + (size / 2))
		texture1:SetPoint("BOTTOMRIGHT", gridFrame, "TOPRIGHT", 0, -(height / 2 + i * hStep + size / 2))

		texture2:SetColorTexture(0, 0, 0, 0.5)
		texture2:SetPoint("TOPLEFT", gridFrame, "TOPLEFT", 0, -(height / 2 - i * hStep) + (size / 2))
		texture2:SetPoint("BOTTOMRIGHT", gridFrame, "TOPRIGHT", 0, -(height / 2 - i * hStep + size / 2))
	end
end

-- Function to show or recreate the grid
local function ShowGrid()
	if not gridFrame then
		CreateGrid()
	elseif gridFrame.boxSize ~= boxSize then
		gridFrame:Hide()
		CreateGrid()
	else
		gridFrame:Show()
	end
end

-- Slash command handler
SlashCmdList["TOGGLEGRID"] = function(arg)
	if isAligning or arg == "1" then
		if gridFrame then
			gridFrame:Hide()
		end
		isAligning = false
	else
		boxSize = math.ceil((tonumber(arg) or boxSize) / 32) * 32
		if boxSize > 256 then
			boxSize = 256
		end
		ShowGrid()
		isAligning = true
	end
end
SLASH_TOGGLEGRID1 = "/ng"
