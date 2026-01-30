--!strict

local BoatAgentTypes = require(script.Parent:WaitForChild("BoatAgentTypes"))

local BoatAgentUtils = {}

local NEAR_ZERO_THRESHOLD = BoatAgentTypes.NEAR_ZERO_THRESHOLD
local STEER_BEHIND_DOT_THRESHOLD = BoatAgentTypes.STEER_BEHIND_DOT_THRESHOLD
local STEER_URGENCY_THRESHOLD = BoatAgentTypes.STEER_URGENCY_THRESHOLD
local STEER_MAX_URGENCY_BOOST = BoatAgentTypes.STEER_MAX_URGENCY_BOOST
local STEER_URGENT_FULL_ANGLE = BoatAgentTypes.STEER_URGENT_FULL_ANGLE
local STEER_URGENT_MID_ANGLE = BoatAgentTypes.STEER_URGENT_MID_ANGLE
local STEER_URGENT_FULL_AMOUNT = BoatAgentTypes.STEER_URGENT_FULL_AMOUNT
local STEER_URGENT_MID_AMOUNT = BoatAgentTypes.STEER_URGENT_MID_AMOUNT
local STEER_URGENT_MIN_AMOUNT = BoatAgentTypes.STEER_URGENT_MIN_AMOUNT
local STEER_NORMAL_FULL_ANGLE = BoatAgentTypes.STEER_NORMAL_FULL_ANGLE
local STEER_NORMAL_MID_ANGLE = BoatAgentTypes.STEER_NORMAL_MID_ANGLE
local STEER_NORMAL_FULL_AMOUNT = BoatAgentTypes.STEER_NORMAL_FULL_AMOUNT
local STEER_NORMAL_MID_AMOUNT = BoatAgentTypes.STEER_NORMAL_MID_AMOUNT

function BoatAgentUtils.GetNumberAttribute(Model: Model, AttributeName: string, DefaultValue: number): number
	local AttributeValue = Model:GetAttribute(AttributeName)
	if typeof(AttributeValue) == "number" then
		return AttributeValue
	end
	return DefaultValue
end

function BoatAgentUtils.FindVehicleSeat(Model: Model): VehicleSeat?
	for _, Descendant in Model:GetDescendants() do
		if Descendant:IsA("VehicleSeat") then
			return Descendant
		end
	end
	return nil
end

function BoatAgentUtils.GetHorizontalLookVector(Part: BasePart): Vector3
	local LookVector = Part.CFrame.LookVector
	local FlatLookVector = Vector3.new(LookVector.X, 0, LookVector.Z)
	local FlatMagnitude = FlatLookVector.Magnitude
	if FlatMagnitude < NEAR_ZERO_THRESHOLD then
		return Vector3.new(0, 0, -1)
	end
	return FlatLookVector / FlatMagnitude
end

function BoatAgentUtils.GetHorizontalRightVector(Part: BasePart): Vector3
	local Forward = BoatAgentUtils.GetHorizontalLookVector(Part)
	return Vector3.new(-Forward.Z, 0, Forward.X)
end

function BoatAgentUtils.ComputeBoatDimensions(Model: Model): (number, number)
	local Size = Model:GetExtentsSize()
	local HalfWidth = Size.X * 0.5
	local HalfLength = Size.Z * 0.5
	return math.max(HalfWidth, HalfLength), HalfLength
end

function BoatAgentUtils.HashStringToSeed(Text: string): number
	local HashValue = 2166136261
	for Index = 1, #Text do
		HashValue = bit32.bxor(HashValue, string.byte(Text, Index))
		HashValue = (HashValue * 16777619) % 4294967296
	end
	return HashValue
end

function BoatAgentUtils.NormalizeVector2D(VectorX: number, VectorZ: number): (number, number, number)
	local Magnitude = math.sqrt(VectorX * VectorX + VectorZ * VectorZ)
	if Magnitude < NEAR_ZERO_THRESHOLD then
		return 0, 0, 0
	end
	return VectorX / Magnitude, VectorZ / Magnitude, Magnitude
end

function BoatAgentUtils.WriteControls(Model: Model, Throttle: number, Steer: number)
	Model:SetAttribute("AiThrottle", math.clamp(Throttle, -1, 1))
	Model:SetAttribute("AiSteer", math.clamp(Steer, -1, 1))
end

function BoatAgentUtils.IsWaterPart(Part: BasePart): boolean
	local PartName = Part.Name:lower()
	if PartName == "ocean" or PartName == "water" or PartName == "sea" then
		return true
	end
	if Part:HasTag("Water") or Part:HasTag("Ocean") then
		return true
	end
	if Part.Transparency > 0.8 and Part.CanCollide == false then
		return true
	end
	return false
end

function BoatAgentUtils.Lerp(ValueA: number, ValueB: number, Alpha: number): number
	return ValueA + (ValueB - ValueA) * Alpha
end

function BoatAgentUtils.ComputeSteerToward(Forward: Vector3, DesiredDirection: Vector3, Urgency: number?): number
	local DesiredMagnitude = DesiredDirection.Magnitude
	if DesiredMagnitude < NEAR_ZERO_THRESHOLD then
		return 0
	end

	local NormalizedDesired = DesiredDirection / DesiredMagnitude
	local CrossY = Forward.X * NormalizedDesired.Z - Forward.Z * NormalizedDesired.X
	local DotForward = Forward.X * NormalizedDesired.X + Forward.Z * NormalizedDesired.Z

	if DotForward < STEER_BEHIND_DOT_THRESHOLD then
		return if CrossY >= 0 then 1 else -1
	end

	local UrgencyMultiplier = Urgency or 1.0
	local TurnSign = if CrossY >= 0 then 1 else -1
	local AngleRad = math.atan2(math.abs(CrossY), DotForward)
	local AngleDeg = math.deg(AngleRad)

	local SteerAmount: number
	if UrgencyMultiplier > STEER_URGENCY_THRESHOLD then
		if AngleDeg > STEER_URGENT_FULL_ANGLE then
			SteerAmount = STEER_URGENT_FULL_AMOUNT
		elseif AngleDeg > STEER_URGENT_MID_ANGLE then
			local Range = STEER_URGENT_FULL_ANGLE - STEER_URGENT_MID_ANGLE
			local Progress = (AngleDeg - STEER_URGENT_MID_ANGLE) / Range
			SteerAmount = STEER_URGENT_MID_AMOUNT + Progress * (STEER_URGENT_FULL_AMOUNT - STEER_URGENT_MID_AMOUNT)
		else
			local Progress = AngleDeg / STEER_URGENT_MID_ANGLE
			SteerAmount = STEER_URGENT_MIN_AMOUNT + Progress * (STEER_URGENT_MID_AMOUNT - STEER_URGENT_MIN_AMOUNT)
		end
	else
		if AngleDeg > STEER_NORMAL_FULL_ANGLE then
			SteerAmount = STEER_NORMAL_FULL_AMOUNT
		elseif AngleDeg > STEER_NORMAL_MID_ANGLE then
			local Range = STEER_NORMAL_FULL_ANGLE - STEER_NORMAL_MID_ANGLE
			local Progress = (AngleDeg - STEER_NORMAL_MID_ANGLE) / Range
			SteerAmount = STEER_NORMAL_MID_AMOUNT + Progress * (STEER_NORMAL_FULL_AMOUNT - STEER_NORMAL_MID_AMOUNT)
		else
			local Progress = AngleDeg / STEER_NORMAL_MID_ANGLE
			SteerAmount = Progress * STEER_NORMAL_MID_AMOUNT
		end
	end

	SteerAmount = SteerAmount * TurnSign

	if UrgencyMultiplier > 1.0 then
		local BoostFactor = math.min(UrgencyMultiplier, STEER_MAX_URGENCY_BOOST)
		SteerAmount = SteerAmount * BoostFactor
	end

	return math.clamp(SteerAmount, -1, 1)
end

return BoatAgentUtils