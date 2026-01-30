--!strict

local BehaviorTypes = require(script.Parent:WaitForChild("BehaviorTypes"))

local BehaviorWander = {}

local WANDER_RADIUS = BehaviorTypes.WANDER_RADIUS
local WANDER_MIN_DISTANCE = BehaviorTypes.WANDER_MIN_DISTANCE

export type WanderConfig = {
	WanderRadius: number?,
	MinTargetDistance: number?,
}

function BehaviorWander.Initialize(Agent: any, Config: WanderConfig?)
	local State = Agent.State.BehaviorState
	State.Name = "Wander"
	State.CurrentWaypointIndex = 0
	State.RouteData = nil

	local WanderRadius = WANDER_RADIUS
	local MinDistance = WANDER_MIN_DISTANCE

	if Config then
		WanderRadius = Config.WanderRadius or WanderRadius
		MinDistance = Config.MinTargetDistance or MinDistance
	end

	local BoatModel = Agent.BoatModel
	WanderRadius = BoatModel:GetAttribute("AiWanderRadius") or WanderRadius
	MinDistance = BoatModel:GetAttribute("AiMinTargetDistance") or MinDistance

	Agent.Config.WanderRadius = WanderRadius
	Agent.Config.MinTargetDistance = MinDistance

	BehaviorWander.ChooseNewTarget(Agent)
end

function BehaviorWander.ChooseNewTarget(Agent: any)
	local BoatPosition = Agent.PrimaryPart.Position
	local RandomGenerator = Agent.RandomGenerator

	local Angle = RandomGenerator:NextNumber(0, math.pi * 2)
	local Radius = RandomGenerator:NextNumber(Agent.Config.MinTargetDistance, Agent.Config.WanderRadius)

	local OffsetX = math.cos(Angle) * Radius
	local OffsetZ = math.sin(Angle) * Radius

	Agent.State.TargetX = BoatPosition.X + OffsetX
	Agent.State.TargetZ = BoatPosition.Z + OffsetZ
end

function BehaviorWander.Update(Agent: any, _DeltaTime: number): BehaviorTypes.BehaviorOutput
	local BoatPosition = Agent.PrimaryPart.Position
	local DeltaX = Agent.State.TargetX - BoatPosition.X
	local DeltaZ = Agent.State.TargetZ - BoatPosition.Z
	local Distance = math.sqrt(DeltaX * DeltaX + DeltaZ * DeltaZ)

	if Distance <= Agent.Config.StopRadius then
		BehaviorWander.ChooseNewTarget(Agent)
	end

	return {
		TargetX = Agent.State.TargetX,
		TargetZ = Agent.State.TargetZ,
		ThrottleOverride = nil,
		SteerOverride = nil,
		ShouldStop = false,
		ObstacleAvoidanceMultiplier = 1.0,
		DockingTarget = nil,
		Priority = 1,
	}
end

return BehaviorWander