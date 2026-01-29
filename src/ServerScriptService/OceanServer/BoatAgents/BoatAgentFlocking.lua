--!strict

local BoatAgentTypes = require(script.Parent:WaitForChild("BoatAgentTypes"))
local BoatAgentUtils = require(script.Parent:WaitForChild("BoatAgentUtils"))
local BoatAgentObstacle = require(script.Parent:WaitForChild("BoatAgentObstacle"))
local BoatAgentDebug = require(script.Parent:WaitForChild("BoatAgentDebug"))

local BoatAgentFlocking = {}

local DEBUG_ENABLED = BoatAgentTypes.DEBUG_ENABLED

function BoatAgentFlocking.ComputeSeparationVector(Agent: BoatAgentTypes.AgentData, ActiveAgents: {[Model]: BoatAgentTypes.AgentData}): Vector3
	local BoatPosition = Agent.PrimaryPart.Position
	local BoatX = BoatPosition.X
	local BoatZ = BoatPosition.Z
	local VelocityX = Agent.State.EstimatedVelocityX
	local VelocityZ = Agent.State.EstimatedVelocityZ
	local Forward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)

	local SeparationX = 0
	local SeparationZ = 0

	for _, OtherAgent in pairs(ActiveAgents) do
		if OtherAgent == Agent then
			continue
		end

		local OtherPosition = OtherAgent.PrimaryPart.Position
		local OtherX = OtherPosition.X
		local OtherZ = OtherPosition.Z

		local DeltaX = BoatX - OtherX
		local DeltaZ = BoatZ - OtherZ
		local DistanceSquared = DeltaX * DeltaX + DeltaZ * DeltaZ
		local CurrentDistance = math.sqrt(DistanceSquared)

		if CurrentDistance < 0.001 then
			SeparationX = SeparationX + Agent.RandomGenerator:NextNumber(-1, 1)
			SeparationZ = SeparationZ + Agent.RandomGenerator:NextNumber(-1, 1)
			continue
		end

		local CombinedRadius = Agent.Geometry.BoundingRadius + OtherAgent.Geometry.BoundingRadius
		local MinDistance = math.max(Agent.Config.MinSeparationDistance, CombinedRadius * 2)
		local DetectionRange = MinDistance * 3

		if CurrentDistance > DetectionRange then
			continue
		end

		local RayOrigin = Vector3.new(BoatX, BoatPosition.Y + 3, BoatZ)
		local RayTarget = Vector3.new(OtherX, OtherPosition.Y + 3, OtherZ)
		if not BoatAgentObstacle.CanSeeOtherBoat(RayOrigin, RayTarget) then
			continue
		end

		local FutureTime = math.min(Agent.Config.LookaheadTime, 3.0)
		local FutureAgentX = BoatX + VelocityX * FutureTime
		local FutureAgentZ = BoatZ + VelocityZ * FutureTime
		local FutureOtherX = OtherX + OtherAgent.State.EstimatedVelocityX * FutureTime
		local FutureOtherZ = OtherZ + OtherAgent.State.EstimatedVelocityZ * FutureTime

		local FutureDeltaX = FutureAgentX - FutureOtherX
		local FutureDeltaZ = FutureAgentZ - FutureOtherZ
		local FutureDistance = math.sqrt(FutureDeltaX * FutureDeltaX + FutureDeltaZ * FutureDeltaZ)

		local ThreatDistance = math.min(CurrentDistance, FutureDistance)

		local DirectionX = DeltaX / CurrentDistance
		local DirectionZ = DeltaZ / CurrentDistance

		local ToOtherDotForward = -DirectionX * Forward.X + -DirectionZ * Forward.Z
		local InFront = ToOtherDotForward > 0

		local Strength: number
		if ThreatDistance < MinDistance then
			Strength = (MinDistance / math.max(ThreatDistance, 1)) * 3
		else
			local NormalizedDistance = (ThreatDistance - MinDistance) / (DetectionRange - MinDistance)
			Strength = (1 - NormalizedDistance) * (1 - NormalizedDistance)
		end

		if InFront then
			Strength = Strength * 1.5
		end

		if FutureDistance < CurrentDistance then
			Strength = Strength * 1.5
		end

		SeparationX = SeparationX + DirectionX * Strength
		SeparationZ = SeparationZ + DirectionZ * Strength
	end

	local ResultVector = Vector3.new(SeparationX, 0, SeparationZ)

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawSeparationVector(BoatPosition, ResultVector)
	end

	return ResultVector
end

function BoatAgentFlocking.ComputeAlignmentVector(Agent: BoatAgentTypes.AgentData, ActiveAgents: {[Model]: BoatAgentTypes.AgentData}): Vector3
	local BoatPosition = Agent.PrimaryPart.Position
	local AlignmentRange = Agent.Geometry.BoundingRadius * 8

	local TotalVelocityX = 0
	local TotalVelocityZ = 0
	local NeighborCount = 0

	for _, OtherAgent in pairs(ActiveAgents) do
		if OtherAgent == Agent then
			continue
		end

		local OtherPosition = OtherAgent.PrimaryPart.Position
		local DeltaX = BoatPosition.X - OtherPosition.X
		local DeltaZ = BoatPosition.Z - OtherPosition.Z
		local DistanceSquared = DeltaX * DeltaX + DeltaZ * DeltaZ

		if DistanceSquared > AlignmentRange * AlignmentRange then
			continue
		end

		TotalVelocityX = TotalVelocityX + OtherAgent.State.EstimatedVelocityX
		TotalVelocityZ = TotalVelocityZ + OtherAgent.State.EstimatedVelocityZ
		NeighborCount = NeighborCount + 1
	end

	if NeighborCount == 0 then
		return Vector3.zero
	end

	local AverageVelocityX = TotalVelocityX / NeighborCount
	local AverageVelocityZ = TotalVelocityZ / NeighborCount

	local DesiredChangeX = AverageVelocityX - Agent.State.EstimatedVelocityX
	local DesiredChangeZ = AverageVelocityZ - Agent.State.EstimatedVelocityZ

	return Vector3.new(DesiredChangeX, 0, DesiredChangeZ)
end

return BoatAgentFlocking