--!strict

local BoatAgentTypes = {}

export type AgentConfig = {
	StopRadius: number,
	WanderRadius: number,
	MinTargetDistance: number,
	SeparationWeight: number,
	AlignmentWeight: number,
	WaypointWeight: number,
	ObstacleWeight: number,
	LookaheadTime: number,
	MinSeparationDistance: number,
}

export type AgentState = {
	TargetX: number,
	TargetZ: number,
	LastPositionX: number,
	LastPositionZ: number,
	EstimatedVelocityX: number,
	EstimatedVelocityZ: number,
	EstimatedSpeed: number,
	LastTerrainCheckTime: number,
	CachedObstacleVector: Vector3,
	CachedObstacleUrgency: number,
}

export type AgentGeometry = {
	BoundingRadius: number,
	BoundingLength: number,
	RaycastHeight: number,
	RaycastDistance: number,
}

export type AgentData = {
	BoatModel: Model,
	PrimaryPart: BasePart,
	Seat: VehicleSeat?,
	Config: AgentConfig,
	State: AgentState,
	Geometry: AgentGeometry,
	RandomGenerator: Random,
}

BoatAgentTypes.AGENT_TAG = "Agent"
BoatAgentTypes.BOAT_TAG = "Boat"

BoatAgentTypes.DEFAULT_STOP_RADIUS = 25
BoatAgentTypes.DEFAULT_WANDER_RADIUS = 400
BoatAgentTypes.DEFAULT_MIN_TARGET_DISTANCE = 80
BoatAgentTypes.DEFAULT_SEPARATION_WEIGHT = 2.0
BoatAgentTypes.DEFAULT_ALIGNMENT_WEIGHT = 0.2
BoatAgentTypes.DEFAULT_WAYPOINT_WEIGHT = 1.0
BoatAgentTypes.DEFAULT_OBSTACLE_WEIGHT = 4.0
BoatAgentTypes.DEFAULT_LOOKAHEAD_TIME = 4.0
BoatAgentTypes.DEFAULT_MIN_SEPARATION_DISTANCE = 40

BoatAgentTypes.WHISKER_COUNT = 11
BoatAgentTypes.WHISKER_SPREAD_ANGLE = math.rad(120)
BoatAgentTypes.RAYCAST_BASE_DISTANCE = 30
BoatAgentTypes.RAYCAST_SIZE_MULTIPLIER = 2.5
BoatAgentTypes.RAYCAST_HEIGHT_OFFSET = 4
BoatAgentTypes.TERRAIN_CHECK_INTERVAL = 0.06

BoatAgentTypes.DEBUG_ENABLED = true

return BoatAgentTypes