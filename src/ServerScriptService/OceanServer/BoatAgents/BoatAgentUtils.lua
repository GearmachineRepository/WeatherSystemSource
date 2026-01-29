--!strict

local BoatAgentUtils = {}

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
	if FlatMagnitude < 0.001 then
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
	if Magnitude < 0.001 then
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
	if DesiredMagnitude < 0.001 then
		return 0
	end

	local NormalizedDesired = DesiredDirection / DesiredMagnitude
	local CrossY = Forward.X * NormalizedDesired.Z - Forward.Z * NormalizedDesired.X
	local DotForward = Forward.X * NormalizedDesired.X + Forward.Z * NormalizedDesired.Z

	if DotForward < -0.2 then
		return if CrossY >= 0 then 1 else -1
	end

	local UrgencyMultiplier = Urgency or 1.0
	local TurnSign = if CrossY >= 0 then 1 else -1
	local AngleRad = math.atan2(math.abs(CrossY), DotForward)
	local AngleDeg = math.deg(AngleRad)

	local SteerAmount: number
	if UrgencyMultiplier > 1.5 then
		if AngleDeg > 15 then
			SteerAmount = 1.0
		elseif AngleDeg > 5 then
			SteerAmount = 0.6 + (AngleDeg - 5) / 10 * 0.4
		else
			SteerAmount = 0.4 + AngleDeg / 5 * 0.2
		end
	else
		if AngleDeg > 25 then
			SteerAmount = 1.0
		elseif AngleDeg > 10 then
			SteerAmount = 0.5 + (AngleDeg - 10) / 15 * 0.5
		else
			SteerAmount = AngleDeg / 10 * 0.5
		end
	end

	SteerAmount = SteerAmount * TurnSign

	if UrgencyMultiplier > 1.0 then
		local BoostFactor = math.min(UrgencyMultiplier, 3.0)
		SteerAmount = SteerAmount * BoostFactor
	end

	return math.clamp(SteerAmount, -1, 1)
end

return BoatAgentUtils