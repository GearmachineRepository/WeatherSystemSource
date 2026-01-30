--!strict

local BoatAgentTypes = require(script.Parent:WaitForChild("BoatAgentTypes"))
local BoatAgentUtils = require(script.Parent:WaitForChild("BoatAgentUtils"))
local BoatAgentDebug = require(script.Parent:WaitForChild("BoatAgentDebug"))

local BoatAgentObstacle = {}

local WHISKER_COUNT = BoatAgentTypes.WHISKER_COUNT
local WHISKER_SPREAD_ANGLE = BoatAgentTypes.WHISKER_SPREAD_ANGLE
local TERRAIN_CHECK_INTERVAL = BoatAgentTypes.TERRAIN_CHECK_INTERVAL
local DEBUG_ENABLED = BoatAgentTypes.DEBUG_ENABLED

local NEAR_ZERO_THRESHOLD = BoatAgentTypes.NEAR_ZERO_THRESHOLD
local WHISKER_SPEED_DISTANCE_MULTIPLIER = BoatAgentTypes.WHISKER_SPEED_DISTANCE_MULTIPLIER
local WHISKER_CENTER_WEIGHT_REDUCTION = BoatAgentTypes.WHISKER_CENTER_WEIGHT_REDUCTION
local WHISKER_CLOSE_HIT_DISTANCE = BoatAgentTypes.WHISKER_CLOSE_HIT_DISTANCE
local WHISKER_CLOSE_HIT_BOOST = BoatAgentTypes.WHISKER_CLOSE_HIT_BOOST
local WHISKER_CENTER_IMPORTANCE = BoatAgentTypes.WHISKER_CENTER_IMPORTANCE
local WHISKER_FORWARD_BIAS_EXPONENT = BoatAgentTypes.WHISKER_FORWARD_BIAS_EXPONENT
local WHISKER_FORWARD_BIAS_BLOCKED_PENALTY = BoatAgentTypes.WHISKER_FORWARD_BIAS_BLOCKED_PENALTY
local WHISKER_SCORE_FORWARD_WEIGHT = BoatAgentTypes.WHISKER_SCORE_FORWARD_WEIGHT
local WHISKER_SCORE_BASE_WEIGHT = BoatAgentTypes.WHISKER_SCORE_BASE_WEIGHT

local BLOCKED_SCORE_MIN_THRESHOLD = BoatAgentTypes.BLOCKED_SCORE_MIN_THRESHOLD
local BLOCKED_SCORE_HIGH_THRESHOLD = BoatAgentTypes.BLOCKED_SCORE_HIGH_THRESHOLD
local BLOCKED_BLEND_ALPHA_OFFSET = BoatAgentTypes.BLOCKED_BLEND_ALPHA_OFFSET
local BLOCKED_BLEND_ALPHA_MULTIPLIER = BoatAgentTypes.BLOCKED_BLEND_ALPHA_MULTIPLIER

local CAN_SEE_DISTANCE_TOLERANCE = BoatAgentTypes.CAN_SEE_DISTANCE_TOLERANCE
local SEPARATION_SAFETY_CHECK_DISTANCE_MULTIPLIER = BoatAgentTypes.SEPARATION_SAFETY_CHECK_DISTANCE_MULTIPLIER

local ObstacleRaycastParams = RaycastParams.new()
ObstacleRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
ObstacleRaycastParams.FilterDescendantsInstances = {}
ObstacleRaycastParams.IgnoreWater = true

local BaseFilterInstances: {Instance} = {}

function BoatAgentObstacle.UpdateRaycastFilter(_ActiveAgents: {[Model]: any})
	local FilterInstances: {Instance} = {}

	local OceanFolder = workspace:FindFirstChild("Ocean")
	if OceanFolder then
		table.insert(FilterInstances, OceanFolder)
	end

	local WaterFolder = workspace:FindFirstChild("Water")
	if WaterFolder then
		table.insert(FilterInstances, WaterFolder)
	end

	BaseFilterInstances = FilterInstances
end

local function SetFilterForAgent(Agent: BoatAgentTypes.AgentData)
	local FilterInstances = table.clone(BaseFilterInstances)
	table.insert(FilterInstances, Agent.BoatModel)
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

function BoatAgentObstacle.IsSeparationDirectionSafe(Agent: BoatAgentTypes.AgentData, SeparationDirection: Vector3): boolean
	local Position = Agent.PrimaryPart.Position
	local RayOrigin = Vector3.new(Position.X, Position.Y + Agent.Geometry.RaycastHeight, Position.Z)
	local CheckDistance = Agent.Geometry.RaycastDistance * SEPARATION_SAFETY_CHECK_DISTANCE_MULTIPLIER

	local DidHit, HitDistance = CastObstacleRay(RayOrigin, SeparationDirection, CheckDistance)

	if DidHit then
		local SafetyMargin = Agent.Geometry.BoundingRadius * 2
		return HitDistance > SafetyMargin
	end

	return true
end

function BoatAgentObstacle.ComputeAvoidanceVector(Agent: BoatAgentTypes.AgentData): (Vector3, number)
	local CurrentTime = os.clock()
	if CurrentTime - Agent.State.LastTerrainCheckTime < TERRAIN_CHECK_INTERVAL then
		return Agent.State.CachedObstacleVector, Agent.State.CachedObstacleUrgency
	end
	Agent.State.LastTerrainCheckTime = CurrentTime

	SetFilterForAgent(Agent)

	local Position = Agent.PrimaryPart.Position
	local Forward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)

	local BaseDistance = Agent.Geometry.RaycastDistance + Agent.State.EstimatedSpeed * WHISKER_SPEED_DISTANCE_MULTIPLIER
	local RayOrigin = Vector3.new(Position.X, Position.Y + Agent.Geometry.RaycastHeight, Position.Z)

	local ClearScoreByIndex: {number} = table.create(WHISKER_COUNT, 1)
	local DirectionByIndex: {Vector3} = table.create(WHISKER_COUNT, Forward)

	local MaxBlockedScore = 0
	local RepulsionX = 0
	local RepulsionZ = 0

	local CenterWhiskerIndex = math.ceil(WHISKER_COUNT / 2)
	local CenterBlockedScore = 0

	for WhiskerIndex = 0, WHISKER_COUNT - 1 do
		local AngleFraction = (WhiskerIndex / (WHISKER_COUNT - 1)) - 0.5
		local AngleOffset = AngleFraction * WHISKER_SPREAD_ANGLE * 2

		local WhiskerCos = math.cos(AngleOffset)
		local WhiskerSin = math.sin(AngleOffset)

		local WhiskerDirX = Forward.X * WhiskerCos - Forward.Z * WhiskerSin
		local WhiskerDirZ = Forward.Z * WhiskerCos + Forward.X * WhiskerSin
		local WhiskerDirection = Vector3.new(WhiskerDirX, 0, WhiskerDirZ).Unit

		local CenterWeight = 1 - math.abs(AngleFraction) * WHISKER_CENTER_WEIGHT_REDUCTION
		local WhiskerDistance = BaseDistance * CenterWeight

		DirectionByIndex[WhiskerIndex + 1] = WhiskerDirection

		local DidHit, HitDistance, HitPosition = CastObstacleRay(RayOrigin, WhiskerDirection, WhiskerDistance)

		local ClearScore = 1
		local BlockedScore = 0

		if DidHit then
			local NormalizedHit = math.clamp(HitDistance / math.max(WhiskerDistance, NEAR_ZERO_THRESHOLD), 0, 1)
			ClearScore = NormalizedHit
			BlockedScore = 1 - NormalizedHit

			if HitDistance < WHISKER_CLOSE_HIT_DISTANCE then
				local CloseBoost = (1 - HitDistance / WHISKER_CLOSE_HIT_DISTANCE) * WHISKER_CLOSE_HIT_BOOST
				BlockedScore = math.clamp(BlockedScore + CloseBoost, 0, 1)
				ClearScore = 1 - BlockedScore
			end

			local CenterImportance = 1 + (1 - math.abs(AngleFraction) * 2) * WHISKER_CENTER_IMPORTANCE
			BlockedScore = math.clamp(BlockedScore * CenterImportance, 0, 1)
			ClearScore = 1 - BlockedScore

			if BlockedScore > MaxBlockedScore then
				MaxBlockedScore = BlockedScore
			end

			RepulsionX = RepulsionX - WhiskerDirection.X * BlockedScore
			RepulsionZ = RepulsionZ - WhiskerDirection.Z * BlockedScore

			if WhiskerIndex + 1 == CenterWhiskerIndex then
				CenterBlockedScore = BlockedScore
			end
		end

		ClearScoreByIndex[WhiskerIndex + 1] = ClearScore

		if DEBUG_ENABLED then
			BoatAgentDebug.DrawRayWithScore(RayOrigin, WhiskerDirection, WhiskerDistance, ClearScore, DidHit, HitPosition)
		end
	end

	local AdjustedForwardBiasExponent = WHISKER_FORWARD_BIAS_EXPONENT + CenterBlockedScore * WHISKER_FORWARD_BIAS_BLOCKED_PENALTY

	local BestDirection = Forward
	local BestScore = 0

	for WhiskerIndex = 0, WHISKER_COUNT - 1 do
		local Index = WhiskerIndex + 1
		local AngleFraction = (WhiskerIndex / (WHISKER_COUNT - 1)) - 0.5

		local ClearScore = ClearScoreByIndex[Index]
		local ForwardBias = (1 - math.abs(AngleFraction)) ^ AdjustedForwardBiasExponent
		local WeightedScore = ClearScore * (WHISKER_SCORE_BASE_WEIGHT + WHISKER_SCORE_FORWARD_WEIGHT * ForwardBias)

		if WeightedScore > BestScore then
			BestScore = WeightedScore
			BestDirection = DirectionByIndex[Index]
		end
	end

	local ResultVector: Vector3

	if MaxBlockedScore < BLOCKED_SCORE_MIN_THRESHOLD then
		ResultVector = Vector3.zero
	elseif MaxBlockedScore > BLOCKED_SCORE_HIGH_THRESHOLD then
		local RepulsionMagnitude = math.sqrt(RepulsionX * RepulsionX + RepulsionZ * RepulsionZ)
		if RepulsionMagnitude > NEAR_ZERO_THRESHOLD then
			local RepulsionNormX = RepulsionX / RepulsionMagnitude
			local RepulsionNormZ = RepulsionZ / RepulsionMagnitude

			local BlendAlpha = math.clamp((MaxBlockedScore - BLOCKED_BLEND_ALPHA_OFFSET) * BLOCKED_BLEND_ALPHA_MULTIPLIER, 0, 1)
			local BlendedX = BestDirection.X * (1 - BlendAlpha) + RepulsionNormX * BlendAlpha
			local BlendedZ = BestDirection.Z * (1 - BlendAlpha) + RepulsionNormZ * BlendAlpha

			local BlendedMagnitude = math.sqrt(BlendedX * BlendedX + BlendedZ * BlendedZ)
			if BlendedMagnitude > NEAR_ZERO_THRESHOLD then
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

local FLOCKING_RAY_HEIGHT_OFFSET = BoatAgentTypes.FLOCKING_RAY_HEIGHT_OFFSET

function BoatAgentObstacle.CanSeeOtherBoat(Agent: BoatAgentTypes.AgentData, OtherAgent: BoatAgentTypes.AgentData): boolean
	local AgentPos = Agent.PrimaryPart.Position
	local OtherPos = OtherAgent.PrimaryPart.Position
	local FromPosition = Vector3.new(AgentPos.X, AgentPos.Y + FLOCKING_RAY_HEIGHT_OFFSET, AgentPos.Z)
	local ToPosition = Vector3.new(OtherPos.X, OtherPos.Y + FLOCKING_RAY_HEIGHT_OFFSET, OtherPos.Z)

	local Direction = ToPosition - FromPosition
	local Distance = Direction.Magnitude
	if Distance < NEAR_ZERO_THRESHOLD then
		return true
	end

	local FilterInstances = table.clone(BaseFilterInstances)
	table.insert(FilterInstances, Agent.BoatModel)
	table.insert(FilterInstances, OtherAgent.BoatModel)

	local VisibilityParams = RaycastParams.new()
	VisibilityParams.FilterType = Enum.RaycastFilterType.Exclude
	VisibilityParams.FilterDescendantsInstances = FilterInstances
	VisibilityParams.IgnoreWater = true

	local RayResult = workspace:Raycast(FromPosition, Direction, VisibilityParams)
	if RayResult then
		local HitDistance = (RayResult.Position - FromPosition).Magnitude
		if HitDistance < Distance - CAN_SEE_DISTANCE_TOLERANCE then
			return false
		end
	end
	return true
end

return BoatAgentObstacle