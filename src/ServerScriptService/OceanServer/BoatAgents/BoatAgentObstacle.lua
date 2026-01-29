--!strict

local BoatAgentTypes = require(script.Parent:WaitForChild("BoatAgentTypes"))
local BoatAgentUtils = require(script.Parent:WaitForChild("BoatAgentUtils"))
local BoatAgentDebug = require(script.Parent:WaitForChild("BoatAgentDebug"))

local BoatAgentObstacle = {}

local WHISKER_COUNT = BoatAgentTypes.WHISKER_COUNT
local WHISKER_SPREAD_ANGLE = BoatAgentTypes.WHISKER_SPREAD_ANGLE
local TERRAIN_CHECK_INTERVAL = BoatAgentTypes.TERRAIN_CHECK_INTERVAL
local DEBUG_ENABLED = BoatAgentTypes.DEBUG_ENABLED

local ObstacleRaycastParams = RaycastParams.new()
ObstacleRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
ObstacleRaycastParams.FilterDescendantsInstances = {}
ObstacleRaycastParams.IgnoreWater = true

function BoatAgentObstacle.UpdateRaycastFilter(ActiveAgents: {[Model]: any})
	local FilterInstances: {Instance} = {}

	local CollectionService = game:GetService("CollectionService")

	for BoatModel, _ in pairs(ActiveAgents) do
		table.insert(FilterInstances, BoatModel)
	end

	for _, TaggedBoat in CollectionService:GetTagged(BoatAgentTypes.BOAT_TAG) do
		if not ActiveAgents[TaggedBoat :: Model] then
			table.insert(FilterInstances, TaggedBoat)
		end
	end

	local OceanFolder = workspace:FindFirstChild("Ocean")
	if OceanFolder then
		table.insert(FilterInstances, OceanFolder)
	end

	local WaterFolder = workspace:FindFirstChild("Water")
	if WaterFolder then
		table.insert(FilterInstances, WaterFolder)
	end

	ObstacleRaycastParams.FilterDescendantsInstances = FilterInstances
end

local function CastObstacleRay(Origin: Vector3, Direction: Vector3, Distance: number): (boolean, number, Vector3?)
	local RayResult = workspace:Raycast(Origin, Direction * Distance, ObstacleRaycastParams)

	if RayResult then
		local HitPart = RayResult.Instance
		if HitPart:IsA("BasePart") and BoatAgentUtils.IsWaterPart(HitPart) then
			return false, Distance, nil
		end

		local HitDistance = (RayResult.Position - Origin).Magnitude
		return true, HitDistance, RayResult.Position
	end

	return false, Distance, nil
end

function BoatAgentObstacle.ComputeAvoidanceVector(Agent: BoatAgentTypes.AgentData): (Vector3, number)
	local CurrentTime = os.clock()
	if CurrentTime - Agent.State.LastTerrainCheckTime < TERRAIN_CHECK_INTERVAL then
		return Agent.State.CachedObstacleVector, Agent.State.CachedObstacleUrgency
	end
	Agent.State.LastTerrainCheckTime = CurrentTime

	local Position = Agent.PrimaryPart.Position
	local Forward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)
	local _RightVector = BoatAgentUtils.GetHorizontalRightVector(Agent.PrimaryPart)

	local BaseDistance = Agent.Geometry.RaycastDistance + Agent.State.EstimatedSpeed * 1.5
	local RayOrigin = Vector3.new(Position.X, Position.Y + Agent.Geometry.RaycastHeight, Position.Z)

	local ClearScoreByIndex: {number} = table.create(WHISKER_COUNT, 1)
	local DirectionByIndex: {Vector3} = table.create(WHISKER_COUNT, Forward)

	local MaxBlockedScore = 0
	local RepulsionX = 0
	local RepulsionZ = 0

	for WhiskerIndex = 0, WHISKER_COUNT - 1 do
		local AngleFraction = (WhiskerIndex / (WHISKER_COUNT - 1)) - 0.5
		local AngleOffset = AngleFraction * WHISKER_SPREAD_ANGLE * 2

		local WhiskerCos = math.cos(AngleOffset)
		local WhiskerSin = math.sin(AngleOffset)

		local WhiskerDirX = Forward.X * WhiskerCos - Forward.Z * WhiskerSin
		local WhiskerDirZ = Forward.Z * WhiskerCos + Forward.X * WhiskerSin
		local WhiskerDirection = Vector3.new(WhiskerDirX, 0, WhiskerDirZ).Unit

		local CenterWeight = 1 - math.abs(AngleFraction) * 0.4
		local WhiskerDistance = BaseDistance * CenterWeight

		DirectionByIndex[WhiskerIndex + 1] = WhiskerDirection

		local DidHit, HitDistance, HitPosition = CastObstacleRay(RayOrigin, WhiskerDirection, WhiskerDistance)

		local ClearScore = 1
		local BlockedScore = 0

		if DidHit then
			local NormalizedHit = math.clamp(HitDistance / math.max(WhiskerDistance, 0.001), 0, 1)
			ClearScore = NormalizedHit
			BlockedScore = 1 - NormalizedHit

			if HitDistance < 15 then
				local CloseBoost = (1 - HitDistance / 15) * 0.5
				BlockedScore = math.clamp(BlockedScore + CloseBoost, 0, 1)
				ClearScore = 1 - BlockedScore
			end

			local CenterImportance = 1 + (1 - math.abs(AngleFraction) * 2) * 0.8
			BlockedScore = math.clamp(BlockedScore * CenterImportance, 0, 1)
			ClearScore = 1 - BlockedScore

			if BlockedScore > MaxBlockedScore then
				MaxBlockedScore = BlockedScore
			end

			RepulsionX = RepulsionX - WhiskerDirection.X * BlockedScore
			RepulsionZ = RepulsionZ - WhiskerDirection.Z * BlockedScore
		end

		ClearScoreByIndex[WhiskerIndex + 1] = ClearScore

		if DEBUG_ENABLED then
			BoatAgentDebug.DrawRayWithScore(RayOrigin, WhiskerDirection, WhiskerDistance, ClearScore, DidHit, HitPosition)
		end
	end

	local BestDirection = Forward
	local BestScore = 0

	for WhiskerIndex = 0, WHISKER_COUNT - 1 do
		local Index = WhiskerIndex + 1
		local AngleFraction = (WhiskerIndex / (WHISKER_COUNT - 1)) - 0.5

		local ClearScore = ClearScoreByIndex[Index]
		local ForwardBias = (1 - math.abs(AngleFraction)) ^ 1.5
		local WeightedScore = ClearScore * (0.3 + 0.7 * ForwardBias)

		if WeightedScore > BestScore then
			BestScore = WeightedScore
			BestDirection = DirectionByIndex[Index]
		end
	end

	local ResultVector: Vector3

	if MaxBlockedScore < 0.05 then
		ResultVector = Vector3.zero
	elseif MaxBlockedScore > 0.7 then
		local RepulsionMagnitude = math.sqrt(RepulsionX * RepulsionX + RepulsionZ * RepulsionZ)
		if RepulsionMagnitude > 0.001 then
			local RepulsionNormX = RepulsionX / RepulsionMagnitude
			local RepulsionNormZ = RepulsionZ / RepulsionMagnitude

			local BlendAlpha = math.clamp((MaxBlockedScore - 0.5) * 2, 0, 1)
			local BlendedX = BestDirection.X * (1 - BlendAlpha) + RepulsionNormX * BlendAlpha
			local BlendedZ = BestDirection.Z * (1 - BlendAlpha) + RepulsionNormZ * BlendAlpha

			local BlendedMagnitude = math.sqrt(BlendedX * BlendedX + BlendedZ * BlendedZ)
			if BlendedMagnitude > 0.001 then
				ResultVector = Vector3.new(BlendedX / BlendedMagnitude, 0, BlendedZ / BlendedMagnitude)
			else
				ResultVector = BestDirection
			end
		else
			ResultVector = BestDirection
		end
	else
		ResultVector = BestDirection
	end

	Agent.State.CachedObstacleVector = ResultVector
	Agent.State.CachedObstacleUrgency = MaxBlockedScore

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawObstacleVector(Position, ResultVector)
	end

	return ResultVector, MaxBlockedScore
end

function BoatAgentObstacle.CanSeeOtherBoat(FromPosition: Vector3, ToPosition: Vector3): boolean
	local Direction = ToPosition - FromPosition
	local Distance = Direction.Magnitude
	if Distance < 0.001 then
		return true
	end

	local RayResult = workspace:Raycast(FromPosition, Direction, ObstacleRaycastParams)
	if RayResult then
		local HitDistance = (RayResult.Position - FromPosition).Magnitude
		if HitDistance < Distance - 5 then
			return false
		end
	end
	return true
end

return BoatAgentObstacle