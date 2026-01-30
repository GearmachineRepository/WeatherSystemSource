--!strict

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local BoatAgentTypes = require(script:WaitForChild("BoatAgentTypes"))
local BoatAgentUtils = require(script:WaitForChild("BoatAgentUtils"))
local BoatAgentObstacle = require(script:WaitForChild("BoatAgentObstacle"))
local BoatAgentFlocking = require(script:WaitForChild("BoatAgentFlocking"))
local BoatAgentDebug = require(script:WaitForChild("BoatAgentDebug"))

local AGENT_TAG = BoatAgentTypes.AGENT_TAG
local BOAT_TAG = BoatAgentTypes.BOAT_TAG
local DEBUG_ENABLED = BoatAgentTypes.DEBUG_ENABLED

local NEAR_ZERO_THRESHOLD = BoatAgentTypes.NEAR_ZERO_THRESHOLD
local VELOCITY_SMOOTHING_FACTOR = BoatAgentTypes.VELOCITY_SMOOTHING_FACTOR
local STEER_SMOOTHING_FACTOR = BoatAgentTypes.STEER_SMOOTHING_FACTOR

local CRITICAL_OBSTACLE_THRESHOLD = BoatAgentTypes.CRITICAL_OBSTACLE_THRESHOLD
local OBSTACLE_STEER_URGENCY_MULTIPLIER = BoatAgentTypes.OBSTACLE_STEER_URGENCY_MULTIPLIER
local OBSTACLE_THROTTLE_REDUCTION = BoatAgentTypes.OBSTACLE_THROTTLE_REDUCTION
local OBSTACLE_MIN_THROTTLE = BoatAgentTypes.OBSTACLE_MIN_THROTTLE
local OBSTACLE_ESCAPE_RIGHT_BLEND = BoatAgentTypes.OBSTACLE_ESCAPE_RIGHT_BLEND

local STUCK_SPEED_THRESHOLD = BoatAgentTypes.STUCK_SPEED_THRESHOLD
local STUCK_OBSTACLE_THRESHOLD = BoatAgentTypes.STUCK_OBSTACLE_THRESHOLD
local STUCK_STEER_URGENCY_BOOST = BoatAgentTypes.STUCK_STEER_URGENCY_BOOST
local STUCK_MIN_THROTTLE = BoatAgentTypes.STUCK_MIN_THROTTLE

local SEPARATION_MAGNITUDE_THRESHOLD = BoatAgentTypes.SEPARATION_MAGNITUDE_THRESHOLD
local SEPARATION_STEER_URGENCY_MULTIPLIER = BoatAgentTypes.SEPARATION_STEER_URGENCY_MULTIPLIER
local SEPARATION_THROTTLE_REDUCTION = BoatAgentTypes.SEPARATION_THROTTLE_REDUCTION
local SEPARATION_MIN_THROTTLE = BoatAgentTypes.SEPARATION_MIN_THROTTLE

local SEPARATION_OBSTACLE_CONFLICT_THRESHOLD = BoatAgentTypes.SEPARATION_OBSTACLE_CONFLICT_THRESHOLD
local SEPARATION_OBSTACLE_CONFLICT_REDUCTION = BoatAgentTypes.SEPARATION_OBSTACLE_CONFLICT_REDUCTION

local DIRECTION_COMMITMENT_DURATION = BoatAgentTypes.DIRECTION_COMMITMENT_DURATION
local DIRECTION_COMMITMENT_URGENCY_THRESHOLD = BoatAgentTypes.DIRECTION_COMMITMENT_URGENCY_THRESHOLD

local NORMAL_OBSTACLE_BOOST_MULTIPLIER = BoatAgentTypes.NORMAL_OBSTACLE_BOOST_MULTIPLIER
local NORMAL_OBSTACLE_URGENCY_THRESHOLD = BoatAgentTypes.NORMAL_OBSTACLE_URGENCY_THRESHOLD
local NORMAL_OBSTACLE_STEER_MULTIPLIER = BoatAgentTypes.NORMAL_OBSTACLE_STEER_MULTIPLIER

local ActiveAgents: {[Model]: BoatAgentTypes.AgentData} = {}

local function ChooseNewTarget(Agent: BoatAgentTypes.AgentData)
	local BoatPosition = Agent.PrimaryPart.Position
	local RandomGenerator = Agent.RandomGenerator

	local Angle = RandomGenerator:NextNumber(0, math.pi * 2)
	local Radius = RandomGenerator:NextNumber(Agent.Config.MinTargetDistance, Agent.Config.WanderRadius)

	local OffsetX = math.cos(Angle) * Radius
	local OffsetZ = math.sin(Angle) * Radius

	Agent.State.TargetX = BoatPosition.X + OffsetX
	Agent.State.TargetZ = BoatPosition.Z + OffsetZ
end

local function UpdateVelocityEstimate(Agent: BoatAgentTypes.AgentData, DeltaTime: number)
	if DeltaTime < NEAR_ZERO_THRESHOLD then
		return
	end

	local CurrentPosition = Agent.PrimaryPart.Position
	local DeltaX = CurrentPosition.X - Agent.State.LastPositionX
	local DeltaZ = CurrentPosition.Z - Agent.State.LastPositionZ

	local NewVelocityX = DeltaX / DeltaTime
	local NewVelocityZ = DeltaZ / DeltaTime

	Agent.State.EstimatedVelocityX = Agent.State.EstimatedVelocityX * (1 - VELOCITY_SMOOTHING_FACTOR) + NewVelocityX * VELOCITY_SMOOTHING_FACTOR
	Agent.State.EstimatedVelocityZ = Agent.State.EstimatedVelocityZ * (1 - VELOCITY_SMOOTHING_FACTOR) + NewVelocityZ * VELOCITY_SMOOTHING_FACTOR
	Agent.State.EstimatedSpeed = math.sqrt(
		Agent.State.EstimatedVelocityX * Agent.State.EstimatedVelocityX +
		Agent.State.EstimatedVelocityZ * Agent.State.EstimatedVelocityZ
	)

	Agent.State.LastPositionX = CurrentPosition.X
	Agent.State.LastPositionZ = CurrentPosition.Z
end

local function ComputeWaypointVector(Agent: BoatAgentTypes.AgentData): (Vector3, number)
	local BoatPosition = Agent.PrimaryPart.Position
	local DeltaX = Agent.State.TargetX - BoatPosition.X
	local DeltaZ = Agent.State.TargetZ - BoatPosition.Z
	local Distance = math.sqrt(DeltaX * DeltaX + DeltaZ * DeltaZ)

	if Distance < NEAR_ZERO_THRESHOLD then
		return Vector3.zero, 0
	end

	local Direction = Vector3.new(DeltaX / Distance, 0, DeltaZ / Distance)

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawWaypoint(BoatPosition, Agent.State.TargetX, Agent.State.TargetZ)
	end

	return Direction, Distance
end

local function UpdateAgent(Agent: BoatAgentTypes.AgentData, DeltaTime: number)
	if Agent.Seat and Agent.Seat.Occupant ~= nil then
		Agent.BoatModel:SetAttribute("AiEnabled", false)
		BoatAgentUtils.WriteControls(Agent.BoatModel, 0, 0)
		return
	end

	Agent.BoatModel:SetAttribute("AiEnabled", true)
	UpdateVelocityEstimate(Agent, DeltaTime)

	local WaypointVector, TargetDistance = ComputeWaypointVector(Agent)

	if TargetDistance <= Agent.Config.StopRadius then
		ChooseNewTarget(Agent)
		BoatAgentUtils.WriteControls(Agent.BoatModel, 0, 0)
		return
	end

	local ObstacleVector, ObstacleUrgency = BoatAgentObstacle.ComputeAvoidanceVector(Agent)
	local ObstacleMagnitude = ObstacleVector.Magnitude

	local SeparationVector = BoatAgentFlocking.ComputeSeparationVector(Agent, ActiveAgents)
	local SeparationMagnitude = SeparationVector.Magnitude

	local AlignmentVector = Vector3.zero

	local Forward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawForward(Agent.PrimaryPart.Position, Forward)
	end

	local DesiredDirection: Vector3
	local Throttle = 1
	local SteerUrgency = 1.0

	if ObstacleUrgency > CRITICAL_OBSTACLE_THRESHOLD then
		local BaseDirection: Vector3
		if ObstacleMagnitude > NEAR_ZERO_THRESHOLD then
			BaseDirection = ObstacleVector / ObstacleMagnitude
		else
			local RightVector = BoatAgentUtils.GetHorizontalRightVector(Agent.PrimaryPart)
			BaseDirection = (Forward + RightVector * OBSTACLE_ESCAPE_RIGHT_BLEND).Unit
		end

		if SeparationMagnitude > NEAR_ZERO_THRESHOLD then
			local SeparationDirection = SeparationVector / SeparationMagnitude
			local SeparationDotObstacle = SeparationDirection:Dot(BaseDirection)

			if SeparationDotObstacle > SEPARATION_OBSTACLE_CONFLICT_THRESHOLD then
				local SeparationBlend = math.clamp(SeparationMagnitude * 0.2, 0, SEPARATION_OBSTACLE_CONFLICT_REDUCTION)
				DesiredDirection = (BaseDirection * (1 - SeparationBlend) + SeparationDirection * SeparationBlend).Unit
			else
				DesiredDirection = BaseDirection
			end
		else
			DesiredDirection = BaseDirection
		end

		SteerUrgency = 1.0 + ObstacleUrgency * OBSTACLE_STEER_URGENCY_MULTIPLIER
		Throttle = math.max(OBSTACLE_MIN_THROTTLE, 1 - ObstacleUrgency * ObstacleUrgency * OBSTACLE_THROTTLE_REDUCTION)

		if Agent.State.EstimatedSpeed < STUCK_SPEED_THRESHOLD and ObstacleUrgency > STUCK_OBSTACLE_THRESHOLD then
			SteerUrgency = SteerUrgency + STUCK_STEER_URGENCY_BOOST
			Throttle = math.max(STUCK_MIN_THROTTLE, Throttle)
		end

	else
		local ObstacleBoost = 1.0 + ObstacleUrgency * NORMAL_OBSTACLE_BOOST_MULTIPLIER
		local SeparationBoost = 1.0 + SeparationMagnitude * 0.5

		local WeightedObstacle = ObstacleVector * Agent.Config.ObstacleWeight * ObstacleBoost
		local WeightedSeparation = SeparationVector * Agent.Config.SeparationWeight * SeparationBoost
		local WeightedAlignment = AlignmentVector * Agent.Config.AlignmentWeight
		local WeightedWaypoint = WaypointVector * Agent.Config.WaypointWeight

		if ObstacleMagnitude > NEAR_ZERO_THRESHOLD and SeparationMagnitude > NEAR_ZERO_THRESHOLD then
			local ObstacleDir = ObstacleVector / ObstacleMagnitude
			local SeparationDir = SeparationVector / SeparationMagnitude
			if ObstacleDir:Dot(SeparationDir) < -0.5 then
				WeightedSeparation = WeightedSeparation * 0.3
			end
		end

		local Combined = WeightedObstacle + WeightedSeparation + WeightedAlignment + WeightedWaypoint
		local CombinedMagnitude = Combined.Magnitude

		if CombinedMagnitude > NEAR_ZERO_THRESHOLD then
			DesiredDirection = Combined / CombinedMagnitude
		else
			DesiredDirection = WaypointVector
		end

		if ObstacleUrgency > NORMAL_OBSTACLE_URGENCY_THRESHOLD then
			SteerUrgency = 1.0 + ObstacleUrgency * NORMAL_OBSTACLE_STEER_MULTIPLIER
		end

		if SeparationMagnitude > SEPARATION_MAGNITUDE_THRESHOLD then
			SteerUrgency = math.max(SteerUrgency, 1.0 + (SeparationMagnitude - SEPARATION_MAGNITUDE_THRESHOLD) * SEPARATION_STEER_URGENCY_MULTIPLIER)
			local SeparationThrottleEffect = (SeparationMagnitude - SEPARATION_MAGNITUDE_THRESHOLD) * SEPARATION_THROTTLE_REDUCTION
			Throttle = math.max(SEPARATION_MIN_THROTTLE, 1 - SeparationThrottleEffect * SeparationThrottleEffect)
		end
	end

	Agent.State.CommitmentTimer = math.max(0, Agent.State.CommitmentTimer - DeltaTime)

	local MaxUrgency = math.max(ObstacleUrgency, SeparationMagnitude * 0.5)

	if MaxUrgency > DIRECTION_COMMITMENT_URGENCY_THRESHOLD then
		if Agent.State.CommitmentTimer <= 0 then
			Agent.State.CommittedDirectionX = DesiredDirection.X
			Agent.State.CommittedDirectionZ = DesiredDirection.Z
			Agent.State.CommitmentTimer = DIRECTION_COMMITMENT_DURATION
		else
			DesiredDirection = Vector3.new(Agent.State.CommittedDirectionX, 0, Agent.State.CommittedDirectionZ)
		end
	end

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawDesiredDirection(Agent.PrimaryPart.Position, DesiredDirection)
	end

	local RawSteer = BoatAgentUtils.ComputeSteerToward(Forward, DesiredDirection, SteerUrgency)

	local AdaptiveSmoothing = STEER_SMOOTHING_FACTOR
	if ObstacleUrgency > CRITICAL_OBSTACLE_THRESHOLD then
		AdaptiveSmoothing = math.min(0.5, STEER_SMOOTHING_FACTOR + ObstacleUrgency * 0.4)
	end

	Agent.State.SmoothedSteer = Agent.State.SmoothedSteer + (RawSteer - Agent.State.SmoothedSteer) * AdaptiveSmoothing

	BoatAgentUtils.WriteControls(Agent.BoatModel, Throttle, Agent.State.SmoothedSteer)
end

local function AddAgent(BoatModel: Model)
	if ActiveAgents[BoatModel] then
		return
	end

	local PrimaryPart = BoatModel.PrimaryPart
	if not PrimaryPart then
		warn("[BoatAgentServer] Boat has no PrimaryPart:", BoatModel:GetFullName())
		return
	end

	local Config: BoatAgentTypes.AgentConfig = {
		StopRadius = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiStopRadius", BoatAgentTypes.DEFAULT_STOP_RADIUS),
		WanderRadius = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiWanderRadius", BoatAgentTypes.DEFAULT_WANDER_RADIUS),
		MinTargetDistance = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiMinTargetDistance", BoatAgentTypes.DEFAULT_MIN_TARGET_DISTANCE),
		SeparationWeight = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiSeparationWeight", BoatAgentTypes.DEFAULT_SEPARATION_WEIGHT),
		AlignmentWeight = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiAlignmentWeight", BoatAgentTypes.DEFAULT_ALIGNMENT_WEIGHT),
		WaypointWeight = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiWaypointWeight", BoatAgentTypes.DEFAULT_WAYPOINT_WEIGHT),
		ObstacleWeight = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiObstacleWeight", BoatAgentTypes.DEFAULT_OBSTACLE_WEIGHT),
		LookaheadTime = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiLookaheadTime", BoatAgentTypes.DEFAULT_LOOKAHEAD_TIME),
		MinSeparationDistance = BoatAgentUtils.GetNumberAttribute(BoatModel, "AiMinSeparationDistance", BoatAgentTypes.DEFAULT_MIN_SEPARATION_DISTANCE),
	}

	local BoundingRadius, BoundingLength = BoatAgentUtils.ComputeBoatDimensions(BoatModel)

	local Geometry: BoatAgentTypes.AgentGeometry = {
		BoundingRadius = BoundingRadius,
		BoundingLength = BoundingLength,
		RaycastHeight = BoatAgentTypes.RAYCAST_HEIGHT_OFFSET,
		RaycastDistance = BoatAgentTypes.RAYCAST_BASE_DISTANCE + BoundingLength * BoatAgentTypes.RAYCAST_SIZE_MULTIPLIER,
	}

	local Position = PrimaryPart.Position

	local State: BoatAgentTypes.AgentState = {
		TargetX = Position.X,
		TargetZ = Position.Z,
		LastPositionX = Position.X,
		LastPositionZ = Position.Z,
		EstimatedVelocityX = 0,
		EstimatedVelocityZ = 0,
		EstimatedSpeed = 0,
		LastTerrainCheckTime = 0,
		CachedObstacleVector = Vector3.zero,
		CachedObstacleUrgency = 0,
		SmoothedSteer = 0,
		CommittedDirectionX = 0,
		CommittedDirectionZ = 0,
		CommitmentTimer = 0,
	}

	local PositionHash = math.floor(Position.X * 100) + math.floor(Position.Z * 100) * 10000
	local Seed = BoatAgentUtils.HashStringToSeed(BoatModel:GetFullName()) + PositionHash

	local Agent: BoatAgentTypes.AgentData = {
		BoatModel = BoatModel,
		PrimaryPart = PrimaryPart,
		Seat = BoatAgentUtils.FindVehicleSeat(BoatModel),
		Config = Config,
		State = State,
		Geometry = Geometry,
		RandomGenerator = Random.new(Seed),
	}

	ChooseNewTarget(Agent)

	BoatModel:SetAttribute("AiEnabled", true)
	BoatAgentUtils.WriteControls(BoatModel, 0, 0)

	ActiveAgents[BoatModel] = Agent
	BoatAgentObstacle.UpdateRaycastFilter(ActiveAgents)
end

local function RemoveAgent(BoatModel: Model)
	local Agent = ActiveAgents[BoatModel]
	if not Agent then
		return
	end

	BoatModel:SetAttribute("AiEnabled", false)
	BoatAgentUtils.WriteControls(Agent.BoatModel, 0, 0)

	ActiveAgents[BoatModel] = nil
	BoatAgentObstacle.UpdateRaycastFilter(ActiveAgents)
end

for _, Instance in CollectionService:GetTagged(AGENT_TAG) do
	if Instance:IsA("Model") then
		AddAgent(Instance)
	end
end

CollectionService:GetInstanceAddedSignal(AGENT_TAG):Connect(function(Instance)
	if Instance:IsA("Model") then
		AddAgent(Instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(AGENT_TAG):Connect(function(Instance)
	if Instance:IsA("Model") then
		RemoveAgent(Instance)
	end
end)

CollectionService:GetInstanceAddedSignal(BOAT_TAG):Connect(function(_)
	BoatAgentObstacle.UpdateRaycastFilter(ActiveAgents)
end)

CollectionService:GetInstanceRemovedSignal(BOAT_TAG):Connect(function(_)
	BoatAgentObstacle.UpdateRaycastFilter(ActiveAgents)
end)

local LastHeartbeatTime = os.clock()

RunService.Heartbeat:Connect(function()
	local CurrentTime = os.clock()
	local DeltaTime = CurrentTime - LastHeartbeatTime
	LastHeartbeatTime = CurrentTime

	for _, Agent in pairs(ActiveAgents) do
		UpdateAgent(Agent, DeltaTime)
	end
end)