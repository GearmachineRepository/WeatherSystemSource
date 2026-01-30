--!strict

local BehaviorTypes = {}

export type BehaviorName = "Wander" | "Patrol" | "Ferry" | "Attack" | "Idle"

export type DockState = "APPROACHING" | "ALIGNING" | "DOCKING" | "DOCKED" | "UNDOCKING"

export type AttackState = "PURSUING" | "CIRCLING"

export type FerryState = "TRAVELING" | "APPROACHING_DOCK" | "DOCKING" | "WAITING" | "DEPARTING" | "UNDOCKING"

export type BehaviorOutput = {
	TargetX: number,
	TargetZ: number,
	ThrottleOverride: number?,
	SteerOverride: number?,
	ShouldStop: boolean?,
	ObstacleAvoidanceMultiplier: number?,
	WaypointBias: number?,
	DockingTarget: BasePart?,
	Priority: number?,
}

export type WaypointData = {
	Position: Vector3,
	WaitTime: number?,
	IsEndpoint: boolean?,
	DepartureDelay: number?,
	DockPoint: BasePart?,
}

export type RouteData = {
	Name: string,
	Waypoints: {WaypointData},
	Loop: boolean,
}

export type DockingState = {
	Active: boolean,
	State: DockState?,
	DockPoint: BasePart?,
	ApproachDistance: number,
	FinalPosition: Vector3?,
	StartTime: number,
}

export type AttackTargetData = {
	Target: Model?,
	TargetPart: BasePart?,
	LastTargetPosition: Vector3?,
	LastTargetVelocity: Vector3?,
	TargetStationaryTime: number,
	CircleAngle: number,
	CircleDirection: number,
}

export type FerryPassengerData = {
	WaitStartTime: number,
	DepartureTime: number?,
	PassengerCount: number,
	AnnouncedDeparture: boolean,
}

export type BehaviorState = {
	Name: BehaviorName,
	RouteData: RouteData?,
	CurrentWaypointIndex: number,
	RouteDirection: number,
	DockingState: DockingState,
	AttackData: AttackTargetData?,
	FerryData: FerryPassengerData?,
	FerryState: FerryState?,
	AttackState: AttackState?,
}

BehaviorTypes.DEFAULT_APPROACH_DISTANCE = 100
BehaviorTypes.DOCK_BUFFER = 5
BehaviorTypes.DOCK_ALIGNMENT_THRESHOLD = 10
BehaviorTypes.DOCK_ARRIVAL_THRESHOLD = 12
BehaviorTypes.DOCK_ALIGN_THROTTLE = 0.25
BehaviorTypes.DOCK_APPROACH_THROTTLE = 0.2
BehaviorTypes.DOCK_UNDOCK_THROTTLE = 0.3
BehaviorTypes.DOCK_STEER_CORRECTION_GAIN = 1.5
BehaviorTypes.DOCK_MAX_STEER_CORRECTION = 0.4
BehaviorTypes.DOCK_FINAL_APPROACH_DISTANCE = 25
BehaviorTypes.DOCK_FINAL_APPROACH_THROTTLE = 0.12

BehaviorTypes.ATTACK_CIRCLE_RADIUS = 60
BehaviorTypes.ATTACK_CIRCLE_THROTTLE = 0.7
BehaviorTypes.ATTACK_PURSUIT_THROTTLE = 1.0
BehaviorTypes.ATTACK_TARGET_STATIONARY_SPEED = 2
BehaviorTypes.ATTACK_TARGET_STATIONARY_TIME = 1.5
BehaviorTypes.ATTACK_CIRCLE_ANGULAR_SPEED = 0.3
BehaviorTypes.ATTACK_DETECTION_RANGE = 200
BehaviorTypes.ATTACK_LOSE_TARGET_RANGE = 300

BehaviorTypes.FERRY_DEFAULT_WAIT_TIME = 30
BehaviorTypes.FERRY_DEPARTURE_DELAY = 10
BehaviorTypes.FERRY_MIN_PASSENGERS_TO_DEPART = 0

BehaviorTypes.PATROL_WAYPOINT_ARRIVAL_RADIUS = 20

BehaviorTypes.WANDER_RADIUS = 400
BehaviorTypes.WANDER_MIN_DISTANCE = 80

return BehaviorTypes