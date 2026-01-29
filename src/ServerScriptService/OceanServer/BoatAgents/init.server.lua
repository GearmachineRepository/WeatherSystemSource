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
	if DeltaTime < 0.001 then
		return
	end

	local CurrentPosition = Agent.PrimaryPart.Position
	local DeltaX = CurrentPosition.X - Agent.State.LastPositionX
	local DeltaZ = CurrentPosition.Z - Agent.State.LastPositionZ

	local NewVelocityX = DeltaX / DeltaTime
	local NewVelocityZ = DeltaZ / DeltaTime

	local SmoothingFactor = 0.3
	Agent.State.EstimatedVelocityX = Agent.State.EstimatedVelocityX * (1 - SmoothingFactor) + NewVelocityX * SmoothingFactor
	Agent.State.EstimatedVelocityZ = Agent.State.EstimatedVelocityZ * (1 - SmoothingFactor) + NewVelocityZ * SmoothingFactor
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

	if Distance < 0.001 then
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

	local AlignmentVector = BoatAgentFlocking.ComputeAlignmentVector(Agent, ActiveAgents)

	local Forward = BoatAgentUtils.GetHorizontalLookVector(Agent.PrimaryPart)

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawForward(Agent.PrimaryPart.Position, Forward)
	end

	local DesiredDirection: Vector3
	local Throttle = 1
	local SteerUrgency = 1.0

	local CriticalObstacleThreshold = 0.2

	if ObstacleUrgency > CriticalObstacleThreshold then
		if ObstacleMagnitude > 0.001 then
			DesiredDirection = ObstacleVector / ObstacleMagnitude
		else
			local RightVector = BoatAgentUtils.GetHorizontalRightVector(Agent.PrimaryPart)
			DesiredDirection = (Forward + RightVector * 0.5).Unit
		end

		SteerUrgency = 1.0 + ObstacleUrgency * 3.0
		Throttle = math.max(0.5, 1 - ObstacleUrgency * 0.4)

		if Agent.State.EstimatedSpeed < 1.0 and ObstacleUrgency > 0.3 then
			SteerUrgency = SteerUrgency + 2.0
			Throttle = math.max(0.6, Throttle)
		end

	elseif SeparationMagnitude > 1.5 then
		local NormalizedSeparation = SeparationVector / SeparationMagnitude
		local DotForward = Forward:Dot(NormalizedSeparation)

		if DotForward < -0.2 then
			local RightX = -Forward.Z
			local RightZ = Forward.X
			local DotRight = NormalizedSeparation.X * RightX + NormalizedSeparation.Z * RightZ
			if DotRight >= 0 then
				DesiredDirection = Vector3.new(RightX, 0, RightZ)
			else
				DesiredDirection = Vector3.new(-RightX, 0, -RightZ)
			end
		else
			DesiredDirection = NormalizedSeparation
		end

		SteerUrgency = 1.0 + (SeparationMagnitude - 1.5) * 0.5
		Throttle = math.max(0.6, 1 - (SeparationMagnitude - 1.5) * 0.1)

	else
		local ObstacleBoost = 1.0 + ObstacleUrgency * 4.0
		local WeightedObstacle = ObstacleVector * Agent.Config.ObstacleWeight * ObstacleBoost
		local WeightedSeparation = SeparationVector * Agent.Config.SeparationWeight
		local WeightedAlignment = AlignmentVector * Agent.Config.AlignmentWeight
		local WeightedWaypoint = WaypointVector * Agent.Config.WaypointWeight

		local Combined = WeightedObstacle + WeightedSeparation + WeightedAlignment + WeightedWaypoint
		local CombinedMagnitude = Combined.Magnitude

		if CombinedMagnitude > 0.001 then
			DesiredDirection = Combined / CombinedMagnitude
		else
			DesiredDirection = WaypointVector
		end

		if ObstacleUrgency > 0.1 then
			SteerUrgency = 1.0 + ObstacleUrgency * 1.5
		end
	end

	if DEBUG_ENABLED then
		BoatAgentDebug.DrawDesiredDirection(Agent.PrimaryPart.Position, DesiredDirection)
	end

	local Steer = BoatAgentUtils.ComputeSteerToward(Forward, DesiredDirection, SteerUrgency)

	BoatAgentUtils.WriteControls(Agent.BoatModel, Throttle, Steer)
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