--!strict

local Lighting: Lighting = game:GetService("Lighting")
local RunService: RunService = game:GetService("RunService")

local DAY_LENGTH_SECONDS: number = 600
local HOURS_PER_DAY: number = 24
local SECONDS_PER_HOUR: number = DAY_LENGTH_SECONDS / HOURS_PER_DAY

local function AdvanceClockTime(DeltaSeconds: number)
	local HoursToAdvance: number = DeltaSeconds / SECONDS_PER_HOUR
	local NewClockTime: number = (Lighting.ClockTime + HoursToAdvance) % 24
	Lighting.ClockTime = NewClockTime
end

local PreviousTimestamp: number = os.clock()

RunService.Heartbeat:Connect(function()
	local CurrentTimestamp: number = os.clock()
	local DeltaSeconds: number = CurrentTimestamp - PreviousTimestamp
	PreviousTimestamp = CurrentTimestamp

	AdvanceClockTime(DeltaSeconds)
end)
