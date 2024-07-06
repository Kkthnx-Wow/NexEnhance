local addonName, Config = ...

-- Constants for commonly used values
local EDITBOX_WIDTH = 250
local EDITBOX_HEIGHT = 20
local ICON_SIZE = 32
local ICON_OFFSET = 4
local EDITBOX_SPACING = 60
local DISCORD_LINK = "https://discord.gg/Rc9wcK9cAB"
local PATREON_LINK = "https://www.patreon.com/kkthnx"
local PAYPAL_LINK = "https://paypal.me/kkthnxtv"

-- Function to create a read-only EditBox
local function CreateReadOnlyEditBox(parent, point, relativeTo, relativePoint, xOffset, yOffset, width, height, text)
	local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
	editBox:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)
	editBox:SetSize(width, height)
	editBox:SetAutoFocus(false)
	editBox:SetFontObject("ChatFontNormal")
	editBox:SetText(text)
	editBox:SetCursorPosition(0)
	editBox:ClearFocus()

	editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
	editBox:SetScript("OnTextChanged", function(self)
		self:SetText(text)
	end)
	editBox:SetScript("OnCursorChanged", function() end)
	editBox:SetScript("OnEditFocusGained", editBox.HighlightText)
	editBox:SetScript("OnMouseUp", function(self)
		if not self:IsMouseOver() then
			self:ClearFocus()
		end
	end)

	return editBox
end

-- Function to create an icon texture
local function CreateIconTexture(parent, texturePath, point, relativeTo, relativePoint, xOffset, yOffset)
	local texture = parent:CreateTexture(nil, "ARTWORK")
	texture:SetTexture(texturePath)
	texture:SetSize(ICON_SIZE, ICON_SIZE)
	texture:SetPoint(point, relativeTo, relativePoint, xOffset, yOffset)
	return texture
end

-- Function to create the support GUI
local function CreateSupportGUI()
	local supportFrame = CreateFrame("Frame", addonName)
	supportFrame.name = "Support"
	supportFrame.parent = addonName

	local title = supportFrame:CreateFontString("$parentTitle", "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOP", supportFrame, "TOP", 0, -15)
	title:SetText(supportFrame.name)

	local description = supportFrame:CreateFontString("$parentDescription", "ARTWORK", "GameFontHighlight")
	description:SetPoint("TOP", title, "BOTTOM", 0, -8)
	description:SetText("Support goes a long way. Supporting NexEnhance helps with the development of the addon.|nJust using the addon means the world and is great support as well.")

	local backgroundImage = supportFrame:CreateTexture(nil, "BACKGROUND")
	backgroundImage:SetTexture(Config.Logo256)
	backgroundImage:SetBlendMode("BLEND")
	backgroundImage:SetAlpha(0.1)
	backgroundImage:SetPoint("CENTER", supportFrame)

	-- Create Discord link EditBox and icon
	local discordLinkEditBox = CreateReadOnlyEditBox(supportFrame, "TOP", supportFrame, "TOP", 0, -210, EDITBOX_WIDTH, EDITBOX_HEIGHT, DISCORD_LINK)
	local joinDiscordIcon = CreateIconTexture(supportFrame, Config.Discord64, "BOTTOM", discordLinkEditBox, "TOP", 0, ICON_OFFSET)

	-- Create Patreon link EditBox and icon
	local patreonEditBox = CreateReadOnlyEditBox(supportFrame, "TOP", discordLinkEditBox, "BOTTOM", 0, -EDITBOX_SPACING, EDITBOX_WIDTH, EDITBOX_HEIGHT, PATREON_LINK)
	local patreonIcon = CreateIconTexture(supportFrame, Config.Patreon64, "BOTTOM", patreonEditBox, "TOP", 0, ICON_OFFSET)

	-- Create PayPal link EditBox and icon
	local paypalEditBox = CreateReadOnlyEditBox(supportFrame, "TOP", patreonEditBox, "BOTTOM", 0, -EDITBOX_SPACING, EDITBOX_WIDTH, EDITBOX_HEIGHT, PAYPAL_LINK)
	local paypalIcon = CreateIconTexture(supportFrame, Config.PayPal64, "BOTTOM", paypalEditBox, "TOP", 0, ICON_OFFSET)

	InterfaceOptions_AddCategory(supportFrame) -- DEPRECATED
	return supportFrame
end

-- Create the support GUI once
function Config.CreateSupportGUI()
	Config.CreateSupportGUI = Config.Dummy -- Ensure this is only executed once
	CreateSupportGUI()
end
