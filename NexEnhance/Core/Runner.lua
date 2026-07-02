--[[
	NexEnhance - Runner
	-------------------------------------------------------------------------
	Spread heavy work across frames with a per-frame time budget (AllTheThings
	Runner pattern). Use for nameplate refreshes, large roster scans, etc.
--]]

local _, ns = ...

local CreateFrame = CreateFrame
local debugprofilestart = debugprofilestart
local debugprofilestop = debugprofilestop
local wipe = wipe

local DEFAULT_BUDGET_MS = 6

local RunnerMeta = {}
RunnerMeta.__index = RunnerMeta

function RunnerMeta:SetBudgetMs(ms)
	self.budgetMs = ms or DEFAULT_BUDGET_MS
end

function RunnerMeta:Cancel()
	if self.frame then
		self.frame:SetScript("OnUpdate", nil)
		self.frame:Hide()
	end
	self.index = 1
	wipe(self.queue)
	self.onComplete = nil
	self.running = false
end

function RunnerMeta:Tick()
	if not self.running then
		return
	end

	debugprofilestart()
	local budget = self.budgetMs or DEFAULT_BUDGET_MS
	local processFn = self.processFn

	while self.index <= #self.queue do
		local item = self.queue[self.index]
		self.index = self.index + 1
		local ok, err = pcall(processFn, item)
		-- One bad nameplate/widget must not error every frame until /reload.
		if not ok and ns.Debug then
			ns.Debug.Log(self.name or "runner", "fail", "process error: %s", err)
		end
		if debugprofilestop() >= budget then
			debugprofilestart()
			return
		end
		debugprofilestart()
	end

	self:Cancel()
	local onComplete = self.onComplete
	if onComplete then
		onComplete()
	end
end

--- Queue `items` and call `processFn(item)` spread across frames.
--- Optional `onComplete` runs once when the queue is drained.
function RunnerMeta:Run(items, processFn, onComplete)
	self:Cancel()
	if not items or #items == 0 then
		if onComplete then
			onComplete()
		end
		return
	end

	for i = 1, #items do
		self.queue[i] = items[i]
	end
	self.index = 1
	self.processFn = processFn
	self.onComplete = onComplete
	self.running = true

	if not self.frame then
		self.frame = CreateFrame("Frame")
	end
	self.frame:SetScript("OnUpdate", function()
		self:Tick()
	end)
	self.frame:Show()
end

--- Create a named runner (`name` is diagnostic only).
function ns:CreateRunner(name, budgetMs)
	local runner = setmetatable({
		name = name,
		budgetMs = budgetMs or DEFAULT_BUDGET_MS,
		queue = {},
		index = 1,
	}, RunnerMeta)
	return runner
end
