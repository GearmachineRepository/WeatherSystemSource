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
	SmoothedSteer: number,
	CommittedDirectionX: number,
	CommittedDirectionZ: number,
	CommitmentTimer: number,
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
BoatAgentTypes.DEFAULT_SEPARATION_WEIGHT = 2.5
BoatAgentTypes.DEFAULT_ALIGNMENT_WEIGHT = 0.2
BoatAgentTypes.DEFAULT_WAYPOINT_WEIGHT = 1.0
BoatAgentTypes.DEFAULT_OBSTACLE_WEIGHT = 4.0
BoatAgentTypes.DEFAULT_LOOKAHEAD_TIME = 5.0
BoatAgentTypes.DEFAULT_MIN_SEPARATION_DISTANCE = 40

BoatAgentTypes.WHISKER_COUNT = 11
BoatAgentTypes.WHISKER_SPREAD_ANGLE = math.rad(120)
BoatAgentTypes.RAYCAST_BASE_DISTANCE = 45
BoatAgentTypes.RAYCAST_SIZE_MULTIPLIER = 2.5
BoatAgentTypes.RAYCAST_HEIGHT_OFFSET = 4
BoatAgentTypes.TERRAIN_CHECK_INTERVAL = 0.06

BoatAgentTypes.DEBUG_ENABLED = false

BoatAgentTypes.NEAR_ZERO_THRESHOLD = 0.001
BoatAgentTypes.VELOCITY_SMOOTHING_FACTOR = 0.3
BoatAgentTypes.STEER_SMOOTHING_FACTOR = 0.12

BoatAgentTypes.CRITICAL_OBSTACLE_THRESHOLD = 0.15
BoatAgentTypes.OBSTACLE_STEER_URGENCY_MULTIPLIER = 4.0
BoatAgentTypes.OBSTACLE_THROTTLE_REDUCTION = 0.5
BoatAgentTypes.OBSTACLE_MIN_THROTTLE = 0.6
BoatAgentTypes.OBSTACLE_ESCAPE_RIGHT_BLEND = 0.5

BoatAgentTypes.STUCK_SPEED_THRESHOLD = 1.0
BoatAgentTypes.STUCK_OBSTACLE_THRESHOLD = 0.3
BoatAgentTypes.STUCK_STEER_URGENCY_BOOST = 2.0
BoatAgentTypes.STUCK_MIN_THROTTLE = 0.6

BoatAgentTypes.SEPARATION_MAGNITUDE_THRESHOLD = 1.0
BoatAgentTypes.SEPARATION_BEHIND_DOT_THRESHOLD = -0.2
BoatAgentTypes.SEPARATION_STEER_URGENCY_MULTIPLIER = 0.5
BoatAgentTypes.SEPARATION_THROTTLE_REDUCTION = 0.15
BoatAgentTypes.SEPARATION_MIN_THROTTLE = 0.8

BoatAgentTypes.SEPARATION_OBSTACLE_CONFLICT_THRESHOLD = -0.3
BoatAgentTypes.SEPARATION_OBSTACLE_CONFLICT_REDUCTION = 0.3

BoatAgentTypes.DIRECTION_COMMITMENT_DURATION = 0.4
BoatAgentTypes.DIRECTION_COMMITMENT_URGENCY_THRESHOLD = 0.3

BoatAgentTypes.NORMAL_OBSTACLE_BOOST_MULTIPLIER = 4.0
BoatAgentTypes.NORMAL_OBSTACLE_URGENCY_THRESHOLD = 0.1
BoatAgentTypes.NORMAL_OBSTACLE_STEER_MULTIPLIER = 1.5

BoatAgentTypes.WHISKER_SPEED_DISTANCE_MULTIPLIER = 1.5
BoatAgentTypes.WHISKER_CENTER_WEIGHT_REDUCTION = 0.4
BoatAgentTypes.WHISKER_CLOSE_HIT_DISTANCE = 15
BoatAgentTypes.WHISKER_CLOSE_HIT_BOOST = 0.5
BoatAgentTypes.WHISKER_CENTER_IMPORTANCE = 0.8
BoatAgentTypes.WHISKER_FORWARD_BIAS_EXPONENT = 1.5
BoatAgentTypes.WHISKER_SCORE_FORWARD_WEIGHT = 0.7
BoatAgentTypes.WHISKER_SCORE_BASE_WEIGHT = 0.3

BoatAgentTypes.BLOCKED_SCORE_MIN_THRESHOLD = 0.05
BoatAgentTypes.BLOCKED_SCORE_HIGH_THRESHOLD = 0.7
BoatAgentTypes.BLOCKED_BLEND_ALPHA_OFFSET = 0.5
BoatAgentTypes.BLOCKED_BLEND_ALPHA_MULTIPLIER = 2

BoatAgentTypes.CAN_SEE_DISTANCE_TOLERANCE = 5

BoatAgentTypes.FLOCKING_RAY_HEIGHT_OFFSET = 3
BoatAgentTypes.FLOCKING_DETECTION_RANGE_MULTIPLIER = 3
BoatAgentTypes.FLOCKING_MAX_FUTURE_TIME = 5.0
BoatAgentTypes.FLOCKING_MIN_THREAT_DISTANCE = 1
BoatAgentTypes.FLOCKING_CLOSE_THREAT_MULTIPLIER = 5
BoatAgentTypes.FLOCKING_IN_FRONT_MULTIPLIER = 2.0
BoatAgentTypes.FLOCKING_CONVERGING_MULTIPLIER = 2.0
BoatAgentTypes.FLOCKING_HEAD_ON_MULTIPLIER = 2.0
BoatAgentTypes.FLOCKING_HEAD_ON_DOT_THRESHOLD = 0.5

BoatAgentTypes.STEER_BEHIND_DOT_THRESHOLD = -0.2
BoatAgentTypes.STEER_URGENCY_THRESHOLD = 1.5
BoatAgentTypes.STEER_MAX_URGENCY_BOOST = 3.0

BoatAgentTypes.STEER_URGENT_FULL_ANGLE = 15
BoatAgentTypes.STEER_URGENT_MID_ANGLE = 5
BoatAgentTypes.STEER_URGENT_FULL_AMOUNT = 1.0
BoatAgentTypes.STEER_URGENT_MID_AMOUNT = 0.6
BoatAgentTypes.STEER_URGENT_MIN_AMOUNT = 0.4

BoatAgentTypes.STEER_NORMAL_FULL_ANGLE = 25
BoatAgentTypes.STEER_NORMAL_MID_ANGLE = 10
BoatAgentTypes.STEER_NORMAL_FULL_AMOUNT = 1.0
BoatAgentTypes.STEER_NORMAL_MID_AMOUNT = 0.5

return BoatAgentTypes